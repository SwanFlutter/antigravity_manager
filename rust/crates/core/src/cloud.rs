//! The cloud account domain: credentials, quota groups, proxy configuration
//! and the traffic log.
//!
//! These types describe the state of the connected Google accounts and of the
//! local API proxy. They stay free of HTTP, SQLite and operating system
//! dependencies so the rules can be tested on their own.

use futures::future::BoxFuture;
use serde::{Deserialize, Serialize};

use crate::repository::RepositoryError;

/// The account a proxy request is charged to.
#[derive(Debug, Clone, PartialEq)]
pub struct AccountLease {
    pub account_id: String,
    pub email: String,
    pub access_token: String,
    pub project_id: Option<String>,
}

/// Hands out the account a proxy request is charged to.
///
/// The implementation refreshes an expired access token before it answers, so
/// the transport never has to know about token lifetimes.
pub trait LeaseProvider: Send + Sync {
    /// The account of the next request.
    fn lease(&self) -> BoxFuture<'_, Result<AccountLease, RepositoryError>>;
}

/// Formats a reset timestamp the way the interface shows it.
///
/// The format follows the upstream application: `42m`, `4h 12m`, `1d 08h`.
pub fn format_reset_label(reset_at: Option<i64>, now_millis: i64) -> String {
    let Some(reset_at) = reset_at else {
        return "—".to_string();
    };

    let delta_minutes = ((reset_at - now_millis) / 60_000).max(0);
    let days = delta_minutes / (60 * 24);
    let hours = (delta_minutes % (60 * 24)) / 60;
    let minutes = delta_minutes % 60;

    if days > 0 {
        format!("{days}d {hours:02}h")
    } else if hours > 0 {
        format!("{hours}h {minutes:02}m")
    } else {
        format!("{minutes}m")
    }
}

/// The credentials of one connected Google account.
///
/// The tokens are never sent to the UI: only the host reads them.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct AccountCredentials {
    pub account_id: String,
    pub access_token: String,
    #[serde(default)]
    pub refresh_token: Option<String>,
    /// Expiry of the access token in milliseconds since the Unix epoch.
    #[serde(default)]
    pub expiry_timestamp: Option<i64>,
    pub email: String,
    #[serde(default)]
    pub project_id: Option<String>,
    #[serde(default)]
    pub plan: Option<String>,
    #[serde(default)]
    pub credits: Option<i64>,
    /// The OAuth client the account was authorized with.
    #[serde(default)]
    pub oauth_client_key: Option<String>,
}

impl AccountCredentials {
    /// Whether the access token is expired or about to expire.
    pub fn needs_refresh(&self, now_millis: i64) -> bool {
        match self.expiry_timestamp {
            Some(expiry) => expiry - now_millis < 300_000,
            None => false,
        }
    }
}

/// One quota bucket of a group.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct QuotaBucket {
    pub bucket_id: String,
    /// The window of the bucket, for example `5h` or `week`.
    pub window: String,
    /// Remaining share between 0.0 and 1.0.
    pub remaining: f64,
    /// When the bucket resets, in milliseconds since the Unix epoch.
    #[serde(default)]
    pub reset_at: Option<i64>,
    pub label: String,
}

impl QuotaBucket {
    /// Whether the bucket belongs to the weekly window.
    pub fn is_weekly(&self) -> bool {
        self.window.to_lowercase().contains("week")
            || self.bucket_id.to_lowercase().contains("week")
    }
}

/// A group of buckets that share one allowance.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct QuotaGroup {
    pub id: String,
    pub label: String,
    pub buckets: Vec<QuotaBucket>,
}

impl QuotaGroup {
    /// The remaining share of the weekly bucket of this group.
    pub fn weekly_remaining(&self) -> Option<f64> {
        self.buckets
            .iter()
            .find(|bucket| bucket.is_weekly())
            .map(|bucket| bucket.remaining)
    }

    /// When the weekly bucket resets, in milliseconds since the Unix epoch.
    pub fn weekly_reset_at(&self) -> Option<i64> {
        self.buckets
            .iter()
            .find(|bucket| bucket.is_weekly())
            .and_then(|bucket| bucket.reset_at)
    }
}

/// The state of the local API proxy.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct ProxyConfig {
    /// Whether the proxy starts with the host.
    pub auto_start: bool,
    /// The port the proxy listens on.
    pub port: u16,
    /// The key the clients send. Without a key the proxy accepts every request.
    #[serde(default)]
    pub api_key: Option<String>,
    /// The account the proxy charges.
    #[serde(default)]
    pub selected_account_id: Option<String>,
}

impl Default for ProxyConfig {
    fn default() -> Self {
        Self {
            auto_start: false,
            port: 8045,
            api_key: None,
            selected_account_id: None,
        }
    }
}

impl ProxyConfig {
    /// The base URL a coding tool talks to.
    pub fn base_url(&self) -> String {
        format!("http://127.0.0.1:{}", self.port)
    }

    /// A new key in the format of the upstream application.
    pub fn generate_key() -> String {
        format!("sk-{}", uuid_like())
    }
}

/// Creates a random hexadecimal string of 32 characters.
fn uuid_like() -> String {
    use std::time::{SystemTime, UNIX_EPOCH};

    let nanos = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|value| value.as_nanos())
        .unwrap_or(0);

    let mut state = nanos as u64 ^ (std::process::id() as u64).wrapping_mul(0x9E37_79B9_7F4A_7C15);
    let mut out = String::with_capacity(32);

    for _ in 0..4 {
        state = state
            .wrapping_mul(6_364_136_223_846_793_005)
            .wrapping_add(1_442_695_040_888_963_407);
        out.push_str(&format!("{:016x}", state));
        if out.len() >= 32 {
            break;
        }
    }

    out.truncate(32);
    out
}

/// The protocol a proxy request used.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum ProxyProtocol {
    Openai,
    Anthropic,
}

impl ProxyProtocol {
    pub fn as_str(&self) -> &'static str {
        match self {
            ProxyProtocol::Openai => "openai",
            ProxyProtocol::Anthropic => "anthropic",
        }
    }
}

/// One request that passed through the proxy.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct TrafficEntry {
    pub id: i64,
    /// When the request arrived, in milliseconds since the Unix epoch.
    pub at: i64,
    pub protocol: String,
    pub model: String,
    #[serde(default)]
    pub account_id: Option<String>,
    pub status: u16,
    pub duration_ms: u64,
    pub request_bytes: u64,
    pub response_bytes: u64,
    #[serde(default)]
    pub error: Option<String>,
}

/// The state of an OAuth session.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum ConnectStatus {
    /// The browser has not answered yet.
    Pending,
    /// The account was added.
    Completed,
    /// The session failed.
    Failed,
    /// The session timed out.
    Expired,
}

impl ConnectStatus {
    pub fn as_str(&self) -> &'static str {
        match self {
            ConnectStatus::Pending => "pending",
            ConnectStatus::Completed => "completed",
            ConnectStatus::Failed => "failed",
            ConnectStatus::Expired => "expired",
        }
    }
}
