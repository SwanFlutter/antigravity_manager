//! The domain and persistence core of Antigravity Manager.
//!
//! The crate is deliberately free of Flutter, Windows and network APIs so the
//! rules can be tested on their own. Everything that touches the operating
//! system lives behind a trait in [`repository`].

pub mod cloud;
pub mod demo;
pub mod domain;
pub mod fakes;
pub mod mapping;
pub mod repository;
pub mod sqlite;

pub use cloud::{
    AccountCredentials, ConnectStatus, ProxyConfig, ProxyProtocol, QuotaBucket, QuotaGroup,
    TrafficEntry,
};
pub use domain::{
    summarize, Account, AccountStatus, AccountSummary, Model, ModelFamily, ModelGroup,
    ModelQuota, WeeklyQuota,
};
pub use repository::{
    AccountRepository, AccountService, Clock, CloudRepository, QuotaProvider, RepositoryError,
    ServiceError,
};
pub use sqlite::SqliteAccountRepository;

#[cfg(test)]
mod tests {
    use super::*;
    use crate::fakes::{FixedClock, InMemoryAccountRepository, StaticQuotaProvider};
    use std::sync::Arc;

    fn account(id: &str, status: AccountStatus, remaining: f64) -> Account {
        Account {
            id: id.to_string(),
            name: id.to_string(),
            handle: format!("{id}@example.com"),
            provider: "Google".to_string(),
            plan: "Google AI Pro".to_string(),
            status,
            credits: 100,
            in_use: false,
            recommended: false,
            selected: false,
            demo: false,
            quotas: vec![ModelQuota {
                name: "Gemini 3.8 Flash (High)".to_string(),
                family: ModelFamily::Gemini,
                remaining,
                reset_label: "6d 21h".to_string(),
            }],
            weekly_quotas: vec![WeeklyQuota {
                group_id: "gemini".to_string(),
                group_label: "Gemini models".to_string(),
                remaining,
                reset_label: "6d 23h".to_string(),
            }],
        }
    }

    #[test]
    fn summary_counts_statuses_and_quota() {
        let accounts = vec![
            account("a", AccountStatus::Active, 1.0),
            account("b", AccountStatus::RateLimited, 0.5),
            account("c", AccountStatus::Idle, 0.0),
        ];

        let summary = summarize(&accounts);

        assert_eq!(summary.total, 3);
        assert_eq!(summary.active, 1);
        assert_eq!(summary.rate_limited, 1);
        assert!((summary.global_remaining - 0.5).abs() < f64::EPSILON);
    }

    #[test]
    fn summary_of_an_empty_pool_is_zero() {
        let summary = summarize(&[]);

        assert_eq!(summary.total, 0);
        assert_eq!(summary.active, 0);
        assert_eq!(summary.rate_limited, 0);
        assert_eq!(summary.global_remaining, 0.0);
    }

    #[test]
    fn service_rejects_unknown_accounts() {
        let repository = InMemoryAccountRepository::new(vec![], vec![], vec![]);
        let service = AccountService::new(
            Arc::new(repository),
            Box::new(StaticQuotaProvider),
            Box::new(FixedClock(0)),
        );

        let error = service.set_active_account("missing").unwrap_err();
        assert!(matches!(error, ServiceError::Validation(_)));
    }

    #[test]
    fn service_marks_exactly_one_active_account() {
        let repository = InMemoryAccountRepository::new(
            vec![
                account("a", AccountStatus::Active, 1.0),
                account("b", AccountStatus::Idle, 1.0),
            ],
            vec![],
            vec![],
        );
        let service = AccountService::new(
            Arc::new(repository),
            Box::new(StaticQuotaProvider),
            Box::new(FixedClock(0)),
        );

        service.set_active_account("b").unwrap();

        let (accounts, _) = service.list_accounts().unwrap();
        assert!(!accounts[0].in_use);
        assert!(accounts[1].in_use);
    }

    #[test]
    fn service_toggles_the_selection() {
        let repository = InMemoryAccountRepository::new(
            vec![account("a", AccountStatus::Active, 1.0)],
            vec![],
            vec![],
        );
        let service = AccountService::new(
            Arc::new(repository),
            Box::new(StaticQuotaProvider),
            Box::new(FixedClock(0)),
        );

        service.set_selected("a", true).unwrap();
        let (accounts, _) = service.list_accounts().unwrap();
        assert!(accounts[0].selected);

        service.set_selected("a", false).unwrap();
        let (accounts, _) = service.list_accounts().unwrap();
        assert!(!accounts[0].selected);
    }
}
