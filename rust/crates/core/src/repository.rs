//! Persistence and side effect boundaries of the core.
//!
//! Every dependency the domain needs is expressed as a trait so the rules can
//! be tested with deterministic fakes instead of a real database or network.

use crate::cloud::{AccountCredentials, ProxyConfig, TrafficEntry};
use crate::domain::{Account, AccountSummary, Model, ModelGroup, Workspace};
use std::sync::Arc;
use thiserror::Error;
/// A failure raised by a repository.
#[derive(Debug, Error)]
pub enum RepositoryError {
    #[error("account not found: {0}")]
    NotFound(String),
    #[error("storage failure: {0}")]
    Storage(String),
    #[error("invalid data: {0}")]
    Invalid(String),
}

/// A failure raised by a domain service.
#[derive(Debug, Error)]
pub enum ServiceError {
    #[error("validation failed: {0}")]
    Validation(String),
    #[error("{0}")]
    Repository(#[from] RepositoryError),
}

/// Stores and reads accounts, model quotas and the model catalog.
pub trait AccountRepository: Send + Sync {
    /// Every known account, ordered by the stored creation order.
    fn list_accounts(&self) -> Result<Vec<Account>, RepositoryError>;

    /// One account by id.
    fn find_account(&self, id: &str) -> Result<Option<Account>, RepositoryError>;

    /// Inserts or replaces an account together with its quota windows.
    fn save_account(&self, account: &Account) -> Result<(), RepositoryError>;

    /// Records a sync failure without touching cached quotas or their timestamp.
    fn set_quota_error(&self, id: &str, error: &str) -> Result<(), RepositoryError>;

    /// Merges actual provider models by their stable id.
    fn merge_models(&self, models: &[Model]) -> Result<(), RepositoryError>;

    /// Marks exactly one account as the account used by the desktop clients.
    fn set_active_account(&self, id: &str) -> Result<(), RepositoryError>;

    /// Adds or removes an account from the selection.
    fn set_account_selected(&self, id: &str, selected: bool) -> Result<(), RepositoryError>;

    /// The catalog of models the gateway can route to.
    fn model_catalog(&self) -> Result<Vec<Model>, RepositoryError>;

    /// The model groups that share a weekly allowance.
    fn model_groups(&self) -> Result<Vec<ModelGroup>, RepositoryError>;
}

/// Reads quota information for the accounts of a provider.
///
/// The production implementation performs the upstream request; the tests use a
/// deterministic provider.
pub trait QuotaProvider: Send + Sync {
    /// Refreshes the quota of one account and returns the updated account.
    fn refresh(&self, account: &Account) -> Result<Account, RepositoryError>;
}

/// A source of the current time.
pub trait Clock: Send + Sync {
    /// Milliseconds since the Unix epoch.
    fn now_millis(&self) -> i64;
}

/// Stores the credentials of the connected accounts, the configuration of the
/// local proxy and the traffic log.
pub trait CloudRepository: Send + Sync {
    /// The credentials of one account.
    fn load_credentials(
        &self,
        account_id: &str,
    ) -> Result<Option<AccountCredentials>, RepositoryError>;

    /// Stores the credentials of one account.
    fn save_credentials(
        &self,
        credentials: &AccountCredentials,
    ) -> Result<(), RepositoryError>;

    /// Removes the credentials of one account.
    fn delete_credentials(&self, account_id: &str) -> Result<(), RepositoryError>;

    /// The ids of every account that has credentials.
    fn list_credential_accounts(&self) -> Result<Vec<String>, RepositoryError>;

    /// The configuration of the local proxy.
    fn load_proxy_config(&self) -> Result<ProxyConfig, RepositoryError>;

    /// Stores the configuration of the local proxy.
    fn save_proxy_config(&self, config: &ProxyConfig) -> Result<(), RepositoryError>;

    /// Appends one entry to the traffic log and returns its id.
    fn record_traffic(&self, entry: &TrafficEntry) -> Result<i64, RepositoryError>;

    /// The newest entries of the traffic log.
    fn list_traffic(&self, limit: u32) -> Result<Vec<TrafficEntry>, RepositoryError>;

    /// Every workspace profile.
    fn list_workspaces(&self) -> Result<Vec<Workspace>, RepositoryError>;

    /// Replaces every workspace profile.
    fn save_workspaces(&self, workspaces: &[Workspace]) -> Result<(), RepositoryError>;
}

/// The application service the transport layer calls.
pub struct AccountService {
    repository: Arc<dyn AccountRepository>,
    quota: Box<dyn QuotaProvider>,
    clock: Box<dyn Clock>,
}

impl AccountService {
    pub fn new(
        repository: Arc<dyn AccountRepository>,
        quota: Box<dyn QuotaProvider>,
        clock: Box<dyn Clock>,
    ) -> Self {
        Self {
            repository,
            quota,
            clock,
        }
    }

    /// Every account plus the aggregate counters.
    pub fn list_accounts(&self) -> Result<(Vec<Account>, AccountSummary), ServiceError> {
        let accounts = self.repository.list_accounts()?;
        let summary = crate::domain::summarize(&accounts);
        Ok((accounts, summary))
    }

    /// Refreshes the quota of one account and stores the result.
    pub fn refresh_account(&self, id: &str) -> Result<Account, ServiceError> {
        let account = self
            .repository
            .find_account(id)?
            .ok_or_else(|| RepositoryError::NotFound(id.to_string()))?;
        let refreshed = self.quota.refresh(&account)?;
        self.repository.save_account(&refreshed)?;
        Ok(refreshed)
    }

    /// Marks one account as the account used by the desktop clients.
    pub fn set_active_account(&self, id: &str) -> Result<(), ServiceError> {
        if self.repository.find_account(id)?.is_none() {
            return Err(ServiceError::Validation(format!(
                "unknown account: {id}"
            )));
        }
        self.repository.set_active_account(id)?;
        Ok(())
    }

    /// Adds or removes an account from the selection.
    pub fn set_selected(&self, id: &str, selected: bool) -> Result<(), ServiceError> {
        if self.repository.find_account(id)?.is_none() {
            return Err(ServiceError::Validation(format!(
                "unknown account: {id}"
            )));
        }
        self.repository.set_account_selected(id, selected)?;
        Ok(())
    }

    /// The catalog of models the gateway can route to.
    pub fn model_catalog(&self) -> Result<Vec<Model>, ServiceError> {
        Ok(self.repository.model_catalog()?)
    }

    /// The model groups that share a weekly allowance.
    pub fn model_groups(&self) -> Result<Vec<ModelGroup>, ServiceError> {
        Ok(self.repository.model_groups()?)
    }

    /// The current time in milliseconds since the Unix epoch.
    pub fn now_millis(&self) -> i64 {
        self.clock.now_millis()
    }

    /// The repository behind the service.
    ///
    /// The host uses it for the operations that are not part of the domain
    /// rules, for example storing the quota of a connected account.
    pub fn repository(&self) -> &dyn AccountRepository {
        self.repository.as_ref()
    }
}
