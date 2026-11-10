//! The SQLite backed account repository.
//!
//! The schema is versioned through `schema_version`. Every migration runs
//! inside a transaction so an interrupted upgrade never leaves a half applied
//! profile behind.
//!
//! The connection lives behind a mutex: SQLite connections are not `Sync`, and
//! the host serves the contract from several tasks.

use std::sync::{Mutex, MutexGuard};

use crate::cloud::{AccountCredentials, ProxyConfig, TrafficEntry};
use crate::domain::{
    Account, AccountStatus, Model, ModelFamily, ModelGroup, ModelQuota, WeeklyQuota, Workspace,
    WorkspaceState,
};
use crate::repository::{AccountRepository, CloudRepository, RepositoryError};

use rusqlite::{params, Connection, OptionalExtension};

/// The schema version this build understands.
pub const SCHEMA_VERSION: i64 = 4;

fn storage<E: std::fmt::Display>(error: E) -> RepositoryError {
    RepositoryError::Storage(error.to_string())
}

/// A repository backed by a SQLite file or an in memory database.
pub struct SqliteAccountRepository {
    connection: Mutex<Connection>,
}

impl SqliteAccountRepository {
    /// Opens a repository on the given path and applies the migrations.
    ///
    /// Pass `:memory:` for a temporary database.
    pub fn open(path: &str) -> Result<Self, RepositoryError> {
        let connection = Connection::open(path).map_err(storage)?;
        let repository = Self {
            connection: Mutex::new(connection),
        };
        repository.migrate()?;
        Ok(repository)
    }

    /// Locks the connection.
    ///
    /// A poisoned lock is recovered instead of propagated: the database file
    /// stays consistent because every write runs inside a transaction.
    fn lock(&self) -> MutexGuard<'_, Connection> {
        match self.connection.lock() {
            Ok(guard) => guard,
            Err(poisoned) => poisoned.into_inner(),
        }
    }

    /// Applies every pending migration.
    pub fn migrate(&self) -> Result<(), RepositoryError> {
        let connection = self.lock();

        connection
            .execute_batch(
                "CREATE TABLE IF NOT EXISTS schema_version (
                    version INTEGER NOT NULL
                );",
            )
            .map_err(storage)?;

        let current: i64 = connection
            .query_row(
                "SELECT COALESCE(MAX(version), 0) FROM schema_version",
                [],
                |row| row.get(0),
            )
            .map_err(storage)?;

        if current > SCHEMA_VERSION {
            return Err(RepositoryError::Invalid(format!(
                "profile schema {current} is newer than the supported version {SCHEMA_VERSION}"
            )));
        }

        if current < 1 {
            connection
                .execute_batch(
                    "BEGIN;
                     CREATE TABLE models (
                         id     TEXT PRIMARY KEY,
                         label  TEXT NOT NULL,
                         family TEXT NOT NULL
                     );
                     CREATE TABLE model_groups (
                         id    TEXT PRIMARY KEY,
                         label TEXT NOT NULL
                     );
                     CREATE TABLE model_group_families (
                         group_id TEXT NOT NULL,
                         family   TEXT NOT NULL,
                         PRIMARY KEY (group_id, family)
                     );
                     CREATE TABLE accounts (
                         id          TEXT PRIMARY KEY,
                         name        TEXT NOT NULL,
                         handle      TEXT NOT NULL,
                         provider    TEXT NOT NULL,
                         plan        TEXT NOT NULL,
                         status      TEXT NOT NULL,
                         credits     INTEGER NOT NULL,
                         in_use      INTEGER NOT NULL,
                         recommended INTEGER NOT NULL,
                         selected    INTEGER NOT NULL,
                         position    INTEGER NOT NULL
                     );
                     CREATE TABLE model_quotas (
                         account_id  TEXT NOT NULL,
                         model_name  TEXT NOT NULL,
                         family      TEXT NOT NULL,
                         remaining   REAL NOT NULL,
                         reset_label TEXT NOT NULL,
                         PRIMARY KEY (account_id, model_name)
                     );
                     CREATE TABLE weekly_quotas (
                         account_id  TEXT NOT NULL,
                         group_id    TEXT NOT NULL,
                         remaining   REAL NOT NULL,
                         reset_label TEXT NOT NULL,
                         PRIMARY KEY (account_id, group_id)
                     );
                     INSERT INTO schema_version (version) VALUES (1);
                     COMMIT;",
                )
                .map_err(storage)?;
        }

        if current < 2 {
            connection
                .execute_batch(
                    "BEGIN;
                     CREATE TABLE account_credentials (
                         account_id        TEXT PRIMARY KEY,
                         access_token      TEXT NOT NULL,
                         refresh_token     TEXT,
                         expiry_timestamp  INTEGER,
                         email             TEXT NOT NULL,
                         project_id        TEXT,
                         plan              TEXT,
                         credits           INTEGER,
                         oauth_client_key  TEXT
                     );
                     CREATE TABLE proxy_config (
                         id                   INTEGER PRIMARY KEY CHECK (id = 1),
                         auto_start           INTEGER NOT NULL DEFAULT 0,
                         port                 INTEGER NOT NULL DEFAULT 8045,
                         api_key              TEXT,
                         selected_account_id  TEXT
                     );
                     CREATE TABLE traffic_log (
                         id             INTEGER PRIMARY KEY AUTOINCREMENT,
                         at             INTEGER NOT NULL,
                         protocol       TEXT NOT NULL,
                         model          TEXT NOT NULL,
                         account_id     TEXT,
                         status         INTEGER NOT NULL,
                         duration_ms    INTEGER NOT NULL,
                         request_bytes  INTEGER NOT NULL,
                         response_bytes INTEGER NOT NULL,
                         error          TEXT
                     );
                     INSERT INTO schema_version (version) VALUES (2);
                     COMMIT;",
                )
                .map_err(storage)?;
        }

        if current < 3 {
            // The accounts of the synthetic dataset are marked, so the
            // interface can tell them apart from a real account. An account
            // without credentials belongs to the sample data.
            connection
                .execute_batch(
                    "BEGIN;
                     ALTER TABLE accounts ADD COLUMN demo INTEGER NOT NULL DEFAULT 0;
                     UPDATE accounts SET demo = 1
                        WHERE id NOT IN (SELECT account_id FROM account_credentials);
                     INSERT INTO schema_version (version) VALUES (3);
                     COMMIT;",
                )
                .map_err(storage)?;
        }

        if current < 4 {
            connection
                .execute_batch(
                    "BEGIN;
                     CREATE TABLE workspaces (
                         id             TEXT PRIMARY KEY,
                         name           TEXT NOT NULL,
                         account_id     TEXT NOT NULL,
                         project_folder TEXT NOT NULL,
                         profile_folder TEXT NOT NULL,
                         last_active_at INTEGER NOT NULL,
                         state          TEXT NOT NULL DEFAULT 'idle'
                     );
                     INSERT INTO schema_version (version) VALUES (4);
                     COMMIT;",
                )
                .map_err(storage)?;
        }

        Ok(())
    }

    /// Removes every account and quota row. Used by the demo seeding.
    pub fn clear_accounts(&self) -> Result<(), RepositoryError> {
        self.lock()
            .execute_batch(
                "DELETE FROM model_quotas;
                 DELETE FROM weekly_quotas;
                 DELETE FROM accounts;",
            )
            .map_err(storage)
    }

    /// Removes the accounts of the synthetic dataset and their quotas.
    ///
    /// Called when real accounts were imported from the upstream
    /// installation, so the interface never mixes sample data with real data.
    pub fn delete_demo_accounts(&self) -> Result<(), RepositoryError> {
        self.lock()
            .execute_batch(
                "DELETE FROM model_quotas
                  WHERE account_id IN (SELECT id FROM accounts WHERE demo = 1);
                 DELETE FROM weekly_quotas
                  WHERE account_id IN (SELECT id FROM accounts WHERE demo = 1);
                 DELETE FROM accounts WHERE demo = 1;",
            )
            .map_err(storage)
    }

    /// Removes every model and model group of the catalog.
    pub fn clear_catalog(&self) -> Result<(), RepositoryError> {
        self.lock()
            .execute_batch(
                "DELETE FROM model_group_families;
                 DELETE FROM model_groups;
                 DELETE FROM models;",
            )
            .map_err(storage)
    }

    /// Runs a raw SQL batch.
    ///
    /// This exists for maintenance tasks and for the tests that simulate a
    /// profile written by another build. Application code must not use it.
    pub fn execute_batch(&self, sql: &str) -> Result<(), RepositoryError> {
        self.lock().execute_batch(sql).map_err(storage)
    }

    /// Stores the model catalog and the model groups.
    pub fn save_catalog(
        &self,
        models: &[Model],
        groups: &[ModelGroup],
    ) -> Result<(), RepositoryError> {
        let connection = self.lock();
        let tx = connection.unchecked_transaction().map_err(storage)?;
        for model in models {
            tx.execute(
                "INSERT INTO models (id, label, family) VALUES (?1, ?2, ?3)
                 ON CONFLICT(id) DO UPDATE SET label = ?2, family = ?3",
                params![model.id, model.label, model.family.as_str()],
            )
            .map_err(storage)?;
        }
        for group in groups {
            tx.execute(
                "INSERT INTO model_groups (id, label) VALUES (?1, ?2)
                 ON CONFLICT(id) DO UPDATE SET label = ?2",
                params![group.id, group.label],
            )
            .map_err(storage)?;
            tx.execute(
                "DELETE FROM model_group_families WHERE group_id = ?1",
                params![group.id],
            )
            .map_err(storage)?;
            for family in &group.families {
                tx.execute(
                    "INSERT INTO model_group_families (group_id, family) VALUES (?1, ?2)",
                    params![group.id, family.as_str()],
                )
                .map_err(storage)?;
            }
        }
        tx.commit().map_err(storage)
    }
}

fn read_account(connection: &Connection, id: &str) -> Result<Option<Account>, RepositoryError> {
    let row = connection
        .query_row(
            "SELECT id, name, handle, provider, plan, status, credits, in_use, recommended,
                    selected, demo
             FROM accounts WHERE id = ?1",
            params![id],
            |row| {
                Ok((
                    row.get::<_, String>(0)?,
                    row.get::<_, String>(1)?,
                    row.get::<_, String>(2)?,
                    row.get::<_, String>(3)?,
                    row.get::<_, String>(4)?,
                    row.get::<_, String>(5)?,
                    row.get::<_, i64>(6)?,
                    row.get::<_, i64>(7)?,
                    row.get::<_, i64>(8)?,
                    row.get::<_, i64>(9)?,
                    row.get::<_, i64>(10)?,
                ))
            },
        )
        .optional()
        .map_err(storage)?;

    let Some((
        id,
        name,
        handle,
        provider,
        plan,
        status,
        credits,
        in_use,
        recommended,
        selected,
        demo,
    )) = row
    else {
        return Ok(None);
    };

    let status = AccountStatus::parse(&status)
        .ok_or_else(|| RepositoryError::Invalid(format!("unknown account status: {status}")))?;

    let mut statement = connection
        .prepare(
            "SELECT model_name, family, remaining, reset_label FROM model_quotas
             WHERE account_id = ?1 ORDER BY rowid",
        )
        .map_err(storage)?;
    let quotas = statement
        .query_map(params![id], |row| {
            Ok((
                row.get::<_, String>(0)?,
                row.get::<_, String>(1)?,
                row.get::<_, f64>(2)?,
                row.get::<_, String>(3)?,
            ))
        })
        .map_err(storage)?
        .map(|entry| {
            let (name, family, remaining, reset_label) = entry.map_err(storage)?;
            let family = ModelFamily::parse(&family).ok_or_else(|| {
                RepositoryError::Invalid(format!("unknown model family: {family}"))
            })?;
            Ok(ModelQuota {
                name,
                family,
                remaining,
                reset_label,
            })
        })
        .collect::<Result<Vec<_>, RepositoryError>>()?;

    let mut statement = connection
        .prepare(
            "SELECT q.group_id, g.label, q.remaining, q.reset_label
             FROM weekly_quotas q
             LEFT JOIN model_groups g ON g.id = q.group_id
             WHERE q.account_id = ?1 ORDER BY g.rowid",
        )
        .map_err(storage)?;
    let weekly_quotas = statement
        .query_map(params![id], |row| {
            Ok((
                row.get::<_, String>(0)?,
                row.get::<_, Option<String>>(1)?,
                row.get::<_, f64>(2)?,
                row.get::<_, String>(3)?,
            ))
        })
        .map_err(storage)?
        .map(|entry| {
            let (group_id, group_label, remaining, reset_label) = entry.map_err(storage)?;
            let label = group_label.unwrap_or_else(|| group_id.clone());
            Ok(WeeklyQuota {
                group_id,
                group_label: label,
                remaining,
                reset_label,
            })
        })
        .collect::<Result<Vec<_>, RepositoryError>>()?;

    Ok(Some(Account {
        id,
        name,
        handle,
        provider,
        plan,
        status,
        credits,
        in_use: in_use != 0,
        recommended: recommended != 0,
        selected: selected != 0,
        demo: demo != 0,
        quotas,
        weekly_quotas,
    }))
}

impl CloudRepository for SqliteAccountRepository {
    fn load_credentials(
        &self,
        account_id: &str,
    ) -> Result<Option<AccountCredentials>, RepositoryError> {
        let connection = self.lock();
        let row = connection
            .query_row(
                "SELECT account_id, access_token, refresh_token, expiry_timestamp, email,
                        project_id, plan, credits, oauth_client_key
                 FROM account_credentials WHERE account_id = ?1",
                params![account_id],
                |row| {
                    Ok(AccountCredentials {
                        account_id: row.get(0)?,
                        access_token: row.get(1)?,
                        refresh_token: row.get(2)?,
                        expiry_timestamp: row.get(3)?,
                        email: row.get(4)?,
                        project_id: row.get(5)?,
                        plan: row.get(6)?,
                        credits: row.get(7)?,
                        oauth_client_key: row.get(8)?,
                    })
                },
            )
            .optional()
            .map_err(storage)?;
        Ok(row)
    }

    fn save_credentials(
        &self,
        credentials: &AccountCredentials,
    ) -> Result<(), RepositoryError> {
        self.lock()
            .execute(
                "INSERT INTO account_credentials
                     (account_id, access_token, refresh_token, expiry_timestamp, email,
                      project_id, plan, credits, oauth_client_key)
                 VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9)
                 ON CONFLICT(account_id) DO UPDATE SET
                     access_token = ?2, refresh_token = ?3, expiry_timestamp = ?4,
                     email = ?5, project_id = ?6, plan = ?7, credits = ?8,
                     oauth_client_key = ?9",
                params![
                    credentials.account_id,
                    credentials.access_token,
                    credentials.refresh_token,
                    credentials.expiry_timestamp,
                    credentials.email,
                    credentials.project_id,
                    credentials.plan,
                    credentials.credits,
                    credentials.oauth_client_key,
                ],
            )
            .map_err(storage)?;
        Ok(())
    }

    fn delete_credentials(&self, account_id: &str) -> Result<(), RepositoryError> {
        self.lock()
            .execute(
                "DELETE FROM account_credentials WHERE account_id = ?1",
                params![account_id],
            )
            .map_err(storage)?;
        Ok(())
    }

    fn list_credential_accounts(&self) -> Result<Vec<String>, RepositoryError> {
        let connection = self.lock();
        let mut statement = connection
            .prepare("SELECT account_id FROM account_credentials ORDER BY account_id")
            .map_err(storage)?;
        let ids = statement
            .query_map([], |row| row.get::<_, String>(0))
            .map_err(storage)?
            .collect::<Result<Vec<_>, rusqlite::Error>>()
            .map_err(storage)?;
        Ok(ids)
    }

    fn load_proxy_config(&self) -> Result<ProxyConfig, RepositoryError> {
        let connection = self.lock();
        let row = connection
            .query_row(
                "SELECT auto_start, port, api_key, selected_account_id
                 FROM proxy_config WHERE id = 1",
                [],
                |row| {
                    Ok(ProxyConfig {
                        auto_start: row.get::<_, i64>(0)? != 0,
                        port: row.get::<_, i64>(1)? as u16,
                        api_key: row.get(2)?,
                        selected_account_id: row.get(3)?,
                    })
                },
            )
            .optional()
            .map_err(storage)?;

        Ok(row.unwrap_or_default())
    }

    fn save_proxy_config(&self, config: &ProxyConfig) -> Result<(), RepositoryError> {
        self.lock()
            .execute(
                "INSERT INTO proxy_config (id, auto_start, port, api_key, selected_account_id)
                 VALUES (1, ?1, ?2, ?3, ?4)
                 ON CONFLICT(id) DO UPDATE SET
                     auto_start = ?1, port = ?2, api_key = ?3, selected_account_id = ?4",
                params![
                    config.auto_start as i64,
                    config.port as i64,
                    config.api_key,
                    config.selected_account_id,
                ],
            )
            .map_err(storage)?;
        Ok(())
    }

    fn record_traffic(&self, entry: &TrafficEntry) -> Result<i64, RepositoryError> {
        self.lock()
            .execute(
                "INSERT INTO traffic_log
                     (at, protocol, model, account_id, status, duration_ms,
                      request_bytes, response_bytes, error)
                 VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9)",
                params![
                    entry.at,
                    entry.protocol,
                    entry.model,
                    entry.account_id,
                    entry.status as i64,
                    entry.duration_ms as i64,
                    entry.request_bytes as i64,
                    entry.response_bytes as i64,
                    entry.error,
                ],
            )
            .map_err(storage)?;
        Ok(self.lock().last_insert_rowid())
    }

    fn list_traffic(&self, limit: u32) -> Result<Vec<TrafficEntry>, RepositoryError> {
        let connection = self.lock();
        let mut statement = connection
            .prepare(
                "SELECT id, at, protocol, model, account_id, status, duration_ms,
                        request_bytes, response_bytes, error
                 FROM traffic_log ORDER BY id DESC LIMIT ?1",
            )
            .map_err(storage)?;
        let entries = statement
            .query_map(params![limit as i64], |row| {
                Ok(TrafficEntry {
                    id: row.get(0)?,
                    at: row.get(1)?,
                    protocol: row.get(2)?,
                    model: row.get(3)?,
                    account_id: row.get(4)?,
                    status: row.get::<_, i64>(5)? as u16,
                    duration_ms: row.get::<_, i64>(6)? as u64,
                    request_bytes: row.get::<_, i64>(7)? as u64,
                    response_bytes: row.get::<_, i64>(8)? as u64,
                    error: row.get(9)?,
                })
            })
            .map_err(storage)?
            .map(|entry| entry.map_err(storage))
            .collect::<Result<Vec<_>, RepositoryError>>()?;
        Ok(entries)
    }

    fn list_workspaces(&self) -> Result<Vec<Workspace>, RepositoryError> {
        let connection = self.lock();
        let mut statement = connection
            .prepare(
                "SELECT id, name, account_id, project_folder, profile_folder, last_active_at, state
                 FROM workspaces ORDER BY last_active_at DESC, id",
            )
            .map_err(storage)?;
        let workspaces = statement
            .query_map([], |row| {
                Ok((
                    row.get::<_, String>(0)?,
                    row.get::<_, String>(1)?,
                    row.get::<_, String>(2)?,
                    row.get::<_, String>(3)?,
                    row.get::<_, String>(4)?,
                    row.get::<_, i64>(5)?,
                    row.get::<_, String>(6)?,
                ))
            })
            .map_err(storage)?
            .map(|entry| {
                let (id, name, account_id, project_folder, profile_folder, last_active_at, state) =
                    entry.map_err(storage)?;
                let state = WorkspaceState::parse(&state).ok_or_else(|| {
                    RepositoryError::Invalid(format!("unknown workspace state: {state}"))
                })?;
                Ok(Workspace {
                    id,
                    name,
                    account_id,
                    project_folder,
                    profile_folder,
                    last_active_at,
                    state,
                })
            })
            .collect::<Result<Vec<_>, RepositoryError>>()?;
        Ok(workspaces)
    }

    fn save_workspaces(&self, workspaces: &[Workspace]) -> Result<(), RepositoryError> {
        let connection = self.lock();
        let tx = connection.unchecked_transaction().map_err(storage)?;
        tx.execute("DELETE FROM workspaces", []).map_err(storage)?;
        for workspace in workspaces {
            tx.execute(
                "INSERT INTO workspaces
                     (id, name, account_id, project_folder, profile_folder, last_active_at, state)
                 VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)",
                params![
                    workspace.id,
                    workspace.name,
                    workspace.account_id,
                    workspace.project_folder,
                    workspace.profile_folder,
                    workspace.last_active_at,
                    workspace.state.as_str(),
                ],
            )
            .map_err(storage)?;
        }
        tx.commit().map_err(storage)
    }
}

impl AccountRepository for SqliteAccountRepository {
    fn list_accounts(&self) -> Result<Vec<Account>, RepositoryError> {
        let connection = self.lock();
        let mut statement = connection
            .prepare("SELECT id FROM accounts ORDER BY position, id")
            .map_err(storage)?;
        let ids = statement
            .query_map([], |row| row.get::<_, String>(0))
            .map_err(storage)?
            .collect::<Result<Vec<_>, rusqlite::Error>>()
            .map_err(storage)?;
        drop(statement);

        let mut accounts = Vec::with_capacity(ids.len());
        for id in ids {
            if let Some(account) = read_account(&connection, &id)? {
                accounts.push(account);
            }
        }
        Ok(accounts)
    }

    fn find_account(&self, id: &str) -> Result<Option<Account>, RepositoryError> {
        read_account(&self.lock(), id)
    }

    fn save_account(&self, account: &Account) -> Result<(), RepositoryError> {
        let connection = self.lock();
        let tx = connection.unchecked_transaction().map_err(storage)?;

        let position: i64 = tx
            .query_row(
                "SELECT COALESCE(MAX(position), 0) + 1 FROM accounts",
                [],
                |row| row.get(0),
            )
            .map_err(storage)?;

        tx.execute(
            "INSERT INTO accounts
                 (id, name, handle, provider, plan, status, credits, in_use, recommended,
                  selected, position, demo)
             VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12)
             ON CONFLICT(id) DO UPDATE SET
                 name = ?2, handle = ?3, provider = ?4, plan = ?5, status = ?6,
                 credits = ?7, in_use = ?8, recommended = ?9, selected = ?10, demo = ?12",
            params![
                account.id,
                account.name,
                account.handle,
                account.provider,
                account.plan,
                account.status.as_str(),
                account.credits,
                account.in_use as i64,
                account.recommended as i64,
                account.selected as i64,
                position,
                account.demo as i64,
            ],
        )
        .map_err(storage)?;

        tx.execute(
            "DELETE FROM model_quotas WHERE account_id = ?1",
            params![account.id],
        )
        .map_err(storage)?;
        for quota in &account.quotas {
            tx.execute(
                "INSERT INTO model_quotas
                     (account_id, model_name, family, remaining, reset_label)
                 VALUES (?1, ?2, ?3, ?4, ?5)",
                params![
                    account.id,
                    quota.name,
                    quota.family.as_str(),
                    quota.remaining,
                    quota.reset_label
                ],
            )
            .map_err(storage)?;
        }

        tx.execute(
            "DELETE FROM weekly_quotas WHERE account_id = ?1",
            params![account.id],
        )
        .map_err(storage)?;
        for quota in &account.weekly_quotas {
            tx.execute(
                "INSERT INTO weekly_quotas (account_id, group_id, remaining, reset_label)
                 VALUES (?1, ?2, ?3, ?4)",
                params![
                    account.id,
                    quota.group_id,
                    quota.remaining,
                    quota.reset_label
                ],
            )
            .map_err(storage)?;
        }

        tx.commit().map_err(storage)
    }

    fn set_active_account(&self, id: &str) -> Result<(), RepositoryError> {
        let connection = self.lock();
        let tx = connection.unchecked_transaction().map_err(storage)?;
        tx.execute("UPDATE accounts SET in_use = 0", [])
            .map_err(storage)?;
        let changed = tx
            .execute("UPDATE accounts SET in_use = 1 WHERE id = ?1", params![id])
            .map_err(storage)?;
        if changed == 0 {
            return Err(RepositoryError::NotFound(id.to_string()));
        }
        tx.commit().map_err(storage)
    }

    fn set_account_selected(&self, id: &str, selected: bool) -> Result<(), RepositoryError> {
        let connection = self.lock();
        let changed = connection
            .execute(
                "UPDATE accounts SET selected = ?2 WHERE id = ?1",
                params![id, selected as i64],
            )
            .map_err(storage)?;
        if changed == 0 {
            return Err(RepositoryError::NotFound(id.to_string()));
        }
        Ok(())
    }

    fn model_catalog(&self) -> Result<Vec<Model>, RepositoryError> {
        let connection = self.lock();
        let mut statement = connection
            .prepare("SELECT id, label, family FROM models ORDER BY rowid")
            .map_err(storage)?;
        let models = statement
            .query_map([], |row| {
                Ok((
                    row.get::<_, String>(0)?,
                    row.get::<_, String>(1)?,
                    row.get::<_, String>(2)?,
                ))
            })
            .map_err(storage)?
            .map(|entry| {
                let (id, label, family) = entry.map_err(storage)?;
                let family = ModelFamily::parse(&family).ok_or_else(|| {
                    RepositoryError::Invalid(format!("unknown model family: {family}"))
                })?;
                Ok(Model { id, label, family })
            })
            .collect::<Result<Vec<_>, RepositoryError>>()?;
        Ok(models)
    }

    fn model_groups(&self) -> Result<Vec<ModelGroup>, RepositoryError> {
        let connection = self.lock();
        let mut statement = connection
            .prepare("SELECT id, label FROM model_groups ORDER BY rowid")
            .map_err(storage)?;
        let groups = statement
            .query_map([], |row| {
                Ok((row.get::<_, String>(0)?, row.get::<_, String>(1)?))
            })
            .map_err(storage)?
            .map(|entry| {
                let (id, label) = entry.map_err(storage)?;
                Ok((id, label))
            })
            .collect::<Result<Vec<_>, RepositoryError>>()?;
        drop(statement);

        let mut result = Vec::with_capacity(groups.len());
        for (id, label) in groups {
            let mut statement = connection
                .prepare("SELECT family FROM model_group_families WHERE group_id = ?1")
                .map_err(storage)?;
            let families = statement
                .query_map(params![id], |row| row.get::<_, String>(0))
                .map_err(storage)?
                .map(|entry| {
                    let family = entry.map_err(storage)?;
                    ModelFamily::parse(&family).ok_or_else(|| {
                        RepositoryError::Invalid(format!("unknown model family: {family}"))
                    })
                })
                .collect::<Result<Vec<_>, RepositoryError>>()?;
            result.push(ModelGroup {
                id,
                label,
                families,
            });
        }
        Ok(result)
    }
}
