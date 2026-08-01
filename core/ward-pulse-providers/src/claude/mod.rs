//! Claude / Anthropic provider normalization.
//!
//! - Plan: undocumented Claude Code `GET /api/oauth/usage` compatibility contract.
//! - Platform: official Usage & Cost Admin API organization reporting.

mod platform;

use std::error::Error as StdError;
use std::fmt;

use serde::Deserialize;
use ward_pulse_core::budget::calculate_budget_state;
use ward_pulse_core::model::{
    connection, AllowanceSource, AllowanceState, BudgetPeriod, ProviderKind, ProviderSnapshot,
};
use ward_pulse_core::time::DateTimeUtc;

use crate::allowance::{credits_from_cents, percent_status, worst_status};
use crate::{BucketCapabilities, ProviderCapabilities};

pub use platform::{
    anthropic_provider_snapshot_from_report_json, AnthropicReportError, AnthropicReportSnapshot,
};

pub const PROVIDER_NAME: &str = "Claude";

/// Union of Claude plan and Anthropic platform reporting capabilities.
pub(crate) const CAPABILITIES: ProviderCapabilities = ProviderCapabilities {
    supports_cost: true,
    supports_tokens: true,
    supports_requests: false,
    supports_credits: true,
    usage_buckets: BucketCapabilities::DAILY_AND_HOURLY,
    cost_buckets: BucketCapabilities::DAILY,
    supports_usage_model_breakdown: true,
    supports_cost_model_breakdown: false,
    supports_workspace_breakdown: true,
    supports_active_agents: false,
};

#[derive(Clone, Debug, PartialEq)]
pub struct ClaudeReportSnapshot {
    pub generated_at: DateTimeUtc,
    pub provider_snapshot: ProviderSnapshot,
}

#[derive(Debug)]
pub enum ClaudeReportError {
    Json(serde_json::Error),
    InvalidTimestamp,
}

impl fmt::Display for ClaudeReportError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::Json(error) => write!(
                formatter,
                "invalid Claude usage JSON at line {} column {}",
                error.line(),
                error.column()
            ),
            Self::InvalidTimestamp => formatter.write_str("invalid Claude reset timestamp"),
        }
    }
}

impl StdError for ClaudeReportError {
    fn source(&self) -> Option<&(dyn StdError + 'static)> {
        match self {
            Self::Json(error) => Some(error),
            Self::InvalidTimestamp => None,
        }
    }
}

/// Normalizes a sanitized Claude Code oauth usage payload into a provider snapshot.
pub fn claude_provider_snapshot_from_report_json(
    report_json: &str,
) -> Result<ClaudeReportSnapshot, ClaudeReportError> {
    let report: RawReport = serde_json::from_str(report_json).map_err(ClaudeReportError::Json)?;
    let mut allowances = Vec::new();

    if let Some(window) = report.five_hour {
        allowances.push(plan_window(
            "claude-five-hour",
            "5-hour session",
            5 * 60,
            window,
        )?);
    }
    if let Some(window) = report.seven_day {
        allowances.push(plan_window(
            "claude-seven-day",
            "Weekly plan",
            7 * 24 * 60,
            window,
        )?);
    }
    if let Some(window) = report.seven_day_opus {
        allowances.push(plan_window(
            "claude-seven-day-opus",
            "Weekly Opus",
            7 * 24 * 60,
            window,
        )?);
    }
    if let Some(window) = report.seven_day_sonnet {
        allowances.push(plan_window(
            "claude-seven-day-sonnet",
            "Weekly Sonnet",
            7 * 24 * 60,
            window,
        )?);
    }

    if let Some(extra) = report.extra_usage.filter(|value| value.is_enabled) {
        let used = extra.used_credits.map(credits_from_cents);
        let limit = extra
            .monthly_limit
            .map(|cents| credits_from_cents(cents as f64));
        let remaining = match (extra.used_credits, extra.monthly_limit) {
            (Some(used_credits), Some(limit_cents)) => Some(credits_from_cents(
                (limit_cents as f64 - used_credits).max(0.0),
            )),
            _ => None,
        };
        allowances.push(AllowanceState {
            id: "claude-extra-usage".to_string(),
            source: AllowanceSource::Purchased,
            label: "Extra usage".to_string(),
            used_percent: extra.utilization,
            used,
            limit,
            remaining,
            unlimited: false,
            window_minutes: None,
            resets_at: None,
            status: percent_status(extra.utilization),
        });
    }

    let status = worst_status(&allowances);
    let unknown_budget = |period| calculate_budget_state(period, None, None, None);

    Ok(ClaudeReportSnapshot {
        generated_at: report.generated_at.clone(),
        provider_snapshot: ProviderSnapshot {
            account_id: report
                .account_id
                .unwrap_or_else(|| "claude-local".to_string()),
            provider: ProviderKind::Claude,
            connection: Some(connection::CLAUDE_PLAN.to_string()),
            status,
            today: unknown_budget(BudgetPeriod::Today),
            week: unknown_budget(BudgetPeriod::Week),
            month: unknown_budget(BudgetPeriod::Month),
            credits: Vec::new(),
            allowances,
            buckets: Vec::new(),
            model_breakdown: Vec::new(),
            last_successful_sync_at: Some(report.generated_at),
            last_error: None,
        },
    })
}

fn plan_window(
    id: &str,
    label: &str,
    window_minutes: u64,
    window: RawWindow,
) -> Result<AllowanceState, ClaudeReportError> {
    Ok(AllowanceState {
        id: id.to_string(),
        source: AllowanceSource::Plan,
        label: label.to_string(),
        used_percent: Some(window.utilization),
        used: None,
        limit: None,
        remaining: None,
        unlimited: false,
        window_minutes: Some(window_minutes),
        resets_at: window
            .resets_at
            .as_deref()
            .map(parse_timestamp)
            .transpose()?,
        status: percent_status(Some(window.utilization)),
    })
}

fn parse_timestamp(value: &str) -> Result<DateTimeUtc, ClaudeReportError> {
    // Accept RFC 3339 with or without fractional seconds; keep the original UTC string.
    let (date, rest) = value
        .split_once('T')
        .ok_or(ClaudeReportError::InvalidTimestamp)?;
    let time = rest.strip_suffix('Z').unwrap_or(rest);
    let (hour_minute_second, _) = time.split_once('.').unwrap_or((time, ""));
    let date = date.as_bytes();
    let clock = hour_minute_second.as_bytes();
    if date.len() != 10
        || clock.len() != 8
        || date.get(4) != Some(&b'-')
        || date.get(7) != Some(&b'-')
        || clock.get(2) != Some(&b':')
        || clock.get(5) != Some(&b':')
    {
        return Err(ClaudeReportError::InvalidTimestamp);
    }
    Ok(DateTimeUtc::new(value.to_string()))
}

/// Provider fields stay snake_case; the phone adds camelCase envelope fields.
#[derive(Debug, Deserialize)]
struct RawReport {
    #[serde(default, alias = "accountId")]
    account_id: Option<String>,
    #[serde(alias = "generatedAt")]
    generated_at: DateTimeUtc,
    #[serde(default)]
    five_hour: Option<RawWindow>,
    #[serde(default)]
    seven_day: Option<RawWindow>,
    #[serde(default)]
    seven_day_opus: Option<RawWindow>,
    #[serde(default)]
    seven_day_sonnet: Option<RawWindow>,
    #[serde(default)]
    extra_usage: Option<RawExtraUsage>,
}

#[derive(Debug, Deserialize)]
struct RawWindow {
    utilization: f64,
    #[serde(default)]
    resets_at: Option<String>,
}

#[derive(Debug, Deserialize)]
struct RawExtraUsage {
    #[serde(default)]
    is_enabled: bool,
    #[serde(default)]
    monthly_limit: Option<u64>,
    #[serde(default)]
    used_credits: Option<f64>,
    #[serde(default)]
    utilization: Option<f64>,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn normalizes_plan_windows_and_extra_usage() {
        let report = include_str!("../../../../fixtures/providers/claude/oauth_usage.json");
        let snapshot = claude_provider_snapshot_from_report_json(report).expect("normalize");
        assert_eq!(snapshot.provider_snapshot.provider, ProviderKind::Claude);
        assert!(snapshot
            .provider_snapshot
            .allowances
            .iter()
            .any(|item| item.id == "claude-five-hour"));
        assert!(snapshot
            .provider_snapshot
            .allowances
            .iter()
            .any(|item| item.source == AllowanceSource::Purchased));
        let extra = snapshot
            .provider_snapshot
            .allowances
            .iter()
            .find(|item| item.id == "claude-extra-usage")
            .expect("extra usage");
        assert_eq!(
            extra.remaining.as_ref().map(|value| value.value.as_str()),
            Some("380.00")
        );
    }

    #[test]
    fn rejects_a_malformed_reset_timestamp() {
        assert!(matches!(
            parse_timestamp("not-a-timestamp"),
            Err(ClaudeReportError::InvalidTimestamp)
        ));
        assert!(parse_timestamp("2026-07-19T12:00:00Z").is_ok());
        assert!(parse_timestamp("2026-07-19T12:00:00.123Z").is_ok());
    }
}
