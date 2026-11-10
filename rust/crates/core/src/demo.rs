//! The synthetic dataset used by the demo profile.
//!
//! Every value is fabricated: the names, handles and numbers exist only to
//! exercise the interface. The same deterministic generator the Flutter
//! prototype uses reproduces the values, so switching the UI between the
//! in-process fake and the Rust host does not change what is on screen.

use crate::domain::{
    Account, AccountStatus, Model, ModelFamily, ModelGroup, ModelQuota, WeeklyQuota,
};
use crate::repository::AccountRepository;
use crate::sqlite::SqliteAccountRepository;

/// The model catalog the gateway can route to.
pub fn model_catalog() -> Vec<Model> {
    let entries: &[(&str, &str, ModelFamily)] = &[
        ("gemini-3.8-flash-high", "Gemini 3.8 Flash (High)", ModelFamily::Gemini),
        ("gemini-3.8-flash-medium", "Gemini 3.8 Flash (Medium)", ModelFamily::Gemini),
        ("gpt-oss-120b-medium", "GPT-OSS 120B (Medium)", ModelFamily::Openai),
        ("gemini-3.5-flash-lite", "Gemini 3.5 Flash Lite (gemini-3.5-flash-lite)", ModelFamily::Gemini),
        ("claude-sonnet-4-6", "Claude Sonnet 4.6 (Thinking) (claude-sonnet-4-6)", ModelFamily::Claude),
        ("gemini-2.5-flash-lite", "Gemini 3.5 Flash Lite (gemini-2.5-flash-lite)", ModelFamily::Gemini),
        ("gemini-3.1-flash-image", "Gemini 3.1 Flash Image", ModelFamily::Gemini),
        ("claude-opus-4-6-thinking", "Claude Opus 4.6 (Thinking)", ModelFamily::Claude),
        ("gemini-3-flash", "Gemini 3 Flash", ModelFamily::Gemini),
        ("gemini-3.1-flash-lite", "Gemini 3.1 Flash Lite", ModelFamily::Gemini),
        ("gemini-3.8-flash-low", "Gemini 3.8 Flash (Low)", ModelFamily::Gemini),
        ("gemini-2.5-flash-thinking", "Gemini 3.5 Flash Lite (gemini-2.5-flash-thinking)", ModelFamily::Gemini),
        ("gemini-3.8-flash-tiered", "gemini-3.8-flash-tiered", ModelFamily::Gemini),
        ("gemini-2.5-pro", "Gemini 2.5 Pro", ModelFamily::Gemini),
        ("gemini-2.5-flash", "Gemini 3.5 Flash Lite (gemini-2.5-flash)", ModelFamily::Gemini),
        ("gemini-4-argon", "Gemini 4 Argon", ModelFamily::Gemini),
        ("gemini-4-argon-high", "Gemini 4 Argon (High)", ModelFamily::Gemini),
        ("gemini-3.7-flash", "Gemini 3.7 Flash", ModelFamily::Gemini),
        ("gemini-3.7-flash-low", "Gemini 3.7 Flash (Low)", ModelFamily::Gemini),
        ("gemini-3.7-flash-medium", "Gemini 3.7 Flash (Medium)", ModelFamily::Gemini),
        ("gemini-3.7-flash-high", "Gemini 3.7 Flash (High)", ModelFamily::Gemini),
        ("gemini-3.5-flash-low", "Gemini 3.5 Flash (Low)", ModelFamily::Gemini),
        ("gemini-3.5-flash-medium", "Gemini 3.5 Flash (Medium)", ModelFamily::Gemini),
        ("gemini-3.5-flash-high", "Gemini 3.5 Flash (High)", ModelFamily::Gemini),
        ("gemini-3.1-pro-low", "Gemini 3.1 Pro (Low)", ModelFamily::Gemini),
        ("gemini-3.1-pro-high", "Gemini 3.1 Pro (High)", ModelFamily::Gemini),
        ("gemini-3-pro-image", "Gemini 3 Pro Image", ModelFamily::Gemini),
        ("claude-sonnet-4-6-thinking", "Claude Sonnet 4.6 (Thinking) (claude-sonnet-4-6-thinking)", ModelFamily::Claude),
        ("gpt-5-1-codex", "GPT 5.1 Codex", ModelFamily::Openai),
        ("gpt-5-1", "GPT 5.1", ModelFamily::Openai),
        ("claude-haiku-4-5", "Claude Haiku 4.5", ModelFamily::Claude),
    ];

    entries
        .iter()
        .map(|(id, label, family)| Model {
            id: (*id).to_string(),
            label: (*label).to_string(),
            family: *family,
        })
        .collect()
}

/// The model groups that share one weekly allowance.
pub fn model_groups() -> Vec<ModelGroup> {
    vec![
        ModelGroup {
            id: "gemini".to_string(),
            label: "Gemini models".to_string(),
            families: vec![ModelFamily::Gemini],
        },
        ModelGroup {
            id: "claudeGpt".to_string(),
            label: "Claude and GPT models".to_string(),
            families: vec![ModelFamily::Claude, ModelFamily::Openai],
        },
    ]
}

/// A stable pseudo random value derived from two strings.
///
/// The hash is masked to 31 bits on every step, exactly like the Flutter
/// prototype does, so both sides produce the same numbers.
fn seed(account_id: &str, key: &str) -> u32 {
    let mut hash: u32 = 17;
    for unit in format!("{account_id}|{key}").encode_utf16() {
        hash = hash.wrapping_mul(31).wrapping_add(unit as u32) & 0x7fff_ffff;
    }
    hash
}

fn seeded_remaining(account_id: &str, key: &str) -> f64 {
    0.12 + (seed(account_id, key) % 1000) as f64 / 1000.0 * 0.83
}

fn seeded_reset(account_id: &str, key: &str) -> String {
    const WINDOWS: [&str; 7] = [
        "42m",
        "4h 12m",
        "9h 30m",
        "1d 08h",
        "2d 04h",
        "3d 11h",
        "6d 21h",
    ];
    WINDOWS[(seed(account_id, key) % WINDOWS.len() as u32) as usize].to_string()
}

fn seeded_weekly_remaining(account_id: &str, group_id: &str) -> f64 {
    0.08 + (seed(account_id, &format!("weekly|{group_id}")) % 1000) as f64 / 1000.0 * 0.9
}

fn seeded_weekly_reset(account_id: &str, group_id: &str) -> String {
    const WINDOWS: [&str; 6] = ["18h 40m", "1d 08h", "3d 04h", "4d 02h", "5d 11h", "6d 23h"];
    WINDOWS[(seed(account_id, &format!("weekly|{group_id}")) % WINDOWS.len() as u32) as usize]
        .to_string()
}

/// A pinned quota value used by the demo narrative.
struct Override {
    model_id: &'static str,
    remaining: f64,
    reset: &'static str,
}

fn overrides_for(account_id: &str) -> &'static [Override] {
    match account_id {
        "acc-01" => &[
            Override { model_id: "gemini-3.8-flash-high", remaining: 1.0, reset: "6d 21h" },
            Override { model_id: "gemini-3.5-flash-lite", remaining: 0.82, reset: "4h 12m" },
            Override { model_id: "gemini-3-flash", remaining: 0.46, reset: "4h 12m" },
            Override { model_id: "gemini-3.1-flash-image", remaining: 0.64, reset: "6d 21h" },
            Override { model_id: "claude-sonnet-4-6-thinking", remaining: 0.71, reset: "6d 21h" },
            Override { model_id: "claude-opus-4-6-thinking", remaining: 0.28, reset: "2d 04h" },
        ],
        "acc-02" => &[
            Override { model_id: "claude-sonnet-4-6-thinking", remaining: 0.18, reset: "42m" },
            Override { model_id: "claude-opus-4-6-thinking", remaining: 0.05, reset: "42m" },
            Override { model_id: "gemini-3.8-flash-medium", remaining: 0.92, reset: "1d 08h" },
        ],
        "acc-03" => &[
            Override { model_id: "gemini-3.8-flash-medium", remaining: 0.55, reset: "9h 30m" },
            Override { model_id: "gemini-3.5-flash-lite", remaining: 0.97, reset: "9h 30m" },
            Override { model_id: "gpt-oss-120b-medium", remaining: 0.34, reset: "3d 11h" },
        ],
        _ => &[
            Override { model_id: "gemini-3.8-flash-low", remaining: 0.0, reset: "—" },
            Override { model_id: "gemini-3-flash", remaining: 0.0, reset: "—" },
        ],
    }
}

fn weekly_overrides_for(account_id: &str) -> &'static [(&'static str, f64, &'static str)] {
    match account_id {
        "acc-01" => &[
            ("gemini", 0.86, "6d 23h"),
            ("claudeGpt", 0.64, "4d 02h"),
        ],
        "acc-02" => &[
            ("gemini", 0.41, "1d 08h"),
            ("claudeGpt", 0.12, "18h 40m"),
        ],
        "acc-03" => &[
            ("gemini", 0.97, "6d 23h"),
            ("claudeGpt", 0.88, "5d 11h"),
        ],
        _ => &[("gemini", 0.0, "—"), ("claudeGpt", 0.0, "—")],
    }
}

/// Builds one demo account.
fn build_account(
    id: &str,
    name: &str,
    handle: &str,
    provider: &str,
    plan: &str,
    status: AccountStatus,
    credits: i64,
    in_use: bool,
    recommended: bool,
    seeded: bool,
    catalog: &[Model],
    groups: &[ModelGroup],
) -> Account {
    let overrides = overrides_for(id);

    let quotas = catalog
        .iter()
        .map(|model| {
            let pinned = overrides
                .iter()
                .find(|entry| entry.model_id == model.id)
                .map(|entry| (entry.remaining, entry.reset.to_string()));
            let (remaining, reset_label) = match pinned {
                Some(value) => value,
                None if seeded => (
                    seeded_remaining(id, &model.id),
                    seeded_reset(id, &model.id),
                ),
                None => (0.0, "—".to_string()),
            };
            ModelQuota {
                name: model.label.clone(),
                family: model.family,
                remaining,
                reset_label,
            }
        })
        .collect();

    let weekly_quotas = groups
        .iter()
        .map(|group| {
            let pinned = weekly_overrides_for(id)
                .iter()
                .find(|(group_id, _, _)| *group_id == group.id);
            let (remaining, reset_label) = match pinned {
                Some((_, remaining, reset)) => (*remaining, reset.to_string()),
                None if seeded => (
                    seeded_weekly_remaining(id, &group.id),
                    seeded_weekly_reset(id, &group.id),
                ),
                None => (0.0, "—".to_string()),
            };
            WeeklyQuota {
                group_id: group.id.clone(),
                group_label: group.label.clone(),
                remaining,
                reset_label,
            }
        })
        .collect();

    Account {
        id: id.to_string(),
        name: name.to_string(),
        handle: handle.to_string(),
        provider: provider.to_string(),
        plan: plan.to_string(),
        status,
        credits,
        in_use,
        recommended,
        selected: false,
        // Every account of the synthetic dataset is a sample.
        demo: true,
        quotas,
        weekly_quotas,
    }
}

/// Writes the demo dataset into an empty profile.
pub fn seed_demo(repository: &SqliteAccountRepository) -> Result<(), crate::repository::RepositoryError> {
    let catalog = model_catalog();
    let groups = model_groups();

    repository.save_catalog(&catalog, &groups)?;
    repository.clear_accounts()?;

    let accounts = vec![
        build_account(
            "acc-01",
            "Northwind Studio",
            "northwind.studio@example.com",
            "Google",
            "Google AI Pro",
            AccountStatus::Active,
            2400,
            true,
            true,
            true,
            &catalog,
            &groups,
        ),
        build_account(
            "acc-02",
            "Atlas Labs",
            "atlas.labs@example.com",
            "Anthropic",
            "Claude Max",
            AccountStatus::RateLimited,
            860,
            false,
            false,
            true,
            &catalog,
            &groups,
        ),
        build_account(
            "acc-03",
            "Meridian Team",
            "meridian.team@example.com",
            "Google",
            "Google AI Ultra",
            AccountStatus::Idle,
            1240,
            false,
            false,
            true,
            &catalog,
            &groups,
        ),
        build_account(
            "acc-04",
            "Lumen Personal",
            "lumen.personal@example.com",
            "Google",
            "Google AI Pro",
            AccountStatus::Error,
            0,
            false,
            false,
            false,
            &catalog,
            &groups,
        ),
    ];

    for account in accounts {
        repository.save_account(&account)?;
    }

    Ok(())
}
