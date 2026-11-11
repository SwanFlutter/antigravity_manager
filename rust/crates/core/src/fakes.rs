//! Deterministic fakes used by the domain tests.
//!
//! They implement the same traits as the production adapters, so the service
//! rules can be exercised without a database, a network or Windows APIs.

use std::sync::Mutex;

use crate::domain::{Account, Model, ModelGroup};
use crate::repository::{AccountRepository, Clock, QuotaProvider, RepositoryError};

/// An in memory account repository.
#[derive(Default)]
pub struct InMemoryAccountRepository {
    accounts: Mutex<Vec<Account>>,
    catalog: Mutex<Vec<Model>>,
    groups: Mutex<Vec<ModelGroup>>,
}

impl InMemoryAccountRepository {
    pub fn new(accounts: Vec<Account>, catalog: Vec<Model>, groups: Vec<ModelGroup>) -> Self {
        Self {
            accounts: Mutex::new(accounts),
            catalog: Mutex::new(catalog),
            groups: Mutex::new(groups),
        }
    }
}

impl AccountRepository for InMemoryAccountRepository {
    fn list_accounts(&self) -> Result<Vec<Account>, RepositoryError> {
        Ok(self.accounts.lock().expect("lock").clone())
    }

    fn find_account(&self, id: &str) -> Result<Option<Account>, RepositoryError> {
        Ok(self
            .accounts
            .lock()
            .expect("lock")
            .iter()
            .find(|account| account.id == id)
            .cloned())
    }

    fn save_account(&self, account: &Account) -> Result<(), RepositoryError> {
        let mut accounts = self.accounts.lock().expect("lock");
        match accounts.iter_mut().find(|item| item.id == account.id) {
            Some(existing) => *existing = account.clone(),
            None => accounts.push(account.clone()),
        }
        Ok(())
    }

    fn set_quota_error(&self, id: &str, error: &str) -> Result<(), RepositoryError> {
        let mut accounts = self.accounts.lock().expect("lock");
        let account = accounts.iter_mut().find(|account| account.id == id)
            .ok_or_else(|| RepositoryError::NotFound(id.to_string()))?;
        account.quota_error = Some(error.to_string());
        Ok(())
    }

    fn merge_models(&self, models: &[Model]) -> Result<(), RepositoryError> {
        let mut catalog = self.catalog.lock().expect("lock");
        for model in models {
            match catalog.iter_mut().find(|entry| entry.id == model.id) {
                Some(entry) => *entry = model.clone(),
                None => catalog.push(model.clone()),
            }
        }
        Ok(())
    }

    fn set_active_account(&self, id: &str) -> Result<(), RepositoryError> {
        let mut accounts = self.accounts.lock().expect("lock");
        let mut found = false;
        for account in accounts.iter_mut() {
            account.in_use = account.id == id;
            found |= account.id == id;
        }
        if found {
            Ok(())
        } else {
            Err(RepositoryError::NotFound(id.to_string()))
        }
    }

    fn set_account_selected(&self, id: &str, selected: bool) -> Result<(), RepositoryError> {
        let mut accounts = self.accounts.lock().expect("lock");
        match accounts.iter_mut().find(|item| item.id == id) {
            Some(account) => {
                account.selected = selected;
                Ok(())
            }
            None => Err(RepositoryError::NotFound(id.to_string())),
        }
    }

    fn model_catalog(&self) -> Result<Vec<Model>, RepositoryError> {
        Ok(self.catalog.lock().expect("lock").clone())
    }

    fn model_groups(&self) -> Result<Vec<ModelGroup>, RepositoryError> {
        Ok(self.groups.lock().expect("lock").clone())
    }
}

/// A quota provider that returns the stored account unchanged.
pub struct StaticQuotaProvider;

impl QuotaProvider for StaticQuotaProvider {
    fn refresh(&self, account: &Account) -> Result<Account, RepositoryError> {
        Ok(account.clone())
    }
}

/// A clock that always reports the same instant.
pub struct FixedClock(pub i64);

impl Clock for FixedClock {
    fn now_millis(&self) -> i64 {
        self.0
    }
}
