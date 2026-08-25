import 'package:flutter_test/flutter_test.dart';
import 'package:ward_pulse_phone/dashboard/apply_alert_settings.dart';
import 'package:ward_pulse_phone/dashboard/dashboard_models.dart';
import 'package:ward_pulse_phone/settings/alert_threshold_preferences.dart';

void main() {
  test('default-off settings clear leftover alerts without FFI', () {
    final snapshot = DashboardSnapshot.empty().withSyncIssue(
      DashboardSyncIssue.rateLimited,
      details: 'provider floor',
    );
    final withAlerts = DashboardSnapshot(
      generatedAt: snapshot.generatedAt,
      overallStatus: snapshot.overallStatus,
      accounts: snapshot.accounts,
      todayTotal: snapshot.todayTotal,
      weekTotal: snapshot.weekTotal,
      monthTotal: snapshot.monthTotal,
      alerts: const [
        AlertSummary(severity: 'warning', message: 'stale auto-fire'),
      ],
      watchSummary: snapshot.watchSummary,
      syncIssue: snapshot.syncIssue,
      syncDetails: snapshot.syncDetails,
    );

    final applied = applyUserAlertSettings(
      withAlerts,
      const AlertThresholdPreferences(),
    );

    expect(applied.alerts, isEmpty);
    expect(applied.syncIssue, DashboardSyncIssue.rateLimited);
    expect(applied.syncDetails, 'provider floor');
  });
}
