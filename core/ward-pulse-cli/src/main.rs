use std::error::Error;
use std::io::{self, Write};

use ward_pulse_core::build_dashboard_snapshot;
use ward_pulse_core::model::DashboardSnapshot;
use ward_pulse_providers::mock::{
    mock_provider_snapshot_from_usage_fixture, MockUsageFixtureError,
};

const MOCK_USAGE_TODAY_FIXTURE: &str =
    include_str!("../../../fixtures/providers/mock/usage_today.json");

fn main() -> Result<(), Box<dyn Error>> {
    let mut stdout = io::stdout().lock();
    let snapshot = mock_dashboard_snapshot()?;

    serde_json::to_writer_pretty(&mut stdout, &snapshot)?;
    writeln!(stdout)?;

    Ok(())
}

fn mock_dashboard_snapshot() -> Result<DashboardSnapshot, MockUsageFixtureError> {
    let fixture =
        mock_provider_snapshot_from_usage_fixture("mock-local", MOCK_USAGE_TODAY_FIXTURE)?;

    Ok(build_dashboard_snapshot(
        fixture.generated_at,
        vec![fixture.provider_snapshot],
    ))
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::collections::HashMap;
    use ward_pulse_core::time::DateTimeUtc;

    use ward_pulse_core::model::connection;
    use ward_pulse_core::{
        apply_alert_settings, AlertSettings, ConnectionAlertThresholds, PercentThreshold,
    };
    use ward_pulse_providers::mock::mock_provider_budget_warning_snapshot;

    #[test]
    fn mock_dashboard_matches_golden_fixture() {
        assert_snapshot_matches_fixture(
            mock_dashboard_snapshot().expect("build mock dashboard snapshot"),
            include_str!("../../../fixtures/snapshots/dashboard_today.json"),
        );
    }

    #[test]
    fn mock_alert_dashboard_extends_golden_fixture_with_typed_condition() {
        let snapshot = build_dashboard_snapshot(
            DateTimeUtc::from("2026-06-27T18:42:00Z"),
            vec![mock_provider_budget_warning_snapshot("mock-local")],
        );
        let settings = AlertSettings {
            connections: HashMap::from([(
                connection::MOCK_PLAN.to_string(),
                ConnectionAlertThresholds {
                    today: PercentThreshold { at: Some(80) },
                    ..ConnectionAlertThresholds::default()
                },
            )]),
        };

        let actual = serde_json::to_value(apply_alert_settings(snapshot, &settings))
            .expect("serialize alert snapshot");
        let mut expected: serde_json::Value = serde_json::from_str(include_str!(
            "../../../fixtures/snapshots/dashboard_alerts.json"
        ))
        .expect("parse legacy alert snapshot fixture");
        expected["alertConditions"] = serde_json::json!([{
            "key": {
                "provider": "mock",
                "accountId": "mock-local",
                "connection": "mock.plan",
                "target": {"kind": "budget", "period": "today"}
            },
            "state": "crossed",
            "alert": {
                "severity": "warning",
                "message": "Mock budget for today reached the alert threshold."
            }
        }]);

        assert_eq!(actual, expected);
    }

    fn assert_snapshot_matches_fixture(snapshot: DashboardSnapshot, fixture: &str) {
        let actual = serde_json::to_value(snapshot).expect("serialize snapshot");
        let expected: serde_json::Value =
            serde_json::from_str(fixture).expect("parse golden snapshot fixture");

        assert_eq!(actual, expected);
        assert!(actual.get("todayTotal").is_some());
        assert!(actual.get("weekTotal").is_some());
        assert!(actual.get("monthTotal").is_some());
        assert!(actual.get("watchSummary").is_some());
        assert!(actual.pointer("/accounts/0/credits/0").is_some());
    }
}
