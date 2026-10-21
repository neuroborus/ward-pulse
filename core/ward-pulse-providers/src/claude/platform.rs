//! Anthropic organization Usage & Cost Admin API normalization.

use std::collections::BTreeMap;
use std::error::Error as StdError;
use std::fmt;

use serde::Deserialize;
use ward_pulse_core::budget::calculate_budget_state;
use ward_pulse_core::model::{
    connection, BudgetPeriod, ModelUsage, Money, ProviderKind, ProviderSnapshot, ProviderStatus,
    UsageBucket,
};
use ward_pulse_core::time::DateTimeUtc;

#[derive(Clone, Debug, PartialEq)]
pub struct AnthropicReportSnapshot {
    pub generated_at: DateTimeUtc,
    pub provider_snapshot: ProviderSnapshot,
}

#[derive(Debug)]
pub enum AnthropicReportError {
    ReportJson(serde_json::Error),
    UsageJson(serde_json::Error),
    CostsJson(serde_json::Error),
    InvalidCurrency(String),
    InvalidAmount,
    NumericOverflow,
}

impl fmt::Display for AnthropicReportError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::ReportJson(error) => write!(
                formatter,
                "invalid Anthropic report JSON at line {} column {}",
                error.line(),
                error.column()
            ),
            Self::UsageJson(error) => write!(
                formatter,
                "invalid Anthropic usage JSON at line {} column {}",
                error.line(),
                error.column()
            ),
            Self::CostsJson(error) => write!(
                formatter,
                "invalid Anthropic costs JSON at line {} column {}",
                error.line(),
                error.column()
            ),
            Self::InvalidCurrency(_) => formatter.write_str("invalid Anthropic cost currency"),
            Self::InvalidAmount => formatter.write_str("invalid Anthropic cost amount"),
            Self::NumericOverflow => formatter.write_str("Anthropic report value overflow"),
        }
    }
}

impl StdError for AnthropicReportError {
    fn source(&self) -> Option<&(dyn StdError + 'static)> {
        match self {
            Self::ReportJson(error) | Self::UsageJson(error) | Self::CostsJson(error) => {
                Some(error)
            }
            Self::InvalidCurrency(_) | Self::InvalidAmount | Self::NumericOverflow => None,
        }
    }
}

/// Normalizes sanitized Anthropic Admin API usage and cost pages.
pub fn anthropic_provider_snapshot_from_report_json(
    report_json: &str,
) -> Result<AnthropicReportSnapshot, AnthropicReportError> {
    let report: RawReport =
        serde_json::from_str(report_json).map_err(AnthropicReportError::ReportJson)?;
    let mut usage_by_bucket = BTreeMap::<DateTimeUtc, (DateTimeUtc, UsageTotals)>::new();
    let mut model_breakdown = BTreeMap::<String, UsageTotals>::new();

    for page_json in &report.usage_pages {
        let page: RawUsagePage =
            serde_json::from_str(page_json).map_err(AnthropicReportError::UsageJson)?;
        for bucket in &page.data {
            let day_start = bucket.starting_at.as_str().split_once('T').map_or_else(
                || bucket.starting_at.clone(),
                |(day, _)| DateTimeUtc::new(format!("{day}T00:00:00Z")),
            );
            let (end, totals) = usage_by_bucket
                .entry(day_start)
                .or_insert_with(|| (bucket.ending_at.clone(), UsageTotals::default()));
            *end = end.clone().max(bucket.ending_at.clone());
            for result in &bucket.results {
                totals.add(result);
                if let Some(model) = result.model.as_deref() {
                    model_breakdown
                        .entry(model.to_string())
                        .or_default()
                        .add(result);
                }
            }
        }
    }

    let mut cost_by_bucket = BTreeMap::<DateTimeUtc, (DateTimeUtc, i64)>::new();
    for page_json in &report.cost_pages {
        let page: RawCostPage =
            serde_json::from_str(page_json).map_err(AnthropicReportError::CostsJson)?;
        for bucket in &page.data {
            let mut bucket_cents = 0_i64;
            for result in &bucket.results {
                if let Some(currency) = result.currency.as_deref() {
                    normalize_currency(currency)?;
                }
                if let Some(amount) = result.amount.as_deref() {
                    bucket_cents = bucket_cents
                        .checked_add(cents_from_decimal(amount)?)
                        .ok_or(AnthropicReportError::NumericOverflow)?;
                }
            }
            let (end, entry) = cost_by_bucket
                .entry(bucket.starting_at.clone())
                .or_insert_with(|| (bucket.ending_at.clone(), 0));
            *end = end.clone().max(bucket.ending_at.clone());
            *entry = entry
                .checked_add(bucket_cents)
                .ok_or(AnthropicReportError::NumericOverflow)?;
        }
    }

    let buckets = merge_buckets(&usage_by_bucket, &cost_by_bucket);
    let model_breakdown = model_breakdown
        .into_iter()
        .map(|(model, totals)| ModelUsage {
            model,
            cost: None,
            input_tokens: Some(totals.input_tokens),
            output_tokens: Some(totals.output_tokens),
            requests: None,
        })
        .collect();

    let today = budget_for(BudgetPeriod::Today, &report.today_start, &buckets)?;
    let week = budget_for(BudgetPeriod::Week, &report.week_start, &buckets)?;
    let month = budget_for(BudgetPeriod::Month, &report.month_start, &buckets)?;

    Ok(AnthropicReportSnapshot {
        generated_at: report.generated_at.clone(),
        provider_snapshot: ProviderSnapshot {
            account_id: report.account_id,
            provider: ProviderKind::Claude,
            connection: Some(connection::ANTHROPIC_PLATFORM.to_string()),
            status: ProviderStatus::Ok,
            today,
            week,
            month,
            credits: Vec::new(),
            allowances: Vec::new(),
            buckets,
            model_breakdown,
            last_successful_sync_at: Some(report.generated_at),
            last_error: None,
        },
    })
}

fn budget_for(
    period: BudgetPeriod,
    start: &DateTimeUtc,
    buckets: &[UsageBucket],
) -> Result<ward_pulse_core::model::BudgetState, AnthropicReportError> {
    let mut total = 0_i64;
    let mut reported = false;
    let mut complete = true;
    for bucket in buckets.iter().filter(|bucket| &bucket.start_at >= start) {
        reported = true;
        if let Some(cost) = &bucket.cost {
            total = total
                .checked_add(cost.minor_units)
                .ok_or(AnthropicReportError::NumericOverflow)?;
        } else {
            complete = false;
        }
    }
    Ok(calculate_budget_state(
        period,
        (reported && complete).then(|| Money::minor_units(total, "USD")),
        None,
        None,
    ))
}

fn merge_buckets(
    usage: &BTreeMap<DateTimeUtc, (DateTimeUtc, UsageTotals)>,
    costs: &BTreeMap<DateTimeUtc, (DateTimeUtc, i64)>,
) -> Vec<UsageBucket> {
    let mut keys: Vec<_> = usage.keys().cloned().chain(costs.keys().cloned()).collect();
    keys.sort();
    keys.dedup();

    keys.into_iter()
        .map(|start| {
            let usage = usage.get(&start);
            let cost = costs.get(&start);
            let end = usage
                .map(|(end, _)| end)
                .into_iter()
                .chain(cost.map(|(end, _)| end))
                .max()
                .expect("day has usage or cost")
                .clone();
            let totals = usage.map(|(_, totals)| *totals);
            UsageBucket {
                start_at: start,
                end_at: end,
                cost: cost.map(|(_, minor)| Money::minor_units(*minor, "USD")),
                input_tokens: totals.map(|value| value.input_tokens),
                output_tokens: totals.map(|value| value.output_tokens),
                cached_tokens: totals.map(|value| value.cached_tokens),
                total_tokens: totals.map(|value| {
                    value
                        .input_tokens
                        .saturating_add(value.output_tokens)
                        .saturating_add(value.cached_tokens)
                }),
                requests: None,
                model: None,
                project: None,
                user: None,
            }
        })
        .collect()
}

/// Anthropic cost amounts are decimal strings in lowest currency units (cents).
fn cents_from_decimal(source: &str) -> Result<i64, AnthropicReportError> {
    let (integer, fraction) = source.split_once('.').unwrap_or((source, ""));
    if !fraction.bytes().all(|digit| digit.is_ascii_digit()) {
        return Err(AnthropicReportError::InvalidAmount);
    }
    let whole: i64 = integer
        .parse()
        .map_err(|_| AnthropicReportError::InvalidAmount)?;
    // Round half away from zero on the first fractional digit.
    let round_up = fraction.bytes().next().is_some_and(|digit| digit >= b'5');
    if round_up {
        whole
            .checked_add(if whole >= 0 { 1 } else { -1 })
            .ok_or(AnthropicReportError::NumericOverflow)
    } else {
        Ok(whole)
    }
}

fn normalize_currency(currency: &str) -> Result<(), AnthropicReportError> {
    if currency.eq_ignore_ascii_case("usd") {
        Ok(())
    } else {
        Err(AnthropicReportError::InvalidCurrency(currency.to_string()))
    }
}

#[derive(Clone, Copy, Debug, Default)]
struct UsageTotals {
    input_tokens: u64,
    output_tokens: u64,
    cached_tokens: u64,
}

impl UsageTotals {
    fn add(&mut self, result: &RawUsageResult) {
        let cache_creation = result
            .cache_creation
            .as_ref()
            .map(|value| {
                value
                    .ephemeral_1h_input_tokens
                    .saturating_add(value.ephemeral_5m_input_tokens)
            })
            .unwrap_or(0);
        self.input_tokens = self
            .input_tokens
            .saturating_add(result.uncached_input_tokens);
        self.output_tokens = self.output_tokens.saturating_add(result.output_tokens);
        self.cached_tokens = self
            .cached_tokens
            .saturating_add(result.cache_read_input_tokens)
            .saturating_add(cache_creation);
    }
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct RawReport {
    account_id: String,
    generated_at: DateTimeUtc,
    today_start: DateTimeUtc,
    week_start: DateTimeUtc,
    month_start: DateTimeUtc,
    usage_pages: Vec<String>,
    cost_pages: Vec<String>,
}

#[derive(Debug, Deserialize)]
struct RawUsagePage {
    data: Vec<RawUsageBucket>,
}

#[derive(Debug, Deserialize)]
struct RawUsageBucket {
    starting_at: DateTimeUtc,
    ending_at: DateTimeUtc,
    results: Vec<RawUsageResult>,
}

#[derive(Debug, Deserialize)]
struct RawUsageResult {
    #[serde(default)]
    uncached_input_tokens: u64,
    #[serde(default)]
    output_tokens: u64,
    #[serde(default)]
    cache_read_input_tokens: u64,
    #[serde(default)]
    cache_creation: Option<RawCacheCreation>,
    #[serde(default)]
    model: Option<String>,
}

#[derive(Debug, Deserialize)]
struct RawCacheCreation {
    #[serde(default)]
    ephemeral_1h_input_tokens: u64,
    #[serde(default)]
    ephemeral_5m_input_tokens: u64,
}

#[derive(Debug, Deserialize)]
struct RawCostPage {
    data: Vec<RawCostBucket>,
}

#[derive(Debug, Deserialize)]
struct RawCostBucket {
    starting_at: DateTimeUtc,
    ending_at: DateTimeUtc,
    results: Vec<RawCostResult>,
}

#[derive(Debug, Deserialize)]
struct RawCostResult {
    #[serde(default)]
    amount: Option<String>,
    #[serde(default)]
    currency: Option<String>,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn normalizes_usage_and_cost_pages() {
        let usage = include_str!("../../../../fixtures/providers/claude/usage_report.json");
        let costs = include_str!("../../../../fixtures/providers/claude/cost_report.json");
        let report = serde_json::json!({
            "accountId": "anthropic-local",
            "generatedAt": "2026-07-19T12:00:00Z",
            "todayStart": "2026-07-19T00:00:00Z",
            "weekStart": "2026-07-13T00:00:00Z",
            "monthStart": "2026-07-01T00:00:00Z",
            "usagePages": [usage],
            "costPages": [costs]
        })
        .to_string();

        let snapshot =
            anthropic_provider_snapshot_from_report_json(&report).expect("normalize Anthropic");
        assert_eq!(snapshot.provider_snapshot.provider, ProviderKind::Claude);
        assert!(snapshot.provider_snapshot.today.spent.is_some());
        assert!(!snapshot.provider_snapshot.buckets.is_empty());
    }

    #[test]
    fn coalesces_current_day_minutes_without_inventing_cost_or_future_coverage() {
        let usage = serde_json::json!({
            "data": [{
                "starting_at": "2026-07-18T00:00:00Z",
                "ending_at": "2026-07-19T00:00:00Z",
                "results": [{
                    "uncached_input_tokens": 10,
                    "output_tokens": 5,
                    "cache_read_input_tokens": 3,
                    "model": "model-a"
                }]
            }, {
                "starting_at": "2026-07-19T00:00:00Z",
                "ending_at": "2026-07-19T00:01:00Z",
                "results": [{
                    "uncached_input_tokens": 7,
                    "output_tokens": 2,
                    "cache_read_input_tokens": 3,
                    "cache_creation": {
                        "ephemeral_1h_input_tokens": 4,
                        "ephemeral_5m_input_tokens": 5
                    },
                    "model": "model-a"
                }]
            }]
        })
        .to_string();
        let next_usage = serde_json::json!({
            "data": [{
                "starting_at": "2026-07-19T00:01:00Z",
                "ending_at": "2026-07-19T00:02:00Z",
                "results": [{
                    "uncached_input_tokens": 11,
                    "output_tokens": 3,
                    "cache_read_input_tokens": 4,
                    "model": "model-a"
                }, {
                    "uncached_input_tokens": 2,
                    "output_tokens": 1,
                    "model": "model-b"
                }]
            }]
        })
        .to_string();
        let costs = serde_json::json!({
            "data": [{
                "starting_at": "2026-07-18T00:00:00Z",
                "ending_at": "2026-07-19T00:00:00Z",
                "results": [{"amount": "25", "currency": "usd"}]
            }]
        })
        .to_string();
        let report = serde_json::json!({
            "accountId": "anthropic-local",
            "generatedAt": "2026-07-19T00:02:30Z",
            "todayStart": "2026-07-19T00:00:00Z",
            "weekStart": "2026-07-13T00:00:00Z",
            "monthStart": "2026-07-01T00:00:00Z",
            "usagePages": [usage, next_usage],
            "costPages": [costs]
        })
        .to_string();

        let provider = anthropic_provider_snapshot_from_report_json(&report)
            .expect("normalize daily and minute usage")
            .provider_snapshot;

        assert_eq!(provider.buckets.len(), 2);
        let historical = &provider.buckets[0];
        assert_eq!(historical.cost, Some(Money::minor_units(25, "USD")));
        assert_eq!(historical.total_tokens, Some(18));
        let current = &provider.buckets[1];
        assert_eq!(historical.end_at, current.start_at);
        assert_eq!(current.start_at.as_str(), "2026-07-19T00:00:00Z");
        assert_eq!(current.end_at.as_str(), "2026-07-19T00:02:00Z");
        assert_eq!(current.input_tokens, Some(20));
        assert_eq!(current.output_tokens, Some(6));
        assert_eq!(current.cached_tokens, Some(16));
        assert_eq!(current.total_tokens, Some(42));
        assert_eq!(current.cost, None);
        assert_eq!(provider.today.spent, None);
        assert_eq!(provider.week.spent, None);
        assert_eq!(provider.month.spent, None);
        assert_eq!(provider.model_breakdown.len(), 2);
        assert_eq!(provider.model_breakdown[0].model, "model-a");
        assert_eq!(provider.model_breakdown[0].input_tokens, Some(28));
        assert_eq!(provider.model_breakdown[0].output_tokens, Some(10));
        assert_eq!(provider.model_breakdown[1].model, "model-b");
        assert_eq!(provider.model_breakdown[1].input_tokens, Some(2));
        assert_eq!(provider.model_breakdown[1].output_tokens, Some(1));
    }

    #[test]
    fn reported_zero_is_distinct_from_absent_cost() {
        for results in [serde_json::json!([]), serde_json::json!([{"amount": "0"}])] {
            let usage = serde_json::json!({
                "data": [{
                    "starting_at": "2026-07-18T00:00:00Z",
                    "ending_at": "2026-07-19T00:00:00Z",
                    "results": []
                }]
            })
            .to_string();
            let costs = serde_json::json!({
                "data": [{
                    "starting_at": "2026-07-18T00:00:00Z",
                    "ending_at": "2026-07-19T00:00:00Z",
                    "results": results
                }]
            })
            .to_string();
            let report = serde_json::json!({
                "accountId": "anthropic-local",
                "generatedAt": "2026-07-19T00:00:00Z",
                "todayStart": "2026-07-19T00:00:00Z",
                "weekStart": "2026-07-13T00:00:00Z",
                "monthStart": "2026-07-01T00:00:00Z",
                "usagePages": [usage],
                "costPages": [costs]
            })
            .to_string();

            let provider = anthropic_provider_snapshot_from_report_json(&report)
                .expect("normalize reported zero")
                .provider_snapshot;

            assert_eq!(provider.buckets.len(), 1);
            assert_eq!(provider.buckets[0].total_tokens, Some(0));
            assert_eq!(provider.buckets[0].cost, Some(Money::minor_units(0, "USD")));
            assert_eq!(provider.today.spent, None);
            assert_eq!(provider.week.spent, Some(Money::minor_units(0, "USD")));
            assert_eq!(provider.month.spent, Some(Money::minor_units(0, "USD")));
        }
    }

    /// Anthropic reports whole seconds today and the phone writes period bounds
    /// with milliseconds, which compares correctly by luck. The reverse shape
    /// would not: `…00.000Z` ranks below `…00Z`, so the boundary bucket would
    /// drop out of the total and no longer merge with its twin. Canonicalizing
    /// on the way in removes the luck.
    #[test]
    fn a_boundary_bucket_counts_whatever_shape_the_provider_sends() {
        let costs = serde_json::json!({
            "data": [{
                "starting_at": "2026-07-19T00:00:00.000Z",
                "ending_at": "2026-07-20T00:00:00.000Z",
                "results": [{"amount": "100", "currency": "usd"}]
            }, {
                "starting_at": "2026-07-19T00:00:00Z",
                "ending_at": "2026-07-20T00:00:00Z",
                "results": [{"amount": "40", "currency": "usd"}]
            }]
        })
        .to_string();
        let report = serde_json::json!({
            "accountId": "anthropic-local",
            "generatedAt": "2026-07-19T12:00:00Z",
            "todayStart": "2026-07-19T00:00:00Z",
            "weekStart": "2026-07-13T00:00:00Z",
            "monthStart": "2026-07-01T00:00:00Z",
            "usagePages": [],
            "costPages": [costs]
        })
        .to_string();

        let snapshot =
            anthropic_provider_snapshot_from_report_json(&report).expect("normalize Anthropic");

        // Both shapes name the same instant, so they are one bucket, summed once.
        assert_eq!(
            snapshot.provider_snapshot.today.spent,
            Some(Money::minor_units(140, "USD"))
        );
        assert_eq!(snapshot.provider_snapshot.buckets.len(), 1);
        assert_eq!(
            snapshot.provider_snapshot.buckets[0].start_at.as_str(),
            "2026-07-19T00:00:00Z"
        );
    }

    #[test]
    fn rounds_cent_amounts() {
        assert_eq!(cents_from_decimal("123.45").expect("parse"), 123);
        assert_eq!(cents_from_decimal("123.78912").expect("parse"), 124);
        assert!(cents_from_decimal("12.3x").is_err());
        assert!(cents_from_decimal("").is_err());
    }

    #[test]
    fn rejects_a_non_usd_cost_currency() {
        let costs = serde_json::json!({
            "data": [{
                "starting_at": "2026-07-19T00:00:00Z",
                "ending_at": "2026-07-20T00:00:00Z",
                "results": [{"amount": "100", "currency": "eur"}]
            }]
        })
        .to_string();
        let report = serde_json::json!({
            "accountId": "anthropic-local",
            "generatedAt": "2026-07-19T12:00:00Z",
            "todayStart": "2026-07-19T00:00:00Z",
            "weekStart": "2026-07-13T00:00:00Z",
            "monthStart": "2026-07-01T00:00:00Z",
            "usagePages": [],
            "costPages": [costs]
        })
        .to_string();

        assert!(matches!(
            anthropic_provider_snapshot_from_report_json(&report),
            Err(AnthropicReportError::InvalidCurrency(currency)) if currency == "eur"
        ));
    }
}
