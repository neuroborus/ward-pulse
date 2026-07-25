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
    AllowanceSource, AllowanceState, BudgetPeriod, ProviderKind, ProviderSnapshot,
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
pub fn cursor_plan_snapshot_from_report_json(
    report_json: &str,
) -> Result<CursorPlanReportSnapshot, CursorPlanReportError> {
    let report: RawReport =
        serde_json::from_str(report_json).map_err(CursorPlanReportError::Json)?;
    let mut allowances = Vec::new();

    if let Some(plan) = report
        .individual_usage
        .as_ref()
        .and_then(|usage| usage.plan.as_ref())
        .filter(|plan| plan.enabled.unwrap_or(true))
    {
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
            unlimited: report.is_unlimited.unwrap_or(false),
            window_minutes: None,
            resets_at: report.billing_cycle_end.clone(),
            status: percent_status(used_percent),
        });
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
            resets_at: report.billing_cycle_end.clone(),
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
    total_percent_used: Option<f64>,
}

#[cfg(test)]
mod tests {
    use ward_pulse_core::model::ProviderStatus;

    use super::*;

    const REPORT_FIXTURE: &str =
        include_str!("../../../../fixtures/providers/cursor/usage_summary.json");

    #[test]
    fn normalizes_plan_and_on_demand_meters() {
        let snapshot = cursor_plan_snapshot_from_report_json(REPORT_FIXTURE).expect("normalize");
        assert_eq!(snapshot.provider_snapshot.provider, ProviderKind::Cursor);
        assert_eq!(snapshot.provider_snapshot.allowances.len(), 2);
    }

    #[test]
    fn keeps_an_omitted_on_demand_limit_unknown() {
        let report = REPORT_FIXTURE.replace("\"limit\": 1000,", "");
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
