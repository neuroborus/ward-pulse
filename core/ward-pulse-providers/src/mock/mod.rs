use std::error::Error as StdError;
use std::fmt;

use serde::Deserialize;
use ward_pulse_core::budget::calculate_budget_state;
use ward_pulse_core::model::{
    BudgetPeriod, CreditSource, CreditState, ModelUsage, Money, ProviderKind, ProviderSnapshot,
    ProviderStatus, UsageBucket,
};
use ward_pulse_core::time::DateTimeUtc;

fn usd(cents: i64) -> Money {
    Money::minor_units(cents, "USD")
}

pub fn mock_provider_snapshot(account_id: impl Into<String>) -> ProviderSnapshot {
    ProviderSnapshot {
        account_id: account_id.into(),
        provider: ProviderKind::Mock,
        status: ProviderStatus::Ok,
        today: calculate_budget_state(
            BudgetPeriod::Today,
            Some(usd(1_240)),
            Some(usd(5_000)),
            None,
        ),
        week: calculate_budget_state(
            BudgetPeriod::Week,
            Some(usd(7_130)),
            Some(usd(25_000)),
            Some(usd(22_800)),
        ),
        month: calculate_budget_state(
            BudgetPeriod::Month,
            Some(usd(21_210)),
            Some(usd(80_000)),
            Some(usd(74_200)),
        ),
        credits: vec![CreditState {
            remaining: Some(usd(1_875)),
            granted: Some(usd(2_500)),
            expires_at: Some("2026-07-31T00:00:00Z".into()),
            source: CreditSource::Provider,
        }],
        buckets: mock_usage_buckets(),
        model_breakdown: vec![ModelUsage {
            model: "mock-fast".to_string(),
            cost: Some(usd(1_240)),
            input_tokens: Some(120_000),
            output_tokens: Some(42_000),
            requests: Some(186),
        }],
        last_successful_sync_at: Some("2026-06-27T18:42:00Z".into()),
        last_error: None,
    }
}

fn mock_usage_buckets() -> Vec<UsageBucket> {
    vec![
        UsageBucket {
            start_at: "2026-06-27T00:00:00Z".into(),
            end_at: "2026-06-27T06:00:00Z".into(),
            cost: Some(usd(220)),
            input_tokens: Some(30_000),
            output_tokens: Some(9_000),
            cached_tokens: None,
            requests: Some(42),
            model: Some("mock-fast".to_string()),
            project: None,
            user: None,
        },
        UsageBucket {
            start_at: "2026-06-27T06:00:00Z".into(),
            end_at: "2026-06-27T12:00:00Z".into(),
            cost: Some(usd(310)),
            input_tokens: Some(28_000),
            output_tokens: Some(10_000),
            cached_tokens: None,
            requests: Some(48),
            model: Some("mock-fast".to_string()),
            project: None,
            user: None,
        },
        UsageBucket {
            start_at: "2026-06-27T12:00:00Z".into(),
            end_at: "2026-06-27T18:00:00Z".into(),
            cost: Some(usd(520)),
            input_tokens: Some(45_000),
            output_tokens: Some(17_000),
            cached_tokens: None,
            requests: Some(72),
            model: Some("mock-fast".to_string()),
            project: None,
            user: None,
        },
        UsageBucket {
            start_at: "2026-06-27T18:00:00Z".into(),
            end_at: "2026-06-27T18:42:00Z".into(),
            cost: Some(usd(190)),
            input_tokens: Some(17_000),
            output_tokens: Some(6_000),
            cached_tokens: None,
            requests: Some(24),
            model: Some("mock-fast".to_string()),
            project: None,
            user: None,
        },
    ]
}

#[derive(Clone, Debug, PartialEq)]
pub struct MockUsageFixtureSnapshot {
    pub generated_at: DateTimeUtc,
    pub provider_snapshot: ProviderSnapshot,
}

#[derive(Debug)]
pub enum MockUsageFixtureError {
    Json(serde_json::Error),
    UnexpectedProvider(ProviderKind),
}

impl fmt::Display for MockUsageFixtureError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::Json(error) => write!(formatter, "invalid mock usage fixture JSON: {error}"),
            Self::UnexpectedProvider(provider) => {
                write!(formatter, "expected mock usage fixture, found {provider:?}")
            }
        }
    }
}

impl StdError for MockUsageFixtureError {
    fn source(&self) -> Option<&(dyn StdError + 'static)> {
        match self {
            Self::Json(error) => Some(error),
            Self::UnexpectedProvider(_) => None,
        }
    }
}

impl From<serde_json::Error> for MockUsageFixtureError {
    fn from(error: serde_json::Error) -> Self {
        Self::Json(error)
    }
}

pub fn mock_provider_snapshot_from_usage_fixture(
    account_id: impl Into<String>,
    fixture: &str,
) -> Result<MockUsageFixtureSnapshot, MockUsageFixtureError> {
    let raw: RawMockUsageFixture = serde_json::from_str(fixture)?;
    if raw.provider != ProviderKind::Mock {
        return Err(MockUsageFixtureError::UnexpectedProvider(raw.provider));
    }

    let buckets = raw.buckets;
    let model_breakdown = model_usage_from_buckets(&buckets);
    let mut snapshot = mock_provider_snapshot(account_id);
    snapshot.provider = raw.provider;
    snapshot.today = calculate_budget_state(
        BudgetPeriod::Today,
        sum_bucket_cost(&buckets),
        Some(usd(5_000)),
        None,
    );
    snapshot.buckets = buckets;
    snapshot.model_breakdown = model_breakdown;
    snapshot.last_successful_sync_at = Some(raw.generated_at.clone());

    Ok(MockUsageFixtureSnapshot {
        generated_at: raw.generated_at,
        provider_snapshot: snapshot,
    })
}

pub fn mock_provider_budget_warning_snapshot(account_id: impl Into<String>) -> ProviderSnapshot {
    let mut snapshot = mock_provider_snapshot(account_id);
    snapshot.today = calculate_budget_state(
        BudgetPeriod::Today,
        Some(usd(4_500)),
        Some(usd(5_000)),
        None,
    );
    snapshot
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct RawMockUsageFixture {
    provider: ProviderKind,
    generated_at: DateTimeUtc,
    buckets: Vec<UsageBucket>,
}

fn sum_bucket_cost(buckets: &[UsageBucket]) -> Option<Money> {
    let mut total: Option<Money> = None;

    for bucket in buckets {
        let Some(cost) = &bucket.cost else {
            return None;
        };

        match &mut total {
            Some(total) if total.currency == cost.currency => {
                total.minor_units += cost.minor_units;
            }
            Some(_) => return None,
            None => total = Some(cost.clone()),
        }
    }

    total
}

fn model_usage_from_buckets(buckets: &[UsageBucket]) -> Vec<ModelUsage> {
    let mut breakdown: Vec<ModelUsage> = Vec::new();

    for bucket in buckets {
        let Some(model) = &bucket.model else {
            continue;
        };

        if let Some(usage) = breakdown.iter_mut().find(|usage| usage.model == *model) {
            merge_bucket_into_model_usage(usage, bucket);
        } else {
            breakdown.push(ModelUsage {
                model: model.clone(),
                cost: bucket.cost.clone(),
                input_tokens: bucket.input_tokens,
                output_tokens: bucket.output_tokens,
                requests: bucket.requests,
            });
        }
    }

    breakdown.sort_by(|left, right| left.model.cmp(&right.model));
    breakdown
}

fn merge_bucket_into_model_usage(usage: &mut ModelUsage, bucket: &UsageBucket) {
    merge_optional_money(&mut usage.cost, &bucket.cost);
    merge_optional_u64(&mut usage.input_tokens, bucket.input_tokens);
    merge_optional_u64(&mut usage.output_tokens, bucket.output_tokens);
    merge_optional_u64(&mut usage.requests, bucket.requests);
}

fn merge_optional_money(total: &mut Option<Money>, next: &Option<Money>) {
    match (total.as_mut(), next) {
        (Some(total), Some(next)) if total.currency == next.currency => {
            total.minor_units += next.minor_units;
        }
        (Some(_), Some(_)) | (Some(_), None) => *total = None,
        (None, _) => {}
    }
}

fn merge_optional_u64(total: &mut Option<u64>, next: Option<u64>) {
    *total = match (*total, next) {
        (Some(total), Some(next)) => Some(total + next),
        _ => None,
    };
}

#[cfg(test)]
mod tests {
    use super::*;

    const USAGE_TODAY_FIXTURE: &str =
        include_str!("../../../../fixtures/providers/mock/usage_today.json");

    #[test]
    fn parses_usage_fixture_into_provider_snapshot() {
        let fixture = mock_provider_snapshot_from_usage_fixture("mock-local", USAGE_TODAY_FIXTURE)
            .expect("parse mock usage fixture");

        assert_eq!(
            fixture.generated_at,
            DateTimeUtc::from("2026-06-27T18:42:00Z")
        );
        assert_eq!(
            fixture.provider_snapshot.last_successful_sync_at,
            Some(DateTimeUtc::from("2026-06-27T18:42:00Z"))
        );
        assert_eq!(fixture.provider_snapshot.buckets.len(), 4);
        assert_eq!(fixture.provider_snapshot.today.spent, Some(usd(1_240)));
        assert_eq!(
            fixture.provider_snapshot.model_breakdown,
            vec![ModelUsage {
                model: "mock-fast".to_string(),
                cost: Some(usd(1_240)),
                input_tokens: Some(120_000),
                output_tokens: Some(42_000),
                requests: Some(186),
            }]
        );
    }

    #[test]
    fn keeps_usage_cost_unknown_when_fixture_bucket_cost_is_missing() {
        let mut value: serde_json::Value =
            serde_json::from_str(USAGE_TODAY_FIXTURE).expect("parse fixture JSON value");
        value["buckets"][0]["cost"] = serde_json::Value::Null;
        let fixture_json = serde_json::to_string(&value).expect("serialize fixture JSON value");

        let fixture = mock_provider_snapshot_from_usage_fixture("mock-local", &fixture_json)
            .expect("parse mock usage fixture");

        assert_eq!(fixture.provider_snapshot.today.spent, None);
        assert_eq!(fixture.provider_snapshot.model_breakdown[0].cost, None);
    }

    #[test]
    fn rejects_non_mock_usage_fixture() {
        let fixture =
            USAGE_TODAY_FIXTURE.replacen("\"provider\": \"mock\"", "\"provider\": \"openai\"", 1);
        let error = mock_provider_snapshot_from_usage_fixture("mock-local", &fixture)
            .expect_err("reject non-mock fixture");

        assert!(matches!(
            error,
            MockUsageFixtureError::UnexpectedProvider(ProviderKind::OpenAi)
        ));
    }
}
