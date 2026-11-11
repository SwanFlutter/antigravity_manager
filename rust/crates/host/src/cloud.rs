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
use antigravity_google::{sanitize_message, GoogleClient, ModelQuotaSnapshot, OAuthClient};
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

pub fn open_browser(url: &str) -> Result<(), CloudError> {
    #[cfg(windows)]
    {
        let candidates = chrome_candidates(|key| std::env::var_os(key));
        let command = chrome_command(url, candidates, |path| path.is_file())?;
        launch_chrome(command)
    }

    #[cfg(not(windows))]
    {
        let _ = url;
        Err(CloudError::Provider(
            "automatic Chrome launch is supported only on Windows".to_string(),
        ))
    }
}

#[cfg(any(windows, test))]
fn chrome_candidates(
    mut environment: impl FnMut(&str) -> Option<std::ffi::OsString>,
) -> Vec<std::path::PathBuf> {
    ["ProgramFiles", "ProgramFiles(x86)", "LOCALAPPDATA"]
        .into_iter()
        .filter_map(|key| environment(key).map(std::path::PathBuf::from))
        .filter(|root| root.is_absolute())
        .map(|root| root.join("Google").join("Chrome").join("Application").join("chrome.exe"))
        .collect()
}

#[cfg(any(windows, test))]
fn chrome_command(
    url: &str,
    candidates: Vec<std::path::PathBuf>,
    is_file: impl Fn(&std::path::Path) -> bool,
) -> Result<std::process::Command, CloudError> {
    let chrome = candidates.into_iter().find(|path| is_file(path)).ok_or_else(|| {
        CloudError::Provider(
            "Google Chrome was not found. Install Chrome in Program Files or Local AppData, then try Add account again.".to_string(),
        )
    })?;
    let mut command = std::process::Command::new(chrome);
    // No shell: OAuth query separators must reach Chrome as part of one argument.
    command.arg(url);
    Ok(command)
}

#[cfg(any(windows, test))]
fn launch_chrome(mut command: std::process::Command) -> Result<(), CloudError> {
    command.spawn().map(|_| ()).map_err(|error| {
        CloudError::Provider(format!(
            "Could not launch Google Chrome at {}: {error}. Check the Chrome installation and permissions, then try Add account again.",
            command.get_program().to_string_lossy(),
        ))
    })
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
    /// Whether Chrome opens the authorization page.
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
    start_connect_with_launcher(service, session_id, open_browser).await
}

async fn start_connect_with_launcher(
    service: Arc<CloudService>,
    session_id: String,
    launcher: impl FnOnce(&str) -> Result<(), CloudError> + Send + 'static,
) -> Result<(String, String, i64), CloudError> {
    let state = uuid::Uuid::new_v4().simple().to_string();
    let (redirect_uri, receiver) = crate::oauth::start_callback_listener(state.clone())
        .await
        .map_err(|error| CloudError::Provider(format!("cannot listen for the callback: {error}")))?;
    let client = OAuthClient::builtin();
    let authorization_url = service.google.auth_url(&client, &redirect_uri, &state);
    let expires_at = now_millis() + 5 * 60 * 1000;
    let (cancel, cancelled) = tokio::sync::oneshot::channel();
    if !service.sessions.insert(
        session_id.clone(),
        redirect_uri.clone(),
        expires_at,
        cancel,
    ) {
        return Err(CloudError::Invalid("the session already exists".to_string()));
    }

    let worker_service = Arc::clone(&service);
    let session = session_id.clone();
    tokio::spawn(async move {
        let answer = tokio::select! {
            biased;
            _ = cancelled => return,
            _ = tokio::time::sleep(Duration::from_secs(300)) => {
                worker_service.sessions.expire(&session, expires_at);
                return;
            }
            answer = receiver => answer,
        };
        let Some(redirect) = worker_service.sessions.claim(&session, now_millis()) else {
            return;
        };
        match answer {
            Ok(OAuthCallback {
                code: Some(code),
                error: None,
                ..
            }) => {
                complete_session(
                    &worker_service.sessions,
                    &session,
                    complete_connect(&worker_service, &code, &redirect),
                )
                .await;
            }
            Ok(OAuthCallback {
                error: Some(error), ..
            }) => {
                let message = if error == "access_denied" {
                    "Google authorization was cancelled. Start Add account again to retry.".to_string()
                } else {
                    format!("Google authorization failed ({error}). Start Add account again to retry.")
                };
                worker_service.sessions.finish(&session, Err(message));
            }
            _ => {
                worker_service.sessions.finish(&session, Err(
                    "The OAuth callback listener stopped. Start Add account again to retry.".to_string(),
                ));
            }
        }
    });

    if service.launch_browser {
        let url = authorization_url.clone();
        let launched = tokio::task::spawn_blocking(move || launcher(&url))
            .await
            .unwrap_or_else(|error| {
                Err(CloudError::Provider(format!(
                    "Chrome launcher failed: {error}. Try Add account again."
                )))
            });
        if let Err(error) = launched {
            if service.sessions.claim(&session_id, now_millis()).is_some() {
                service.sessions.finish(&session_id, Err(error.to_string()));
            }
            return Err(error);
        }
    }

    Ok((authorization_url, redirect_uri, expires_at))
}

/// Finishes a session with a code the user copied by hand.
pub async fn submit_code(
    service: Arc<CloudService>,
    session_id: &str,
    code: &str,
) -> Result<(), CloudError> {
    submit_code_with_completion(
        service.sessions.clone(), session_id, code,
        move |code, redirect| async move { complete_connect(&service, &code, &redirect).await },
    )
}

fn submit_code_with_completion<F>(
    sessions: Arc<SessionStore>,
    session_id: &str,
    code: &str,
    completion: impl FnOnce(String, String) -> F + Send + 'static,
) -> Result<(), CloudError>
where
    F: std::future::Future<Output = Result<String, CloudError>> + Send + 'static,
{
    let code = code.trim();
    if code.is_empty() {
        return Err(CloudError::Invalid("enter the authorization code from Google".to_string()));
    }
    let redirect_uri = sessions.claim(session_id, now_millis())
        .ok_or(CloudError::UnknownSession)?;
    let session = session_id.to_string();
    let code = code.to_string();
    tokio::spawn(async move {
        complete_session(&sessions, &session, completion(code, redirect_uri)).await;
    });
    Ok(())
}

async fn complete_session(
    sessions: &SessionStore,
    session_id: &str,
    completion: impl std::future::Future<Output = Result<String, CloudError>>,
) {
    sessions.finish(session_id, completion.await.map_err(|error| error.to_string()));
}

/// Exchanges the code, reads the identity and stores the account.
async fn complete_connect(
    service: &CloudService,
    code: &str,
    redirect_uri: &str,
) -> Result<String, CloudError> {
    let client = OAuthClient::builtin();

    let tokens = service
        .google
        .exchange_code(&client, code, redirect_uri)
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
    connected_identity(info.email, refresh_quota(service, &account).await)
}

fn connected_identity(email: String, sync: Result<Account, CloudError>) -> Result<String, CloudError> {
    if let Err(error) = sync {
        // Identity and credentials are already saved. The persisted quota_error
        // is shown separately from OAuth completion; never report a failed login.
        eprintln!("[host] account connected; quota sync failed: {}", sanitize_message(&error.to_string(), &[]));
    }
    Ok(email)
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
        quota_fetched_at: None,
        quota_error: None,
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
    let fetch = async {
        let Some(mut credentials) = service.cloud.load_credentials(&account.id)
            .map_err(|error| CloudError::Repository(error.to_string()))?
        else {
            return Err(CloudError::Invalid("the account is not connected".to_string()));
        };
        if credentials.needs_refresh(now_millis()) {
            credentials = refresh_credentials(service, credentials).await?;
        }
        let provider_error = |error: antigravity_google::GoogleError| {
            CloudError::Provider(sanitize_message(&error.to_string(), &[
                &credentials.access_token,
                credentials.refresh_token.as_deref().unwrap_or_default(),
            ]))
        };
        let snapshot = service.google
            .fetch_model_quotas(&credentials.access_token, credentials.project_id.as_deref())
            .await.map_err(provider_error)?;
        let groups = service.google
            .fetch_quota_groups(&credentials.access_token, credentials.project_id.as_deref())
            .await.map_err(provider_error);
        Ok((snapshot, groups))
    };
    refresh_quota_with(service, account, fetch).await
}

/// The fetch seam keeps persistence and failure handling testable without Google.
async fn refresh_quota_with(
    service: &CloudService,
    account: &Account,
    fetch: impl std::future::Future<Output = Result<
        (ModelQuotaSnapshot, Result<Vec<QuotaGroup>, CloudError>), CloudError,
    >>,
) -> Result<Account, CloudError> {
    let repository = service.accounts.repository();
    let result: Result<Account, CloudError> = async {
        let (snapshot, groups) = fetch.await?;
        let mut updated = repository.find_account(&account.id)
            .map_err(|error| CloudError::Repository(error.to_string()))?
            .ok_or_else(|| CloudError::Invalid("the account no longer exists".to_string()))?;
        updated.quotas = snapshot.quotas;
        updated.quota_fetched_at = Some(service.accounts.now_millis());
        updated.quota_error = None;
        match groups {
            Ok(groups) => updated.weekly_quotas = weekly_quotas(&groups),
            Err(error) => {
                updated.quota_error = Some(format!(
                    "Weekly quota sync failed; previous weekly quotas retained: {}",
                    sanitize_message(&error.to_string(), &[]),
                ));
            }
        }
        repository.merge_models(&snapshot.models)
            .map_err(|error| CloudError::Repository(error.to_string()))?;
        repository.save_account(&updated)
            .map_err(|error| CloudError::Repository(error.to_string()))?;
        Ok(updated)
    }.await;
    if let Err(error) = &result {
        let diagnostic = format!("Model quota sync failed; cached quotas retained: {}",
            sanitize_message(&error.to_string(), &[]));
        if let Err(save_error) = repository.set_quota_error(&account.id, &diagnostic) {
            return Err(CloudError::Repository(format!(
                "{diagnostic}; could not persist quota error: {}",
                sanitize_message(&save_error.to_string(), &[]),
            )));
        }
    }
    result
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
        .map_err(|error| CloudError::Provider(sanitize_message(&error.to_string(), &[
            &credentials.access_token, &refresh_token, &client.client_secret,
        ])))?;

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

#[cfg(test)]
mod oauth_tests {
    use super::*;
    use std::path::PathBuf;
    use tokio::sync::oneshot;

    fn service(launch_browser: bool) -> Arc<CloudService> {
        let repository = Arc::new(antigravity_core::sqlite::SqliteAccountRepository::open(":memory:").unwrap());
        let accounts = Arc::new(AccountService::new(
            repository.clone(),
            Box::new(antigravity_core::fakes::StaticQuotaProvider),
            Box::new(antigravity_core::fakes::FixedClock(0)),
        ));
        Arc::new(CloudService {
            accounts: accounts.clone(),
            cloud: repository.clone(),
            google: Arc::new(GoogleClient::new().unwrap()),
            sessions: Arc::new(SessionStore::default()),
            proxy: Arc::new(ProxyRuntime::default()),
            catalog: Arc::new(HostModelCatalog { accounts }),
            config: Arc::new(tokio::sync::RwLock::new(repository.load_proxy_config().unwrap())),
            launch_browser,
        })
    }

    fn insert_session(service: &CloudService, expires_at: i64) {
        let (cancel, _) = oneshot::channel();
        assert!(service.sessions.insert("session".into(), "http://127.0.0.1:1234/oauth-callback".into(), expires_at, cancel));
    }

    async fn assert_listener_closed(redirect: &str) {
        let address = redirect.trim_start_matches("http://").trim_end_matches("/oauth-callback");
        tokio::time::timeout(Duration::from_secs(3), async {
            while tokio::net::TcpStream::connect(address).await.is_ok() {
                tokio::task::yield_now().await;
            }
        }).await.expect("listener closes after cancellation");
    }

    #[test]
    fn chrome_selection_uses_standard_locations_and_a_single_url_argument() {
        let roots: Vec<PathBuf> = ["Program Files", "Program Files (x86)", "Local AppData"]
            .map(|name| std::env::temp_dir().join(name)).into();
        let candidates = chrome_candidates(|key| match key {
            "ProgramFiles" => Some(roots[0].clone().into_os_string()),
            "ProgramFiles(x86)" => Some(roots[1].clone().into_os_string()),
            "LOCALAPPDATA" => Some(roots[2].clone().into_os_string()),
            _ => panic!("unexpected environment variable"),
        });
        assert_eq!(candidates, roots.iter().map(|root| root.join("Google/Chrome/Application/chrome.exe")).collect::<Vec<_>>());
        let url = "https://accounts.google.com/o/oauth2/v2/auth?state=state&scope=one%20two&redirect_uri=http%3A%2F%2F127.0.0.1%3A1234%2Foauth-callback";
        for index in 0..candidates.len() {
            let command = chrome_command(url, candidates.clone(), |path| path == candidates[index]).unwrap();
            assert_eq!(command.get_program(), candidates[index].as_os_str());
            assert_eq!(command.get_args().collect::<Vec<_>>(), vec![std::ffi::OsStr::new(url)]);
        }
        let command = chrome_command(url, candidates.clone(), |_| true).unwrap();
        assert_eq!(command.get_program(), candidates[0].as_os_str());
    }

    #[test]
    fn missing_chrome_and_launch_errors_are_actionable_without_shell_fallback() {
        assert!(chrome_candidates(|_| None).is_empty());
        assert!(chrome_candidates(|_| Some("relative".into())).is_empty());
        let missing = chrome_command("https://example.invalid/?a=b&c=d", Vec::new(), |_| false).unwrap_err();
        assert!(missing.to_string().contains("Install Chrome"));
        let path = std::env::temp_dir().join(uuid::Uuid::new_v4().to_string()).join("chrome.exe");
        let command = chrome_command("https://example.invalid/?a=b&c=d", vec![path], |_| true).unwrap();
        let failed = launch_chrome(command).unwrap_err().to_string();
        assert!(failed.contains("Could not launch Google Chrome"));
        assert!(failed.contains("installation and permissions"));
        assert!(!failed.contains("https://"));
    }

    #[tokio::test]
    async fn launch_failure_is_returned_and_stored_after_session_insertion() {
        let service = service(true);
        let sessions = service.sessions.clone();
        let (sent, received) = oneshot::channel();
        let result = start_connect_with_launcher(service.clone(), "session".into(), move |url| {
            assert_eq!(sessions.status("session").unwrap().0, "pending");
            let url = reqwest::Url::parse(url).unwrap();
            let redirect = url.query_pairs().find(|(key, _)| key == "redirect_uri").unwrap().1.into_owned();
            sent.send(redirect).unwrap();
            Err(CloudError::Provider("Chrome launch failed; reinstall Chrome".into()))
        }).await;
        assert!(result.unwrap_err().to_string().contains("reinstall Chrome"));
        let status = service.sessions.status("session").unwrap();
        assert_eq!(status.0, "failed");
        assert!(status.2.unwrap().contains("reinstall Chrome"));
        assert_listener_closed(&received.await.unwrap()).await;
    }

    #[tokio::test]
    async fn tests_can_disable_launch_and_expiration_closes_the_listener() {
        let service = service(false);
        let (_, redirect, _) = start_connect_with_launcher(service.clone(), "session".into(), |_| {
            panic!("launch_browser:false must never invoke the launcher");
        }).await.unwrap();
        assert_eq!(service.sessions.status("session").unwrap().0, "pending");
        service.sessions.expire("session", i64::MAX);
        assert_eq!(service.sessions.status("session").unwrap().0, "expired");
        assert_listener_closed(&redirect).await;
    }

    #[tokio::test]
    async fn manual_codes_reject_empty_unknown_processing_and_finished_sessions() {
        let service = service(false);
        insert_session(&service, i64::MAX);
        for code in ["", " \r\n\t "] {
            assert!(matches!(submit_code(service.clone(), "session", code).await, Err(CloudError::Invalid(_))));
            assert_eq!(service.sessions.status("session").unwrap().0, "pending");
        }
        assert!(matches!(submit_code(service.clone(), "unknown", "code").await, Err(CloudError::UnknownSession)));
        assert!(service.sessions.claim("session", now_millis()).is_some());
        assert!(matches!(submit_code(service.clone(), "session", "code").await, Err(CloudError::UnknownSession)));
        service.sessions.finish("session", Ok("test@example.invalid".into()));
        for _ in 0..2 {
            assert!(matches!(submit_code(service.clone(), "session", "code").await, Err(CloudError::UnknownSession)));
        }
        assert_eq!(service.sessions.status("session").unwrap().0, "completed");
    }

    #[tokio::test]
    async fn manual_completion_is_claimed_once_and_closes_the_browser_listener() {
        let service = service(false);
        let (_, redirect, expires_at) = start_connect(service.clone(), "session".into()).await.unwrap();
        let expected_redirect = redirect.clone();
        let (release, released) = oneshot::channel();
        submit_code_with_completion(service.sessions.clone(), "session", "  test-code  ", move |code, redirect| async move {
            assert_eq!(code, "test-code");
            assert_eq!(redirect, expected_redirect);
            released.await.unwrap();
            Ok("test@example.invalid".into())
        }).unwrap();
        assert!(matches!(submit_code(service.clone(), "session", "duplicate").await, Err(CloudError::UnknownSession)));
        assert_listener_closed(&redirect).await;
        service.sessions.expire("session", expires_at);
        assert_eq!(service.sessions.status("session").unwrap().0, "pending");
        release.send(()).unwrap();
        tokio::time::timeout(Duration::from_secs(3), async {
            while service.sessions.status("session").unwrap().0 == "pending" {
                tokio::task::yield_now().await;
            }
        }).await.unwrap();
        service.sessions.expire("session", i64::MAX);
        assert_eq!(service.sessions.status("session").unwrap(), ("completed".into(), Some("test@example.invalid".into()), None));
        assert!(matches!(submit_code(service.clone(), "session", "duplicate").await, Err(CloudError::UnknownSession)));
    }

    #[tokio::test]
    async fn completion_errors_reach_status_and_cannot_be_overwritten_by_timeout() {
        for error in [CloudError::Provider("exchange rejected".into()), CloudError::Repository("storage unavailable".into())] {
            let service = service(false);
            insert_session(&service, i64::MAX);
            assert!(service.sessions.claim("session", now_millis()).is_some());
            let expected = error.to_string();
            complete_session(&service.sessions, "session", async { Err(error) }).await;
            service.sessions.expire("session", i64::MAX);
            assert_eq!(service.sessions.status("session").unwrap(), ("failed".into(), None, Some(expected)));
            assert!(matches!(submit_code(service.clone(), "session", "code").await, Err(CloudError::UnknownSession)));
        }
        let service = service(false);
        insert_session(&service, 0);
        assert!(matches!(submit_code(service.clone(), "session", "code").await, Err(CloudError::UnknownSession)));
        assert_eq!(service.sessions.status("session").unwrap().0, "expired");
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
