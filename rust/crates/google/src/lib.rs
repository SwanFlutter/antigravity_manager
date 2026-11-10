//! The adapter for the Google Cloud Code `v1internal` API.
//!
//! The crate speaks to the same endpoints as the upstream Electron
//! application: the OAuth endpoints of Google, the identity endpoint, the
//! project context endpoint, the model quota endpoint, the weekly quota
//! endpoint and the generation endpoints.
//!
//! Every mapping from an upstream answer to the domain of
//! [`antigravity_core`] lives in [`mapping`] and is a pure function, so the
//! behaviour can be tested without touching the network.

use std::pin::Pin;
use std::time::Duration;

use antigravity_core::cloud::QuotaGroup;
use antigravity_core::domain::ModelQuota;
use futures::future::BoxFuture;
use futures::stream::{Stream, StreamExt};
use serde_json::Value;

pub mod mapping;
pub mod time;

pub use mapping::{
    map_model_quotas, map_project_context, map_quota_groups, model_family_for, ProjectContext,
};
pub use time::{now_millis, parse_rfc3339_millis};

/// The client id of the built-in "Antigravity Enterprise" OAuth client.
pub const DEFAULT_CLIENT_ID: &str =
    "1071006060591-tmhssin2h21lcre235vtolojh4g403ep.apps.googleusercontent.com";

/// The client secret of the built-in "Antigravity Enterprise" OAuth client.
pub const DEFAULT_CLIENT_SECRET: &str = "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";

/// The scopes the upstream application asks for.
pub const OAUTH_SCOPE: &str = "openid https://www.googleapis.com/auth/cloud-platform https://www.googleapis.com/auth/userinfo.email https://www.googleapis.com/auth/userinfo.profile https://www.googleapis.com/auth/cclog https://www.googleapis.com/auth/experimentsandconfigs https://www.googleapis.com/auth/aicode";

/// The version this adapter announces to Google.
///
/// It is the version of the crate, so the identity of the client follows the
/// build of Antigravity Manager.
pub const CLIENT_VERSION: &str = env!("CARGO_PKG_VERSION");

/// The client version of the hub identity.
///
/// Upstream uses the hub identity of the Antigravity language server and
/// Google withholds the model specific quota groups from older hub versions.
/// The floor of upstream is therefore used here.
pub const HUB_CLIENT_VERSION: &str = "2.26.0";

/// The timeout of every HTTP request of this crate.
pub const REQUEST_TIMEOUT: Duration = Duration::from_secs(30);

/// The endpoint the browser is sent to.
pub const AUTH_ENDPOINT: &str = "https://accounts.google.com/o/oauth2/v2/auth";

/// The endpoint that hands out the tokens.
pub const TOKEN_ENDPOINT: &str = "https://oauth2.googleapis.com/token";

/// The endpoint that answers with the profile of the account.
pub const USER_INFO_ENDPOINT: &str = "https://www.googleapis.com/oauth2/v2/userinfo";

/// The endpoints of the project context, in the order upstream tries them.
pub const PROJECT_CONTEXT_ENDPOINTS: [&str; 3] = [
    "https://cloudcode-pa.googleapis.com/v1internal:loadCodeAssist",
    "https://daily-cloudcode-pa.googleapis.com/v1internal:loadCodeAssist",
    "https://daily-cloudcode-pa.sandbox.googleapis.com/v1internal:loadCodeAssist",
];

/// The endpoints of the model quotas, in the order upstream tries them.
pub const MODEL_QUOTA_ENDPOINTS: [&str; 3] = [
    "https://daily-cloudcode-pa.sandbox.googleapis.com/v1internal:fetchAvailableModels",
    "https://daily-cloudcode-pa.googleapis.com/v1internal:fetchAvailableModels",
    "https://cloudcode-pa.googleapis.com/v1internal:fetchAvailableModels",
];

/// The endpoints of the weekly quota groups, in the order upstream tries them.
pub const QUOTA_GROUP_ENDPOINTS: [&str; 3] = [
    "https://daily-cloudcode-pa.googleapis.com/v1internal:retrieveUserQuotaSummary",
    "https://cloudcode-pa.googleapis.com/v1internal:retrieveUserQuotaSummary",
    "https://daily-cloudcode-pa.sandbox.googleapis.com/v1internal:retrieveUserQuotaSummary",
];

/// The endpoints of the generation, in the order upstream tries them.
pub const GENERATE_CONTENT_ENDPOINTS: [&str; 2] = [
    "https://daily-cloudcode-pa.googleapis.com/v1internal:generateContent",
    "https://cloudcode-pa.googleapis.com/v1internal:generateContent",
];

/// The endpoints of the streaming generation, in the order upstream tries them.
pub const STREAM_GENERATE_CONTENT_ENDPOINTS: [&str; 2] = [
    "https://daily-cloudcode-pa.googleapis.com/v1internal:streamGenerateContent?alt=sse",
    "https://cloudcode-pa.googleapis.com/v1internal:streamGenerateContent?alt=sse",
];

/// The stream of a streaming answer.
///
/// The bytes are the raw SSE frames of the upstream service. The crate does
/// not interpret them, so the local proxy can forward them as they are.
pub type ByteStream =
    Pin<Box<dyn Stream<Item = Result<Vec<u8>, std::io::Error>> + Send>>;

/// The generation service the local proxy forwards to.
///
/// The trait hides the network behind a seam, so the proxy can be tested
/// against a fake generator without touching Google.
pub trait Generator: Send + Sync {
    /// Sends a request and returns the answer of the service.
    fn generate<'a>(
        &'a self,
        access_token: &'a str,
        project: Option<&'a str>,
        body: &'a Value,
    ) -> BoxFuture<'a, Result<Value, GoogleError>>;

    /// Sends a streaming request and returns the stream of the answer.
    fn stream<'a>(
        &'a self,
        access_token: &'a str,
        project: Option<&'a str>,
        body: &'a Value,
    ) -> BoxFuture<'a, Result<ByteStream, GoogleError>>;
}

impl Generator for GoogleClient {
    fn generate<'a>(
        &'a self,
        access_token: &'a str,
        project: Option<&'a str>,
        body: &'a Value,
    ) -> BoxFuture<'a, Result<Value, GoogleError>> {
        Box::pin(self.generate_content(access_token, project, body))
    }

    fn stream<'a>(
        &'a self,
        access_token: &'a str,
        project: Option<&'a str>,
        body: &'a Value,
    ) -> BoxFuture<'a, Result<ByteStream, GoogleError>> {
        Box::pin(async move {
            let response = self.stream_generate_content(access_token, project, body).await?;
            let stream = response.bytes_stream().map(|chunk| {
                chunk.map(|bytes| bytes.to_vec()).map_err(|error| {
                    std::io::Error::new(std::io::ErrorKind::Other, error.to_string())
                })
            });
            Ok(Box::pin(stream) as ByteStream)
        })
    }
}

/// One OAuth client an account can be authorized with.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct OAuthClient {
    /// The stable key of the client.
    pub key: String,
    /// The name shown in the interface.
    pub label: String,
    pub client_id: String,
    pub client_secret: String,
}

impl OAuthClient {
    /// The built-in "Antigravity Enterprise" client of the upstream
    /// application.
    pub fn builtin() -> Self {
        Self {
            key: "builtin".to_string(),
            label: "Antigravity Enterprise".to_string(),
            client_id: DEFAULT_CLIENT_ID.to_string(),
            client_secret: DEFAULT_CLIENT_SECRET.to_string(),
        }
    }
}

/// The tokens of one connected account.
#[derive(Debug, Clone, PartialEq, Eq, Default)]
pub struct TokenSet {
    pub access_token: String,
    /// The refresh token. A refresh answer omits it, so the caller keeps the
    /// one it already stored.
    pub refresh_token: Option<String>,
    /// The lifetime of the access token in seconds.
    pub expires_in: Option<i64>,
    /// When the access token expires, in milliseconds since the Unix epoch.
    pub expiry_timestamp: Option<i64>,
    pub token_type: String,
    pub id_token: Option<String>,
}

/// The profile of the connected account.
#[derive(Debug, Clone, PartialEq, Eq, Default)]
pub struct UserInfo {
    pub email: String,
    pub name: Option<String>,
    pub picture: Option<String>,
}

/// The errors of this crate.
#[derive(Debug, thiserror::Error)]
pub enum GoogleError {
    #[error("network error: {0}")]
    Network(String),
    #[error("upstream returned {status}: {message}")]
    Upstream { status: u16, message: String },
    #[error("malformed upstream response: {0}")]
    Malformed(String),
    #[error("no account is connected")]
    NoAccount,
}

/// The client of the Google Cloud Code API.
#[derive(Debug, Clone)]
pub struct GoogleClient {
    http: reqwest::Client,
}

impl GoogleClient {
    /// Builds a client with the timeout of the upstream application.
    pub fn new() -> Result<Self, GoogleError> {
        let http = reqwest::Client::builder()
            .timeout(REQUEST_TIMEOUT)
            .build()
            .map_err(|error| GoogleError::Network(error.to_string()))?;
        Ok(Self { http })
    }

    /// The URL the browser is sent to in order to connect an account.
    pub fn auth_url(&self, client: &OAuthClient, redirect_uri: &str, state: &str) -> String {
        let mut url = reqwest::Url::parse(AUTH_ENDPOINT).expect("the auth endpoint is a valid URL");
        {
            let mut query = url.query_pairs_mut();
            query.append_pair("access_type", "offline");
            query.append_pair("prompt", "consent");
            query.append_pair("response_type", "code");
            query.append_pair("include_granted_scopes", "true");
            query.append_pair("client_id", &client.client_id);
            query.append_pair("redirect_uri", redirect_uri);
            query.append_pair("state", state);
            query.append_pair("scope", OAUTH_SCOPE);
        }
        url.to_string()
    }

    /// Exchanges an authorization code for the tokens of the account.
    pub async fn exchange_code(
        &self,
        client: &OAuthClient,
        code: &str,
        redirect_uri: &str,
    ) -> Result<TokenSet, GoogleError> {
        let form = [
            ("client_id", client.client_id.as_str()),
            ("client_secret", client.client_secret.as_str()),
            ("code", code),
            ("redirect_uri", redirect_uri),
            ("grant_type", "authorization_code"),
        ];

        let payload = self.post_form(TOKEN_ENDPOINT, &form).await?;
        parse_token_set(&payload, now_millis())
    }

    /// Refreshes an access token.
    ///
    /// Google omits the refresh token in the answer. The returned set
    /// therefore carries the refresh token that was passed in, so the caller
    /// can store the answer as it is.
    pub async fn refresh_access_token(
        &self,
        client: &OAuthClient,
        refresh_token: &str,
    ) -> Result<TokenSet, GoogleError> {
        let form = [
            ("client_id", client.client_id.as_str()),
            ("client_secret", client.client_secret.as_str()),
            ("refresh_token", refresh_token),
            ("grant_type", "refresh_token"),
        ];

        let payload = self.post_form(TOKEN_ENDPOINT, &form).await?;
        let mut tokens = parse_token_set(&payload, now_millis())?;
        if tokens.refresh_token.is_none() {
            tokens.refresh_token = Some(refresh_token.to_string());
        }
        Ok(tokens)
    }

    /// The profile of the connected account.
    pub async fn user_info(&self, access_token: &str) -> Result<UserInfo, GoogleError> {
        let response = self
            .http
            .get(USER_INFO_ENDPOINT)
            .bearer_auth(access_token)
            .send()
            .await
            .map_err(|error| GoogleError::Network(error.to_string()))?;

        let status = response.status();
        let body = response.text().await.unwrap_or_default();
        if !status.is_success() {
            return Err(GoogleError::Upstream {
                status: status.as_u16(),
                message: sanitize_message(&body),
            });
        }

        let payload: Value = serde_json::from_str(&body)
            .map_err(|error| GoogleError::Malformed(error.to_string()))?;
        let email = payload
            .get("email")
            .and_then(Value::as_str)
            .map(str::trim)
            .filter(|value| !value.is_empty())
            .ok_or_else(|| GoogleError::Malformed("the user info has no email".to_string()))?;

        Ok(UserInfo {
            email: email.to_string(),
            name: payload
                .get("name")
                .and_then(Value::as_str)
                .map(str::trim)
                .filter(|value| !value.is_empty())
                .map(str::to_string),
            picture: payload
                .get("picture")
                .and_then(Value::as_str)
                .map(str::trim)
                .filter(|value| !value.is_empty())
                .map(str::to_string),
        })
    }

    /// The project, the plan and the credits of the connected account.
    ///
    /// The endpoints are tried in the order of
    /// [`PROJECT_CONTEXT_ENDPOINTS`]. A failing endpoint does not stop the
    /// lookup, the error of the last endpoint is reported.
    pub async fn load_project(&self, access_token: &str) -> Result<ProjectContext, GoogleError> {
        // The upstream application identifies itself as the Antigravity
        // client, otherwise Google does not return the project of the account.
        let body = serde_json::json!({
            "metadata": { "ideType": "ANTIGRAVITY" }
        });

        let payload = self
            .post_json_with_fallback(
                &PROJECT_CONTEXT_ENDPOINTS,
                access_token,
                &body,
                false,
            )
            .await?;
        Ok(map_project_context(&payload))
    }

    /// The quotas of the models of the connected account.
    ///
    /// The endpoints are tried in the order of [`MODEL_QUOTA_ENDPOINTS`].
    pub async fn fetch_model_quotas(
        &self,
        access_token: &str,
        project: Option<&str>,
    ) -> Result<Vec<ModelQuota>, GoogleError> {
        let payload = match self
            .post_json_with_fallback(
                &MODEL_QUOTA_ENDPOINTS,
                access_token,
                &project_body(project),
                false,
            )
            .await
        {
            Ok(payload) => payload,
            // Google rejects the project of some accounts. The answer without
            // the project still carries the quota.
            Err(GoogleError::Upstream { status: 403, .. }) if project.is_some() => {
                self.post_json_with_fallback(
                    &MODEL_QUOTA_ENDPOINTS,
                    access_token,
                    &Value::Object(serde_json::Map::new()),
                    false,
                )
                .await?
            }
            Err(error) => return Err(error),
        };

        Ok(map_model_quotas(&payload, now_millis()))
    }

    /// The weekly allowance of the model groups of the connected account.
    ///
    /// The endpoints are tried in the order of [`QUOTA_GROUP_ENDPOINTS`]. This
    /// request uses the hub identity of the Antigravity language server,
    /// because Google withholds the model specific groups from the plain
    /// identity.
    pub async fn fetch_quota_groups(
        &self,
        access_token: &str,
        project: Option<&str>,
    ) -> Result<Vec<QuotaGroup>, GoogleError> {
        let payload = match self
            .post_json_with_fallback(
                &QUOTA_GROUP_ENDPOINTS,
                access_token,
                &project_body(project),
                true,
            )
            .await
        {
            Ok(payload) => payload,
            Err(GoogleError::Upstream { status: 403, .. }) if project.is_some() => {
                self.post_json_with_fallback(
                    &QUOTA_GROUP_ENDPOINTS,
                    access_token,
                    &Value::Object(serde_json::Map::new()),
                    true,
                )
                .await?
            }
            Err(error) => return Err(error),
        };

        Ok(map_quota_groups(&payload))
    }

    /// Sends a generation request and returns the answer of Google.
    ///
    /// The body is passed through unchanged, the caller builds the internal
    /// envelope of Google. The upstream may answer flat or wrapped in a
    /// `response` object; the inner object is returned in the second case.
    pub async fn generate_content(
        &self,
        access_token: &str,
        project: Option<&str>,
        body: &Value,
    ) -> Result<Value, GoogleError> {
        let _ = project;
        let payload = self
            .post_json_with_fallback(&GENERATE_CONTENT_ENDPOINTS, access_token, body, false)
            .await?;
        Ok(unwrap_generation_response(payload))
    }

    /// Sends a streaming generation request and hands the answer to the
    /// caller, so the caller can stream the bytes of the SSE answer.
    pub async fn stream_generate_content(
        &self,
        access_token: &str,
        project: Option<&str>,
        body: &Value,
    ) -> Result<reqwest::Response, GoogleError> {
        let _ = project;
        let mut last_error = None;

        for endpoint in STREAM_GENERATE_CONTENT_ENDPOINTS {
            let response = self
                .http
                .post(endpoint)
                .bearer_auth(access_token)
                .header(reqwest::header::CONTENT_TYPE, "application/json")
                .header(reqwest::header::USER_AGENT, plain_user_agent())
                .json(body)
                .send()
                .await;

            match response {
                Ok(response) if response.status().is_success() => return Ok(response),
                Ok(response) => {
                    let status = response.status();
                    let body = response.text().await.unwrap_or_default();
                    last_error = Some(GoogleError::Upstream {
                        status: status.as_u16(),
                        message: sanitize_message(&body),
                    });
                }
                Err(error) => {
                    last_error = Some(GoogleError::Network(error.to_string()));
                }
            }
        }

        Err(last_error.unwrap_or(GoogleError::NoAccount))
    }

    /// Sends a form encoded request to the token endpoint.
    async fn post_form(
        &self,
        endpoint: &str,
        form: &[(&str, &str)],
    ) -> Result<Value, GoogleError> {
        let response = self
            .http
            .post(endpoint)
            .header(
                reqwest::header::CONTENT_TYPE,
                "application/x-www-form-urlencoded",
            )
            .form(form)
            .send()
            .await
            .map_err(|error| GoogleError::Network(error.to_string()))?;

        let status = response.status();
        let body = response.text().await.unwrap_or_default();
        if !status.is_success() {
            return Err(GoogleError::Upstream {
                status: status.as_u16(),
                message: sanitize_message(&body),
            });
        }

        serde_json::from_str(&body).map_err(|error| GoogleError::Malformed(error.to_string()))
    }

    /// Posts a JSON body to the given endpoints until one of them answers.
    ///
    /// The error of the last endpoint is reported when none of them answers.
    async fn post_json_with_fallback(
        &self,
        endpoints: &[&str],
        access_token: &str,
        body: &Value,
        hub_identity: bool,
    ) -> Result<Value, GoogleError> {
        let mut last_error = None;

        for endpoint in endpoints {
            let user_agent = if hub_identity {
                hub_user_agent()
            } else {
                plain_user_agent()
            };

            let response = self
                .http
                .post(*endpoint)
                .bearer_auth(access_token)
                .header(reqwest::header::CONTENT_TYPE, "application/json")
                .header(reqwest::header::USER_AGENT, user_agent)
                .json(body)
                .send()
                .await;

            match response {
                Ok(response) if response.status().is_success() => {
                    let body = response.text().await.unwrap_or_default();
                    return serde_json::from_str(&body)
                        .map_err(|error| GoogleError::Malformed(error.to_string()));
                }
                Ok(response) => {
                    let status = response.status();
                    let body = response.text().await.unwrap_or_default();
                    last_error = Some(GoogleError::Upstream {
                        status: status.as_u16(),
                        message: sanitize_message(&body),
                    });
                }
                Err(error) => {
                    last_error = Some(GoogleError::Network(error.to_string()));
                }
            }
        }

        Err(last_error.unwrap_or(GoogleError::NoAccount))
    }
}

/// The body of the requests that know a project.
fn project_body(project: Option<&str>) -> Value {
    match project {
        Some(project) if !project.is_empty() => serde_json::json!({ "project": project }),
        _ => Value::Object(serde_json::Map::new()),
    }
}

/// The identity of the plain client.
fn plain_user_agent() -> String {
    format!("antigravity/{CLIENT_VERSION} windows/amd64")
}

/// The identity of the hub client of the Antigravity language server.
fn hub_user_agent() -> String {
    format!(
        "antigravity/hub/{HUB_CLIENT_VERSION} (aidev_client; os_type=windows; arch=amd64)"
    )
}

/// Reads the answer of the token endpoint.
fn parse_token_set(payload: &Value, now_millis: i64) -> Result<TokenSet, GoogleError> {
    let access_token = payload
        .get("access_token")
        .and_then(Value::as_str)
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .ok_or_else(|| GoogleError::Malformed("the token answer has no access token".to_string()))?;

    let expires_in = payload
        .get("expires_in")
        .and_then(Value::as_i64)
        .or_else(|| {
            payload
                .get("expires_in")
                .and_then(Value::as_f64)
                .map(|value| value as i64)
        });

    Ok(TokenSet {
        access_token: access_token.to_string(),
        refresh_token: payload
            .get("refresh_token")
            .and_then(Value::as_str)
            .map(str::trim)
            .filter(|value| !value.is_empty())
            .map(str::to_string),
        expires_in,
        expiry_timestamp: expires_in.map(|seconds| now_millis + seconds * 1_000),
        token_type: payload
            .get("token_type")
            .and_then(Value::as_str)
            .map(str::trim)
            .filter(|value| !value.is_empty())
            .unwrap_or("Bearer")
            .to_string(),
        id_token: payload
            .get("id_token")
            .and_then(Value::as_str)
            .map(str::trim)
            .filter(|value| !value.is_empty())
            .map(str::to_string),
    })
}

/// Unwraps the `response` envelope the upstream may answer with.
fn unwrap_generation_response(payload: Value) -> Value {
    match payload.get("response") {
        Some(inner) if inner.is_object() => inner.clone(),
        _ => payload,
    }
}

/// Shortens the body of a failed request and removes the secrets from it.
///
/// The message never carries a token: it is meant for a log and for the
/// interface.
fn sanitize_message(body: &str) -> String {
    let redacted = match serde_json::from_str::<Value>(body) {
        Ok(Value::Object(_)) => {
            let mut value: Value = serde_json::from_str(body).unwrap_or(Value::Null);
            redact_json(&mut value);
            value.to_string()
        }
        _ => redact_text(body),
    };

    let mut excerpt: String = redacted.chars().take(300).collect();
    if excerpt.chars().count() < redacted.chars().count() {
        excerpt.push('…');
    }
    excerpt
}

/// Removes the secret fields of a JSON answer.
fn redact_json(value: &mut Value) {
    match value {
        Value::Object(map) => {
            for (key, entry) in map.iter_mut() {
                let lowered = key.to_ascii_lowercase();
                if lowered.contains("token")
                    || lowered.contains("secret")
                    || lowered.contains("authorization")
                {
                    *entry = Value::String("[redacted]".to_string());
                } else {
                    redact_json(entry);
                }
            }
        }
        Value::Array(entries) => {
            for entry in entries {
                redact_json(entry);
            }
        }
        _ => {}
    }
}

/// Removes the token shaped words of a plain text answer.
fn redact_text(body: &str) -> String {
    body.split_whitespace()
        .map(|word| {
            if word.starts_with("ya29.")
                || word.starts_with("1//")
                || (word.starts_with("eyJ") && word.contains('.'))
            {
                "[redacted]".to_string()
            } else {
                word.to_string()
            }
        })
        .collect::<Vec<_>>()
        .join(" ")
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    fn client() -> GoogleClient {
        GoogleClient::new().expect("the client builds")
    }

    #[test]
    fn the_auth_url_carries_every_parameter() {
        let url = client().auth_url(
            &OAuthClient::builtin(),
            "http://127.0.0.1:8045/oauth/callback",
            "state-123",
        );

        assert!(url.starts_with("https://accounts.google.com/o/oauth2/v2/auth?"));

        let query = url.split_once('?').expect("the url has a query").1;
        let pairs: Vec<(String, String)> = query
            .split('&')
            .map(|pair| {
                let (key, value) = pair.split_once('=').expect("every pair has a key");
                (percent_decode(key), percent_decode(value))
            })
            .collect();
        let get = |key: &str| {
            pairs
                .iter()
                .find(|(name, _)| name == key)
                .map(|(_, value)| value.as_str())
        };

        assert_eq!(get("access_type"), Some("offline"));
        assert_eq!(get("prompt"), Some("consent"));
        assert_eq!(get("response_type"), Some("code"));
        assert_eq!(get("include_granted_scopes"), Some("true"));
        assert_eq!(get("client_id"), Some(DEFAULT_CLIENT_ID));
        assert_eq!(
            get("redirect_uri"),
            Some("http://127.0.0.1:8045/oauth/callback")
        );
        assert_eq!(get("state"), Some("state-123"));
        assert_eq!(get("scope"), Some(OAUTH_SCOPE));
    }

    #[test]
    fn the_scope_is_the_scope_of_the_upstream_application() {
        assert_eq!(
            OAUTH_SCOPE,
            "openid https://www.googleapis.com/auth/cloud-platform https://www.googleapis.com/auth/userinfo.email https://www.googleapis.com/auth/userinfo.profile https://www.googleapis.com/auth/cclog https://www.googleapis.com/auth/experimentsandconfigs https://www.googleapis.com/auth/aicode"
        );
    }

    #[test]
    fn the_builtin_client_is_the_enterprise_client() {
        let builtin = OAuthClient::builtin();
        assert_eq!(builtin.key, "builtin");
        assert_eq!(builtin.label, "Antigravity Enterprise");
        assert_eq!(builtin.client_id, DEFAULT_CLIENT_ID);
        assert_eq!(builtin.client_secret, DEFAULT_CLIENT_SECRET);
    }

    #[test]
    fn the_endpoint_order_is_the_order_of_the_upstream_application() {
        assert_eq!(
            PROJECT_CONTEXT_ENDPOINTS,
            [
                "https://cloudcode-pa.googleapis.com/v1internal:loadCodeAssist",
                "https://daily-cloudcode-pa.googleapis.com/v1internal:loadCodeAssist",
                "https://daily-cloudcode-pa.sandbox.googleapis.com/v1internal:loadCodeAssist",
            ]
        );
        assert_eq!(
            MODEL_QUOTA_ENDPOINTS,
            [
                "https://daily-cloudcode-pa.sandbox.googleapis.com/v1internal:fetchAvailableModels",
                "https://daily-cloudcode-pa.googleapis.com/v1internal:fetchAvailableModels",
                "https://cloudcode-pa.googleapis.com/v1internal:fetchAvailableModels",
            ]
        );
        assert_eq!(
            QUOTA_GROUP_ENDPOINTS,
            [
                "https://daily-cloudcode-pa.googleapis.com/v1internal:retrieveUserQuotaSummary",
                "https://cloudcode-pa.googleapis.com/v1internal:retrieveUserQuotaSummary",
                "https://daily-cloudcode-pa.sandbox.googleapis.com/v1internal:retrieveUserQuotaSummary",
            ]
        );
        assert_eq!(
            GENERATE_CONTENT_ENDPOINTS,
            [
                "https://daily-cloudcode-pa.googleapis.com/v1internal:generateContent",
                "https://cloudcode-pa.googleapis.com/v1internal:generateContent",
            ]
        );
        assert_eq!(
            STREAM_GENERATE_CONTENT_ENDPOINTS,
            [
                "https://daily-cloudcode-pa.googleapis.com/v1internal:streamGenerateContent?alt=sse",
                "https://cloudcode-pa.googleapis.com/v1internal:streamGenerateContent?alt=sse",
            ]
        );
    }

    #[test]
    fn the_identities_are_the_identities_of_the_upstream_application() {
        assert_eq!(
            plain_user_agent(),
            format!("antigravity/{CLIENT_VERSION} windows/amd64")
        );
        assert_eq!(
            hub_user_agent(),
            format!("antigravity/hub/{HUB_CLIENT_VERSION} (aidev_client; os_type=windows; arch=amd64)")
        );
    }

    #[test]
    fn reads_the_token_answer() {
        let payload = json!({
            "access_token": "access",
            "refresh_token": "refresh",
            "expires_in": 3599,
            "token_type": "Bearer",
            "id_token": "id"
        });

        let tokens = parse_token_set(&payload, 1_000).expect("the answer is read");

        assert_eq!(tokens.access_token, "access");
        assert_eq!(tokens.refresh_token.as_deref(), Some("refresh"));
        assert_eq!(tokens.expires_in, Some(3599));
        assert_eq!(tokens.expiry_timestamp, Some(3_600_000));
        assert_eq!(tokens.token_type, "Bearer");
        assert_eq!(tokens.id_token.as_deref(), Some("id"));
    }

    #[test]
    fn rejects_a_token_answer_without_an_access_token() {
        let payload = json!({ "expires_in": 10 });

        let error = parse_token_set(&payload, 0).unwrap_err();

        assert!(matches!(error, GoogleError::Malformed(_)));
    }

    #[test]
    fn unwraps_the_generation_envelope() {
        let wrapped = json!({ "response": { "candidates": [] } });
        assert_eq!(
            unwrap_generation_response(wrapped),
            json!({ "candidates": [] })
        );

        let flat = json!({ "candidates": [] });
        assert_eq!(unwrap_generation_response(flat.clone()), flat);
    }

    #[test]
    fn shortens_and_redacts_the_message_of_a_failure() {
        let body = json!({
            "error": "invalid_grant",
            "access_token": "ya29.secret",
            "detail": "x".repeat(400)
        })
        .to_string();

        let message = sanitize_message(&body);

        assert!(!message.contains("ya29.secret"));
        assert!(message.contains("[redacted]"));
        assert!(message.chars().count() <= 301);
    }

    #[test]
    fn redacts_the_tokens_of_a_plain_text_answer() {
        let message = sanitize_message("the token ya29.abcdef was rejected");

        assert!(!message.contains("ya29.abcdef"));
        assert!(message.contains("[redacted]"));
    }

    /// Decodes the percent encoding of a query part.
    fn percent_decode(value: &str) -> String {
        let bytes = value.as_bytes();
        let mut out = Vec::with_capacity(bytes.len());
        let mut index = 0;
        while index < bytes.len() {
            match bytes[index] {
                b'%' if index + 2 < bytes.len() => {
                    let hex = std::str::from_utf8(&bytes[index + 1..index + 3]).unwrap_or("");
                    match u8::from_str_radix(hex, 16) {
                        Ok(byte) => {
                            out.push(byte);
                            index += 3;
                        }
                        Err(_) => {
                            out.push(bytes[index]);
                            index += 1;
                        }
                    }
                }
                b'+' => {
                    out.push(b' ');
                    index += 1;
                }
                byte => {
                    out.push(byte);
                    index += 1;
                }
            }
        }
        String::from_utf8_lossy(&out).to_string()
    }
}
