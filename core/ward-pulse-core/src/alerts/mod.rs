use std::collections::HashMap;

use serde::{Deserialize, Serialize};

use crate::budget::calculate_budget_state;
use crate::dashboard::build_dashboard_snapshot;
use crate::model::{
    connection, Alert, AlertSeverity, AllowanceSource, AllowanceState, BudgetPeriod, BudgetState,
    DashboardSnapshot, Money, ProviderKind, ProviderSnapshot, ProviderStatus,
};

/// Opt-in used-% threshold. `None` means the rule is off.
#[derive(Clone, Debug, Default, PartialEq, Eq, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct PercentThreshold {
    /// Fire when used percent reaches this value.
    #[serde(default, alias = "warnAt", skip_serializing_if = "Option::is_none")]
    pub at: Option<u8>,
}

impl PercentThreshold {
    pub fn is_enabled(&self) -> bool {
        self.at.is_some()
    }
}

/// Connection-scoped rules: plan windows, purchased meters, and spend budgets.
///
/// Budgets are per connection on purpose — a threshold on one organization key
/// must not fire because another provider spent money.
#[derive(Clone, Debug, Default, PartialEq, Eq, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ConnectionAlertThresholds {
    #[serde(default)]
    pub plan: PercentThreshold,
    #[serde(default)]
    pub purchased: PercentThreshold,
    #[serde(default)]
    pub today: PercentThreshold,
    #[serde(default)]
    pub week: PercentThreshold,
    #[serde(default)]
    pub month: PercentThreshold,
    /// Local spend limits in minor units. Organization keys report spend but no
    /// budget, so a percentage is only computable once the user sets one.
    #[serde(default)]
    pub budget: ConnectionBudget,
}

/// User-entered spend limits, one per budget period.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ConnectionBudget {
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub today: Option<i64>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub week: Option<i64>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub month: Option<i64>,
}

impl ConnectionBudget {
    fn for_period(&self, period: BudgetPeriod) -> Option<i64> {
        match period {
            BudgetPeriod::Today => self.today,
            BudgetPeriod::Week => self.week,
            BudgetPeriod::Month => self.month,
        }
    }
}

impl ConnectionAlertThresholds {
    /// Rule governing an allowance, chosen by where its capacity comes from.
    fn for_allowance(&self, source: AllowanceSource) -> &PercentThreshold {
        match source {
            AllowanceSource::Plan => &self.plan,
            AllowanceSource::Purchased => &self.purchased,
        }
    }

    pub fn is_enabled(&self) -> bool {
        self.plan.is_enabled()
            || self.purchased.is_enabled()
            || self.today.is_enabled()
            || self.week.is_enabled()
            || self.month.is_enabled()
    }
}

/// User-configured alert rules from the phone shell (Providers).
///
/// Defaults are all off (opt-in). Keys in [`Self::connections`] match phone
/// `ProviderConnectionId.storageKey` values (`openai.plan`, …).
#[derive(Clone, Debug, Default, PartialEq, Eq, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct AlertSettings {
    #[serde(default)]
    pub connections: HashMap<String, ConnectionAlertThresholds>,
}

/// Evaluates dashboard alerts from user rules only — never from status chrome alone.
pub fn calculate_alerts(snapshot: &DashboardSnapshot, settings: &AlertSettings) -> Vec<Alert> {
    let mut alerts = Vec::new();
    for account in &snapshot.accounts {
        alerts.extend(alerts_for_account(account, settings));
    }
    alerts
}

/// Applies local budget limits, then replaces alerts with [`calculate_alerts`].
///
/// Limits arrive from the shell because providers do not report them. Rebuilding
/// the snapshot keeps totals, watch summary, and per-account percentages in step
/// with the limits the user just set.
pub fn apply_alert_settings(
    snapshot: DashboardSnapshot,
    settings: &AlertSettings,
) -> DashboardSnapshot {
    let accounts = snapshot
        .accounts
        .into_iter()
        .map(|account| apply_local_budget(account, settings))
        .map(|account| raise_crossed_thresholds(account, settings))
        .collect();
    let rebuilt = build_dashboard_snapshot(snapshot.generated_at, accounts);
    let alerts = calculate_alerts(&rebuilt, settings);
    DashboardSnapshot { alerts, ..rebuilt }
}

/// Recomputes the account's budget states against the user's local limits.
fn apply_local_budget(mut account: ProviderSnapshot, settings: &AlertSettings) -> ProviderSnapshot {
    let Some(rules) = settings.connections.get(connection_key(&account)) else {
        return account;
    };
    for (period, state) in [
        (BudgetPeriod::Today, &mut account.today),
        (BudgetPeriod::Week, &mut account.week),
        (BudgetPeriod::Month, &mut account.month),
    ] {
        let (Some(limit), Some(spent)) = (rules.budget.for_period(period), state.spent.as_ref())
        else {
            continue;
        };
        *state = calculate_budget_state(
            period,
            Some(spent.clone()),
            Some(Money::minor_units(limit, spent.currency.clone())),
            state.projected_total.clone(),
        );
    }
    account
}

/// Raises every card whose own threshold is crossed to Warning.
///
/// A provider only reports whether a pool works, so without this the dashboard
/// shows a healthy check beside its own alert for the same window. Budget cards
/// already carry a percentage-driven status
/// (`budget::DEFAULT_BUDGET_WARN_AT_PERCENT`) but a user line can sit below that
/// fixed one, so they need the same treatment.
///
/// Raising goes through [`ProviderStatus::worst`], so a provider status that
/// already ranks higher — rate limited, auth required — is never softened.
fn raise_crossed_thresholds(
    mut account: ProviderSnapshot,
    settings: &AlertSettings,
) -> ProviderSnapshot {
    let Some(connection) = settings.connections.get(connection_key(&account)) else {
        return account;
    };

    let mut window_crossed = false;
    for allowance in &mut account.allowances {
        let threshold = connection.for_allowance(allowance.source);
        if crossed(allowance.used_percent, threshold.at) {
            allowance.status = ProviderStatus::worst([allowance.status, ProviderStatus::Warning]);
            window_crossed = true;
        }
    }
    // The account follows its windows, the way adapters already derive it, but
    // never its budgets: `build_dashboard_snapshot` keeps the overall pulse about
    // connected providers rather than local spend cards.
    if window_crossed {
        account.status = ProviderStatus::worst([account.status, ProviderStatus::Warning]);
    }

    for (state, threshold) in [
        (&mut account.today, &connection.today),
        (&mut account.week, &connection.week),
        (&mut account.month, &connection.month),
    ] {
        if crossed(state.used_percent, threshold.at) {
            state.status = ProviderStatus::worst([state.status, ProviderStatus::Warning]);
        }
    }
    account
}

fn alert_for_budget(
    provider_label: &str,
    period: &str,
    state: &BudgetState,
    threshold: &PercentThreshold,
) -> Option<Alert> {
    crossed(state.used_percent, threshold.at).then(|| Alert {
        severity: AlertSeverity::Warning,
        message: format!("{provider_label} budget for {period} reached the alert threshold."),
    })
}

/// Storage key of the connection that produced this account.
fn connection_key(account: &ProviderSnapshot) -> &str {
    account
        .connection
        .as_deref()
        .unwrap_or_else(|| fallback_storage_key(account.provider))
}

fn alerts_for_account(account: &ProviderSnapshot, settings: &AlertSettings) -> Vec<Alert> {
    let Some(connection) = settings.connections.get(connection_key(account)) else {
        return Vec::new();
    };
    if !connection.is_enabled() {
        return Vec::new();
    }

    let mut alerts = Vec::new();
    let provider_label = provider_label(account.provider);
    for (period, state, threshold) in [
        ("today", &account.today, &connection.today),
        ("this week", &account.week, &connection.week),
        ("this month", &account.month, &connection.month),
    ] {
        alerts.extend(alert_for_budget(provider_label, period, state, threshold));
    }
    for allowance in &account.allowances {
        let threshold = connection.for_allowance(allowance.source);
        if let Some(alert) = alert_for_allowance(provider_label, allowance, threshold) {
            alerts.push(alert);
        }
    }
    alerts
}

fn alert_for_allowance(
    provider_label: &str,
    allowance: &AllowanceState,
    threshold: &PercentThreshold,
) -> Option<Alert> {
    crossed(allowance.used_percent, threshold.at).then(|| Alert {
        severity: AlertSeverity::Warning,
        message: format!(
            "{} reached the alert threshold.",
            qualified_label(provider_label, &allowance.label)
        ),
    })
}

/// Names a pool as `Codex Weekly plan`, but leaves `Cursor Models` alone.
///
/// Pool labels keep each provider's own wording, so a few already open with the
/// family name and must not carry it twice.
fn qualified_label(provider_label: &str, label: &str) -> String {
    if label.split(' ').next() == Some(provider_label) {
        return label.to_string();
    }
    format!("{provider_label} {label}")
}

fn crossed(used_percent: Option<f64>, at: Option<u8>) -> bool {
    match (used_percent, at) {
        (Some(used), Some(threshold)) => used >= f64::from(threshold),
        _ => false,
    }
}

/// Fallback for snapshots taken before adapters stamped
/// [`ProviderSnapshot::connection`]: the one connection each kind used to imply.
fn fallback_storage_key(provider: ProviderKind) -> &'static str {
    match provider {
        ProviderKind::Codex => connection::CODEX_PLAN,
        ProviderKind::OpenAi => connection::OPENAI_PLATFORM,
        ProviderKind::Claude => connection::CLAUDE_PLAN,
        ProviderKind::Cursor => connection::CURSOR_PLAN,
        ProviderKind::Mock => connection::MOCK_PLAN,
    }
}

fn provider_label(provider: ProviderKind) -> &'static str {
    match provider {
        ProviderKind::OpenAi => "OpenAI",
        ProviderKind::Codex => "Codex",
        ProviderKind::Claude => "Claude",
        ProviderKind::Cursor => "Cursor",
        ProviderKind::Mock => "Mock",
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::model::{
        BudgetPeriod, BudgetState, Money, ProviderSnapshot, ProviderStatus, Quantity, QuantityUnit,
        WatchSummary,
    };
    use crate::time::DateTimeUtc;

    fn budget(used_percent: f64) -> BudgetState {
        BudgetState {
            period: BudgetPeriod::Today,
            spent: Some(Money::minor_units(used_percent as i64, "USD")),
            limit: Some(Money::minor_units(100, "USD")),
            remaining: None,
            used_percent: Some(used_percent),
            projected_total: None,
            status: ProviderStatus::Ok,
        }
    }

    fn snapshot_with(account: ProviderSnapshot, today: BudgetState) -> DashboardSnapshot {
        DashboardSnapshot {
            generated_at: DateTimeUtc::from("2026-06-27T18:42:00Z"),
            overall_status: ProviderStatus::Ok,
            accounts: vec![account],
            today_total: today,
            week_total: budget(0.0),
            month_total: budget(0.0),
            alerts: Vec::new(),
            watch_summary: WatchSummary {
                today_used_percent: None,
                week_used_percent: None,
                status: ProviderStatus::Ok,
            },
        }
    }

    fn claude_account(allowance: AllowanceState) -> ProviderSnapshot {
        ProviderSnapshot {
            account_id: "claude".into(),
            provider: ProviderKind::Claude,
            connection: None,
            status: ProviderStatus::Warning,
            today: budget(0.0),
            week: budget(0.0),
            month: budget(0.0),
            credits: Vec::new(),
            allowances: vec![allowance],
            buckets: Vec::new(),
            model_breakdown: Vec::new(),
            last_successful_sync_at: None,
            last_error: None,
        }
    }

    fn purchased(used_percent: f64) -> AllowanceState {
        AllowanceState {
            id: "claude-extra-usage".into(),
            source: AllowanceSource::Purchased,
            label: "Extra usage".into(),
            used_percent: Some(used_percent),
            used: None,
            limit: None,
            remaining: Some(Quantity {
                value: "15.10".into(),
                unit: QuantityUnit::Credits,
            }),
            unlimited: false,
            window_minutes: None,
            resets_at: None,
            status: ProviderStatus::Warning,
        }
    }

    #[test]
    fn defaults_emit_no_alerts_even_when_status_is_warning() {
        let snapshot = snapshot_with(claude_account(purchased(84.0)), budget(90.0));
        assert!(calculate_alerts(&snapshot, &AlertSettings::default()).is_empty());
    }

    #[test]
    fn a_window_without_a_threshold_keeps_the_status_its_provider_reported() {
        let mut account = claude_account(purchased(84.0));
        account.status = ProviderStatus::Ok;
        account.allowances[0].status = ProviderStatus::Ok;
        // The connection has a rule, but not one that governs this window.
        let settings = AlertSettings {
            connections: HashMap::from([(
                connection::CLAUDE_PLAN.to_string(),
                ConnectionAlertThresholds {
                    today: PercentThreshold { at: Some(80) },
                    ..ConnectionAlertThresholds::default()
                },
            )]),
        };

        let applied = apply_alert_settings(snapshot_with(account, budget(10.0)), &settings);

        let account = &applied.accounts[0];
        assert_eq!(account.allowances[0].status, ProviderStatus::Ok);
        assert_eq!(account.status, ProviderStatus::Ok);
    }

    #[test]
    fn fires_budget_alert_from_the_owning_connection() {
        let mut account = claude_account(purchased(10.0));
        account.today = budget(85.0);
        let snapshot = snapshot_with(account, budget(85.0));
        let settings = AlertSettings {
            connections: HashMap::from([(
                connection::CLAUDE_PLAN.to_string(),
                ConnectionAlertThresholds {
                    today: PercentThreshold { at: Some(80) },
                    ..ConnectionAlertThresholds::default()
                },
            )]),
        };

        let alerts = calculate_alerts(&snapshot, &settings);

        assert_eq!(alerts.len(), 1);
        assert_eq!(alerts[0].severity, AlertSeverity::Warning);
        assert!(alerts[0].message.contains("Claude budget for today"));
    }

    #[test]
    fn a_local_limit_makes_the_budget_percentage_computable() {
        // Organization keys report spend without a budget, so nothing can fire
        // until the user sets a limit.
        let mut account = claude_account(purchased(10.0));
        account.today = calculate_budget_state(
            BudgetPeriod::Today,
            Some(Money::minor_units(9_000, "USD")),
            None,
            None,
        );
        assert_eq!(account.today.used_percent, None);

        let snapshot = snapshot_with(account, budget(0.0));
        let settings = AlertSettings {
            connections: HashMap::from([(
                connection::CLAUDE_PLAN.to_string(),
                ConnectionAlertThresholds {
                    today: PercentThreshold { at: Some(80) },
                    budget: ConnectionBudget {
                        today: Some(10_000),
                        ..ConnectionBudget::default()
                    },
                    ..ConnectionAlertThresholds::default()
                },
            )]),
        };

        let applied = apply_alert_settings(snapshot, &settings);

        assert_eq!(applied.accounts[0].today.used_percent, Some(90.0));
        assert_eq!(applied.alerts.len(), 1);
        assert!(applied.alerts[0]
            .message
            .contains("Claude budget for today"));
    }

    #[test]
    fn budget_alert_ignores_what_other_providers_spent() {
        // The dashboard total crosses the threshold; this connection does not.
        let mut account = claude_account(purchased(10.0));
        account.today = budget(10.0);
        let snapshot = snapshot_with(account, budget(99.0));
        let settings = AlertSettings {
            connections: HashMap::from([(
                connection::CLAUDE_PLAN.to_string(),
                ConnectionAlertThresholds {
                    today: PercentThreshold { at: Some(80) },
                    ..ConnectionAlertThresholds::default()
                },
            )]),
        };

        assert!(calculate_alerts(&snapshot, &settings).is_empty());
    }

    #[test]
    fn a_crossed_threshold_raises_the_window_and_its_account() {
        let mut account = claude_account(purchased(84.0));
        account.status = ProviderStatus::Ok;
        account.allowances[0].status = ProviderStatus::Ok;
        let settings = AlertSettings {
            connections: HashMap::from([(
                connection::CLAUDE_PLAN.to_string(),
                ConnectionAlertThresholds {
                    purchased: PercentThreshold { at: Some(80) },
                    ..ConnectionAlertThresholds::default()
                },
            )]),
        };

        let applied = apply_alert_settings(snapshot_with(account, budget(10.0)), &settings);

        let account = &applied.accounts[0];
        assert_eq!(account.allowances[0].status, ProviderStatus::Warning);
        assert_eq!(account.status, ProviderStatus::Warning);
    }

    /// A user line can sit below the fixed 80% warn, so the card would otherwise
    /// stay Ok next to its own alert. The overall pulse stays out of it: budgets
    /// are local spend cards, not connected-provider health.
    ///
    /// The percentage only exists once the local limit is applied, so this also
    /// pins that raising runs after [`apply_local_budget`], not before.
    #[test]
    fn a_crossed_budget_raises_its_card_but_not_the_overall_pulse() {
        let mut account = claude_account(purchased(10.0));
        account.status = ProviderStatus::Ok;
        account.today = calculate_budget_state(
            BudgetPeriod::Today,
            Some(Money::minor_units(5_000, "USD")),
            None,
            None,
        );
        assert_eq!(account.today.used_percent, None);
        let settings = AlertSettings {
            connections: HashMap::from([(
                connection::CLAUDE_PLAN.to_string(),
                ConnectionAlertThresholds {
                    today: PercentThreshold { at: Some(50) },
                    budget: ConnectionBudget {
                        today: Some(10_000),
                        ..ConnectionBudget::default()
                    },
                    ..ConnectionAlertThresholds::default()
                },
            )]),
        };

        let applied = apply_alert_settings(snapshot_with(account, budget(0.0)), &settings);

        assert_eq!(applied.accounts[0].today.used_percent, Some(50.0));

        assert_eq!(applied.accounts[0].today.status, ProviderStatus::Warning);
        assert_eq!(applied.accounts[0].status, ProviderStatus::Ok);
        assert_eq!(applied.overall_status, ProviderStatus::Ok);
    }

    #[test]
    fn raising_never_softens_a_worse_provider_status() {
        let mut account = claude_account(purchased(84.0));
        account.allowances[0].status = ProviderStatus::RateLimited;
        let settings = AlertSettings {
            connections: HashMap::from([(
                connection::CLAUDE_PLAN.to_string(),
                ConnectionAlertThresholds {
                    purchased: PercentThreshold { at: Some(80) },
                    ..ConnectionAlertThresholds::default()
                },
            )]),
        };

        let applied = apply_alert_settings(snapshot_with(account, budget(10.0)), &settings);

        assert_eq!(
            applied.accounts[0].allowances[0].status,
            ProviderStatus::RateLimited
        );
    }

    #[test]
    fn accepts_legacy_warn_at_json_field() {
        let threshold: PercentThreshold =
            serde_json::from_str(r#"{"warnAt":80,"criticalAt":100}"#).unwrap();
        assert_eq!(threshold.at, Some(80));
    }

    #[test]
    fn fires_purchased_allowance_from_connection_settings() {
        let snapshot = snapshot_with(claude_account(purchased(84.0)), budget(10.0));
        let mut connections = HashMap::new();
        connections.insert(
            "anthropic.plan".into(),
            ConnectionAlertThresholds {
                purchased: PercentThreshold { at: Some(80) },
                ..ConnectionAlertThresholds::default()
            },
        );
        let settings = AlertSettings { connections };
        let alerts = calculate_alerts(&snapshot, &settings);
        assert_eq!(alerts.len(), 1);
        assert_eq!(
            alerts[0].message,
            "Claude Extra usage reached the alert threshold."
        );
        assert_eq!(alerts[0].severity, AlertSeverity::Warning);
    }

    /// Both pools belong to Cursor, but only one already names it — the rule is
    /// per label, not per provider.
    #[test]
    fn allowance_alert_does_not_repeat_a_family_already_in_the_label() {
        let pool = |label: &str| AllowanceState {
            source: AllowanceSource::Plan,
            label: label.into(),
            ..purchased(95.0)
        };
        let account = ProviderSnapshot {
            provider: ProviderKind::Cursor,
            allowances: vec![pool("Cursor Models"), pool("Other Models")],
            ..claude_account(purchased(95.0))
        };
        let snapshot = snapshot_with(account, budget(10.0));
        let settings = AlertSettings {
            connections: HashMap::from([(
                connection::CURSOR_PLAN.to_string(),
                ConnectionAlertThresholds {
                    plan: PercentThreshold { at: Some(80) },
                    ..ConnectionAlertThresholds::default()
                },
            )]),
        };

        let alerts = calculate_alerts(&snapshot, &settings);

        assert_eq!(
            alerts
                .iter()
                .map(|alert| alert.message.as_str())
                .collect::<Vec<_>>(),
            [
                "Cursor Models reached the alert threshold.",
                "Cursor Other Models reached the alert threshold.",
            ]
        );
    }

    #[test]
    fn platform_and_plan_of_one_family_keep_separate_rules() {
        let mut account = claude_account(purchased(84.0));
        account.connection = Some(connection::ANTHROPIC_PLATFORM.to_string());
        let snapshot = snapshot_with(account, budget(10.0));

        let rule = ConnectionAlertThresholds {
            purchased: PercentThreshold { at: Some(80) },
            ..ConnectionAlertThresholds::default()
        };
        let plan_only = AlertSettings {
            connections: HashMap::from([(connection::CLAUDE_PLAN.to_string(), rule.clone())]),
        };
        let platform_only = AlertSettings {
            connections: HashMap::from([(connection::ANTHROPIC_PLATFORM.to_string(), rule)]),
        };

        assert!(calculate_alerts(&snapshot, &plan_only).is_empty());
        assert_eq!(calculate_alerts(&snapshot, &platform_only).len(), 1);
    }

    #[test]
    fn ignores_plan_allowance_when_only_purchased_rule_is_set() {
        let mut plan = purchased(90.0);
        plan.source = AllowanceSource::Plan;
        plan.id = "claude-five-hour".into();
        plan.label = "5-hour session".into();
        let snapshot = snapshot_with(claude_account(plan), budget(10.0));
        let mut connections = HashMap::new();
        connections.insert(
            "anthropic.plan".into(),
            ConnectionAlertThresholds {
                purchased: PercentThreshold { at: Some(80) },
                ..ConnectionAlertThresholds::default()
            },
        );
        let settings = AlertSettings { connections };
        assert!(calculate_alerts(&snapshot, &settings).is_empty());
    }
}
