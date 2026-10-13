import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ward_pulse_phone/dashboard/dashboard_models.dart';
import 'package:ward_pulse_phone/dashboard/dashboard_repository.dart';
import 'package:ward_pulse_phone/dashboard/merging_connection_repository.dart';
import 'package:ward_pulse_phone/providers/provider_connection.dart';
import 'package:ward_pulse_phone/settings/watch_ring_preferences.dart';
import 'package:ward_pulse_phone/sync/provider_sync_logger.dart';
import 'package:ward_pulse_phone/sync/watch_sync_service.dart';

void main() {
  final snapshot = DashboardSnapshot.fromJsonString(
    File('../../fixtures/snapshots/dashboard_today.json').readAsStringSync(),
  );

  DashboardLoadException mapError(Object error) =>
      const DashboardLoadException(details: 'mapped');

  test('passes through to the fallback without a stored credential', () async {
    final repository = MergingConnectionRepository(
      fallback: ValueDashboardRepository(snapshot),
      logger: const NullProviderSyncLogger(),
      mapError: mapError,
      normalizeReport: (_) => throw StateError('must not normalize'),
      loadReport: () async => null,
    );

    expect(await repository.load(), same(snapshot));
  });

  test('normalizes a fetched report when no other account is live', () async {
    String? receivedReport;
    final repository = MergingConnectionRepository(
      fallback: ValueDashboardRepository(snapshot),
      logger: const NullProviderSyncLogger(),
      mapError: mapError,
      loadReport: () async => '{"sanitized":true}',
      normalizeReport: (value) {
        receivedReport = value;
        return File(
          '../../fixtures/snapshots/dashboard_today.json',
        ).readAsStringSync();
      },
    );

    expect((await repository.load()).primaryAccount?.provider, 'mock');
    expect(receivedReport, '{"sanitized":true}');
  });

  test('merges the connection snapshot with a live fallback', () async {
    final fallbackJson = snapshot.toJson();
    (fallbackJson['accounts'] as List).first['provider'] = 'openai';
    final fallbackSnapshot = DashboardSnapshot.fromJson(fallbackJson);
    final connectionJson = snapshot.toJson();
    (connectionJson['accounts'] as List).first['provider'] = 'anthropic';

    final repository = MergingConnectionRepository(
      fallback: ValueDashboardRepository(fallbackSnapshot),
      logger: const NullProviderSyncLogger(),
      mapError: mapError,
      loadReport: () async => '{"sanitized":true}',
      normalizeReport: (_) => jsonEncode(connectionJson),
      mergeSnapshots: (values) {
        final decoded =
            values
                .map((value) => jsonDecode(value) as Map<String, dynamic>)
                .toList();
        final merged = Map<String, dynamic>.from(decoded.first);
        merged['accounts'] = [
          ...(decoded.first['accounts'] as List),
          ...(decoded.last['accounts'] as List),
        ];
        return jsonEncode(merged);
      },
    );

    final result = await repository.load();

    expect(result.accounts.map((account) => account.provider), [
      'openai',
      'anthropic',
    ]);
  });

  test(
    'keeps the fallback live and surfaces the mapped issue on failure',
    () async {
      final fallbackJson = snapshot.toJson();
      (fallbackJson['accounts'] as List).first['provider'] = 'openai';
      final repository = MergingConnectionRepository(
        fallback: ValueDashboardRepository(
          DashboardSnapshot.fromJson(fallbackJson),
        ),
        logger: const NullProviderSyncLogger(),
        mapError:
            (_) => const DashboardLoadException(
              issue: DashboardSyncIssue.authentication,
              details: 'Usage · HTTP 401',
            ),
        loadReport: () => throw StateError('token rejected'),
        normalizeReport: (_) => throw StateError('must not normalize'),
      );

      final result = await repository.load();

      expect(result.primaryAccount?.provider, 'openai');
      expect(result.syncIssue, DashboardSyncIssue.authentication);
      expect(result.syncDetails, 'Usage · HTTP 401');
    },
  );

  test(
    'falls back to the last successful snapshot when nothing else is live',
    () async {
      final connectionJson = snapshot.toJson();
      (connectionJson['accounts'] as List).first['provider'] = 'anthropic';
      var loadReport = () async => '{"sanitized":true}';
      final repository = MergingConnectionRepository(
        fallback: const NoProvidersDashboardRepository(),
        logger: const NullProviderSyncLogger(),
        mapError:
            (_) => const DashboardLoadException(
              issue: DashboardSyncIssue.rateLimited,
            ),
        loadReport: () => loadReport(),
        normalizeReport: (_) => jsonEncode(connectionJson),
      );

      final first = await repository.load();
      expect(first.primaryAccount?.provider, 'anthropic');

      loadReport = () => throw StateError('rate limited');
      final second = await repository.load();

      expect(second.overallStatus, ProviderStatus.stale);
      expect(second.syncIssue, DashboardSyncIssue.rateLimited);
      expect(second.primaryAccount?.provider, 'anthropic');
    },
  );

  test(
    'throws when a failure has no live fallback and no cached snapshot',
    () async {
      const failure = DashboardLoadException(
        issue: DashboardSyncIssue.dashboardUnavailable,
      );
      final repository = MergingConnectionRepository(
        fallback: const NoProvidersDashboardRepository(),
        logger: const NullProviderSyncLogger(),
        mapError: (_) => failure,
        loadReport: () => throw StateError('network error'),
        normalizeReport: (_) => throw StateError('must not normalize'),
      );

      await expectLater(repository.load(), throwsA(same(failure)));
    },
  );

  test('recovers using an early fallback failure while loading', () async {
    final report = Completer<String?>();
    const failure = DashboardLoadException(
      details: 'Platform reporting failed',
    );
    final repository = MergingConnectionRepository(
      fallback: const _FailingDashboardRepository(failure),
      logger: const NullProviderSyncLogger(),
      mapError: mapError,
      loadReport: () => report.future,
      normalizeReport: (_) => throw StateError('must not normalize'),
    );

    final load = repository.load();
    await Future<void>.delayed(Duration.zero);
    report.complete(null);

    await expectLater(load, throwsA(same(failure)));
  });

  group('per-connection recovery', () {
    final firstAt = DateTime.utc(2026, 10, 13, 10);
    final nextAt = firstAt.add(const Duration(minutes: 5));
    final recoveredAt = nextAt.add(const Duration(minutes: 5));
    late _MutableDashboardRepository fallback;
    late _RecordingLogger logger;
    late DashboardSnapshot connection;
    late Future<String?> Function() loadReport;
    late ReportNormalizer normalizeReport;
    late DashboardSnapshotMerger mergeSnapshots;
    late MergingConnectionRepository repository;

    setUp(() {
      fallback = _MutableDashboardRepository(
        _liveSnapshot(snapshot, 'openai', firstAt, 100),
      );
      logger = _RecordingLogger();
      connection = _liveSnapshot(snapshot, 'claude', firstAt, 200);
      loadReport = () async => '{"sanitized":true}';
      normalizeReport = (_) => connection.toJsonString();
      mergeSnapshots = _mergeTestSnapshots;
      repository = MergingConnectionRepository(
        fallback: fallback,
        logger: logger,
        mapError:
            (_) => const DashboardLoadException(
              issue: DashboardSyncIssue.rateLimited,
              details: 'Provider request failed',
            ),
        loadReport: () => loadReport(),
        normalizeReport: (report) => normalizeReport(report),
        mergeSnapshots: (values) => mergeSnapshots(values),
      );
    });

    void failReport() {
      loadReport = () => throw StateError('sanitized failure');
    }

    test('keeps fresh A and stale B, then replaces B on recovery', () async {
      final first = await repository.load();
      expect(first.todayTotal.spent?.minorUnits, 300);

      fallback.snapshot = _liveSnapshot(snapshot, 'openai', nextAt, 150);
      failReport();
      final failed = await repository.load();
      expect(failed.accounts.map((account) => account.accountId), [
        'openai-account',
        'claude-account',
      ]);
      expect(failed.accounts.first.status, ProviderStatus.ok);
      expect(failed.accounts.first.today.spent?.minorUnits, 150);
      expect(failed.accounts.first.lastSuccessfulSyncAt, nextAt);
      expect(failed.accounts.last.status, ProviderStatus.stale);
      expect(failed.accounts.last.connection, 'anthropic.platform');
      expect(failed.accounts.last.today.spent?.minorUnits, 200);
      expect(failed.accounts.last.lastSuccessfulSyncAt, firstAt);
      expect(
        failed.accounts.last.toJson()..remove('status'),
        connection.accounts.single.toJson()..remove('status'),
      );
      expect(failed.generatedAt, nextAt);
      expect(failed.todayTotal.spent?.minorUnits, 350);
      expect(failed.overallStatus, ProviderStatus.stale);
      expect(failed.watchSummary.status, ProviderStatus.stale);
      expect(failed.syncIssue, DashboardSyncIssue.rateLimited);
      expect(failed.syncDetails, 'Provider request failed');
      final payload = jsonDecode(
        WatchDashboardSummaryPayload.fromSnapshot(
          failed,
          const WatchRingPreferences(),
        ).encode(),
      );
      expect(payload['isStale'], isTrue);
      expect(payload['providers'], [
        {
          'provider': 'openai',
          'status': 'ok',
          'todaySpent': {'minorUnits': 150, 'currency': 'USD'},
        },
        {
          'provider': 'claude',
          'status': 'stale',
          'todaySpent': {'minorUnits': 200, 'currency': 'USD'},
        },
      ]);

      connection = _liveSnapshot(snapshot, 'claude', recoveredAt, 250);
      loadReport = () async => '{"sanitized":true}';
      final recovered = await repository.load();
      expect(recovered.accounts.length, 2);
      expect(recovered.accounts.last.status, ProviderStatus.ok);
      expect(recovered.accounts.last.today.spent?.minorUnits, 250);
      expect(recovered.accounts.last.lastSuccessfulSyncAt, recoveredAt);
      expect(recovered.generatedAt, recoveredAt);
      expect(recovered.todayTotal.spent?.minorUnits, 400);
      expect(recovered.overallStatus, ProviderStatus.ok);
      expect(recovered.syncIssue, isNull);
      expect(logger.events, [
        ProviderSyncEvent.succeeded,
        ProviderSyncEvent.usingCachedSnapshot,
        ProviderSyncEvent.succeeded,
      ]);
    });

    for (final failure in ['normalization', 'parsing']) {
      test('retains only B after a $failure failure', () async {
        await repository.load();
        fallback.snapshot = _liveSnapshot(snapshot, 'openai', nextAt, 150);
        normalizeReport =
            failure == 'normalization'
                ? (_) => throw StateError('sanitized normalization failure')
                : (_) => '{}';

        final result = await repository.load();

        expect(result.accounts.map((account) => account.status), [
          ProviderStatus.ok,
          ProviderStatus.stale,
        ]);
        expect(result.accounts.last.connection, 'anthropic.platform');
        expect(result.accounts.last.lastSuccessfulSyncAt, firstAt);
        expect(result.todayTotal.spent?.minorUnits, 350);
        expect(result.syncIssue, DashboardSyncIssue.rateLimited);
      });
    }

    test('does not invent a cached B on the first failed load', () async {
      failReport();

      final result = await repository.load();

      expect(result.accounts.map((account) => account.accountId), [
        'openai-account',
      ]);
      expect(result.overallStatus, ProviderStatus.ok);
      expect(result.syncIssue, DashboardSyncIssue.rateLimited);
      expect(logger.events, isEmpty);
    });

    test(
      'does not restore A after the fallback connection is removed',
      () async {
        await repository.load();
        fallback.snapshot = DashboardSnapshot.empty(generatedAt: nextAt);
        failReport();

        final result = await repository.load();

        expect(result.accounts.map((account) => account.accountId), [
          'claude-account',
        ]);
        expect(result.generatedAt, firstAt);
        expect(result.todayTotal.spent?.minorUnits, 200);
        expect(result.overallStatus, ProviderStatus.stale);
      },
    );

    test('a missing credential erases B before a later failure', () async {
      await repository.load();
      loadReport = () async => null;
      expect(await repository.load(), same(fallback.snapshot));
      failReport();

      final result = await repository.load();

      expect(result.accounts.map((account) => account.accountId), [
        'openai-account',
      ]);
      expect(logger.events, [ProviderSyncEvent.succeeded]);
    });

    test('invalidation clears B and reaches the fallback', () async {
      await repository.load();
      repository.invalidate();
      failReport();

      final result = await repository.load();

      expect(fallback.invalidations, 1);
      expect(result.accounts.map((account) => account.accountId), [
        'openai-account',
      ]);
    });

    test('a recovery merge failure keeps A and leaves B cached', () async {
      await repository.load();
      fallback.snapshot = _liveSnapshot(snapshot, 'openai', nextAt, 150);
      failReport();
      mergeSnapshots = (_) => throw StateError('sanitized merge failure');

      final failed = await repository.load();
      expect(failed.accounts.map((account) => account.accountId), [
        'openai-account',
      ]);
      expect(failed.accounts.single.today.spent?.minorUnits, 150);
      expect(failed.syncIssue, DashboardSyncIssue.rateLimited);
      expect(failed.syncDetails, 'Provider request failed');

      mergeSnapshots = _mergeTestSnapshots;
      final retried = await repository.load();
      expect(retried.accounts.map((account) => account.accountId), [
        'openai-account',
        'claude-account',
      ]);
      expect(retried.accounts.last.status, ProviderStatus.stale);
      expect(logger.events, [
        ProviderSyncEvent.succeeded,
        ProviderSyncEvent.invalidResponse,
        ProviderSyncEvent.usingCachedSnapshot,
      ]);
    });

    test(
      'replaces cached accounts when B reports a different account',
      () async {
        await repository.load();
        final replacement = _liveSnapshot(snapshot, 'claude', nextAt, 250);
        final json = replacement.toJson();
        (json['accounts'] as List).single['accountId'] = 'replacement-account';
        connection = DashboardSnapshot.fromJson(json);
        await repository.load();
        failReport();

        final result = await repository.load();

        expect(result.accounts.map((account) => account.accountId), [
          'openai-account',
          'replacement-account',
        ]);
        expect(result.accounts.last.lastSuccessfulSyncAt, nextAt);
      },
    );

    for (final reset in ['invalidation', 'missing credential']) {
      test('an old success cannot refill B after $reset', () async {
        await repository.load();
        final pending = Completer<String?>();
        loadReport = () => pending.future;
        final oldLoad = repository.load();
        if (reset == 'invalidation') {
          repository.invalidate();
        } else {
          loadReport = () async => null;
          await repository.load();
        }
        pending.complete('{"sanitized":true}');
        await oldLoad;
        fallback.snapshot = _liveSnapshot(snapshot, 'openai', nextAt, 150);
        failReport();

        final result = await repository.load();

        expect(result.accounts.map((account) => account.accountId), [
          'openai-account',
        ]);
        expect(result.accounts.single.today.spent?.minorUnits, 150);
        expect(result.syncIssue, DashboardSyncIssue.rateLimited);
        expect(
          logger.events,
          isNot(contains(ProviderSyncEvent.usingCachedSnapshot)),
        );
      });
    }

    for (final completion in ['success', 'missing credential']) {
      test('a newer B cache survives an older $completion', () async {
        await repository.load();
        normalizeReport = (report) => report;
        final pending = Completer<String?>();
        loadReport = () => pending.future;
        final oldLoad = repository.load();
        final replacement = _liveSnapshot(snapshot, 'claude', nextAt, 250);
        loadReport = () async => replacement.toJsonString();
        await repository.load();
        pending.complete(
          completion == 'success' ? connection.toJsonString() : null,
        );
        await oldLoad;
        failReport();

        final result = await repository.load();

        expect(result.accounts.last.accountId, 'claude-account');
        expect(result.accounts.last.today.spent?.minorUnits, 250);
        expect(result.accounts.last.lastSuccessfulSyncAt, nextAt);
        expect(result.accounts.last.status, ProviderStatus.stale);
      });
    }

    test(
      'an old failure cannot read a cache loaded after invalidation',
      () async {
        await repository.load();
        final pending = Completer<String?>();
        loadReport = () => pending.future;
        final oldLoad = repository.load();
        repository.invalidate();
        connection = _liveSnapshot(snapshot, 'claude', nextAt, 250);
        loadReport = () async => '{"sanitized":true}';
        await repository.load();
        pending.completeError(StateError('sanitized old request failure'));

        final oldResult = await oldLoad;
        expect(oldResult.accounts.map((account) => account.accountId), [
          'openai-account',
        ]);
        expect(
          logger.events,
          isNot(contains(ProviderSyncEvent.usingCachedSnapshot)),
        );

        failReport();
        final current = await repository.load();
        expect(current.accounts.last.today.spent?.minorUnits, 250);
        expect(current.accounts.last.lastSuccessfulSyncAt, nextAt);
        expect(current.accounts.last.status, ProviderStatus.stale);
      },
    );
  });
}

DashboardSnapshot _liveSnapshot(
  DashboardSnapshot fixture,
  String provider,
  DateTime generatedAt,
  int spend,
) {
  final json = fixture.toJson();
  json['generatedAt'] = generatedAt.toIso8601String();
  json['overallStatus'] = 'ok';
  final account = (json['accounts'] as List).single as Map<String, dynamic>;
  account['accountId'] = '$provider-account';
  account['provider'] = provider;
  account['connection'] = switch (provider) {
    'openai' => ProviderConnections.openAiPlatform.storageKey,
    'claude' => ProviderConnections.anthropicPlatform.storageKey,
    _ => throw ArgumentError.value(provider, 'provider'),
  };
  account['status'] = 'ok';
  account['lastSuccessfulSyncAt'] = generatedAt.toIso8601String();
  for (final period in ['today', 'week', 'month']) {
    (account[period] as Map)['spent'] = {
      'minorUnits': spend,
      'currency': 'USD',
    };
    (json['${period}Total'] as Map)['spent'] = {
      'minorUnits': spend,
      'currency': 'USD',
    };
  }
  return DashboardSnapshot.fromJson(json);
}

// A deterministic merger double; production aggregates are built by Rust.
String _mergeTestSnapshots(Iterable<String> values) {
  final snapshots =
      values.map((value) => jsonDecode(value) as Map<String, dynamic>).toList();
  final merged = Map<String, dynamic>.from(snapshots.first);
  final accounts = [
    for (final snapshot in snapshots) ...snapshot['accounts'] as List,
  ];
  merged['accounts'] = accounts;
  merged['generatedAt'] =
      snapshots
          .map((snapshot) => DateTime.parse(snapshot['generatedAt'] as String))
          .reduce((left, right) => left.isAfter(right) ? left : right)
          .toIso8601String();
  final status =
      accounts.any((account) => account['status'] == 'stale') ? 'stale' : 'ok';
  merged['overallStatus'] = status;
  (merged['watchSummary'] as Map)['status'] = status;
  for (final period in ['today', 'week', 'month']) {
    final total = accounts.fold<int>(
      0,
      (sum, account) => sum + account[period]['spent']['minorUnits'] as int,
    );
    (merged['${period}Total'] as Map)['spent'] = {
      'minorUnits': total,
      'currency': 'USD',
    };
  }
  return jsonEncode(merged);
}

final class _MutableDashboardRepository extends DashboardRepository {
  _MutableDashboardRepository(this.snapshot);

  DashboardSnapshot snapshot;
  var invalidations = 0;

  @override
  Future<DashboardSnapshot> load() async => snapshot;

  @override
  void invalidate() => invalidations++;
}

final class _RecordingLogger implements ProviderSyncLogger {
  final events = <ProviderSyncEvent>[];

  @override
  void record(ProviderSyncEvent event, {String? details}) => events.add(event);
}

final class _FailingDashboardRepository extends DashboardRepository {
  const _FailingDashboardRepository(this.error);

  final Object error;

  @override
  Future<DashboardSnapshot> load() => Future.error(error);
}
