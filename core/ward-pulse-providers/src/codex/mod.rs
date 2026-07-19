use std::collections::BTreeMap;
use std::error::Error as StdError;
use std::fmt;

use serde::Deserialize;
use ward_pulse_core::budget::calculate_budget_state;
use ward_pulse_core::model::{
    AllowanceSource, AllowanceState, BudgetPeriod, ProviderKind, ProviderSnapshot, ProviderStatus,
    Quantity, QuantityUnit, UsageBucket,
};
use ward_pulse_core::time::DateTimeUtc;

use crate::{BucketCapabilities, ProviderCapabilities};

pub const PROVIDER_NAME: &str = "Codex";

pub(crate) const CAPABILITIES: ProviderCapabilities = ProviderCapabilities {
    supports_cost: false,
    supports_tokens: true,
    supports_requests: false,
    supports_credits: true,
    usage_buckets: BucketCapabilities::DAILY,
    cost_buckets: BucketCapabilities::NONE,
    supports_usage_model_breakdown: false,
    supports_cost_model_breakdown: false,
    supports_workspace_breakdown: false,
    supports_active_agents: false,
};

#[derive(Clone, Debug, PartialEq)]
pub struct CodexReportSnapshot {
    pub generated_at: DateTimeUtc,
    pub provider_snapshot: ProviderSnapshot,
}

#[derive(Debug)]
pub enum CodexReportError {
    Json(serde_json::Error),
    InvalidDate,
    InvalidQuantity,
    InvalidTimestamp,
}

impl fmt::Display for CodexReportError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::Json(error) => write!(
                formatter,
                "invalid Codex account JSON at line {} column {}",
                error.line(),
                error.column()
            ),
            Self::InvalidDate => formatter.write_str("invalid Codex usage date"),
            Self::InvalidQuantity => formatter.write_str("invalid Codex credit quantity"),
            Self::InvalidTimestamp => formatter.write_str("invalid Codex reset timestamp"),
        }
    }
}

impl StdError for CodexReportError {
    fn source(&self) -> Option<&(dyn StdError + 'static)> {
        match self {
            Self::Json(error) => Some(error),
            Self::InvalidDate | Self::InvalidQuantity | Self::InvalidTimestamp => None,
        }
    }
}

pub fn codex_provider_snapshot_from_report_json(
    report_json: &str,
) -> Result<CodexReportSnapshot, CodexReportError> {
    let report: RawReport = serde_json::from_str(report_json).map_err(CodexReportError::Json)?;
    let rate_limits = report
        .rate_limits
        .rate_limits_by_limit_id
        .as_ref()
        .filter(|values| !values.is_empty())
        .map(|values| values.values().collect::<Vec<_>>())
        .unwrap_or_else(|| vec![&report.rate_limits.rate_limits]);

    let mut allowances = Vec::new();
    for rate_limit in rate_limits {
        if let Some(window) = &rate_limit.primary {
            allowances.push(plan_allowance(rate_limit, "primary", window)?);
        }
        if let Some(window) = &rate_limit.secondary {
            allowances.push(plan_allowance(rate_limit, "secondary", window)?);
        }
    }

    if let Some(credits) = report.rate_limits.rate_limits.credits.as_ref() {
        if credits.has_credits || credits.unlimited {
            allowances.push(AllowanceState {
                id: "codex-purchased-credits".to_string(),
                source: AllowanceSource::Purchased,
                label: "Purchased credits".to_string(),
                used_percent: None,
                used: None,
                limit: None,
                remaining: credits
                    .balance
                    .as_deref()
                    .map(quantity_credits)
                    .transpose()?,
                unlimited: credits.unlimited,
                window_minutes: None,
                resets_at: None,
                status: ProviderStatus::Ok,
            });
        }
    }

    let status = allowances
        .iter()
        .map(|allowance| allowance.status)
        .max_by_key(status_rank)
        .unwrap_or(ProviderStatus::Unknown);
    let buckets = report
        .usage
        .daily_usage_buckets
        .unwrap_or_default()
        .into_iter()
        .map(usage_bucket)
        .collect::<Result<Vec<_>, _>>()?;
    let unknown_budget = |period| calculate_budget_state(period, None, None, None);
    let provider_snapshot = ProviderSnapshot {
        account_id: "codex-local".to_string(),
        provider: ProviderKind::Codex,
        status,
        today: unknown_budget(BudgetPeriod::Today),
        week: unknown_budget(BudgetPeriod::Week),
        month: unknown_budget(BudgetPeriod::Month),
        credits: Vec::new(),
        allowances,
        buckets,
        model_breakdown: Vec::new(),
        last_successful_sync_at: Some(report.generated_at.clone()),
        last_error: None,
    };

    Ok(CodexReportSnapshot {
        generated_at: report.generated_at,
        provider_snapshot,
    })
}

fn quantity_credits(value: &str) -> Result<Quantity, CodexReportError> {
    let mut parts = value.split('.');
    let whole = parts.next().unwrap_or_default();
    let fraction = parts.next();
    if whole.is_empty()
        || !whole.bytes().all(|value| value.is_ascii_digit())
        || fraction.is_some_and(|value| {
            value.is_empty() || !value.bytes().all(|value| value.is_ascii_digit())
        })
        || parts.next().is_some()
    {
        return Err(CodexReportError::InvalidQuantity);
    }

    Ok(Quantity {
        value: value.to_string(),
        unit: QuantityUnit::Credits,
    })
}

fn plan_allowance(
    rate_limit: &RawRateLimit,
    window_id: &str,
    window: &RawRateLimitWindow,
) -> Result<AllowanceState, CodexReportError> {
    let status = if window.used_percent >= 100.0 {
        ProviderStatus::RateLimited
    } else if window.used_percent >= 80.0 {
        ProviderStatus::Warning
    } else {
        ProviderStatus::Ok
    };
    let duration = window.window_duration_mins;
    let label = rate_limit
        .limit_name
        .clone()
        .unwrap_or_else(|| window_label(duration));

    Ok(AllowanceState {
        id: format!(
            "{}-{window_id}",
            rate_limit.limit_id.as_deref().unwrap_or("codex")
        ),
        source: AllowanceSource::Plan,
        label,
        used_percent: Some(window.used_percent),
        used: None,
        limit: None,
        remaining: None,
        unlimited: false,
        window_minutes: duration,
        resets_at: window.resets_at.map(unix_seconds_to_utc).transpose()?,
        status,
    })
}

fn window_label(duration: Option<u64>) -> String {
    match duration {
        Some(1_440) => "Daily plan".to_string(),
        Some(10_080) => "Weekly plan".to_string(),
        Some(minutes) if minutes % 1_440 == 0 => format!("{}-day plan", minutes / 1_440),
        Some(minutes) if minutes % 60 == 0 => format!("{}-hour plan", minutes / 60),
        Some(minutes) => format!("{minutes}-minute plan"),
        None => "Plan usage".to_string(),
    }
}

fn usage_bucket(bucket: RawUsageBucket) -> Result<UsageBucket, CodexReportError> {
    let end_date = next_date(&bucket.start_date)?;

    Ok(UsageBucket {
        start_at: DateTimeUtc::new(format!("{}T00:00:00Z", bucket.start_date)),
        end_at: DateTimeUtc::new(format!("{end_date}T00:00:00Z")),
        cost: None,
        input_tokens: None,
        output_tokens: None,
        cached_tokens: None,
        total_tokens: Some(bucket.tokens),
        requests: None,
        model: None,
        project: None,
        user: None,
    })
}

fn next_date(value: &str) -> Result<String, CodexReportError> {
    let mut parts = value.split('-');
    let mut year = parts
        .next()
        .and_then(|part| part.parse::<u32>().ok())
        .ok_or(CodexReportError::InvalidDate)?;
    let mut month = parts
        .next()
        .and_then(|part| part.parse::<u32>().ok())
        .ok_or(CodexReportError::InvalidDate)?;
    let mut day = parts
        .next()
        .and_then(|part| part.parse::<u32>().ok())
        .ok_or(CodexReportError::InvalidDate)?;
    if parts.next().is_some() || !(1..=12).contains(&month) {
        return Err(CodexReportError::InvalidDate);
    }

    let days_in_month = match month {
        2 if is_leap_year(year) => 29,
        2 => 28,
        4 | 6 | 9 | 11 => 30,
        _ => 31,
    };
    if day == 0 || day > days_in_month {
        return Err(CodexReportError::InvalidDate);
    }

    if day < days_in_month {
        day += 1;
    } else if month < 12 {
        month += 1;
        day = 1;
    } else {
        year = year.checked_add(1).ok_or(CodexReportError::InvalidDate)?;
        month = 1;
        day = 1;
    }

    Ok(format!("{year:04}-{month:02}-{day:02}"))
}

fn is_leap_year(year: u32) -> bool {
    year % 4 == 0 && (year % 100 != 0 || year % 400 == 0)
}

fn unix_seconds_to_utc(timestamp: i64) -> Result<DateTimeUtc, CodexReportError> {
    let days = timestamp.div_euclid(86_400);
    let seconds = timestamp.rem_euclid(86_400);
    let (year, month, day) = civil_from_days(days).ok_or(CodexReportError::InvalidTimestamp)?;
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

fn status_rank(status: &ProviderStatus) -> u8 {
    match status {
        ProviderStatus::Ok => 1,
        ProviderStatus::Unknown => 2,
        ProviderStatus::Stale => 3,
        ProviderStatus::Warning => 4,
        ProviderStatus::RateLimited => 5,
        ProviderStatus::AuthRequired => 6,
        ProviderStatus::Error => 7,
    }
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct RawReport {
    generated_at: DateTimeUtc,
    rate_limits: RawRateLimitsResponse,
    usage: RawUsageResponse,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct RawRateLimitsResponse {
    rate_limits: RawRateLimit,
    rate_limits_by_limit_id: Option<BTreeMap<String, RawRateLimit>>,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct RawRateLimit {
    limit_id: Option<String>,
    limit_name: Option<String>,
    primary: Option<RawRateLimitWindow>,
    secondary: Option<RawRateLimitWindow>,
    credits: Option<RawCredits>,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct RawRateLimitWindow {
    used_percent: f64,
    window_duration_mins: Option<u64>,
    resets_at: Option<i64>,
}

#[derive(Debug, Deserialize)]
struct RawCredits {
    #[serde(default, rename = "hasCredits")]
    has_credits: bool,
    #[serde(default)]
    unlimited: bool,
    balance: Option<String>,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct RawUsageResponse {
    daily_usage_buckets: Option<Vec<RawUsageBucket>>,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct RawUsageBucket {
    start_date: String,
    tokens: u64,
}

#[cfg(test)]
mod tests {
    use super::*;

    const REPORT_FIXTURE: &str = include_str!("../../../../fixtures/providers/codex/report.json");

    #[test]
    fn normalizes_plan_and_purchased_consumption() {
        let report = codex_provider_snapshot_from_report_json(REPORT_FIXTURE)
            .expect("normalize Codex account report");
        let snapshot = report.provider_snapshot;

        assert_eq!(snapshot.provider, ProviderKind::Codex);
        assert_eq!(snapshot.status, ProviderStatus::Warning);
        assert_eq!(snapshot.allowances.len(), 2);
        assert_eq!(snapshot.allowances[0].source, AllowanceSource::Plan);
        assert_eq!(snapshot.allowances[0].used_percent, Some(84.0));
        assert_eq!(
            snapshot.allowances[0].resets_at,
            Some(DateTimeUtc::from("2026-07-26T09:55:37Z"))
        );
        assert_eq!(snapshot.allowances[1].source, AllowanceSource::Purchased);
        assert_eq!(
            snapshot.allowances[1].remaining,
            Some(Quantity {
                value: "12.5".to_string(),
                unit: QuantityUnit::Credits,
            })
        );
        assert_eq!(snapshot.buckets[1].total_tokens, Some(4_200_000));
    }

    #[test]
    fn advances_daily_bucket_dates_across_boundaries() {
        assert_eq!(next_date("2024-02-28").unwrap(), "2024-02-29");
        assert_eq!(next_date("2026-02-28").unwrap(), "2026-03-01");
        assert_eq!(next_date("2026-12-31").unwrap(), "2027-01-01");
    }

    #[test]
    fn omits_unavailable_purchased_credits() {
        let report_json = REPORT_FIXTURE.replace("\"hasCredits\": true", "\"hasCredits\": false");
        let report = codex_provider_snapshot_from_report_json(&report_json)
            .expect("normalize Codex account report");

        assert_eq!(report.provider_snapshot.allowances.len(), 1);
        assert_eq!(
            report.provider_snapshot.allowances[0].source,
            AllowanceSource::Plan
        );
    }

    #[test]
    fn preserves_unlimited_purchased_credits() {
        let report_json = REPORT_FIXTURE
            .replace("\"unlimited\": false", "\"unlimited\": true")
            .replace("\"balance\": \"12.5\"", "\"balance\": null");
        let report = codex_provider_snapshot_from_report_json(&report_json)
            .expect("normalize unlimited Codex credits");
        let allowance = &report.provider_snapshot.allowances[1];

        assert!(allowance.unlimited);
        assert_eq!(allowance.remaining, None);
        assert_eq!(
            serde_json::to_value(&report.provider_snapshot)
                .expect("serialize Codex provider snapshot")["allowances"][1]["unlimited"],
            true
        );
    }
}
