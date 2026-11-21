import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ward_pulse_bindings/ward_pulse_bindings.dart';
import 'package:ward_pulse_phone/app/ward_pulse_app.dart';
import 'package:ward_pulse_phone/dashboard/apply_alert_settings.dart';
import 'package:ward_pulse_phone/dashboard/codex_dashboard_repository.dart';
import 'package:ward_pulse_phone/dashboard/connection_snapshot_cache.dart';
import 'package:ward_pulse_phone/dashboard/dashboard_models.dart';
import 'package:ward_pulse_phone/dashboard/dashboard_repository.dart';
import 'package:ward_pulse_phone/dashboard/merging_connection_repository.dart';
import 'package:ward_pulse_phone/providers/connection_lifecycle.dart';
import 'package:ward_pulse_phone/providers/codex_account_service.dart';
import 'package:ward_pulse_phone/settings/alert_threshold_preferences.dart';
import 'package:ward_pulse_phone/sync/provider_sync_logger.dart';
import 'package:ward_pulse_phone/sync/automatic_poll.dart';
import 'package:ward_pulse_phone/settings/watch_ring_preferences.dart';
import 'package:ward_pulse_phone/sync/watch_sync_service.dart';
import 'package:ward_pulse_phone/widget/phone_widget_payload.dart';
import 'package:ward_pulse_phone/widget/phone_widget_preferences.dart';
import 'package:ward_pulse_phone/widget/phone_widget_sync.dart';

import 'package:ward_pulse_phone/dashboard/dashboard_load.dart';
import 'package:ward_pulse_phone/dashboard/openai_dashboard_repository.dart';
import 'package:ward_pulse_phone/dashboard/live_provider_stack.dart';
import 'package:ward_pulse_phone/providers/provider_connection.dart';
import 'package:ward_pulse_phone/providers/provider_credential_store.dart';
import 'package:ward_pulse_phone/providers/claude_account_service.dart';
import 'package:ward_pulse_phone/sync/openai_reporting_client.dart';
import 'package:ward_pulse_phone/sync/provider_reporting.dart';
import 'package:ward_pulse_phone/sync/provider_reporting_clients.dart';

import 'package:ward_pulse_phone/dashboard/plan_recoveries.dart';
import 'package:ward_pulse_phone/providers/codex_account_store.dart';
import 'package:ward_pulse_phone/settings/alert_notification_preferences.dart';
import 'package:ward_pulse_phone/sync/alert_notifications.dart';
import 'package:ward_pulse_phone/sync/codex_account_client.dart';
import 'package:ward_pulse_phone/sync/recovery_notifications.dart';
import 'package:ward_pulse_phone/sync/recovery_watchlist.dart';
import 'package:ward_pulse_phone/sync/recovery_wake.dart';

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
  ConnectionSnapshotCache cache(
    String owner,
    String id, {
    ConnectionCachePlatform? platform,
  }) => ConnectionSnapshotCache(
    connection: id,
    platform: platform ?? bridge.platform(owner),
    readCredentialVersion:
        () async => (await credentials(owner, id).read())?.version,
  );
  MergingConnectionRepository repository(
    String owner,
    String id,
    Future<String?> Function() load, {
    DashboardRepository fallback = const NoProvidersDashboardRepository(),
    ConnectionCachePlatform? cachePlatform,
  }) => MergingConnectionRepository(
    cache: cache(owner, id, platform: cachePlatform),
    fallback: fallback,
    loadReport: load,
    normalizeReport: (report) => report,
    mergeSnapshots: _merge,
    logger: const _SilentLogger(),
    mapError:
        (_) =>
            const DashboardLoadException(issue: DashboardSyncIssue.rateLimited),
  );

  MergingConnectionRepository owned(
    String owner,
    String id,
    Future<String> Function(String) load, {
    DashboardRepository fallback = const NoProvidersDashboardRepository(),
    ConnectionCachePlatform? cachePlatform,
  }) => MergingConnectionRepository(
    connection: ProviderConnectionId.fromStorageKey(id),
    credentialStore: SecureProviderCredentialStore(
      storage: secure,
      platform: bridge.platform(owner),
    ),
    cache: cache(owner, id, platform: cachePlatform),
    fallback: fallback,
    loadCredentialReport: load,
    normalizeReport: (value) => value,
    mergeSnapshots: _merge,
    logger: const _SilentLogger(),
    mapError:
        (_) =>
            const DashboardLoadException(issue: DashboardSyncIssue.rateLimited),
  );
  AutomaticPollContext automatic() => AutomaticPollContext(
    readInterval: () async => const Duration(minutes: 5),
  );

  group('snapshot clock ordering', () {
    const cursorId = ProviderConnections.cursorPlan;
    final fastAt = firstAt.add(const Duration(days: 1));
    final correctedAt = firstAt.add(const Duration(minutes: 1));
    late DateTime now;
    Future<void> setClock(DateTime at) async {
      now = at;
      await bridge.invoke('test', 'setClock', {
        'value': at.millisecondsSinceEpoch,
      });
    }

    SecureProviderCredentialStore store(ConnectionCachePlatform platform) =>
        SecureProviderCredentialStore(storage: secure, platform: platform);

    DashboardRepository cursor(
      String owner,
      Future<int> Function() usage, {
      ConnectionCachePlatform? observed,
      DashboardRepository fallback = const NoProvidersDashboardRepository(),
    }) {
      final platform = observed ?? bridge.platform(owner);
      return buildLiveProviderStack(
        credentialStore: store(platform),
        claudeAccountService: const EmptyClaudeAccountService(),
        openAiAndCodex: fallback,
        caches: {
          cursorId.storageKey: cache(
            owner,
            cursorId.storageKey,
            platform: platform,
          ),
        },
        cursorSessionClient: CursorPlanClient(
          http: ProviderReportingHttp(transport: _CursorUsageTransport(usage)),
        ),
        clock: () => now,
        logger: const _SilentLogger(),
      );
    }

    double? cursorUsage(DashboardSnapshot snapshot) =>
        snapshot.accounts
            .singleWhere((account) => account.connection == cursorId.storageKey)
            .allowances
            .singleWhere((allowance) => allowance.id == 'cursor-plan-models')
            .usedPercent;

    Future<DashboardSnapshot> coldCursor() async {
      await bridge.invoke('test', 'restart', {});
      return (await cache('cold', cursorId.storageKey).capture()).snapshot!;
    }

    Future<void> waitForHold(
      Completer<void> reached,
      Future<CapturedDashboardLoad> load,
    ) => Future.any([
      reached.future,
      load.then<void>((result) {
        result.value;
        throw StateError('Dashboard refresh finished before its barrier.');
      }),
    ]);

    final superseded = isA<DashboardLoadException>().having(
      (error) => error.details,
      'details',
      'Connection changed during refresh.',
    );

    test('an equal-time write retires a confirmed aggregate', () async {
      await store(
        bridge.platform('seed'),
      ).writeSecret(cursorId, 'synthetic-session');
      await setClock(firstAt);
      final older = cursor('older', () async => 40);
      final original = await older.load();
      expect(cursorUsage(original), 40);
      expect(await older.isSnapshotCurrent(original), isTrue);

      final newer = cursor('newer', () async => 70);
      final replacement = await newer.load();
      expect(cursorUsage(replacement), 70);
      expect(replacement.generatedAt, original.generatedAt);
      final key = cursorId.storageKey;
      expect(
        replacement.connectionVersions[key],
        original.connectionVersions[key],
      );
      expect(
        replacement.snapshotOrdering[key]?.payload,
        original.snapshotOrdering[key]?.payload,
      );
      expect(await older.isSnapshotCurrent(original), isFalse);
      expect(await newer.isSnapshotCurrent(replacement), isTrue);
    });

    for (final (scenario, replacementAfterRead) in [
      ('keeps provisional RAM when the equal-time row is unchanged', null),
      ('selects an equal-time replacement after the first pair', 1),
      ('selects an equal-time replacement after the final pair', 2),
    ]) {
      test('a failed write $scenario', () async {
        final key = cursorId.storageKey;
        await store(
          bridge.platform('seed'),
        ).writeSecret(cursorId, 'synthetic-session');
        final equalAt = nextAt.add(const Duration(microseconds: 1));
        await setClock(equalAt);
        expect(cursorUsage(await cursor('seed', () async => 40).load()), 40);

        final paired = Completer<void>();
        final resume = Completer<void>();
        final platform = ObservingCachePlatform(bridge.platform('older'));
        var selectionReads = 0;
        Object? write;
        platform.onComplete = (method, arguments, result) async {
          if (arguments['connection'] != key) return;
          if (method == 'writeSnapshot') write = result;
          if (method == 'readSnapshot' &&
              arguments['forSelection'] == true &&
              ++selectionReads == (replacementAfterRead ?? 1)) {
            paired.complete();
            await resume.future;
          }
        };
        var usage = 70;
        final older = cursor('older', () async => usage, observed: platform);
        await bridge.invoke('test', 'failCommit', {'value': true});
        final pending = CapturedDashboardLoad.capture(older.load);
        try {
          await waitForHold(paired, pending);
          expect(write, containsPair('status', 'storageFailure'));
          await bridge.invoke('test', 'failCommit', {'value': false});
          if (replacementAfterRead != null) {
            final replacement = await cursor('newer', () async => 90).load();
            expect(cursorUsage(replacement), 90);
            expect(replacement.generatedAt, equalAt);
          }
          resume.complete();

          final selected = (await pending).value;
          expect(cursorUsage(selected), replacementAfterRead == null ? 70 : 90);
          expect(selected.generatedAt, equalAt);
          expect(await older.isSnapshotCurrent(selected), isTrue);
          expect(selectionReads, replacementAfterRead == 2 ? 3 : 2);
          if (replacementAfterRead == null) {
            // An older report must leave approved RAM paired to the same row.
            usage = 50;
            write = null;
            await setClock(nextAt);
            final retained = await older.load();
            expect(write, isNull);
            expect(cursorUsage(retained), 70);
            expect(retained.generatedAt, equalAt);
            expect(retained.snapshotOrdering[key]?.attemptEra, 0);
            expect(await older.isSnapshotCurrent(retained), isTrue);

            Future<DashboardSnapshot> failBeforeAdmission() =>
                AutomaticPollContext(
                  readInterval:
                      () async =>
                          throw StateError('Synthetic cadence failure.'),
                ).run(older.load);
            final paired = await cache('reader', key).capture();
            expect(cursorUsage(paired.snapshot!), 40);
            expect(
              retained.snapshotOrdering[key]?.cacheObservation,
              paired.observation,
            );
            final ramFallback = await failBeforeAdmission();
            expect(
              ramFallback.syncIssue,
              DashboardSyncIssue.credentialUnavailable,
            );
            expect(ramFallback.accounts.single.status, ProviderStatus.stale);
            expect(cursorUsage(ramFallback), 70);
            expect(ramFallback.snapshotOrdering[key]?.confirmedRowId, isNull);
            expect(
              ramFallback.snapshotOrdering[key]?.emptyCacheOrder,
              paired.order,
            );
            expect(await older.isSnapshotCurrent(ramFallback), isTrue);

            await setClock(equalAt);
            final replacement = await cursor('newer', () async => 90).load();
            final replacementRow =
                replacement.snapshotOrdering[key]?.confirmedRowId;
            expect(replacementRow, isA<String>());
            expect(replacementRow, isNot(paired.record?.rowId));
            expect(
              replacement.snapshotOrdering[key]?.payload,
              ramFallback.snapshotOrdering[key]?.payload,
            );
            final confirmedFallback = await failBeforeAdmission();
            expect(cursorUsage(confirmedFallback), 90);
            expect(
              confirmedFallback.snapshotOrdering[key]?.confirmedRowId,
              replacementRow,
            );
            expect(await older.isSnapshotCurrent(confirmedFallback), isTrue);
          }
        } finally {
          if (!resume.isCompleted) resume.complete();
          await pending;
          await bridge.invoke('test', 'failCommit', {'value': false});
        }
      });
    }

    for (final initialPair in [
      'unavailable',
      'from a previous credential',
      'from a previous epoch',
    ]) {
      test(
        'a failed write retains equal-order RAM when the pair is $initialPair',
        () async {
          final key = cursorId.storageKey;
          final reader = cache('reader', key);
          final credentials = store(bridge.platform('seed'));
          await credentials.writeSecret(cursorId, 'synthetic-session');
          await setClock(firstAt);
          expect(cursorUsage(await cursor('seed', () async => 40).load()), 40);
          final original = await reader.capture();
          final platform = ObservingCachePlatform(bridge.platform('older'));
          var paired = original;
          var initialReads = 0;
          Object? initialReply;
          Object? write;
          platform.beforeInvoke = (method, arguments) async {
            if (arguments['connection'] != key) return;
            if (method == 'readSnapshot' && arguments['forSelection'] != true) {
              initialReads++;
              if (initialPair == 'unavailable') {
                throw StateError('Synthetic initial paired read failure.');
              }
            }
            if (method == 'writeSnapshot') {
              await bridge.invoke('test', 'failCommit', {'value': true});
            }
          };
          platform.onComplete = (method, arguments, result) async {
            if (arguments['connection'] != key) return;
            if (method == 'writeSnapshot') {
              write = result;
              await bridge.invoke('test', 'failCommit', {'value': false});
            }
            if (method != 'readSnapshot' || arguments['forSelection'] == true) {
              return;
            }
            initialReply = result;
            if (initialPair == 'from a previous credential') {
              await credentials.writeSecret(cursorId, 'synthetic-replacement');
            } else {
              await reader.clear(original.version);
            }
            await cursor('seed', () async => 50).load();
            paired = await reader.capture();
          };

          final older = cursor('older', () async => 70, observed: platform);
          try {
            final selected = await older.load();
            expect(initialReads, 1);
            if (initialPair != 'unavailable') {
              expect(
                initialReply,
                containsPair('rowId', original.record!.rowId),
              );
              expect(paired.version!.sameCache(original.version!), isFalse);
              expect(paired.record!.rowId, isNot(original.record!.rowId));
              expect(cursorUsage(paired.snapshot!), 50);
            }
            if (initialPair == 'from a previous epoch') {
              expect(paired.version!.generation, original.version!.generation);
              expect(paired.version!.epoch, isNot(original.version!.epoch));
            }
            expect(write, containsPair('status', 'storageFailure'));
            expect(selected.connectionVersions[key], paired.version!.values);
            final ordering = selected.snapshotOrdering[key]!;
            expect(ordering.payload, (
              era: paired.record!.selectionEra,
              generatedAtMicros:
                  paired.snapshot!.generatedAt.microsecondsSinceEpoch,
            ));
            expect(ordering.confirmedRowId, isNull);
            expect(ordering.cacheObservation, paired.observation);
            expect(cursorUsage(selected), 70);
            expect(selected.syncIssue, isNull);
            expect(await older.isSnapshotCurrent(selected), isTrue);
            expect((await reader.capture()).observation, paired.observation);
          } finally {
            await bridge.invoke('test', 'failCommit', {'value': false});
          }
        },
      );
    }

    for (final scenario in [
      'unchanged payload',
      'replaced payload',
      'replaced payload at the same instant',
      'advanced floor',
      'unavailable paired read',
    ]) {
      test('a pre-admission outage retains the proof of $scenario', () async {
        final key = cursorId.storageKey;
        final reader = cache('reader', key);
        final credentialStore = store(bridge.platform('seed'));
        await credentialStore.writeSecret(cursorId, 'synthetic-session');
        final version = (await credentialStore.readVersion(cursorId))!;
        await setClock(firstAt);
        final sameInstant = scenario == 'replaced payload at the same instant';
        if (sameInstant) {
          expect(cursorUsage(await cursor('seed', () async => 40).load()), 40);
        } else {
          // A legacy confirmed row remains eligible when the first stamped
          // write advances the floor to zero without replacing the payload.
          expect(
            await reader.store(_snapshot('cursor', key, firstAt, 40), version),
            isTrue,
          );
        }
        final original = await reader.capture(expected: version);
        expect(original.order, isNotNull);
        expect(original.minimumEra, sameInstant ? 0 : isNull);

        final released = Completer<void>();
        final resume = Completer<void>();
        final platform = ObservingCachePlatform(bridge.platform('old'));
        final missingPair = scenario == 'unavailable paired read';
        var admissionFailed = false;
        var prepareOutage = false;
        var requests = 0;
        var selectionReads = 0;
        platform.beforeInvoke = (method, arguments) async {
          if (arguments['connection'] != key || !prepareOutage) return;
          if (method == 'readSnapshot') {
            if (arguments['forSelection'] == true) {
              selectionReads++;
            } else if (missingPair) {
              throw StateError('Synthetic initial paired read failure.');
            }
          }
          if (method != 'claimAutomatic') return;
          await bridge.invoke('test', 'failCommit', {'value': true});
          try {
            await bridge.invoke('old', method, arguments);
          } catch (_) {
            admissionFailed = true;
            rethrow;
          } finally {
            await bridge.invoke('test', 'failCommit', {'value': false});
          }
        };
        platform.onComplete = (method, arguments, _) async {
          if (method != 'releaseFetch' ||
              arguments['connection'] != key ||
              !prepareOutage) {
            return;
          }
          released.complete();
          await resume.future;
        };
        final older = cursor('old', () async {
          requests++;
          throw StateError('Synthetic provider failure.');
        }, observed: platform);
        if (missingPair) {
          // Prime RAM with the confirmed row without writing a new snapshot.
          expect(
            (await older.load()).accounts.single.status,
            ProviderStatus.stale,
          );
        }
        prepareOutage = true;
        final pending = CapturedDashboardLoad.capture(
          () => automatic().run(older.load),
        );
        try {
          await waitForHold(released, pending);
          expect(admissionFailed, isTrue);
          expect(requests, missingPair ? 1 : 0);
          final advanceFloor = scenario == 'advanced floor';
          if (advanceFloor || sameInstant || scenario == 'replaced payload') {
            if (!sameInstant) await setClock(nextAt);
            final newer = cursor('newer', () async => 70);
            if (advanceFloor) {
              await bridge.invoke('test', 'failCommit', {'value': true});
            }
            try {
              expect(cursorUsage(await newer.load()), 70);
            } finally {
              await bridge.invoke('test', 'failCommit', {'value': false});
            }
            final changed = await reader.capture(expected: version);
            expect(changed.order, isNot(original.order));
            expect(changed.minimumEra, 0);
            expect(
              changed.snapshot?.generatedAt,
              advanceFloor || sameInstant ? firstAt : nextAt,
            );
            if (sameInstant) {
              expect(changed.record?.era, original.record?.era);
              expect(cursorUsage(changed.snapshot!), 70);
            }
            if (advanceFloor) {
              final retained = original.record!;
              expect(
                await reader.validSnapshot(
                  retained.snapshot.withConnectionVersions(
                    {key: version.values},
                    snapshotOrdering: {
                      key: SnapshotOrdering(
                        payload: (
                          era: retained.selectionEra,
                          generatedAtMicros: firstAt.microsecondsSinceEpoch,
                        ),
                      ),
                    },
                  ),
                ),
                isTrue,
              );
            }
          }
          resume.complete();
          final result = await pending;
          expect(selectionReads, 0);
          expect(result.connectionVersions[key], version.values);
          final order = result.snapshotOrdering[key]!;
          if (scenario == 'unchanged payload') {
            final retained = result.value;
            expect(
              retained.syncIssue,
              DashboardSyncIssue.credentialUnavailable,
            );
            expect(retained.accounts.single.status, ProviderStatus.stale);
            expect(retained.accounts.single.today.spent?.minorUnits, 40);
            expect(await older.isSnapshotCurrent(retained), isTrue);
          } else {
            final failure = result.loadException!;
            expect(failure.issue, DashboardSyncIssue.credentialUnavailable);
            expect(
              failure.reportingOutcomes.single.category,
              ReportingOutcomeCategory.localReadFailure,
            );
            expect(order.selectionUnverified, isTrue);
            expect(await older.isFailureCurrent(failure), isFalse);
            expect(
              order.emptyCacheOrder,
              missingPair ? isNull : original.order,
            );
          }
          expect(
            order.payload?.generatedAtMicros,
            firstAt.microsecondsSinceEpoch,
          );
        } finally {
          if (!resume.isCompleted) resume.complete();
          await pending;
        }
      });
    }

    test(
      'a pre-admission outage keeps the paired row over equal RAM',
      () async {
        final key = cursorId.storageKey;
        final reader = cache('reader', key);
        final credentialStore = store(bridge.platform('seed'));
        await credentialStore.writeSecret(cursorId, 'synthetic-session');
        final version = (await credentialStore.readVersion(cursorId))!;
        await setClock(firstAt);
        var requests = 0;
        final older = cursor('old', () async {
          requests++;
          return 40;
        });
        expect(cursorUsage(await older.load()), 40);
        final newer = await cursor('newer', () async => 70).load();
        expect(cursorUsage(newer), 70);
        final paired = await reader.capture(expected: version);
        expect(paired.record?.era, 0);
        expect(paired.snapshot?.generatedAt, firstAt);

        final poll = AutomaticPollContext(
          readInterval:
              () async => throw StateError('Synthetic cadence failure.'),
        );
        final retained = await poll.run(older.load);
        expect(requests, 1);
        expect(retained.syncIssue, DashboardSyncIssue.credentialUnavailable);
        expect(retained.accounts.single.status, ProviderStatus.stale);
        expect(cursorUsage(retained), 70);
        expect(retained.connectionVersions[key], version.values);
        expect(retained.snapshotOrdering[key]?.emptyCacheOrder, paired.order);
        expect(await older.isSnapshotCurrent(retained), isTrue);
      },
    );

    for (final restart in [false, true]) {
      test(
        'Cursor manual rollback accepts fresh Dashboard usage (${restart ? 'recreated' : 'warm'} cache)',
        () async {
          await store(
            bridge.platform('ui'),
          ).writeSecret(cursorId, 'synthetic-session');
          var used = 40;
          var repository = cursor('ui', () async => used);
          await setClock(fastAt);
          expect(cursorUsage(await repository.load()), 40);
          expect(
            cursorUsage(
              (await cache('reader', cursorId.storageKey).capture()).snapshot!,
            ),
            40,
          );
          if (restart) {
            await bridge.invoke('test', 'restart', {});
            repository = cursor('recreated', () async => used);
          }
          await setClock(correctedAt);
          used = 70;
          final dashboard = await repository.load();
          // Keep this first corrected assertion replayable with the parent's
          // original production code and bridge.
          expect(
            cursorUsage(dashboard),
            70,
            reason: 'Dashboard must show corrected Cursor usage',
          );
          expect(dashboard.generatedAt, correctedAt);
          final watch = jsonDecode(
            WatchDashboardSummaryPayload.fromSnapshot(
              dashboard,
              const WatchRingPreferences(selectedIds: [cursorOwnPoolId]),
              clock: correctedAt,
            ).encode(),
          );
          final ring = (watch['rings'] as List).single as Map;
          expect(ring['id'], cursorOwnPoolId);
          expect(ring['usedPercent'], 70);
          final widget = buildPhoneWidgetPayload(
            dashboard,
            const PhoneWidgetPreferences(selectedIds: [cursorOwnPoolId]),
          );
          expect(widget.rows.single.remainingPercent, 30);
          final corrected = await coldCursor();
          expect(cursorUsage(corrected), 70);
          expect(corrected.generatedAt, correctedAt);
          await setClock(nextAt);
          final refreshed = await cursor('recreated', () async => 80).load();
          expect(cursorUsage(refreshed), 80);
          expect(refreshed.generatedAt, nextAt);
          expect(cursorUsage(await coldCursor()), 80);
        },
      );
    }

    for (final failCommit in [false, true]) {
      test(
        'a late fast-clock write follows the corrected era (commit failure: $failCommit)',
        () async {
          await store(
            bridge.platform('seed'),
          ).writeSecret(cursorId, 'synthetic-session');
          final seedAt = firstAt.subtract(const Duration(minutes: 1));
          await setClock(seedAt);
          expect(cursorUsage(await cursor('seed', () async => 40).load()), 40);
          await setClock(firstAt);

          final httpEntered = Completer<void>();
          final httpReply = Completer<int>();
          final writeEntered = Completer<void>();
          final releaseWrite = Completer<void>();
          final platform = ObservingCachePlatform(bridge.platform('late'));
          var released = false;
          platform.onComplete = (method, arguments, _) {
            if (method == 'releaseFetch' &&
                arguments['connection'] == cursorId.storageKey) {
              released = true;
            }
          };
          platform.beforeInvoke = (method, _) async {
            if (method == 'writeSnapshot') {
              writeEntered.complete();
              await releaseWrite.future;
            }
          };
          final late = cursor('late', () {
            httpEntered.complete();
            return httpReply.future;
          }, observed: platform);
          final pending = CapturedDashboardLoad.capture(late.load);
          try {
            await waitForHold(httpEntered, pending);
            await setClock(fastAt);
            httpReply.complete(60);
            await waitForHold(writeEntered, pending);
            expect(released, isTrue);
            await setClock(correctedAt);
            final accepting = cursor('corrected', () async => 70);
            if (failCommit) {
              await bridge.invoke('test', 'failCommit', {'value': true});
            }
            expect(cursorUsage(await accepting.load()), 70);
            await bridge.invoke('test', 'failCommit', {'value': false});
            releaseWrite.complete();
            final result = await pending;
            if (failCommit) {
              expect(() => result.value, throwsA(superseded));
            } else {
              expect(cursorUsage(result.value), 70);
              expect(result.value.generatedAt, correctedAt);
            }
            final durable = await coldCursor();
            expect(cursorUsage(durable), failCommit ? 40 : 70);
            expect(durable.generatedAt, failCommit ? seedAt : correctedAt);
          } finally {
            if (!httpReply.isCompleted) httpReply.complete(60);
            if (!releaseWrite.isCompleted) releaseWrite.complete();
            await pending;
            await bridge.invoke('test', 'failCommit', {'value': false});
          }
        },
      );
    }

    for (final (failFetch, failCommit) in [
      (false, false),
      (false, true),
      (true, false),
      (true, true),
    ]) {
      test('a refresh rechecks its era after waiting for a sibling '
          '(fetch failure: $failFetch, commit failure: $failCommit)', () async {
        await store(
          bridge.platform('initial'),
        ).writeSecret(cursorId, 'synthetic-session');
        await setClock(fastAt);
        if (failFetch) {
          final seed = await cursor('seed', () async => 40).load();
          expect(cursorUsage(seed), 40);
        }
        final selected = Completer<void>();
        final sibling = Completer<DashboardSnapshot>();
        final siblingSnapshot = _snapshot(
          'openai',
          ProviderConnections.openAiPlatform.storageKey,
          firstAt,
          100,
        );
        final platform = ObservingCachePlatform(bridge.platform('initial'));
        platform.onComplete = (method, _, _) {
          if (method == 'validAll' && !selected.isCompleted) {
            selected.complete();
          }
        };
        final initial = cursor(
          'initial',
          () async {
            if (failFetch) throw StateError('Synthetic fetch failure.');
            return 40;
          },
          observed: platform,
          fallback: _HeldDashboardRepository(sibling.future),
        );
        final pending = CapturedDashboardLoad.capture(initial.load);
        try {
          await waitForHold(selected, pending);
          await setClock(correctedAt);
          if (failCommit) {
            await bridge.invoke('test', 'failCommit', {'value': true});
          }
          final correcting = cursor('corrected', () async => 70);
          final corrected = await correcting.load();
          expect(cursorUsage(corrected), 70);
          expect(await correcting.isSnapshotCurrent(corrected), isTrue);
          await bridge.invoke('test', 'failCommit', {'value': false});
          sibling.complete(siblingSnapshot);
          final result = await pending;
          if (failCommit) {
            DashboardLoadException? failure;
            try {
              result.value;
            } on DashboardLoadException catch (error) {
              failure = error;
            }
            expect(failure, superseded);
            expect(await initial.isFailureCurrent(failure!), isFalse);
          } else {
            expect(cursorUsage(result.value), 70);
            expect(result.value.accounts, hasLength(2));
            expect(result.value.syncIssue, isNull);
            expect(await initial.isSnapshotCurrent(result.value), isTrue);
          }
          expect(cursorUsage(await coldCursor()), failCommit ? 40 : 70);
        } finally {
          if (!sibling.isCompleted) sibling.complete(siblingSnapshot);
          await pending;
          await bridge.invoke('test', 'failCommit', {'value': false});
        }
      });
    }

    for (final (replaceCredential, failFetch) in [
      (false, true),
      (true, true),
      (true, false),
    ]) {
      final scenario = replaceCredential ? ' after credential replacement' : '';
      test(
        failFetch
            ? 'a failed queued refresh recovers the corrected usage$scenario'
            : 'a successful queued refresh uses the replacement credential',
        () async {
          await store(
            bridge.platform('seed'),
          ).writeSecret(cursorId, 'synthetic-session');
          await setClock(fastAt);
          expect(cursorUsage(await cursor('seed', () async => 40).load()), 40);

          final queued = Completer<void>();
          final resume = Completer<void>();
          final platform = ObservingCachePlatform(bridge.platform('queued'));
          platform.beforeInvoke = (method, arguments) async {
            if (method == 'acquireFetch' &&
                arguments['connection'] == cursorId.storageKey) {
              // Cursor has captured 40%, and its fetch has yet to be admitted.
              queued.complete();
              await resume.future;
            }
          };
          final refreshing = cursor('queued', () async {
            if (failFetch) {
              throw const ProviderReportingException(
                ProviderReportingFailure.rateLimited,
              );
            }
            return 80;
          }, observed: platform);
          final pending = CapturedDashboardLoad.capture(refreshing.load);
          try {
            await waitForHold(queued, pending);
            if (replaceCredential) {
              await store(
                bridge.platform('corrected'),
              ).writeSecret(cursorId, 'synthetic-replacement');
            }
            await setClock(correctedAt);
            final corrected = await cursor('corrected', () async => 70).load();
            expect(cursorUsage(corrected), 70);
            resume.complete();
            final snapshot = (await pending).value;
            expect(cursorUsage(snapshot), failFetch ? 70 : 80);
            expect(snapshot.generatedAt, correctedAt);
            expect(await refreshing.isSnapshotCurrent(snapshot), isTrue);
            if (failFetch) {
              expect(snapshot.accounts.single.status, ProviderStatus.stale);
              expect(snapshot.syncIssue, DashboardSyncIssue.rateLimited);
            } else {
              expect(snapshot.syncIssue, isNull);
              final durable =
                  await cache('corrected', cursorId.storageKey).capture();
              expect(cursorUsage(durable.snapshot!), 80);
            }
          } finally {
            if (!resume.isCompleted) resume.complete();
            await pending;
          }
        },
      );
    }

    for (final correctedCommitFails in [false, true]) {
      test('a failed payload reread uses the stale data era '
          '(failed corrected commit: $correctedCommitFails)', () async {
        const id = 'openai.platform';
        await credentials('seed', id).write('synthetic-openai-key');
        await setClock(fastAt);
        await owned('seed', id, (_) async {
          return _snapshot('openai', id, fastAt, 400).toJsonString();
        }).load();
        await setClock(correctedAt);
        Future<DashboardSnapshot> refreshCorrected() =>
            owned('corrected', id, (_) async {
              return _snapshot('openai', id, correctedAt, 700).toJsonString();
            }).load();

        if (correctedCommitFails) {
          await bridge.invoke('test', 'failCommit', {'value': true});
          try {
            final corrected = await refreshCorrected();
            expect(corrected.accounts.single.today.spent?.minorUnits, 700);
          } finally {
            await bridge.invoke('test', 'failCommit', {'value': false});
          }
        }

        var readsUntilFailure = 1;
        var rereadFailed = false;
        final platform = ObservingCachePlatform(bridge.platform('failing'));
        platform.beforeInvoke = (method, arguments) {
          if (method != 'readSnapshot' || arguments['forSelection'] != true) {
            return;
          }
          readsUntilFailure--;
          if (readsUntilFailure == 0) {
            rereadFailed = true;
            throw StateError('Synthetic payload reread failure.');
          }
        };
        final failing = owned(
          'failing',
          id,
          (_) async => throw StateError('Synthetic provider failure.'),
          cachePlatform: platform,
          fallback: ValueDashboardRepository(
            _snapshot('claude', 'anthropic.platform', firstAt, 100),
          ),
        );
        final result = await CapturedDashboardLoad.capture(
          () => automatic().run(failing.load),
        );
        expect(rereadFailed, isTrue);
        if (correctedCommitFails) {
          expect(() => result.value, throwsA(superseded));
          final skipped = automatic();
          await expectLater(skipped.run(failing.load), throwsA(superseded));
          expect(skipped.whollySkipped, isTrue);
        } else {
          final stale = result.value;
          final retained = stale.accounts.singleWhere(
            (account) => account.connection == id,
          );
          expect(stale.accounts, hasLength(2));
          expect(retained.today.spent?.minorUnits, 400);
          expect(retained.status, ProviderStatus.stale);
          expect(
            stale.reportingOutcomes.single.category,
            ReportingOutcomeCategory.rateLimited,
          );
          expect(await failing.isSnapshotCurrent(stale), isTrue);
          readsUntilFailure = 2;
          rereadFailed = false;
          final poll = automatic();
          final skipped = await poll.run(failing.load);
          expect(rereadFailed, isTrue);
          expect(poll.whollySkipped, isTrue);
          expect(
            skipped.accounts
                .singleWhere((account) => account.connection == id)
                .today
                .spent
                ?.minorUnits,
            400,
          );
          expect(
            skipped.reportingOutcomes.single.freshness,
            ReportingOutcomeFreshness.stale,
          );
          await refreshCorrected();
          expect(await failing.isSnapshotCurrent(stale), isFalse);
        }
      });
    }

    test('a rejected final era check reselects the confirmed winner', () async {
      await store(
        bridge.platform('initial'),
      ).writeSecret(cursorId, 'synthetic-session');
      await setClock(fastAt);
      final beforeValidation = Completer<void>();
      final resume = Completer<void>();
      final platform = ObservingCachePlatform(bridge.platform('initial'));
      var selectionReads = 0;
      platform.onComplete = (method, arguments, _) async {
        if (method != 'readSnapshot' || arguments['forSelection'] != true) {
          return;
        }
        selectionReads++;
        if (selectionReads == 2) {
          // Native has returned the old floor. Hold its reply to Dart until
          // the corrected write has committed, before final validation.
          beforeValidation.complete();
          await resume.future;
        }
      };
      var requests = 0;
      final initial = cursor('initial', () async {
        requests++;
        return 40;
      }, observed: platform);
      final pending = CapturedDashboardLoad.capture(initial.load);
      try {
        await waitForHold(beforeValidation, pending);
        await setClock(correctedAt);
        final corrected = await cursor('corrected', () async => 70).load();
        expect(cursorUsage(corrected), 70);
        resume.complete();
        final accepted = (await pending).value;
        expect(cursorUsage(accepted), 70);
        expect(accepted.generatedAt, correctedAt);
        expect(await initial.isSnapshotCurrent(accepted), isTrue);
        expect(requests, 1);
        expect(cursorUsage(await coldCursor()), 70);
      } finally {
        if (!resume.isCompleted) resume.complete();
        await pending;
      }
    });

    for (final (hasCachedPayload, failRead, failInitialRead) in [
      (false, false, false),
      (false, true, false),
      (false, true, true),
      (true, false, false),
    ]) {
      test('failed fallback checks a newer record in the same era '
          '(cached payload: $hasCachedPayload, read failure: $failRead, '
          'initial read failure: $failInitialRead)', () async {
        const id = 'openai.platform';
        final newerAt = firstAt.add(const Duration(microseconds: 1));
        await credentials('initial', id).write('synthetic-openai-key');
        await setClock(firstAt);
        if (hasCachedPayload) {
          await owned('initial', id, (_) async {
            return _snapshot('openai', id, firstAt, 400).toJsonString();
          }).load();
        }

        final beforeValidation = Completer<void>();
        final resume = Completer<void>();
        final platform = ObservingCachePlatform(bridge.platform('failing'));
        platform.beforeInvoke = (method, arguments) {
          if (failInitialRead &&
              method == 'readSnapshot' &&
              arguments['forSelection'] != true) {
            throw StateError('Synthetic initial payload read failure.');
          }
        };
        platform.onComplete = (method, arguments, _) async {
          if (method == 'readSnapshot' &&
              arguments['forSelection'] == true &&
              !beforeValidation.isCompleted) {
            beforeValidation.complete();
            await resume.future;
            if (failRead) throw StateError('Synthetic payload reread failure.');
          }
        };
        final failing = owned(
          'failing',
          id,
          (_) async => throw StateError('Synthetic provider failure.'),
          cachePlatform: platform,
          fallback: ValueDashboardRepository(
            _snapshot('claude', 'anthropic.platform', nextAt, 100),
          ),
        );
        final pending = CapturedDashboardLoad.capture(failing.load);
        try {
          await waitForHold(beforeValidation, pending);
          final newer =
              await owned('newer', id, (_) async {
                return _snapshot('openai', id, newerAt, 700).toJsonString();
              }).load();
          expect(newer.accounts.single.today.spent?.minorUnits, 700);
          resume.complete();
          final captured = await pending;
          if (failInitialRead) {
            expect(() => captured.value, throwsA(superseded));
            final proof = DashboardSnapshot.empty().withConnectionVersions(
              captured.connectionVersions,
              snapshotOrdering: captured.snapshotOrdering,
            );
            expect(await failing.isSnapshotCurrent(proof), isFalse);
            return;
          }
          final merged = captured.value;
          final retained = merged.accounts.singleWhere(
            (account) => account.connection == id,
          );
          expect(merged.generatedAt, nextAt);
          expect(retained.today.spent?.minorUnits, 700);
          expect(retained.lastSuccessfulSyncAt, newerAt);
          expect(retained.status, ProviderStatus.stale);
          expect(
            merged.reportingOutcomes.single.category,
            ReportingOutcomeCategory.rateLimited,
          );
          expect(await failing.isSnapshotCurrent(merged), isTrue);
        } finally {
          if (!resume.isCompleted) resume.complete();
          await pending;
        }
      });
    }

    test('a nested supersession fences a partial aggregate', () async {
      const innerId = 'openai.platform';
      const outerId = 'anthropic.platform';
      await credentials('initial', innerId).write('synthetic-openai-key');
      await credentials('initial', outerId).write('synthetic-anthropic-key');
      await setClock(fastAt);
      final selected = Completer<void>();
      final sibling = Completer<DashboardSnapshot>();
      final platform = ObservingCachePlatform(bridge.platform('initial'));
      platform.onComplete = (method, _, _) {
        if (method == 'validAll' && !selected.isCompleted) selected.complete();
      };
      final inner = owned(
        'initial',
        innerId,
        (_) async => _snapshot('openai', innerId, fastAt, 400).toJsonString(),
        fallback: _HeldDashboardRepository(sibling.future),
        cachePlatform: platform,
      );
      final outer = owned(
        'initial',
        outerId,
        (_) async => _snapshot('claude', outerId, fastAt, 100).toJsonString(),
        fallback: inner,
      );
      final pending = CapturedDashboardLoad.capture(outer.load);
      try {
        await waitForHold(selected, pending);
        await setClock(correctedAt);
        await bridge.invoke('test', 'failCommit', {'value': true});
        final corrected =
            await owned('corrected', innerId, (_) async {
              return _snapshot(
                'openai',
                innerId,
                correctedAt,
                700,
              ).toJsonString();
            }).load();
        expect(corrected.accounts.single.today.spent?.minorUnits, 700);
        await bridge.invoke('test', 'failCommit', {'value': false});
        sibling.complete(DashboardSnapshot.empty());
        final result = await pending;
        expect(() => result.value, throwsA(superseded));
      } finally {
        if (!sibling.isCompleted) sibling.complete(DashboardSnapshot.empty());
        await pending;
        await bridge.invoke('test', 'failCommit', {'value': false});
      }
    });

    test('a cadence skip retains the corrected snapshot era', () async {
      const id = 'openai.platform';
      await credentials('seed', id).write('synthetic-openai-key');
      await setClock(fastAt);
      final seed = owned('seed', id, (_) async {
        return _snapshot('openai', id, fastAt, 400).toJsonString();
      });
      await automatic().run(seed.load);

      final selected = Completer<void>();
      final sibling = Completer<DashboardSnapshot>();
      final platform = ObservingCachePlatform(bridge.platform('skipped'));
      platform.onComplete = (method, _, _) {
        if (method == 'validAll' && !selected.isCompleted) selected.complete();
      };
      var requests = 0;
      final skipping = owned(
        'skipped',
        id,
        (_) async {
          requests++;
          return _snapshot('openai', id, fastAt, 400).toJsonString();
        },
        fallback: _HeldDashboardRepository(sibling.future),
        cachePlatform: platform,
      );
      final poll = automatic();
      final pending = CapturedDashboardLoad.capture(
        () => poll.run(skipping.load),
      );
      try {
        await waitForHold(selected, pending);
        await setClock(correctedAt);
        final correcting = owned('corrected', id, (_) async {
          return _snapshot('openai', id, correctedAt, 700).toJsonString();
        });
        expect(
          (await correcting.load()).accounts.single.today.spent?.minorUnits,
          700,
        );
        sibling.complete(DashboardSnapshot.empty());
        final retained = (await pending).value;
        expect(retained.accounts.single.today.spent?.minorUnits, 700);
        expect(retained.reportingOutcomes, isEmpty);
        expect(poll.whollySkipped, isTrue);
        expect(requests, 0);
      } finally {
        if (!sibling.isCompleted) sibling.complete(DashboardSnapshot.empty());
        await pending;
      }
    });

    for (final failCorrectedCommit in [false, true]) {
      test(
        'a cacheless cadence skip qualifies retained reporting feedback '
        '(failed corrected commit and reread: $failCorrectedCommit)',
        () async {
          const id = 'openai.platform';
          await credentials('failing', id).write('synthetic-openai-key');
          await setClock(fastAt);
          final passingSibling = ValueDashboardRepository(
            _snapshot('claude', 'anthropic.platform', firstAt, 100),
          );
          var requests = 0;
          var failSelectionReads = false;
          var failedSelectionReads = 0;
          var failNextFeedbackCheck = false;
          final platform = ObservingCachePlatform(bridge.platform('failing'));
          platform.beforeInvoke = (method, arguments) {
            if (failSelectionReads &&
                method == 'readSnapshot' &&
                arguments['forSelection'] == true) {
              failedSelectionReads++;
              throw StateError('Synthetic payload reread failure.');
            }
            if (failNextFeedbackCheck &&
                method == 'validAll' &&
                (arguments['attemptClockEras'] as Map?)?[id] != null &&
                arguments['payloadOrders'] == null &&
                arguments['emptyCacheOrders'] == null) {
              failNextFeedbackCheck = false;
              throw StateError('Synthetic feedback metadata check failure.');
            }
          };
          final failing = owned(
            'failing',
            id,
            (_) async {
              requests++;
              throw StateError('Synthetic provider failure.');
            },
            fallback: passingSibling,
            cachePlatform: platform,
          );
          await automatic().run(failing.load);

          failSelectionReads = failCorrectedCommit;
          if (failSelectionReads) {
            failNextFeedbackCheck = true;
            final poll = automatic();
            final skipped = await poll.run(failing.load);
            expect(failNextFeedbackCheck, isFalse);
            expect(failedSelectionReads, greaterThanOrEqualTo(2));
            expect(poll.whollySkipped, isTrue);
            expect(skipped.accounts.single.connection, 'anthropic.platform');
            expect(skipped.reportingOutcomes, isEmpty);
            final cacheOrder = poll.skipped[id]?.cacheOrder;
            expect(cacheOrder, isNotNull);
            expect(skipped.snapshotOrdering[id]?.emptyCacheOrder, cacheOrder);
            expect(skipped.snapshotOrdering[id]?.attemptEra, isNull);
            failedSelectionReads = 0;
          }
          final ordinarySkip = await automatic().run(failing.load);
          expect(ordinarySkip.accounts.single.connection, 'anthropic.platform');
          final retained = ordinarySkip.reportingOutcomes.single;
          expect(retained.category, ReportingOutcomeCategory.rateLimited);
          expect(retained.freshness, ReportingOutcomeFreshness.current);
          expect(
            failedSelectionReads,
            failCorrectedCommit ? greaterThanOrEqualTo(2) : 0,
          );

          await setClock(correctedAt);
          if (failCorrectedCommit) {
            await bridge.invoke('test', 'failCommit', {'value': true});
          }
          try {
            final corrected =
                await owned('corrected', id, (_) async {
                  return _snapshot(
                    'openai',
                    id,
                    correctedAt,
                    700,
                  ).toJsonString();
                }).load();
            expect(corrected.accounts.single.today.spent?.minorUnits, 700);
          } finally {
            if (failCorrectedCommit) {
              await bridge.invoke('test', 'failCommit', {'value': false});
            }
          }
          failedSelectionReads = 0;
          final poll = automatic();
          final correctedSkip = await poll.run(failing.load);
          expect(
            failedSelectionReads,
            failCorrectedCommit ? greaterThanOrEqualTo(2) : 0,
          );
          expect(poll.whollySkipped, isTrue);
          if (failCorrectedCommit) {
            expect(
              correctedSkip.accounts.single.connection,
              'anthropic.platform',
            );
          } else {
            expect(
              correctedSkip.accounts
                  .singleWhere((account) => account.connection == id)
                  .today
                  .spent
                  ?.minorUnits,
              700,
            );
          }
          expect(correctedSkip.reportingOutcomes, isEmpty);
          expect(requests, 1);
        },
      );
    }

    for (final (correct, duringPublication) in [
      (false, false),
      (true, false),
      (true, true),
    ]) {
      test(
        'a cacheless cadence skip checks its ordering '
        '(correction: $correct, during publication: $duringPublication)',
        () async {
          const id = 'openai.platform';
          await credentials('seed', id).write('synthetic-openai-key');
          await setClock(fastAt);
          final seed = owned('seed', id, (_) async {
            throw StateError('Synthetic provider failure.');
          });
          await expectLater(
            automatic().run(seed.load),
            throwsA(isA<DashboardLoadException>()),
          );

          final checked = Completer<void>();
          final selectionRead = Completer<void>();
          final resume = Completer<void>();
          final sibling = Completer<DashboardSnapshot>();
          final siblingSnapshot = _snapshot(
            'claude',
            'anthropic.platform',
            firstAt,
            100,
          );
          final platform = ObservingCachePlatform(bridge.platform('skipping'));
          var reads = 0;
          platform.onComplete = (method, _, _) async {
            if (method != 'readSnapshot') return;
            reads++;
            if (reads == 2) checked.complete();
            if (reads == 3 && duringPublication) {
              // Hold the paired reply after native has confirmed the old order.
              selectionRead.complete();
              await resume.future;
            }
          };
          var requests = 0;
          final skipping = owned(
            'skipping',
            id,
            (_) async {
              requests++;
              throw StateError('Cadence should deny this request.');
            },
            fallback: _HeldDashboardRepository(sibling.future),
            cachePlatform: platform,
          );
          final poll = automatic();
          final pending = CapturedDashboardLoad.capture(
            () => poll.run(skipping.load),
          );
          Future<void> correctClockAndRefresh() async {
            await setClock(correctedAt);
            await owned('corrected', id, (_) async {
              return _snapshot('openai', id, correctedAt, 700).toJsonString();
            }).load();
          }

          try {
            await waitForHold(checked, pending);
            if (correct && !duringPublication) await correctClockAndRefresh();
            sibling.complete(siblingSnapshot);
            if (duringPublication) {
              await waitForHold(selectionRead, pending);
              await correctClockAndRefresh();
              resume.complete();
            }
            final snapshot = (await pending).value;
            expect(snapshot.accounts, hasLength(correct ? 2 : 1));
            if (correct) {
              final recovered = snapshot.accounts.singleWhere(
                (account) => account.connection == id,
              );
              expect(recovered.today.spent?.minorUnits, 700);
            }
            expect(await skipping.isSnapshotCurrent(snapshot), isTrue);
            expect(snapshot.reportingOutcomes, isEmpty);
            expect(poll.whollySkipped, isTrue);
            expect(requests, 0);
          } finally {
            if (!sibling.isCompleted) sibling.complete(siblingSnapshot);
            if (!resume.isCompleted) resume.complete();
            await pending;
          }
        },
      );
    }

    test(
      'a cacheless plan skip retains its order across fetch release',
      () async {
        await store(
          bridge.platform('seed'),
        ).writeSecret(cursorId, 'synthetic-session');
        await setClock(fastAt);
        final seed = cursor(
          'seed',
          () async => throw StateError('Synthetic fetch failure.'),
        );
        await expectLater(
          automatic().run(seed.load),
          throwsA(isA<DashboardLoadException>()),
        );

        final released = Completer<void>();
        final resume = Completer<void>();
        final sibling = Completer<DashboardSnapshot>();
        final siblingSnapshot = _snapshot(
          'openai',
          ProviderConnections.openAiPlatform.storageKey,
          firstAt,
          100,
        );
        final platform = ObservingCachePlatform(bridge.platform('skipping'));
        platform.onComplete = (method, arguments, _) async {
          if (method == 'releaseFetch' &&
              arguments['connection'] == cursorId.storageKey) {
            released.complete();
            await resume.future;
          }
        };
        var requests = 0;
        final skipping = cursor(
          'skipping',
          () async {
            requests++;
            return 40;
          },
          observed: platform,
          fallback: _HeldDashboardRepository(sibling.future),
        );
        final poll = automatic();
        final pending = CapturedDashboardLoad.capture(
          () => poll.run(skipping.load),
        );
        try {
          await waitForHold(released, pending);
          await setClock(correctedAt);
          await bridge.invoke('test', 'failCommit', {'value': true});
          final corrected = await cursor('corrected', () async => 70).load();
          expect(cursorUsage(corrected), 70);
          await bridge.invoke('test', 'failCommit', {'value': false});
          resume.complete();
          sibling.complete(siblingSnapshot);

          final result = await pending;
          expect(() => result.value, throwsA(superseded));
          expect(poll.whollySkipped, isTrue);
          expect(requests, 0);
        } finally {
          if (!resume.isCompleted) resume.complete();
          if (!sibling.isCompleted) sibling.complete(siblingSnapshot);
          await pending;
          await bridge.invoke('test', 'failCommit', {'value': false});
        }
      },
    );

    test('a lower report sample preserves the fast-clock reference', () async {
      await store(
        bridge.platform('seed'),
      ).writeSecret(cursorId, 'synthetic-session');
      await setClock(fastAt);
      expect(cursorUsage(await cursor('seed', () async => 40).load()), 40);
      final entered = Completer<void>();
      final response = Completer<int>();
      final delayed = cursor('lower-sample', () {
        entered.complete();
        return response.future;
      });
      final pending = CapturedDashboardLoad.capture(delayed.load);
      try {
        await waitForHold(entered, pending);
        await setClock(correctedAt);
        response.complete(60);
        expect(cursorUsage((await pending).value), 40);
        expect(
          cursorUsage(await cursor('corrected', () async => 70).load()),
          70,
        );
        final durable = await coldCursor();
        expect(cursorUsage(durable), 70);
        expect(durable.generatedAt, correctedAt);
      } finally {
        if (!response.isCompleted) response.complete(60);
        await pending;
      }
    });

    test('an unstamped RAM result cannot displace era zero', () async {
      const id = 'openai.platform';
      await credentials('legacy', id).write('synthetic-admin-key');
      var failFetch = false;
      final legacy = repository('legacy', id, () async {
        if (failFetch) throw StateError('Synthetic fetch failure.');
        return _snapshot('openai', id, fastAt, 400).toJsonString();
      });
      await setClock(fastAt);
      await bridge.invoke('test', 'failCommit', {'value': true});
      final DashboardSnapshot unconfirmed;
      try {
        unconfirmed = await legacy.load();
      } finally {
        await bridge.invoke('test', 'failCommit', {'value': false});
      }
      expect(unconfirmed.accounts.single.today.spent?.minorUnits, 400);

      await setClock(correctedAt);
      final corrected =
          await owned('corrected', id, (_) async {
            return _snapshot('openai', id, correctedAt, 700).toJsonString();
          }).load();
      expect(corrected.accounts.single.today.spent?.minorUnits, 700);
      failFetch = true;
      final stale = await legacy.load();
      expect(stale.accounts.single.today.spent?.minorUnits, 700);
      expect(stale.accounts.single.status, ProviderStatus.stale);
      failFetch = false;
      final refreshed = await legacy.load();
      expect(refreshed.accounts.single.today.spent?.minorUnits, 700);
      expect(await legacy.isSnapshotCurrent(unconfirmed), isFalse);
    });

    test(
      'failed final validation cannot seed later in-memory recovery',
      () async {
        final key = cursorId.storageKey;
        await store(
          bridge.platform('seed'),
        ).writeSecret(cursorId, 'synthetic-session');
        await setClock(firstAt);
        expect(cursorUsage(await cursor('seed', () async => 40).load()), 40);

        final platform = ObservingCachePlatform(bridge.platform('refresh'));
        var providerFails = false;
        final refreshing = cursor('refresh', () async {
          if (providerFails) throw StateError('Synthetic provider failure.');
          return 70;
        }, observed: platform);
        Object? write;
        Object? validation;
        Map<String, Object?>? interruptedProof;
        var checks = 0;
        platform.onComplete = (method, arguments, result) {
          if (method == 'writeSnapshot' && arguments['connection'] == key) {
            write = result;
          }
          final payload = (arguments['payloadOrders'] as Map?)?[key] as Map?;
          if (method == 'validAll' &&
              payload?['generatedAt'] == nextAt.microsecondsSinceEpoch &&
              ++checks == 2) {
            validation = result;
            interruptedProof = Map.of(arguments);
            throw StateError('Synthetic native validation reply failure.');
          }
        };

        await setClock(nextAt);
        await bridge.invoke('test', 'failCommit', {'value': true});
        try {
          await expectLater(refreshing.load(), throwsA(superseded));
        } finally {
          await bridge.invoke('test', 'failCommit', {'value': false});
        }
        expect(write, containsPair('status', 'storageFailure'));
        expect(validation, isTrue);
        expect(
          await bridge.invoke('reader', 'validAll', interruptedProof!),
          isTrue,
        );

        providerFails = true;
        final fallback = await refreshing.load();
        expect(cursorUsage(fallback), 40);
        expect(fallback.accounts.single.status, ProviderStatus.stale);
        expect(await refreshing.isSnapshotCurrent(fallback), isTrue);
      },
    );

    for (final failRead in [false, true]) {
      test(
        'a skipped older write cannot publish after a failed corrected commit (read failure: $failRead)',
        () async {
          await store(
            bridge.platform('seed'),
          ).writeSecret(cursorId, 'synthetic-session');
          final confirmedAt = fastAt.add(const Duration(microseconds: 500));
          await setClock(confirmedAt);
          expect(cursorUsage(await cursor('seed', () async => 40).load()), 40);
          await setClock(fastAt.add(const Duration(microseconds: 200)));
          final released = Completer<void>();
          final resumeSelection = Completer<void>();
          final platform = ObservingCachePlatform(bridge.platform('older'));
          var writes = 0;
          platform.beforeInvoke = (method, _) {
            if (method == 'writeSnapshot') writes++;
            if (method == 'readSnapshot' && failRead && released.isCompleted) {
              throw StateError('Synthetic snapshot read failure.');
            }
          };
          platform.onComplete = (method, arguments, _) async {
            if (method == 'releaseFetch' &&
                arguments['connection'] == cursorId.storageKey) {
              released.complete();
              await resumeSelection.future;
            }
          };
          final older = cursor('older', () async => 60, observed: platform);
          final pending = CapturedDashboardLoad.capture(older.load);
          try {
            await waitForHold(released, pending);
            await setClock(correctedAt);
            await bridge.invoke('test', 'failCommit', {'value': true});
            final accepting = await cursor('corrected', () async => 70).load();
            expect(cursorUsage(accepting), 70);
            await bridge.invoke('test', 'failCommit', {'value': false});
            resumeSelection.complete();
            final result = await pending;
            expect(() => result.value, throwsA(superseded));
            expect(
              writes,
              0,
              reason: 'The older candidate bypasses native write CAS',
            );
            final durable = await coldCursor();
            expect(cursorUsage(durable), 40);
            expect(durable.generatedAt, confirmedAt);
          } finally {
            if (!resumeSelection.isCompleted) resumeSelection.complete();
            await pending;
            await bridge.invoke('test', 'failCommit', {'value': false});
          }
        },
      );
    }

    test(
      'reporting release keeps its clock sample when selection fails',
      () async {
        const id = ProviderConnections.openAiPlatform;
        await store(
          bridge.platform('seed'),
        ).writeSecret(id, 'synthetic-admin-key');
        await setClock(firstAt);
        final platform = ObservingCachePlatform(bridge.platform('interrupted'));
        platform.beforeInvoke = (method, arguments) {
          if (method == 'writeSnapshot' ||
              (method == 'readSnapshot' && arguments['forSelection'] == true)) {
            throw StateError('Synthetic snapshot I/O failure.');
          }
        };
        final interrupted = owned('interrupted', id.storageKey, (_) async {
          await setClock(fastAt);
          return _snapshot('openai', id.storageKey, fastAt, 900).toJsonString();
        }, cachePlatform: platform);
        await expectLater(interrupted.load(), throwsA(superseded));

        await setClock(correctedAt);
        final corrected =
            await owned(
              'corrected',
              id.storageKey,
              (_) async =>
                  _snapshot(
                    'openai',
                    id.storageKey,
                    correctedAt,
                    400,
                  ).toJsonString(),
            ).load();
        expect(corrected.accounts.single.today.spent?.minorUnits, 400);
        final version =
            (await store(bridge.platform('reader')).readVersion(id))!;
        expect(
          await bridge.invoke('reader', 'readSnapshot', {
            'connection': id.storageKey,
            'expected': version.values,
            'ordered': true,
          }),
          containsPair('minimumEra', 1),
        );
      },
    );

    test(
      'OpenAI reporting commits the clock reference before fetch release',
      () async {
        const id = ProviderConnections.openAiPlatform;
        final platform = ObservingCachePlatform(bridge.platform('reporting'));
        await store(platform).writeSecret(id, 'synthetic-admin-key');
        final releaseEntered = Completer<void>();
        final releaseFetch = Completer<void>();
        platform.onComplete = (method, _, _) async {
          if (method == 'stampFetch') await setClock(fastAt);
        };
        platform.beforeInvoke = (method, _) async {
          if (method == 'releaseFetch') {
            releaseEntered.complete();
            await releaseFetch.future;
          }
        };
        DashboardRepository reporting(
          String owner,
          ConnectionCachePlatform platform,
          String cost,
        ) => openAiDashboardRepository(
          credentialStore: store(platform),
          cache: cache(owner, id.storageKey, platform: platform),
          client: OpenAiReportingClient(
            http: ProviderReportingHttp(
              transport: _HistoryReportingTransport(now, cost: cost),
            ),
          ),
          clock: () => now,
          logger: const _SilentLogger(),
        );

        await setClock(firstAt);
        final pending = CapturedDashboardLoad.capture(
          reporting('reporting', platform, '9.00').load,
        );
        try {
          await waitForHold(releaseEntered, pending);
          final confirmed =
              (await cache('reader', id.storageKey).capture()).snapshot!;
          expect(confirmed.generatedAt, fastAt);
          expect(confirmed.accounts.single.month.spent?.minorUnits, 900);
          // This instant is after admission and before the committed report sample.
          await setClock(correctedAt);
          await bridge.invoke('test', 'restart', {});
          final corrected =
              await reporting(
                'recreated',
                bridge.platform('recreated'),
                '4.00',
              ).load();
          expect(corrected.generatedAt, correctedAt);
          expect(corrected.accounts.single.month.spent?.minorUnits, 400);
          final durable =
              (await cache('reader', id.storageKey).capture()).snapshot!;
          expect(durable.generatedAt, correctedAt);
          expect(durable.accounts.single.month.spent?.minorUnits, 400);
        } finally {
          if (!releaseFetch.isCompleted) releaseFetch.complete();
          await pending;
        }
      },
    );
  });

  test(
    'six real Rust normalizers retain phone and cache source ownership',
    () async {
      String fixture(String path) =>
          File('../../fixtures/providers/$path').readAsStringSync();
      final cases = [
        (
          ProviderConnections.codexPlan,
          'codex',
          'codex-local',
          normalizeCodexReportJson,
          fixture('codex/report.json'),
        ),
        (
          ProviderConnections.openAiPlatform,
          'openai',
          'openai-local',
          normalizeOpenAiReportJson,
          jsonEncode({
            'accountId': 'openai-local',
            'generatedAt': '2026-07-19T12:00:00Z',
            'todayStart': 1784419200,
            'weekStart': 1783900800,
            'monthStart': 1782864000,
            'usagePages': [fixture('openai/usage_completions.json')],
            'costPages': [fixture('openai/costs.json')],
          }),
        ),
        (
          ProviderConnections.claudePlan,
          'claude',
          'claude-local',
          normalizeClaudeReportJson,
          fixture('claude/oauth_usage.json'),
        ),
        (
          ProviderConnections.anthropicPlatform,
          'claude',
          'anthropic-local',
          normalizeAnthropicReportJson,
          jsonEncode({
            'accountId': 'anthropic-local',
            'generatedAt': '2026-07-19T12:00:00Z',
            'capturedEndMicros': 1784462400000000,
            'todayStart': '2026-07-19T00:00:00Z',
            'weekStart': '2026-07-13T00:00:00Z',
            'monthStart': '2026-07-01T00:00:00Z',
            'usagePages': [fixture('claude/usage_report.json')],
            'costPages': [fixture('claude/cost_report.json')],
          }),
        ),
        (
          ProviderConnections.cursorPlan,
          'cursor',
          'cursor-local',
          normalizeCursorPlanReportJson,
          fixture('cursor/usage_summary.json'),
        ),
        (
          ProviderConnections.cursorPlatform,
          'cursor',
          'cursor-team-local',
          normalizeCursorPlatformReportJson,
          jsonEncode({
            'accountId': 'cursor-team-local',
            'generatedAt': '2026-07-19T12:00:00Z',
            'requestStartMs': 1782864000000,
            'endExclusiveMs': 1784462400000,
            'todayStartMs': 1784419200000,
            'weekStartMs': 1783900800000,
            'monthStartMs': 1782864000000,
            'dailyUsagePages': [fixture('cursor/daily_usage.json')],
            'usageEventPages': [fixture('cursor/usage_events.json')],
          }),
        ),
      ];
      final normalized = <String>[];
      final expectedAccounts = <Map<String, dynamic>>[];
      for (final (id, tag, accountId, normalize, report) in cases) {
        final snapshot = DashboardSnapshot.fromJsonString(normalize(report));
        final roundTrip = DashboardSnapshot.fromJsonString(
          snapshot.toJsonString(),
        );
        expect(roundTrip.toJson(), snapshot.toJson());
        final account = roundTrip.accounts.single;
        expect(account.provider, tag);
        expect(account.connection, id.storageKey);
        expect(account.accountId, accountId);
        final snapshots = cache('writer', id.storageKey);
        expect(snapshots.owns(roundTrip), isTrue);
        await credentials(
          'writer',
          id.storageKey,
        ).write('synthetic-${id.storageKey}');
        final version =
            (await credentials('writer', id.storageKey).read())!.version;
        expect(await snapshots.store(roundTrip, version), isTrue);
        final retained =
            (await cache('reader', id.storageKey).capture()).snapshot!;
        expect(
          retained.accounts.single.historyOwner,
          HistoryOwner.fromVersion(id.storageKey, version),
        );
        expect(
          retained.accounts.single.allowances.map((value) => value.toJson()),
          account.allowances.map((value) => value.toJson()),
        );
        expect(await snapshots.validSnapshot(retained), isTrue);
        normalized.add(retained.toJsonString());
        expectedAccounts.add(retained.accounts.single.toJson());

        for (final field in ['provider', 'connection']) {
          final wrong = roundTrip.toJson();
          final wrongAccount = (wrong['accounts'] as List).single as Map;
          wrongAccount[field] =
              field == 'provider'
                  ? 'mock'
                  : ProviderConnectionId(
                    provider: id.provider,
                    kind:
                        id.kind == ConnectionKind.plan
                            ? ConnectionKind.platform
                            : ConnectionKind.plan,
                  ).storageKey;
          final rejected = DashboardSnapshot.fromJson(wrong);
          expect(
            snapshots.owns(rejected),
            isFalse,
            reason: '${id.storageKey}: wrong $field',
          );
          await expectLater(
            snapshots.store(rejected, version),
            throwsFormatException,
          );
        }
      }
      final merged = DashboardSnapshot.fromJsonString(
        mergeDashboardSnapshotsJson(normalized),
      );
      expect(
        merged.accounts.map((account) => account.toJson()),
        expectedAccounts,
      );
      expect(
        DashboardSnapshot.fromJsonString(merged.toJsonString()).toJson(),
        merged.toJson(),
      );
    },
  );

  DashboardRepository codex(
    String owner,
    ConnectionReportLoader load, {
    ConnectionCachePlatform? platform,
    ReportNormalizer normalizeReport = normalizeCodexReportJson,
  }) => codexDashboardRepository(
    accountService: const EmptyCodexAccountService(),
    fallback: ValueDashboardRepository(
      _snapshot('openai', 'openai.platform', DateTime.utc(2026, 11, 14, 9), 1),
    ),
    cache: ConnectionSnapshotCache(
      connection: 'openai.plan',
      platform: platform ?? bridge.platform(owner),
      readCredentialVersion:
          () async => (await credentials(owner, 'openai.plan').read())?.version,
    ),
    loadReport: load,
    normalizeReport: normalizeReport,
    mergeSnapshots: mergeDashboardSnapshotsJson,
    logger: const _SilentLogger(),
  );

  group('connection absence ownership', () {
    final at = DateTime.utc(2026, 11, 18, 12);
    const a = ProviderConnections.cursorPlan;
    const b = ProviderConnections.openAiPlatform;
    SecureProviderCredentialStore keys(String owner) =>
        SecureProviderCredentialStore(
          storage: secure,
          platform: bridge.platform(owner),
        );
    DashboardRepository live(
      String owner, {
      ConnectionCachePlatform? platform,
    }) {
      final native = platform ?? bridge.platform(owner);
      final store = SecureProviderCredentialStore(
        storage: secure,
        platform: native,
      );
      final http = ProviderReportingHttp(
        transport: _HistoryReportingTransport(at),
      );
      final caches = {
        for (final id in [a, b])
          id.storageKey: ConnectionSnapshotCache(
            connection: id.storageKey,
            platform: native,
            readCredentialVersion: () => store.readVersion(id),
          ),
      };
      return buildLiveProviderStack(
        credentialStore: store,
        claudeAccountService: const EmptyClaudeAccountService(),
        openAiAndCodex: openAiDashboardRepository(
          credentialStore: store,
          cache: caches[b.storageKey],
          client: OpenAiReportingClient(http: http),
          clock: () => at,
          logger: const _SilentLogger(),
        ),
        caches: caches,
        cursorSessionClient: CursorPlanClient(http: http),
        clock: () => at,
        logger: const _SilentLogger(),
      );
    }

    test('cacheless plan absence rechecks a replaced sibling row', () async {
      const plan = ProviderConnections.codexPlan;
      final planCredentials = credentials('cacheless', plan.storageKey);
      await bridge.invoke('test', 'setClock', {
        'value': at.millisecondsSinceEpoch,
      });
      await planCredentials.delete();
      await keys('setup').writeSecret(b, 'synthetic-b');
      final platform = ObservingCachePlatform(bridge.platform('sibling'));
      final sibling = owned(
        'sibling',
        b.storageKey,
        (_) async => _snapshot('openai', b.storageKey, at, 20).toJsonString(),
        cachePlatform: platform,
      );
      final repository = codexDashboardRepository(
        accountService: const EmptyCodexAccountService(),
        fallback: sibling,
        loadReport: () async {
          await planCredentials.read();
          return null;
        },
        logger: const _SilentLogger(),
      );
      final original = await repository.load();
      expect(
        original.connectionVersions[plan.storageKey]?['absentRead'],
        'true',
      );
      final originalOrder = original.snapshotOrdering[b.storageKey]!;
      expect(originalOrder.confirmedRowId, isNotNull);
      expect(await repository.isSnapshotCurrent(original), isTrue);

      final successor = owned('successor', b.storageKey, (_) async {
        return _snapshot('openai', b.storageKey, at, 30).toJsonString();
      });
      String? replacementRow;
      platform.onComplete = (method, _, result) async {
        if (method != 'validAll') return;
        expect(result, isTrue);
        final replacement = await successor.load();
        final order = replacement.snapshotOrdering[b.storageKey]!;
        expect(order.payload, originalOrder.payload);
        replacementRow = order.confirmedRowId;
      };
      expect(await repository.isSnapshotCurrent(original), isFalse);
      expect(replacementRow, isNotNull);
      expect(replacementRow, isNot(originalOrder.confirmedRowId));
    });

    test(
      'a legacy null remains valid after an unavailable cache pair',
      () async {
        await keys('ui').writeSecret(a, 'synthetic-session');
        final native = ObservingCachePlatform(bridge.platform('legacy'));
        var pairedReads = 0;
        native.beforeInvoke = (method, arguments) {
          if (method == 'readSnapshot' &&
              arguments['connection'] == a.storageKey) {
            pairedReads++;
            throw StateError('Synthetic paired cache read failure.');
          }
        };
        final sibling = _snapshot('openai', b.storageKey, at, 20);
        final result =
            await repository(
              'legacy',
              a.storageKey,
              () async => null,
              cachePlatform: native,
              fallback: ValueDashboardRepository(sibling),
            ).load();
        expect(pairedReads, 1);
        expect(result.toJson(), sibling.toJson());
        expect(result.snapshotOrdering, isEmpty);
      },
    );

    test('retains accepted A+B after late work', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      await keys('ui').writeSecret(b, 'synthetic-b');
      var fetchingA = false;
      var completedAbsentReads = 0;
      final native = ObservingCachePlatform(bridge.platform('late'));
      native.onComplete = (method, arguments, result) {
        if (arguments['connection'] != a.storageKey) return;
        if (method == 'acquireFetch') fetchingA = true;
        if (method == 'releaseFetch') fetchingA = false;
        if (fetchingA &&
            method == 'finish' &&
            result is Map &&
            result['mode'] == 'deleted') {
          completedAbsentReads++;
        }
      };
      final oldRepository = live('late', platform: native);
      final old = await oldRepository.load();
      final initiallyCurrent = await oldRepository.isSnapshotCurrent(old);
      final entered = Completer<void>();
      final release = Completer<void>();
      final visible = <String, Object?>{};
      final publications = <Map<String, Object?>>[];
      final redraws = <Map<String, Object?>>[];
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      const publication = MethodChannel('app.wardpulse/widget_publication');
      const widget = MethodChannel('home_widget');
      messenger.setMockMethodCallHandler(publication, (call) async {
        if (call.method != 'publish') throw MissingPluginException();
        visible.addAll(Map<String, Object?>.from(call.arguments as Map));
        publications.add(Map.of(visible));
        return true;
      });
      messenger.setMockMethodCallHandler(widget, (call) async {
        if (call.method != 'updateWidget') throw MissingPluginException();
        redraws.add(Map.of(visible));
        return true;
      });
      final preferences = PhoneWidgetPreferences(
        selectedIds: [
          'allowance.cursor.cursor-plan',
          'budget.openai.platform.today',
        ],
      );
      PhoneWidgetSyncCoordinator coordinator() => PhoneWidgetSyncCoordinator(
        write: HomeWidgetPhoneWidgetSyncService.writeHomeWidgetPayload,
      );
      final late = CapturedDashboardLoad.capture(() async {
        await coordinator().sync(
          old,
          preferences,
          isCurrent: () async {
            if (!entered.isCompleted) {
              entered.complete();
              await release.future;
            }
            return oldRepository.isSnapshotCurrent(old);
          },
        );
        return old;
      });
      try {
        await entered.future;
        await keys('activation').writeSecret(a, 'synthetic-a');
        final acceptedRepository = live('accepted');
        final accepted = await acceptedRepository.load();
        await coordinator().sync(
          accepted,
          preferences,
          isCurrent: () => acceptedRepository.isSnapshotCurrent(accepted),
        );
        final acceptedVisible = Map.of(visible);
        release.complete();
        final settled = await late;
        Object? lateError;
        try {
          settled.value;
        } catch (error) {
          lateError = error;
        }
        // Complete the operation and receiver readback before any OLD oracle.
        final lateVisible = Map.of(visible);
        final lateRedraws = List.of(redraws);
        final lateCurrent = await oldRepository.isSnapshotCurrent(old);
        final bCache = await cache('readback', b.storageKey).capture();
        List<Object?> accounts(DashboardSnapshot snapshot) => [
          for (final row in snapshot.accounts)
            {
              'id': row.accountId,
              'connection': row.connection,
              'status': row.status.name,
              'spent': row.today.spent?.minorUnits,
              'allowances': [
                for (final window in row.allowances)
                  {'id': window.id, 'usedPercent': window.usedPercent},
              ],
            },
        ];
        final evidence = {
          'oldAccounts': accounts(old),
          'acceptedAccounts': accounts(accepted),
          'lateOutcome': lateError == null ? 'completed' : 'error',
          'lateCurrent': lateCurrent,
          'latePublished': publications.length > 1,
          'completedAbsentReads': completedAbsentReads,
          'publications': publications,
          'redraws': lateRedraws,
          'visible': lateVisible,
        };
        stdout.writeln(
          'connection absence ownership oracle ${jsonEncode(evidence)}',
        );
        expect(lateError, isNull);
        expect(completedAbsentReads, 1);
        expect(old.accounts.map((row) => row.connection), [b.storageKey]);
        expect(accepted.accounts.map((row) => row.connection), [
          b.storageKey,
          a.storageKey,
        ]);
        expect(accepted.accounts.map((row) => row.accountId), [
          'openai-local',
          'cursor-local',
        ]);
        expect(acceptedVisible['row_count'], 2);
        expect(acceptedVisible['row_0_family'], 'Cursor');
        expect(acceptedVisible['row_0_percent'], '80% left');
        expect(acceptedVisible['row_1_family'], 'OpenAI');
        expect(acceptedVisible['row_1_spent_minor'], '900');
        expect(acceptedVisible['stale'], '0');
        expect(
          lateVisible,
          acceptedVisible,
          reason: 'Late B-only work must not replace accepted A+B',
        );
        expect(lateRedraws, [acceptedVisible]);
        expect(publications, [acceptedVisible]);
        expect(initiallyCurrent, isTrue);
        expect(lateCurrent, isFalse);
        expect(bCache.snapshot!.accounts.single.status, ProviderStatus.ok);
        expect(bCache.snapshot!.todayTotal.spent!.minorUnits, 900);
      } finally {
        if (!release.isCompleted) release.complete();
        await late;
        messenger.setMockMethodCallHandler(publication, null);
        messenger.setMockMethodCallHandler(widget, null);
      }
    });

    test(
      'preserves genuine absence through copies, settings and skipped work',
      () async {
        await keys('ui').writeSecret(b, 'synthetic-b');
        final repository = live('copies');
        final snapshot = await repository.load();
        final absent = snapshot.connectionVersions[a.storageKey];
        expect(absent?['absentRead'], 'true');
        final enabled = applyUserAlertSettings(
          snapshot,
          const AlertThresholdPreferences(
            connections: {
              'openai.platform': ConnectionAlertThresholds(
                today: AlertPercentThreshold(at: 80),
                budget: ConnectionBudget(today: 1000),
              ),
            },
          ),
        );
        expect(enabled.alertConditions, isNotEmpty);
        final copies = [
          snapshot.withAccounts(snapshot.accounts),
          snapshot.withConnectionVersions(snapshot.connectionVersions),
          snapshot.withReportingOutcomes(snapshot.reportingOutcomes),
          snapshot.withSyncIssue(DashboardSyncIssue.rateLimited),
          snapshot.withStaleStatus(),
          enabled,
          applyUserAlertSettings(enabled, const AlertThresholdPreferences()),
        ];
        for (final copy in copies) {
          expect(copy.connectionVersions, snapshot.connectionVersions);
          expect(await repository.isSnapshotCurrent(copy), isTrue);
          expect(copy.toJsonString(), isNot(contains('absentRead')));
        }
        final skipped = await automatic().run(repository.load);
        final skippedAgain = await automatic().run(repository.load);
        expect(skippedAgain.connectionVersions[a.storageKey], absent);
        expect(skippedAgain.accounts.single.status, ProviderStatus.ok);
        expect(
          skipped.accounts.single.accountId,
          snapshot.accounts.single.accountId,
        );
        expect(snapshot.connectionVersions, isNot(contains('anthropic.plan')));
        expect(
          await repository.isSnapshotCurrent(
            snapshot.withAccounts(const []).withReportingOutcomes([
              const ConnectionReportingOutcome(
                connection: a,
                category: ReportingOutcomeCategory.success,
                source: ReportingOutcomeSource.live,
                freshness: ReportingOutcomeFreshness.current,
              ),
            ]),
          ),
          isFalse,
        );
        final conflicting = snapshot.withConnectionVersions({
          ...snapshot.connectionVersions,
          b.storageKey: absent!,
        });
        expect(await repository.isSnapshotCurrent(conflicting), isFalse);
        expect(
          await repository.isSnapshotCurrent(
            conflicting.withReportingOutcomes(const []),
          ),
          isFalse,
        );
        final cacheBytes =
            await bridge.invoke('readback', 'readSnapshot', {
                  'connection': b.storageKey,
                  'expected': snapshot.connectionVersions[b.storageKey],
                })
                as String;
        expect(cacheBytes, isNot(contains('absentRead')));
        final watch =
            WatchDashboardSummaryPayload.fromSnapshot(
              snapshot,
              const WatchRingPreferences(selectedIds: []),
            ).encode();
        expect(watch, isNot(contains('absentRead')));
        await keys('activation').writeSecret(a, 'synthetic-a');
        for (final copy in copies) {
          expect(await repository.isSnapshotCurrent(copy), isFalse);
        }
        expect(await repository.isSnapshotCurrent(skippedAgain), isFalse);
      },
    );

    test('empty and all-off selections retain genuine absence', () async {
      await keys('setup').writeSecret(a, 'synthetic-prior');
      final prior = await live('prior').load();
      final priorOwner = prior.accounts.single.historyOwner;
      expect(priorOwner, isNotNull);
      await keys('setup').deleteSecret(a);
      final repository = live('empty');
      final empty = await repository.load();
      expect(empty.accounts, isEmpty);
      expect(empty.connectionVersions[a.storageKey]?['absentRead'], 'true');
      expect(await repository.isSnapshotCurrent(empty), isTrue);
      final history = SecureRecoveryWatchlistStore(storage: secure);
      final key = (
        accountId: 'previous',
        allowanceId: 'window',
        historyOwner: priorOwner,
      );
      await history.write([key]);
      await syncPlanRecoveries(
        empty,
        history,
        _HistoryRecoveryNotifier(),
        const DisabledRecoveryWakeScheduler(),
        readWindows: (_) => const [],
        now: () => at,
        rethrowFailures: true,
      );
      expect(await history.read(), [
        key,
      ], reason: 'Absence cannot own recovery history');
      for (final preferences in [
        const PhoneWidgetPreferences(),
        const PhoneWidgetPreferences(selectedIds: []),
      ]) {
        expect(buildPhoneWidgetPayload(empty, preferences).isEmpty, isTrue);
      }
    });

    for (final path in ['fallback', 'stale', 'merge error', 'failure']) {
      test('retains absence through $path and captured failures', () async {
        await keys('ui').writeSecret(b, 'synthetic-b');
        final absent = owned(
          'absent',
          a.storageKey,
          (_) async => throw StateError('Unreachable'),
        );
        final bSnapshot = _snapshot('openai', b.storageKey, at, 900);
        if (path == 'stale') {
          await owned(
            'prime',
            b.storageKey,
            (_) async => bSnapshot.toJsonString(),
          ).load();
        }
        final fallback =
            path == 'failure'
                ? absent
                : owned('b', b.storageKey, (_) async {
                  if (path == 'stale')
                    throw StateError('Synthetic reporting failure.');
                  return bSnapshot.toJsonString();
                }, fallback: absent);
        final DashboardRepository repository;
        if (path == 'merge error' || path == 'failure') {
          const c = ProviderConnections.cursorPlatform;
          await keys('ui').writeSecret(c, 'synthetic-c');
          repository = MergingConnectionRepository(
            connection: c,
            credentialStore: keys('c'),
            cache: cache('c', c.storageKey),
            fallback: fallback,
            loadCredentialReport: (_) async {
              if (path == 'failure')
                throw StateError('Synthetic reporting failure.');
              return _snapshot('cursor', c.storageKey, at, 100).toJsonString();
            },
            normalizeReport: (value) => value,
            mergeSnapshots:
                (_) => throw const FormatException('Synthetic merge failure.'),
            mapError:
                (_) => const DashboardLoadException(
                  issue: DashboardSyncIssue.rateLimited,
                ),
            logger: const _SilentLogger(),
          );
        } else {
          repository = fallback;
        }
        final captured = await CapturedDashboardLoad.capture(repository.load);
        DashboardSnapshot? snapshot;
        DashboardLoadException? failure;
        try {
          snapshot = captured.value;
        } on DashboardLoadException catch (error) {
          failure = error;
        }
        if (snapshot != null) {
          expect(
            snapshot.connectionVersions[a.storageKey]?['absentRead'],
            'true',
          );
          expect(snapshot.accounts.single.connection, b.storageKey);
          expect(
            snapshot.accounts.single.status,
            path == 'stale' ? ProviderStatus.stale : ProviderStatus.ok,
          );
          expect(await repository.isSnapshotCurrent(snapshot), isTrue);
        } else {
          expect(failure, isNotNull);
          expect(await repository.isFailureCurrent(failure!), isTrue);
        }
        await keys('activation').writeSecret(a, 'synthetic-a');
        if (snapshot != null) {
          expect(await repository.isSnapshotCurrent(snapshot), isFalse);
        } else {
          expect(await repository.isFailureCurrent(failure!), isFalse);
        }
      });
    }

    test('cache-only absence cannot qualify a failed report read', () async {
      final owner = repository(
        'probe',
        a.storageKey,
        () async => throw StateError('Synthetic unavailable read.'),
      );
      final captured = await CapturedDashboardLoad.capture(owner.load);
      DashboardLoadException? failure;
      try {
        captured.value;
      } on DashboardLoadException catch (error) {
        failure = error;
      }
      expect(failure, isNotNull);
      await keys('activation').writeSecret(a, 'synthetic-a');
      expect(await owner.isFailureCurrent(failure!), isTrue);
    });
  });

  test('late reporting replacement preserves the newer widget', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    const a = ProviderConnections.openAiPlatform;
    const b = ProviderConnections.anthropicPlatform;
    final keys = SecureProviderCredentialStore(
      storage: secure,
      platform: bridge.platform('ui'),
    );
    await keys.writeSecret(a, 'synthetic-a1');
    await keys.writeSecret(b, 'synthetic-b');
    final v1 = (await keys.readVersion(a))!;
    final reportHeld = Completer<String>();
    final releaseReport = Completer<void>();
    final aggregateHeld = Completer<void>();
    final releaseAggregate = Completer<void>();
    // Only old A's cache pauses: its first aggregate check follows the native
    // fetch release, whether the request carries B alone or A(v1)+B.
    final oldCache = ObservingCachePlatform(bridge.platform('old'));
    oldCache.beforeInvoke = (method, _) async {
      if (method != 'validAll' || aggregateHeld.isCompleted) return;
      aggregateHeld.complete();
      await releaseAggregate.future;
    };
    final oldRepository = owned(
      'old',
      a.storageKey,
      (secret) async {
        reportHeld.complete(secret);
        await releaseReport.future;
        return _snapshot('openai', a.storageKey, firstAt, 500).toJsonString();
      },
      fallback: owned(
        'old',
        b.storageKey,
        (_) async =>
            _snapshot('claude', b.storageKey, firstAt, 900).toJsonString(),
      ),
      cachePlatform: oldCache,
    );
    final visible = <String, Object?>{};
    final publications = <Map<String, Object?>>[];
    final redraws = <Map<String, Object?>>[];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    const publication = MethodChannel('app.wardpulse/widget_publication');
    const widget = MethodChannel('home_widget');
    messenger.setMockMethodCallHandler(publication, (call) async {
      if (call.method == 'publish') {
        visible.addAll(Map<String, Object?>.from(call.arguments as Map));
      } else if (call.method == 'markStale') {
        visible['stale'] = '1';
      } else {
        throw MissingPluginException();
      }
      publications.add(Map.of(visible));
      return true;
    });
    messenger.setMockMethodCallHandler(widget, (call) async {
      if (call.method != 'updateWidget') throw MissingPluginException();
      redraws.add(Map.of(visible));
      return true;
    });
    const preferences = PhoneWidgetPreferences(
      selectedIds: [
        'budget.openai.platform.today',
        'budget.anthropic.platform.today',
      ],
    );
    PhoneWidgetSyncCoordinator coordinator() => PhoneWidgetSyncCoordinator(
      write: HomeWidgetPhoneWidgetSyncService.writeHomeWidgetPayload,
    );
    final oldAttempt = CapturedDashboardLoad.capture(oldRepository.load);
    Future<void> entered(Future<void> hold, String name) => Future.any([
      hold,
      oldAttempt.then<void>((result) {
        result.value;
        throw StateError('Old load completed before its $name hold.');
      }),
    ]);
    try {
      await entered(reportHeld.future, 'report');
      expect(await reportHeld.future, 'synthetic-a1');
      await SecureProviderCredentialStore(
        storage: secure,
        platform: bridge.platform('replace'),
      ).writeSecret(a, 'synthetic-a2');
      releaseReport.complete();
      await entered(aggregateHeld.future, 'aggregate');
      final newer = owned(
        'new',
        a.storageKey,
        (_) async =>
            _snapshot('openai', a.storageKey, nextAt, 700).toJsonString(),
        fallback: owned(
          'new',
          b.storageKey,
          (_) async =>
              _snapshot('claude', b.storageKey, nextAt, 900).toJsonString(),
        ),
      );
      final accepted = await newer.load();
      await coordinator().sync(
        accepted,
        preferences,
        isCurrent: () => newer.isSnapshotCurrent(accepted),
      );
      final acceptedVisible = Map.of(visible);
      releaseAggregate.complete();
      final settled = await oldAttempt;
      DashboardLoadException? lateError;
      try {
        final old = settled.value;
        await coordinator().sync(
          old,
          preferences,
          isCurrent: () => oldRepository.isSnapshotCurrent(old),
        );
      } on DashboardLoadException catch (error) {
        lateError = error;
        await HomeWidgetPhoneWidgetSyncService.markExistingRowsStale(
          isCurrent: () => oldRepository.isFailureCurrent(error),
        );
      }
      final bCache = await cache('readback', b.storageKey).capture();
      expect(accepted.accounts.map((row) => row.connection), [
        b.storageKey,
        a.storageKey,
      ]);
      expect(acceptedVisible['row_count'], 2);
      expect([
        acceptedVisible['row_0_spent_minor'],
        acceptedVisible['row_1_spent_minor'],
      ], unorderedEquals(['700', '900']));
      expect(acceptedVisible['stale'], '0');
      expect(
        visible,
        acceptedVisible,
        reason: 'Late B-only work must not replace newer A+B',
      );
      expect(publications, [acceptedVisible]);
      expect(redraws, [acceptedVisible]);
      expect(lateError, isNotNull);
      final retained = lateError!.connectionVersions[a.storageKey];
      expect(retained, isNotNull);
      expect(CredentialVersion(retained!).sameCache(v1), isTrue);
      expect(bCache.snapshot!.accounts.single.status, ProviderStatus.ok);
      expect(bCache.snapshot!.todayTotal.spent!.minorUnits, 900);
    } finally {
      if (!releaseReport.isCompleted) releaseReport.complete();
      if (!releaseAggregate.isCompleted) releaseAggregate.complete();
      await oldAttempt;
      messenger.setMockMethodCallHandler(publication, null);
      messenger.setMockMethodCallHandler(widget, null);
    }
  });

  group('accepted connection history', () {
    final at = DateTime.utc(2026, 11, 14, 12);
    SecureCodexAccountStore codexStore(String engine) =>
        SecureCodexAccountStore(
          storage: secure,
          platform: bridge.platform(engine),
        );
    DashboardRepository codexHistory(
      String engine,
      _HistoryCodexTransport transport,
    ) {
      final sessions = codexStore(engine);
      return codexDashboardRepository(
        accountService: MobileCodexAccountService(
          store: sessions,
          client: CodexAccountClient(transport: transport, clock: () => at),
        ),
        cache: ConnectionSnapshotCache(
          connection: 'openai.plan',
          platform: bridge.platform(engine),
          readCredentialVersion:
              () async => (await sessions.readVersioned())?.version,
        ),
        fallback: const NoProvidersDashboardRepository(),
        logger: const _SilentLogger(),
      );
    }

    SecureProviderCredentialStore keys(String engine) =>
        SecureProviderCredentialStore(
          storage: secure,
          platform: bridge.platform(engine),
        );
    ConnectionSnapshotCache keyCache(String engine, ProviderConnectionId id) =>
        ConnectionSnapshotCache(
          connection: id.storageKey,
          platform: bridge.platform(engine),
          readCredentialVersion: () => keys(engine).readVersion(id),
        );
    DashboardRepository cursorHistory(
      String engine,
      _HistoryReportingTransport transport,
    ) => buildLiveProviderStack(
      credentialStore: keys(engine),
      claudeAccountService: const EmptyClaudeAccountService(),
      openAiAndCodex: const NoProvidersDashboardRepository(),
      caches: {'cursor.plan': keyCache(engine, ProviderConnections.cursorPlan)},
      cursorSessionClient: CursorPlanClient(
        http: ProviderReportingHttp(transport: transport),
      ),
      clock: () => at,
      logger: const _SilentLogger(),
    );
    DashboardRepository reportingHistory(
      String engine,
      _HistoryReportingTransport transport,
    ) => openAiDashboardRepository(
      credentialStore: keys(engine),
      cache: keyCache(engine, ProviderConnections.openAiPlatform),
      client: OpenAiReportingClient(
        http: ProviderReportingHttp(transport: transport),
      ),
      clock: () => at,
      logger: const _SilentLogger(),
    );
    Future<void> recover(
      DashboardSnapshot snapshot,
      _HistoryRecoveryNotifier notifier,
    ) => syncPlanRecoveries(
      snapshot,
      SecureRecoveryWatchlistStore(storage: secure),
      notifier,
      const DisabledRecoveryWakeScheduler(),
      now: () => at,
      rethrowFailures: true,
    );
    AlertNotificationDelivery alerts(_HistoryAlertNotifier notifier) =>
        AlertNotificationDelivery(
          preferences: const DefaultAlertNotificationPreferenceStore(),
          conditions: SecureAlertConditionStore(storage: secure),
          notifier: notifier,
        );
    final planRules = AlertThresholdPreferences(
      connections: const {
        'openai.plan': ConnectionAlertThresholds(
          planWindows: {'codex-secondary': AlertPercentThreshold(at: 80)},
        ),
      },
    );
    final reportingRules = AlertThresholdPreferences(
      connections: const {
        'openai.platform': ConnectionAlertThresholds(
          today: AlertPercentThreshold(at: 80),
          budget: ConnectionBudget(today: 1000),
        ),
      },
    );

    test(
      'Codex replacement cannot inherit recovery; same owner still recovers',
      () async {
        final sessions = codexStore('history-a');
        await sessions.write(_historySession('principal-a', at));
        final transport = _HistoryCodexTransport(at)..used = 100;
        final first = await codexHistory('history-a', transport).load();
        final notifier = _HistoryRecoveryNotifier();
        await recover(first, notifier);
        final history = SecureRecoveryWatchlistStore(storage: secure);
        final oldKeys = await history.read();
        expect(oldKeys.single.allowanceId, 'codex-secondary');
        await sessions.write(_historySession('principal-b', at));
        transport.used = 20;
        // No recovery observation occurs between accepting B and its usable report.
        final replacement = await codexHistory('history-b', transport).load();
        await recover(replacement, notifier);
        expect(
          notifier.reported,
          isEmpty,
          reason: 'B must not inherit A recovery',
        );
        expect(
          replacement.accounts.single.accountId,
          first.accounts.single.accountId,
        );
        final firstOwner = first.accounts.single.toJson()['historyOwner'];
        expect(firstOwner, isNotNull);
        expect(
          replacement.accounts.single.toJson()['historyOwner'],
          isNot(equals(firstOwner)),
        );
        expect(
          encodeWindowKeys(await history.read()),
          encodeWindowKeys(oldKeys),
        );

        transport.used = 100;
        final exhausted = await codexHistory('history-b', transport).load();
        await recover(exhausted, notifier);
        // A delayed A write has no authority over B's partition.
        await history.write(oldKeys);
        expect(await history.read(), hasLength(2));
        await bridge.invoke('test', 'restart', {});
        transport.used = 20;
        final usable =
            await codexHistory('history-restarted', transport).load();
        await recover(usable, notifier);
        expect(notifier.reported.map((r) => r.allowanceId), [
          'codex-secondary',
        ]);
        expect(
          encodeWindowKeys(await history.read()),
          encodeWindowKeys(oldKeys),
        );
        // An obsolete owner's work cannot post, clear, or cancel a current wake.
        await syncPlanRecoveries(
          first,
          history,
          notifier,
          const DisabledRecoveryWakeScheduler(),
          isCurrent: () async => false,
          rethrowFailures: true,
        );
        expect(notifier.reported, hasLength(1));
        expect(
          encodeWindowKeys(await history.read()),
          encodeWindowKeys(oldKeys),
        );
      },
    );

    test(
      'Cursor opaque replacement cannot inherit fixed-ID plan recovery',
      () async {
        const id = ProviderConnections.cursorPlan;
        final credentials = keys('cursor-a');
        await credentials.writeSecret(id, 'synthetic-cursor-a');
        final transport = _HistoryReportingTransport(at)..used = 100;
        final first = await cursorHistory('cursor-a', transport).load();
        final notifier = _HistoryRecoveryNotifier();
        await recover(first, notifier);
        final store = SecureRecoveryWatchlistStore(storage: secure);
        final oldKeys = await store.read();
        expect(oldKeys, isNotEmpty);
        await credentials.writeSecret(id, 'synthetic-cursor-b');
        transport.used = 20;
        final replacement = await cursorHistory('cursor-b', transport).load();
        await recover(replacement, notifier);
        expect(
          notifier.reported,
          isEmpty,
          reason: 'B must not inherit A recovery',
        );
        expect(first.accounts.single.accountId, 'cursor-local');
        expect(replacement.accounts.single.accountId, 'cursor-local');
        expect(
          replacement.accounts.single.toJson()['historyOwner'],
          isNot(equals(first.accounts.single.toJson()['historyOwner'])),
        );
        expect(encodeWindowKeys(await store.read()), encodeWindowKeys(oldKeys));
        // Labels, whitespace and an accepted identical token preserve the scope.
        await credentials.writeLabel(id, 'Renamed plan');
        await credentials.writeSecret(id, '  synthetic-cursor-b  ');
        transport.used = 100;
        await recover(
          await cursorHistory('cursor-b', transport).load(),
          notifier,
        );
        transport.used = 20;
        await recover(
          await cursorHistory('cursor-b', transport).load(),
          notifier,
        );
        expect(notifier.reported, hasLength(1));
        expect(encodeWindowKeys(await store.read()), encodeWindowKeys(oldKeys));
      },
    );

    test(
      'Codex replacement is eligible after A consumed the 80 percent boundary',
      () async {
        final sessions = codexStore('threshold-a');
        await sessions.write(_historySession('principal-a', at));
        final transport = _HistoryCodexTransport(at)..used = 90;
        final notifier = _HistoryAlertNotifier();
        final delivery = alerts(notifier);
        Future<DashboardSnapshot> observe(String engine) async {
          final snapshot = applyUserAlertSettings(
            await codexHistory(engine, transport).load(),
            planRules,
          );
          await delivery.sync(snapshot, alertThresholds: planRules);
          return snapshot;
        }

        final first = await observe('threshold-a');
        expect(notifier.posts, hasLength(1));
        await observe('threshold-a');
        expect(notifier.posts, hasLength(1));
        // Actual same-principal token rotation changes revision, not history.
        final captured = (await sessions.readVersioned())!;
        expect(
          await sessions.refresh(
            _historySession('principal-a', at, token: 'rotated'),
            captured.version,
          ),
          isNotNull,
        );
        await observe('threshold-rotated');
        expect(notifier.posts, hasLength(1));
        await sessions.write(
          _historySession('principal-a', at, token: 'reconnected'),
        );
        await observe('threshold-reconnected');
        expect(notifier.posts, hasLength(1));
        await sessions.write(_historySession('principal-b', at));
        final replacement = await observe('threshold-b');
        expect(
          notifier.posts,
          hasLength(2),
          reason: 'B must not inherit A threshold suppression',
        );
        expect(
          replacement.accounts.single.accountId,
          first.accounts.single.accountId,
        );
        final oldKey = first.alertConditions.single.key;
        final newKey = replacement.alertConditions.single.key;
        final persisted = SecureAlertConditionStore(storage: secure);
        expect(await persisted.read(oldKey), isTrue);
        expect(await persisted.read(newKey), isTrue);
        expect(
          newKey.toJson()['historyOwner'],
          isNot(equals(oldKey.toJson()['historyOwner'])),
        );
        // A delayed clear cannot rearm the replacement's condition.
        await persisted.write(oldKey, false);
        await bridge.invoke('test', 'restart', {});
        await alerts(notifier).sync(
          applyUserAlertSettings(
            await codexHistory('threshold-restarted', transport).load(),
            planRules,
          ),
        );
        expect(notifier.posts, hasLength(2));
        expect(await persisted.read(newKey), isTrue);
      },
    );

    test(
      'OpenAI reporting replacement is eligible at the same USD 9 of 10 crossing',
      () async {
        const id = ProviderConnections.openAiPlatform;
        final credentials = keys('report-a');
        await credentials.writeSecret(id, 'synthetic-report-a');
        final transport = _HistoryReportingTransport(at);
        final notifier = _HistoryAlertNotifier();
        final delivery = alerts(notifier);
        Future<DashboardSnapshot> observe(String engine) async {
          final snapshot = applyUserAlertSettings(
            await reportingHistory(engine, transport).load(),
            reportingRules,
          );
          await delivery.sync(snapshot, alertThresholds: reportingRules);
          return snapshot;
        }

        final first = await observe('report-a');
        expect(first.accounts.single.today.spent?.minorUnits, 900);
        expect(notifier.posts, hasLength(1));
        await credentials.writeLabel(id, 'Renamed reporting');
        final cancelled = await credentials.beginReconnect(id);
        await credentials.cancelReconnect(id, cancelled);
        await credentials.writeSecret(id, 'synthetic-report-a');
        await observe('report-same');
        expect(notifier.posts, hasLength(1));
        await credentials.writeSecret(id, 'synthetic-report-b');
        final replacement = await observe('report-b');
        expect(
          notifier.posts,
          hasLength(2),
          reason: 'B must not inherit A threshold suppression',
        );
        expect(replacement.accounts.single.today.spent?.minorUnits, 900);
        expect(
          replacement.accounts.single.accountId,
          first.accounts.single.accountId,
        );
        expect(
          replacement.accounts.single.toJson()['historyOwner'],
          isNot(equals(first.accounts.single.toJson()['historyOwner'])),
        );
        final persisted = SecureAlertConditionStore(storage: secure);
        expect(await persisted.read(first.alertConditions.single.key), isTrue);
        expect(
          await persisted.read(replacement.alertConditions.single.key),
          isTrue,
        );
        await bridge.invoke('test', 'restart', {});
        await observe('report-restarted');
        expect(notifier.posts, hasLength(2));
      },
    );

    test(
      'owned incomplete and skipped observations retain sibling history and wakes',
      () async {
        final sessions = codexStore('partial');
        await sessions.write(_historySession('principal-a', at));
        const cursor = ProviderConnections.cursorPlan;
        await keys('partial').writeSecret(cursor, 'synthetic-cursor');
        final codexTransport = _HistoryCodexTransport(at)..used = 100;
        final cursorTransport = _HistoryReportingTransport(at)..used = 100;
        final firstCodex = await codexHistory('partial', codexTransport).load();
        final firstCursor =
            await cursorHistory('partial', cursorTransport).load();
        final notifier = _HistoryRecoveryNotifier();
        DashboardSnapshot together(
          DashboardSnapshot codex,
          DashboardSnapshot cursor,
        ) => DashboardSnapshot.fromJsonString(
          mergeDashboardSnapshotsJson([
            codex.toJsonString(),
            cursor.toJsonString(),
          ]),
        ).withConnectionVersions({
          ...codex.connectionVersions,
          ...cursor.connectionVersions,
        });
        final store = SecureRecoveryWatchlistStore(storage: secure);
        final wake = _HistoryWake();
        await syncPlanRecoveries(
          together(firstCodex, firstCursor),
          store,
          notifier,
          wake,
          now: () => at,
          rethrowFailures: true,
        );
        final earlyReset = at.add(const Duration(days: 1));
        expect(wake.booked, [earlyReset]);
        final before = encodeWindowKeys(await store.read());
        expect(await store.read(), hasLength(2));
        await bridge.invoke('test', 'restart', {});
        // A missing secondary window is no positive recovery evidence.
        codexTransport.used = null;
        final unknown = await codexHistory('partial', codexTransport).load();
        expect(
          unknown.accounts.single.allowances.map((window) => window.id),
          isNot(contains('codex-secondary')),
        );
        await syncPlanRecoveries(
          together(unknown, firstCursor),
          SecureRecoveryWatchlistStore(storage: secure),
          notifier,
          wake,
          now: () => at,
          rethrowFailures: true,
        );
        expect(notifier.reported, isEmpty);
        expect(encodeWindowKeys(await store.read()), before);
        expect(wake.cancelled, 0);
        expect(
          wake.booked.last,
          earlyReset,
          reason:
              'The later Cursor reset must not postpone the missing Codex window',
        );
        final version = (await sessions.readVersioned())!.version;
        final poll =
            AutomaticPollContext(origin: AutomaticPollOrigin.resetWake)
              ..attempted.add(cursor.storageKey)
              ..skipped['openai.plan'] = AutomaticPollSkipped(
                'openai.plan',
                version,
                at.add(const Duration(minutes: 5)),
              )
              ..retainedAccountIds['openai.plan'] = {
                firstCodex.accounts.single.accountId,
              };
        await syncPlanRecoveries(
          together(unknown, firstCursor),
          store,
          notifier,
          wake,
          now: () => at,
          poll: poll,
          rethrowFailures: true,
        );
        expect(wake.booked.last, earlyReset);
        cursorTransport.used = 20;
        final usableCursor =
            await cursorHistory('partial', cursorTransport).load();
        final aggregate = together(unknown, usableCursor);
        await syncPlanRecoveries(
          aggregate,
          store,
          notifier,
          wake,
          now: () => at,
          poll: poll,
          rethrowFailures: true,
        );
        expect(notifier.reported.map((r) => r.provider), ['cursor']);
        expect(
          (await store.read()).single.accountId,
          firstCodex.accounts.single.accountId,
        );
        expect(wake.booked.last, earlyReset);
        // Demo cleanup preserves the qualified sibling and cannot establish live history.
        final bookings = List<DateTime>.of(wake.booked);
        await syncPlanRecoveries(
          DashboardSnapshot.empty(generatedAt: at),
          store,
          notifier,
          wake,
          mockData: true,
          isCurrent: () async => true,
          rethrowFailures: true,
        );
        expect(
          (await store.read()).single.accountId,
          firstCodex.accounts.single.accountId,
        );
        expect(wake.cancelled, 0);
        expect(wake.booked, bookings);
        codexTransport.used = 20;
        await recover(
          await codexHistory('partial', codexTransport).load(),
          notifier,
        );
        expect(notifier.reported.map((r) => r.provider), ['cursor', 'codex']);
        expect(await store.read(), isEmpty);
      },
    );

    test(
      'unbound legacy history is not adopted by qualified observations',
      () async {
        final sessions = codexStore('legacy');
        await sessions.write(_historySession('principal-a', at));
        final transport = _HistoryCodexTransport(at)..used = 20;
        secure.values['wardpulse.recovery.exhaustedWindows'] = jsonEncode([
          {'accountId': 'codex-local', 'allowanceId': 'codex-secondary'},
        ]);
        final notifier = _HistoryRecoveryNotifier();
        await recover(await codexHistory('legacy', transport).load(), notifier);
        expect(notifier.reported, isEmpty);
        final store = SecureRecoveryWatchlistStore(storage: secure);
        expect(await store.read(), hasLength(1));
        transport.used = 90;
        final qualified = applyUserAlertSettings(
          await codexHistory('legacy', transport).load(),
          planRules,
        );
        final legacyKey = AlertConditionKey.fromJson({
          ...qualified.alertConditions.single.key.toJson(),
          'historyOwner': null,
        });
        final conditions = SecureAlertConditionStore(storage: secure);
        await conditions.write(legacyKey, true);
        final alertNotifier = _HistoryAlertNotifier();
        await alerts(alertNotifier).sync(qualified);
        expect(alertNotifier.posts, hasLength(1));
        expect(await conditions.read(legacyKey), isTrue);
        expect(
          await conditions.read(qualified.alertConditions.single.key),
          isTrue,
        );
        transport.used = 100;
        await recover(await codexHistory('legacy', transport).load(), notifier);
        transport.used = 20;
        await recover(await codexHistory('legacy', transport).load(), notifier);
        expect(notifier.reported, hasLength(1));
        expect(
          await store.read(),
          hasLength(1),
        ); // The separate legacy list remains unbound.
      },
    );

    test(
      'native cache provenance binds legacy payloads and rejects conflicting owners',
      () async {
        const id = ProviderConnections.openAiPlatform;
        final credentials = keys('cache-owner');
        await credentials.writeSecret(id, 'synthetic-cache-owner');
        final version = (await credentials.readVersion(id))!;
        final snapshots = keyCache('cache-owner', id);
        final legacy = _snapshot('openai', id.storageKey, at, 900);
        // Old normalized payloads are qualified by the native versioned cache,
        // independently of the unbound recovery list.
        expect(
          await bridge.invoke('test', 'writeSnapshot', {
            'connection': id.storageKey,
            'expected': version.values,
            'snapshot': legacy.toJsonString(),
            'generatedAt': at.microsecondsSinceEpoch,
          }),
          isTrue,
        );
        final bound = (await snapshots.capture(expected: version)).snapshot!;
        expect(bound.accounts.single.today.spent?.minorUnits, 900);
        expect(bound.accounts.single.toJson()['historyOwner'], isNotNull);
        final corrupted = bound.toJson();
        (corrupted['accounts'] as List).single['historyOwner'] = {
          'connection': id.storageKey,
          'identity': 'synthetic-conflicting-owner',
        };
        expect(
          await bridge.invoke('test', 'writeSnapshot', {
            'connection': id.storageKey,
            'expected': version.values,
            'snapshot': jsonEncode(corrupted),
            'generatedAt': at.microsecondsSinceEpoch,
          }),
          isTrue,
        );
        expect((await snapshots.capture(expected: version)).snapshot, isNull);
        expect(await snapshots.valid(version), isTrue);
        expect(
          await snapshots.validSnapshot(
            DashboardSnapshot.fromJson(
              corrupted,
            ).withConnectionVersions({id.storageKey: version.values}),
          ),
          isFalse,
        );
        expect(
          () => snapshots.stamp(DashboardSnapshot.fromJson(corrupted), version),
          throwsFormatException,
        );
      },
    );

    test(
      'Anthropic and Cursor Team wrappers preserve accepted reporting ownership',
      () async {
        final credentials = keys('mapping');
        const ids = [
          ProviderConnections.anthropicPlatform,
          ProviderConnections.cursorPlatform,
        ];
        for (final id in ids)
          await credentials.writeSecret(id, 'synthetic-${id.storageKey}-a');
        final transport = _EmptyReportingTransport();
        DashboardRepository repository() => buildLiveProviderStack(
          credentialStore: credentials,
          claudeAccountService: const EmptyClaudeAccountService(),
          openAiAndCodex: const NoProvidersDashboardRepository(),
          caches: {
            for (final id in ids) id.storageKey: keyCache('mapping', id),
          },
          anthropicReportingClient: AnthropicReportingClient(
            http: ProviderReportingHttp(transport: transport),
          ),
          cursorReportingClient: CursorPlatformClient(
            http: ProviderReportingHttp(transport: transport),
          ),
          clock: () => at,
          logger: const _SilentLogger(),
        );
        final first = await repository().load();
        expect(
          first.accounts.map((a) => a.accountId),
          containsAll(['anthropic-local', 'cursor-team-local']),
        );
        for (final account in first.accounts)
          expect(account.toJson()['historyOwner'], isNotNull);
        await credentials.writeSecret(
          ids.first,
          'synthetic-anthropic-replacement',
        );
        final replacement = await repository().load();
        for (final account in replacement.accounts) {
          final previous = first.accounts.singleWhere(
            (a) => a.connection == account.connection,
          );
          expect(
            account.toJson()['historyOwner'],
            account.connection == ids.first.storageKey
                ? isNot(equals(previous.toJson()['historyOwner']))
                : equals(previous.toJson()['historyOwner']),
          );
        }
      },
    );
  });

  test('late older Codex report retains newer normalized cache', () async {
    const id = 'openai.plan';
    final reportA = _codexReport('2026-11-14T09:00:00.100Z', 60);
    final reportB = _codexReport('2026-11-14T09:00:00.800Z', 90);
    final accessA = credentials('a', id);
    final accessB = credentials('b', id);
    await accessA.write('synthetic-codex-session');
    final version = (await accessA.read())!.version;
    final normalizations = <({String input, String output})>[];
    String normalize(String input) {
      final output = normalizeCodexReportJson(input);
      normalizations.add((input: input, output: output));
      stdout.writeln(
        'Codex normalization: ${jsonEncode({'input': input, 'output': output})}',
      );
      return output;
    }

    final heldA = Completer<void>(), releaseA = Completer<void>();
    final platform = _RecordingCachePlatform(bridge.platform('a'));
    var failA = false;
    final a = codex(
      'a',
      () async {
        final report = await accessA.serializeFetch(() async {
          if (failA) throw StateError('Sanitized offline failure.');
          return reportA;
        });
        // serializeFetch has validated and released A's native fetch ticket.
        heldA.complete();
        await releaseA.future;
        return report;
      },
      platform: platform,
      normalizeReport: normalize,
    );
    final lateLoad = CapturedDashboardLoad.capture(a.load);
    try {
      await Future.any([
        heldA.future,
        lateLoad.then<void>((result) {
          result.value;
          throw StateError('Codex A completed before its hold.');
        }),
      ]);
      final newer =
          await codex(
            'b',
            () => accessB.serializeFetch(() async => reportB),
            normalizeReport: normalize,
          ).load();
      final persistedBeforeA = DashboardSnapshot.fromJsonString(
        await bridge.invoke('test', 'readSnapshot', {
              'connection': id,
              'expected': version.values,
            })
            as String,
      );
      releaseA.complete();
      final late = (await lateLoad).value;
      final durable = DashboardSnapshot.fromJsonString(
        await bridge.invoke('test', 'readSnapshot', {
              'connection': id,
              'expected': version.values,
            })
            as String,
      );
      failA = true;
      platform.failSnapshotRead = true;
      final DashboardSnapshot memory;
      try {
        memory = await a.load();
      } finally {
        platform.failSnapshotRead = false;
      }
      await bridge.invoke('test', 'restart', {});
      final cold =
          await codex(
            'cold',
            () => credentials('cold', id).serializeFetch<String?>(() async {
              throw StateError('Sanitized cold offline failure.');
            }),
            normalizeReport: normalize,
          ).load();

      // Gather every cache path before asserting the substantive downgrade contract.
      final observations = {
        'late return': late,
        'durable payload': durable,
        'memory fallback': memory,
        'cold recovery': cold,
      };
      for (final entry in observations.entries) {
        _expectCodexUsage(entry.value, 90, reason: entry.key);
      }
      _expectCodexUsage(newer, 90, reason: 'B success');
      _expectCodexUsage(persistedBeforeA, 90, reason: 'B persisted before A');
      expect(newer.syncIssue, isNull);
      expect(late.syncIssue, isNull);

      // Precision diagnostics follow B retention so the old library fails above.
      expect(normalizations.map((record) => record.input), [reportB, reportA]);
      for (final record in normalizations) {
        final normalized = jsonDecode(record.output) as Map;
        final expected =
            record.input == reportA
                ? '2026-11-14T09:00:00.1Z'
                : '2026-11-14T09:00:00.8Z';
        expect(normalized['generatedAt'], expected);
        expect(
          (normalized['accounts'] as List).single['lastSuccessfulSyncAt'],
          expected,
        );
      }
      final normalizedA = DashboardSnapshot.fromJsonString(
        normalizations.last.output,
      );
      final normalizedB = DashboardSnapshot.fromJsonString(
        normalizations.first.output,
      );
      expect(
        normalizedB.generatedAt
            .difference(normalizedA.generatedAt)
            .inMicroseconds,
        700000,
      );
      for (final snapshot in [
        newer,
        persistedBeforeA,
        ...observations.values,
      ]) {
        final account = snapshot.accounts.singleWhere(
          (account) => account.provider == 'codex',
        );
        expect(
          snapshot.generatedAt,
          DateTime.parse('2026-11-14T09:00:00.800Z'),
        );
        expect(
          account.lastSuccessfulSyncAt,
          DateTime.parse('2026-11-14T09:00:00.800Z'),
        );
      }
    } finally {
      platform.failSnapshotRead = false;
      if (!releaseA.isCompleted) releaseA.complete();
      await lateLoad;
    }
  });

  test('equal Codex instants accept a later completed refresh', () async {
    const id = 'openai.plan';
    final access = credentials('ui', id);
    await access.write('synthetic-codex-session');
    final first =
        await codex(
          'ui',
          () => access.serializeFetch(
            () async => _codexReport('2026-11-14T09:00:00.100Z', 60),
          ),
        ).load();
    final second =
        await codex(
          'ui',
          () => access.serializeFetch(
            () async => _codexReport('2026-11-14T09:00:00.100000Z', 90),
          ),
        ).load();
    final durable = (await cache('reader', id).capture()).snapshot!;
    _expectCodexUsage(first, 60, reason: 'first equal-instant refresh');
    _expectCodexUsage(second, 90, reason: 'later equal-instant refresh');
    _expectCodexUsage(durable, 90, reason: 'equal-instant durable payload');
    expect(second.generatedAt, first.generatedAt);
    expect(durable.generatedAt, first.generatedAt);
    expect(first.generatedAt, DateTime.parse('2026-11-14T09:00:00.100Z'));
  });

  for (final id in [
    'openai.platform',
    'anthropic.platform',
    'cursor.platform',
  ]) {
    for (final owners in [
      ('foreground', 'headless'),
      ('headless', 'foreground'),
    ]) {
      test(
        '$id ${owners.$1} admission suppresses queued ${owners.$2} and rereads cache',
        () async {
          await credentials('ui', id).write('synthetic-key');
          final provider =
              id == 'anthropic.platform' ? 'claude' : id.split('.').first;
          final version = (await credentials('ui', id).read())!.version;
          await cache(
            'ui',
            id,
          ).store(_snapshot(provider, id, firstAt, 10), version);
          final entered = Completer<void>(), release = Completer<void>();
          var calls = 0;
          String payload(int spend) =>
              _snapshot(provider, id, nextAt, spend).toJsonString();
          final first = owned(owners.$1, id, (_) async {
            calls++;
            entered.complete();
            await release.future;
            return payload(25);
          });
          final firstLoad = automatic().run(first.load);
          await entered.future;
          await bridge.invoke('test', 'setClock', {'value': 60000});
          final second = owned(owners.$2, id, (_) async {
            calls++;
            return payload(99);
          });
          final poll = automatic();
          final secondLoad = poll.run(second.load);
          late DashboardSnapshot retained;
          try {
            expect(
              (await cache('reader', id).capture())
                  .snapshot!
                  .accounts
                  .single
                  .today
                  .spent
                  ?.minorUnits,
              10,
            );
          } finally {
            release.complete();
            retained = (await Future.wait([firstLoad, secondLoad])).last;
          }
          expect(calls, 1);
          expect(poll.whollySkipped, isTrue);
          expect(retained.accounts.single.today.spent?.minorUnits, 25);
          expect(retained.generatedAt, nextAt);
          expect(retained.reportingOutcomes, isEmpty);
          await bridge.invoke('test', 'setClock', {'value': 299999});
          await automatic().run(second.load);
          expect(calls, 1);
          await bridge.invoke('test', 'setClock', {'value': 300000});
          await automatic().run(second.load);
          expect(calls, 2);
        },
      );
    }
  }
  test(
    'Cursor polling keeps the corrected deadline across callers and restart',
    () async {
      const id = 'cursor.plan';
      const interval = Duration(minutes: 15);
      final deadline = firstAt.add(interval);
      await credentials('ui', id).write('synthetic-session');
      final payload = _snapshot('cursor', id, firstAt, 10).toJsonString();
      var calls = 0;
      MergingConnectionRepository cursor(String owner) =>
          owned(owner, id, (_) async {
            calls++;
            return payload;
          });
      AutomaticPollContext periodic() =>
          AutomaticPollContext(readInterval: () async => interval);
      Future<void> setClock(DateTime at) async {
        await bridge.invoke('test', 'setClock', {
          'value': at.millisecondsSinceEpoch,
        });
      }

      final foreground = cursor('foreground');
      final headless = cursor('headless');
      await setClock(firstAt.add(const Duration(days: 1)));
      await periodic().run(foreground.load);
      expect(calls, 1);

      await setClock(firstAt);
      final rebased = periodic();
      await rebased.run(headless.load);
      expect(rebased.skipped[id]?.nextEligible, deadline);
      expect(rebased.resetEligibleAt(id), nextAt);
      expect(calls, 1);

      await setClock(nextAt);
      await foreground.load();
      expect(calls, 2);
      final later = periodic();
      await later.run(foreground.load);
      expect(later.skipped[id]?.nextEligible, deadline);
      expect(later.resetEligibleAt(id), nextAt);
      expect(calls, 2);

      await bridge.invoke('test', 'restart', {});
      final restarted = cursor('restarted');
      await setClock(deadline.subtract(const Duration(milliseconds: 1)));
      final beforeDeadline = periodic();
      await beforeDeadline.run(restarted.load);
      expect(beforeDeadline.skipped[id]?.nextEligible, deadline);
      expect(calls, 2);

      await setClock(deadline);
      await periodic().run(restarted.load);
      expect(calls, 3);
    },
  );
  test(
    'Cursor plan failed attempt suppresses recreated clients without inventing data',
    () async {
      const id = ProviderConnections.cursorPlan;
      final transport = _EmptyReportingTransport(denyCursor: true);
      final store = SecureProviderCredentialStore(
        storage: secure,
        platform: bridge.platform('ui'),
      );
      await store.writeSecret(id, 'synthetic-session');
      DashboardRepository live(String owner) => buildLiveProviderStack(
        credentialStore: SecureProviderCredentialStore(
          storage: secure,
          platform: bridge.platform(owner),
        ),
        claudeAccountService: const EmptyClaudeAccountService(),
        openAiAndCodex: const NoProvidersDashboardRepository(),
        caches: {id.storageKey: cache(owner, id.storageKey)},
        cursorSessionClient: CursorPlanClient(
          http: ProviderReportingHttp(transport: transport),
        ),
        mergeSnapshots: _merge,
        logger: const _SilentLogger(),
      );
      await CapturedDashboardLoad.capture(
        () => automatic().run(live('ui').load),
      );
      expect(transport.requests, hasLength(1));
      final poll = automatic();
      final retained = await poll.run(live('headless').load);
      expect(transport.requests, hasLength(1));
      expect(poll.whollySkipped, isTrue);
      expect(retained.accounts, isEmpty);
      expect(retained.reportingOutcomes, isEmpty);
    },
  );
  test(
    'manual bypass keeps the anchor and partial skips retain stale evidence',
    () async {
      const a = 'openai.platform', b = 'anthropic.platform';
      await credentials('ui', a).write('synthetic-A');
      await credentials('ui', b).write('synthetic-B');
      var calls = 0, fails = false;
      final first = owned('ui', a, (_) async {
        calls++;
        if (fails) throw StateError('Synthetic rate limit');
        return _snapshot('openai', a, firstAt, 10).toJsonString();
      });
      await first
          .load(); // Manual work supplies cache, not an automatic anchor.
      fails = true;
      final failed = await automatic().run(first.load);
      expect(failed.syncIssue, DashboardSyncIssue.rateLimited);
      final fresh = owned(
        'worker',
        b,
        (_) async => _snapshot('claude', b, nextAt, 20).toJsonString(),
        fallback: first,
      );
      final poll = automatic();
      final mixed = await poll.run(fresh.load);
      expect(calls, 2);
      expect(poll.whollySkipped, isFalse);
      expect(mixed.accounts.first.status, ProviderStatus.stale);
      expect(mixed.accounts.first.lastSuccessfulSyncAt, firstAt);
      _expectSelectedBudgetFreshness(mixed, a, stale: true);
      _expectSelectedBudgetFreshness(mixed, b, stale: false);
      expect(
        mixed.reportingOutcomes.where(
          (o) =>
              o.connection.storageKey == a &&
              o.category == ReportingOutcomeCategory.success,
        ),
        isEmpty,
      );
      fails = false;
      await first.load();
      expect(calls, 3);
      await automatic().run(first.load);
      expect(calls, 3);
      await bridge.invoke('test', 'setClock', {'value': 300000});
      await automatic().run(first.load);
      expect(calls, 4);
    },
  );
  test(
    'partial skip without prior failure does not create stale surface data',
    () async {
      const a = 'openai.platform', b = 'anthropic.platform';
      await credentials('ui', a).write('synthetic-A');
      await credentials('ui', b).write('synthetic-B');
      final first = owned(
        'ui',
        a,
        (_) async => _snapshot('openai', a, firstAt, 10).toJsonString(),
      );
      await automatic().run(first.load);
      final fresh = owned(
        'worker',
        b,
        (_) async => _snapshot('claude', b, nextAt, 20).toJsonString(),
        fallback: first,
      );
      final poll = automatic();
      final mixed = await poll.run(fresh.load);
      expect(poll.whollySkipped, isFalse);
      expect(poll.skipped.keys, [a]);
      expect(mixed.accounts.first.lastSuccessfulSyncAt, firstAt);
      _expectSelectedBudgetFreshness(mixed, a, stale: false);
    },
  );
  test(
    'a denied replacement load cannot inherit the previous generation failure',
    () async {
      const id = 'openai.platform';
      await credentials('ui', id).write('synthetic-old');
      var failing = false, calls = 0;
      final previous = owned('ui', id, (_) async {
        calls++;
        if (failing) throw StateError('Synthetic old failure');
        return _snapshot('openai', id, firstAt, 10).toJsonString();
      });
      await previous.load();
      failing = true;
      expect(
        (await automatic().run(previous.load)).syncIssue,
        DashboardSyncIssue.rateLimited,
      );
      await credentials('worker', id).write('synthetic-replacement');
      await automatic().run(
        owned(
          'worker',
          id,
          (_) async => _snapshot('openai', id, nextAt, 20).toJsonString(),
        ).load,
      );
      final poll = automatic();
      final retained = await poll.run(previous.load);
      expect(calls, 2);
      expect(poll.whollySkipped, isTrue);
      expect(retained.accounts.single.status, ProviderStatus.ok);
      expect(retained.accounts.single.lastSuccessfulSyncAt, nextAt);
      expect(retained.syncIssue, isNull);
      expect(retained.reportingOutcomes, isEmpty);
    },
  );
  test(
    'a skip retains a current failure when its first cached data arrives from another client',
    () async {
      const id = 'openai.platform';
      await credentials('ui', id).write('synthetic-key');
      var calls = 0;
      final failed = owned('ui', id, (_) async {
        calls++;
        throw StateError('Synthetic rate limit');
      });
      await expectLater(
        automatic().run(failed.load),
        throwsA(isA<DashboardLoadException>()),
      );
      await owned(
        'worker',
        id,
        (_) async => _snapshot('openai', id, firstAt, 20).toJsonString(),
      ).load();
      final poll = automatic();
      final retained = await poll.run(failed.load);
      expect(calls, 1);
      expect(poll.whollySkipped, isTrue);
      expect(retained.accounts.single.status, ProviderStatus.stale);
      expect(retained.accounts.single.lastSuccessfulSyncAt, firstAt);
      expect(retained.syncIssue, DashboardSyncIssue.rateLimited);
      expect(
        retained.reportingOutcomes.single.source,
        ReportingOutcomeSource.cache,
      );
    },
  );
  test(
    'queued admission resolves the current preference and metadata failure consumes no attempt',
    () async {
      const id = 'cursor.platform';
      final access = credentials('ui', id);
      await access.write('synthetic-key');
      var calls = 0, minutes = 5;
      final repository = owned('worker', id, (_) async {
        calls++;
        return _snapshot('cursor', id, firstAt, calls).toJsonString();
      });
      await automatic().run(repository.load);
      await bridge.invoke('test', 'setClock', {'value': 300000});
      final entered = Completer<void>(), release = Completer<void>();
      final held = access.serializeFetch(() async {
        entered.complete();
        await release.future;
      });
      await entered.future;
      final poll = AutomaticPollContext(
        readInterval: () async => Duration(minutes: minutes),
      );
      final queued = poll.run(repository.load);
      minutes = 60;
      release.complete();
      await held;
      await queued;
      expect(calls, 1);
      expect(poll.whollySkipped, isTrue);
      await bridge.invoke('test', 'failCommit', {'value': true});
      await automatic().run(repository.load);
      expect(calls, 1);
      await bridge.invoke('test', 'failCommit', {'value': false});
      expect(await access.read(), isNotNull);
      await automatic().run(repository.load);
      expect(calls, 2);

      await bridge.invoke('test', 'setClock', {'value': 0});
      await bridge.invoke('test', 'failCommit', {'value': true});
      final failedRebase = automatic();
      final retained = await failedRebase.run(repository.load);
      expect(retained.syncIssue, DashboardSyncIssue.credentialUnavailable);
      expect(failedRebase.resetEligibleAt(id), isNull);
      expect(calls, 2);
    },
  );

  test(
    'Cursor legacy basis misses preserve bytes, timestamps and credential epochs',
    () async {
      const id = 'cursor.platform';
      await credentials('ui', id).write('synthetic-team-key');
      final original = firstAt.add(const Duration(microseconds: 500));
      final version = (await credentials('ui', id).read())!.version;
      final snapshot = _snapshot('cursor', id, original, 500);
      await cache('ui', id).store(snapshot, version);
      final legacy = [
        snapshot.toJsonString(),
        jsonEncode({
          'monetaryBasis': 'cursor-cycle-v0',
          'snapshot': snapshot.toJson(),
        }),
        '{unmarked-unreadable',
      ];
      for (final encoded in legacy) {
        await bridge.invoke('test', 'setDisk', {
          'key': '$id.snapshot',
          'value': encoded,
        });
        await bridge.invoke('test', 'setDisk', {
          'key': '$id.snapshotTimeUnit',
          'value': 'milliseconds',
        });
        await bridge.invoke('test', 'setDisk', {
          'key': '$id.snapshotAt',
          'value': original.millisecondsSinceEpoch,
        });
        await bridge.invoke('test', 'restart', {});
        final platform = _RecordingCachePlatform(bridge.platform('cold'));
        final cold = ConnectionSnapshotCache(
          connection: id,
          platform: platform,
          readCredentialVersion:
              () async => (await credentials('cold', id).read())?.version,
        );
        for (final expected in <CredentialVersion?>[null, version]) {
          final captured = await cold.capture(expected: expected);
          expect(captured.snapshot, isNull);
          expect(captured.version!.values, version.values);
        }
        expect(platform.methods, isNot(contains('upgradeSnapshotTimestamp')));
        expect(platform.methods, isNot(contains('clearSnapshot')));
        expect(
          await bridge.invoke('test', 'readSnapshot', {
            'connection': id,
            'expected': version.values,
          }),
          encoded,
        );
        final retained = (await credentials('ui', id).read())!;
        expect(retained.version.values, version.values);
        expect(retained.value, 'synthetic-team-key');
      }
      final fresh =
          await repository(
            'live',
            id,
            () async => _snapshot('cursor', id, nextAt, 20).toJsonString(),
          ).load();
      expect(fresh.accounts.single.today.spent?.minorUnits, 20);
      expect((await cache('cold', id).capture()).snapshot!.generatedAt, nextAt);
    },
  );

  test(
    'Cursor new-basis cold fallback keeps success times and refuses older writes',
    () async {
      const id = 'cursor.platform';
      final original = firstAt.add(const Duration(microseconds: 500));
      await credentials('ui', id).write('synthetic-team-key');
      final fresh =
          await repository(
            'ui',
            id,
            () async => _snapshot('cursor', id, original, 25).toJsonString(),
          ).load();
      final version = (await credentials('ui', id).read())!.version;
      final encoded =
          await bridge.invoke('test', 'readSnapshot', {
                'connection': id,
                'expected': version.values,
              })
              as String;
      final wrapper = jsonDecode(encoded) as Map;
      expect(wrapper['monetaryBasis'], 'cursor-extra-paid-calendar-v1');
      expect(
        (wrapper['snapshot'] as Map)['generatedAt'],
        original.toIso8601String(),
      );
      expect(
        jsonDecode(fresh.toJsonString()),
        isNot(contains('monetaryBasis')),
      );
      await bridge.invoke('test', 'restart', {});
      final stale =
          await repository(
            'cold',
            id,
            () async => throw StateError('Synthetic offline report'),
          ).load();
      expect(stale.accounts.single.status, ProviderStatus.stale);
      expect(stale.accounts.single.today.spent?.minorUnits, 25);
      expect(stale.generatedAt, original);
      expect(stale.accounts.single.lastSuccessfulSyncAt, original);
      expect(
        await cache(
          'old',
          id,
        ).store(_snapshot('cursor', id, firstAt, 1), version),
        isFalse,
      );
      expect(
        (await cache('cold', id).capture()).snapshot!.generatedAt,
        original,
      );
    },
  );

  group('versioned reporting feedback', () {
    const ids = [
      ProviderConnections.openAiPlatform,
      ProviderConnections.anthropicPlatform,
      ProviderConnections.cursorPlatform,
    ];
    SecureProviderCredentialStore store(
      String owner, {
      ConnectionCachePlatform? platform,
    }) => SecureProviderCredentialStore(
      storage: secure,
      platform: platform ?? bridge.platform(owner),
    );
    MergingConnectionRepository reporting(
      ProviderConnectionId id,
      Future<String> Function(String) fetch, {
      DashboardRepository fallback = const NoProvidersDashboardRepository(),
      ConnectionCachePlatform? platform,
    }) => MergingConnectionRepository(
      connection: id,
      credentialStore: store('ui', platform: platform),
      cache: cache('ui', id.storageKey, platform: platform),
      fallback: fallback,
      loadCredentialReport: fetch,
      normalizeReport: (value) => value,
      mergeSnapshots: _merge,
      logger: const _SilentLogger(),
      mapError: (error) => mapReportingError(error, const _SilentLogger()),
    );

    testWidgets(
      'uncached Admin rejection renders truthful replacement feedback',
      (tester) async {
        const id = ProviderConnections.anthropicPlatform;
        final credentials = store('ui');
        final snapshots = cache('ui', id.storageKey);
        final transport = _EmptyReportingTransport();
        var normalizations = 0;
        late CapturedDashboardLoad captured;
        await tester.runAsync(() async {
          await credentials.writeSecret(id, 'sk-ant-admin01-synthetic');
          await credentials.writeLabel(id, 'Saved organization');
          final version = (await credentials.readVersion(id))!;
          final savedSecrets = Map<String, String>.from(secure.values);
          expect((await snapshots.capture()).snapshot, isNull);
          final repository = buildLiveProviderStack(
            credentialStore: credentials,
            claudeAccountService: const EmptyClaudeAccountService(),
            openAiAndCodex: const NoProvidersDashboardRepository(),
            caches: {id.storageKey: snapshots},
            clock: () => nextAt,
            anthropicReportingClient: AnthropicReportingClient(
              http: ProviderReportingHttp(transport: transport),
            ),
            normalizeAnthropicReport: (_) {
              normalizations++;
              return _snapshot(
                'claude',
                id.storageKey,
                nextAt,
                88,
              ).toJsonString();
            },
            mergeSnapshots: _merge,
            logger: const _SilentLogger(),
          );
          final updates = <ConnectionReportingUpdate>[];
          final loading = repository.loadObserved(updates.add);
          await expectLater(
            loading,
            throwsA(
              isA<DashboardLoadException>().having(
                (failure) => failure.issue,
                'issue',
                DashboardSyncIssue.authentication,
              ),
            ),
          );
          captured = await CapturedDashboardLoad.capture(() => loading);
          final rejection = captured.reportingOutcomes.single;
          expect(rejection.connection, id);
          expect(
            rejection.category,
            ReportingOutcomeCategory.authenticationRejected,
          );
          expect(rejection.source, ReportingOutcomeSource.local);
          expect(rejection.freshness, ReportingOutcomeFreshness.current);
          expect(rejection.credentialVersion!.sameCache(version), isTrue);
          expect(rejection.supportingCopy, anthropicReportingKeyGuidance);
          expect(rejection.canEditKey, isTrue);
          final reported =
              updates.where((update) => update.outcome != null).single;
          expect(reported.outcome?.source, ReportingOutcomeSource.local);
          expect(reported.credentialVersion!.sameCache(version), isTrue);
          expect(await credentials.readSecret(id), 'sk-ant-admin01-synthetic');
          expect(await credentials.readLabel(id), 'Saved organization');
          expect(
            (await credentials.readVersion(id))!.sameCache(version),
            isTrue,
          );
          expect(secure.values, savedSecrets);
          expect((await snapshots.capture()).snapshot, isNull);
        });

        final loading = Future<DashboardSnapshot>.sync(() => captured.value);
        unawaited(
          loading.then<void>((_) {}).onError<DashboardLoadException>((_, _) {}),
        );
        await tester.pumpWidget(
          WardPulseApp(
            repository: _HeldDashboardRepository(loading),
            credentialStore: credentials,
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Dashboard unavailable'), findsOneWidget);
        expect(
          find.textContaining(
            'Anthropic · Organization reporting: Key rejected.',
          ),
          findsOneWidget,
        );
        expect(
          find.textContaining(anthropicReportingKeyGuidance),
          findsOneWidget,
        );
        final editKey = find.widgetWithText(TextButton, 'Edit key');
        expect(editKey.hitTestable(), findsOneWidget);
        expect(tester.widget<TextButton>(editKey).onPressed, isNotNull);
        const message =
            'The credential was not accepted. Check that you pasted the full key or token.';
        expect(find.byTooltip(message), findsOneWidget);
        await tester.longPress(find.byTooltip(message));
        await tester.pumpAndSettle();
        expect(find.text(message), findsOneWidget);
        expect(
          find.textContaining('The provider rejected the credential'),
          findsNothing,
        );
        expect(transport.requests, isEmpty);
        expect(normalizations, 0);
      },
    );

    test(
      'saved Admin rejection preserves legacy credential, label and shared-stack cache until replacement',
      () async {
        const id = ProviderConnections.anthropicPlatform;
        final credentials = store('ui');
        secure.values['wardpulse.${id.storageKey}.secret'] =
            'sk-ant-admin01-synthetic';
        await credentials.writeLabel(id, 'Saved organization');
        final version = (await credentials.readVersion(id))!;
        final snapshots = cache('ui', id.storageKey);
        final original = _snapshot('claude', id.storageKey, firstAt, 77);
        expect(await snapshots.store(original, version), isTrue);
        final savedSecrets = Map<String, String>.from(secure.values);
        final originalCache =
            (await snapshots.capture()).snapshot!.toJsonString();
        final transport = _EmptyReportingTransport();
        var normalizations = 0;
        final repository = buildLiveProviderStack(
          credentialStore: credentials,
          claudeAccountService: const EmptyClaudeAccountService(),
          openAiAndCodex: const NoProvidersDashboardRepository(),
          caches: {id.storageKey: snapshots},
          clock: () => nextAt,
          anthropicReportingClient: AnthropicReportingClient(
            http: ProviderReportingHttp(transport: transport),
          ),
          normalizeAnthropicReport: (_) {
            normalizations++;
            return _snapshot(
              'claude',
              id.storageKey,
              nextAt,
              88,
            ).toJsonString();
          },
          mergeSnapshots: _merge,
          logger: const _SilentLogger(),
        );
        final updates = <ConnectionReportingUpdate>[];
        final retained = await repository.loadObserved(updates.add);
        expect(transport.requests, isEmpty);
        expect(normalizations, 0);
        expect(secure.values, savedSecrets);
        expect(await credentials.readLabel(id), 'Saved organization');
        expect(await credentials.readSecret(id), 'sk-ant-admin01-synthetic');
        expect((await credentials.readVersion(id))!.sameCache(version), isTrue);
        expect(
          (await snapshots.capture()).snapshot!.toJsonString(),
          originalCache,
        );
        expect(retained.accounts.single.status, ProviderStatus.stale);
        expect(retained.accounts.single.today.spent?.minorUnits, 77);
        expect(retained.accounts.single.lastSuccessfulSyncAt, firstAt);
        final rejection = retained.reportingOutcomes.single;
        expect(rejection.connection, id);
        expect(
          rejection.category,
          ReportingOutcomeCategory.authenticationRejected,
        );
        expect(rejection.source, ReportingOutcomeSource.local);
        expect(rejection.freshness, ReportingOutcomeFreshness.current);
        expect(rejection.credentialVersion!.sameCache(version), isTrue);
        expect(rejection.supportingCopy, anthropicReportingKeyGuidance);
        expect(rejection.canEditKey, isTrue);
        final reported =
            updates.where((update) => update.outcome != null).single;
        expect(reported.outcome?.source, ReportingOutcomeSource.local);
        expect(reported.credentialVersion!.sameCache(version), isTrue);
        expect(retained.toJsonString(), isNot(contains('sk-ant-admin')));

        await credentials.writeSecret(id, 'sk-ant-api03-synthetic');
        repository.invalidate();
        updates.clear();
        final recovered = await repository.loadObserved(updates.add);
        final replacement = (await credentials.readVersion(id))!;
        expect(replacement.sameCache(version), isFalse);
        expect(await credentials.readLabel(id), 'Saved organization');
        expect(transport.requests, isNotEmpty);
        expect(normalizations, 1);
        expect(recovered.accounts.single.today.spent?.minorUnits, 88);
        expect(recovered.accounts.single.lastSuccessfulSyncAt, nextAt);
        final success = recovered.reportingOutcomes.single;
        expect(success.category, ReportingOutcomeCategory.success);
        expect(success.source, ReportingOutcomeSource.live);
        expect(success.freshness, ReportingOutcomeFreshness.current);
        expect(success.credentialVersion!.sameCache(replacement), isTrue);
        expect((await snapshots.capture()).snapshot!.generatedAt, nextAt);
      },
    );

    test(
      'shared factories collect every reporting connection with captured bounds',
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
        const console = ProviderConnections.anthropicPlatform;
        await credentials.writeLabel(console, 'Saved Console');
        final consoleVersion =
            (await credentials.credentialAccess(console)!.read())!.version;
        final consoleCache = caches[console.storageKey]!;
        expect(
          await consoleCache.store(
            _snapshot('claude', console.storageKey, firstAt, 77),
            consoleVersion,
          ),
          isTrue,
        );
        String empty(String _) =>
            DashboardSnapshot.empty(generatedAt: firstAt).toJsonString();
        Map<String, dynamic>? anthropicInput;
        Map<String, dynamic>? cursorInput;
        var clockReads = 0;
        final capturedAt = firstAt.add(const Duration(microseconds: 500));
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
          clock: () {
            clockReads++;
            return capturedAt;
          },
          anthropicReportingClient: AnthropicReportingClient(http: http),
          normalizeAnthropicReport: (report) {
            anthropicInput = jsonDecode(report) as Map<String, dynamic>;
            return _snapshot(
              'claude',
              console.storageKey,
              capturedAt,
              77,
            ).toJsonString();
          },
          cursorReportingClient: CursorPlatformClient(http: http),
          normalizeCursorPlatformReport: (report) {
            cursorInput = jsonDecode(report) as Map<String, dynamic>;
            return empty(report);
          },
          mergeSnapshots: _merge,
          logger: const _SilentLogger(),
        );
        final observations = <ConnectionReportingUpdate>[];
        final snapshot = await repository.loadObserved(observations.add);
        expect(clockReads, 2); // One captured instant per reporting collector.
        expect(anthropicInput!['accountId'], 'anthropic-local');
        expect(anthropicInput!['generatedAt'], capturedAt.toIso8601String());
        expect(
          anthropicInput!['capturedEndMicros'],
          capturedAt.microsecondsSinceEpoch,
        );
        expect(
          anthropicInput!['todayStart'],
          DateTime.utc(2026, 10, 13).toIso8601String(),
        );
        expect(
          anthropicInput!['weekStart'],
          DateTime.utc(2026, 10, 12).toIso8601String(),
        );
        expect(
          anthropicInput!['monthStart'],
          DateTime.utc(2026, 10, 1).toIso8601String(),
        );
        expect(anthropicInput!['usagePages'], hasLength(2));
        expect(anthropicInput!['costPages'], hasLength(1));
        expect(
          transport.uris
              .where((uri) => uri.path.startsWith('/v1/organizations/'))
              .map(
                (uri) => (
                  uri.path,
                  uri.queryParameters['bucket_width'],
                  uri.queryParameters['starting_at'],
                  uri.queryParameters['ending_at'],
                ),
              ),
          unorderedEquals([
            (
              '/v1/organizations/usage_report/messages',
              '1d',
              DateTime.utc(2026, 10, 1).toIso8601String(),
              DateTime.utc(2026, 10, 13).toIso8601String(),
            ),
            (
              '/v1/organizations/usage_report/messages',
              '1m',
              DateTime.utc(2026, 10, 13).toIso8601String(),
              capturedAt.toIso8601String(),
            ),
            (
              '/v1/organizations/cost_report',
              '1d',
              DateTime.utc(2026, 10, 1).toIso8601String(),
              DateTime.utc(2026, 10, 14, 0, 0, 1).toIso8601String(),
            ),
          ]),
        );
        expect(cursorInput!['generatedAt'], capturedAt.toIso8601String());
        expect(
          cursorInput!['endExclusiveMs'],
          capturedAt.millisecondsSinceEpoch,
        );
        expect(
          cursorInput!['todayStartMs'],
          DateTime.utc(2026, 10, 13).millisecondsSinceEpoch,
        );
        expect(
          cursorInput!['weekStartMs'],
          DateTime.utc(2026, 10, 12).millisecondsSinceEpoch,
        );
        expect(
          cursorInput!['monthStartMs'],
          DateTime.utc(2026, 10, 1).millisecondsSinceEpoch,
        );
        expect(cursorInput!['requestStartMs'], cursorInput!['monthStartMs']);
        final eventRequest = transport.eventRequest!;
        expect(eventRequest['startDate'], cursorInput!['requestStartMs']);
        expect(
          eventRequest['endDate'],
          (cursorInput!['endExclusiveMs'] as int) - 1,
        );
        expect(snapshot.accounts.single.connection, console.storageKey);
        expect(snapshot.accounts.single.today.spent!.minorUnits, 77);
        expect(
          await credentials.readSecret(console),
          'synthetic-${console.storageKey}',
        );
        expect(await credentials.readLabel(console), 'Saved Console');
        expect(
          (await credentials.credentialAccess(console)!.read())!.version.values,
          consoleVersion.values,
        );
        expect(
          (await consoleCache.capture()).snapshot!.generatedAt,
          capturedAt,
        );
        expect(
          snapshot.connectionVersions[console.storageKey],
          consoleVersion.values,
        );
        expect(
          snapshot.reportingOutcomes.map((outcome) => outcome.connection),
          unorderedEquals([
            ProviderConnections.openAiPlatform,
            ProviderConnections.anthropicPlatform,
            ProviderConnections.cursorPlatform,
          ]),
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
          final completed = observations.singleWhere(
            (update) =>
                update.connection == outcome.connection && !update.checking,
          );
          expect(
            completed.attemptEra,
            snapshot
                .snapshotOrdering[outcome.connection.storageKey]!
                .attemptEra,
          );
          expect(completed.attemptEra, isNotNull);
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
            '/teams/filtered-usage-events',
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
        expect(
          () => failed.value,
          throwsA(
            isA<DashboardLoadException>().having(
              (error) => error.issue,
              'issue',
              DashboardSyncIssue.providerUnavailable,
            ),
          ),
        );
        final plan = _snapshot('codex', 'openai.plan', firstAt, 0);
        final mixed = await stack(ValueDashboardRepository(plan)).load();
        expect(mixed.accounts.single.connection, 'openai.plan');
        expect(
          mixed.reportingOutcomes.map((outcome) => outcome.connection),
          ids,
        );
        final snapshots = cache('ui', ids.first.storageKey);
        expect(await snapshots.validSnapshot(mixed), isTrue);
        expect(mixed.connectionVersions, {
          for (final outcome in mixed.reportingOutcomes)
            outcome.connection.storageKey: outcome.credentialVersion!.values,
        });
        for (final id in ids) {
          expect(mixed.snapshotOrdering[id.storageKey]!.payload, isNull);
          expect(mixed.snapshotOrdering[id.storageKey]!.attemptEra, isNotNull);
        }
        // The outcomes also carry credential proof independently of the cache.
        final outcomeProof = mixed.withConnectionVersions(
          const {},
          snapshotOrdering: const {},
        );
        expect(await snapshots.validSnapshot(outcomeProof), isTrue);
        await store('worker').writeSecret(ids[1], 'replacement');
        expect(await snapshots.validSnapshot(mixed), isFalse);
        expect(await snapshots.validSnapshot(outcomeProof), isFalse);
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
        final credentialStore = store('ui');
        final unchanged = ids.first;
        final replaced = ids[1];
        await credentialStore.writeSecret(unchanged, 'synthetic-A');
        await credentialStore.writeSecret(replaced, 'synthetic-B');
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
        await credentialStore.writeSecret(replaced, 'synthetic-replacement');
        repository.invalidate();
        fail = true;
        final retained = await repository.load();
        expect(retained.accounts.single.connection, unchanged.storageKey);
        expect(retained.accounts.single.status, ProviderStatus.stale);
        expect(retained.accounts.single.today.spent?.minorUnits, 20);
        expect(retained.accounts.single.lastSuccessfulSyncAt, nextAt);
        expect(retained.generatedAt, nextAt);
        final replacementVersion =
            (await credentials('worker', replaced.storageKey).read())!.version;
        expect(retained.connectionVersions, {
          unchanged.storageKey: newest.connectionVersions[unchanged.storageKey],
          replaced.storageKey: replacementVersion.values,
        });
        final replacementOrder =
            retained.snapshotOrdering[replaced.storageKey]!;
        expect(replacementOrder.payload, isNull);
        expect(replacementOrder.attemptEra, 0);
        expect(
          retained.reportingOutcomes
              .singleWhere((outcome) => outcome.connection == replaced)
              .credentialVersion!
              .values,
          replacementVersion.values,
        );
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
          if (boundary == 'detach') {
            final failure = retired.loadException;
            expect(failure?.details, 'Connection changed during refresh.');
            expect(await repository.isFailureCurrent(failure!), isFalse);
          }
          expect(observations.where((update) => !update.checking), isEmpty);
          expect(
            (await cache('worker', id.storageKey).capture()).snapshot,
            isNull,
          );
        },
      );
    }

    for (final retirePrimary in [true, false]) {
      test(
        retirePrimary
            ? 'a retired fetch keeps the sibling storage diagnostic'
            : 'an owned provider failure keeps its issue when a sibling retires',
        () async {
          const primaryId = ProviderConnections.openAiPlatform;
          const siblingId = ProviderConnections.anthropicPlatform;
          final primaryKey = primaryId.storageKey;
          final siblingKey = siblingId.storageKey;
          final writer = store('writer');
          await writer.writeSecret(siblingId, 'synthetic-sibling');
          final siblingSlot = secure.values.keys.single;
          await writer.writeSecret(primaryId, 'synthetic-primary');
          final primaryVersion = (await writer.readVersion(primaryId))!;
          final siblingCache = cache('reader', siblingKey);
          var siblingRequests = 0;
          final sibling = reporting(siblingId, (_) async {
            siblingRequests++;
            return _snapshot('claude', siblingKey, firstAt, 10).toJsonString();
          });
          await sibling.load();
          final before = await siblingCache.capture();
          expect(before.record?.rowId, isA<String>());
          secure.failReadKey = siblingSlot;

          const owner = 'retiring-primary';
          final repository = owned(owner, primaryKey, (_) async {
            if (retirePrimary) await bridge.invoke(owner, 'detach', {});
            throw const ProviderReportingException(
              ProviderReportingFailure.rateLimited,
            );
          }, fallback: sibling);
          final captured = await CapturedDashboardLoad.capture(repository.load);
          final failure = captured.loadException;
          expect(
            failure?.issue,
            retirePrimary
                ? DashboardSyncIssue.credentialUnavailable
                : DashboardSyncIssue.rateLimited,
          );
          expect(failure!.syncRejection, isNull);
          expect(
            failure.reportingOutcomes.map((outcome) => outcome.connection),
            [siblingId, if (!retirePrimary) primaryId],
          );
          final outcome = failure.reportingOutcomes.first;
          expect(outcome.category, ReportingOutcomeCategory.localReadFailure);
          expect(outcome.source, ReportingOutcomeSource.local);
          expect(outcome.credentialVersion, isNull);
          if (!retirePrimary) {
            final primaryOutcome = failure.reportingOutcomes.last;
            expect(
              primaryOutcome.category,
              ReportingOutcomeCategory.rateLimited,
            );
            expect(primaryOutcome.source, ReportingOutcomeSource.live);
            expect(
              primaryOutcome.credentialVersion?.values,
              primaryVersion.values,
            );
            expect(failure.snapshotOrdering[primaryKey]?.attemptEra, isNotNull);
          }
          expect(failure.connectionVersions, {
            primaryKey: primaryVersion.values,
          });
          expect(
            failure.snapshotOrdering.keys,
            unorderedEquals([primaryKey, siblingKey]),
          );
          expect(
            failure.snapshotOrdering[primaryKey]?.selectionUnverified,
            retirePrimary,
          );
          expect(
            failure.snapshotOrdering[siblingKey]?.selectionUnverified,
            isTrue,
          );
          expect(await repository.isFailureCurrent(failure), isFalse);

          secure.failReadKey = null;
          final after = await siblingCache.capture();
          expect(after.version?.values, before.version?.values);
          expect(after.record?.rowId, before.record?.rowId);
          expect(after.snapshot?.toJson(), before.snapshot?.toJson());
          expect(siblingRequests, 1);
        },
      );
    }

    for (final (failReread, newerLoadDuringReread) in [
      (false, true),
      (true, true),
      (true, false),
    ]) {
      final scenario =
          newerLoadDuringReread
              ? 'a newer load during the cache reread retires the primary failure '
                  '(read failure without a cache order: $failReread)'
              : 'a failed cache reread without an order retires the primary '
                  'failure without a newer load';
      test(scenario, () async {
        await bridge.invoke('test', 'setClock', {
          'value': firstAt.millisecondsSinceEpoch,
        });
        const primaryId = ProviderConnections.openAiPlatform;
        const siblingId = ProviderConnections.anthropicPlatform;
        final primaryKey = primaryId.storageKey;
        final siblingKey = siblingId.storageKey;
        final writer = store('writer');
        await writer.writeSecret(primaryId, 'synthetic-primary');
        await writer.writeSecret(siblingId, 'synthetic-sibling');
        if (!failReread) {
          await reporting(primaryId, (_) async {
            return _snapshot('openai', primaryKey, firstAt, 10).toJsonString();
          }).load();
        }
        final siblingPair = await cache('reader', siblingKey).capture();
        final siblingVersion = siblingPair.version!;
        final siblingOrder = SnapshotOrdering(
          emptyCacheOrder: siblingPair.order!,
        );
        final storageOutcome = ConnectionReportingOutcome(
          connection: siblingId,
          category: ReportingOutcomeCategory.localReadFailure,
          source: ReportingOutcomeSource.local,
          credentialVersion: siblingVersion,
        );
        final sibling = ValueDashboardRepository(
          DashboardSnapshot.empty()
              .withSyncIssue(DashboardSyncIssue.credentialUnavailable)
              .withReportingOutcomes([storageOutcome])
              .withConnectionVersions(
                {siblingKey: siblingVersion.values},
                snapshotOrdering: {siblingKey: siblingOrder},
              ),
        );
        final platform = ObservingCachePlatform(bridge.platform('primary'));
        var requests = 0;
        final primary = reporting(
          primaryId,
          (_) async {
            requests++;
            throw ProviderReportingException(
              ProviderReportingFailure.rateLimited,
              details: 'Synthetic rate limit for request $requests.',
            );
          },
          fallback: sibling,
          platform: platform,
        );
        CapturedDashboardLoad? newer;
        if (failReread) {
          platform.beforeInvoke = (method, arguments) {
            if (method == 'readSnapshot' && arguments['forSelection'] != true) {
              throw StateError('Synthetic initial payload read failure.');
            }
          };
        }
        platform.onComplete = (method, arguments, _) async {
          if (method != 'readSnapshot' || arguments['forSelection'] != true) {
            return;
          }
          platform.beforeInvoke = null;
          platform.onComplete = null;
          if (newerLoadDuringReread) {
            newer = await CapturedDashboardLoad.capture(primary.load);
          }
          if (failReread) throw StateError('Synthetic payload reread failure.');
        };

        final retired = await CapturedDashboardLoad.capture(primary.load);
        final failure = retired.loadException!;
        if (!newerLoadDuringReread) {
          expect(requests, 1);
          expect(
            await bridge.invoke('reader', 'validAll', {
              'versions': failure.connectionVersions,
              'attemptClockEras': {
                primaryKey: failure.snapshotOrdering[primaryKey]?.attemptEra,
              },
              'emptyCacheOrders': {siblingKey: siblingPair.order!},
            }),
            isTrue,
          );
        }
        expect(await primary.isFailureCurrent(failure), isFalse);
        final current =
            newer ?? await CapturedDashboardLoad.capture(primary.load);
        expect(requests, 2);
        expect(failure.issue, DashboardSyncIssue.rateLimited);
        expect(failure.details, 'Synthetic rate limit for request 1.');
        expect(failure.reportingOutcomes.first, same(storageOutcome));
        final primaryOutcome = failure.reportingOutcomes.last;
        expect(failure.reportingOutcomes, hasLength(2));
        expect(primaryOutcome.connection, primaryId);
        expect(primaryOutcome.category, ReportingOutcomeCategory.rateLimited);
        expect(primaryOutcome.source, ReportingOutcomeSource.live);
        expect(
          primaryOutcome.credentialVersion?.values,
          current.connectionVersions[primaryKey],
        );
        expect(failure.connectionVersions, current.connectionVersions);
        expect(
          failure.snapshotOrdering.keys,
          unorderedEquals(current.snapshotOrdering.keys),
        );
        expect(failure.snapshotOrdering[siblingKey], same(siblingOrder));
        final retiredOrder = failure.snapshotOrdering[primaryKey]!;
        final currentOrder = current.snapshotOrdering[primaryKey]!;
        expect(retiredOrder.confirmedRowId, currentOrder.confirmedRowId);
        expect(retiredOrder.payload, currentOrder.payload);
        expect(retiredOrder.attemptEra, isNotNull);
        expect(retiredOrder.attemptEra, currentOrder.attemptEra);
        expect(retiredOrder.emptyCacheOrder, isNull);
        expect(retiredOrder.selectionUnverified, isTrue);
        if (failReread) {
          expect(currentOrder.emptyCacheOrder, isNotNull);
          expect(
            await primary.isFailureCurrent(current.loadException!),
            isTrue,
          );
        } else {
          expect(await primary.isSnapshotCurrent(current.value), isTrue);
        }
      });
    }

    for (final (failOuterReread, newerLoadDuringReread) in [
      (false, false),
      (true, false),
      (false, true),
    ]) {
      test(
        failOuterReread
            ? 'a failed outer selection reread preserves an inner provider failure'
            : newerLoadDuringReread
            ? 'a newer outer load during reread keeps the inner provider failure'
            : 'a successful outer load preserves an inner unverified provider failure',
        () async {
          await bridge.invoke('test', 'setClock', {
            'value': firstAt.millisecondsSinceEpoch,
          });
          const innerId = ProviderConnections.openAiPlatform;
          const outerId = ProviderConnections.anthropicPlatform;
          final innerKey = innerId.storageKey;
          final outerKey = outerId.storageKey;
          final writer = store('writer');
          await writer.writeSecret(innerId, 'synthetic-inner');
          await writer.writeSecret(outerId, 'synthetic-outer');
          final innerVersion = (await writer.readVersion(innerId))!;
          final outerVersion = (await writer.readVersion(outerId))!;
          final platform = ObservingCachePlatform(bridge.platform('inner'));
          platform.beforeInvoke = (method, _) {
            if (method == 'readSnapshot') {
              throw StateError('Synthetic paired cache read failure.');
            }
          };
          const details = 'Synthetic rate limit.';
          final inner = reporting(innerId, (_) async {
            throw const ProviderReportingException(
              ProviderReportingFailure.rateLimited,
              details: details,
            );
          }, platform: platform);
          final outerPlatform = ObservingCachePlatform(
            bridge.platform('outer'),
          );
          var outerSelectionReads = 0;
          outerPlatform.beforeInvoke = (method, arguments) {
            if (method == 'readSnapshot' && arguments['forSelection'] == true) {
              outerSelectionReads++;
              if (failOuterReread && outerSelectionReads == 2) {
                throw StateError('Synthetic outer selection reread failure.');
              }
            }
          };
          var outerRequests = 0;
          final outer = reporting(
            outerId,
            (_) async {
              if (++outerRequests == 2) {
                // Keep the original cache row available to validate its proof.
                throw const ProviderReportingException(
                  ProviderReportingFailure.rateLimited,
                  details: 'Synthetic newer outer rate limit.',
                );
              }
              return _snapshot('claude', outerKey, firstAt, 10).toJsonString();
            },
            fallback: inner,
            platform: outerPlatform,
          );
          if (newerLoadDuringReread) {
            outerPlatform.onComplete = (method, arguments, _) async {
              if (method != 'readSnapshot' ||
                  arguments['forSelection'] != true ||
                  outerSelectionReads != 2) {
                return;
              }
              outerPlatform.beforeInvoke = null;
              outerPlatform.onComplete = null;
              await CapturedDashboardLoad.capture(outer.load);
            };
          }

          final result = await CapturedDashboardLoad.capture(outer.load);
          expect(outerSelectionReads, 2);
          expect(outerRequests, newerLoadDuringReread ? 2 : 1);
          final failure = result.loadException!;
          expect(failure.issue, DashboardSyncIssue.rateLimited);
          expect(failure.details, details);
          final outcome = failure.reportingOutcomes.single;
          expect(outcome.connection, innerId);
          expect(outcome.category, ReportingOutcomeCategory.rateLimited);
          expect(outcome.source, ReportingOutcomeSource.live);
          expect(outcome.credentialVersion?.values, innerVersion.values);
          expect(failure.connectionVersions, {
            innerKey: innerVersion.values,
            outerKey: outerVersion.values,
          });
          final innerOrder = failure.snapshotOrdering[innerKey]!;
          expect(innerOrder.attemptEra, isNotNull);
          expect(innerOrder.payload, isNull);
          expect(innerOrder.emptyCacheOrder, isNull);
          expect(innerOrder.selectionUnverified, isTrue);
          final outerRecord =
              (await cache('reader', outerKey).capture()).record!;
          final outerOrder = failure.snapshotOrdering[outerKey]!;
          expect(outerOrder.confirmedRowId, isNotNull);
          expect(outerOrder.confirmedRowId, outerRecord.rowId);
          final outerRetired = failOuterReread || newerLoadDuringReread;
          expect(outerOrder.selectionUnverified, outerRetired);
          expect(await outer.isFailureCurrent(failure), isFalse);
          final proofWithoutRetirement = failure.withConnectionVersions(
            failure.connectionVersions,
            snapshotOrdering: {
              ...failure.snapshotOrdering,
              innerKey: SnapshotOrdering(attemptEra: innerOrder.attemptEra),
              if (outerRetired)
                outerKey: SnapshotOrdering(
                  payload: outerOrder.payload,
                  confirmedRowId: outerOrder.confirmedRowId,
                  attemptEra: outerOrder.attemptEra,
                ),
            },
          );
          expect(await outer.isFailureCurrent(proofWithoutRetirement), isTrue);
        },
      );
    }

    test(
      'a retired fetch keeps a sibling admission failure with empty order',
      () async {
        const primaryId = ProviderConnections.openAiPlatform;
        const siblingId = ProviderConnections.anthropicPlatform;
        final primaryKey = primaryId.storageKey;
        final siblingKey = siblingId.storageKey;
        final writer = store('writer');
        await writer.writeSecret(primaryId, 'synthetic-primary');
        await writer.writeSecret(siblingId, 'synthetic-sibling');
        final primaryVersion = (await writer.readVersion(primaryId))!;
        final siblingCache = cache('reader', siblingKey);
        final empty = await siblingCache.capture();
        expect(empty.record, isNull);
        expect(empty.order, isNotNull);

        final platform = ObservingCachePlatform(bridge.platform('ui'));
        platform.beforeInvoke = (method, _) {
          if (method == 'claimAutomatic') {
            throw StateError('Synthetic automatic admission storage failure.');
          }
        };
        var siblingRequests = 0;
        final sibling = reporting(siblingId, (_) async {
          siblingRequests++;
          return _snapshot('claude', siblingKey, firstAt, 10).toJsonString();
        }, platform: platform);
        const owner = 'retiring-primary';
        final repository = owned(owner, primaryKey, (_) async {
          await bridge.invoke(owner, 'detach', {});
          throw const ProviderReportingException(
            ProviderReportingFailure.rateLimited,
          );
        }, fallback: sibling);
        final poll = automatic();
        final captured = await poll.run(
          () => CapturedDashboardLoad.capture(repository.load),
        );
        final failure = captured.loadException;
        expect(failure?.issue, DashboardSyncIssue.credentialUnavailable);
        final outcome = failure!.reportingOutcomes.single;
        expect(outcome.connection, siblingId);
        expect(outcome.category, ReportingOutcomeCategory.localReadFailure);
        expect(outcome.source, ReportingOutcomeSource.local);
        expect(outcome.credentialVersion?.values, empty.version!.values);
        expect(failure.connectionVersions, {
          primaryKey: primaryVersion.values,
          siblingKey: empty.version!.values,
        });
        expect(
          failure.snapshotOrdering[primaryKey]?.selectionUnverified,
          isTrue,
        );
        expect(
          failure.snapshotOrdering[siblingKey]?.selectionUnverified,
          isFalse,
        );
        expect(
          failure.snapshotOrdering[siblingKey]?.emptyCacheOrder,
          empty.order,
        );
        expect(await repository.isFailureCurrent(failure), isFalse);
        expect((await siblingCache.capture()).observation, empty.observation);
        expect(poll.attempted, {primaryKey});
        expect(siblingRequests, 0);
      },
    );

    for (final (throwsValidation, staleSibling) in [
      (false, false),
      (true, true),
    ]) {
      test(
        'retired admission failures keep both storage outcomes '
        '(validation throws: $throwsValidation, stale sibling: $staleSibling)',
        () async {
          const primaryId = ProviderConnections.openAiPlatform;
          const siblingId = ProviderConnections.anthropicPlatform;
          final primaryKey = primaryId.storageKey;
          final siblingKey = siblingId.storageKey;
          final writer = store('writer');
          await writer.writeSecret(primaryId, 'synthetic-primary');
          await writer.writeSecret(siblingId, 'synthetic-sibling');
          var requests = 0;
          final sibling = reporting(siblingId, (_) async {
            requests++;
            return _snapshot('claude', siblingKey, firstAt, 10).toJsonString();
          });
          if (staleSibling) await sibling.load();
          final primaryPair = await cache('reader', primaryKey).capture();
          final siblingPair = await cache('reader', siblingKey).capture();
          final versions = {
            primaryKey: primaryPair.version!.values,
            siblingKey: siblingPair.version!.values,
          };

          final platform = ObservingCachePlatform(bridge.platform('primary'));
          Map<String, Object?>? rejectedProof;
          platform.beforeInvoke = (method, arguments) {
            if (method != 'validAll') return;
            rejectedProof = Map.of(arguments);
            if (throwsValidation) {
              throw StateError('Synthetic order validation failure.');
            }
            arguments['rejectValidation'] = true;
          };
          final primary = reporting(
            primaryId,
            (_) async {
              throw StateError('Admission failure must prevent this request.');
            },
            fallback: sibling,
            platform: platform,
          );
          final poll = AutomaticPollContext(
            readInterval:
                () async => throw StateError('Synthetic cadence failure.'),
          );
          final result = await poll.run(
            () => CapturedDashboardLoad.capture(primary.load),
          );
          final failure = result.loadException!;
          expect(failure.issue, DashboardSyncIssue.credentialUnavailable);
          expect(
            failure.reportingOutcomes.map((outcome) => outcome.connection),
            [siblingId, primaryId],
          );
          for (final outcome in failure.reportingOutcomes) {
            expect(outcome.category, ReportingOutcomeCategory.localReadFailure);
            expect(outcome.source, ReportingOutcomeSource.local);
            expect(
              outcome.credentialVersion?.values,
              versions[outcome.connection.storageKey],
            );
          }
          expect(requests, staleSibling ? 1 : 0);
          expect(failure.connectionVersions, versions);
          expect(
            failure.snapshotOrdering[primaryKey]?.selectionUnverified,
            isTrue,
          );
          expect(
            failure.snapshotOrdering[primaryKey]?.emptyCacheOrder,
            primaryPair.order,
          );
          expect(
            failure.snapshotOrdering[siblingKey]?.confirmedRowId,
            siblingPair.record?.rowId,
          );
          expect(
            failure.snapshotOrdering[siblingKey]?.emptyCacheOrder,
            siblingPair.order,
          );
          final proof = rejectedProof!;
          expect(proof['versions'], versions);
          expect(await bridge.invoke('reader', 'validAll', proof), isTrue);
          expect(await primary.isFailureCurrent(failure), isFalse);
          expect(rejectedProof, same(proof));
        },
      );
    }

    test(
      'a readable replacement cannot qualify an earlier reporting key read failure',
      () async {
        final id = ids.first;
        await store('ui').writeSecret(id, 'synthetic-A');
        secure.failRead = true;
        final held = Completer<DashboardSnapshot>();
        final read = Completer<void>();
        secure.onRead = (_, _) {
          if (!read.isCompleted) read.complete();
        };
        final repository = reporting(
          id,
          (_) async => throw StateError('No network work is allowed'),
          fallback: _HeldDashboardRepository(held.future),
        );
        final observations = <ConnectionReportingUpdate>[];
        final pending = CapturedDashboardLoad.capture(
          () => repository.loadObserved(observations.add),
        );
        try {
          await Future.any([
            read.future,
            pending.then<void>((_) {
              throw StateError('Reporting load skipped the credential read.');
            }),
          ]);
          secure.failRead = false;
          await store('worker').writeSecret(id, 'synthetic-B');
          held.complete(DashboardSnapshot.empty());
          final result = await pending;
          expect(observations, isEmpty);
          expect(
            result.reportingOutcomes.single.category,
            ReportingOutcomeCategory.localReadFailure,
          );
          expect(
            result.snapshotOrdering[id.storageKey]?.selectionUnverified,
            isTrue,
          );
          expect(() => result.value, throwsA(isA<DashboardLoadException>()));
        } finally {
          secure.onRead = null;
          secure.failRead = false;
          if (!held.isCompleted) held.complete(DashboardSnapshot.empty());
          await pending;
        }
      },
    );

    for (final nested in [false, true]) {
      test(
        nested
            ? 'a nested Cursor report-time read failure is retired by cross-engine session removal'
            : 'Cursor report-time read failure is retired by cross-engine session removal',
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
            openAiAndCodex:
                nested
                    ? const NoProvidersDashboardRepository()
                    : _HeldDashboardRepository(held.future),
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
            cursorReportingClient: CursorPlatformClient(http: http),
            cursorSessionClient: CursorPlanClient(http: http),
            mergeSnapshots: _merge,
            logger: const _SilentLogger(),
          );
          final innerCompleted = Completer<CapturedDashboardLoad>();
          final aggregate =
              nested
                  ? MergingConnectionRepository(
                    fallback: _ObservedDashboardRepository(
                      repository,
                      innerCompleted.complete,
                    ),
                    loadReport: () async => (await held.future).toJsonString(),
                    normalizeReport: (value) => value,
                    mapError:
                        (error) =>
                            mapReportingError(error, const _SilentLogger()),
                  )
                  : repository;
          final result = CapturedDashboardLoad.capture(
            () => aggregate.loadObserved((update) {
              if (update.connection == id && update.outcome != null)
                observed.complete(update.outcome!);
            }),
          );
          try {
            final failure = await Future.any([
              observed.future,
              if (nested)
                innerCompleted.future.then<ConnectionReportingOutcome>((_) {
                  throw StateError('The Cursor read failure was not observed.');
                }),
            ]);
            expect(cacheReads, 1);
            expect(failure.category, ReportingOutcomeCategory.localReadFailure);
            expect(failure.credentialVersion, isNull);
            DashboardLoadException? innerFailure;
            if (nested) {
              innerFailure = (await innerCompleted.future).loadException!;
              expect(innerFailure.reportingOutcomes.single, same(failure));
              expect(await repository.isFailureCurrent(innerFailure), isTrue);
            }
            await store('worker').deleteSecret(id);
            if (innerFailure != null) {
              expect(await repository.isFailureCurrent(innerFailure), isFalse);
            }
            held.complete(DashboardSnapshot.empty());
            final captured = await result;
            expect(captured.reportingOutcomes, isEmpty);
            expect(transport.requests, isEmpty);
            if (nested) {
              expect(
                captured.loadException?.issue,
                DashboardSyncIssue.dashboardUnavailable,
              );
              expect(
                captured.loadException?.details,
                'Connection changed during refresh.',
              );
              expect(
                await aggregate.isFailureCurrent(captured.loadException!),
                isFalse,
              );
            }
          } finally {
            if (!held.isCompleted) held.complete(DashboardSnapshot.empty());
            await result;
          }
        },
      );
    }

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
      const id = 'openai.platform';
      await credentials('ui', id).write('fake-A');
      var fail = false;
      final ui = repository(
        'ui',
        id,
        () async =>
            fail
                ? throw StateError('Sanitized failure.')
                : _snapshot('openai', id, firstAt, 10).toJsonString(),
      );
      await bridge.invoke('test', 'failCommit', {'value': true});
      try {
        final fresh = await ui.load();
        expect(fresh.connectionVersions, isNotEmpty);
        expect((await cache('reader', id).capture()).snapshot, isNull);

        fail = true;
        final retained = await ui.load();
        expect(retained.connectionVersions, fresh.connectionVersions);
        expect(retained.accounts.single.status, ProviderStatus.stale);
        expect(retained.accounts.single.today.spent?.minorUnits, 10);
        expect(retained.generatedAt, firstAt);
      } finally {
        await bridge.invoke('test', 'failCommit', {'value': false});
      }
    },
  );
  test(
    'legacy fallback keeps newer memory until a newer disk row is confirmed',
    () async {
      const id = 'openai.platform';
      final access = credentials('ui', id);
      await access.write('fake-A');
      final version = (await access.read())!.version;
      final worker = cache('worker', id);
      expect(
        await worker.store(_snapshot('openai', id, firstAt, 10), version),
        isTrue,
      );
      final platform = ObservingCachePlatform(bridge.platform('ui'));
      var fail = false;
      final ui = repository(
        'ui',
        id,
        () async =>
            fail
                ? throw StateError('Sanitized failure.')
                : _snapshot('openai', id, nextAt, 20).toJsonString(),
        cachePlatform: platform,
      );
      await bridge.invoke('test', 'failCommit', {'value': true});
      try {
        final fresh = await ui.load();
        expect(fresh.connectionVersions, isNotEmpty);
        expect(fresh.accounts.single.today.spent?.minorUnits, 20);
        fail = true;
        final retained = await ui.load();
        expect(retained.accounts.single.status, ProviderStatus.stale);
        expect(retained.accounts.single.today.spent?.minorUnits, 20);
        expect(retained.generatedAt, nextAt);
      } finally {
        await bridge.invoke('test', 'failCommit', {'value': false});
      }

      final newerAt = nextAt.add(const Duration(microseconds: 1));
      bool? stored;
      platform.onComplete = (method, arguments, _) async {
        if (method == 'readSnapshot' && arguments['forSelection'] == true) {
          // Commit after the final paired read has sampled the earlier row.
          platform.onComplete = null;
          stored = await worker.store(
            _snapshot('openai', id, newerAt, 30),
            version,
          );
        }
      };
      final recovered = await ui.load();
      expect(stored, isTrue);
      expect(recovered.accounts.single.status, ProviderStatus.stale);
      expect(recovered.accounts.single.today.spent?.minorUnits, 30);
      expect(recovered.generatedAt, newerAt);
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

String _codexReport(String generatedAt, int usedPercent) {
  final report =
      jsonDecode(
            File(
              '../../fixtures/providers/codex/report.json',
            ).readAsStringSync(),
          )
          as Map<String, dynamic>;
  report['generatedAt'] = generatedAt;
  final limits = report['rateLimits'] as Map;
  limits['rateLimits']['primary']['usedPercent'] = usedPercent;
  limits['rateLimitsByLimitId']['codex']['primary']['usedPercent'] =
      usedPercent;
  return jsonEncode(report);
}

void _expectCodexUsage(
  DashboardSnapshot snapshot,
  int usedPercent, {
  required String reason,
}) {
  final account = snapshot.accounts.singleWhere(
    (account) => account.provider == 'codex',
  );
  expect(account.accountId, 'codex-local', reason: reason);
  expect(account.connection, 'openai.plan', reason: reason);
  final allowance = account.allowances.singleWhere(
    (allowance) => allowance.source == AllowanceSource.plan,
  );
  expect(allowance.id, 'codex-primary', reason: reason);
  expect(allowance.usedPercent, usedPercent, reason: '$reason: retained usage');
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

final class _ObservedDashboardRepository extends DashboardRepository {
  const _ObservedDashboardRepository(this.delegate, this.onCompleted);

  final DashboardRepository delegate;
  final void Function(CapturedDashboardLoad) onCompleted;

  @override
  Future<DashboardSnapshot> load() => loadObserved((_) {});

  @override
  Future<DashboardSnapshot> loadObserved(ReportingObserver observer) async {
    final result = await CapturedDashboardLoad.capture(
      () => delegate.loadObserved(observer),
    );
    onCompleted(result);
    return result.value;
  }

  @override
  Future<bool> isSnapshotCurrent(DashboardSnapshot snapshot) =>
      delegate.isSnapshotCurrent(snapshot);
}

final class _EmptyReportingTransport implements ProviderHttpTransport {
  _EmptyReportingTransport({this.denyCursor = false});
  final bool denyCursor;
  final requests = <String>[];
  final uris = <Uri>[];
  Map<String, dynamic>? eventRequest;
  ProviderHttpResponse reply(Uri uri, [String? requestBody]) {
    requests.add(uri.path);
    uris.add(uri);
    if (denyCursor && uri.path == '/api/usage-summary') {
      return const ProviderHttpResponse(
        statusCode: 403,
        headers: {},
        body: '{}',
      );
    }
    if (uri.path == '/teams/filtered-usage-events') {
      eventRequest = jsonDecode(requestBody!) as Map<String, dynamic>;
      return ProviderHttpResponse(
        statusCode: 200,
        headers: const {},
        body: jsonEncode({
          'usageEvents': <Object>[],
          'totalUsageEventsCount': 0,
          'pagination': {
            'numPages': 1,
            'currentPage': 1,
            'pageSize': 1000,
            'hasNextPage': false,
            'hasPreviousPage': false,
          },
          'period': {
            'startDate': eventRequest!['startDate'],
            'endDate': eventRequest!['endDate'],
          },
        }),
      );
    }
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
  }) async => reply(uri, body);
}

final class _CursorUsageTransport implements ProviderHttpTransport {
  const _CursorUsageTransport(this.usage);
  final Future<int> Function() usage;

  @override
  Future<ProviderHttpResponse> get(
    Uri uri, {
    required Map<String, String> headers,
  }) async {
    if (uri.path != '/api/usage-summary')
      throw StateError('Unexpected synthetic Cursor request.');
    return ProviderHttpResponse(
      statusCode: 200,
      headers: const {},
      body: jsonEncode({
        'membershipType': 'pro_plus',
        'individualUsage': {
          'plan': {
            'enabled': true,
            'autoPercentUsed': await usage(),
            'apiPercentUsed': 20,
          },
        },
      }),
    );
  }

  @override
  Future<ProviderHttpResponse> post(
    Uri uri, {
    required Map<String, String> headers,
    String? body,
  }) async => throw StateError('Unexpected synthetic Cursor request.');
}

final class _HeldReadFailure implements ConnectionCredentialAccess {
  @override
  Future<void> observeLifecycle(
    void Function(String, CredentialVersion?) observer,
  ) async => throw StateError('Synthetic storage read failure');
  @override
  Future<void> admitAutomatic(CredentialVersion expected) async {}
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
  Future<void> deleteSecret(
    ProviderConnectionId id, {
    void Function(CredentialVersion)? onRetired,
  }) async => throw UnsupportedError('Read-only fixture');
  @override
  Future<void> writeLabel(ProviderConnectionId id, String? value) async =>
      throw UnsupportedError('Read-only fixture');
}

final class _CurrentReadFailure implements ConnectionCredentialAccess {
  @override
  Future<void> observeLifecycle(
    void Function(String, CredentialVersion?) observer,
  ) => access.observeLifecycle(observer);
  @override
  Future<void> admitAutomatic(CredentialVersion expected) =>
      access.admitAutomatic(expected);
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

final class _RecordingCachePlatform implements ConnectionCachePlatform {
  _RecordingCachePlatform(this.delegate);
  final ConnectionCachePlatform delegate;
  final methods = <String>[];
  bool failSnapshotRead = false;
  @override
  Future<Object?> invoke(String method, Map<String, Object?> arguments) {
    methods.add(method);
    if (failSnapshotRead && method == 'readSnapshot') {
      return Future.error(StateError('Sanitized snapshot read failure.'));
    }
    return delegate.invoke(method, arguments);
  }
}

void _expectSelectedBudgetFreshness(
  DashboardSnapshot snapshot,
  String connection, {
  required bool stale,
}) {
  final id = 'budget.$connection.month';
  final watch = jsonDecode(
    WatchDashboardSummaryPayload.fromSnapshot(
      snapshot,
      WatchRingPreferences(selectedIds: [id]),
    ).encode(),
  );
  expect((watch['rings'] as List).single['id'], id);
  expect(watch['isStale'], stale);
  final widget = buildPhoneWidgetPayload(
    snapshot,
    PhoneWidgetPreferences(selectedIds: [id]),
  );
  expect(widget.rows.single.spent, isNotNull);
  expect(widget.stale, stale);
}

CodexAccountSession _historySession(
  String principal,
  DateTime at, {
  String token = 'initial',
}) => CodexAccountSession(
  accountId: principal,
  accessToken:
      'header.${base64Url.encode(utf8.encode(jsonEncode({'exp': at.add(const Duration(days: 1)).millisecondsSinceEpoch ~/ 1000})))}.$token',
  refreshToken: 'synthetic-refresh-$token',
  refreshedAt: at,
);

final class _HistoryCodexTransport implements CodexHttpTransport {
  _HistoryCodexTransport(this.at);
  final DateTime at;
  int? used = 20;
  @override
  Future<CodexHttpResponse> send(
    String method,
    Uri uri, {
    required Map<String, String> headers,
    String? body,
  }) async {
    final Object response;
    if (uri.path.endsWith('/usage')) {
      response = {
        'plan_type': 'plus',
        'rate_limit': {
          'allowed': true,
          'limit_reached': false,
          'primary_window': {
            'used_percent': 20,
            'limit_window_seconds': 18000,
            'reset_at':
                at.add(const Duration(hours: 1)).millisecondsSinceEpoch ~/ 1000,
          },
          if (used != null)
            'secondary_window': {
              'used_percent': used,
              'limit_window_seconds': 604800,
              'reset_at':
                  at.add(const Duration(days: 1)).millisecondsSinceEpoch ~/
                  1000,
            },
        },
      };
    } else if (uri.path.endsWith('/profiles/me')) {
      response = {
        'stats': {'daily_usage_buckets': <Object>[]},
      };
    } else {
      throw StateError('Unexpected synthetic Codex request.');
    }
    return CodexHttpResponse(statusCode: 200, body: jsonEncode(response));
  }
}

final class _HistoryReportingTransport implements ProviderHttpTransport {
  _HistoryReportingTransport(this.at, {this.cost = '9.00'});
  final DateTime at;
  final String cost;
  int used = 20;
  @override
  Future<ProviderHttpResponse> get(
    Uri uri, {
    required Map<String, String> headers,
  }) async {
    final Object response;
    if (uri.path == '/api/usage-summary') {
      response = {
        'billingCycleStart':
            at.subtract(const Duration(days: 1)).toIso8601String(),
        'billingCycleEnd': at.add(const Duration(days: 29)).toIso8601String(),
        'membershipType': 'pro',
        'isUnlimited': false,
        'individualUsage': {
          'plan': {
            'enabled': true,
            'used': used,
            'limit': 100,
            'remaining': 100 - used,
            'totalPercentUsed': used,
          },
        },
      };
    } else if (uri.path.endsWith('/costs')) {
      final start = DateTime.utc(at.year, at.month, at.day);
      response = {
        'object': 'page',
        'has_more': false,
        'data': [
          {
            'object': 'bucket',
            'start_time': start.millisecondsSinceEpoch ~/ 1000,
            'end_time':
                start.add(const Duration(days: 1)).millisecondsSinceEpoch ~/
                1000,
            'results': [
              {
                'object': 'organization.costs.result',
                'amount': {'value': cost, 'currency': 'usd'},
              },
            ],
          },
        ],
      };
    } else {
      response = {'object': 'page', 'has_more': false, 'data': <Object>[]};
    }
    return ProviderHttpResponse(
      statusCode: 200,
      headers: const {},
      body: jsonEncode(response),
    );
  }

  @override
  Future<ProviderHttpResponse> post(
    Uri uri, {
    required Map<String, String> headers,
    String? body,
  }) async => throw StateError('Unexpected synthetic reporting request.');
}

final class _HistoryRecoveryNotifier implements RecoveryNotifier {
  final reported = <PlanRecovery>[];
  @override
  Future<void> notify(PlanRecovery recovery) async {
    reported.add(recovery);
  }

  @override
  Future<bool> requestPermission() async => true;
}

final class _HistoryAlertNotifier implements AlertNotifier {
  final posts = <AlertConditionKey>[];
  @override
  Future<bool> canPost() async => true;
  @override
  Future<bool> requestPermission() async => true;
  @override
  Future<void> notify(
    AlertConditionKey key, {
    required String title,
    required String body,
  }) async {
    posts.add(key);
  }
}

final class _HistoryWake implements RecoveryWakeScheduler {
  final booked = <DateTime>[];
  int cancelled = 0;
  @override
  Future<void> scheduleAt(DateTime instant) async {
    booked.add(instant);
  }

  @override
  Future<void> cancel() async {
    cancelled++;
  }
}
