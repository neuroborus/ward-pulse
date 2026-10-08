//! Cursor team Admin API normalization (`/teams/daily-usage-data`, `/teams/spend`).

use std::collections::BTreeMap;
use std::error::Error as StdError;
use std::fmt;

use serde::Deserialize;
use ward_pulse_core::budget::calculate_budget_state;
use ward_pulse_core::model::{
    connection, BudgetPeriod, Money, ProviderKind, ProviderSnapshot, ProviderStatus, UsageBucket,
};
use ward_pulse_core::time::DateTimeUtc;

#[derive(Clone, Debug, PartialEq)]
pub struct CursorPlatformReportSnapshot {
    pub generated_at: DateTimeUtc,
    pub provider_snapshot: ProviderSnapshot,
}

#[derive(Debug)]
pub enum CursorPlatformReportError {
    Json(serde_json::Error),
    InvalidDate,
    NumericOverflow,
}

impl fmt::Display for CursorPlatformReportError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::Json(error) => write!(
                formatter,
                "invalid Cursor Admin report JSON at line {} column {}",
                error.line(),
                error.column()
            ),
            Self::InvalidDate => formatter.write_str("invalid Cursor usage date"),
            Self::NumericOverflow => formatter.write_str("Cursor report value overflow"),
        }
    }
}

impl StdError for CursorPlatformReportError {
    fn source(&self) -> Option<&(dyn StdError + 'static)> {
        match self {
            Self::Json(error) => Some(error),
            Self::InvalidDate | Self::NumericOverflow => None,
        }
    }
}

/// Normalizes sanitized Cursor team Admin daily-usage and spend pages.
pub fn cursor_platform_snapshot_from_report_json(
    report_json: &str,
) -> Result<CursorPlatformReportSnapshot, CursorPlatformReportError> {
    let report: RawReport =
        serde_json::from_str(report_json).map_err(CursorPlatformReportError::Json)?;

    let mut requests_by_day = BTreeMap::<String, u64>::new();
    for page_json in &report.daily_usage_pages {
        let page: RawDailyUsagePage =
            serde_json::from_str(page_json).map_err(CursorPlatformReportError::Json)?;
        for row in page.data {
            let day = row.day.ok_or(CursorPlatformReportError::InvalidDate)?;
            let requests = row
                .subscription_included_reqs
                .saturating_add(row.usage_based_reqs)
                .saturating_add(row.api_key_reqs)
                .saturating_add(row.composer_requests)
                .saturating_add(row.chat_requests)
                .saturating_add(row.agent_requests);
            let entry = requests_by_day.entry(day).or_default();
            *entry = entry.saturating_add(requests);
        }
    }

    let mut spend_cents = 0_i64;
    for page_json in &report.spend_pages {
        let page: RawSpendPage =
            serde_json::from_str(page_json).map_err(CursorPlatformReportError::Json)?;
        for member in page.team_member_spend {
            let cents = member.overall_spend_cents.unwrap_or(0.0).round() as i64;
            spend_cents = spend_cents
                .checked_add(cents)
                .ok_or(CursorPlatformReportError::NumericOverflow)?;
        }
    }

    let buckets = requests_by_day
        .into_iter()
        .map(|(day, requests)| {
            let end = next_date(&day)?;
            Ok(UsageBucket {
                start_at: DateTimeUtc::new(format!("{day}T00:00:00Z")),
                end_at: DateTimeUtc::new(format!("{end}T00:00:00Z")),
                cost: None,
                input_tokens: None,
                output_tokens: None,
                cached_tokens: None,
                total_tokens: None,
                requests: Some(requests),
                model: None,
                project: None,
                user: None,
            })
        })
        .collect::<Result<Vec<_>, _>>()?;

    let spent = Some(Money::minor_units(spend_cents, "USD"));
    // `/teams/spend` is billing-cycle scoped, not day/week. Leave shorter periods unknown.
    let unknown = |period| calculate_budget_state(period, None, None, None);

    Ok(CursorPlatformReportSnapshot {
        generated_at: report.generated_at.clone(),
        provider_snapshot: ProviderSnapshot {
            account_id: report.account_id,
            provider: ProviderKind::Cursor,
            connection: Some(connection::CURSOR_PLATFORM.to_string()),
            status: ProviderStatus::Ok,
            today: unknown(BudgetPeriod::Today),
            week: unknown(BudgetPeriod::Week),
            month: calculate_budget_state(BudgetPeriod::Month, spent, None, None),
            credits: Vec::new(),
            allowances: Vec::new(),
            buckets,
            model_breakdown: Vec::new(),
            last_successful_sync_at: Some(report.generated_at),
            last_error: None,
        },
    })
}

fn next_date(value: &str) -> Result<String, CursorPlatformReportError> {
    let mut parts = value.split('-');
    let mut year = parts
        .next()
        .and_then(|part| part.parse::<u32>().ok())
        .ok_or(CursorPlatformReportError::InvalidDate)?;
    let mut month = parts
        .next()
        .and_then(|part| part.parse::<u32>().ok())
        .ok_or(CursorPlatformReportError::InvalidDate)?;
    let mut day = parts
        .next()
        .and_then(|part| part.parse::<u32>().ok())
        .ok_or(CursorPlatformReportError::InvalidDate)?;
    if parts.next().is_some() || !(1..=12).contains(&month) {
        return Err(CursorPlatformReportError::InvalidDate);
    }

    let days_in_month = match month {
        2 if year % 4 == 0 && (year % 100 != 0 || year % 400 == 0) => 29,
        2 => 28,
        4 | 6 | 9 | 11 => 30,
        _ => 31,
    };
    if day == 0 || day > days_in_month {
        return Err(CursorPlatformReportError::InvalidDate);
    }

    if day < days_in_month {
        day += 1;
    } else if month < 12 {
        month += 1;
        day = 1;
    } else {
        year = year
            .checked_add(1)
            .ok_or(CursorPlatformReportError::InvalidDate)?;
        month = 1;
        day = 1;
    }

    Ok(format!("{year:04}-{month:02}-{day:02}"))
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct RawReport {
    account_id: String,
    generated_at: DateTimeUtc,
    daily_usage_pages: Vec<String>,
    spend_pages: Vec<String>,
}

#[derive(Debug, Deserialize)]
struct RawDailyUsagePage {
    data: Vec<RawDailyUsageRow>,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct RawDailyUsageRow {
    #[serde(default)]
    day: Option<String>,
    #[serde(default)]
    subscription_included_reqs: u64,
    #[serde(default)]
    usage_based_reqs: u64,
    #[serde(default)]
    api_key_reqs: u64,
    #[serde(default)]
    composer_requests: u64,
    #[serde(default)]
    chat_requests: u64,
    #[serde(default)]
    agent_requests: u64,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct RawSpendPage {
    #[serde(default, alias = "teamMembers")]
    team_member_spend: Vec<RawSpendMember>,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct RawSpendMember {
    #[serde(default)]
    overall_spend_cents: Option<f64>,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn normalizes_daily_usage_and_spend() {
        let daily = include_str!("../../../../fixtures/providers/cursor/daily_usage.json");
        let spend = include_str!("../../../../fixtures/providers/cursor/spend.json");
        let report = serde_json::json!({
            "accountId": "cursor-team-local",
            "generatedAt": "2026-07-19T12:00:00Z",
            "dailyUsagePages": [daily],
            "spendPages": [spend]
        })
        .to_string();

        let snapshot =
            cursor_platform_snapshot_from_report_json(&report).expect("normalize Cursor platform");
        assert_eq!(snapshot.provider_snapshot.provider, ProviderKind::Cursor);
        assert_eq!(
            snapshot.provider_snapshot.month.spent,
            Some(Money::minor_units(4326, "USD"))
        );
        assert!(snapshot.provider_snapshot.today.spent.is_none());
        assert!(!snapshot.provider_snapshot.buckets.is_empty());
    }
}
