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

import 'package:ward_pulse_phone/dashboard/dashboard_load.dart';
import 'package:ward_pulse_phone/dashboard/openai_dashboard_repository.dart';
import 'package:ward_pulse_phone/dashboard/live_provider_stack.dart';
import 'package:ward_pulse_phone/providers/provider_connection.dart';
import 'package:ward_pulse_phone/providers/provider_credential_store.dart';
import 'package:ward_pulse_phone/providers/claude_account_service.dart';
import 'package:ward_pulse_phone/sync/openai_reporting_client.dart';
import 'package:ward_pulse_phone/sync/provider_reporting.dart';
import 'package:ward_pulse_phone/sync/provider_reporting_clients.dart';

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

  group('versioned reporting feedback', () {
    const ids = [
      ProviderConnections.openAiPlatform,
      ProviderConnections.anthropicPlatform,
      ProviderConnections.cursorPlatform,
    ];
    SecureProviderCredentialStore store(String owner) =>
        SecureProviderCredentialStore(
          storage: secure,
          platform: bridge.platform(owner),
        );
    MergingConnectionRepository reporting(
      ProviderConnectionId id,
      Future<String> Function(String) fetch, {
      DashboardRepository fallback = const NoProvidersDashboardRepository(),
    }) => MergingConnectionRepository(
      connection: id,
      credentialStore: store('ui'),
      cache: cache('ui', id.storageKey),
      fallback: fallback,
      loadCredentialReport: fetch,
      normalizeReport: (value) => value,
      mergeSnapshots: _merge,
      logger: const _SilentLogger(),
      mapError: (error) => mapReportingError(error, const _SilentLogger()),
    );

    test(
      'all three real factories use their own read and empty reports verify access',
      () async {
        final credentials = store('ui');
        for (final id in ids) {
          await credentials.writeSecret(id, 'synthetic-${id.storageKey}');
        }
        final transport = _EmptyReportingTransport();
        final http = ProviderReportingHttp(transport: transport);
        final caches = {
          for (final id in ids) id.storageKey: cache('ui', id.storageKey),
        };
        String empty(String _) =>
            DashboardSnapshot.empty(generatedAt: firstAt).toJsonString();
        final repository = buildLiveProviderStack(
          credentialStore: credentials,
          claudeAccountService: const EmptyClaudeAccountService(),
          openAiAndCodex: openAiDashboardRepository(
            credentialStore: credentials,
            cache: caches[ids.first.storageKey],
            client: OpenAiReportingClient(http: http),
            normalizeReport: empty,
            mergeSnapshots: _merge,
            logger: const _SilentLogger(),
          ),
          caches: caches,
          clock: () => firstAt,
          anthropicReportingClient: AnthropicReportingClient(http: http),
          cursorReportingClient: CursorPlatformClient(
            http: http,
            clock: () => firstAt,
          ),
          normalizeAnthropicReport: empty,
          normalizeCursorPlatformReport: empty,
          mergeSnapshots: _merge,
          logger: const _SilentLogger(),
        );
        final observations = <ConnectionReportingUpdate>[];
        final snapshot = await repository.loadObserved(observations.add);
        expect(snapshot.accounts, isEmpty);
        expect(
          snapshot.reportingOutcomes.map((outcome) => outcome.connection),
          unorderedEquals(ids),
        );
        for (final outcome in snapshot.reportingOutcomes) {
          final version =
              (await credentials.credentialAccess(outcome.connection)!.read())!
                  .version;
          expect(outcome.category, ReportingOutcomeCategory.success);
          expect(outcome.source, ReportingOutcomeSource.live);
          expect(outcome.credentialVersion!.values, version.values);
          expect(
            observations.where(
              (update) =>
                  update.connection == outcome.connection && update.checking,
            ),
            hasLength(1),
          );
        }
        expect(
          transport.requests,
          unorderedEquals([
            '/v1/organization/usage/completions',
            '/v1/organization/costs',
            '/v1/organizations/usage_report/messages',
            '/v1/organizations/usage_report/messages',
            '/v1/organizations/cost_report',
            '/teams/daily-usage-data',
            '/teams/spend',
          ]),
        );
        expect(snapshot.toJsonString(), isNot(contains('synthetic-')));
        expect(snapshot.toJsonString(), isNot(contains('reportingOutcomes')));
      },
    );

    test(
      'three cold failures survive all-failed and healthy-plan fallback without invented accounts',
      () async {
        for (final id in ids) {
          await store('ui').writeSecret(id, 'synthetic-key');
        }
        const fallback = NoProvidersDashboardRepository();
        final failures = [
          ProviderReportingFailure.authentication,
          ProviderReportingFailure.permissionDenied,
          ProviderReportingFailure.unavailable,
        ];
        DashboardRepository stack(DashboardRepository base) {
          var result = base;
          for (var i = 0; i < ids.length; i++) {
            final failure = failures[i];
            result = reporting(
              ids[i],
              (_) async => throw ProviderReportingException(failure),
              fallback: result,
            );
          }
          return result;
        }

        final failed = await CapturedDashboardLoad.capture(
          stack(fallback).load,
        );
        expect(
          failed.reportingOutcomes.map((outcome) => outcome.connection),
          ids,
        );
        expect(failed.reportingOutcomes.map((outcome) => outcome.category), [
          ReportingOutcomeCategory.authenticationRejected,
          ReportingOutcomeCategory.accessDenied,
          ReportingOutcomeCategory.transientFailure,
        ]);
        expect(() => failed.value, throwsA(isA<DashboardLoadException>()));
        final plan = _snapshot('codex', 'openai.plan', firstAt, 0);
        final mixed = await stack(ValueDashboardRepository(plan)).load();
        expect(mixed.accounts.single.connection, 'openai.plan');
        expect(
          mixed.reportingOutcomes.map((outcome) => outcome.connection),
          ids,
        );
        expect(
          await cache('ui', ids.first.storageKey).validSnapshot(mixed),
          isTrue,
        );
        await store('worker').writeSecret(ids[1], 'replacement');
        // There is no failed account in connectionVersions: only the failure
        // provenance can make this existing atomic gate reject the whole result.
        expect(mixed.connectionVersions, isEmpty);
        expect(
          await cache('ui', ids.first.storageKey).validSnapshot(mixed),
          isFalse,
        );
      },
    );

    test(
      'recovery replaces the failed outcome and preserves original stale success time',
      () async {
        final id = ids.first;
        await store('ui').writeSecret(id, 'synthetic-key');
        var fail = false;
        var at = firstAt;
        final repository = reporting(id, (_) async {
          if (fail)
            throw const ProviderReportingException(
              ProviderReportingFailure.authentication,
            );
          return _snapshot('openai', id.storageKey, at, 10).toJsonString();
        });
        await repository.load();
        fail = true;
        final failed = await repository.load();
        expect(
          failed.reportingOutcomes.single.category,
          ReportingOutcomeCategory.authenticationRejected,
        );
        expect(failed.accounts.single.status, ProviderStatus.stale);
        expect(failed.accounts.single.lastSuccessfulSyncAt, firstAt);
        fail = false;
        at = nextAt;
        final recovered = await repository.load();
        expect(
          recovered.reportingOutcomes.single.category,
          ReportingOutcomeCategory.success,
        );
        expect(recovered.accounts.single.status, ProviderStatus.ok);
        expect(recovered.accounts.single.lastSuccessfulSyncAt, nextAt);
        expect(recovered.syncIssue, isNull);
      },
    );

    test(
      'replacing another key preserves the newest RAM-only fallback',
      () async {
        final credentials = store('ui');
        final unchanged = ids.first;
        final replaced = ids[1];
        await credentials.writeSecret(unchanged, 'synthetic-A');
        await credentials.writeSecret(replaced, 'synthetic-B');
        var at = firstAt;
        var spend = 10;
        var fail = false;
        final fallback = reporting(unchanged, (_) async {
          if (fail)
            throw const ProviderReportingException(
              ProviderReportingFailure.unavailable,
            );
          return _snapshot(
            'openai',
            unchanged.storageKey,
            at,
            spend,
          ).toJsonString();
        });
        final repository = reporting(replaced, (_) async {
          if (fail)
            throw const ProviderReportingException(
              ProviderReportingFailure.authentication,
            );
          return _snapshot(
            'claude',
            replaced.storageKey,
            firstAt,
            30,
          ).toJsonString();
        }, fallback: fallback);
        await repository.load();
        await bridge.invoke('test', 'failCommit', {'value': true});
        at = nextAt;
        spend = 20;
        final newest = await repository.load();
        expect(newest.todayTotal.spent?.minorUnits, 50);
        await bridge.invoke('test', 'failCommit', {'value': false});
        final disk =
            (await cache('worker', unchanged.storageKey).capture()).snapshot!;
        expect(disk.accounts.single.today.spent?.minorUnits, 10);
        expect(disk.generatedAt, firstAt);

        // The app invalidates the full stack after saving a reporting key.
        await credentials.writeSecret(replaced, 'synthetic-replacement');
        repository.invalidate();
        fail = true;
        final retained = await repository.load();
        expect(retained.accounts.single.connection, unchanged.storageKey);
        expect(retained.accounts.single.status, ProviderStatus.stale);
        expect(retained.accounts.single.today.spent?.minorUnits, 20);
        expect(retained.accounts.single.lastSuccessfulSyncAt, nextAt);
        expect(retained.generatedAt, nextAt);
        expect(retained.connectionVersions, {
          unchanged.storageKey: newest.connectionVersions[unchanged.storageKey],
        });
        expect(retained.reportingOutcomes.map((outcome) => outcome.category), [
          ReportingOutcomeCategory.transientFailure,
          ReportingOutcomeCategory.authenticationRejected,
        ]);
        expect(await repository.isSnapshotCurrent(newest), isFalse);
        expect(await repository.isSnapshotCurrent(retained), isTrue);
      },
    );

    test(
      'same-load completion is observed once while fallback is held',
      () async {
        final id = ids.first;
        await store('ui').writeSecret(id, 'synthetic-key');
        final held = Completer<DashboardSnapshot>();
        final observed = Completer<ConnectionReportingUpdate>();
        var requests = 0;
        final repository = reporting(id, (_) async {
          requests++;
          return DashboardSnapshot.empty(generatedAt: firstAt).toJsonString();
        }, fallback: _HeldDashboardRepository(held.future));
        final loading = repository.loadObserved((update) {
          if (!update.checking) observed.complete(update);
        });
        final update = await observed.future;
        expect(update.outcome!.category, ReportingOutcomeCategory.success);
        expect(requests, 1);
        expect(held.isCompleted, isFalse);
        held.complete(DashboardSnapshot.empty());
        expect((await loading).reportingOutcomes.single, same(update.outcome));
        expect(requests, 1);
      },
    );

    test(
      'replacement check is not queued behind an unrelated held fallback',
      () async {
        final id = ids.first;
        await store('ui').writeSecret(id, 'synthetic-A');
        final held = Completer<DashboardSnapshot>();
        var requests = 0;
        final repository = reporting(id, (_) async {
          requests++;
          return DashboardSnapshot.empty().toJsonString();
        }, fallback: _HeldDashboardRepository(held.future));
        final firstDone = Completer<void>();
        final first = repository.loadObserved((update) {
          if (!update.checking) firstDone.complete();
        });
        final retired = expectLater(
          first,
          throwsA(isA<DashboardLoadException>()),
        );
        await firstDone.future;
        await store('worker').writeSecret(id, 'synthetic-B');
        final nextDone = Completer<ConnectionReportingUpdate>();
        final next = repository.loadObserved((update) {
          if (!update.checking) nextDone.complete(update);
        });
        final update = await nextDone.future;
        expect(requests, 2);
        expect(held.isCompleted, isFalse);
        expect(
          update.credentialVersion!.values,
          (await store('worker').credentialAccess(id)!.read())!.version.values,
        );
        held.complete(DashboardSnapshot.empty());
        await retired;
        expect((await next).reportingOutcomes.single, same(update.outcome));
      },
    );

    for (final boundary in ['replacement', 'remove', 'epoch', 'detach']) {
      test(
        'late ${boundary == 'replacement' ? 'success' : 'error'} cannot publish after $boundary',
        () async {
          final id = ids.first;
          await store('ui').writeSecret(id, 'synthetic-A');
          final started = Completer<void>();
          final response = Completer<String>();
          final observations = <ConnectionReportingUpdate>[];
          final repository = reporting(id, (_) {
            started.complete();
            return response.future;
          });
          final loading = repository.loadObserved(observations.add);
          await started.future;
          final result = CapturedDashboardLoad.capture(() => loading);
          switch (boundary) {
            case 'replacement':
              await store('worker').writeSecret(id, 'synthetic-B');
            case 'remove':
              await store('worker').deleteSecret(id);
            case 'epoch':
              await cache('worker', id.storageKey).clear();
            case 'detach':
              await bridge.invoke('ui', 'detach', {});
          }
          if (boundary == 'replacement') {
            response.complete(
              DashboardSnapshot.empty(generatedAt: firstAt).toJsonString(),
            );
          } else {
            response.completeError(
              const ProviderReportingException(
                ProviderReportingFailure.authentication,
              ),
            );
          }
          final retired = await result;
          expect(retired.reportingOutcomes, isEmpty);
          expect(observations.where((update) => !update.checking), isEmpty);
          expect(
            (await cache('worker', id.storageKey).capture()).snapshot,
            isNull,
          );
        },
      );
    }

    test(
      'an unreadable old key cannot publish a local failure for a readable replacement',
      () async {
        final id = ids.first;
        await store('ui').writeSecret(id, 'synthetic-A');
        secure.failRead = true;
        final held = Completer<DashboardSnapshot>();
        final observed = Completer<void>();
        final repository = reporting(
          id,
          (_) async => throw StateError('No network work is allowed'),
          fallback: _HeldDashboardRepository(held.future),
        );
        final loading = repository.loadObserved((update) {
          if (update.outcome?.category ==
              ReportingOutcomeCategory.localReadFailure)
            observed.complete();
        });
        final result = CapturedDashboardLoad.capture(() => loading);
        await observed.future;
        secure.failRead = false;
        await store('worker').writeSecret(id, 'synthetic-B');
        held.complete(DashboardSnapshot.empty());
        expect((await result).reportingOutcomes, isEmpty);
      },
    );

    test(
      'Cursor report-time read failure is retired by cross-engine session removal',
      () async {
        const id = ProviderConnections.cursorPlan;
        final credentials = store('ui');
        await credentials.writeSecret(id, 'synthetic-session');
        final access = credentials.credentialAccess(id)!;
        final version = (await access.read())!.version;
        final unreadable = _ReadFailureStore(
          _CurrentReadFailure(access, version),
          connection: id,
          delegate: credentials,
        );
        var cacheReads = 0;
        final held = Completer<DashboardSnapshot>();
        final observed = Completer<ConnectionReportingOutcome>();
        final transport = _EmptyReportingTransport();
        final http = ProviderReportingHttp(transport: transport);
        final repository = buildLiveProviderStack(
          credentialStore: unreadable,
          claudeAccountService: const EmptyClaudeAccountService(),
          openAiAndCodex: _HeldDashboardRepository(held.future),
          caches: {
            id.storageKey: ConnectionSnapshotCache(
              connection: id.storageKey,
              platform: bridge.platform('ui'),
              readCredentialVersion: () async {
                cacheReads++;
                return credentials.readVersion(id);
              },
            ),
          },
          anthropicReportingClient: AnthropicReportingClient(http: http),
          cursorReportingClient: CursorPlatformClient(http: http),
          mergeSnapshots: _merge,
          logger: const _SilentLogger(),
        );
        final result = CapturedDashboardLoad.capture(
          () => repository.loadObserved((update) {
            if (update.connection == id && update.outcome != null)
              observed.complete(update.outcome!);
          }),
        );
        final failure = await observed.future;
        expect(cacheReads, 1);
        expect(failure.category, ReportingOutcomeCategory.localReadFailure);
        expect(failure.credentialVersion, isNull);
        await store('worker').deleteSecret(id);
        held.complete(DashboardSnapshot.empty());
        expect((await result).reportingOutcomes, isEmpty);
        expect(transport.requests, isEmpty);
      },
    );

    test(
      'a held local-read probe cannot validate another retired connection',
      () async {
        const local = ProviderConnections.openAiPlatform;
        const stamped = ProviderConnections.anthropicPlatform;
        final credentials = store('ui');
        await credentials.writeSecret(stamped, 'synthetic-current');
        final version =
            (await credentials.credentialAccess(stamped)!.read())!.version;
        final probe = _HeldReadFailure();
        final localRepository = MergingConnectionRepository(
          connection: local,
          credentialStore: _ReadFailureStore(probe),
          cache: cache('ui', local.storageKey),
          fallback: const NoProvidersDashboardRepository(),
          loadReport: () async => null,
          normalizeReport: (value) => value,
          mapError: (error) => mapReportingError(error, const _SilentLogger()),
        );
        final outer = reporting(
          stamped,
          (_) async => '',
          fallback: localRepository,
        );
        final snapshot = DashboardSnapshot.empty().withReportingOutcomes([
          const ConnectionReportingOutcome(
            connection: local,
            category: ReportingOutcomeCategory.localReadFailure,
            source: ReportingOutcomeSource.local,
          ),
          ConnectionReportingOutcome(
            connection: stamped,
            credentialVersion: version,
            category: ReportingOutcomeCategory.authenticationRejected,
            source: ReportingOutcomeSource.live,
          ),
        ]);
        final validation = outer.isSnapshotCurrent(snapshot);
        await probe.started.future;
        await store('worker').writeSecret(stamped, 'synthetic-replacement');
        probe.release.complete();
        expect(await validation, isFalse);
      },
    );

    test(
      'queued load reads the replacement only after ownership is granted',
      () async {
        final id = ids.first;
        final credentials = store('ui');
        await credentials.writeSecret(id, 'synthetic-A');
        final access = credentials.credentialAccess(id)!;
        final held = Completer<void>();
        final acquired = Completer<void>();
        final reservation = access.serializeFetch(() async {
          acquired.complete();
          await held.future;
        });
        await acquired.future;
        String? used;
        final repository = reporting(id, (value) async {
          used = value;
          return DashboardSnapshot.empty().toJsonString();
        });
        final loading = repository.load();
        await store('worker').writeSecret(id, 'synthetic-B');
        held.complete();
        await reservation;
        final snapshot = await loading;
        expect(used, 'synthetic-B');
        expect(
          snapshot.reportingOutcomes.single.credentialVersion!.values,
          (await credentials.credentialAccess(id)!.read())!.version.values,
        );
      },
    );
  });

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

final class _HeldDashboardRepository extends DashboardRepository {
  const _HeldDashboardRepository(this.result);
  final Future<DashboardSnapshot> result;
  @override
  Future<DashboardSnapshot> load() => result;
}

final class _EmptyReportingTransport implements ProviderHttpTransport {
  final requests = <String>[];
  ProviderHttpResponse reply(Uri uri) {
    requests.add(uri.path);
    return const ProviderHttpResponse(
      statusCode: 200,
      headers: {},
      body: '{"data":[],"has_more":false,"next_page":null,"totalPages":1}',
    );
  }

  @override
  Future<ProviderHttpResponse> get(
    Uri uri, {
    required Map<String, String> headers,
  }) async => reply(uri);
  @override
  Future<ProviderHttpResponse> post(
    Uri uri, {
    required Map<String, String> headers,
    String? body,
  }) async => reply(uri);
}

final class _HeldReadFailure implements ConnectionCredentialAccess {
  final started = Completer<void>();
  final release = Completer<void>();
  @override
  Future<VersionedCredential<String>?> read() async {
    started.complete();
    await release.future;
    throw StateError('Synthetic storage read failure');
  }

  @override
  Future<bool> isCurrent(CredentialVersion expected) async => false;
  @override
  Future<R> serializeFetch<R>(Future<R> Function() operation) => operation();
}

final class _ReadFailureStore
    implements ProviderCredentialStore, VersionedProviderCredentialStore {
  const _ReadFailureStore(this.access, {this.connection, this.delegate});
  final ConnectionCredentialAccess access;
  final ProviderConnectionId? connection;
  final SecureProviderCredentialStore? delegate;
  @override
  ConnectionCredentialAccess? credentialAccess(ProviderConnectionId id) =>
      connection == null || connection == id
          ? access
          : delegate?.credentialAccess(id);
  @override
  Future<String?> readSecret(ProviderConnectionId id) async =>
      connection == null || connection == id
          ? (await access.read())?.value
          : await delegate?.readSecret(id);
  @override
  Future<String?> readLabel(ProviderConnectionId id) async =>
      await delegate?.readLabel(id);
  @override
  Future<void> writeSecret(ProviderConnectionId id, String value) async =>
      throw UnsupportedError('Read-only fixture');
  @override
  Future<void> deleteSecret(ProviderConnectionId id) async =>
      throw UnsupportedError('Read-only fixture');
  @override
  Future<void> writeLabel(ProviderConnectionId id, String? value) async =>
      throw UnsupportedError('Read-only fixture');
}

final class _CurrentReadFailure implements ConnectionCredentialAccess {
  const _CurrentReadFailure(this.access, this.version);
  final ConnectionCredentialAccess access;
  final CredentialVersion version;
  @override
  Future<VersionedCredential<String>?> read() async {
    final read = await access.read();
    if (read != null && version.sameCache(read.version))
      throw StateError('Synthetic current credential read failure');
    return read;
  }

  @override
  Future<bool> isCurrent(CredentialVersion expected) =>
      access.isCurrent(expected);
  @override
  Future<R> serializeFetch<R>(Future<R> Function() operation) =>
      access.serializeFetch(operation);
}
