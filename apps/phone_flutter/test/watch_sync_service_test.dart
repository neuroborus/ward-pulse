import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ward_pulse_phone/dashboard/dashboard_models.dart';
import 'package:ward_pulse_phone/sync/watch_sync_service.dart';

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

    final payload = WatchDashboardSummaryPayload.fromSnapshot(dashboard);

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
              WatchDashboardSummaryPayload.fromSnapshot(dashboard).encode(),
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
}
