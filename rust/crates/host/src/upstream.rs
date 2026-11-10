//! Imports the real data of the upstream Antigravity Manager installation.
//!
//! The upstream Electron application stores its connected Google accounts in
//! `~/.antigravity-agent/cloud_accounts.db`. The desktop host reads that file
//! at startup and copies the accounts, their credentials, their quota, the
//! model catalog and the workspace profiles into its own profile, so the
//! interface shows the real account pool instead of the synthetic demo
//! dataset. The upstream file is opened read-only and is never modified.

use std::path::PathBuf;

use antigravity_core::cloud::{format_reset_label, AccountCredentials, ProxyConfig};
use antigravity_core::demo;
use antigravity_core::domain::{
    Account, AccountStatus, Model, ModelQuota, WeeklyQuota, Workspace, WorkspaceState,
};
use antigravity_core::repository::{AccountRepository, CloudRepository};
use antigravity_core::sqlite::SqliteAccountRepository;
use antigravity_google::mapping::slugify;
use antigravity_google::{model_family_for, parse_rfc3339_millis};
use rusqlite::{Connection, OpenFlags};
use serde_json::Value;

/// The account database of the upstream installation, when it exists.
fn upstream_db_path() -> Option<PathBuf> {
    let home = std::env::var_os("USERPROFILE").or_else(|| std::env::var_os("HOME"))?;
    let path = PathBuf::from(home)
        .join(".antigravity-agent")
        .join("cloud_accounts.db");
    path.exists().then_some(path)
}

/// One row of the `accounts` table of the upstream database.
struct UpstreamAccount {
    id: String,
    email: String,
    name: Option<String>,
    is_active: bool,
    tokens: Value,
    quota: Value,
}

/// Imports every real account of the upstream installation into the profile.
///
/// Returns the number of imported accounts. When the upstream database does
/// not exist, nothing is imported and `0` is returned.
pub fn import_upstream(repository: &SqliteAccountRepository, now: i64) -> Result<usize, String> {
    let Some(path) = upstream_db_path() else {
        return Ok(0);
    };

    let connection = Connection::open_with_flags(&path, OpenFlags::SQLITE_OPEN_READ_ONLY)
        .map_err(|error| format!("cannot open {}: {error}", path.display()))?;

    let accounts = read_accounts(&connection)?;
    if accounts.is_empty() {
        return Ok(0);
    }

    let mut catalog: Vec<Model> = Vec::new();
    let mut imported = Vec::with_capacity(accounts.len());

    for upstream in &accounts {
        let Some(credentials) = credentials_of(upstream) else {
            continue;
        };
        let (quotas, weekly, plan, credits) = quota_of(upstream, now);
        let active = upstream.is_active;

        repository
            .save_credentials(&credentials)
            .map_err(|error| error.to_string())?;

        let account = Account {
            id: upstream.id.clone(),
            name: upstream
                .name
                .clone()
                .filter(|name| !name.is_empty())
                .unwrap_or_else(|| upstream.email.split('@').next().unwrap_or("Google").to_string()),
            handle: upstream.email.clone(),
            provider: "Google".to_string(),
            plan: plan.unwrap_or_else(|| "Google AI".to_string()),
            status: if active {
                AccountStatus::Active
            } else {
                AccountStatus::Idle
            },
            credits,
            in_use: active,
            recommended: active,
            selected: false,
            // An imported account is a real account, never a sample.
            demo: false,
            quotas,
            weekly_quotas: weekly,
        };
        repository
            .save_account(&account)
            .map_err(|error| error.to_string())?;
        imported.push(account);

        for model in models_of(&upstream.quota) {
            if !catalog.iter().any(|entry| entry.id == model.id) {
                catalog.push(model);
            }
        }
    }

    if !catalog.is_empty() {
        // The real catalog replaces the synthetic one of an earlier demo seed.
        repository
            .clear_catalog()
            .map_err(|error| error.to_string())?;
        repository
            .save_catalog(&catalog, &demo::model_groups())
            .map_err(|error| error.to_string())?;
    }

    let workspaces = read_workspaces(&connection);
    repository
        .save_workspaces(&workspaces)
        .map_err(|error| error.to_string())?;

    ensure_proxy_config(repository, &imported)?;

    Ok(imported.len())
}

/// Reads the accounts of the upstream database.
fn read_accounts(connection: &Connection) -> Result<Vec<UpstreamAccount>, String> {
    let mut statement = connection
        .prepare(
            "SELECT id, email, name, is_active, token_json, quota_json FROM accounts ORDER BY last_used DESC",
        )
        .map_err(|error| format!("cannot read the upstream accounts: {error}"))?;

    let rows = statement
        .query_map([], |row| {
            Ok(UpstreamAccount {
                id: row.get(0)?,
                email: row.get(1)?,
                name: row.get(2)?,
                is_active: row.get::<_, i64>(3)? != 0,
                tokens: serde_json::from_str(&row.get::<_, String>(4)?).unwrap_or(Value::Null),
                quota: serde_json::from_str(&row.get::<_, Option<String>>(5)?.unwrap_or_default())
                    .unwrap_or(Value::Null),
            })
        })
        .map_err(|error| error.to_string())?
        .collect::<Result<Vec<_>, _>>()
        .map_err(|error| error.to_string())?;

    Ok(rows)
}

/// Reads the workspace profiles of the upstream database.
///
/// A missing table is not an error: older installations have no workspaces.
fn read_workspaces(connection: &Connection) -> Vec<Workspace> {
    let mut statement = match connection.prepare(
        "SELECT id, name, account_id, project_path, user_data_dir, last_launched_at
         FROM workspace_profiles",
    ) {
        Ok(statement) => statement,
        Err(_) => return Vec::new(),
    };

    statement
        .query_map([], |row| {
            Ok(Workspace {
                id: row.get(0)?,
                name: row.get(1)?,
                account_id: row.get(2)?,
                project_folder: row.get(3)?,
                profile_folder: row.get(4)?,
                last_active_at: row.get::<_, i64>(5).unwrap_or(0),
                // The upstream installation does not track a running state.
                state: WorkspaceState::Idle,
            })
        })
        .map(|rows| {
            rows.filter_map(|row| row.ok())
                .collect::<Vec<_>>()
        })
        .unwrap_or_default()
}

/// Builds the credentials out of the stored token JSON.
fn credentials_of(upstream: &UpstreamAccount) -> Option<AccountCredentials> {
    let access_token = upstream
        .tokens
        .get("access_token")
        .and_then(Value::as_str)
        .map(str::trim)
        .filter(|token| !token.is_empty())?
        .to_string();

    Some(AccountCredentials {
        account_id: upstream.id.clone(),
        access_token,
        refresh_token: upstream
            .tokens
            .get("refresh_token")
            .and_then(Value::as_str)
            .map(str::trim)
            .filter(|token| !token.is_empty())
            .map(str::to_string),
        expiry_timestamp: upstream
            .tokens
            .get("expiry_timestamp")
            .and_then(Value::as_i64)
            .or_else(|| {
                upstream
                    .tokens
                    .get("expires_in")
                    .and_then(Value::as_i64)
                    .map(|seconds| now_millis() + seconds * 1_000)
            }),
        email: upstream
            .tokens
            .get("email")
            .and_then(Value::as_str)
            .map(str::trim)
            .filter(|email| !email.is_empty())
            .unwrap_or(&upstream.email)
            .to_string(),
        project_id: upstream
            .tokens
            .get("project_id")
            .and_then(Value::as_str)
            .map(str::trim)
            .filter(|project| !project.is_empty())
            .map(str::to_string),
        plan: None,
        credits: None,
        oauth_client_key: upstream
            .tokens
            .get("oauth_client_key")
            .and_then(Value::as_str)
            .map(str::to_string),
    })
}

/// Builds the quotas, the weekly allowances, the plan and the credits out of
/// the stored quota JSON of the upstream installation.
fn quota_of(
    upstream: &UpstreamAccount,
    now: i64,
) -> (Vec<ModelQuota>, Vec<WeeklyQuota>, Option<String>, i64) {
    let quota = &upstream.quota;

    // The display name of a model is not unique, the quota table is keyed by
    // the name, so a repeated display name falls back to the model id.
    let mut seen_names: Vec<String> = Vec::new();
    let quotas = models_of(quota)
        .into_iter()
        .map(|model| {
            let info = &quota["models"][&model.id];
            let remaining = info
                .get("percentage")
                .and_then(Value::as_f64)
                .unwrap_or(0.0)
                / 100.0;
            let reset_at = info
                .get("resetTime")
                .and_then(Value::as_str)
                .and_then(parse_rfc3339_millis);
            let name = if seen_names.contains(&model.label) {
                model.id.clone()
            } else {
                seen_names.push(model.label.clone());
                model.label
            };
            ModelQuota {
                name,
                family: model.family,
                remaining: remaining.clamp(0.0, 1.0),
                reset_label: format_reset_label(reset_at, now),
            }
        })
        .collect();

    let weekly = quota
        .get("quota_groups")
        .and_then(Value::as_array)
        .map(|groups| {
            groups
                .iter()
                .filter_map(|group| {
                    let display_name = group.get("display_name").and_then(Value::as_str)?;
                    let lowered = display_name.to_lowercase();
                    let group_id = if lowered.contains("gemini") {
                        "gemini".to_string()
                    } else if lowered.contains("claude") || lowered.contains("gpt") {
                        "claudeGpt".to_string()
                    } else {
                        slugify(display_name)
                    };
                    let bucket = group
                        .get("buckets")
                        .and_then(Value::as_array)?
                        .iter()
                        .find(|bucket| {
                            bucket
                                .get("window")
                                .and_then(Value::as_str)
                                .unwrap_or_default()
                                .to_lowercase()
                                .contains("week")
                        })?;
                    let remaining = bucket
                        .get("remaining_fraction")
                        .and_then(Value::as_f64)
                        .unwrap_or(0.0);
                    let reset_at = bucket
                        .get("reset_time")
                        .and_then(Value::as_str)
                        .and_then(parse_rfc3339_millis);
                    Some(WeeklyQuota {
                        group_id,
                        group_label: display_name.to_string(),
                        remaining: remaining.clamp(0.0, 1.0),
                        reset_label: format_reset_label(reset_at, now),
                    })
                })
                .collect()
        })
        .unwrap_or_default();

    let plan = quota
        .get("subscription_tier")
        .and_then(Value::as_str)
        .map(str::to_string);

    let credits = quota
        .get("ai_credits")
        .and_then(|credits| credits.get("credits"))
        .and_then(Value::as_i64)
        .unwrap_or(0);

    (quotas, weekly, plan, credits)
}

/// The models of the stored quota JSON, mapped onto the catalog.
fn models_of(quota: &Value) -> Vec<Model> {
    let Some(models) = quota.get("models").and_then(Value::as_object) else {
        return Vec::new();
    };

    // The display name of a model is not unique, so a repeated display name
    // falls back to the model id to keep every catalog entry distinguishable.
    let mut seen_labels: Vec<String> = Vec::new();
    models
        .iter()
        .filter_map(|(id, info)| {
            let family = model_family_for(id)?;
            let display = info
                .get("display_name")
                .and_then(Value::as_str)
                .map(str::trim)
                .filter(|name| !name.is_empty())
                .unwrap_or(id.as_str())
                .to_string();
            let label = if seen_labels.contains(&display) {
                id.clone()
            } else {
                seen_labels.push(display.clone());
                display
            };
            Some(Model {
                id: id.clone(),
                label,
                family,
            })
        })
        .collect()
}

/// Makes sure the proxy has a key and a selected account.
///
/// A proxy with a key is reachable from the coding tools, so the first import
/// generates the key and starts the proxy with the host. The selected account
/// is the account the upstream installation marked as active.
fn ensure_proxy_config(
    repository: &SqliteAccountRepository,
    imported: &[Account],
) -> Result<(), String> {
    let mut config = repository
        .load_proxy_config()
        .map_err(|error| error.to_string())?;
    let mut changed = false;

    if config.api_key.as_deref().map_or(true, str::is_empty) {
        config.api_key = Some(ProxyConfig::generate_key());
        config.auto_start = true;
        changed = true;
    }

    if config.selected_account_id.is_none() {
        config.selected_account_id = imported
            .iter()
            .find(|account| account.in_use)
            .or_else(|| imported.first())
            .map(|account| account.id.clone());
        changed = true;
    }

    if changed {
        repository
            .save_proxy_config(&config)
            .map_err(|error| error.to_string())?;
    }

    Ok(())
}

/// The current time in milliseconds since the Unix epoch.
fn now_millis() -> i64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|value| value.as_millis() as i64)
        .unwrap_or(0)
}
