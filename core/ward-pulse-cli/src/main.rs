use ward_pulse_core::build_dashboard_snapshot;
use ward_pulse_core::time::DateTimeUtc;
use ward_pulse_providers::mock_provider_snapshot;

fn main() {
    let snapshot = build_dashboard_snapshot(
        DateTimeUtc::from("2026-06-27T18:42:00Z"),
        vec![mock_provider_snapshot("mock-local")],
    );

    println!("WardPulse snapshot");
    println!("status: {:?}", snapshot.overall_status);
    println!("today: {:?}", snapshot.today_total.used_percent);
    println!("week: {:?}", snapshot.week_total.used_percent);
}
