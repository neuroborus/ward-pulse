import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ward_pulse_phone/dashboard/dashboard_models.dart';
import 'package:ward_pulse_phone/sync/watch_sync_service.dart';
import 'package:ward_pulse_phone/settings/consumption_display_preferences.dart';

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
    );

    expect(jsonDecode(payload.encode()), expected);
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

  test('sends only selected allowance sources', () {
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
                const ConsumptionDisplayPreferences(
                  plan: false,
                  purchased: true,
                ),
              ).encode(),
            )
            as Map<String, dynamic>;

    expect(payload['schemaVersion'], 3);
    expect(payload['dataMode'], 'mock');
    expect((payload['allowances'] as List), hasLength(1));
    expect((payload['allowances'] as List).first['source'], 'purchased');
  });

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
              ).encode(),
            )
            as Map<String, dynamic>;

    expect((payload['allowances'] as List).first['unlimited'], isTrue);
  });
}
