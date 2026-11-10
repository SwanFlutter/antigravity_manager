//! The versioned application contract shared by the Flutter UI and the Rust core.
//!
//! The transport is a private named pipe carrying JSON-RPC 2.0. Every payload is
//! validated on the receiving side, so the generated or hand written Dart
//! bindings are never treated as a trust boundary on their own.

use serde::{Deserialize, Serialize};
use serde_json::Value;

/// Version of the application contract implemented by this crate.
///
/// The Dart side refuses to talk to a host that reports a different version.
pub const CONTRACT_VERSION: u32 = 1;

/// Name of the private Windows named pipe used by the desktop host.
pub const PIPE_NAME: &str = "antigravity-manager-host";

/// JSON-RPC version string used by every message.
pub const JSONRPC_VERSION: &str = "2.0";

/// A JSON-RPC request.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Request {
    pub jsonrpc: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub id: Option<Value>,
    pub method: String,
    #[serde(default, skip_serializing_if = "Value::is_null")]
    pub params: Value,
}

impl Request {
    pub fn new(id: Option<Value>, method: impl Into<String>, params: Value) -> Self {
        Self {
            jsonrpc: JSONRPC_VERSION.to_string(),
            id,
            method: method.into(),
            params,
        }
    }
}

/// A JSON-RPC response. Exactly one of `result` and `error` is set.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Response {
    pub jsonrpc: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub id: Option<Value>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub result: Option<Value>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub error: Option<RpcError>,
}

impl Response {
    pub fn ok(id: Option<Value>, result: Value) -> Self {
        Self {
            jsonrpc: JSONRPC_VERSION.to_string(),
            id,
            result: Some(result),
            error: None,
        }
    }

    pub fn err(id: Option<Value>, error: RpcError) -> Self {
        Self {
            jsonrpc: JSONRPC_VERSION.to_string(),
            id,
            result: None,
            error: Some(error),
        }
    }
}

/// The error envelope. `code` is stable, `message` is for humans and may be
/// localized later, `data` carries sanitized diagnostics only.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct RpcError {
    pub code: i64,
    pub message: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub data: Option<Value>,
}

impl RpcError {
    pub fn new(code: i64, message: impl Into<String>) -> Self {
        Self {
            code,
            message: message.into(),
            data: None,
        }
    }

    pub fn with_data(mut self, data: Value) -> Self {
        self.data = Some(data);
        self
    }
}

/// Stable error codes shared by both sides of the contract.
pub mod error_codes {
    /// The request could not be parsed or violated the contract shape.
    pub const INVALID_REQUEST: i64 = -32600;
    /// The method does not exist in this contract version.
    pub const METHOD_NOT_FOUND: i64 = -32601;
    /// The parameters of the method are invalid.
    pub const INVALID_PARAMS: i64 = -32602;
    /// The host speaks a different contract version.
    pub const VERSION_MISMATCH: i64 = -32000;
    /// A domain rule rejected the operation.
    pub const VALIDATION: i64 = -32001;
    /// Persistence failed.
    pub const PERSISTENCE: i64 = -32002;
    /// A required dependency is not available (network, credential, process).
    pub const UNAVAILABLE: i64 = -32003;
    /// The operation was cancelled by the caller.
    pub const CANCELLED: i64 = -32004;
}

/// Data transfer objects exchanged over the pipe.
///
/// The field names are camelCase so the Dart side can use them directly.
pub mod dto {
    use super::{Deserialize, Serialize};

    /// Lifecycle state of an account.
    #[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
    #[serde(rename_all = "camelCase")]
    pub enum AccountStatusDto {
        Active,
        Idle,
        RateLimited,
        Error,
    }

    /// The provider family a model belongs to.
    #[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
    #[serde(rename_all = "camelCase")]
    pub enum ModelFamilyDto {
        Gemini,
        Claude,
        Openai,
    }

    /// One model quota inside a five hour window.
    #[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
    #[serde(rename_all = "camelCase")]
    pub struct ModelQuotaDto {
        pub name: String,
        pub family: ModelFamilyDto,
        /// Remaining share between 0.0 and 1.0.
        pub remaining: f64,
        /// Human readable reset time, for example `4h 12m`.
        pub reset_label: String,
    }

    /// The weekly allowance of one model group.
    #[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
    #[serde(rename_all = "camelCase")]
    pub struct WeeklyQuotaDto {
        pub group_id: String,
        pub group_label: String,
        pub remaining: f64,
        pub reset_label: String,
    }

    /// A model the gateway can route to.
    #[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
    #[serde(rename_all = "camelCase")]
    pub struct ModelDto {
        pub id: String,
        pub label: String,
        pub family: ModelFamilyDto,
    }

    /// A provider account.
    #[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
    #[serde(rename_all = "camelCase")]
    pub struct AccountDto {
        pub id: String,
        pub name: String,
        pub handle: String,
        pub provider: String,
        pub plan: String,
        pub status: AccountStatusDto,
        pub credits: i64,
        pub in_use: bool,
        pub recommended: bool,
        /// Whether the account belongs to the synthetic dataset.
        #[serde(default)]
        pub demo: bool,
        pub quotas: Vec<ModelQuotaDto>,
        pub weekly_quotas: Vec<WeeklyQuotaDto>,
    }

    /// Aggregate counters shown above the account list.
    #[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
    #[serde(rename_all = "camelCase")]
    pub struct AccountSummaryDto {
        pub total: u64,
        pub active: u64,
        pub rate_limited: u64,
        /// Average remaining quota across every account and model.
        pub global_remaining: f64,
    }

    /// The account list plus its aggregate counters.
    #[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
    #[serde(rename_all = "camelCase")]
    pub struct AccountListDto {
        pub accounts: Vec<AccountDto>,
        pub summary: AccountSummaryDto,
    }

    /// Host health and contract information.
    #[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
    #[serde(rename_all = "camelCase")]
    pub struct HostInfoDto {
        pub contract_version: u32,
        pub app_version: String,
        pub profile_path: String,
    }

    /// An OAuth session that waits for the browser to come back.
    #[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
    #[serde(rename_all = "camelCase")]
    pub struct ConnectSessionDto {
        pub session_id: String,
        pub authorization_url: String,
        pub redirect_uri: String,
        /// When the session expires, in milliseconds since the Unix epoch.
        pub expires_at: i64,
    }

    /// The state of an OAuth session.
    #[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
    #[serde(rename_all = "camelCase")]
    pub struct ConnectStatusDto {
        /// `pending`, `completed`, `failed` or `expired`.
        pub status: String,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        pub email: Option<String>,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        pub error: Option<String>,
    }

    /// An account that is connected with real credentials.
    #[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
    #[serde(rename_all = "camelCase")]
    pub struct ConnectedAccountDto {
        pub account_id: String,
        pub email: String,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        pub plan: Option<String>,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        pub project_id: Option<String>,
    }

    /// The state of the local API proxy.
    #[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
    #[serde(rename_all = "camelCase")]
    pub struct ProxyStatusDto {
        pub running: bool,
        pub port: u16,
        pub base_url: String,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        pub api_key: Option<String>,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        pub selected_account_id: Option<String>,
        pub models: usize,
    }

    /// A workspace profile of the upstream installation.
    #[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
    #[serde(rename_all = "camelCase")]
    pub struct WorkspaceDto {
        pub id: String,
        pub name: String,
        pub account_id: String,
        /// Display name of the account the workspace belongs to.
        pub account_name: String,
        pub plan: String,
        pub project_folder: String,
        pub profile_folder: String,
        /// Last launch in milliseconds since the Unix epoch.
        pub last_active_at: i64,
        /// `idle`, `running` or `stopped`.
        pub state: String,
        /// Whether the account of the workspace has no credentials anymore.
        #[serde(default)]
        pub unbound: bool,
    }

    /// One request that passed through the local proxy.
    #[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
    #[serde(rename_all = "camelCase")]
    pub struct TrafficEntryDto {
        pub id: i64,
        pub at: i64,
        pub protocol: String,
        pub model: String,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        pub account_id: Option<String>,
        pub status: u16,
        pub duration_ms: u64,
        pub request_bytes: u64,
        pub response_bytes: u64,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        pub error: Option<String>,
    }
}

/// The methods the host implements in contract version 1.
pub mod methods {
    /// Returns the contract version, app version and the active profile path.
    pub const HOST_INFO: &str = "host.info";
    /// Returns every account with its quota windows and the aggregate counters.
    pub const ACCOUNTS_LIST: &str = "accounts.list";
    /// Marks one account as the account used by the desktop clients.
    pub const ACCOUNTS_SET_ACTIVE: &str = "accounts.setActive";
    /// Adds or removes an account from the selection.
    pub const ACCOUNTS_SET_SELECTED: &str = "accounts.setSelected";
    /// Returns the catalog of models the gateway can route to.
    pub const MODELS_CATALOG: &str = "models.catalog";

    // --- Cloud accounts -------------------------------------------------

    /// Starts an OAuth session and returns the URL the browser has to open.
    pub const ACCOUNTS_START_CONNECT: &str = "accounts.startConnect";
    /// Reads the state of an OAuth session.
    pub const ACCOUNTS_CONNECT_STATUS: &str = "accounts.connectStatus";
    /// Finishes an OAuth session with a code the user copied by hand.
    pub const ACCOUNTS_SUBMIT_CODE: &str = "accounts.submitCode";
    /// Refreshes the quota of one account from the provider.
    pub const ACCOUNTS_REFRESH_QUOTA: &str = "accounts.refreshQuota";
    /// Removes one account with its credentials.
    pub const ACCOUNTS_REMOVE: &str = "accounts.remove";
    /// Lists the accounts that are connected with real credentials.
    pub const ACCOUNTS_CONNECTED: &str = "accounts.connected";

    // --- Local API proxy -------------------------------------------------

    /// Reads the state of the local proxy.
    pub const PROXY_STATUS: &str = "proxy.status";
    /// Starts the local proxy.
    pub const PROXY_START: &str = "proxy.start";
    /// Stops the local proxy.
    pub const PROXY_STOP: &str = "proxy.stop";
    /// Replaces the key of the local proxy.
    pub const PROXY_ROTATE_KEY: &str = "proxy.rotateKey";

    // --- Traffic ---------------------------------------------------------

    /// The newest requests that passed through the local proxy.
    pub const TRAFFIC_LIST: &str = "traffic.list";

    // --- Workspaces ------------------------------------------------------

    /// The workspace profiles of the connected accounts.
    pub const WORKSPACES_LIST: &str = "workspaces.list";
}
