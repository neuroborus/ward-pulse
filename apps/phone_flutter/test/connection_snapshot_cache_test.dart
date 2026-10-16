import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ward_pulse_phone/dashboard/apply_alert_settings.dart';
import 'package:ward_pulse_phone/dashboard/connection_snapshot_cache.dart';
import 'package:ward_pulse_phone/dashboard/dashboard_models.dart';
import 'package:ward_pulse_phone/dashboard/dashboard_repository.dart';
import 'package:ward_pulse_phone/dashboard/merging_connection_repository.dart';
import 'package:ward_pulse_phone/providers/connection_lifecycle.dart';
import 'package:ward_pulse_phone/settings/alert_threshold_preferences.dart';
import 'package:ward_pulse_phone/sync/provider_sync_logger.dart';

import 'connection_cache_test_support.dart';

void main() {
  late NativeCacheTestBridge bridge;
  late FakeSecureStorage secure;
  final firstAt = DateTime.utc(2026, 10, 13, 8);
  final nextAt = firstAt.add(const Duration(minutes: 5));
  setUpAll(() async {
    bridge = await NativeCacheTestBridge.start();
  });
  tearDownAll(() => bridge.close());
  setUp(() async {
    await bridge.reset();
    secure = FakeSecureStorage();
  });
  ConnectionCredentialStorage credentials(String owner, String id) =>
      ConnectionCredentialStorage(
        connection: id,
        legacyKey: 'wardpulse.$id.secret',
        principal: (value) => value,
        storage: secure,
        platform: bridge.platform(owner),
      );
  ConnectionSnapshotCache cache(String owner, String id) =>
      ConnectionSnapshotCache(
        connection: id,
        platform: bridge.platform(owner),
        readCredentialVersion:
            () async => (await credentials(owner, id).read())?.version,
      );
  MergingConnectionRepository repository(
    String owner,
    String id,
    Future<String?> Function() load, {
    DashboardRepository fallback = const NoProvidersDashboardRepository(),
  }) => MergingConnectionRepository(
    cache: cache(owner, id),
    fallback: fallback,
    loadReport: load,
    normalizeReport: (report) => report,
    mergeSnapshots: _merge,
    logger: const _SilentLogger(),
    mapError:
        (_) =>
            const DashboardLoadException(issue: DashboardSyncIssue.rateLimited),
  );

  test(
    'fresh engine recovers fresh A with persisted stale B and original times',
    () async {
      await credentials('ui', 'openai.platform').write('fake-A');
      await credentials('ui', 'anthropic.platform').write('fake-B');
      final a1 = _snapshot('openai', 'openai.platform', firstAt, 100);
      final b1 = _snapshot('claude', 'anthropic.platform', firstAt, 200);
      final warmA = repository(
        'ui',
        'openai.platform',
        () async => a1.toJsonString(),
      );
      await repository(
        'ui',
        'anthropic.platform',
        () async => b1.toJsonString(),
        fallback: warmA,
      ).load();
      await bridge.invoke('test', 'restart', {});
      final a2 = _snapshot('openai', 'openai.platform', nextAt, 150);
      final coldA = repository(
        'worker',
        'openai.platform',
        () async => a2.toJsonString(),
      );
      final recovered =
          await repository(
            'worker',
            'anthropic.platform',
            () async => throw StateError('Sanitized fetch failure.'),
            fallback: coldA,
          ).load();
      expect(recovered.accounts.map((account) => account.provider), [
        'openai',
        'claude',
      ]);
      expect(recovered.accounts.first.status, ProviderStatus.ok);
      expect(recovered.accounts.last.status, ProviderStatus.stale);
      expect(recovered.accounts.last.connection, 'anthropic.platform');
      expect(recovered.accounts.last.lastSuccessfulSyncAt, firstAt);
      expect(recovered.generatedAt, nextAt);
      expect(recovered.todayTotal.spent?.minorUnits, 350);
      expect(recovered.connectionVersions.length, 2);
      expect(
        applyUserAlertSettings(
          recovered,
          const AlertThresholdPreferences(),
        ).connectionVersions,
        recovered.connectionVersions,
      );
      expect(recovered.toJson().containsKey('connectionVersions'), isFalse);
    },
  );
  test(
    'cold all-failure recovers both caches; uncached first failure invents nothing',
    () async {
      await credentials('ui', 'openai.platform').write('fake-A');
      await credentials('ui', 'anthropic.platform').write('fake-B');
      await repository(
        'ui',
        'openai.platform',
        () async =>
            _snapshot('openai', 'openai.platform', firstAt, 100).toJsonString(),
      ).load();
      await repository(
        'ui',
        'anthropic.platform',
        () async =>
            _snapshot(
              'claude',
              'anthropic.platform',
              firstAt,
              200,
            ).toJsonString(),
      ).load();
      await bridge.invoke('test', 'restart', {});
      Future<String?> fail() async => throw StateError('Sanitized failure.');
      final both =
          await repository(
            'worker',
            'anthropic.platform',
            fail,
            fallback: repository('worker', 'openai.platform', fail),
          ).load();
      expect(both.accounts, hasLength(2));
      expect(
        both.accounts.map((account) => account.status),
        everyElement(ProviderStatus.stale),
      );
      expect(both.generatedAt, firstAt);
      await credentials('worker', 'cursor.platform').write('fake-C');
      await expectLater(
        repository('worker', 'cursor.platform', fail).load(),
        throwsA(isA<DashboardLoadException>()),
      );
    },
  );
  test(
    'UI memory adopts newer worker cache and older success cannot downgrade it',
    () async {
      final newerAt = firstAt.add(const Duration(microseconds: 1));
      await credentials('ui', 'openai.platform').write('fake-A');
      var report =
          _snapshot('openai', 'openai.platform', firstAt, 100).toJsonString();
      var fail = false;
      final ui = repository(
        'ui',
        'openai.platform',
        () async => fail ? throw StateError('Sanitized failure.') : report,
      );
      await ui.load();
      await repository(
        'worker',
        'openai.platform',
        () async =>
            _snapshot('openai', 'openai.platform', newerAt, 200).toJsonString(),
      ).load();
      fail = true;
      expect((await ui.load()).accounts.single.today.spent?.minorUnits, 200);
      fail = false;
      report =
          _snapshot('openai', 'openai.platform', firstAt, 50).toJsonString();
      final olderSuccess = await ui.load();
      expect(olderSuccess.accounts.single.today.spent?.minorUnits, 200);
      expect(olderSuccess.generatedAt, newerAt);
      fail = true;
      final recovered = await ui.load();
      expect(recovered.generatedAt, newerAt);
      expect(recovered.accounts.single.today.spent?.minorUnits, 200);
      final cold =
          await repository(
            'cold',
            'openai.platform',
            () async => throw StateError('Sanitized cold failure.'),
          ).load();
      expect(cold.accounts.single.today.spent?.minorUnits, 200);
      expect(cold.generatedAt, newerAt);
    },
  );
  test(
    'skipped older response rereads a newer worker snapshot before publication',
    () async {
      final t2 = firstAt.add(const Duration(microseconds: 1));
      final t3 = firstAt.add(const Duration(microseconds: 2));
      await credentials('ui', 'openai.platform').write('fake-A');
      Future<String?> Function() loader =
          () async =>
              _snapshot('openai', 'openai.platform', t2, 200).toJsonString();
      final ui = repository('ui', 'openai.platform', () => loader());
      await ui.load();
      final entered = Completer<void>();
      final release = Completer<String?>();
      loader = () {
        entered.complete();
        return release.future;
      };
      final older = ui.load();
      await entered.future;
      await repository(
        'worker',
        'openai.platform',
        () async =>
            _snapshot('openai', 'openai.platform', t3, 300).toJsonString(),
      ).load();
      release.complete(
        _snapshot('openai', 'openai.platform', firstAt, 50).toJsonString(),
      );
      final published = await older;
      expect(published.accounts.single.today.spent?.minorUnits, 300);
      expect(published.generatedAt, t3);
      final cold =
          await repository(
            'cold',
            'openai.platform',
            () async => throw StateError('Sanitized failure.'),
          ).load();
      expect(cold.accounts.single.today.spent?.minorUnits, 300);
      expect(cold.generatedAt, t3);
    },
  );
  test(
    'cold legacy millisecond ordering upgrades from the original microsecond timestamp',
    () async {
      final original = firstAt.add(const Duration(microseconds: 1));
      await credentials('ui', 'openai.platform').write('fake-A');
      await repository(
        'ui',
        'openai.platform',
        () async =>
            _snapshot(
              'openai',
              'openai.platform',
              original,
              200,
            ).toJsonString(),
      ).load();
      await bridge.invoke('test', 'setDisk', {
        'key': 'openai.platform.snapshotTimeUnit',
        'value': 'milliseconds',
      });
      await bridge.invoke('test', 'setDisk', {
        'key': 'openai.platform.snapshotAt',
        'value': original.millisecondsSinceEpoch,
      });
      await bridge.invoke('test', 'restart', {});
      final captured = await cache('cold', 'openai.platform').capture();
      expect(captured.snapshot?.generatedAt, original);
      expect(
        await cache('old', 'openai.platform').store(
          _snapshot('openai', 'openai.platform', firstAt, 50),
          captured.version!,
        ),
        isFalse,
      );
      final recovered =
          await repository(
            'next-engine',
            'openai.platform',
            () async => throw StateError('Sanitized failure.'),
          ).load();
      expect(recovered.accounts.single.today.spent?.minorUnits, 200);
      expect(recovered.generatedAt, original);
    },
  );
  test(
    'deletion/replacement/identity mismatch refuse old memory and disk',
    () async {
      final store = credentials('ui', 'openai.platform');
      await store.write('fake-A');
      var fail = false;
      final ui = repository(
        'ui',
        'openai.platform',
        () async =>
            fail
                ? throw StateError('Sanitized failure.')
                : _snapshot(
                  'openai',
                  'openai.platform',
                  firstAt,
                  10,
                ).toJsonString(),
      );
      final warm = await ui.load();
      await store.delete();
      expect(await ui.isSnapshotCurrent(warm), isFalse);
      fail = true;
      await expectLater(ui.load(), throwsA(isA<DashboardLoadException>()));
      await store.write('fake-new');
      await expectLater(
        repository(
          'worker',
          'openai.platform',
          () async => throw StateError('Sanitized failure.'),
        ).load(),
        throwsA(isA<DashboardLoadException>()),
      );
      fail = false;
      await ui.load();
      final slot = secure.values.keys.singleWhere(
        (key) => key.startsWith('wardpulse.connection.'),
      );
      secure.values[slot] = 'fake-unexpected-identity';
      fail = true;
      await expectLater(ui.load(), throwsA(isA<DashboardLoadException>()));
      expect(
        (await cache('worker', 'openai.platform').capture()).snapshot,
        isNull,
      );
    },
  );
  test(
    'delayed old successful fetch cannot return or refill a deleted connection',
    () async {
      final store = credentials('ui', 'openai.platform');
      await store.write('fake-A');
      final started = Completer<void>();
      final response = Completer<String?>();
      final ui = repository('ui', 'openai.platform', () {
        started.complete();
        return response.future;
      });
      final loading = ui.load();
      await started.future;
      await store.delete();
      response.complete(
        _snapshot('openai', 'openai.platform', firstAt, 10).toJsonString(),
      );
      expect((await loading).accounts, isEmpty);
      expect(
        (await cache('worker', 'openai.platform').capture()).snapshot,
        isNull,
      );
    },
  );
  test(
    'fresh success retains stamped memory when payload persistence is unavailable',
    () async {
      await credentials('ui', 'openai.platform').write('fake-A');
      await bridge.invoke('test', 'failCommit', {'value': true});
      var fail = false;
      final ui = repository(
        'ui',
        'openai.platform',
        () async =>
            fail
                ? throw StateError('Sanitized failure.')
                : _snapshot(
                  'openai',
                  'openai.platform',
                  firstAt,
                  10,
                ).toJsonString(),
      );
      final fresh = await ui.load();
      expect(fresh.connectionVersions, isNotEmpty);
      fail = true;
      final retained = await ui.load();
      expect(retained.accounts.single.status, ProviderStatus.stale);
      expect(retained.accounts.single.today.spent?.minorUnits, 10);
      expect(retained.generatedAt, firstAt);
    },
  );
  test(
    'snapshot IO failure preserves a fresh live response; credential IO fails closed',
    () async {
      await credentials('ui', 'openai.platform').write('fake-A');
      final version =
          (await credentials('ui', 'openai.platform').read())!.version;
      await cache(
        'ui',
        'openai.platform',
      ).store(_snapshot('openai', 'openai.platform', firstAt, 10), version);
      await bridge.invoke('test', 'setDisk', {
        'key': 'openai.platform.snapshot',
        'value': '{corrupt',
      });
      await bridge.invoke('test', 'failCommit', {'value': true});
      final fresh =
          await repository(
            'ui',
            'openai.platform',
            () async =>
                _snapshot(
                  'openai',
                  'openai.platform',
                  nextAt,
                  20,
                ).toJsonString(),
          ).load();
      expect(fresh.accounts.single.today.spent?.minorUnits, 20);
      await bridge.invoke('test', 'failCommit', {'value': false});
      secure.failRead = true;
      await expectLater(
        repository(
          'worker',
          'openai.platform',
          () async => throw StateError('Sanitized failure.'),
        ).load(),
        throwsA(isA<DashboardLoadException>()),
      );
      secure.failRead = false;
      expect(await cache('worker', 'openai.platform').valid(version), isTrue);
    },
  );
  for (final corruption in [
    'provider',
    'status',
    'percentage',
    'source',
    'window',
    'money',
    'currency',
    'severity',
  ]) {
    test(
      'rejects cached $corruption without discarding the credential',
      () async {
        await credentials('ui', 'openai.platform').write('fake-A');
        final version =
            (await credentials('ui', 'openai.platform').read())!.version;
        final json =
            _snapshot('openai', 'openai.platform', firstAt, 10).toJson();
        final account = (json['accounts'] as List).single as Map;
        switch (corruption) {
          case 'provider':
            account['provider'] = 'claude';
          case 'status':
            account['status'] = 'invented';
          case 'percentage':
            (account['today'] as Map)['usedPercent'] = -1;
          case 'source':
            account['allowances'] = [
              {'source': 'invented'},
            ];
          case 'window':
            account['allowances'] = [
              {'windowMinutes': 0},
            ];
          case 'money':
            (account['today'] as Map)['spent'] = {
              'minorUnits': 1.5,
              'currency': 'USD',
            };
          case 'currency':
            (account['today'] as Map)['spent'] = {
              'minorUnits': -1,
              'currency': 'usd',
            };
          case 'severity':
            json['alerts'] = [
              {'severity': 'invented'},
            ];
        }
        await bridge.invoke('test', 'setDisk', {
          'key': 'openai.platform.snapshot',
          'value': jsonEncode(json),
        });
        await bridge.invoke('test', 'setDisk', {
          'key': 'openai.platform.snapshotVersion',
          'value': '1',
        });
        expect(
          (await cache('worker', 'openai.platform').capture()).snapshot,
          isNull,
        );
        final retained =
            (await credentials('worker', 'openai.platform').read())!;
        expect(retained.value, 'fake-A');
        expect(retained.version.generation, version.generation);
      },
    );
  }
}

DashboardSnapshot _snapshot(
  String provider,
  String connection,
  DateTime time,
  int spend,
) {
  final json =
      jsonDecode(
            File(
              '../../fixtures/snapshots/dashboard_today.json',
            ).readAsStringSync(),
          )
          as Map<String, dynamic>;
  json['generatedAt'] = time.toIso8601String();
  json['overallStatus'] = 'ok';
  final account = (json['accounts'] as List).single as Map;
  account['provider'] = provider;
  account['connection'] = connection;
  account['accountId'] = '$provider-sanitized';
  account['status'] = 'ok';
  account['lastSuccessfulSyncAt'] = time.toIso8601String();
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

String _merge(Iterable<String> values) {
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
          .reduce((a, b) => a.isAfter(b) ? a : b)
          .toIso8601String();
  final status =
      accounts.any((account) => account['status'] == 'stale') ? 'stale' : 'ok';
  merged['overallStatus'] = status;
  (merged['watchSummary'] as Map)['status'] = status;
  for (final period in ['today', 'week', 'month']) {
    (merged['${period}Total'] as Map)['spent'] = {
      'minorUnits': accounts.fold<int>(
        0,
        (sum, account) => sum + account[period]['spent']['minorUnits'] as int,
      ),
      'currency': 'USD',
    };
  }
  return jsonEncode(merged);
}

final class _SilentLogger implements ProviderSyncLogger {
  const _SilentLogger();
  @override
  void record(ProviderSyncEvent event, {String? details}) {}
}
