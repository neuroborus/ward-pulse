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
    let mut usage_by_bucket = BTreeMap::<(DateTimeUtc, DateTimeUtc), UsageTotals>::new();
    let mut model_breakdown = BTreeMap::<String, UsageTotals>::new();

    for page_json in &report.usage_pages {
        let page: RawUsagePage =
            serde_json::from_str(page_json).map_err(AnthropicReportError::UsageJson)?;
        for bucket in &page.data {
            let totals = usage_by_bucket
                .entry((bucket.starting_at.clone(), bucket.ending_at.clone()))
                .or_default();
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

    let mut cost_by_bucket = BTreeMap::<(DateTimeUtc, DateTimeUtc), i64>::new();
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
            let entry = cost_by_bucket
                .entry((bucket.starting_at.clone(), bucket.ending_at.clone()))
                .or_default();
            *entry = entry
                .checked_add(bucket_cents)
                .ok_or(AnthropicReportError::NumericOverflow)?;
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
            requests: None,
        })
        .collect();

    let today = budget_for(BudgetPeriod::Today, &report.today_start, &cost_by_bucket)?;
    let week = budget_for(BudgetPeriod::Week, &report.week_start, &cost_by_bucket)?;
    let month = budget_for(BudgetPeriod::Month, &report.month_start, &cost_by_bucket)?;

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
    costs: &BTreeMap<(DateTimeUtc, DateTimeUtc), i64>,
) -> Result<ward_pulse_core::model::BudgetState, AnthropicReportError> {
    let total = costs
        .iter()
        .filter(|((bucket_start, _), _)| bucket_start >= start)
        .try_fold(0_i64, |total, (_, value)| {
            total
                .checked_add(*value)
                .ok_or(AnthropicReportError::NumericOverflow)
        })?;
    Ok(calculate_budget_state(
        period,
        Some(Money::minor_units(total, "USD")),
        None,
        None,
    ))
}

fn merge_buckets(
    usage: &BTreeMap<(DateTimeUtc, DateTimeUtc), UsageTotals>,
    costs: &BTreeMap<(DateTimeUtc, DateTimeUtc), i64>,
) -> Result<Vec<UsageBucket>, AnthropicReportError> {
    let mut keys: Vec<_> = usage.keys().cloned().chain(costs.keys().cloned()).collect();
    keys.sort();
    keys.dedup();

    keys.into_iter()
        .map(|(start, end)| {
            let totals = usage.get(&(start.clone(), end.clone())).copied();
            let cost = costs.get(&(start.clone(), end.clone())).copied();
            Ok(UsageBucket {
                start_at: start,
                end_at: end,
                cost: cost.map(|minor| Money::minor_units(minor, "USD")),
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
            })
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
