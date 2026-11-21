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
    final mockSeeds = <int>[];
    final preferences = _MemoryDebugDataPreferenceStore();
    final repository = DebugDashboardRepository(
      live: ValueDashboardRepository(live),
      mock: DemoDashboardRepository(
        debugSeed: '42',
        loadDebugDashboardJson: (seed) {
          mockSeeds.add(seed);
          return fixture;
        },
      ),
      preferences: preferences,
    );

    expect(await repository.load(), same(live));
    repository.invalidate();
    expect(await repository.loadObserved((_) {}), same(live));
    expect(mockSeeds, isEmpty);

    preferences.value = true;

    expect(await repository.load(), isNot(same(live)));
    expect(mockSeeds, [42]);

    preferences.value = false;
    expect(await repository.loadObserved((_) {}), same(live));
    expect(mockSeeds, [42]);
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

  test('debug demo advances loaded scenarios and restarts', () async {
    final fixture =
        File(
          '../../fixtures/snapshots/dashboard_today.json',
        ).readAsStringSync();
    final seeds = <int>[];
    DemoDashboardRepository createRepository() => DemoDashboardRepository(
      debugSeed: '0042',
      loadDebugDashboardJson: (seed) {
        seeds.add(seed);
        return fixture;
      },
      seedForLoad: () => throw StateError('unexpected random seed'),
    );
    final repository = createRepository();

    repository.invalidate();
    repository.invalidate();

    final first = await repository.load();
    final second = await repository.load();
    expect(second, same(first));
    expect(seeds, [42]);

    repository.invalidate();
    repository.invalidate();
    final third = await repository.load();
    expect(third, isNot(same(first)));
    expect(seeds, [42, 43]);

    repository.invalidate();
    await repository.load();
    final restarted = await createRepository().load();
    expect(restarted.toJson(), first.toJson());
    expect(seeds, [42, 43, 44, 42]);
  });

  test('debug demo seeds include zero and wrap the maximum to zero', () async {
    final fixture =
        File(
          '../../fixtures/snapshots/dashboard_today.json',
        ).readAsStringSync();
    for (final startingSeed in [0, 9223372036854775807]) {
      final seeds = <int>[];
      final repository = DemoDashboardRepository(
        debugSeed: '$startingSeed',
        loadDebugDashboardJson: (seed) {
          seeds.add(seed);
          return fixture;
        },
      );

      await repository.load();
      repository.invalidate();
      repository.invalidate();
      await repository.load();
      expect(seeds, [startingSeed, startingSeed == 0 ? 1 : 0]);
    }
  });

  test(
    'dated demo forwards a fixed anchor through cached seed advancement',
    () async {
      final fixture =
          File(
            '../../fixtures/snapshots/dashboard_today.json',
          ).readAsStringSync();
      final requests = <(int, String)>[];
      DemoDashboardRepository create() => DemoDashboardRepository(
        debugSeed: '280',
        debugAnchor: '2026-11-02T12:00:00Z',
        loadDebugDashboardJson:
            (_) => throw StateError('unexpected seed-only load'),
        loadDatedDebugDashboardJson: (seed, anchor) {
          requests.add((seed, anchor));
          return fixture;
        },
      );
      final repository = create();
      repository.invalidate();
      final first = await repository.load();
      expect(await repository.load(), same(first));
      repository.invalidate();
      repository.invalidate();
      expect(await repository.load(), isNot(same(first)));
      expect((await create().load()).toJson(), first.toJson());
      expect(requests, [
        (280, '2026-11-02T12:00:00Z'),
        (281, '2026-11-02T12:00:00Z'),
        (280, '2026-11-02T12:00:00Z'),
      ]);
    },
  );

  test(
    'invalid explicit demo anchors fail without caching or fallback',
    () async {
      for (final anchor in ['', 'invalid']) {
        final seeds = <int>[];
        var fallbacks = 0;
        final repository = DemoDashboardRepository(
          debugSeed: '280',
          debugAnchor: anchor,
          loadDebugDashboardJson: (_) {
            fallbacks += 1;
            throw StateError('unexpected fallback');
          },
          loadDatedDebugDashboardJson: (seed, forwarded) {
            expect(forwarded, anchor);
            seeds.add(seed);
            throw const FormatException('invalid explicit anchor');
          },
        );
        await expectLater(
          repository.load(),
          throwsA(isA<DashboardLoadException>()),
        );
        repository.invalidate();
        await expectLater(
          repository.load(),
          throwsA(isA<DashboardLoadException>()),
        );
        expect(seeds, [280, 280]);
        expect(fallbacks, 0);
      }
    },
  );

  test('absent or invalid demo seeds retain the fallback source', () async {
    final fixture =
        File(
          '../../fixtures/snapshots/dashboard_today.json',
        ).readAsStringSync();
    for (final debugSeed in [
      null,
      '',
      '-1',
      '+1',
      ' 1',
      '1 ',
      '1\n',
      '1.0',
      '1e3',
      '0x33',
      'invalid',
      '9223372036854775808',
    ]) {
      final seeds = <int>[];
      var fallbackSeed = 100;
      final repository = DemoDashboardRepository(
        debugSeed: debugSeed,
        seedForLoad: () => fallbackSeed += 7,
        loadDebugDashboardJson: (seed) {
          seeds.add(seed);
          return fixture;
        },
      );

      await repository.load();
      repository.invalidate();
      await repository.load();
      expect(seeds, [107, 114], reason: jsonEncode(debugSeed));
    }
  });

  test('non-debug demo builds ignore a valid configured seed', () async {
    final fixture =
        File(
          '../../fixtures/snapshots/dashboard_today.json',
        ).readAsStringSync();
    final seeds = <int>[];
    var fallbackSeed = 100;
    final repository = DemoDashboardRepository(
      debugMode: false,
      debugSeed: '42',
      debugAnchor: 'invalid',
      loadDatedDebugDashboardJson: (_, _) => throw StateError('release anchor'),
      seedForLoad: () => fallbackSeed += 7,
      loadDebugDashboardJson: (seed) {
        seeds.add(seed);
        return fixture;
      },
    );

    await repository.load();
    repository.invalidate();
    await repository.load();
    expect(seeds, [107, 114]);
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
