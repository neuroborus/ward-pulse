use std::error::Error;
use std::io::{self, Write};

use ward_pulse_core::build_dashboard_snapshot;
use ward_pulse_core::model::DashboardSnapshot;
use ward_pulse_core::time::DateTimeUtc;
use ward_pulse_providers::mock_provider_snapshot;

fn main() -> Result<(), Box<dyn Error>> {
    let mut stdout = io::stdout().lock();

    serde_json::to_writer_pretty(&mut stdout, &mock_dashboard_snapshot())?;
    writeln!(stdout)?;

    Ok(())
}

fn mock_dashboard_snapshot() -> DashboardSnapshot {
    build_dashboard_snapshot(
        DateTimeUtc::from("2026-06-27T18:42:00Z"),
        vec![mock_provider_snapshot("mock-local")],
    )
}

#[cfg(test)]
mod tests {
    use super::*;
    use ward_pulse_providers::mock::mock_provider_budget_warning_snapshot;

    #[test]
    fn mock_dashboard_matches_golden_fixture() {
        assert_snapshot_matches_fixture(
            mock_dashboard_snapshot(),
            include_str!("../../../fixtures/snapshots/dashboard_today.json"),
        );
    }

    #[test]
    fn mock_alert_dashboard_matches_golden_fixture() {
        let snapshot = build_dashboard_snapshot(
            DateTimeUtc::from("2026-06-27T18:42:00Z"),
            vec![mock_provider_budget_warning_snapshot("mock-local")],
        );

        assert_snapshot_matches_fixture(
            snapshot,
            include_str!("../../../fixtures/snapshots/dashboard_alerts.json"),
        );
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
    }
}
