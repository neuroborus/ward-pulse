//! Debug multi-provider dashboard built from sanitized provider fixtures.
//!
//! Used by the phone Settings "Mock data" toggle so debug builds can exercise
//! Codex / Claude / Cursor / OpenAI UI without live credentials. A seed reshuffles
//! utilization so refresh cycles cover healthy, warning, and rate-limited cases.

use std::error::Error as StdError;
use std::fmt;

use serde_json::json;
use ward_pulse_core::budget::calculate_budget_state;
use ward_pulse_core::build_dashboard_snapshot;
use ward_pulse_core::model::{
    AllowanceSource, AllowanceState, BudgetState, DashboardSnapshot, Money, ProviderSnapshot,
    ProviderStatus, Quantity, QuantityUnit,
};
use ward_pulse_core::time::DateTimeUtc;

use crate::allowance::{percent_status, worst_status};
use crate::claude::{
    anthropic_provider_snapshot_from_report_json, claude_provider_snapshot_from_report_json,
};
use crate::codex::codex_provider_snapshot_from_report_json;
use crate::cursor::{
    cursor_plan_snapshot_from_report_json, cursor_platform_snapshot_from_report_json,
};
use crate::openai::openai_provider_snapshot_from_report_json;

const CODEX_FIXTURE: &str = include_str!("../../../../fixtures/providers/codex/report.json");
const CLAUDE_OAUTH_FIXTURE: &str =
    include_str!("../../../../fixtures/providers/claude/oauth_usage.json");
const CLAUDE_USAGE_FIXTURE: &str =
    include_str!("../../../../fixtures/providers/claude/usage_report.json");
const CLAUDE_COST_FIXTURE: &str =
    include_str!("../../../../fixtures/providers/claude/cost_report.json");
const CURSOR_PLAN_FIXTURE: &str =
    include_str!("../../../../fixtures/providers/cursor/usage_summary.json");
const CURSOR_DAILY_FIXTURE: &str =
    include_str!("../../../../fixtures/providers/cursor/daily_usage.json");
const CURSOR_SPEND_FIXTURE: &str = include_str!("../../../../fixtures/providers/cursor/spend.json");
const OPENAI_USAGE_FIXTURE: &str =
    include_str!("../../../../fixtures/providers/openai/usage_completions.json");
const OPENAI_COST_FIXTURE: &str = include_str!("../../../../fixtures/providers/openai/costs.json");

#[derive(Debug)]
pub enum DebugDemoDashboardError {
    Build(String),
    Serialize(serde_json::Error),
}

impl fmt::Display for DebugDemoDashboardError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::Build(message) => {
                write!(formatter, "failed to build debug demo dashboard: {message}")
            }
            Self::Serialize(error) => {
                write!(
                    formatter,
                    "failed to serialize debug demo dashboard: {error}"
                )
            }
        }
    }
}

impl StdError for DebugDemoDashboardError {
    fn source(&self) -> Option<&(dyn StdError + 'static)> {
        match self {
            Self::Serialize(error) => Some(error),
            Self::Build(_) => None,
        }
    }
}

/// Builds a full multi-provider dashboard JSON document for debug Mock data.
///
/// Same seed → same snapshot. A new seed (for example each phone refresh) yields
/// different utilization / status combinations while keeping account shapes stable.
pub fn debug_multi_provider_dashboard_json(seed: u64) -> Result<String, DebugDemoDashboardError> {
    let snapshot = debug_multi_provider_dashboard(seed)?;
    serde_json::to_string(&snapshot).map_err(DebugDemoDashboardError::Serialize)
}

pub fn debug_multi_provider_dashboard(
    seed: u64,
) -> Result<DashboardSnapshot, DebugDemoDashboardError> {
    let mut rng = SeedRng(seed);
    let cursor_plan = cursor_plan_account(&mut rng)?;
    let accounts = vec![
        scramble_account(&mut rng, openai_account()?, ScrambleMode::Budgets),
        scramble_account(&mut rng, codex_account()?, ScrambleMode::Allowances),
        scramble_account(&mut rng, claude_plan_account()?, ScrambleMode::Allowances),
        scramble_account(
            &mut rng,
            anthropic_platform_account()?,
            ScrambleMode::Budgets,
        ),
        scramble_account(&mut rng, cursor_plan, ScrambleMode::Allowances),
        scramble_account(&mut rng, cursor_platform_account()?, ScrambleMode::Budgets),
    ];

    // Newest fixture stamp keeps relative ordering; seed is what varies content.
    let generated_at = accounts
        .iter()
        .filter_map(|account| account.last_successful_sync_at.as_ref())
        .max_by(|left, right| left.as_str().cmp(right.as_str()))
        .cloned()
        .unwrap_or_else(|| DateTimeUtc::from("2026-07-19T12:00:00Z"));

    Ok(build_dashboard_snapshot(generated_at, accounts))
}

#[derive(Clone, Copy)]
enum ScrambleMode {
    Allowances,
    Budgets,
}

fn scramble_account(
    rng: &mut SeedRng,
    mut account: ProviderSnapshot,
    mode: ScrambleMode,
) -> ProviderSnapshot {
    match mode {
        ScrambleMode::Allowances => {
            for allowance in &mut account.allowances {
                scramble_allowance(rng, allowance);
            }
            account.status = worst_status(&account.allowances);
        }
        ScrambleMode::Budgets => {
            scramble_budget(rng, &mut account.today);
            scramble_budget(rng, &mut account.week);
            scramble_budget(rng, &mut account.month);
            account.status = worst_budget_status(&account);
        }
    }

    // Occasional stale chrome so Wear / phone refresh UI can be exercised.
    if rng.next_u32() % 11 == 0 {
        account.status = ProviderStatus::Stale;
    }

    account
}

fn scramble_allowance(rng: &mut SeedRng, allowance: &mut AllowanceState) {
    if matches!(allowance.source, AllowanceSource::Purchased) {
        scramble_purchased_credits(rng, allowance);
        return;
    }

    let used_percent = interesting_percent(rng);
    allowance.used_percent = Some(used_percent);
    allowance.status = percent_status(Some(used_percent));

    if let (Some(limit), Some(used)) = (allowance.limit.clone(), allowance.used.as_mut()) {
        // Keep quantity units; approximate used from percent when a limit exists.
        if let Ok(limit_value) = limit.value.parse::<f64>() {
            used.value = format!("{:.2}", limit_value * (used_percent / 100.0).min(1.0));
        }
    }
    if let (Some(limit), Some(remaining)) = (allowance.limit.clone(), allowance.remaining.as_mut())
    {
        if let Ok(limit_value) = limit.value.parse::<f64>() {
            let left = (limit_value * (1.0 - (used_percent / 100.0).min(1.0))).max(0.0);
            remaining.value = format!("{left:.2}");
        }
    }
}

/// Demo purchased limits (Claude Extra / Cursor on-demand).
const DEMO_CREDIT_LIMITS: &[i64] = &[200, 500, 1_000, 2_500, 5_000, 12_000, 25_000];

/// Demo balance-only remaining pools (Codex).
const DEMO_CREDIT_BALANCES: &[i64] = &[0, 80, 320, 500, 1_200, 4_500, 12_500, 48_000];

/// Whole, glanceable purchased credits for Mock data (live Codex may be fractional).
fn scramble_purchased_credits(rng: &mut SeedRng, allowance: &mut AllowanceState) {
    // Match live Codex: unlimited / balance-only meters have no utilization percent.
    if allowance.unlimited {
        allowance.used_percent = None;
        allowance.status = ProviderStatus::Ok;
        return;
    }
    if allowance.limit.is_none() {
        if let Some(remaining) = allowance.remaining.as_mut() {
            *remaining = credits(pick_i64(rng, DEMO_CREDIT_BALANCES));
        }
        allowance.used_percent = None;
        allowance.status = ProviderStatus::Ok;
        return;
    }

    let used_percent = interesting_percent(rng);
    allowance.used_percent = Some(used_percent);
    allowance.status = percent_status(Some(used_percent));

    let limit = pick_i64(rng, DEMO_CREDIT_LIMITS);
    let remaining = ((limit as f64) * (1.0 - (used_percent / 100.0).min(1.0)))
        .round()
        .clamp(0.0, limit as f64) as i64;
    let used = limit - remaining;

    if let Some(slot) = allowance.limit.as_mut() {
        *slot = credits(limit);
    }
    if let Some(slot) = allowance.used.as_mut() {
        *slot = credits(used);
    }
    if let Some(slot) = allowance.remaining.as_mut() {
        *slot = credits(remaining);
    }
}

fn credits(value: i64) -> Quantity {
    Quantity {
        value: value.to_string(),
        unit: QuantityUnit::Credits,
    }
}

fn pick_i64(rng: &mut SeedRng, choices: &[i64]) -> i64 {
    choices[(rng.next_u32() as usize) % choices.len()]
}

fn scramble_budget(rng: &mut SeedRng, budget: &mut BudgetState) {
    let used_percent = interesting_percent(rng);
    let Some(limit) = budget_limit(budget, used_percent) else {
        return;
    };
    let spent_units = ((limit.minor_units as f64) * (used_percent / 100.0).min(1.2)).round() as i64;
    let spent = Money::minor_units(spent_units.max(0), limit.currency.clone());
    let projected = budget.projected_total.clone().map(|projected| {
        let bump = ((projected.minor_units as f64) * (0.85 + rng.next_f64() * 0.3)).round() as i64;
        Money::minor_units(bump.max(spent_units), projected.currency)
    });
    *budget = calculate_budget_state(budget.period, Some(spent), Some(limit), projected);
}

/// Ceiling to scramble the budget against.
///
/// Demo platform accounts are built by the real adapters, and providers report
/// spend but never a budget, so every `limit` arrives as `None` and the budget
/// rings could never fill. Stand in for the local limit a user would set,
/// derived from the fixture's own spend so the invented ceiling stays in scale.
fn budget_limit(budget: &BudgetState, used_percent: f64) -> Option<Money> {
    match budget.limit.clone() {
        Some(limit) if limit.minor_units > 0 => Some(limit),
        _ => {
            let spent = budget.spent.as_ref()?;
            // Clamp the divisor so a 0% draw cannot blow the ceiling up.
            let units = ((spent.minor_units as f64) * 100.0 / used_percent.max(5.0)).round() as i64;
            (units > 0).then(|| Money::minor_units(units, spent.currency.clone()))
        }
    }
}

fn worst_budget_status(account: &ProviderSnapshot) -> ProviderStatus {
    ProviderStatus::worst([
        account.today.status,
        account.week.status,
        account.month.status,
    ])
}

fn interesting_percent(rng: &mut SeedRng) -> f64 {
    match rng.next_u32() % 10 {
        0 => 0.0,
        1 => 100.0,
        2 => (92.0 + rng.next_f64() * 8.0).min(100.0),
        3 => 80.0 + rng.next_f64() * 15.0,
        4 => 45.0 + rng.next_f64() * 20.0,
        _ => (rng.next_f64() * 100.0 * 10.0).round() / 10.0,
    }
}

fn openai_account() -> Result<ProviderSnapshot, DebugDemoDashboardError> {
    let report = json!({
        "accountId": "openai-demo",
        "generatedAt": "2026-07-19T12:00:00Z",
        "todayStart": 1_784_419_200_i64,
        "weekStart": 1_783_900_800_i64,
        "monthStart": 1_782_864_000_i64,
        "usagePages": [OPENAI_USAGE_FIXTURE],
        "costPages": [OPENAI_COST_FIXTURE]
    })
    .to_string();
    openai_provider_snapshot_from_report_json(&report)
        .map(|report| report.provider_snapshot)
        .map_err(|error| DebugDemoDashboardError::Build(error.to_string()))
}

fn codex_account() -> Result<ProviderSnapshot, DebugDemoDashboardError> {
    codex_provider_snapshot_from_report_json(CODEX_FIXTURE)
        .map(|report| report.provider_snapshot)
        .map_err(|error| DebugDemoDashboardError::Build(error.to_string()))
}

fn claude_plan_account() -> Result<ProviderSnapshot, DebugDemoDashboardError> {
    claude_provider_snapshot_from_report_json(CLAUDE_OAUTH_FIXTURE)
        .map(|report| report.provider_snapshot)
        .map_err(|error| DebugDemoDashboardError::Build(error.to_string()))
}

fn anthropic_platform_account() -> Result<ProviderSnapshot, DebugDemoDashboardError> {
    let report = json!({
        "accountId": "anthropic-demo",
        "generatedAt": "2026-07-19T12:00:00Z",
        "todayStart": "2026-07-19T00:00:00Z",
        "weekStart": "2026-07-13T00:00:00Z",
        "monthStart": "2026-07-01T00:00:00Z",
        "usagePages": [CLAUDE_USAGE_FIXTURE],
        "costPages": [CLAUDE_COST_FIXTURE]
    })
    .to_string();
    anthropic_provider_snapshot_from_report_json(&report)
        .map(|report| report.provider_snapshot)
        .map_err(|error| DebugDemoDashboardError::Build(error.to_string()))
}

fn cursor_plan_account(rng: &mut SeedRng) -> Result<ProviderSnapshot, DebugDemoDashboardError> {
    let mut value: serde_json::Value = serde_json::from_str(CURSOR_PLAN_FIXTURE)
        .map_err(|error| DebugDemoDashboardError::Build(error.to_string()))?;
    // Occasionally drop pool meters so the older single "Plan usage" bar appears;
    // percent values are always applied later by scramble_allowance.
    if rng.next_u32() % 5 == 0 {
        if let Some(plan) = value
            .pointer_mut("/individualUsage/plan")
            .and_then(|node| node.as_object_mut())
        {
            plan.remove("autoPercentUsed");
            plan.remove("apiPercentUsed");
            plan.insert("totalPercentUsed".into(), json!(50.0));
        }
    }
    cursor_plan_snapshot_from_report_json(&value.to_string())
        .map(|report| report.provider_snapshot)
        .map_err(|error| DebugDemoDashboardError::Build(error.to_string()))
}

fn cursor_platform_account() -> Result<ProviderSnapshot, DebugDemoDashboardError> {
    let report = json!({
        "accountId": "cursor-team-demo",
        "generatedAt": "2026-07-19T12:00:00Z",
        "dailyUsagePages": [CURSOR_DAILY_FIXTURE],
        "spendPages": [CURSOR_SPEND_FIXTURE]
    })
    .to_string();
    cursor_platform_snapshot_from_report_json(&report)
        .map(|report| report.provider_snapshot)
        .map_err(|error| DebugDemoDashboardError::Build(error.to_string()))
}

/// Tiny deterministic PRNG — no extra crate dependency.
struct SeedRng(u64);

impl SeedRng {
    fn next_u32(&mut self) -> u32 {
        self.0 = self.0.wrapping_mul(6364136223846793005).wrapping_add(1);
        (self.0 >> 33) as u32
    }

    fn next_f64(&mut self) -> f64 {
        f64::from(self.next_u32()) / f64::from(u32::MAX)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use ward_pulse_core::model::ProviderKind;

    /// Providers never report a budget, so without a stand-in limit every budget
    /// ring stays unavailable and the demo cannot exercise them at all.
    #[test]
    fn platform_budgets_get_a_percentage_to_show() {
        let snapshot = debug_multi_provider_dashboard(42).expect("demo dashboard");
        let mut checked = 0;
        for account in &snapshot.accounts {
            for state in [&account.today, &account.week, &account.month] {
                // Spend without a percentage is the state that hid the rings. A
                // period the provider never reports stays absent on purpose, the
                // way Cursor leaves day and week.
                if state.spent.is_none() {
                    continue;
                }
                checked += 1;
                assert!(
                    state.used_percent.is_some(),
                    "{:?} {:?} has spend but no percentage",
                    account.provider,
                    state.period
                );
            }
        }
        assert!(
            checked >= 4,
            "too few spend-reporting periods to prove anything"
        );
    }

    #[test]
    fn builds_all_live_provider_kinds() {
        let snapshot = debug_multi_provider_dashboard(42).expect("demo dashboard");
        let kinds: Vec<_> = snapshot
            .accounts
            .iter()
            .map(|account| account.provider)
            .collect();
        assert!(kinds.contains(&ProviderKind::OpenAi));
        assert!(kinds.contains(&ProviderKind::Codex));
        assert!(kinds.contains(&ProviderKind::Claude));
        assert!(kinds.contains(&ProviderKind::Cursor));
        assert!(!kinds.contains(&ProviderKind::Mock));
        assert!(snapshot.accounts.len() >= 5);
    }

    #[test]
    fn same_seed_is_stable() {
        let left = debug_multi_provider_dashboard_json(7).expect("left");
        let right = debug_multi_provider_dashboard_json(7).expect("right");
        assert_eq!(left, right);
    }

    #[test]
    fn different_seeds_diverge() {
        let left = debug_multi_provider_dashboard_json(1).expect("left");
        let right = debug_multi_provider_dashboard_json(2).expect("right");
        assert_ne!(left, right);
    }

    #[test]
    fn demo_purchased_credits_are_glanceable_integers() {
        let snapshot = debug_multi_provider_dashboard(42).expect("demo dashboard");
        let mut saw_purchased = false;
        for account in &snapshot.accounts {
            for allowance in &account.allowances {
                if !matches!(allowance.source, AllowanceSource::Purchased) || allowance.unlimited {
                    continue;
                }
                saw_purchased = true;

                if let Some(limit) = &allowance.limit {
                    let value: i64 = limit.value.parse().expect("integer limit");
                    assert_eq!(limit.unit, QuantityUnit::Credits);
                    assert!(
                        DEMO_CREDIT_LIMITS.contains(&value),
                        "unexpected demo limit {value}"
                    );
                }

                for quantity in [allowance.remaining.as_ref(), allowance.used.as_ref()]
                    .into_iter()
                    .flatten()
                {
                    assert_eq!(quantity.unit, QuantityUnit::Credits);
                    let value: i64 = quantity.value.parse().expect("integer credits");
                    assert!(value >= 0, "credits must be non-negative, got {value}");
                }

                if allowance.limit.is_none() {
                    assert_eq!(allowance.used_percent, None);
                    assert_eq!(allowance.status, ProviderStatus::Ok);
                    if let Some(remaining) = &allowance.remaining {
                        let value: i64 = remaining.value.parse().expect("integer remaining");
                        assert!(
                            DEMO_CREDIT_BALANCES.contains(&value),
                            "unexpected demo balance {value}"
                        );
                    }
                }
            }
        }
        assert!(
            saw_purchased,
            "demo dashboard should include purchased meters"
        );
    }
}
