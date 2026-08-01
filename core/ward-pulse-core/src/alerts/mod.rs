use std::collections::HashMap;

use serde::{Deserialize, Serialize};

use crate::model::{
    Alert, AlertSeverity, AllowanceSource, AllowanceState, BudgetState, DashboardSnapshot,
    ProviderKind, ProviderSnapshot,
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

/// Connection-scoped rules for plan windows and purchased meters.
#[derive(Clone, Debug, Default, PartialEq, Eq, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ConnectionAlertThresholds {
    #[serde(default)]
    pub plan: PercentThreshold,
    #[serde(default)]
    pub purchased: PercentThreshold,
}

impl ConnectionAlertThresholds {
    pub fn is_enabled(&self) -> bool {
        self.plan.is_enabled() || self.purchased.is_enabled()
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
    #[serde(default)]
    pub today: PercentThreshold,
    #[serde(default)]
    pub week: PercentThreshold,
    #[serde(default)]
    pub month: PercentThreshold,
}

/// Evaluates dashboard alerts from user rules only — never from status chrome alone.
pub fn calculate_alerts(snapshot: &DashboardSnapshot, settings: &AlertSettings) -> Vec<Alert> {
    let mut alerts = Vec::new();
    alerts.extend(alerts_for_budget(
        "Today",
        &snapshot.today_total,
        &settings.today,
    ));
    alerts.extend(alerts_for_budget(
        "Week",
        &snapshot.week_total,
        &settings.week,
    ));
    alerts.extend(alerts_for_budget(
        "Month",
        &snapshot.month_total,
        &settings.month,
    ));
    for account in &snapshot.accounts {
        alerts.extend(alerts_for_account(account, settings));
    }
    alerts
}

/// Returns a copy of [snapshot] with alerts replaced by [`calculate_alerts`].
pub fn apply_alert_settings(
    snapshot: DashboardSnapshot,
    settings: &AlertSettings,
) -> DashboardSnapshot {
    let alerts = calculate_alerts(&snapshot, settings);
    DashboardSnapshot { alerts, ..snapshot }
}

fn alerts_for_budget(label: &str, state: &BudgetState, threshold: &PercentThreshold) -> Vec<Alert> {
    if !crossed(state.used_percent, threshold.at) {
        return Vec::new();
    }
    vec![Alert {
        severity: AlertSeverity::Warning,
        message: format!("{label} budget reached the alert threshold."),
    }]
}

fn alerts_for_account(account: &ProviderSnapshot, settings: &AlertSettings) -> Vec<Alert> {
    let Some(connection) = settings
        .connections
        .get(connection_storage_key(account.provider))
    else {
        return Vec::new();
    };
    if !connection.is_enabled() {
        return Vec::new();
    }

    let mut alerts = Vec::new();
    let provider_label = provider_label(account.provider);
    for allowance in &account.allowances {
        let threshold = match allowance.source {
            AllowanceSource::Plan => &connection.plan,
            AllowanceSource::Purchased => &connection.purchased,
        };
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
    if !crossed(allowance.used_percent, threshold.at) {
        return None;
    }
    Some(Alert {
        severity: AlertSeverity::Warning,
        message: format!(
            "{provider_label} {} reached the alert threshold.",
            allowance.label
        ),
    })
}

fn crossed(used_percent: Option<f64>, at: Option<u8>) -> bool {
    match (used_percent, at) {
        (Some(used), Some(threshold)) => used >= f64::from(threshold),
        _ => false,
    }
}

/// Phone `ProviderConnectionId.storageKey` for allowance-scoped rules.
fn connection_storage_key(provider: ProviderKind) -> &'static str {
    match provider {
        ProviderKind::Codex => "openai.plan",
        ProviderKind::OpenAi => "openai.platform",
        ProviderKind::Claude => "anthropic.plan",
        ProviderKind::Cursor => "cursor.plan",
        ProviderKind::Mock => "mock.plan",
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
                today_used_percent: Some(0.0),
                week_used_percent: Some(0.0),
                status: ProviderStatus::Ok,
            },
        }
    }

    fn claude_account(allowance: AllowanceState) -> ProviderSnapshot {
        ProviderSnapshot {
            account_id: "claude".into(),
            provider: ProviderKind::Claude,
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
    fn fires_budget_alert_from_settings() {
        let snapshot = snapshot_with(claude_account(purchased(10.0)), budget(85.0));
        let settings = AlertSettings {
            today: PercentThreshold { at: Some(80) },
            ..AlertSettings::default()
        };
        let alerts = calculate_alerts(&snapshot, &settings);
        assert_eq!(alerts.len(), 1);
        assert_eq!(alerts[0].severity, AlertSeverity::Warning);
        assert!(alerts[0].message.contains("Today"));
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
        let settings = AlertSettings {
            connections,
            ..AlertSettings::default()
        };
        let alerts = calculate_alerts(&snapshot, &settings);
        assert_eq!(alerts.len(), 1);
        assert!(alerts[0].message.contains("Extra usage"));
        assert_eq!(alerts[0].severity, AlertSeverity::Warning);
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
        let settings = AlertSettings {
            connections,
            ..AlertSettings::default()
        };
        assert!(calculate_alerts(&snapshot, &settings).is_empty());
    }
}
