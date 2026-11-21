use crate::time::DateTimeUtc;
use serde::{Deserialize, Serialize};

mod identity;
mod legacy;

pub use legacy::ProviderKind;

pub use identity::{
    ConnectionKind, ProviderConnectionId, ProviderFamily, ProviderIdentity, ProviderSource,
    SourceOrigin,
};

pub type AccountId = String;

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

/// Legacy storage keys shared with the phone. Canonical source decisions use
/// [`ProviderConnectionId`]; unknown explicit boundary keys remain accepted.
pub mod connection {
    pub const CODEX_PLAN: &str = "openai.plan";
    pub const OPENAI_PLATFORM: &str = "openai.platform";
    pub const CLAUDE_PLAN: &str = "anthropic.plan";
    pub const ANTHROPIC_PLATFORM: &str = "anthropic.platform";
    pub const CURSOR_PLAN: &str = "cursor.plan";
    pub const CURSOR_PLATFORM: &str = "cursor.platform";
    pub const MOCK_PLAN: &str = "mock.plan";
}

/// Private local history scope, bound by the shell to accepted credentials.
///
/// `identity` is the existing lifecycle identity digest, never credential bytes.
/// Lifecycle generation/revision/epoch prove currentness, not history identity.
#[derive(Clone, Debug, PartialEq, Eq, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct HistoryOwner {
    pub connection: String,
    pub identity: String,
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
    pub provider: ProviderIdentity,
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

/// Included Plan constraints required by one target, within its account and owner.
/// Incomplete evidence is scoped to that target; raw usage and resets stay independent.
#[derive(Clone, Debug, PartialEq, Eq, Deserialize, Serialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct RecoveryRequirements {
    pub allowance_ids: Vec<String>,
    pub complete: bool,
}

/// Optional context must never make an otherwise valid snapshot or saved key unreadable.
pub fn deserialize_recovery_requirements<'de, D>(
    deserializer: D,
) -> Result<Option<RecoveryRequirements>, D::Error>
where
    D: serde::Deserializer<'de>,
{
    #[derive(Deserialize)]
    #[serde(untagged)]
    enum Context {
        Valid(RecoveryRequirements),
        Invalid(serde::de::IgnoredAny),
    }
    Ok(match Context::deserialize(deserializer)? {
        Context::Valid(requirements)
            if !requirements.allowance_ids.is_empty()
                && requirements
                    .allowance_ids
                    .iter()
                    .enumerate()
                    .all(|(index, id)| {
                        !id.is_empty() && !requirements.allowance_ids[..index].contains(id)
                    }) =>
        {
            Some(requirements)
        }
        Context::Valid(_) => None,
        Context::Invalid(ignored) => {
            let _ = ignored;
            None
        }
    })
}

#[derive(Clone, Debug, PartialEq, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct AllowanceState {
    #[serde(
        default,
        skip_serializing_if = "Option::is_none",
        deserialize_with = "deserialize_recovery_requirements"
    )]
    pub recovery_requirements: Option<RecoveryRequirements>,
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
    #[serde(flatten)]
    pub source: ProviderSource,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub history_owner: Option<HistoryOwner>,
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

/// Structural threshold identity, independent of its label and configured value.
#[derive(Clone, Debug, PartialEq, Eq, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct AlertConditionKey {
    pub provider: ProviderIdentity,
    pub account_id: AccountId,
    /// Rule-routing identity, including compatibility fallback; not source evidence.
    pub connection: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub history_owner: Option<HistoryOwner>,
    pub target: AlertConditionTarget,
}

#[derive(Clone, Debug, PartialEq, Eq, Deserialize, Serialize)]
#[serde(tag = "kind", rename_all = "camelCase")]
pub enum AlertConditionTarget {
    Allowance { source: AllowanceSource, id: String },
    Budget { period: BudgetPeriod },
}

/// A crossed observation carries the exact alert emitted by the evaluator.
#[derive(Clone, Debug, PartialEq, Eq, Deserialize, Serialize)]
#[serde(tag = "state", rename_all = "camelCase")]
pub enum AlertConditionState {
    Crossed { alert: Alert },
    Clear,
    Unknown,
}

/// One enabled threshold observed in the snapshot; absence is not clearance.
#[derive(Clone, Debug, PartialEq, Eq, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct AlertCondition {
    pub key: AlertConditionKey,
    #[serde(flatten)]
    pub state: AlertConditionState,
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
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub alert_conditions: Vec<AlertCondition>,
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

    #[test]
    fn six_sources_keep_their_exact_legacy_boundary() {
        let tags = ["codex", "openai", "claude", "claude", "cursor", "cursor"];
        let keys = [
            "openai.plan",
            "openai.platform",
            "anthropic.plan",
            "anthropic.platform",
            "cursor.plan",
            "cursor.platform",
        ];
        for ((id, tag), key) in ProviderConnectionId::ALL.into_iter().zip(tags).zip(keys) {
            assert_eq!(id.storage_key(), key);
            assert_eq!(ProviderConnectionId::from_storage_key(key), Some(id));
            let source = ProviderSource::connection(id);
            assert_eq!(source.origin(), SourceOrigin::Connection(id));
            assert_eq!(source.provider().family(), Some(id.family));
            let encoded = serde_json::to_value(&source).unwrap();
            assert_eq!(
                encoded,
                serde_json::json!({"provider": tag, "connection": key})
            );
            assert_eq!(
                serde_json::from_value::<ProviderSource>(encoded).unwrap(),
                source
            );
        }
        assert_eq!(ProviderConnectionId::from_storage_key("future.plan"), None);
        let mock = ProviderSource::mock();
        assert_eq!(mock.origin(), SourceOrigin::Mock);
        assert_eq!(mock.provider().family(), None);
        assert_eq!(
            serde_json::to_value(mock).unwrap(),
            serde_json::json!({"provider": "mock", "connection": "mock.plan"})
        );
    }

    #[test]
    fn legacy_snapshots_preserve_unresolved_and_unknown_sources() {
        let golden: serde_json::Value = serde_json::from_str(include_str!(
            "../../../../fixtures/snapshots/dashboard_today.json"
        ))
        .unwrap();
        for (tag, origin) in [
            (
                "openai",
                SourceOrigin::Connection(ProviderConnectionId::OPENAI_PLATFORM),
            ),
            (
                "codex",
                SourceOrigin::Connection(ProviderConnectionId::OPENAI_PLAN),
            ),
            ("claude", SourceOrigin::UnresolvedLegacy),
            ("cursor", SourceOrigin::UnresolvedLegacy),
            ("mock", SourceOrigin::Mock),
        ] {
            for connection in [
                None,
                Some(serde_json::Value::Null),
                Some(serde_json::json!("future.source")),
            ] {
                let mut value = golden["accounts"][0].clone();
                value["provider"] = tag.into();
                value.as_object_mut().unwrap().remove("connection");
                if let Some(connection) = &connection {
                    value["connection"] = connection.clone();
                }
                let snapshot: ProviderSnapshot = serde_json::from_value(value.clone()).unwrap();
                let expected = if connection.as_ref().is_some_and(|c| c.is_string()) {
                    SourceOrigin::UnresolvedLegacy
                } else {
                    origin
                };
                assert_eq!(snapshot.source.origin(), expected, "{tag}: {connection:?}");
                let fallback = match tag {
                    "openai" => "openai.platform",
                    "codex" => "openai.plan",
                    "claude" => "anthropic.plan",
                    "cursor" => "cursor.plan",
                    "mock" => "mock.plan",
                    _ => unreachable!(),
                };
                assert_eq!(
                    snapshot.source.alert_connection(),
                    if connection.as_ref().is_some_and(|c| c.is_string()) {
                        "future.source"
                    } else {
                        fallback
                    }
                );
                if connection == Some(serde_json::Value::Null) {
                    value.as_object_mut().unwrap().remove("connection");
                }
                assert_eq!(serde_json::to_value(snapshot).unwrap(), value);
            }
        }
        let mismatched = serde_json::json!({"provider": "claude", "connection": "openai.plan"});
        let source: ProviderSource = serde_json::from_value(mismatched.clone()).unwrap();
        assert_eq!(source.origin(), SourceOrigin::UnresolvedLegacy);
        assert_eq!(source.provider().family(), Some(ProviderFamily::Anthropic));
        assert_eq!(serde_json::to_value(source).unwrap(), mismatched);
    }

    #[test]
    fn old_accounts_have_family_membership_without_an_invented_source() {
        for (tag, family) in [
            ("openai", Some(ProviderFamily::OpenAi)),
            ("codex", Some(ProviderFamily::OpenAi)),
            ("claude", Some(ProviderFamily::Anthropic)),
            ("cursor", Some(ProviderFamily::Cursor)),
            ("mock", None),
        ] {
            let value = serde_json::json!({"id": "account", "provider": tag, "displayName": "Local", "workspaceName": null, "maskedCredential": null, "enabled": true, "budget": null});
            let account: ProviderAccount = serde_json::from_value(value.clone()).unwrap();
            assert_eq!(account.provider.family(), family);
            assert_eq!(serde_json::to_value(account).unwrap(), value);
        }
    }

    #[test]
    fn condition_keys_keep_legacy_provider_tokens_and_required_connection() {
        for (tag, connection) in [
            ("openai", "openai.platform"),
            ("codex", "openai.plan"),
            ("claude", "anthropic.plan"),
            ("claude", "anthropic.platform"),
            ("cursor", "cursor.plan"),
            ("cursor", "cursor.platform"),
            ("cursor", "future.source"),
            ("mock", "mock.plan"),
        ] {
            let value = serde_json::json!({"provider": tag, "accountId": "same-account", "connection": connection, "historyOwner": {"connection": connection, "identity": "accepted-owner"}, "target": {"kind": "allowance", "source": "plan", "id": "same-window"}});
            let key: AlertConditionKey = serde_json::from_value(value.clone()).unwrap();
            assert_eq!(serde_json::to_value(key).unwrap(), value);
            let mut missing = value;
            missing.as_object_mut().unwrap().remove("connection");
            assert!(serde_json::from_value::<AlertConditionKey>(missing).is_err());
        }
    }
}
