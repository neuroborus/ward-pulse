import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ward_pulse_phone/dashboard/apply_alert_settings.dart';
import 'package:ward_pulse_phone/dashboard/dashboard_models.dart';
import 'package:ward_pulse_phone/providers/connection_lifecycle.dart';
import 'package:ward_pulse_phone/providers/provider_connection.dart';
import 'package:ward_pulse_phone/settings/alert_threshold_preferences.dart';

void main() {
  const condition = AlertCondition.crossed(
    key: AlertConditionKey(
      provider: 'codex',
      accountId: 'account-a',
      connection: 'openai.plan',
      target: AllowanceAlertTarget(
        source: AllowanceSource.plan,
        id: 'window-a',
      ),
    ),
    alert: AlertSummary(severity: 'warning', message: 'configured alert'),
  );
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

  for (final includeAlerts in [false, true]) {
    test(
      'disabled rules clear observations without FFI (alerts: $includeAlerts)',
      () {
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
          alerts: includeAlerts ? [condition.alert!] : const [],
          alertConditions: const [condition],
          watchSummary: snapshot.watchSummary,
          syncIssue: snapshot.syncIssue,
          syncDetails: snapshot.syncDetails,
          connectionVersions: versions,
          reportingOutcomes: [outcome],
        );

        final applied = applyUserAlertSettings(
          withAlerts,
          const AlertThresholdPreferences(
            connections: {
              'openai.plan': ConnectionAlertThresholds(
                planWindows: {'unavailable': AlertPercentThreshold()},
              ),
            },
          ),
          applyJson: (_, _) => throw StateError('Disabled effect was invoked.'),
        );

        expect(applied.alerts, isEmpty);
        expect(applied.alertConditions, isEmpty);
        expect(applied.syncIssue, DashboardSyncIssue.rateLimited);
        expect(applied.syncDetails, 'provider floor');
        expect(applied.reportingOutcomes, [outcome]);
        expect(applied.connectionVersions, versions);
        final expected = withAlerts.toJson()..remove('alertConditions');
        expected['alerts'] = <Object>[];
        expect(applied.toJson(), expected);
        expect(
          applyUserAlertSettings(
            applied,
            const AlertThresholdPreferences(),
            applyJson:
                (_, _) => throw StateError('Disabled effect was invoked.'),
          ),
          same(applied),
        );
        const ApplyAlertSettings compatible = applyUserAlertSettings;
        expect(
          compatible(withAlerts, const AlertThresholdPreferences()).alerts,
          isEmpty,
        );
        expect(
          compatible(applied, const AlertThresholdPreferences()),
          same(applied),
        );
      },
    );
  }

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
        const ConnectionAlertThresholds(
          planWindows: {
            'window-a': AlertPercentThreshold(at: 0),
            'window-b': AlertPercentThreshold(at: 100),
            'window-c': AlertPercentThreshold(at: 83),
            'unavailable': AlertPercentThreshold(),
          },
        ),
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
            'alertConditions': [condition.toJson()],
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
