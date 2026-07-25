import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ward_pulse_phone/dashboard/dashboard_models.dart';
import 'package:ward_pulse_phone/dashboard/dashboard_repository.dart';
import 'package:ward_pulse_phone/dashboard/merging_connection_repository.dart';
import 'package:ward_pulse_phone/sync/provider_sync_logger.dart';

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
}

final class _FailingDashboardRepository extends DashboardRepository {
  const _FailingDashboardRepository(this.error);

  final Object error;

  @override
  Future<DashboardSnapshot> load() => Future.error(error);
}
