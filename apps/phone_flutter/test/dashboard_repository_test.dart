import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ward_pulse_phone/dashboard/dashboard_load.dart';
import 'package:ward_pulse_phone/dashboard/dashboard_repository.dart';
import 'package:ward_pulse_phone/dashboard/dashboard_models.dart';
import 'package:ward_pulse_phone/providers/connection_lifecycle.dart';
import 'package:ward_pulse_phone/providers/provider_connection.dart';
import 'package:ward_pulse_phone/settings/debug_data_preferences.dart';
import 'package:ward_pulse_phone/sync/provider_sync_logger.dart';

void main() {
  test('freezes reporting metadata and preserves it in snapshot copies', () {
    final stamp = <String, String>{
      'generation': 'g1',
      'revision': 'r1',
      'epoch': 'e1',
      'identity': 'digest1',
    };
    final version = CredentialVersion(stamp);
    final outcome = ConnectionReportingOutcome(
      connection: ProviderConnections.openAiPlatform,
      category: ReportingOutcomeCategory.success,
      source: ReportingOutcomeSource.live,
      freshness: ReportingOutcomeFreshness.current,
      credentialVersion: version,
    );
    final outcomes = [outcome];
    final versions = {ProviderConnections.openAiPlatform.storageKey: stamp};
    final base = DashboardSnapshot.empty(
      generatedAt: DateTime.utc(2026, 10, 16),
    );
    final snapshot = DashboardSnapshot(
      generatedAt: base.generatedAt,
      overallStatus: base.overallStatus,
      accounts: base.accounts,
      todayTotal: base.todayTotal,
      weekTotal: base.weekTotal,
      monthTotal: base.monthTotal,
      alerts: base.alerts,
      watchSummary: base.watchSummary,
      connectionVersions: versions,
      reportingOutcomes: outcomes,
    );
    stamp['revision'] = 'changed';
    versions.clear();
    outcomes.clear();

    expect(version.revision, 'r1');
    expect(() => version.values.clear(), throwsUnsupportedError);
    expect(() => snapshot.reportingOutcomes.clear(), throwsUnsupportedError);
    expect(() => snapshot.connectionVersions.clear(), throwsUnsupportedError);
    expect(
      () => snapshot.connectionVersions.values.single.clear(),
      throwsUnsupportedError,
    );
    for (final copy in [
      snapshot,
      snapshot.withStaleStatus(syncIssue: DashboardSyncIssue.rateLimited),
      snapshot.withSyncIssue(DashboardSyncIssue.providerUnavailable),
      snapshot.withConnectionVersions(snapshot.connectionVersions),
      snapshot.withReportingOutcomes(snapshot.reportingOutcomes),
    ]) {
      expect(copy.reportingOutcomes, [outcome]);
      expect(copy.reportingOutcomes.single.credentialVersion, same(version));
      expect(copy.connectionVersions.values.single, version.values);
      expect(copy.generatedAt, snapshot.generatedAt);
    }
    final shared = snapshot.toJson();
    expect(
      shared.keys,
      unorderedEquals([
        'generatedAt',
        'overallStatus',
        'accounts',
        'todayTotal',
        'weekTotal',
        'monthTotal',
        'alerts',
        'watchSummary',
      ]),
    );
    final roundTrip = DashboardSnapshot.fromJsonString(snapshot.toJsonString());
    expect(roundTrip.reportingOutcomes, isEmpty);
    expect(roundTrip.connectionVersions, isEmpty);
    expect(roundTrip.toJson(), shared);
  });

  test(
    'captures simultaneous first failures without inventing accounts',
    () async {
      final outcomes = [
        for (final connection in [
          ProviderConnections.openAiPlatform,
          ProviderConnections.anthropicPlatform,
          ProviderConnections.cursorPlatform,
        ])
          ConnectionReportingOutcome(
            connection: connection,
            category: ReportingOutcomeCategory.authenticationRejected,
            source: ReportingOutcomeSource.live,
            credentialVersion: CredentialVersion({
              'generation': connection.storageKey,
              'revision': 'r1',
              'epoch': 'e1',
              'identity': 'digest1',
            }),
          ),
      ];
      final retained = List.of(outcomes);
      final failure = DashboardLoadException.withOutcomes(
        issue: DashboardSyncIssue.authentication,
        details: 'sanitized failure',
        reportingOutcomes: outcomes,
      );
      outcomes.clear();
      final captured = await CapturedDashboardLoad.capture(
        () async => throw failure,
      );
      expect(captured.reportingOutcomes, retained);
      expect(
        captured.reportingOutcomes.map((result) => result.connectionLabel),
        [
          'OpenAI · Platform reporting',
          'Anthropic · Organization reporting',
          'Cursor · Team Admin API',
        ],
      );
      expect(
        captured.reportingOutcomes.map((result) => result.connection),
        isNot(contains(ProviderConnections.codexPlan)),
      );
      expect(() => failure.reportingOutcomes.clear(), throwsUnsupportedError);
      expect(() => captured.value, throwsA(same(failure)));
      expect(
        mapReportingError(failure, const NullProviderSyncLogger()),
        same(failure),
      );
      expect(failure.issue, DashboardSyncIssue.authentication);
      expect(failure.details, 'sanitized failure');
      expect(const DashboardLoadException().reportingOutcomes, isEmpty);

      final snapshot = DashboardSnapshot.empty().withReportingOutcomes(
        retained,
      );
      final success = await CapturedDashboardLoad.capture(() async => snapshot);
      expect(success.value, same(snapshot));
      expect(success.value.accounts, isEmpty);
      expect(success.reportingOutcomes, retained);
    },
  );

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

  test(
    'Mock observed loads neither query live reporting nor forward live proof',
    () async {
      final preferences = _MemoryDebugDataPreferenceStore()..value = true;
      var liveCalls = 0;
      final live = _ObservedRepository(() {
        liveCalls++;
      });
      final repository = DebugDashboardRepository(
        live: live,
        preferences: preferences,
        mock: ValueDashboardRepository(DashboardSnapshot.empty()),
      );
      final updates = <ConnectionReportingUpdate>[];
      final result = await repository.loadObserved(updates.add);
      expect(liveCalls, 0);
      expect(updates, isEmpty);
      expect(result.reportingOutcomes, isEmpty);
    },
  );

  test('demo repository reshuffles by seed', () async {
    var loads = 0;
    final repository = DemoDashboardRepository(
      loadDebugDashboardJson: (seed) {
        loads += 1;
        final json =
            jsonDecode(
                  File(
                    '../../fixtures/snapshots/dashboard_today.json',
                  ).readAsStringSync(),
                )
                as Map<String, dynamic>;
        (json['accounts'] as List).first['accountId'] = 'seed-$seed';
        return jsonEncode(json);
      },
      seedForLoad: () => 42,
    );

    final first = await repository.load();
    final second = await repository.load();
    expect(first.accounts.single.accountId, 'seed-42');
    expect(identical(first, second), isTrue);
    expect(loads, 1);

    repository.invalidate();
    final third = await repository.load();
    expect(third.accounts.single.accountId, 'seed-42');
    expect(loads, 2);
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

final class _ObservedRepository extends DashboardRepository {
  const _ObservedRepository(this.onLoad);
  final void Function() onLoad;
  @override
  Future<DashboardSnapshot> load() async {
    onLoad();
    return DashboardSnapshot.empty();
  }

  @override
  Future<DashboardSnapshot> loadObserved(ReportingObserver observer) => load();
}
