//! Pure mapping of the upstream Google responses onto the core domain types.
//!
//! Every function here takes the parsed JSON of an upstream answer and returns
//! the core types. They never touch the network, so they can be unit tested
//! with recorded payloads.

use antigravity_core::cloud::{format_reset_label, QuotaBucket, QuotaGroup};
use antigravity_core::domain::{Model, ModelFamily, ModelQuota};
use std::collections::{HashMap, HashSet};
use crate::GoogleError;
use serde_json::Value;

use crate::time::parse_rfc3339_millis;

/// The project context of a connected account.
#[derive(Debug, Clone, PartialEq, Eq, Default)]
pub struct ProjectContext {
    pub project_id: Option<String>,
    pub plan: Option<String>,
    pub credits: Option<i64>,
}

/// Maps the answer of `v1internal:loadCodeAssist`.
///
/// The project id is the `cloudaicompanionProject` field, the plan is the paid
/// tier name (or its id) and the credits are the sum of the available credit
/// amounts.
pub fn map_project_context(payload: &Value) -> ProjectContext {
    let project_id = payload
        .get("cloudaicompanionProject")
        .and_then(|project| project.as_str().or_else(|| project.get("id")?.as_str()))
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .map(str::to_string);

    let paid_tier = payload.get("paidTier");
    let plan = [paid_tier, payload.get("currentTier")]
        .into_iter()
        .flatten()
        .find_map(|tier| {
            ["name", "id"].into_iter().find_map(|key| {
                tier.get(key)?.as_str().map(str::trim)
                    .filter(|value| !value.is_empty()).map(str::to_string)
            })
        });

    let credits = payload
        .get("availableCredits")
        .and_then(Value::as_array)
        .or_else(|| {
            paid_tier
                .and_then(|tier| tier.get("availableCredits"))
                .and_then(Value::as_array)
        })
        .map(|credits| {
            credits
                .iter()
                .filter_map(|credit| credit.get("creditAmount"))
                .filter_map(parse_credit_amount)
                .sum::<i64>()
        });

    ProjectContext {
        project_id,
        plan,
        credits,
    }
}

/// Reads a credit amount, which upstream sends as a number or as a string.
fn parse_credit_amount(value: &Value) -> Option<i64> {
    match value {
        Value::Number(number) => number.as_i64().or_else(|| number.as_f64().map(|f| f as i64)),
        Value::String(text) => text.trim().parse::<i64>().ok(),
        _ => None,
    }
}

/// The provider family of a model id.
///
/// Upstream tracks only the Gemini, Claude, GPT and image model families.
/// Every other id is ignored.
pub fn model_family_for(model_id: &str) -> Option<ModelFamily> {
    let lowered = model_id.trim_start().to_ascii_lowercase();
    if lowered.starts_with("gemini") {
        Some(ModelFamily::Gemini)
    } else if lowered.starts_with("claude") {
        Some(ModelFamily::Claude)
    } else if lowered.starts_with("gpt") {
        Some(ModelFamily::Openai)
    } else if lowered.starts_with("image") || lowered.starts_with("imagen") {
        Some(ModelFamily::Gemini)
    } else {
        None
    }
}

/// Catalog and known quotas from a single `fetchAvailableModels` response.
#[derive(Debug, Clone, PartialEq)]
pub struct ModelQuotaSnapshot {
    pub models: Vec<Model>,
    pub quotas: Vec<ModelQuota>,
}

/// Maps actual provider ids and labels separately from unique quota row names.
/// Unknown fractions are omitted, not interpreted as exhausted quotas.
pub fn map_model_quotas(payload: &Value, now_millis: i64) -> Result<ModelQuotaSnapshot, GoogleError> {
    let entries = payload.get("models").and_then(Value::as_object)
        .ok_or_else(|| GoogleError::Malformed("models must be an object".to_string()))?;
    if entries.iter().any(|(id, info)| id.trim().is_empty() || !info.is_object()) {
        return Err(GoogleError::Malformed("models must contain model objects with nonempty ids".to_string()));
    }
    let models: Vec<Model> = entries.iter().filter_map(|(id, info)| {
        Some(Model {
            id: id.clone(),
            label: info.get("displayName").and_then(Value::as_str)
                .map(str::trim).filter(|label| !label.is_empty())
                .unwrap_or(id).to_string(),
            family: model_family_for(id)?,
        })
    }).collect();
    let mut counts = HashMap::new();
    for model in &models {
        *counts.entry(model.label.as_str()).or_insert(0) += 1;
    }
    // Reserve original labels too: a provider label may itself look like a
    // disambiguated name. Never let it collide with a generated quota key.
    let mut used: HashSet<String> = models.iter().map(|model| model.label.clone()).collect();
    let mut quotas = Vec::new();
    for model in &models {
        let mut name = model.label.clone();
        if counts[model.label.as_str()] > 1 {
            loop {
                name = format!("{name} ({})", model.id);
                if used.insert(name.clone()) {
                    break;
                }
            }
        }
        let quota = &entries[&model.id]["quotaInfo"];
        let Some(remaining) = quota.get("remainingFraction").and_then(parse_fraction) else {
            continue;
        };
        let reset_at = quota.get("resetTime").and_then(Value::as_str)
            .and_then(parse_rfc3339_millis);
        quotas.push(ModelQuota {
            name,
            family: model.family,
            remaining,
            reset_label: format_reset_label(reset_at, now_millis),
        });
    }
    Ok(ModelQuotaSnapshot { models, quotas })
}

fn parse_fraction(value: &Value) -> Option<f64> {
    let fraction = value.as_f64().or_else(|| value.as_str()?.trim().parse::<f64>().ok())?;
    (fraction.is_finite() && (0.0..=1.0).contains(&fraction)).then_some(fraction)
}

/// Maps the answer of `v1internal:retrieveUserQuotaSummary` onto quota groups.
///
/// The id of a group is a stable slug of its display name, so the interface
/// can keep the selection of a group across refreshes.
pub fn map_quota_groups(payload: &Value) -> Vec<QuotaGroup> {
    let Some(groups) = payload.get("groups").and_then(Value::as_array) else {
        return Vec::new();
    };

    groups
        .iter()
        .map(|group| {
            let display_name = group
                .get("displayName")
                .and_then(Value::as_str)
                .map(str::trim)
                .filter(|value| !value.is_empty());
            let id = display_name.map(slugify).unwrap_or_default();
            let label = display_name.unwrap_or(id.as_str()).to_string();

            let buckets = group
                .get("buckets")
                .and_then(Value::as_array)
                .map(|buckets| buckets.iter().filter_map(map_quota_bucket).collect())
                .unwrap_or_default();

            QuotaGroup { id, label, buckets }
        })
        .collect()
}

/// Maps one bucket of a quota group.
fn map_quota_bucket(bucket: &Value) -> Option<QuotaBucket> {
    let bucket_id = bucket
        .get("bucketId")
        .and_then(Value::as_str)
        .unwrap_or_default()
        .to_string();
    let window = bucket
        .get("window")
        .and_then(Value::as_str)
        .unwrap_or_default()
        .to_string();
    let remaining = bucket.get("remainingFraction").and_then(parse_fraction)?;
    let reset_at = bucket
        .get("resetTime")
        .and_then(Value::as_str)
        .and_then(parse_rfc3339_millis);
    let label = bucket
        .get("displayName")
        .and_then(Value::as_str)
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .unwrap_or(bucket_id.as_str())
        .to_string();

    Some(QuotaBucket {
        bucket_id,
        window,
        remaining,
        reset_at,
        label,
    })
}

/// Turns a display name into a stable slug.
///
/// The name is lowercased and every character that is not a letter or a digit
/// becomes a dash, so `Gemini models` becomes `gemini-models`.
pub fn slugify(value: &str) -> String {
    let mut slug = String::with_capacity(value.len());
    for character in value.chars() {
        if character.is_alphanumeric() {
            slug.extend(character.to_lowercase());
        } else if !slug.ends_with('-') {
            slug.push('-');
        }
    }
    slug.trim_matches('-').to_string()
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn maps_the_project_context() {
        let payload = json!({
            "cloudaicompanionProject": "projects/antigravity-123",
            "currentTier": { "id": "free-tier", "name": "Free" },
            "paidTier": { "id": "gcp-enterprise", "name": "Enterprise" },
            "allowedTiers": [{ "id": "gcp-enterprise" }],
            "ineligibleTiers": [],
            "availableCredits": [
                { "creditType": "PAID", "creditAmount": "120", "minimumCreditAmountForUsage": 1 },
                { "creditType": "PAID", "creditAmount": 30.0, "minimumCreditAmountForUsage": 1 }
            ]
        });

        let context = map_project_context(&payload);

        assert_eq!(
            context.project_id.as_deref(),
            Some("projects/antigravity-123")
        );
        assert_eq!(context.plan.as_deref(), Some("Enterprise"));
        assert_eq!(context.credits, Some(150));
    }

    #[test]
    fn falls_back_to_the_paid_tier_id() {
        let payload = json!({ "paidTier": { "id": "gcp-enterprise" } });

        let context = map_project_context(&payload);

        assert_eq!(context.plan.as_deref(), Some("gcp-enterprise"));
        assert_eq!(context.project_id, None);
        assert_eq!(context.credits, None);
    }

    #[test]
    fn maps_the_model_quotas() {
        let payload = json!({
            "models": {
                "gemini-3-pro": {
                    "displayName": "Gemini 3 Pro",
                    "quotaInfo": { "remainingFraction": 0.75, "resetTime": "2026-01-02T03:04:05Z" }
                },
                "claude-sonnet-4": {
                    "displayName": "Claude Sonnet 4",
                    "quotaInfo": { "remainingFraction": 0.25, "resetTime": "2026-01-02T03:04:05Z" }
                },
                "gpt-5": { "quotaInfo": { "remainingFraction": 1.0 } },
                "imagen-4": { "displayName": "Imagen 4" },
                "unknown-model": { "displayName": "Unknown" }
            },
            "deprecatedModelIds": {}
        });

        let snapshot = map_model_quotas(&payload, 1_767_320_645_000)
            .expect("the payload maps");

        // The catalog carries every model with a known family, including the
        // one that reports no quota at all.
        assert_eq!(snapshot.models.len(), 4);
        // A model without a known family is skipped and an unknown fraction is
        // omitted, never read as an exhausted quota.
        assert_eq!(snapshot.quotas.len(), 3);

        let find = |name: &str| {
            snapshot
                .quotas
                .iter()
                .find(|quota| quota.name == name)
                .unwrap_or_else(|| panic!("{name} is mapped"))
        };

        let gemini = find("Gemini 3 Pro");
        assert_eq!(gemini.family, ModelFamily::Gemini);
        assert!((gemini.remaining - 0.75).abs() < f64::EPSILON);
        assert_eq!(gemini.reset_label, "40m");

        let claude = find("Claude Sonnet 4");
        assert_eq!(claude.family, ModelFamily::Claude);
        assert!((claude.remaining - 0.25).abs() < f64::EPSILON);
        assert_eq!(claude.reset_label, "40m");

        // A model without a display name falls back to its id.
        let gpt = find("gpt-5");
        assert_eq!(gpt.family, ModelFamily::Openai);
        assert!((gpt.remaining - 1.0).abs() < f64::EPSILON);
        // A model without a quota has no reset time.
        assert_eq!(gpt.reset_label, "—");

        // `imagen` belongs to the Gemini family and carries no quota row.
        assert!(
            snapshot
                .models
                .iter()
                .any(|model| model.id == "imagen-4" && model.label == "Imagen 4")
        );
        assert!(snapshot.quotas.iter().all(|quota| quota.name != "Imagen 4"));
    }

    #[test]
    fn maps_the_quota_groups() {
        let payload = json!({
            "groups": [
                {
                    "displayName": "Gemini models",
                    "description": "weekly allowance",
                    "buckets": [
                        {
                            "bucketId": "week",
                            "window": "week",
                            "remainingFraction": 0.5,
                            "resetTime": "2026-01-02T03:04:05Z",
                            "displayName": "Weekly"
                        },
                        { "bucketId": "day", "window": "day", "remainingFraction": 0.9 }
                    ]
                },
                { "displayName": "Claude models", "buckets": [] }
            ]
        });

        let groups = map_quota_groups(&payload);

        assert_eq!(groups.len(), 2);
        assert_eq!(groups[0].id, "gemini-models");
        assert_eq!(groups[0].label, "Gemini models");
        assert_eq!(groups[0].buckets.len(), 2);

        let weekly = &groups[0].buckets[0];
        assert_eq!(weekly.bucket_id, "week");
        assert_eq!(weekly.window, "week");
        assert!((weekly.remaining - 0.5).abs() < f64::EPSILON);
        assert_eq!(weekly.reset_at, Some(1_767_323_045_000));
        assert_eq!(weekly.label, "Weekly");

        let daily = &groups[0].buckets[1];
        assert_eq!(daily.bucket_id, "day");
        assert!((daily.remaining - 0.9).abs() < f64::EPSILON);
        assert_eq!(daily.reset_at, None);
        assert_eq!(daily.label, "day");

        assert_eq!(groups[1].id, "claude-models");
        assert!(groups[1].buckets.is_empty());
    }

    #[test]
    fn maps_the_model_families() {
        assert_eq!(model_family_for("gemini-3-pro"), Some(ModelFamily::Gemini));
        assert_eq!(model_family_for("GEMINI-3-pro"), Some(ModelFamily::Gemini));
        assert_eq!(model_family_for("claude-sonnet-4"), Some(ModelFamily::Claude));
        assert_eq!(model_family_for("gpt-5-codex"), Some(ModelFamily::Openai));
        assert_eq!(model_family_for("imagen-4"), Some(ModelFamily::Gemini));
        assert_eq!(model_family_for("image-pro"), Some(ModelFamily::Gemini));
        assert_eq!(model_family_for("llama-3"), None);
        assert_eq!(model_family_for(""), None);
    }

    #[test]
    fn slugs_the_display_names() {
        assert_eq!(slugify("Gemini models"), "gemini-models");
        assert_eq!(slugify("Claude 4.5 models"), "claude-4-5-models");
        assert_eq!(slugify("  spaced  out  "), "spaced-out");
        assert_eq!(slugify("!!!"), "");
    }
}
