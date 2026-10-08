//! Cursor provider normalization.
//!
//! - Plan: undocumented dashboard `GET /api/usage-summary` compatibility contract.
//! - Platform: official team Admin API daily usage and spend.

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
    cursor_platform_snapshot_from_report_json, CursorPlatformReportError,
    CursorPlatformReportSnapshot,
};

pub const PROVIDER_NAME: &str = "Cursor";

/// Union of Cursor plan and team Admin API capabilities.
pub(crate) const CAPABILITIES: ProviderCapabilities = ProviderCapabilities {
    supports_cost: true,
    supports_tokens: false,
    supports_requests: true,
    supports_credits: true,
    usage_buckets: BucketCapabilities::DAILY,
    cost_buckets: BucketCapabilities::DAILY,
    supports_usage_model_breakdown: false,
    supports_cost_model_breakdown: false,
    supports_workspace_breakdown: false,
    supports_active_agents: false,
};

#[derive(Clone, Debug, PartialEq)]
pub struct CursorPlanReportSnapshot {
    pub generated_at: DateTimeUtc,
    pub provider_snapshot: ProviderSnapshot,
}

#[derive(Debug)]
pub enum CursorPlanReportError {
    Json(serde_json::Error),
}

impl fmt::Display for CursorPlanReportError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::Json(error) => write!(
                formatter,
                "invalid Cursor usage summary JSON at line {} column {}",
                error.line(),
                error.column()
            ),
        }
    }
}

impl StdError for CursorPlanReportError {
    fn source(&self) -> Option<&(dyn StdError + 'static)> {
        match self {
            Self::Json(error) => Some(error),
        }
    }
}

/// Normalizes a sanitized Cursor dashboard usage-summary payload.
///
/// Pro+ / Ultra dashboards expose two included plan pools (`autoPercentUsed` =
/// Cursor Models, `apiPercentUsed` = Other Models). When either pool percent is
/// present, emit those as separate plan allowances. Older payloads without pool
/// percents keep a single combined "Plan usage" bar.
pub fn cursor_plan_snapshot_from_report_json(
    report_json: &str,
) -> Result<CursorPlanReportSnapshot, CursorPlanReportError> {
    let report: RawReport =
        serde_json::from_str(report_json).map_err(CursorPlanReportError::Json)?;
    let mut allowances = Vec::new();
    let unlimited = report.is_unlimited.unwrap_or(false);
    let resets_at = report.billing_cycle_end.clone();

    if let Some(plan) = report
        .individual_usage
        .as_ref()
        .and_then(|usage| usage.plan.as_ref())
        .filter(|plan| plan.enabled.unwrap_or(true))
    {
        let has_pool_percents = plan.auto_percent_used.is_some() || plan.api_percent_used.is_some();
        if has_pool_percents {
            if let Some(used_percent) = plan.auto_percent_used {
                allowances.push(plan_pool_allowance(
                    "cursor-plan-models",
                    "Cursor Models",
                    used_percent,
                    unlimited,
                    resets_at.clone(),
                ));
            }
            if let Some(used_percent) = plan.api_percent_used {
                allowances.push(plan_pool_allowance(
                    "cursor-plan-other",
                    "Other Models",
                    used_percent,
                    unlimited,
                    resets_at.clone(),
                ));
            }
        } else {
            let used_percent = plan
                .total_percent_used
                .or_else(|| percent_of(plan.used, plan.limit));
            allowances.push(AllowanceState {
                id: "cursor-plan".to_string(),
                source: AllowanceSource::Plan,
                label: "Plan usage".to_string(),
                used_percent,
                used: plan.used.map(credits_from_cents),
                limit: plan.limit.map(credits_from_cents),
                remaining: plan.remaining.map(credits_from_cents),
                unlimited,
                window_minutes: None,
                resets_at: resets_at.clone(),
                status: percent_status(used_percent),
            });
        }
    }

    if let Some(on_demand) = report
        .individual_usage
        .as_ref()
        .and_then(|usage| usage.on_demand.as_ref())
        .filter(|value| value.enabled.unwrap_or(false))
    {
        let used_percent = percent_of(on_demand.used, on_demand.limit);
        allowances.push(AllowanceState {
            id: "cursor-on-demand".to_string(),
            source: AllowanceSource::Purchased,
            label: "On-demand usage".to_string(),
            used_percent,
            used: on_demand.used.map(credits_from_cents),
            limit: on_demand.limit.map(credits_from_cents),
            remaining: on_demand.remaining.map(credits_from_cents),
            // A missing limit is unknown, not unlimited.
            unlimited: false,
            window_minutes: None,
            resets_at,
            status: percent_status(used_percent),
        });
    }

    let status = worst_status(&allowances);
    let unknown_budget = |period| calculate_budget_state(period, None, None, None);

    Ok(CursorPlanReportSnapshot {
        generated_at: report.generated_at.clone(),
        provider_snapshot: ProviderSnapshot {
            account_id: report
                .account_id
                .unwrap_or_else(|| "cursor-local".to_string()),
            provider: ProviderKind::Cursor,
            connection: Some(connection::CURSOR_PLAN.to_string()),
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

fn percent_of(used: Option<f64>, limit: Option<f64>) -> Option<f64> {
    match (used, limit) {
        (Some(used), Some(limit)) if limit > 0.0 => Some((used / limit) * 100.0),
        _ => None,
    }
}

fn plan_pool_allowance(
    id: &str,
    label: &str,
    used_percent: f64,
    unlimited: bool,
    resets_at: Option<DateTimeUtc>,
) -> AllowanceState {
    // Pool meters are percentage-first; shared plan used/limit cents are not
    // attributed per pool in usage-summary.
    AllowanceState {
        id: id.to_string(),
        source: AllowanceSource::Plan,
        label: label.to_string(),
        used_percent: Some(used_percent),
        used: None,
        limit: None,
        remaining: None,
        unlimited,
        window_minutes: None,
        resets_at,
        status: percent_status(Some(used_percent)),
    }
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct RawReport {
    #[serde(default)]
    account_id: Option<String>,
    generated_at: DateTimeUtc,
    #[serde(default)]
    billing_cycle_end: Option<DateTimeUtc>,
    #[serde(default)]
    is_unlimited: Option<bool>,
    #[serde(default)]
    individual_usage: Option<RawIndividualUsage>,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct RawIndividualUsage {
    #[serde(default)]
    plan: Option<RawMeter>,
    #[serde(default)]
    on_demand: Option<RawMeter>,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct RawMeter {
    #[serde(default)]
    enabled: Option<bool>,
    #[serde(default)]
    used: Option<f64>,
    #[serde(default)]
    limit: Option<f64>,
    #[serde(default)]
    remaining: Option<f64>,
    #[serde(default)]
    auto_percent_used: Option<f64>,
    #[serde(default)]
    api_percent_used: Option<f64>,
    #[serde(default)]
    total_percent_used: Option<f64>,
}

#[cfg(test)]
mod tests {
    use ward_pulse_core::model::ProviderStatus;

    use super::*;

    const REPORT_FIXTURE: &str =
        include_str!("../../../../fixtures/providers/cursor/usage_summary.json");

    #[test]
    fn normalizes_plan_pools_and_on_demand_meters() {
        let snapshot = cursor_plan_snapshot_from_report_json(REPORT_FIXTURE).expect("normalize");
        assert_eq!(snapshot.provider_snapshot.provider, ProviderKind::Cursor);
        let allowances = &snapshot.provider_snapshot.allowances;
        assert_eq!(allowances.len(), 3);
        assert_eq!(allowances[0].id, "cursor-plan-models");
        assert_eq!(allowances[0].label, "Cursor Models");
        assert_eq!(allowances[0].used_percent, Some(47.0));
        assert_eq!(allowances[1].id, "cursor-plan-other");
        assert_eq!(allowances[1].label, "Other Models");
        assert_eq!(allowances[1].used_percent, Some(100.0));
        assert_eq!(allowances[2].id, "cursor-on-demand");
    }

    #[test]
    fn falls_back_to_combined_plan_without_pool_percents() {
        let report = REPORT_FIXTURE
            .replace("\"autoPercentUsed\": 47.0,\n      ", "")
            .replace("\"apiPercentUsed\": 100.0,\n      ", "");
        let snapshot = cursor_plan_snapshot_from_report_json(&report).expect("normalize");
        let plan = snapshot
            .provider_snapshot
            .allowances
            .iter()
            .find(|allowance| allowance.id == "cursor-plan")
            .expect("combined plan");
        assert_eq!(plan.label, "Plan usage");
        assert_eq!(plan.used_percent, Some(60.35));
    }

    #[test]
    fn keeps_an_omitted_on_demand_limit_unknown() {
        let report = REPORT_FIXTURE.replace("\"limit\": 100000,", "");
        let snapshot = cursor_plan_snapshot_from_report_json(&report).expect("normalize");
        let on_demand = snapshot
            .provider_snapshot
            .allowances
            .iter()
            .find(|allowance| allowance.id == "cursor-on-demand")
            .expect("on-demand allowance");

        assert_eq!(on_demand.limit, None);
        assert_eq!(on_demand.used_percent, None);
        assert!(!on_demand.unlimited);
        assert_eq!(on_demand.status, ProviderStatus::Unknown);
    }
}
