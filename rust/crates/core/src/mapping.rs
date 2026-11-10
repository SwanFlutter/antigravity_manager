//! Translation between the domain model and the wire contract.

use antigravity_contract::dto::{
    AccountDto, AccountListDto, AccountStatusDto, AccountSummaryDto, ModelDto, ModelFamilyDto,
    ModelQuotaDto, WeeklyQuotaDto, WorkspaceDto,
};

use crate::domain::{
    Account, AccountStatus, AccountSummary, Model, ModelFamily, ModelQuota, WeeklyQuota,
    Workspace,
};

/// Converts an account status into its wire representation.
pub fn status_to_dto(status: AccountStatus) -> AccountStatusDto {
    match status {
        AccountStatus::Active => AccountStatusDto::Active,
        AccountStatus::Idle => AccountStatusDto::Idle,
        AccountStatus::RateLimited => AccountStatusDto::RateLimited,
        AccountStatus::Error => AccountStatusDto::Error,
    }
}

/// Converts a model family into its wire representation.
pub fn family_to_dto(family: ModelFamily) -> ModelFamilyDto {
    match family {
        ModelFamily::Gemini => ModelFamilyDto::Gemini,
        ModelFamily::Claude => ModelFamilyDto::Claude,
        ModelFamily::Openai => ModelFamilyDto::Openai,
    }
}

/// Converts a model quota into its wire representation.
pub fn quota_to_dto(quota: &ModelQuota) -> ModelQuotaDto {
    ModelQuotaDto {
        name: quota.name.clone(),
        family: family_to_dto(quota.family),
        remaining: quota.remaining,
        reset_label: quota.reset_label.clone(),
    }
}

/// Converts a weekly quota into its wire representation.
pub fn weekly_to_dto(quota: &WeeklyQuota) -> WeeklyQuotaDto {
    WeeklyQuotaDto {
        group_id: quota.group_id.clone(),
        group_label: quota.group_label.clone(),
        remaining: quota.remaining,
        reset_label: quota.reset_label.clone(),
    }
}

/// Converts an account into its wire representation.
pub fn account_to_dto(account: &Account) -> AccountDto {
    AccountDto {
        id: account.id.clone(),
        name: account.name.clone(),
        handle: account.handle.clone(),
        provider: account.provider.clone(),
        plan: account.plan.clone(),
        status: status_to_dto(account.status),
        credits: account.credits,
        in_use: account.in_use,
        recommended: account.recommended,
        demo: account.demo,
        quotas: account.quotas.iter().map(quota_to_dto).collect(),
        weekly_quotas: account.weekly_quotas.iter().map(weekly_to_dto).collect(),
    }
}

/// Converts the aggregate counters into their wire representation.
pub fn summary_to_dto(summary: &AccountSummary) -> AccountSummaryDto {
    AccountSummaryDto {
        total: summary.total,
        active: summary.active,
        rate_limited: summary.rate_limited,
        global_remaining: summary.global_remaining,
    }
}

/// Converts an account list into its wire representation.
pub fn account_list_to_dto(accounts: &[Account], summary: &AccountSummary) -> AccountListDto {
    AccountListDto {
        accounts: accounts.iter().map(account_to_dto).collect(),
        summary: summary_to_dto(summary),
    }
}

/// Converts a model into its wire representation.
pub fn model_to_dto(model: &Model) -> ModelDto {
    ModelDto {
        id: model.id.clone(),
        label: model.label.clone(),
        family: family_to_dto(model.family),
    }
}

/// Converts a workspace profile into its wire representation.
///
/// The account name and the plan are joined by the caller, the unbound flag
/// tells whether the account of the workspace still has credentials.
pub fn workspace_to_dto(
    workspace: &Workspace,
    account_name: String,
    plan: String,
    unbound: bool,
) -> WorkspaceDto {
    WorkspaceDto {
        id: workspace.id.clone(),
        name: workspace.name.clone(),
        account_id: workspace.account_id.clone(),
        account_name,
        plan,
        project_folder: workspace.project_folder.clone(),
        profile_folder: workspace.profile_folder.clone(),
        last_active_at: workspace.last_active_at,
        state: workspace.state.as_str().to_string(),
        unbound,
    }
}
