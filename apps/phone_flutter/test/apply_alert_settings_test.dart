import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ward_pulse_phone/dashboard/apply_alert_settings.dart';
import 'package:ward_pulse_phone/dashboard/dashboard_models.dart';
import 'package:ward_pulse_phone/providers/connection_lifecycle.dart';
import 'package:ward_pulse_phone/providers/provider_connection.dart';
import 'package:ward_pulse_phone/settings/alert_threshold_preferences.dart';

void main() {
  final version = CredentialVersion({
    'generation': 'g1',
    'revision': 'r1',
    'epoch': 'e1',
    'identity': 'digest1',
  });
  final outcome = ConnectionReportingOutcome(
    connection: ProviderConnections.openAiPlatform,
    category: ReportingOutcomeCategory.accessDenied,
    source: ReportingOutcomeSource.live,
    credentialVersion: version,
  );
  final versions = {
    ProviderConnections.openAiPlatform.storageKey: version.values,
  };

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
      connectionVersions: versions,
      reportingOutcomes: [outcome],
    );

    final applied = applyUserAlertSettings(
      withAlerts,
      const AlertThresholdPreferences(),
      applyJson: (_, _) => throw StateError('Disabled effect was invoked.'),
    );

    expect(applied.alerts, isEmpty);
    expect(applied.syncIssue, DashboardSyncIssue.rateLimited);
    expect(applied.syncDetails, 'provider floor');
    expect(applied.reportingOutcomes, [outcome]);
    expect(applied.connectionVersions, versions);
    expect(applied.toJson(), {...withAlerts.toJson(), 'alerts': <Object>[]});
    expect(
      applyUserAlertSettings(
        applied,
        const AlertThresholdPreferences(),
        applyJson: (_, _) => throw StateError('Disabled effect was invoked.'),
      ),
      same(applied),
    );
    const ApplyAlertSettings compatible = applyUserAlertSettings;
    expect(
      compatible(applied, const AlertThresholdPreferences()),
      same(applied),
    );
  });

  for (final withSyncIssue in [false, true]) {
    test('enabled effect restores metadata (sync issue: $withSyncIssue)', () {
      final shared = DashboardSnapshot.fromJsonString(
        File(
          '../../fixtures/snapshots/dashboard_today.json',
        ).readAsStringSync(),
      );
      var snapshot = shared
          .withConnectionVersions(versions)
          .withReportingOutcomes([outcome]);
      if (withSyncIssue) {
        snapshot = snapshot.withSyncIssue(
          DashboardSyncIssue.permissionDenied,
          details: 'sanitized reporting issue',
        );
      }
      final settings = const AlertThresholdPreferences().withConnection(
        ProviderConnections.openAiPlatform,
        const ConnectionAlertThresholds(today: AlertPercentThreshold(at: 80)),
      );
      var calls = 0;
      late Map<String, dynamic> transformed;
      final applied = applyUserAlertSettings(
        snapshot,
        settings,
        applyJson: (source, rules) {
          calls++;
          final input = jsonDecode(source) as Map<String, dynamic>;
          // Exact shared data also proves that phone-only fields never reach the effect.
          expect(input, shared.toJson());
          expect(jsonDecode(rules), settings.toJson());
          transformed = {
            ...input,
            'generatedAt': '2026-10-16T12:00:00.000Z',
            'alerts': [
              {'severity': 'warning', 'message': 'configured alert'},
            ],
          };
          return jsonEncode(transformed);
        },
      );

      expect(calls, 1);
      expect(applied.toJson(), transformed);
      expect(applied.reportingOutcomes, [outcome]);
      expect(applied.reportingOutcomes.single.credentialVersion, same(version));
      expect(applied.connectionVersions, versions);
      expect(applied.syncIssue, snapshot.syncIssue);
      expect(applied.syncDetails, snapshot.syncDetails);
    });
  }
}
