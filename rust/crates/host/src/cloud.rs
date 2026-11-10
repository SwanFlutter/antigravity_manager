//! The cloud side of the host: connected Google accounts and the local proxy.
//!
//! This module owns the rules that need both the profile on disk and the
//! upstream service: the OAuth session, the quota refresh and the account a
//! proxy request is charged to.

use std::sync::Arc;
use std::time::{Duration, SystemTime, UNIX_EPOCH};

use antigravity_core::cloud::{
    format_reset_label, AccountCredentials, AccountLease, ConnectStatus, LeaseProvider,
    ProxyConfig, QuotaGroup, TrafficEntry,
};
use antigravity_core::domain::{Account, WeeklyQuota};
use antigravity_core::repository::{AccountService, CloudRepository, RepositoryError};
use antigravity_google::{GoogleClient, OAuthClient};
use antigravity_proxy::{ModelCatalog, ProxyState, TrafficRecorder};
use futures::future::BoxFuture;

use crate::oauth::{OAuthCallback, SessionStore};

/// The current time in milliseconds since the Unix epoch.
pub fn now_millis() -> i64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|value| value.as_millis() as i64)
        .unwrap_or(0)
}

/// Opens a URL in the browser of the system.
pub fn open_browser(url: &str) {
    #[cfg(windows)]
    {
        let _ = std::process::Command::new("cmd")
            .args(["/C", "start", "", url])
            .spawn();
    }

    #[cfg(not(windows))]
    {
        let _ = url;
    }
}

/// The cloud service of the host.
pub struct CloudService {
    pub accounts: Arc<AccountService>,
    pub cloud: Arc<dyn CloudRepository>,
    pub google: Arc<GoogleClient>,
    pub sessions: Arc<SessionStore>,
    pub proxy: Arc<ProxyRuntime>,
    pub catalog: Arc<dyn ModelCatalog>,
    /// The live configuration of the local proxy.
    ///
    /// The running proxy holds this very lock, so a new key takes effect
    /// without restarting the proxy.
    pub config: Arc<tokio::sync::RwLock<ProxyConfig>>,
    /// Whether the browser of the system opens the authorization page.
    ///
    /// The tests turn this off: they must not open a window.
    pub launch_browser: bool,
}

/// The error of the cloud service.
#[derive(Debug, thiserror::Error)]
pub enum CloudError {
    #[error("the repository failed: {0}")]
    Repository(String),
    #[error("the provider failed: {0}")]
    Provider(String),
    #[error("the request is invalid: {0}")]
    Invalid(String),
    #[error("the session is unknown or already finished")]
    UnknownSession,
}

/// Starts an OAuth session and returns the URL the browser has to open.
pub async fn start_connect(
    service: Arc<CloudService>,
    session_id: String,
) -> Result<(String, String, i64), CloudError> {
    let state = uuid::Uuid::new_v4().simple().to_string();
    let (redirect_uri, receiver) = crate::oauth::start_callback_listener(state.clone())
        .await
        .map_err(|error| CloudError::Provider(format!("cannot listen for the callback: {error}")))?;

    let client = OAuthClient::builtin();
    let authorization_url = service.google.auth_url(&client, &redirect_uri, &state);

    // The browser of the system opens the authorization page, exactly like
    // the upstream application does.
    if service.launch_browser {
        let url = authorization_url.clone();
        tokio::task::spawn_blocking(move || open_browser(&url));
    }

    let expires_at = now_millis() + 5 * 60 * 1000;
    let (sender, _receiver) = tokio::sync::oneshot::channel();
    service.sessions.insert(
        session_id.clone(),
        redirect_uri.clone(),
        expires_at,
        sender,
    );

    let service = Arc::clone(&service);
    let session = session_id.clone();
    tokio::spawn(async move {
        let answer = match tokio::time::timeout(Duration::from_secs(300), receiver).await {
            Ok(Ok(callback)) => Some(callback),
            _ => None,
        };

        match answer {
            Some(OAuthCallback {
                code: Some(code),
                error: None,
                ..
            }) => {
                let _ = complete_connect(&service, &session, &code).await;
            }
            Some(OAuthCallback {
                error: Some(error),
                ..
            }) => {
                service.sessions.finish(&session, "failed", None, Some(error));
            }
            _ => {
                service.sessions.finish(&session, "expired", None, None);
            }
        }
    });

    Ok((authorization_url, redirect_uri, expires_at))
}

/// Finishes a session with a code the user copied by hand.
pub async fn submit_code(
    service: Arc<CloudService>,
    session_id: &str,
    code: &str,
) -> Result<(), CloudError> {
    if service.sessions.status(session_id).is_none() {
        return Err(CloudError::UnknownSession);
    }

    let service = Arc::clone(&service);
    let session = session_id.to_string();
    let code = code.to_string();

    tokio::spawn(async move {
        let _ = complete_connect(&service, &session, &code).await;
    });

    Ok(())
}

/// Exchanges the code, reads the identity and stores the account.
async fn complete_connect(
    service: &CloudService,
    session_id: &str,
    code: &str,
) -> Result<(), CloudError> {
    let client = OAuthClient::builtin();
    // The code can only be exchanged with the same redirect URI the browser
    // used, so the session keeps it.
    let redirect_uri = service
        .sessions
        .redirect_uri(session_id)
        .unwrap_or_default();

    let tokens = service
        .google
        .exchange_code(&client, code, &redirect_uri)
        .await
        .map_err(|error| CloudError::Provider(error.to_string()))?;

    let info = service
        .google
        .user_info(&tokens.access_token)
        .await
        .map_err(|error| CloudError::Provider(error.to_string()))?;

    let project = service
        .google
        .load_project(&tokens.access_token)
        .await
        .map_err(|error| CloudError::Provider(error.to_string()))?;

    let account_id = format!("google-{}", stable_id(&info.email));
    let credentials = AccountCredentials {
        account_id: account_id.clone(),
        access_token: tokens.access_token.clone(),
        refresh_token: tokens.refresh_token.clone(),
        expiry_timestamp: tokens.expiry_timestamp,
        email: info.email.clone(),
        project_id: project.project_id.clone(),
        plan: project.plan.clone(),
        credits: project.credits,
        oauth_client_key: Some(client.key.clone()),
    };

    service
        .cloud
        .save_credentials(&credentials)
        .map_err(|error| CloudError::Repository(error.to_string()))?;

    let account = upsert_account(service, &credentials).await?;
    let _ = refresh_quota(service, &account).await;

    service
        .sessions
        .finish(session_id, "completed", Some(info.email), None);

    Ok(())
}

/// Creates or updates the account that belongs to the credentials.
async fn upsert_account(
    service: &CloudService,
    credentials: &AccountCredentials,
) -> Result<Account, CloudError> {
    let existing = service
        .accounts
        .list_accounts()
        .map_err(|error| CloudError::Repository(error.to_string()))?
        .0
        .into_iter()
        .find(|account| account.id == credentials.account_id);

    let mut account = existing.unwrap_or(Account {
        id: credentials.account_id.clone(),
        name: credentials
            .email
            .split('@')
            .next()
            .unwrap_or("Google account")
            .to_string(),
        handle: credentials.email.clone(),
        provider: "Google".to_string(),
        plan: credentials.plan.clone().unwrap_or_else(|| "Google AI".to_string()),
        status: antigravity_core::domain::AccountStatus::Idle,
        credits: credentials.credits.unwrap_or(0),
        in_use: false,
        recommended: false,
        selected: false,
        // A connected account is a real account, never a sample.
        demo: false,
        quotas: Vec::new(),
        weekly_quotas: Vec::new(),
    });

    account.handle = credentials.email.clone();
    if let Some(plan) = &credentials.plan {
        account.plan = plan.clone();
    }
    if let Some(credits) = credentials.credits {
        account.credits = credits;
    }

    let repository = service.accounts.repository();
    repository
        .save_account(&account)
        .map_err(|error| CloudError::Repository(error.to_string()))?;

    Ok(account)
}

/// Refreshes the quota of one account from the provider.
pub async fn refresh_quota(
    service: &CloudService,
    account: &Account,
) -> Result<Account, CloudError> {
    let Some(mut credentials) = service
        .cloud
        .load_credentials(&account.id)
        .map_err(|error| CloudError::Repository(error.to_string()))?
    else {
        return Err(CloudError::Invalid(
            "the account is not connected".to_string(),
        ));
    };

    if credentials.needs_refresh(now_millis()) {
        credentials = refresh_credentials(service, credentials).await?;
    }

    let project = credentials.project_id.clone();
    let quotas = service
        .google
        .fetch_model_quotas(&credentials.access_token, project.as_deref())
        .await
        .map_err(|error| CloudError::Provider(error.to_string()))?;

    let groups = service
        .google
        .fetch_quota_groups(&credentials.access_token, project.as_deref())
        .await
        .unwrap_or_default();

    let mut updated = account.clone();
    updated.quotas = quotas;
    updated.weekly_quotas = weekly_quotas(&groups);

    let repository = service.accounts.repository();
    repository
        .save_account(&updated)
        .map_err(|error| CloudError::Repository(error.to_string()))?;

    Ok(updated)
}

/// Refreshes an expired access token.
async fn refresh_credentials(
    service: &CloudService,
    mut credentials: AccountCredentials,
) -> Result<AccountCredentials, CloudError> {
    let Some(refresh_token) = credentials.refresh_token.clone() else {
        return Err(CloudError::Invalid(
            "the account has to be connected again".to_string(),
        ));
    };

    let client = match credentials.oauth_client_key.as_deref() {
        Some("builtin") | None => OAuthClient::builtin(),
        Some(_) => OAuthClient::builtin(),
    };

    let tokens = service
        .google
        .refresh_access_token(&client, &refresh_token)
        .await
        .map_err(|error| CloudError::Provider(error.to_string()))?;

    credentials.access_token = tokens.access_token;
    if tokens.refresh_token.is_some() {
        credentials.refresh_token = tokens.refresh_token;
    }
    credentials.expiry_timestamp = tokens.expiry_timestamp;

    service
        .cloud
        .save_credentials(&credentials)
        .map_err(|error| CloudError::Repository(error.to_string()))?;

    Ok(credentials)
}

/// Builds the weekly quotas out of the quota groups of the provider.
fn weekly_quotas(groups: &[QuotaGroup]) -> Vec<WeeklyQuota> {
    groups
        .iter()
        .filter(|group| group.weekly_remaining().is_some())
        .map(|group| WeeklyQuota {
            group_id: group.id.clone(),
            group_label: group.label.clone(),
            remaining: group.weekly_remaining().unwrap_or(0.0),
            reset_label: format_reset_label(group.weekly_reset_at(), now_millis()),
        })
        .collect()
}

/// A stable id out of an email address.
fn stable_id(email: &str) -> String {
    let mut hash: u64 = 1469598103934665603;
    for byte in email.as_bytes() {
        hash ^= *byte as u64;
        hash = hash.wrapping_mul(1099511628211);
    }
    format!("{hash:016x}")
}

/// Hands out the account a proxy request is charged to.
pub struct HostLeaseProvider {
    pub accounts: Arc<AccountService>,
    pub cloud: Arc<dyn CloudRepository>,
    pub google: Arc<GoogleClient>,
}

impl LeaseProvider for HostLeaseProvider {
    fn lease(&self) -> BoxFuture<'_, Result<AccountLease, RepositoryError>> {
        Box::pin(async move {
            let config = self.cloud.load_proxy_config()?;

            let accounts = self.accounts.repository().list_accounts()?;
            let connected = self.cloud.list_credential_accounts()?;

            let chosen = config
                .selected_account_id
                .clone()
                .filter(|id| connected.contains(id))
                .or_else(|| {
                    accounts
                        .iter()
                        .find(|account| account.in_use && connected.contains(&account.id))
                        .map(|account| account.id.clone())
                })
                .or_else(|| connected.first().cloned());

            let Some(account_id) = chosen else {
                return Err(RepositoryError::NotFound(
                    "no Google account is connected".to_string(),
                ));
            };

            let Some(mut credentials) = self.cloud.load_credentials(&account_id)? else {
                return Err(RepositoryError::NotFound(account_id));
            };

            if credentials.needs_refresh(now_millis()) {
                let client = OAuthClient::builtin();
                let Some(refresh_token) = credentials.refresh_token.clone() else {
                    return Err(RepositoryError::Storage(
                        "the account has to be connected again".to_string(),
                    ));
                };
                let tokens = self
                    .google
                    .refresh_access_token(&client, &refresh_token)
                    .await
                    .map_err(|error| RepositoryError::Storage(error.to_string()))?;
                credentials.access_token = tokens.access_token;
                if tokens.refresh_token.is_some() {
                    credentials.refresh_token = tokens.refresh_token;
                }
                credentials.expiry_timestamp = tokens.expiry_timestamp;
                self.cloud.save_credentials(&credentials)?;
            }

            Ok(AccountLease {
                account_id: credentials.account_id,
                email: credentials.email,
                access_token: credentials.access_token,
                project_id: credentials.project_id,
            })
        })
    }
}

/// Writes the traffic log into the profile.
pub struct HostTrafficRecorder {
    pub cloud: Arc<dyn CloudRepository>,
}

impl TrafficRecorder for HostTrafficRecorder {
    fn record(&self, entry: TrafficEntry) -> i64 {
        self.cloud.record_traffic(&entry).unwrap_or(0)
    }
}

/// Serves the models of the connected accounts.
pub struct HostModelCatalog {
    pub accounts: Arc<AccountService>,
}

impl ModelCatalog for HostModelCatalog {
    fn models(&self) -> Vec<antigravity_core::domain::Model> {
        self.accounts
            .model_catalog()
            .unwrap_or_default()
    }

    fn resolve(&self, requested: &str) -> Option<String> {
        let models = self.models();
        if let Some(model) = models.iter().find(|model| model.id == requested) {
            return Some(model.id.clone());
        }

        // The coding tools ask for the model names of their own protocol. The
        // gateway routes them onto the models the account really has.
        let lowered = requested.to_lowercase();
        let fallback = if lowered.starts_with("claude") {
            "gemini-3.8-flash-high"
        } else if lowered.starts_with("gpt") || lowered.starts_with("o1") {
            "gemini-3.8-flash-high"
        } else {
            "gemini-3.8-flash-high"
        };

        models
            .iter()
            .find(|model| model.id == fallback)
            .map(|model| model.id.clone())
    }
}

/// The running local proxy.
pub struct ProxyRuntime {
    pub state: tokio::sync::Mutex<Option<tokio::task::JoinHandle<()>>>,
    pub port: tokio::sync::Mutex<Option<u16>>,
}

impl Default for ProxyRuntime {
    fn default() -> Self {
        Self {
            state: tokio::sync::Mutex::new(None),
            port: tokio::sync::Mutex::new(None),
        }
    }
}

impl ProxyRuntime {
    /// Whether the proxy is listening.
    pub async fn is_running(&self) -> bool {
        self.state.lock().await.is_some()
    }

    /// The port the proxy listens on.
    pub async fn current_port(&self) -> Option<u16> {
        *self.port.lock().await
    }

    /// Starts the proxy on the given port.
    pub async fn start(
        &self,
        state: ProxyState,
        port: u16,
        bind_all: bool,
    ) -> Result<u16, CloudError> {
        if self.is_running().await {
            return Ok(self.current_port().await.unwrap_or(port));
        }

        let address = if bind_all {
            format!("0.0.0.0:{port}")
        } else {
            format!("127.0.0.1:{port}")
        };

        let listener = tokio::net::TcpListener::bind(&address)
            .await
            .map_err(|error| CloudError::Provider(format!("cannot bind {address}: {error}")))?;
        let bound = listener
            .local_addr()
            .map_err(|error| CloudError::Provider(error.to_string()))?
            .port();

        let router = antigravity_proxy::router(state);
        let handle = tokio::spawn(async move {
            let _ = axum::serve(listener, router).await;
        });

        *self.state.lock().await = Some(handle);
        *self.port.lock().await = Some(bound);

        Ok(bound)
    }

    /// Restarts the proxy on the same port.
    ///
    /// The bind address follows the key: a proxy with a key listens on every
    /// interface, a proxy without a key stays on the loopback.
    pub async fn restart(
        &self,
        state: ProxyState,
        port: u16,
        bind_all: bool,
    ) -> Result<u16, CloudError> {
        self.stop().await;
        self.start(state, port, bind_all).await
    }

    /// Stops the proxy.
    ///
    /// The task of the server is awaited, so the socket of the listener is
    /// really closed when the call returns. Without that, a restart would try
    /// to bind a port the kernel still holds.
    pub async fn stop(&self) {
        if let Some(handle) = self.state.lock().await.take() {
            handle.abort();
            let _ = handle.await;
        }
        *self.port.lock().await = None;
    }
}

/// The status of a finished session.
pub fn session_status(service: &CloudService, session_id: &str) -> Option<ConnectStatus> {
    service.sessions.status(session_id).map(|(status, _, _)| {
        match status.as_str() {
            "completed" => ConnectStatus::Completed,
            "failed" => ConnectStatus::Failed,
            "expired" => ConnectStatus::Expired,
            _ => ConnectStatus::Pending,
        }
    })
}
