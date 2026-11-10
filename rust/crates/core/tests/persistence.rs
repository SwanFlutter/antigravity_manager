//! Persistence tests for the SQLite repository.
//!
//! Every test uses a temporary database so it can never touch a real profile.

use antigravity_core::demo::seed_demo;
use antigravity_core::domain::{AccountStatus, ModelFamily};
use antigravity_core::repository::AccountRepository;
use antigravity_core::sqlite::SqliteAccountRepository;

fn repository() -> SqliteAccountRepository {
    SqliteAccountRepository::open(":memory:").expect("open in memory database")
}

#[test]
fn migration_is_idempotent() {
    let repository = repository();

    // Re-running the migration on an already migrated database is a no-op.
    repository.migrate().expect("second migration");
    repository.migrate().expect("third migration");

    let version: i64 = repository
        .list_accounts()
        .map(|accounts| accounts.len() as i64)
        .expect("list accounts");
    assert_eq!(version, 0);
}

#[test]
fn the_demo_dataset_matches_the_flutter_prototype() {
    let repository = repository();
    seed_demo(&repository).expect("seed demo profile");

    let accounts = repository.list_accounts().expect("list accounts");
    let summary = antigravity_core::summarize(&accounts);

    // The Flutter prototype computes the same numbers with the same seed, so
    // switching between the in process fake and the running host does not
    // change what is on screen.
    assert_eq!(summary.total, 4);
    assert_eq!(summary.active, 1);
    assert_eq!(summary.rate_limited, 1);
    assert!((summary.global_remaining - 0.3905095967741935).abs() < 1e-12);
}

#[test]
fn the_accounts_of_the_sample_data_are_marked() {
    let repository = repository();
    seed_demo(&repository).expect("seed demo profile");

    let accounts = repository.list_accounts().expect("list accounts");
    assert!(
        accounts.iter().all(|account| account.demo),
        "every account of the sample data is marked"
    );

    // A real account is never marked.
    let mut real = accounts[0].clone();
    real.id = "google-1234".to_string();
    real.demo = false;
    repository.save_account(&real).expect("save the real account");

    let accounts = repository.list_accounts().expect("list accounts");
    let stored = accounts
        .iter()
        .find(|account| account.id == "google-1234")
        .expect("the real account is stored");
    assert!(!stored.demo, "a real account is not a sample");
}

#[test]
fn seeded_profile_round_trips() {
    let repository = repository();
    seed_demo(&repository).expect("seed demo profile");

    let accounts = repository.list_accounts().expect("list accounts");
    assert_eq!(accounts.len(), 4);

    let first = &accounts[0];
    assert_eq!(first.id, "acc-01");
    assert_eq!(first.status, AccountStatus::Active);
    assert!(first.in_use);
    assert!(first.recommended);
    assert_eq!(first.quotas.len(), 31);
    assert_eq!(first.weekly_quotas.len(), 2);

    // The pinned narrative values survive the round trip.
    let pinned = first
        .quotas
        .iter()
        .find(|quota| quota.name == "Gemini 3.8 Flash (High)")
        .expect("pinned quota");
    assert!((pinned.remaining - 1.0).abs() < f64::EPSILON);
    assert_eq!(pinned.reset_label, "6d 21h");

    let weekly = first
        .weekly_quotas
        .iter()
        .find(|quota| quota.group_id == "gemini")
        .expect("weekly quota");
    assert!((weekly.remaining - 0.86).abs() < f64::EPSILON);
    assert_eq!(weekly.reset_label, "6d 23h");
}

#[test]
fn catalog_and_groups_are_readable() {
    let repository = repository();
    seed_demo(&repository).expect("seed demo profile");

    let catalog = repository.model_catalog().expect("model catalog");
    assert_eq!(catalog.len(), 31);
    assert!(catalog
        .iter()
        .any(|model| model.id == "gemini-3.1-pro-high" && model.family == ModelFamily::Gemini));

    let groups = repository.model_groups().expect("model groups");
    assert_eq!(groups.len(), 2);

    let claude_group = groups
        .iter()
        .find(|group| group.id == "claudeGpt")
        .expect("claude group");
    assert!(claude_group.families.contains(&ModelFamily::Claude));
    assert!(claude_group.families.contains(&ModelFamily::Openai));
}

#[test]
fn only_one_account_stays_active() {
    let repository = repository();
    seed_demo(&repository).expect("seed demo profile");

    repository.set_active_account("acc-03").expect("set active");

    let accounts = repository.list_accounts().expect("list accounts");
    assert_eq!(
        accounts.iter().filter(|account| account.in_use).count(),
        1,
        "exactly one account may be active"
    );
    assert!(accounts
        .iter()
        .find(|account| account.id == "acc-03")
        .expect("acc-03")
        .in_use);
}

#[test]
fn selection_is_stored_per_account() {
    let repository = repository();
    seed_demo(&repository).expect("seed demo profile");

    repository
        .set_account_selected("acc-02", true)
        .expect("select account");

    let account = repository
        .find_account("acc-02")
        .expect("find account")
        .expect("acc-02");
    assert!(account.selected);
}

#[test]
fn unknown_account_is_reported() {
    let repository = repository();

    let error = repository
        .set_active_account("missing")
        .expect_err("unknown account must fail");
    assert!(error.to_string().contains("missing"));
}

#[test]
fn a_newer_schema_is_rejected_instead_of_being_downgraded() {
    let repository = repository();
    seed_demo(&repository).expect("seed demo profile");

    // Simulate a profile written by a newer build.
    repository
        .execute_batch("INSERT INTO schema_version (version) VALUES (99);")
        .expect("bump schema version");

    let error = repository.migrate().expect_err("newer schema must be rejected");
    assert!(error.to_string().contains("newer"));
}
