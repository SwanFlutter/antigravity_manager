//! Domain model of Antigravity Manager.
//!
//! These types are free of Flutter, Windows, SQLite, HTTP and process
//! dependencies so the rules can be unit tested on their own.

/// Lifecycle state of an account.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum AccountStatus {
    Active,
    Idle,
    RateLimited,
    Error,
}

impl AccountStatus {
    pub fn as_str(&self) -> &'static str {
        match self {
            AccountStatus::Active => "active",
            AccountStatus::Idle => "idle",
            AccountStatus::RateLimited => "rateLimited",
            AccountStatus::Error => "error",
        }
    }

    pub fn parse(value: &str) -> Option<Self> {
        match value {
            "active" => Some(AccountStatus::Active),
            "idle" => Some(AccountStatus::Idle),
            "rateLimited" => Some(AccountStatus::RateLimited),
            "error" => Some(AccountStatus::Error),
            _ => None,
        }
    }
}

/// The provider family a model belongs to.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ModelFamily {
    Gemini,
    Claude,
    Openai,
}

impl ModelFamily {
    pub fn as_str(&self) -> &'static str {
        match self {
            ModelFamily::Gemini => "gemini",
            ModelFamily::Claude => "claude",
            ModelFamily::Openai => "openai",
        }
    }

    pub fn parse(value: &str) -> Option<Self> {
        match value {
            "gemini" => Some(ModelFamily::Gemini),
            "claude" => Some(ModelFamily::Claude),
            "openai" => Some(ModelFamily::Openai),
            _ => None,
        }
    }
}

/// One model quota inside a five hour window.
#[derive(Debug, Clone, PartialEq)]
pub struct ModelQuota {
    pub name: String,
    pub family: ModelFamily,
    /// Remaining share between 0.0 and 1.0.
    pub remaining: f64,
    /// Human readable reset time, for example `4h 12m`.
    pub reset_label: String,
}

/// The weekly allowance of one model group.
#[derive(Debug, Clone, PartialEq)]
pub struct WeeklyQuota {
    pub group_id: String,
    pub group_label: String,
    pub remaining: f64,
    pub reset_label: String,
}

/// A model the gateway can route to.
#[derive(Debug, Clone, PartialEq)]
pub struct Model {
    pub id: String,
    pub label: String,
    pub family: ModelFamily,
}

/// A group of models that share one weekly allowance.
#[derive(Debug, Clone, PartialEq)]
pub struct ModelGroup {
    pub id: String,
    pub label: String,
    pub families: Vec<ModelFamily>,
}

/// A provider account.
#[derive(Debug, Clone, PartialEq)]
pub struct Account {
    pub id: String,
    pub name: String,
    pub handle: String,
    pub provider: String,
    pub plan: String,
    pub status: AccountStatus,
    pub credits: i64,
    pub in_use: bool,
    pub recommended: bool,
    pub selected: bool,
    /// Whether the account belongs to the synthetic dataset.
    ///
    /// The interface marks those accounts, so a real account is never
    /// confused with the sample data of a fresh profile.
    pub demo: bool,
    /// Last successful model fetch, in Unix milliseconds; None denotes an undated cache.
    pub quota_fetched_at: Option<i64>,
    /// Sanitized model-sync failure or weekly-sync warning.
    pub quota_error: Option<String>,
    pub quotas: Vec<ModelQuota>,
    pub weekly_quotas: Vec<WeeklyQuota>,
}

impl Account {
    /// Average remaining quota across every model quota of this account.
    pub fn remaining_share(&self) -> f64 {
        if self.quotas.is_empty() {
            return 0.0;
        }
        let total: f64 = self.quotas.iter().map(|q| q.remaining).sum();
        total / self.quotas.len() as f64
    }
}

/// Lifecycle state of a workspace profile.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum WorkspaceState {
    Idle,
    Running,
    Stopped,
}

impl WorkspaceState {
    pub fn as_str(&self) -> &'static str {
        match self {
            WorkspaceState::Idle => "idle",
            WorkspaceState::Running => "running",
            WorkspaceState::Stopped => "stopped",
        }
    }

    pub fn parse(value: &str) -> Option<Self> {
        match value {
            "running" => Some(WorkspaceState::Running),
            "stopped" => Some(WorkspaceState::Stopped),
            "idle" => Some(WorkspaceState::Idle),
            _ => None,
        }
    }
}

/// A workspace profile, imported from the upstream installation.
#[derive(Debug, Clone, PartialEq)]
pub struct Workspace {
    pub id: String,
    pub name: String,
    pub account_id: String,
    pub project_folder: String,
    pub profile_folder: String,
    /// Last launch in milliseconds since the Unix epoch.
    pub last_active_at: i64,
    pub state: WorkspaceState,
}

/// Aggregate counters shown above the account list.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct AccountSummary {
    pub total: u64,
    pub active: u64,
    pub rate_limited: u64,
    pub global_remaining: f64,
}

/// Computes the aggregate counters for a list of accounts.
pub fn summarize(accounts: &[Account]) -> AccountSummary {
    let total = accounts.len() as u64;
    let active = accounts
        .iter()
        .filter(|a| a.status == AccountStatus::Active)
        .count() as u64;
    let rate_limited = accounts
        .iter()
        .filter(|a| a.status == AccountStatus::RateLimited)
        .count() as u64;

    let global_remaining = if accounts.is_empty() {
        0.0
    } else {
        let total: f64 = accounts.iter().map(|a| a.remaining_share()).sum();
        total / accounts.len() as f64
    };

    AccountSummary {
        total,
        active,
        rate_limited,
        global_remaining,
    }
}
