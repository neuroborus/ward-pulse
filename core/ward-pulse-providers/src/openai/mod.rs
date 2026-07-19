use std::collections::BTreeMap;
use std::error::Error as StdError;
use std::fmt;

use serde::Deserialize;
use serde_json::Number;
use ward_pulse_core::budget::calculate_budget_state;
use ward_pulse_core::model::{
    BudgetPeriod, ModelUsage, Money, ProviderKind, ProviderSnapshot, ProviderStatus, UsageBucket,
};
use ward_pulse_core::time::DateTimeUtc;

use crate::{BucketCapabilities, ProviderCapabilities};

pub const PROVIDER_NAME: &str = "OpenAI";

pub(crate) const CAPABILITIES: ProviderCapabilities = ProviderCapabilities {
    supports_cost: true,
    supports_tokens: true,
    supports_requests: true,
    supports_credits: false,
    usage_buckets: BucketCapabilities::DAILY_AND_HOURLY,
    cost_buckets: BucketCapabilities::DAILY,
    supports_usage_model_breakdown: true,
    supports_cost_model_breakdown: false,
    supports_workspace_breakdown: false,
    supports_active_agents: false,
};

#[derive(Clone, Debug, PartialEq)]
pub struct OpenAiReportSnapshot {
    pub generated_at: DateTimeUtc,
    pub provider_snapshot: ProviderSnapshot,
}

#[derive(Debug)]
pub enum OpenAiReportError {
    Json(serde_json::Error),
    InvalidCurrency(String),
    InvalidAmount(String),
    InvalidTimestamp(i64),
    NumericOverflow,
}

impl fmt::Display for OpenAiReportError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::Json(error) => write!(formatter, "invalid OpenAI report JSON: {error}"),
            Self::InvalidCurrency(currency) => {
                write!(formatter, "invalid OpenAI cost currency: {currency}")
            }
            Self::InvalidAmount(amount) => {
                write!(formatter, "invalid OpenAI cost amount: {amount}")
            }
            Self::InvalidTimestamp(timestamp) => {
                write!(formatter, "invalid OpenAI bucket timestamp: {timestamp}")
            }
            Self::NumericOverflow => formatter.write_str("OpenAI report value overflow"),
        }
    }
}

impl StdError for OpenAiReportError {
    fn source(&self) -> Option<&(dyn StdError + 'static)> {
        match self {
            Self::Json(error) => Some(error),
            Self::InvalidCurrency(_)
            | Self::InvalidAmount(_)
            | Self::InvalidTimestamp(_)
            | Self::NumericOverflow => None,
        }
    }
}

impl From<serde_json::Error> for OpenAiReportError {
    fn from(error: serde_json::Error) -> Self {
        Self::Json(error)
    }
}

pub fn openai_provider_snapshot_from_report_json(
    report_json: &str,
) -> Result<OpenAiReportSnapshot, OpenAiReportError> {
    let report: RawReport = serde_json::from_str(report_json)?;
    let mut usage_by_bucket = BTreeMap::<(i64, i64), UsageTotals>::new();
    let mut model_breakdown = BTreeMap::<String, UsageTotals>::new();

    for page_json in &report.usage_pages {
        let page: RawUsagePage = serde_json::from_str(page_json)?;
        for bucket in &page.data {
            let totals = usage_by_bucket
                .entry((bucket.start_time, bucket.end_time))
                .or_default();

            for result in &bucket.results {
                totals.add(result)?;
                if let Some(model) = result.model.as_deref() {
                    model_breakdown
                        .entry(model.to_string())
                        .or_default()
                        .add(result)?;
                }
            }
        }
    }

    let mut cost_by_bucket = BTreeMap::<(i64, i64), DecimalAmount>::new();
    for page_json in &report.cost_pages {
        let page: RawCostPage = serde_json::from_str(page_json)?;
        for bucket in &page.data {
            let mut bucket_cost = DecimalAmount::default();
            for result in &bucket.results {
                let Some(amount) = &result.amount else {
                    continue;
                };
                let (Some(value), Some(currency)) = (&amount.value, &amount.currency) else {
                    continue;
                };
                normalize_currency(currency)?;

                bucket_cost = bucket_cost.checked_add(DecimalAmount::from_number(value)?)?;
            }
            let total = cost_by_bucket
                .entry((bucket.start_time, bucket.end_time))
                .or_default();
            *total = total.checked_add(bucket_cost)?;
        }
    }

    let buckets = merge_buckets(&usage_by_bucket, &cost_by_bucket)?;
    let model_breakdown = model_breakdown
        .into_iter()
        .map(|(model, totals)| ModelUsage {
            model,
            cost: None,
            input_tokens: Some(totals.input_tokens),
            output_tokens: Some(totals.output_tokens),
            requests: Some(totals.requests),
        })
        .collect();
    let today = report.budget_state(BudgetPeriod::Today, report.today_start, &cost_by_bucket)?;
    let week = report.budget_state(BudgetPeriod::Week, report.week_start, &cost_by_bucket)?;
    let month = report.budget_state(BudgetPeriod::Month, report.month_start, &cost_by_bucket)?;
    let provider_snapshot = ProviderSnapshot {
        account_id: report.account_id,
        provider: ProviderKind::OpenAi,
        status: ProviderStatus::Ok,
        today,
        week,
        month,
        credits: Vec::new(),
        buckets,
        model_breakdown,
        last_successful_sync_at: Some(report.generated_at.clone()),
        last_error: None,
    };

    Ok(OpenAiReportSnapshot {
        generated_at: report.generated_at,
        provider_snapshot,
    })
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct RawReport {
    account_id: String,
    generated_at: DateTimeUtc,
    today_start: i64,
    week_start: i64,
    month_start: i64,
    usage_pages: Vec<String>,
    cost_pages: Vec<String>,
}

impl RawReport {
    fn budget_state(
        &self,
        period: BudgetPeriod,
        start: i64,
        costs: &BTreeMap<(i64, i64), DecimalAmount>,
    ) -> Result<ward_pulse_core::model::BudgetState, OpenAiReportError> {
        let total = costs
            .iter()
            .filter(|((bucket_start, _), _)| *bucket_start >= start)
            .try_fold(DecimalAmount::default(), |total, (_, value)| {
                total.checked_add(*value)
            })?;
        let spent = Some(Money::minor_units(total.to_minor_units()?, "USD"));

        Ok(calculate_budget_state(period, spent, None, None))
    }
}

#[derive(Debug, Deserialize)]
struct RawUsagePage {
    data: Vec<RawUsageBucket>,
}

#[derive(Debug, Deserialize)]
struct RawUsageBucket {
    start_time: i64,
    end_time: i64,
    results: Vec<RawUsageResult>,
}

#[derive(Debug, Deserialize)]
struct RawUsageResult {
    input_tokens: u64,
    output_tokens: u64,
    input_cached_tokens: Option<u64>,
    num_model_requests: u64,
    model: Option<String>,
}

#[derive(Debug, Deserialize)]
struct RawCostPage {
    data: Vec<RawCostBucket>,
}

#[derive(Debug, Deserialize)]
struct RawCostBucket {
    start_time: i64,
    end_time: i64,
    results: Vec<RawCostResult>,
}

#[derive(Debug, Deserialize)]
struct RawCostResult {
    amount: Option<RawAmount>,
}

#[derive(Debug, Deserialize)]
struct RawAmount {
    value: Option<Number>,
    currency: Option<String>,
}

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
struct DecimalAmount {
    coefficient: i128,
    scale: u32,
}

impl DecimalAmount {
    fn new(mut coefficient: i128, mut scale: u32) -> Self {
        if coefficient == 0 {
            return Self::default();
        }

        while scale > 0 && coefficient % 10 == 0 {
            coefficient /= 10;
            scale -= 1;
        }

        Self { coefficient, scale }
    }

    fn from_number(value: &Number) -> Result<Self, OpenAiReportError> {
        let source = value.to_string();
        let (mantissa, exponent) = match source.split_once(['e', 'E']) {
            Some((mantissa, exponent)) => {
                let exponent = exponent
                    .parse::<i32>()
                    .map_err(|_| OpenAiReportError::InvalidAmount(source.clone()))?;
                (mantissa, exponent)
            }
            None => (source.as_str(), 0),
        };
        let (integer, fraction) = mantissa.split_once('.').unwrap_or((mantissa, ""));
        let coefficient = format!("{integer}{fraction}")
            .parse::<i128>()
            .map_err(|_| OpenAiReportError::InvalidAmount(source.clone()))?;
        let fractional_digits = i32::try_from(fraction.len())
            .map_err(|_| OpenAiReportError::InvalidAmount(source.clone()))?;
        let decimal_places = fractional_digits
            .checked_sub(exponent)
            .ok_or_else(|| OpenAiReportError::InvalidAmount(source.clone()))?;

        if coefficient == 0 {
            Ok(Self::default())
        } else if decimal_places >= 0 {
            Ok(Self::new(coefficient, decimal_places as u32))
        } else {
            Ok(Self::new(
                coefficient
                    .checked_mul(power_of_ten(decimal_places.unsigned_abs())?)
                    .ok_or(OpenAiReportError::NumericOverflow)?,
                0,
            ))
        }
    }

    fn checked_add(self, other: Self) -> Result<Self, OpenAiReportError> {
        if self.coefficient == 0 {
            return Ok(other);
        }
        if other.coefficient == 0 {
            return Ok(self);
        }

        let scale = self.scale.max(other.scale);
        let left = self
            .coefficient
            .checked_mul(power_of_ten(scale - self.scale)?)
            .ok_or(OpenAiReportError::NumericOverflow)?;
        let right = other
            .coefficient
            .checked_mul(power_of_ten(scale - other.scale)?)
            .ok_or(OpenAiReportError::NumericOverflow)?;

        Ok(Self::new(
            left.checked_add(right)
                .ok_or(OpenAiReportError::NumericOverflow)?,
            scale,
        ))
    }

    fn to_minor_units(self) -> Result<i64, OpenAiReportError> {
        let minor_units = if self.scale <= 2 {
            self.coefficient
                .checked_mul(power_of_ten(2 - self.scale)?)
                .ok_or(OpenAiReportError::NumericOverflow)?
        } else if self.scale - 2 > 38 {
            0
        } else {
            let divisor = power_of_ten(self.scale - 2)?;
            let quotient = self.coefficient / divisor;
            let remainder = self.coefficient % divisor;
            let round_away_from_zero = remainder.unsigned_abs() >= ((divisor + 1) / 2) as u128;

            quotient
                .checked_add(if round_away_from_zero {
                    self.coefficient.signum()
                } else {
                    0
                })
                .ok_or(OpenAiReportError::NumericOverflow)?
        };

        i64::try_from(minor_units).map_err(|_| OpenAiReportError::NumericOverflow)
    }
}

#[derive(Clone, Debug, Default)]
struct UsageTotals {
    input_tokens: u64,
    output_tokens: u64,
    cached_tokens: u64,
    requests: u64,
}

impl UsageTotals {
    fn add(&mut self, result: &RawUsageResult) -> Result<(), OpenAiReportError> {
        self.input_tokens = self
            .input_tokens
            .checked_add(result.input_tokens)
            .ok_or(OpenAiReportError::NumericOverflow)?;
        self.output_tokens = self
            .output_tokens
            .checked_add(result.output_tokens)
            .ok_or(OpenAiReportError::NumericOverflow)?;
        self.cached_tokens = self
            .cached_tokens
            .checked_add(result.input_cached_tokens.unwrap_or_default())
            .ok_or(OpenAiReportError::NumericOverflow)?;
        self.requests = self
            .requests
            .checked_add(result.num_model_requests)
            .ok_or(OpenAiReportError::NumericOverflow)?;
        Ok(())
    }
}

fn merge_buckets(
    usage: &BTreeMap<(i64, i64), UsageTotals>,
    costs: &BTreeMap<(i64, i64), DecimalAmount>,
) -> Result<Vec<UsageBucket>, OpenAiReportError> {
    let mut periods = usage
        .keys()
        .chain(costs.keys())
        .copied()
        .collect::<Vec<_>>();
    periods.sort_unstable();
    periods.dedup();

    periods
        .into_iter()
        .map(|(start, end)| {
            let usage = usage.get(&(start, end));
            let cost = costs
                .get(&(start, end))
                .map(|value| value.to_minor_units())
                .transpose()?
                .map(|value| Money::minor_units(value, "USD"));

            Ok(UsageBucket {
                start_at: unix_seconds_to_utc(start)?,
                end_at: unix_seconds_to_utc(end)?,
                cost,
                input_tokens: usage.map(|value| value.input_tokens),
                output_tokens: usage.map(|value| value.output_tokens),
                cached_tokens: usage.map(|value| value.cached_tokens),
                requests: usage.map(|value| value.requests),
                model: None,
                project: None,
                user: None,
            })
        })
        .collect()
}

fn normalize_currency(currency: &str) -> Result<(), OpenAiReportError> {
    if currency.eq_ignore_ascii_case("usd") {
        Ok(())
    } else {
        Err(OpenAiReportError::InvalidCurrency(currency.to_string()))
    }
}

fn power_of_ten(exponent: u32) -> Result<i128, OpenAiReportError> {
    10_i128
        .checked_pow(exponent)
        .ok_or(OpenAiReportError::NumericOverflow)
}

fn unix_seconds_to_utc(timestamp: i64) -> Result<DateTimeUtc, OpenAiReportError> {
    let days = timestamp.div_euclid(86_400);
    let seconds = timestamp.rem_euclid(86_400);
    let (year, month, day) =
        civil_from_days(days).ok_or(OpenAiReportError::InvalidTimestamp(timestamp))?;
    let hour = seconds / 3_600;
    let minute = seconds % 3_600 / 60;
    let second = seconds % 60;

    Ok(DateTimeUtc::new(format!(
        "{year:04}-{month:02}-{day:02}T{hour:02}:{minute:02}:{second:02}Z"
    )))
}

fn civil_from_days(days_since_epoch: i64) -> Option<(i64, i64, i64)> {
    let days = days_since_epoch.checked_add(719_468)?;
    let era = if days >= 0 { days } else { days - 146_096 } / 146_097;
    let day_of_era = days - era * 146_097;
    let year_of_era =
        (day_of_era - day_of_era / 1_460 + day_of_era / 36_524 - day_of_era / 146_096) / 365;
    let mut year = year_of_era + era * 400;
    let day_of_year = day_of_era - (365 * year_of_era + year_of_era / 4 - year_of_era / 100);
    let month_prime = (5 * day_of_year + 2) / 153;
    let day = day_of_year - (153 * month_prime + 2) / 5 + 1;
    let month = month_prime + if month_prime < 10 { 3 } else { -9 };
    year += i64::from(month <= 2);

    Some((year, month, day))
}

#[cfg(test)]
mod tests {
    use super::*;

    const USAGE_FIXTURE: &str =
        include_str!("../../../../fixtures/providers/openai/usage_completions.json");
    const COST_FIXTURE: &str = include_str!("../../../../fixtures/providers/openai/costs.json");

    fn report_json() -> String {
        serde_json::json!({
            "accountId": "openai-local",
            "generatedAt": "2026-07-19T12:00:00Z",
            "todayStart": 1_784_419_200_i64,
            "weekStart": 1_783_900_800_i64,
            "monthStart": 1_782_864_000_i64,
            "usagePages": [USAGE_FIXTURE],
            "costPages": [COST_FIXTURE]
        })
        .to_string()
    }

    #[test]
    fn normalizes_openai_usage_and_cost_reports() {
        let report = openai_provider_snapshot_from_report_json(&report_json())
            .expect("normalize OpenAI report");
        let snapshot = report.provider_snapshot;

        assert_eq!(snapshot.provider, ProviderKind::OpenAi);
        assert_eq!(snapshot.status, ProviderStatus::Ok);
        assert_eq!(snapshot.today.spent, Some(Money::minor_units(50, "USD")));
        assert_eq!(snapshot.week.spent, Some(Money::minor_units(280, "USD")));
        assert_eq!(snapshot.month.spent, Some(Money::minor_units(400, "USD")));
        assert_eq!(snapshot.buckets.len(), 3);
        assert_eq!(snapshot.buckets[2].input_tokens, Some(3_500));
        assert_eq!(snapshot.buckets[2].cached_tokens, Some(600));
        assert_eq!(snapshot.model_breakdown.len(), 2);
        assert_eq!(snapshot.model_breakdown[0].model, "gpt-example");
        assert_eq!(snapshot.model_breakdown[0].input_tokens, Some(4_500));
        assert_eq!(snapshot.model_breakdown[0].cost, None);
    }

    #[test]
    fn converts_provider_timestamps_to_utc() {
        assert_eq!(
            unix_seconds_to_utc(1_784_462_400).expect("valid timestamp"),
            DateTimeUtc::from("2026-07-19T12:00:00Z")
        );
    }

    #[test]
    fn rounds_decimal_currency_without_floating_point() {
        let values = [
            ("1.005", 101),
            ("0.004", 0),
            ("1e1", 1_000),
            ("-1.005", -101),
            ("-0.004", 0),
            ("1e-100", 0),
            ("90071992547409.995", 9_007_199_254_741_000),
        ];

        for (source, expected) in values {
            let value: Number = serde_json::from_str(source).expect("JSON number");
            assert_eq!(
                DecimalAmount::from_number(&value)
                    .and_then(DecimalAmount::to_minor_units)
                    .expect("valid cost amount"),
                expected
            );
        }
    }

    #[test]
    fn rejects_non_usd_costs() {
        let mut report: serde_json::Value =
            serde_json::from_str(&report_json()).expect("report JSON");
        report["costPages"] = serde_json::json!([COST_FIXTURE.replace("\"usd\"", "\"eur\"")]);

        assert!(matches!(
            openai_provider_snapshot_from_report_json(&report.to_string()),
            Err(OpenAiReportError::InvalidCurrency(currency)) if currency == "eur"
        ));
    }

    #[test]
    fn treats_missing_optional_cost_amounts_as_zero() {
        let mut report: serde_json::Value =
            serde_json::from_str(&report_json()).expect("report JSON");
        let costs = serde_json::json!({
            "data": [{
                "start_time": 1_784_419_200_i64,
                "end_time": 1_784_505_600_i64,
                "results": [
                    {},
                    {"amount": {}},
                    {"amount": {"value": 1}},
                    {"amount": {"currency": "usd"}}
                ]
            }]
        })
        .to_string();
        report["costPages"] = serde_json::json!([costs]);

        let snapshot = openai_provider_snapshot_from_report_json(&report.to_string())
            .expect("normalize optional cost amounts")
            .provider_snapshot;

        assert_eq!(snapshot.today.spent, Some(Money::minor_units(0, "USD")));
        assert_eq!(
            snapshot
                .buckets
                .last()
                .and_then(|bucket| bucket.cost.clone()),
            Some(Money::minor_units(0, "USD"))
        );
    }

    #[test]
    fn treats_an_empty_cost_report_as_zero() {
        let mut report: serde_json::Value =
            serde_json::from_str(&report_json()).expect("report JSON");
        report["costPages"] = serde_json::json!([serde_json::json!({"data": []}).to_string()]);

        let snapshot = openai_provider_snapshot_from_report_json(&report.to_string())
            .expect("normalize empty cost report")
            .provider_snapshot;

        assert_eq!(snapshot.today.spent, Some(Money::minor_units(0, "USD")));
        assert_eq!(snapshot.week.spent, Some(Money::minor_units(0, "USD")));
        assert_eq!(snapshot.month.spent, Some(Money::minor_units(0, "USD")));
    }

    #[test]
    fn rounds_period_totals_after_summing_subcent_costs() {
        let mut report: serde_json::Value =
            serde_json::from_str(&report_json()).expect("report JSON");
        let costs = serde_json::json!({
            "data": [
                {
                    "start_time": 1_784_332_800_i64,
                    "end_time": 1_784_419_200_i64,
                    "results": [{"amount": {"value": 0.004, "currency": "usd"}}]
                },
                {
                    "start_time": 1_784_419_200_i64,
                    "end_time": 1_784_505_600_i64,
                    "results": [{"amount": {"value": 0.004, "currency": "usd"}}]
                }
            ]
        })
        .to_string();
        report["costPages"] = serde_json::json!([costs]);

        let snapshot = openai_provider_snapshot_from_report_json(&report.to_string())
            .expect("normalize subcent costs")
            .provider_snapshot;

        assert_eq!(snapshot.today.spent, Some(Money::minor_units(0, "USD")));
        assert_eq!(snapshot.week.spent, Some(Money::minor_units(1, "USD")));
        assert_eq!(snapshot.month.spent, Some(Money::minor_units(1, "USD")));
    }
}
