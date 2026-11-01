//! Claude / Anthropic provider normalization.
//!
//! - Plan: undocumented Claude Code `GET /api/oauth/usage` compatibility contract.
//! - Platform: official Usage & Cost Admin API organization reporting.

mod platform;

use std::error::Error as StdError;
use std::fmt;

use serde::Deserialize;
use serde_json::Value;
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
    if let Some(window) = fable_weekly_window(&report.limits, &report.weekly_scoped_shares) {
        allowances.push(window);
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

/// Recognizes only the evidenced response-local weekly/Fable join.
/// Optional data is inspected locally so malformed entries cannot reject ordinary windows.
fn fable_weekly_window(limits: &Value, shares: &Value) -> Option<AllowanceState> {
    let limits = limits.as_array()?;
    shares.as_array()?.iter().find_map(|share| {
        let index = usize::try_from(share.get("limit_index")?.as_u64()?).ok()?;
        let limit = limits.get(index)?;
        let model = limit.get("scope")?.get("model")?;
        if limit.get("kind").and_then(Value::as_str) != Some("weekly_scoped")
            || limit.get("group").and_then(Value::as_str) != Some("weekly")
            || !model.get("id")?.is_null()
            || model.get("display_name").and_then(Value::as_str) != Some("Fable")
        {
            return None;
        }

        // This narrow inference uses the explicit weekly-relative share, never limit.percent.
        let used_percent = match (
            share.get("used_percent_of_weekly").and_then(Value::as_f64),
            share
                .get("allowance_percent_of_weekly")
                .and_then(Value::as_f64),
        ) {
            (Some(used), Some(allowance))
                if used.is_finite() && used >= 0.0 && allowance.is_finite() && allowance > 0.0 =>
            {
                Some(if used >= allowance {
                    100.0
                } else {
                    used / allowance * 100.0
                })
            }
            _ => None,
        };

        Some(AllowanceState {
            id: "claude-seven-day-fable".to_string(),
            source: AllowanceSource::Plan,
            label: "Fable weekly".to_string(),
            used_percent,
            used: None,
            limit: None,
            remaining: None,
            unlimited: false,
            window_minutes: Some(7 * 24 * 60),
            resets_at: limit
                .get("resets_at")
                .and_then(Value::as_str)
                .and_then(|value| parse_timestamp(value).ok()),
            status: percent_status(used_percent),
        })
    })
}

/// Parses ASCII Gregorian `YYYY-MM-DDTHH:MM:SS[.digits]` with `Z` or `±HH:MM`.
/// Years must remain within 0000–9999 in UTC; leap seconds are unsupported.
fn parse_timestamp(value: &str) -> Result<DateTimeUtc, ClaudeReportError> {
    let bytes = value.as_bytes();
    if bytes.len() < 20
        || !value.is_ascii()
        || bytes[4] != b'-'
        || bytes[7] != b'-'
        || bytes[10] != b'T'
        || bytes[13] != b':'
        || bytes[16] != b':'
    {
        return Err(ClaudeReportError::InvalidTimestamp);
    }

    let digits = |part: &str| {
        if !part.bytes().all(|byte| byte.is_ascii_digit()) {
            return Err(ClaudeReportError::InvalidTimestamp);
        }
        part.parse::<i32>()
            .map_err(|_| ClaudeReportError::InvalidTimestamp)
    };
    let mut year = digits(&value[..4])?;
    let mut month = digits(&value[5..7])?;
    let mut day = digits(&value[8..10])?;
    let hour = digits(&value[11..13])?;
    let minute = digits(&value[14..16])?;
    let second = digits(&value[17..19])?;
    if day == 0 || day > days_in_month(year, month) || hour > 23 || minute > 59 || second > 59 {
        return Err(ClaudeReportError::InvalidTimestamp);
    }

    let tail = &value[19..];
    let zone = if let Some(fraction) = tail.strip_prefix('.') {
        let end = fraction
            .bytes()
            .position(|byte| !byte.is_ascii_digit())
            .ok_or(ClaudeReportError::InvalidTimestamp)?;
        if end == 0 {
            return Err(ClaudeReportError::InvalidTimestamp);
        }
        &fraction[end..]
    } else {
        tail
    };
    let offset = if zone == "Z" {
        0
    } else {
        let zone_bytes = zone.as_bytes();
        if zone_bytes.len() != 6 || !matches!(zone_bytes[0], b'+' | b'-') || zone_bytes[3] != b':' {
            return Err(ClaudeReportError::InvalidTimestamp);
        }
        let hours = digits(&zone[1..3])?;
        let minutes = digits(&zone[4..6])?;
        if hours > 23 || minutes > 59 {
            return Err(ClaudeReportError::InvalidTimestamp);
        }
        let seconds = hours * 3_600 + minutes * 60;
        if zone_bytes[0] == b'+' {
            seconds
        } else {
            -seconds
        }
    };

    // Valid clock and offset bounds limit UTC conversion to one adjacent day.
    let mut seconds = hour * 3_600 + minute * 60 + second - offset;
    if seconds < 0 {
        seconds += 86_400;
        day -= 1;
        if day == 0 {
            if month == 1 {
                year -= 1;
                month = 12;
            } else {
                month -= 1;
            }
            day = days_in_month(year, month);
        }
    } else if seconds >= 86_400 {
        seconds -= 86_400;
        day += 1;
        if day > days_in_month(year, month) {
            day = 1;
            month += 1;
            if month == 13 {
                year += 1;
                month = 1;
            }
        }
    }
    if !(0..=9999).contains(&year) {
        return Err(ClaudeReportError::InvalidTimestamp);
    }

    let hour = seconds / 3_600;
    let minute = seconds % 3_600 / 60;
    let second = seconds % 60;
    Ok(DateTimeUtc::new(format!(
        "{year:04}-{month:02}-{day:02}T{hour:02}:{minute:02}:{second:02}Z"
    )))
}

fn days_in_month(year: i32, month: i32) -> i32 {
    match month {
        2 if year % 4 == 0 && (year % 100 != 0 || year % 400 == 0) => 29,
        2 => 28,
        4 | 6 | 9 | 11 => 30,
        1 | 3 | 5 | 7 | 8 | 10 | 12 => 31,
        _ => 0,
    }
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
    // Raw optional values preserve response-local indices and tolerate unknown field shapes.
    #[serde(default)]
    limits: Value,
    #[serde(default)]
    weekly_scoped_shares: Value,
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
    use serde_json::json;
    use ward_pulse_core::model::ProviderStatus;

    fn synthetic_fable_report() -> Value {
        serde_json::from_str(include_str!(
            "../../../../fixtures/providers/claude/oauth_usage_max_fable_synthetic.json"
        ))
        .expect("synthetic Max projection")
    }

    fn normalized_fable(report: &Value) -> AllowanceState {
        claude_provider_snapshot_from_report_json(&report.to_string())
            .expect("normalize synthetic report")
            .provider_snapshot
            .allowances
            .into_iter()
            .find(|allowance| allowance.id == "claude-seven-day-fable")
            .expect("independent Fable allowance")
    }

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
    fn synthetic_pro_projection_preserves_absent_null_and_empty_shares() {
        let mut report: Value = serde_json::from_str(include_str!(
            "../../../../fixtures/providers/claude/oauth_usage_pro_synthetic.json"
        ))
        .expect("synthetic Pro projection");
        let baseline = claude_provider_snapshot_from_report_json(&report.to_string())
            .expect("normalize synthetic Pro projection");
        assert_eq!(
            baseline
                .provider_snapshot
                .allowances
                .iter()
                .map(|allowance| allowance.id.as_str())
                .collect::<Vec<_>>(),
            ["claude-five-hour", "claude-seven-day"]
        );
        for shares in [None, Some(Value::Null), Some(json!([]))] {
            if let Some(shares) = shares {
                report["weekly_scoped_shares"] = shares;
            } else {
                report
                    .as_object_mut()
                    .unwrap()
                    .remove("weekly_scoped_shares");
            }
            assert_eq!(
                claude_provider_snapshot_from_report_json(&report.to_string()).unwrap(),
                baseline
            );
        }
    }

    #[test]
    fn synthetic_max_projection_recognizes_explicit_zero_despite_inactive_false() {
        let allowance = normalized_fable(&synthetic_fable_report());
        assert_eq!(allowance.source, AllowanceSource::Plan);
        assert_eq!(allowance.label, "Fable weekly");
        assert_eq!(allowance.used_percent, Some(0.0));
        assert_eq!(allowance.status, ProviderStatus::Ok);
        assert_eq!(allowance.window_minutes, Some(7 * 24 * 60));
        assert_eq!(
            allowance.resets_at.as_ref().map(DateTimeUtc::as_str),
            Some("2026-11-08T08:00:00Z")
        );
        assert_eq!(
            (allowance.used, allowance.limit, allowance.remaining),
            (None, None, None)
        );
        assert!(!allowance.unlimited);
    }

    #[test]
    fn malformed_optional_lists_preserve_ordinary_legacy_and_purchased_allowances() {
        let legacy: Value = serde_json::from_str(include_str!(
            "../../../../fixtures/providers/claude/oauth_usage.json"
        ))
        .unwrap();
        let baseline = claude_provider_snapshot_from_report_json(&legacy.to_string()).unwrap();
        let optional = synthetic_fable_report();
        for field in ["limits", "weekly_scoped_shares"] {
            for malformed in [
                Value::Null,
                json!(true),
                json!(7),
                json!("unexpected"),
                json!({}),
                json!([]),
                json!([null, false, "unexpected", {}, {"limit_index": "2"}]),
            ] {
                let mut report = legacy.clone();
                report["limits"] = optional["limits"].clone();
                report["weekly_scoped_shares"] = optional["weekly_scoped_shares"].clone();
                report[field] = malformed;
                assert_eq!(
                    claude_provider_snapshot_from_report_json(&report.to_string()).unwrap(),
                    baseline,
                    "malformed optional {field}"
                );
            }
        }
    }

    #[test]
    fn follows_moved_indices_skips_bad_neighbors_and_emits_at_most_one_fable() {
        let mut report = synthetic_fable_report();
        report["limits"].as_array_mut().unwrap().swap(0, 2);
        report["limits"][1] = Value::Null;
        report["weekly_scoped_shares"][0]["limit_index"] = json!(0);
        let share = report["weekly_scoped_shares"][0].clone();
        report["weekly_scoped_shares"] = json!([
            null,
            {},
            {"limit_index": 100},
            share.clone(),
            share
        ]);
        let snapshot = claude_provider_snapshot_from_report_json(&report.to_string()).unwrap();
        let fable: Vec<_> = snapshot
            .provider_snapshot
            .allowances
            .iter()
            .filter(|allowance| allowance.id == "claude-seven-day-fable")
            .collect();
        assert_eq!(fable.len(), 1);
        assert_eq!(fable[0].used_percent, Some(0.0));
    }

    #[test]
    fn rejects_missing_wrong_type_nonintegral_negative_and_out_of_range_indices() {
        for index in [
            None,
            Some(Value::Null),
            Some(json!("2")),
            Some(json!(true)),
            Some(json!(-1)),
            Some(json!(2.5)),
            Some(json!(0)),
            Some(json!(1)),
            Some(json!(3)),
            Some(json!(u64::MAX)),
        ] {
            let mut report = synthetic_fable_report();
            let share = report["weekly_scoped_shares"][0].as_object_mut().unwrap();
            if let Some(index) = index {
                share.insert("limit_index".to_string(), index);
            } else {
                share.remove("limit_index");
            }
            let snapshot = claude_provider_snapshot_from_report_json(&report.to_string()).unwrap();
            assert_eq!(snapshot.provider_snapshot.allowances.len(), 2);
        }
    }

    #[test]
    fn recognizes_only_the_exact_weekly_fable_scope_with_an_explicit_null_model_id() {
        for (path, value) in [
            ("/limits/2/kind", json!("weekly_all")),
            ("/limits/2/group", json!("session")),
            ("/limits/2/scope", Value::Null),
            ("/limits/2/scope", json!({})),
            ("/limits/2/scope/model", json!([])),
            ("/limits/2/scope/model", json!({"display_name": "Fable"})),
            ("/limits/2/scope/model", json!({"id": null})),
            ("/limits/2/scope/model/id", json!("fable")),
            ("/limits/2/scope/model/display_name", json!("fable")),
            ("/limits/2/scope/model/display_name", json!("Fable weekly")),
            ("/limits/2/scope/model/display_name", json!("Opus")),
        ] {
            let mut report = synthetic_fable_report();
            *report.pointer_mut(path).unwrap() = value;
            let snapshot = claude_provider_snapshot_from_report_json(&report.to_string()).unwrap();
            assert_eq!(snapshot.provider_snapshot.allowances.len(), 2, "{path}");
        }
    }

    #[test]
    fn synthetic_nonzero_share_ratios_are_bounded_without_using_limit_percent() {
        // Positive arithmetic cases are synthetic, not observed provider consumption.
        for (used, allowance, expected, status) in [
            (0.0, 50.0, 0.0, ProviderStatus::Ok),
            (12.5, 50.0, 25.0, ProviderStatus::Ok),
            (5.0, 20.0, 25.0, ProviderStatus::Ok),
            (40.0, 50.0, 80.0, ProviderStatus::Warning),
            (50.0, 50.0, 100.0, ProviderStatus::RateLimited),
            (75.0, 50.0, 100.0, ProviderStatus::RateLimited),
            (f64::MAX, 1.0, 100.0, ProviderStatus::RateLimited),
            (1e308, 1.5e308, 200.0 / 3.0, ProviderStatus::Ok),
            (1e-300, 2e-300, 50.0, ProviderStatus::Ok),
        ] {
            let mut report = synthetic_fable_report();
            report["weekly_scoped_shares"][0]["used_percent_of_weekly"] = json!(used);
            report["weekly_scoped_shares"][0]["allowance_percent_of_weekly"] = json!(allowance);
            report["limits"][2]["percent"] = json!(99);
            let normalized = normalized_fable(&report);
            let actual = normalized.used_percent.expect("known share ratio");
            assert!(actual.is_finite() && (0.0..=100.0).contains(&actual));
            assert!((actual - expected).abs() < 1e-10, "{used}/{allowance}");
            assert_eq!(normalized.status, status);
        }
    }

    #[test]
    fn invalid_or_missing_share_numbers_stay_unknown_without_a_percent_fallback() {
        for field in ["used_percent_of_weekly", "allowance_percent_of_weekly"] {
            let mut invalid = vec![
                None,
                Some(Value::Null),
                Some(json!(-1)),
                Some(json!("50")),
                Some(json!(true)),
                Some(json!([])),
                Some(json!({})),
                Some(serde_json::from_str::<Value>("1e400").unwrap()),
            ];
            if field == "allowance_percent_of_weekly" {
                invalid.push(Some(json!(0)));
            }
            for value in invalid {
                let mut report = synthetic_fable_report();
                let share = report["weekly_scoped_shares"][0].as_object_mut().unwrap();
                if let Some(value) = value {
                    share.insert(field.to_string(), value);
                } else {
                    share.remove(field);
                }
                let allowance = normalized_fable(&report);
                assert_eq!(allowance.used_percent, None, "{field}");
                assert_eq!(allowance.status, ProviderStatus::Unknown, "{field}");
                assert_eq!(
                    allowance.resets_at.as_ref().map(DateTimeUtc::as_str),
                    Some("2026-11-08T08:00:00Z")
                );
            }
        }
    }

    #[test]
    fn uses_only_fables_own_reset_and_tolerates_invalid_optional_resets() {
        let mut report = synthetic_fable_report();
        report["limits"][2]["resets_at"] = json!("2026-11-09T11:15:00.125+02:00");
        assert_eq!(
            normalized_fable(&report)
                .resets_at
                .as_ref()
                .map(DateTimeUtc::as_str),
            Some("2026-11-09T09:15:00Z")
        );
        for reset in [
            None,
            Some(Value::Null),
            Some(json!(7)),
            Some(json!("invalid-reset")),
            Some(json!("2026-02-30T08:00:00Z")),
            Some(json!("9999-12-31T23:59:59-00:01")),
        ] {
            if let Some(reset) = reset {
                report["limits"][2]["resets_at"] = reset;
            } else {
                report["limits"][2]
                    .as_object_mut()
                    .unwrap()
                    .remove("resets_at");
            }
            let snapshot = claude_provider_snapshot_from_report_json(&report.to_string()).unwrap();
            let allowances = snapshot.provider_snapshot.allowances;
            assert_eq!(allowances[2].resets_at, None);
            assert_eq!(allowances[2].used_percent, Some(0.0));
            assert_eq!(
                allowances[1].resets_at.as_ref().map(DateTimeUtc::as_str),
                Some("2026-11-08T08:00:00Z")
            );
        }
    }

    #[test]
    fn keeps_fable_independent_of_legacy_windows_and_extra_usage() {
        let mut report: Value = serde_json::from_str(include_str!(
            "../../../../fixtures/providers/claude/oauth_usage.json"
        ))
        .unwrap();
        // Synthetic legacy Sonnet coverage complements the existing non-null Opus window.
        report["seven_day_sonnet"] = json!({"utilization": 23.0, "resets_at": null});
        let baseline = claude_provider_snapshot_from_report_json(&report.to_string()).unwrap();
        let optional = synthetic_fable_report();
        report["limits"] = optional["limits"].clone();
        report["weekly_scoped_shares"] = optional["weekly_scoped_shares"].clone();
        let mut snapshot = claude_provider_snapshot_from_report_json(&report.to_string()).unwrap();
        assert_eq!(
            snapshot.provider_snapshot.allowances.len(),
            baseline.provider_snapshot.allowances.len() + 1
        );
        snapshot
            .provider_snapshot
            .allowances
            .retain(|allowance| allowance.id != "claude-seven-day-fable");
        assert_eq!(snapshot, baseline);
    }

    #[test]
    fn normalizes_report_reset_timestamps_without_changing_allowances() {
        let fixture = include_str!("../../../../fixtures/providers/claude/oauth_usage.json");
        let baseline = claude_provider_snapshot_from_report_json(fixture).expect("fixture");
        let mut report: serde_json::Value = serde_json::from_str(fixture).expect("fixture JSON");
        for (window, reset) in [
            ("five_hour", "2026-07-19T19:00:00.123456+02:00"),
            ("seven_day", "2026-07-25T07:00:00-05:00"),
            ("seven_day_opus", "2026-07-25T12:00:00.000+00:00"),
        ] {
            report[window]["resets_at"] = serde_json::json!(reset);
        }

        let snapshot =
            claude_provider_snapshot_from_report_json(&report.to_string()).expect("normalize");
        for (id, reset) in [
            ("claude-five-hour", "2026-07-19T17:00:00Z"),
            ("claude-seven-day", "2026-07-25T12:00:00Z"),
            ("claude-seven-day-opus", "2026-07-25T12:00:00Z"),
        ] {
            let allowance = snapshot
                .provider_snapshot
                .allowances
                .iter()
                .find(|item| item.id == id)
                .expect("plan window");
            assert_eq!(
                allowance.resets_at.as_ref().map(DateTimeUtc::as_str),
                Some(reset)
            );
        }
        // Window selection, utilization, extra usage and all other fields stay unchanged.
        assert_eq!(snapshot, baseline);
    }

    #[test]
    fn normalizes_reset_timestamps_to_whole_second_utc() {
        for (input, expected) in [
            ("2026-07-19T12:00:00Z", "2026-07-19T12:00:00Z"),
            ("2026-07-19T12:00:00.123Z", "2026-07-19T12:00:00Z"),
            (
                "2026-07-19T12:00:00.123456789012345678901234567890Z",
                "2026-07-19T12:00:00Z",
            ),
            ("2026-07-19T12:00:00+00:00", "2026-07-19T12:00:00Z"),
            ("2026-07-19T12:00:00-00:00", "2026-07-19T12:00:00Z"),
            ("2026-07-19T12:00:00.1+00:00", "2026-07-19T12:00:00Z"),
            ("2026-07-19T00:15:00.999+01:30", "2026-07-18T22:45:00Z"),
            ("2026-07-19T23:15:00.999-01:30", "2026-07-20T00:45:00Z"),
            ("2026-01-01T00:00:30+00:01", "2025-12-31T23:59:30Z"),
            ("2025-12-31T23:59:30-00:01", "2026-01-01T00:00:30Z"),
            ("2026-07-19T00:00:00+23:59", "2026-07-18T00:01:00Z"),
            ("2026-07-19T23:59:59-23:59", "2026-07-20T23:58:59Z"),
            ("2024-02-29T12:00:00Z", "2024-02-29T12:00:00Z"),
            ("2024-03-01T00:00:00+01:00", "2024-02-29T23:00:00Z"),
            ("2024-02-29T23:00:00-01:00", "2024-03-01T00:00:00Z"),
            ("2000-02-29T12:00:00Z", "2000-02-29T12:00:00Z"),
            ("1900-03-01T00:00:00+00:01", "1900-02-28T23:59:00Z"),
            ("0000-02-29T12:00:00Z", "0000-02-29T12:00:00Z"),
            ("0000-01-01T00:00:00Z", "0000-01-01T00:00:00Z"),
            ("0000-01-02T00:00:00+23:59", "0000-01-01T00:01:00Z"),
            ("9999-12-31T23:59:59Z", "9999-12-31T23:59:59Z"),
            ("9999-12-31T23:59:59+23:59", "9999-12-31T00:00:59Z"),
        ] {
            assert_eq!(
                parse_timestamp(input).expect("valid reset").as_str(),
                expected,
                "{input}"
            );
        }
    }

    #[test]
    fn canonical_resets_compare_equal_and_order_chronologically() {
        let instant = parse_timestamp("2026-07-19T12:00:00Z").expect("UTC reset");
        for equivalent in [
            "2026-07-19T12:00:00.999Z",
            "2026-07-19T12:00:00+00:00",
            "2026-07-19T13:00:00+01:00",
            "2026-07-19T11:00:00-01:00",
        ] {
            assert_eq!(
                parse_timestamp(equivalent).expect("equivalent reset"),
                instant
            );
        }
        let earlier = parse_timestamp("2026-07-19T12:59:59+01:00").expect("earlier reset");
        let later = parse_timestamp("2026-07-19T11:00:01-01:00").expect("later reset");
        assert!(earlier < instant);
        assert!(instant < later);
    }

    #[test]
    fn rejects_malformed_or_out_of_range_reset_timestamps() {
        for input in [
            "",
            "not-a-timestamp",
            "2026-07-19",
            "2026-07-19T12:00:00",
            "2026-07-19T12:00:00.123",
            "2026-07-19t12:00:00Z",
            "2026-07-19T12:00:00z",
            "2026-07-19 12:00:00Z",
            " 2026-07-19T12:00:00Z",
            "2026-07-19T12:00:00Z ",
            "2026-7-19T12:00:00Z",
            "2026-07-19T1:00:00Z",
            "202a-07-19T12:00:00Z",
            "2026-0a-19T12:00:00Z",
            "2026-07-1aT12:00:00Z",
            "2026-07-19T1a:00:00Z",
            "2026-07-19T12:0a:00Z",
            "2026-07-19T12:00:0aZ",
            "２０２６-07-19T12:00:00Z",
            "2026-00-19T12:00:00Z",
            "2026-13-19T12:00:00Z",
            "2026-07-00T12:00:00Z",
            "2026-07-32T12:00:00Z",
            "2026-04-31T12:00:00Z",
            "2026-02-29T12:00:00Z",
            "2024-02-30T12:00:00Z",
            "1900-02-29T12:00:00Z",
            "2026-07-19T24:00:00Z",
            "2026-07-19T12:60:00Z",
            "2026-07-19T12:00:60Z",
            "2026-07-19T12:00:00.Z",
            "2026-07-19T12:00:00.+00:00",
            "2026-07-19T12:00:00..1Z",
            "2026-07-19T12:00:00.1.2Z",
            "2026-07-19T12:00:00.123aZ",
            "2026-07-19T12:00:00.123a+00:00",
            "2026-07-19T12:00:00.１２３Z",
            "2026-07-19T12:00:00+24:00",
            "2026-07-19T12:00:00-24:00",
            "2026-07-19T12:00:00+00:60",
            "2026-07-19T12:00:00-00:60",
            "2026-07-19T12:00:00+1:00",
            "2026-07-19T12:00:00+01:0",
            "2026-07-19T12:00:00+0100",
            "2026-07-19T12:00:00+01",
            "2026-07-19T12:00:00+0a:00",
            "2026-07-19T12:00:00+01:0a",
            "2026-07-19T12:00:00+01:00:00",
            "2026-07-19T12:00:00+01:00Z",
            "2026-07-19T12:00:00Z+00:00",
            "2026-07-19T12:00:00Ztrailing",
            "2026-07-19T12:00:00.123Ztrailing",
            "2026-07-19T12:00:00.123+00:00trailing",
            "-001-07-19T12:00:00Z",
            "+2026-07-19T12:00:00Z",
            "10000-07-19T12:00:00Z",
            "0000-01-01T00:00:00+00:01",
            "0000-01-01T23:58:59+23:59",
            "9999-12-31T23:59:59-00:01",
            "9999-12-31T00:01:00-23:59",
        ] {
            assert!(
                matches!(
                    parse_timestamp(input),
                    Err(ClaudeReportError::InvalidTimestamp)
                ),
                "{input}"
            );
        }
    }

    #[test]
    fn keeps_missing_and_null_resets_absent() {
        for input in [
            r#"{"utilization":42.5}"#,
            r#"{"utilization":42.5,"resets_at":null}"#,
        ] {
            let window: RawWindow = serde_json::from_str(input).expect("window JSON");
            let allowance = plan_window("claude-five-hour", "5-hour session", 300, window)
                .expect("window without a reset");
            assert_eq!(allowance.resets_at, None);
        }
    }

    #[test]
    fn propagates_reset_errors_without_exposing_the_input() {
        let error = plan_window(
            "claude-five-hour",
            "5-hour session",
            300,
            RawWindow {
                utilization: 42.5,
                resets_at: Some("invalid-reset".to_string()),
            },
        )
        .expect_err("invalid reset must fail the window");
        assert!(matches!(error, ClaudeReportError::InvalidTimestamp));
        assert_eq!(error.to_string(), "invalid Claude reset timestamp");
        assert_eq!(format!("{error:?}"), "InvalidTimestamp");
        assert!(error.source().is_none());
    }
}
