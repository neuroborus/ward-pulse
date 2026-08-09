import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ward_pulse_phone/dashboard/dashboard_models.dart';
import 'package:ward_pulse_phone/sync/watch_sync_service.dart';
import 'package:ward_pulse_phone/settings/consumption_display_preferences.dart';
import 'package:ward_pulse_phone/settings/watch_ring_preferences.dart';
import 'package:ward_pulse_phone/sync/manual_refresh_window.dart';

void main() {
  test('builds the sanitized watch summary fixture', () {
    final dashboard = DashboardSnapshot.fromJsonString(
      File('../../fixtures/snapshots/dashboard_today.json').readAsStringSync(),
    );
    final expected = jsonDecode(
      File(
        '../../fixtures/snapshots/watch_dashboard_summary.json',
      ).readAsStringSync(),
    );

    final payload = WatchDashboardSummaryPayload.fromSnapshot(
      dashboard,
      const ConsumptionDisplayPreferences(),
      const WatchRingPreferences(),
      // Match fixture: PollCadence floor already elapsed.
      clock: dashboard.generatedAt.add(ManualRefreshWindow.floor),
    );

    expect(jsonDecode(payload.encode()), expected);
  });

  test('sends budget rings keyed by connection', () {
    final json =
        jsonDecode(
              File(
                '../../fixtures/snapshots/dashboard_today.json',
              ).readAsStringSync(),
            )
            as Map<String, dynamic>;
    final account = (json['accounts'] as List).first as Map<String, dynamic>;
    // Mock accounts hold no rings, so only the connection differs here.
    account['provider'] = 'claude';
    account['connection'] = 'anthropic.platform';

    final payload =
        jsonDecode(
              WatchDashboardSummaryPayload.fromSnapshot(
                DashboardSnapshot.fromJson(json),
                const ConsumptionDisplayPreferences(),
                const WatchRingPreferences(),
              ).encode(),
            )
            as Map<String, dynamic>;

    final rings = payload['rings'] as List;
    expect(rings.map((ring) => ring['id']), [
      'budget.anthropic.platform.week',
      'budget.anthropic.platform.month',
      'budget.anthropic.platform.today',
    ]);
    // Wear prefixes a family onto a bare pool name; a budget ring arrives named,
    // so Glance shows the connection (`glance-legend-budget.svg`).
    expect(rings.first['label'], 'Anthropic platform · Week');
    // Money travels as structure, currency included: the face strip spells the
    // symbol itself instead of assuming every connection bills in dollars.
    expect(rings.first['spent'], {'minorUnits': 7130, 'currency': 'USD'});
    expect(rings.first['limit'], {'minorUnits': 25000, 'currency': 'USD'});
  });

  test('marks the previous watch summary stale after a sync failure', () {
    final dashboard =
        DashboardSnapshot.fromJsonString(
          File(
            '../../fixtures/snapshots/dashboard_today.json',
          ).readAsStringSync(),
        ).withStaleStatus();

    final payload =
        jsonDecode(
              WatchDashboardSummaryPayload.fromSnapshot(
                dashboard,
                const ConsumptionDisplayPreferences(),
                const WatchRingPreferences(),
              ).encode(),
            )
            as Map<String, dynamic>;

    expect(payload['overallStatus'], 'stale');
    expect(payload['isStale'], isTrue);
    expect(
      (payload['providers'] as List<dynamic>).map(
        (provider) => (provider as Map<String, dynamic>)['status'],
      ),
      everyElement('stale'),
    );
  });

  test('sends all reported allowance sources', () {
    final json =
        jsonDecode(
              File(
                '../../fixtures/snapshots/dashboard_today.json',
              ).readAsStringSync(),
            )
            as Map<String, dynamic>;
    final account = (json['accounts'] as List).first as Map<String, dynamic>;
    account['allowances'] = [
      {
        'id': 'plan',
        'source': 'plan',
        'label': 'Weekly plan',
        'usedPercent': 80,
        'used': null,
        'limit': null,
        'remaining': null,
        'windowMinutes': 10080,
        'resetsAt': null,
        'status': 'warning',
      },
      {
        'id': 'purchased',
        'source': 'purchased',
        'label': 'Purchased credits',
        'usedPercent': null,
        'used': null,
        'limit': null,
        'remaining': {'value': '12.5', 'unit': 'credits'},
        'unlimited': false,
        'windowMinutes': null,
        'resetsAt': null,
        'status': 'ok',
      },
    ];

    final payload =
        jsonDecode(
              WatchDashboardSummaryPayload.fromSnapshot(
                DashboardSnapshot.fromJson(json),
                // Display prefs no longer filter surfaces.
                const ConsumptionDisplayPreferences(plan: false),
                const WatchRingPreferences(),
              ).encode(),
            )
            as Map<String, dynamic>;

    expect(payload['schemaVersion'], 8);
    expect(payload['creditsGlance'], {
      'text': '12.5',
      'label': 'Credits left',
      'provider': 'mock',
    });
    expect(payload['dataMode'], 'mock');
    final allowances = payload['allowances'] as List;
    expect(allowances, hasLength(2));
    expect(allowances.map((row) => row['source']), ['plan', 'purchased']);
    expect(allowances.last['label'], 'Mock · Purchased credits');
  });

  test(
    'marks multi-provider debug dashboards as mock dataMode when forced',
    () {
      final json =
          jsonDecode(
                File(
                  '../../fixtures/snapshots/dashboard_today.json',
                ).readAsStringSync(),
              )
              as Map<String, dynamic>;
      (json['accounts'] as List).first['provider'] = 'cursor';

      final payload =
          jsonDecode(
                WatchDashboardSummaryPayload.fromSnapshot(
                  DashboardSnapshot.fromJson(json),
                  const ConsumptionDisplayPreferences(),
                  const WatchRingPreferences(),
                  mockDataMode: true,
                ).encode(),
              )
              as Map<String, dynamic>;

      expect(payload['dataMode'], 'mock');
    },
  );

  test('sends unlimited purchased usage explicitly', () {
    final json =
        jsonDecode(
              File(
                '../../fixtures/snapshots/dashboard_today.json',
              ).readAsStringSync(),
            )
            as Map<String, dynamic>;
    final account = (json['accounts'] as List).first as Map<String, dynamic>;
    account['allowances'] = [
      {
        'id': 'purchased',
        'source': 'purchased',
        'label': 'Purchased credits',
        'usedPercent': null,
        'used': null,
        'limit': null,
        'remaining': null,
        'unlimited': true,
        'windowMinutes': null,
        'resetsAt': null,
        'status': 'ok',
      },
    ];

    final payload =
        jsonDecode(
              WatchDashboardSummaryPayload.fromSnapshot(
                DashboardSnapshot.fromJson(json),
                const ConsumptionDisplayPreferences(purchased: true),
                const WatchRingPreferences(),
              ).encode(),
            )
            as Map<String, dynamic>;

    expect((payload['allowances'] as List).first['unlimited'], isTrue);
  });

  test('embeds PollCadence floor window for Wear refresh chrome', () {
    final dashboard = DashboardSnapshot.fromJsonString(
      File('../../fixtures/snapshots/dashboard_today.json').readAsStringSync(),
    );
    final lastSync = dashboard.generatedAt;
    final payload =
        jsonDecode(
              WatchDashboardSummaryPayload.fromSnapshot(
                dashboard,
                const ConsumptionDisplayPreferences(),
                const WatchRingPreferences(),
                manualRefreshAnchorAt: lastSync,
                clock: lastSync.add(const Duration(minutes: 2)),
              ).encode(),
            )
            as Map<String, dynamic>;

    expect(payload['manualRefreshAllowed'], isFalse);
    expect(
      payload['manualRefreshAvailableAt'],
      lastSync.add(ManualRefreshWindow.floor).toUtc().toIso8601String(),
    );
  });
}
