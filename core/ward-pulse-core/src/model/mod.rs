use crate::time::DateTimeUtc;
use serde::{Deserialize, Serialize};

pub type AccountId = String;

#[derive(Clone, Copy, Debug, PartialEq, Eq, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub enum ProviderKind {
    #[serde(rename = "openai")]
    OpenAi,
    Codex,
    Claude,
    Cursor,
    Mock,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub enum ProviderStatus {
    Ok,
    Warning,
    Error,
    RateLimited,
    AuthRequired,
    Stale,
    Unknown,
}

impl ProviderStatus {
    /// Most severe status, or `Unknown` when there is nothing to judge.
    pub fn worst(statuses: impl IntoIterator<Item = Self>) -> Self {
        statuses
            .into_iter()
            .max_by_key(|status| status.severity())
            .unwrap_or(Self::Unknown)
    }

    /// Aggregation rank. Ranks are distinct, so [`Self::worst`] never depends on
    /// input order. `Unknown` outranks `Ok`: a surface that reported nothing
    /// must not read as healthy.
    fn severity(self) -> u8 {
        match self {
            Self::Ok => 1,
            Self::Unknown => 2,
            Self::Stale => 3,
            Self::Warning => 4,
            Self::RateLimited => 5,
            Self::AuthRequired => 6,
            Self::Error => 7,
        }
    }
}

/// Phone `ProviderConnectionId.storageKey` values.
///
/// One provider kind can back two connections — a subscription plan and an
/// organization API — so [`ProviderKind`] alone cannot say which one produced a
/// snapshot. The adapter that owns a connection stamps its key into
/// [`ProviderSnapshot::connection`], and user alert rules are keyed by it.
pub mod connection {
    pub const CODEX_PLAN: &str = "openai.plan";
    pub const OPENAI_PLATFORM: &str = "openai.platform";
    pub const CLAUDE_PLAN: &str = "anthropic.plan";
    pub const ANTHROPIC_PLATFORM: &str = "anthropic.platform";
    pub const CURSOR_PLAN: &str = "cursor.plan";
    pub const CURSOR_PLATFORM: &str = "cursor.platform";
    pub const MOCK_PLAN: &str = "mock.plan";
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub enum BudgetPeriod {
    Today,
    Week,
    Month,
}

#[derive(Clone, Debug, PartialEq, Eq, Deserialize, Serialize)]
#[serde(transparent)]
pub struct CurrencyCode(String);

impl CurrencyCode {
    pub fn new(value: impl Into<String>) -> Self {
        Self(value.into())
    }

    pub fn as_str(&self) -> &str {
        &self.0
    }
}

impl From<&str> for CurrencyCode {
    fn from(value: &str) -> Self {
        Self::new(value)
    }
}

impl From<String> for CurrencyCode {
    fn from(value: String) -> Self {
        Self::new(value)
    }
}

#[derive(Clone, Debug, PartialEq, Eq, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Money {
    pub minor_units: i64,
    pub currency: CurrencyCode,
}

impl Money {
    pub fn minor_units(minor_units: i64, currency: impl Into<CurrencyCode>) -> Self {
        Self {
            minor_units,
            currency: currency.into(),
        }
    }
}

#[derive(Clone, Debug, PartialEq, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct BudgetPolicy {
    pub daily_limit: Option<Money>,
    pub weekly_limit: Option<Money>,
    pub monthly_limit: Option<Money>,
    pub warn_at_percent: u8,
}

#[derive(Clone, Debug, PartialEq, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct BudgetState {
    pub period: BudgetPeriod,
    pub spent: Option<Money>,
    pub limit: Option<Money>,
    pub remaining: Option<Money>,
    pub used_percent: Option<f64>,
    pub projected_total: Option<Money>,
    pub status: ProviderStatus,
}

#[derive(Clone, Debug, PartialEq, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ProviderAccount {
    pub id: AccountId,
    pub provider: ProviderKind,
    pub display_name: String,
    pub workspace_name: Option<String>,
    pub masked_credential: Option<String>,
    pub enabled: bool,
    pub budget: Option<BudgetPolicy>,
}

#[derive(Clone, Debug, PartialEq, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct UsageBucket {
    pub start_at: DateTimeUtc,
    pub end_at: DateTimeUtc,
    pub cost: Option<Money>,
    pub input_tokens: Option<u64>,
    pub output_tokens: Option<u64>,
    pub cached_tokens: Option<u64>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub total_tokens: Option<u64>,
    pub requests: Option<u64>,
    pub model: Option<String>,
    pub project: Option<String>,
    pub user: Option<String>,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub enum CreditSource {
    Provider,
    Promo,
    Manual,
    Unknown,
}

#[derive(Clone, Debug, PartialEq, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct CreditState {
    pub remaining: Option<Money>,
    pub granted: Option<Money>,
    pub expires_at: Option<DateTimeUtc>,
    pub source: CreditSource,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub enum AllowanceSource {
    Plan,
    Purchased,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub enum QuantityUnit {
    Tokens,
    Credits,
}

#[derive(Clone, Debug, PartialEq, Eq, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Quantity {
    pub value: String,
    pub unit: QuantityUnit,
}

#[derive(Clone, Debug, PartialEq, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct AllowanceState {
    pub id: String,
    pub source: AllowanceSource,
    pub label: String,
    pub used_percent: Option<f64>,
    pub used: Option<Quantity>,
    pub limit: Option<Quantity>,
    pub remaining: Option<Quantity>,
    #[serde(default, skip_serializing_if = "is_false")]
    pub unlimited: bool,
    pub window_minutes: Option<u64>,
    pub resets_at: Option<DateTimeUtc>,
    pub status: ProviderStatus,
}

fn is_false(value: &bool) -> bool {
    !value
}

#[derive(Clone, Debug, PartialEq, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ModelUsage {
    pub model: String,
    pub cost: Option<Money>,
    pub input_tokens: Option<u64>,
    pub output_tokens: Option<u64>,
    pub requests: Option<u64>,
}

#[derive(Clone, Debug, PartialEq, Eq, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ProviderErrorSummary {
    pub code: String,
    pub message: String,
}

#[derive(Clone, Debug, PartialEq, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ProviderSnapshot {
    pub account_id: AccountId,
    pub provider: ProviderKind,
    /// Owning connection, as a [`connection`] key. `None` on snapshots built
    /// before adapters stamped it; alerts then fall back to the provider's plan.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub connection: Option<String>,
    pub status: ProviderStatus,
    pub today: BudgetState,
    pub week: BudgetState,
    pub month: BudgetState,
    pub credits: Vec<CreditState>,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub allowances: Vec<AllowanceState>,
    pub buckets: Vec<UsageBucket>,
    pub model_breakdown: Vec<ModelUsage>,
    pub last_successful_sync_at: Option<DateTimeUtc>,
    pub last_error: Option<ProviderErrorSummary>,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub enum AlertSeverity {
    Info,
    Warning,
    Error,
}

#[derive(Clone, Debug, PartialEq, Eq, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Alert {
    pub severity: AlertSeverity,
    pub message: String,
}

#[derive(Clone, Debug, PartialEq, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct WatchSummary {
    pub today_used_percent: Option<f64>,
    pub week_used_percent: Option<f64>,
    pub status: ProviderStatus,
}

#[derive(Clone, Debug, PartialEq, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct DashboardSnapshot {
    pub generated_at: DateTimeUtc,
    pub overall_status: ProviderStatus,
    pub accounts: Vec<ProviderSnapshot>,
    pub today_total: BudgetState,
    pub week_total: BudgetState,
    pub month_total: BudgetState,
    pub alerts: Vec<Alert>,
    pub watch_summary: WatchSummary,
}

#[cfg(test)]
mod tests {
    use std::collections::BTreeSet;

    use super::*;

    #[test]
    fn worst_status_keeps_an_unreported_surface_above_a_healthy_one() {
        let statuses = [ProviderStatus::Unknown, ProviderStatus::Ok];

        assert_eq!(ProviderStatus::worst(statuses), ProviderStatus::Unknown);
    }

    /// Distinct ranks are what keep [`ProviderStatus::worst`] order-independent:
    /// `max_by_key` would otherwise return whichever tied value came last.
    #[test]
    fn every_status_has_a_distinct_severity() {
        let statuses = [
            ProviderStatus::Ok,
            ProviderStatus::Warning,
            ProviderStatus::Error,
            ProviderStatus::RateLimited,
            ProviderStatus::AuthRequired,
            ProviderStatus::Stale,
            ProviderStatus::Unknown,
        ];

        let severities: BTreeSet<u8> = statuses.iter().map(|status| status.severity()).collect();
        assert_eq!(severities.len(), statuses.len());
    }

    #[test]
    fn worst_status_of_nothing_is_unknown() {
        assert_eq!(ProviderStatus::worst([]), ProviderStatus::Unknown);
    }

    #[test]
    fn serializes_provider_kinds_as_stable_contract_values() {
        let values = [
            ProviderKind::OpenAi,
            ProviderKind::Codex,
            ProviderKind::Claude,
            ProviderKind::Cursor,
            ProviderKind::Mock,
        ]
        .map(|provider| serde_json::to_string(&provider).expect("serialize provider kind"));

        assert_eq!(
            values,
            [
                "\"openai\"",
                "\"codex\"",
                "\"claude\"",
                "\"cursor\"",
                "\"mock\""
            ]
        );
    }
}
