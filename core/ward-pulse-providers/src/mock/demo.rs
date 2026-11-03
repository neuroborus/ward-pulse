//! Debug multi-provider dashboard built from sanitized provider fixtures.
//!
//! Used by the phone Settings "Mock data" toggle so debug builds can exercise
//! Codex / Claude / Cursor / OpenAI UI without live credentials. A seed reshuffles
//! utilization so refresh cycles cover healthy, warning, and rate-limited cases.

use std::error::Error as StdError;
use std::fmt;

use serde_json::{json, Value};
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
const CLAUDE_FABLE_FIXTURE: &str =
    include_str!("../../../../fixtures/providers/claude/oauth_usage_max_fable_synthetic.json");
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
    InvalidAnchor,
    Serialize(serde_json::Error),
}

impl fmt::Display for DebugDemoDashboardError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::InvalidAnchor => formatter.write_str(
                "capture anchor must be YYYY-MM-DDTHH:MM:SSZ with representable rebased dates",
            ),
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
            Self::Build(_) | Self::InvalidAnchor => None,
        }
    }
}

/// Builds a full multi-provider dashboard JSON document for debug Mock data.
///
/// Same seed → same snapshot. A new seed (for example each phone refresh) yields
/// different utilization / status combinations while keeping account shapes stable.
pub fn debug_multi_provider_dashboard_json(seed: u64) -> Result<String, DebugDemoDashboardError> {
    debug_multi_provider_dashboard_json_at(seed, None)
}

/// Optional whole-second UTC anchor; omission preserves the historical seeded output.
pub fn debug_multi_provider_dashboard_json_at(
    seed: u64,
    capture_anchor: Option<&str>,
) -> Result<String, DebugDemoDashboardError> {
    let snapshot = debug_multi_provider_dashboard_at(seed, capture_anchor)?;
    serde_json::to_string(&snapshot).map_err(DebugDemoDashboardError::Serialize)
}

pub fn debug_multi_provider_dashboard(
    seed: u64,
) -> Result<DashboardSnapshot, DebugDemoDashboardError> {
    debug_multi_provider_dashboard_at(seed, None)
}

/// Builds dated Mock data through the normal adapters, without consulting a clock.
pub fn debug_multi_provider_dashboard_at(
    seed: u64,
    capture_anchor: Option<&str>,
) -> Result<DashboardSnapshot, DebugDemoDashboardError> {
    let anchor = capture_anchor.map(DemoTime::parse).transpose()?;
    let mut rng = SeedRng(seed);
    let cursor_plan = cursor_plan_account(&mut rng, anchor)?;
    let mut accounts = vec![
        (openai_account(anchor)?, ScrambleMode::Budgets),
        (codex_account(anchor)?, ScrambleMode::Allowances),
        (claude_plan_account(anchor)?, ScrambleMode::Allowances),
        (anthropic_platform_account(anchor)?, ScrambleMode::Budgets),
        (cursor_plan, ScrambleMode::Allowances),
    ];
    if anchor.is_none() {
        accounts.push((cursor_platform_account(anchor)?, ScrambleMode::Budgets));
    }
    let accounts: Vec<_> = accounts
        .into_iter()
        .map(|(account, mode)| scramble_account(&mut rng, account, mode, anchor.is_some()))
        .collect();

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
    preserve_unknowns: bool,
) -> ProviderSnapshot {
    match mode {
        ScrambleMode::Allowances => {
            for allowance in &mut account.allowances {
                if !preserve_unknowns
                    || allowance.used_percent.is_some()
                    || (allowance.source == AllowanceSource::Purchased
                        && allowance.limit.is_none()
                        && allowance.remaining.is_some())
                {
                    scramble_allowance(rng, allowance);
                }
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
    let Some((limit, used_percent)) = budget_target(budget, interesting_percent(rng)) else {
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

/// Ceiling to scramble the budget against, and the draw to scramble with.
///
/// Demo platform accounts are built by the real adapters, and providers report
/// spend but never a budget, so every `limit` arrives as `None` and the budget
/// rings could never fill. Stand in for the local limit a user would set,
/// derived from the fixture's own spend so the invented ceiling stays in scale.
///
/// The draw is clamped only for an invented ceiling: a limit we made up should
/// not also make up an exhausted budget, which `calculate_budget_state` reports
/// as `Error` and which then reads as a real failure on every surface. A real
/// limit still runs the full range.
fn budget_target(budget: &BudgetState, drawn: f64) -> Option<(Money, f64)> {
    match budget.limit.clone() {
        Some(limit) if limit.minor_units > 0 => Some((limit, drawn)),
        _ => {
            let spent = budget.spent.as_ref()?;
            let used_percent = drawn.clamp(5.0, 95.0);
            let units = ((spent.minor_units as f64) * 100.0 / used_percent).round() as i64;
            (units > 0).then(|| {
                (
                    Money::minor_units(units, spent.currency.clone()),
                    used_percent,
                )
            })
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

fn openai_account(anchor: Option<DemoTime>) -> Result<ProviderSnapshot, DebugDemoDashboardError> {
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
    openai_provider_snapshot_from_report_json(&dated_report(&report, anchor)?)
        .map(|report| report.provider_snapshot)
        .map_err(|error| DebugDemoDashboardError::Build(error.to_string()))
}

fn codex_account(anchor: Option<DemoTime>) -> Result<ProviderSnapshot, DebugDemoDashboardError> {
    codex_provider_snapshot_from_report_json(&dated_report(CODEX_FIXTURE, anchor)?)
        .map(|report| report.provider_snapshot)
        .map_err(|error| DebugDemoDashboardError::Build(error.to_string()))
}

fn claude_plan_account(
    anchor: Option<DemoTime>,
) -> Result<ProviderSnapshot, DebugDemoDashboardError> {
    let fixture = if anchor.is_some() {
        CLAUDE_FABLE_FIXTURE
    } else {
        CLAUDE_OAUTH_FIXTURE
    };
    claude_provider_snapshot_from_report_json(&dated_report(fixture, anchor)?)
        .map(|report| report.provider_snapshot)
        .map_err(|error| DebugDemoDashboardError::Build(error.to_string()))
}

fn anthropic_platform_account(
    anchor: Option<DemoTime>,
) -> Result<ProviderSnapshot, DebugDemoDashboardError> {
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
    let mut report: Value = serde_json::from_str(&dated_report(&report, anchor)?)
        .map_err(|error| DebugDemoDashboardError::Build(error.to_string()))?;
    let captured = DemoTime::parse(
        report["generatedAt"]
            .as_str()
            .ok_or(DebugDemoDashboardError::InvalidAnchor)?,
    )?;
    report["capturedEndMicros"] = json!(captured.0 * 1_000_000);
    let mut costs: Value = serde_json::from_str(
        report["costPages"][0]
            .as_str()
            .ok_or(DebugDemoDashboardError::InvalidAnchor)?,
    )
    .map_err(|error| DebugDemoDashboardError::Build(error.to_string()))?;
    let days = costs["data"]
        .as_array_mut()
        .ok_or(DebugDemoDashboardError::InvalidAnchor)?;
    let start = captured.week_start()?.0.min(captured.month_start(false)?.0);
    // These explicit empty buckets are synthetic coverage, never evidence of live costs.
    for seconds in (start..captured.0).step_by(DAY_SECONDS as usize) {
        let day = DemoTime(seconds).stamp();
        if !days
            .iter()
            .any(|bucket| bucket["starting_at"].as_str() == Some(day.as_str()))
        {
            days.push(json!({
                "starting_at": day,
                "ending_at": DemoTime::new(seconds + DAY_SECONDS)?.stamp(),
                "results": []
            }));
        }
    }
    report["costPages"] = json!([costs.to_string()]);
    anthropic_provider_snapshot_from_report_json(&report.to_string())
        .map(|report| report.provider_snapshot)
        .map_err(|error| DebugDemoDashboardError::Build(error.to_string()))
}

fn cursor_plan_account(
    rng: &mut SeedRng,
    anchor: Option<DemoTime>,
) -> Result<ProviderSnapshot, DebugDemoDashboardError> {
    let mut value: serde_json::Value = serde_json::from_str(CURSOR_PLAN_FIXTURE)
        .map_err(|error| DebugDemoDashboardError::Build(error.to_string()))?;
    // Occasionally drop pool meters so the older single "Plan usage" bar appears;
    // percent values are always applied later by scramble_allowance.
    if rng.next_u32() % 5 == 0 && anchor.is_none() {
        if let Some(plan) = value
            .pointer_mut("/individualUsage/plan")
            .and_then(|node| node.as_object_mut())
        {
            plan.remove("autoPercentUsed");
            plan.remove("apiPercentUsed");
            plan.insert("totalPercentUsed".into(), json!(50.0));
        }
    }
    cursor_plan_snapshot_from_report_json(&dated_report(&value.to_string(), anchor)?)
        .map(|report| report.provider_snapshot)
        .map_err(|error| DebugDemoDashboardError::Build(error.to_string()))
}

fn cursor_platform_account(
    anchor: Option<DemoTime>,
) -> Result<ProviderSnapshot, DebugDemoDashboardError> {
    let report = json!({
        "accountId": "cursor-team-demo",
        "generatedAt": "2026-07-19T12:00:00Z",
        "dailyUsagePages": [CURSOR_DAILY_FIXTURE],
        "spendPages": [CURSOR_SPEND_FIXTURE]
    })
    .to_string();
    cursor_platform_snapshot_from_report_json(&dated_report(&report, anchor)?)
        .map(|report| report.provider_snapshot)
        .map_err(|error| DebugDemoDashboardError::Build(error.to_string()))
}

const DAY_SECONDS: i64 = 86_400;

/// Gregorian UTC arithmetic confined to the debug producer (no clock or dependency).
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
struct DemoTime(i64);

impl DemoTime {
    fn new(seconds: i64) -> Result<Self, DebugDemoDashboardError> {
        if !(-62_135_596_800..=253_402_300_799).contains(&seconds) {
            return Err(DebugDemoDashboardError::InvalidAnchor);
        }
        Ok(Self(seconds))
    }

    fn parse(value: &str) -> Result<Self, DebugDemoDashboardError> {
        if value.len() != 20 || !value.is_ascii() {
            return Err(DebugDemoDashboardError::InvalidAnchor);
        }
        let number = |range: std::ops::Range<usize>| {
            value[range]
                .parse::<i64>()
                .map_err(|_| DebugDemoDashboardError::InvalidAnchor)
        };
        let (year, month, day) = (number(0..4)?, number(5..7)?, number(8..10)?);
        let (hour, minute, second) = (number(11..13)?, number(14..16)?, number(17..19)?);
        if !(1..=12).contains(&month)
            || !(1..=31).contains(&day)
            || !(0..24).contains(&hour)
            || !(0..60).contains(&minute)
            || !(0..60).contains(&second)
        {
            return Err(DebugDemoDashboardError::InvalidAnchor);
        }
        let parsed = Self::new(
            Self::days(year, month, day) * DAY_SECONDS + hour * 3_600 + minute * 60 + second,
        )?;
        if parsed.stamp() != value {
            return Err(DebugDemoDashboardError::InvalidAnchor);
        }
        Ok(parsed)
    }

    fn days(year: i64, month: i64, day: i64) -> i64 {
        let year = year - i64::from(month <= 2);
        let era = year.div_euclid(400);
        let year_of_era = year - era * 400;
        let month = month + if month > 2 { -3 } else { 9 };
        let day_of_year = (153 * month + 2) / 5 + day - 1;
        era * 146_097 + year_of_era * 365 + year_of_era / 4 - year_of_era / 100 + day_of_year
            - 719_468
    }

    fn civil(self) -> (i64, i64, i64) {
        let days = self.0.div_euclid(DAY_SECONDS) + 719_468;
        let era = days.div_euclid(146_097);
        let day_of_era = days - era * 146_097;
        let year_of_era =
            (day_of_era - day_of_era / 1_460 + day_of_era / 36_524 - day_of_era / 146_096) / 365;
        let day_of_year = day_of_era - (365 * year_of_era + year_of_era / 4 - year_of_era / 100);
        let month_prime = (5 * day_of_year + 2) / 153;
        let day = day_of_year - (153 * month_prime + 2) / 5 + 1;
        let month = month_prime + if month_prime < 10 { 3 } else { -9 };
        (year_of_era + era * 400 + i64::from(month <= 2), month, day)
    }

    fn stamp(self) -> String {
        let (year, month, day) = self.civil();
        let clock = self.0.rem_euclid(DAY_SECONDS);
        format!(
            "{year:04}-{month:02}-{day:02}T{:02}:{:02}:{:02}Z",
            clock / 3_600,
            clock % 3_600 / 60,
            clock % 60
        )
    }

    fn day_start(self) -> Self {
        Self(self.0.div_euclid(DAY_SECONDS) * DAY_SECONDS)
    }

    fn week_start(self) -> Result<Self, DebugDemoDashboardError> {
        Self::new(
            self.day_start().0 - (self.0.div_euclid(DAY_SECONDS) + 3).rem_euclid(7) * DAY_SECONDS,
        )
    }

    fn month_start(self, next: bool) -> Result<Self, DebugDemoDashboardError> {
        let (mut year, mut month, _) = self.civil();
        if next {
            month += 1;
            if month == 13 {
                year += 1;
                month = 1;
            }
        }
        Self::new(Self::days(year, month, 1) * DAY_SECONDS)
    }
}

fn dated_report(raw: &str, anchor: Option<DemoTime>) -> Result<String, DebugDemoDashboardError> {
    let Some(anchor) = anchor else {
        return Ok(raw.to_string());
    };
    let mut report: Value = serde_json::from_str(raw)
        .map_err(|error| DebugDemoDashboardError::Build(error.to_string()))?;
    let original = DemoTime::parse(
        report["generatedAt"]
            .as_str()
            .ok_or(DebugDemoDashboardError::InvalidAnchor)?,
    )?;
    rebase_fields(&mut report, anchor, original)?;
    Ok(report.to_string())
}

// Only temporal fields in the bundled reports are rewritten. Calendar buckets move
// by whole days; rolling resets retain elapsed time relative to their own report.
fn rebase_fields(
    node: &mut Value,
    anchor: DemoTime,
    original: DemoTime,
) -> Result<(), DebugDemoDashboardError> {
    match node {
        Value::Array(values) => {
            for value in values {
                rebase_fields(value, anchor, original)?;
            }
        }
        Value::Object(fields) => {
            for (key, value) in fields {
                if value.is_null() {
                    continue;
                }
                let day_delta = anchor.day_start().0 - original.day_start().0;
                let shifted = |seconds: i64, delta: i64| {
                    DemoTime::new(
                        seconds
                            .checked_add(delta)
                            .ok_or(DebugDemoDashboardError::InvalidAnchor)?,
                    )
                };
                match key.as_str() {
                    "generatedAt" => *value = json!(anchor.stamp()),
                    "todayStart" | "weekStart" | "monthStart" => {
                        let start = match key.as_str() {
                            "todayStart" => anchor.day_start(),
                            "weekStart" => anchor.week_start()?,
                            _ => anchor.month_start(false)?,
                        };
                        *value = if value.is_number() {
                            json!(start.0)
                        } else {
                            json!(start.stamp())
                        };
                    }
                    "billingCycleStart" | "billingCycleEnd" => {
                        *value = json!(anchor.month_start(key == "billingCycleEnd")?.stamp())
                    }
                    "resetsAt" | "start_time" | "end_time" | "date" => {
                        let scale = if key == "date" { 1_000 } else { 1 };
                        let seconds = value
                            .as_i64()
                            .ok_or(DebugDemoDashboardError::InvalidAnchor)?;
                        let delta = if key == "resetsAt" {
                            anchor.0 - original.0
                        } else {
                            day_delta
                        };
                        *value = json!(
                            shifted(seconds / scale, delta)?.0 * scale + seconds.rem_euclid(scale)
                        );
                    }
                    "resets_at" | "starting_at" | "ending_at" | "startDate" | "day" => {
                        let raw = value
                            .as_str()
                            .ok_or(DebugDemoDashboardError::InvalidAnchor)?;
                        let date_only = matches!(key.as_str(), "startDate" | "day");
                        let stamp = if date_only {
                            format!("{raw}T00:00:00Z")
                        } else if let Some(utc) = raw.strip_suffix("+00:00") {
                            format!("{utc}Z")
                        } else {
                            raw.to_string()
                        };
                        let delta = if key == "resets_at" {
                            anchor.0 - original.0
                        } else {
                            day_delta
                        };
                        let stamp = shifted(DemoTime::parse(&stamp)?.0, delta)?.stamp();
                        *value = json!(if date_only { &stamp[..10] } else { &stamp });
                    }
                    "usagePages" | "costPages" | "dailyUsagePages" | "spendPages" => {
                        for page in value
                            .as_array_mut()
                            .ok_or(DebugDemoDashboardError::InvalidAnchor)?
                        {
                            let mut parsed: Value = serde_json::from_str(
                                page.as_str()
                                    .ok_or(DebugDemoDashboardError::InvalidAnchor)?,
                            )
                            .map_err(|error| DebugDemoDashboardError::Build(error.to_string()))?;
                            rebase_fields(&mut parsed, anchor, original)?;
                            *page = json!(parsed.to_string());
                        }
                    }
                    _ => rebase_fields(value, anchor, original)?,
                }
            }
        }
        _ => {}
    }
    Ok(())
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

    /// A budget at 100% is reported as `Error` and reads as a real failure on
    /// the dashboard, the watch and the widget — which the demo must never
    /// stage. Every ceiling here is invented, since no provider reports one, so
    /// the clamp in `budget_target` has to hold for every account.
    #[test]
    fn demo_budgets_never_read_as_exhausted() {
        for seed in 0..24 {
            let snapshot = debug_multi_provider_dashboard(seed).expect("demo dashboard");
            for account in &snapshot.accounts {
                for state in [&account.today, &account.week, &account.month] {
                    let Some(percent) = state.used_percent else {
                        continue;
                    };
                    assert!(
                        percent < 100.0,
                        "seed {seed}: {:?} {:?} drew {percent}",
                        account.provider,
                        state.period
                    );
                }
            }
        }
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
        assert_eq!(
            left,
            debug_multi_provider_dashboard_json_at(7, None).unwrap()
        );
        let snapshot: DashboardSnapshot = serde_json::from_str(&left).unwrap();
        assert_eq!(snapshot.accounts.len(), 6);
        let anthropic = snapshot
            .accounts
            .iter()
            .find(|account| account.connection.as_deref() == Some("anthropic.platform"))
            .unwrap();
        for budget in [&anthropic.today, &anthropic.week, &anthropic.month] {
            assert!(budget.spent.is_some());
        }
        let cursor = snapshot
            .accounts
            .iter()
            .find(|account| account.connection.as_deref() == Some("cursor.platform"))
            .unwrap();
        for budget in [&cursor.today, &cursor.week] {
            assert!(budget.spent.is_none());
            assert_eq!(budget.status, ProviderStatus::Unknown);
        }
        assert_ne!(cursor.status, ProviderStatus::Ok);
    }

    #[test]
    fn different_seeds_diverge() {
        let left = debug_multi_provider_dashboard_json(1).expect("left");
        let right = debug_multi_provider_dashboard_json(2).expect("right");
        assert_ne!(left, right);
    }

    #[test]
    fn dated_healthy_scenario() {
        // Complete anchored scenario; other seeds may still produce problems.
        let anchor = "2026-11-02T12:00:00Z";
        let snapshot = debug_multi_provider_dashboard_at(280, Some(anchor)).unwrap();
        assert_eq!(
            snapshot,
            debug_multi_provider_dashboard_at(280, Some(anchor)).unwrap()
        );
        assert_ne!(
            snapshot,
            debug_multi_provider_dashboard_at(281, Some(anchor)).unwrap()
        );
        assert_eq!(
            snapshot
                .accounts
                .iter()
                .map(|account| (account.account_id.as_str(), account.connection.as_deref()))
                .collect::<Vec<_>>(),
            vec![
                ("openai-demo", Some("openai.platform")),
                ("codex-local", Some("openai.plan")),
                ("claude-local", Some("anthropic.plan")),
                ("anthropic-demo", Some("anthropic.platform")),
                ("cursor-local", Some("cursor.plan")),
            ]
        );
        assert_eq!(snapshot.overall_status, ProviderStatus::Ok);
        for account in &snapshot.accounts {
            assert_eq!(account.status, ProviderStatus::Ok, "{}", account.account_id);
            for allowance in &account.allowances {
                assert_eq!(allowance.status, ProviderStatus::Ok, "{}", allowance.id);
            }
        }
        let allowance = |id: &str| {
            snapshot
                .accounts
                .iter()
                .flat_map(|account| &account.allowances)
                .find(|value| value.id == id)
                .unwrap()
        };
        for (id, used) in [
            ("codex-primary", 9.6),
            ("claude-five-hour", 48.4),
            ("claude-seven-day", 30.6),
            ("claude-seven-day-fable", 36.9),
            ("cursor-plan-models", 45.95531337916742),
            ("cursor-plan-other", 2.3),
        ] {
            let meter = allowance(id);
            assert_eq!(meter.source, AllowanceSource::Plan);
            assert_eq!(meter.status, ProviderStatus::Ok);
            assert!((meter.used_percent.unwrap() - used).abs() < 1e-9);
        }
        let purchased = allowance("codex-purchased-credits");
        assert!(!purchased.unlimited);
        assert_eq!(purchased.remaining, Some(credits(1_200)));
        assert_eq!(
            (
                purchased.used_percent,
                &purchased.limit,
                &purchased.resets_at
            ),
            (None, &None, &None)
        );
        assert!(allowance("claude-five-hour").resets_at.is_none());
        assert_eq!(
            allowance("claude-seven-day-fable").resets_at,
            allowance("claude-seven-day").resets_at
        );
    }

    #[test]
    fn dated_reports_keep_calendar_buckets_and_rolling_offsets() {
        let baseline = debug_multi_provider_dashboard(280).unwrap();
        for (anchor, day, week, month, next_month) in [
            (
                "2028-02-29T23:59:59Z",
                "2028-02-29",
                "2028-02-28",
                "2028-02-01",
                "2028-03-01",
            ),
            (
                "2027-01-01T00:00:00Z",
                "2027-01-01",
                "2026-12-28",
                "2027-01-01",
                "2027-02-01",
            ),
            (
                "2026-11-02T12:00:00Z",
                "2026-11-02",
                "2026-11-02",
                "2026-11-01",
                "2026-12-01",
            ),
        ] {
            let time = DemoTime::parse(anchor).unwrap();
            assert_eq!(
                time.week_start().unwrap().stamp(),
                format!("{week}T00:00:00Z")
            );
            assert_eq!(
                time.month_start(false).unwrap().stamp(),
                format!("{month}T00:00:00Z")
            );
            let snapshot = debug_multi_provider_dashboard_at(280, Some(anchor)).unwrap();
            assert_eq!(snapshot.generated_at.as_str(), anchor);
            for (account, previous) in snapshot.accounts.iter().zip(&baseline.accounts) {
                assert_eq!(
                    account.last_successful_sync_at.as_ref().unwrap().as_str(),
                    anchor
                );
                let anthropic = account.connection.as_deref() == Some("anthropic.platform");
                let history: Vec<_> = account
                    .buckets
                    .iter()
                    .filter(|bucket| !anthropic || bucket.input_tokens.is_some())
                    .collect();
                let old_history: Vec<_> = previous
                    .buckets
                    .iter()
                    .filter(|bucket| !anthropic || bucket.input_tokens.is_some())
                    .collect();
                assert_eq!(history.len(), old_history.len());
                for (bucket, old_bucket) in history.iter().zip(&old_history) {
                    let start = DemoTime::parse(bucket.start_at.as_str()).unwrap();
                    let old_start = DemoTime::parse(old_bucket.start_at.as_str()).unwrap();
                    let old_sync = DemoTime::parse(
                        previous.last_successful_sync_at.as_ref().unwrap().as_str(),
                    )
                    .unwrap();
                    assert_eq!(
                        start.0 - old_start.0,
                        time.day_start().0 - old_sync.day_start().0,
                        "{:?} history",
                        account.connection
                    );
                    assert_eq!(bucket.input_tokens, old_bucket.input_tokens);
                    assert_eq!(bucket.cached_tokens, old_bucket.cached_tokens);
                }
                for bucket in &account.buckets {
                    let start = DemoTime::parse(bucket.start_at.as_str()).unwrap();
                    let end = DemoTime::parse(bucket.end_at.as_str()).unwrap();
                    assert_eq!(start.0.rem_euclid(DAY_SECONDS), 0);
                    assert_eq!(end.0 - start.0, DAY_SECONDS);
                    assert!(start.0 <= time.day_start().0);
                }
                if anthropic {
                    let start = time
                        .week_start()
                        .unwrap()
                        .0
                        .min(time.month_start(false).unwrap().0);
                    let covered = account
                        .buckets
                        .iter()
                        .filter(|bucket| bucket.cost.is_some())
                        .count();
                    assert_eq!(
                        covered as i64,
                        (time.0 - start + DAY_SECONDS - 1) / DAY_SECONDS
                    );
                }
                for meter in &account.allowances {
                    if meter.id == "codex-primary" {
                        assert_eq!(meter.window_minutes, Some(10_080));
                        let reset =
                            DemoTime::parse(meter.resets_at.as_ref().unwrap().as_str()).unwrap();
                        assert_eq!(reset.0 - time.0, 1_785_059_737 - 1_784_462_400);
                    } else if meter.id == "claude-seven-day" || meter.id == "claude-seven-day-fable"
                    {
                        assert_eq!(meter.window_minutes, Some(10_080));
                        let reset =
                            DemoTime::parse(meter.resets_at.as_ref().unwrap().as_str()).unwrap();
                        assert_eq!(reset.0 - time.0, 7 * DAY_SECONDS + 8 * 3_600);
                    } else if meter.id.starts_with("cursor-") {
                        assert_eq!(
                            meter.resets_at.as_ref().unwrap().as_str(),
                            format!("{next_month}T00:00:00Z")
                        );
                    }
                }
            }
            // These un-scrambled adapters must calculate periods from the rebased history.
            for account in [
                openai_account(Some(time)).unwrap(),
                anthropic_platform_account(Some(time)).unwrap(),
            ] {
                for (state, start) in [
                    (&account.today, day),
                    (&account.week, week),
                    (&account.month, month),
                ] {
                    let start = format!("{start}T00:00:00Z");
                    let cents: i64 = account
                        .buckets
                        .iter()
                        .filter(|bucket| bucket.start_at.as_str() >= start.as_str())
                        .filter_map(|bucket| bucket.cost.as_ref())
                        .map(|cost| cost.minor_units)
                        .sum();
                    let empty = account.connection.as_deref() == Some("anthropic.platform")
                        && DemoTime::parse(&start).unwrap().0 >= time.0;
                    assert_eq!(
                        state.spent.as_ref().map(|spent| spent.minor_units),
                        (!empty).then_some(cents)
                    );
                }
            }
        }
    }

    #[test]
    fn dated_input_refuses_invalid_anchors_and_retains_unknowns() {
        for anchor in [
            "",
            "not a date",
            "2026-02-29T12:00:00Z",
            "2026-04-31T00:00:00Z",
            "2026-11-02T24:00:00Z",
            "2026-11-02T12:00:60Z",
            "2026-11-02T12:00:00+00:00",
            "2026-11-02T12:00:00.1Z",
            "0000-01-01T00:00:00Z",
            "0000-06-01T00:00:00Z",
            "0001-01-01T00:00:00Z",
            "9999-12-31T12:00:00Z",
            "2026-11-02T12:00:00Z\0",
        ] {
            assert!(
                matches!(
                    debug_multi_provider_dashboard_at(280, Some(anchor)),
                    Err(DebugDemoDashboardError::InvalidAnchor)
                ),
                "{anchor:?}"
            );
        }
        let mut account =
            claude_plan_account(Some(DemoTime::parse("2026-11-02T12:00:00Z").unwrap())).unwrap();
        account.allowances[0].used_percent = None;
        account.allowances[0].status = ProviderStatus::Unknown;
        let mut purchased = account.allowances[0].clone();
        purchased.id = "purchased".to_string();
        purchased.source = AllowanceSource::Purchased;
        purchased.limit = Some(credits(500));
        purchased.remaining = Some(credits(400));
        account.allowances.push(purchased);
        let unknowns = account.allowances.clone();
        let scrambled =
            scramble_account(&mut SeedRng(280), account, ScrambleMode::Allowances, true);
        assert_eq!(scrambled.allowances[0], unknowns[0]);
        assert_eq!(scrambled.allowances.last(), unknowns.last());
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
