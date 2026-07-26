import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ward_pulse_phone/dashboard/dashboard_repository.dart';
import 'package:ward_pulse_phone/dashboard/dashboard_models.dart';
import 'package:ward_pulse_phone/settings/debug_data_preferences.dart';

void main() {
  test('loads a Rust-produced dashboard JSON document', () async {
    final fixture =
        File(
          '../../fixtures/snapshots/dashboard_today.json',
        ).readAsStringSync();
    final repository = RustDashboardRepository(
      loadDashboardJson: () => fixture,
    );

    final snapshot = await repository.load();

    expect(snapshot.accounts.single.accountId, 'mock-local');
  });

  test('maps bridge failures to a safe dashboard error', () {
    final repository = RustDashboardRepository(
      loadDashboardJson: () => throw StateError('native details'),
    );

    expect(
      repository.load(),
      throwsA(
        isA<DashboardLoadException>().having(
          (error) => error.issue,
          'issue',
          DashboardSyncIssue.dashboardUnavailable,
        ),
      ),
    );
  });

  test('uses mock data only when the debug preference is enabled', () async {
    final fixture =
        File(
          '../../fixtures/snapshots/dashboard_today.json',
        ).readAsStringSync();
    final live = DashboardSnapshot.fromJsonString(fixture);
    final mock = DashboardSnapshot.fromJsonString(fixture);
    final preferences = _MemoryDebugDataPreferenceStore();
    final repository = DebugDashboardRepository(
      live: ValueDashboardRepository(live),
      mock: ValueDashboardRepository(mock),
      preferences: preferences,
    );

    expect(await repository.load(), same(live));

    preferences.value = true;

    expect(await repository.load(), same(mock));
  });

  test('does not double-count cached input tokens', () {
    final bucket = UsageBucket(
      startAt: DateTime.utc(2026, 7, 19),
      endAt: DateTime.utc(2026, 7, 20),
      cost: null,
      inputTokens: 1000,
      outputTokens: 200,
      cachedTokens: 300,
      requests: 1,
      model: 'gpt-example',
    );

    expect(bucket.totalTokens, 1200);
  });
}

final class _MemoryDebugDataPreferenceStore
    implements DebugDataPreferenceStore {
  bool value = false;

  @override
  Future<bool> readMockDataEnabled() async => value;

  @override
  Future<void> writeMockDataEnabled(bool value) async {
    this.value = value;
  }
}
