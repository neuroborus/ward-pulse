import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:ward_pulse_phone/dashboard/phone_live_bindings.dart';
import 'package:ward_pulse_phone/providers/provider_connection.dart';
import 'package:ward_pulse_phone/providers/provider_credential_store.dart';
import 'package:ward_pulse_phone/providers/claude_account_store.dart';
import 'package:ward_pulse_phone/providers/codex_account_store.dart';
import 'package:ward_pulse_phone/providers/connection_rejection_notice.dart';
import 'package:ward_pulse_phone/providers/connection_lifecycle.dart';
import 'package:ward_pulse_phone/sync/claude_account_client.dart';
import 'package:ward_pulse_phone/sync/codex_account_client.dart';
import 'package:ward_pulse_phone/sync/openai_reporting_client.dart';
import 'package:ward_pulse_phone/sync/provider_reporting.dart';
import 'package:ward_pulse_phone/sync/provider_reporting_clients.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ward_pulse_phone/dashboard/apply_alert_settings.dart';
import 'package:ward_pulse_phone/dashboard/dashboard_models.dart';
import 'package:ward_pulse_phone/dashboard/dashboard_repository.dart';
import 'package:ward_pulse_phone/dashboard/plan_recoveries.dart';
import 'package:ward_pulse_phone/settings/alert_threshold_preferences.dart';
import 'package:ward_pulse_phone/settings/debug_data_preferences.dart';
import 'package:ward_pulse_phone/settings/recovery_notification_preferences.dart';
import 'package:ward_pulse_phone/settings/watch_ring_preferences.dart';
import 'package:ward_pulse_phone/sync/headless_provider_sync.dart';
import 'package:ward_pulse_phone/sync/provider_sync_once.dart';
import 'package:ward_pulse_phone/sync/watch_sync_service.dart';
import 'package:ward_pulse_phone/sync/automatic_poll.dart';
import 'package:ward_pulse_phone/sync/recovery_notifications.dart';
import 'package:ward_pulse_phone/sync/recovery_wake.dart';
import 'package:ward_pulse_phone/sync/recovery_watchlist.dart';
import 'package:ward_pulse_phone/widget/phone_widget_preferences.dart';
import 'package:ward_pulse_phone/widget/phone_widget_sync.dart';

import 'connection_cache_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // Debug test builds read the saved Mock choice; absent means Live.
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  test(
    'setup failure after wholly skipped work cannot mark the widget stale',
    () async {
      var staleWrites = 0;
      await providerSyncOnce(
        load: (_) async {
          final poll = AutomaticPollContext.current!;
          poll.skipped['openai.platform'] = AutomaticPollSkipped(
            'openai.platform',
            CredentialVersion({}),
            DateTime.utc(2026, 11, 6),
          );
          throw StateError('Synthetic post-load failure');
        },
        markWidgetStale: ({required isCurrent}) async {
          staleWrites++;
        },
        logFailure: (_, _, _) {},
      );
      expect(staleWrites, 0);
    },
  );
  test(
    'both registered headless tasks retain their automatic origin',
    () async {
      for (final entry
          in {
            HeadlessProviderSync.taskName: AutomaticPollOrigin.periodic,
            WorkmanagerRecoveryWakeScheduler.taskName:
                AutomaticPollOrigin.resetWake,
          }.entries) {
        AutomaticPollOrigin? observed;
        await runHeadlessProviderTask(
          entry.key,
          sync: () async {
            observed = AutomaticPollContext.current?.origin;
          },
        );
        expect(observed, entry.value);
        expect(AutomaticPollContext.current, isNull);
      }
    },
  );

  group('production shared collection rejection wiring', () {
    late NativeCacheTestBridge bridge;
    setUpAll(AndroidFlutterLocalNotificationsPlugin.registerWith);
    setUpAll(() async {
      bridge = await NativeCacheTestBridge.start();
    });
    tearDownAll(() => bridge.close());
    setUp(() async {
      FlutterSecureStorage.setMockInitialValues({});
      await bridge.reset();
    });
    for (final boundary in [
      'cache capture',
      'paired cache read',
      'rejected cache pair',
      'cache pair during reconnect',
      'credential read after a valid cache pair',
      'cache probe before activation',
      'fetch acquisition',
      'credential read and rejected final lease',
      'credential read and throwing final lease check',
    ]) {
      final reconnectDuringPair = boundary == 'cache pair during reconnect';
      final reconnectAfterPair =
          boundary == 'credential read after a valid cache pair';
      final activatesAfterProbe = boundary == 'cache probe before activation';
      final pendingReconnect = reconnectDuringPair || reconnectAfterPair;
      final rejectedPair =
          boundary == 'rejected cache pair' || reconnectDuringPair;
      final acquisitionFails = boundary == 'fetch acquisition';
      final finalLeaseRejects =
          boundary == 'credential read and rejected final lease';
      final finalLeaseThrows =
          boundary == 'credential read and throwing final lease check';
      final finalLeaseFails = finalLeaseRejects || finalLeaseThrows;
      final pairedReadFails =
          boundary == 'paired cache read' || acquisitionFails;
      final readThrows = !pendingReconnect && !acquisitionFails;
      test('unavailable initial $boundary preserves newer surfaces', () async {
        const id = ProviderConnections.cursorPlan;
        final secure = FakeSecureStorage();
        final foreground = SecureProviderCredentialStore(
          storage: secure,
          platform: bridge.platform('ui'),
        );
        await foreground.writeSecret(id, 'synthetic-session');
        final version = (await foreground.readVersion(id))!;
        if (activatesAfterProbe) await foreground.deleteSecret(id);
        await SecureWatchRingPreferenceStore().write(
          const WatchRingPreferences(selectedIds: [cursorOwnPoolId]),
        );
        await SecurePhoneWidgetPreferenceStore().write(
          const PhoneWidgetPreferences(selectedIds: [cursorOwnPoolId]),
        );

        final reading = Completer<void>();
        final release = Completer<void>();
        final older = ObservingCachePlatform(bridge.platform('older'));
        var credentialReads = 0;
        var failedSecureReads = 0;
        var failedPairs = 0;
        Object? pairReply;
        Object? finalLeaseReply;
        Object? credentialMode;
        Object? initialMode;
        CredentialVersion? reconnect;
        if (finalLeaseFails) {
          secure.onRead = (key, _) {
            if (key == secure.failReadKey) failedSecureReads++;
          };
        }
        older.onComplete = (method, arguments, result) async {
          if (arguments['connection'] != id.storageKey) return;
          if (method == 'readSnapshot' && arguments['forSelection'] != true) {
            pairReply = result;
            if (reconnectAfterPair)
              reconnect = await foreground.beginReconnect(id);
            if (finalLeaseFails) secure.failReadKey = secure.values.keys.single;
          }
          if (finalLeaseFails && method == 'validFetch') {
            finalLeaseReply = result;
            secure.failReadKey = null;
            if (finalLeaseThrows) {
              throw StateError('Synthetic final fetch validation failure.');
            }
          }
          if (pendingReconnect &&
              method == 'acquire' &&
              arguments['action'] == 'read') {
            credentialMode = (result as Map)['mode'];
          }
          if (activatesAfterProbe &&
              credentialReads == 1 &&
              method == 'finish' &&
              arguments['operation'] == 'release') {
            initialMode = (result as Map)['mode'];
            await foreground.writeSecret(id, 'synthetic-reconnect');
          }
          if ((pendingReconnect || activatesAfterProbe || finalLeaseFails) &&
              method == 'releaseFetch') {
            reading.complete();
            await release.future;
          }
        };
        older.beforeInvoke = (method, arguments) async {
          if (arguments['connection'] != id.storageKey) return;
          if (finalLeaseRejects && method == 'validFetch') {
            // Retire only this fetch; the final check sees the native rejection.
            await bridge.invoke('older', 'releaseFetch', arguments);
          }
          if (rejectedPair && method == 'readSnapshot') {
            await foreground.deleteSecret(id);
            if (reconnectDuringPair)
              reconnect = await foreground.beginReconnect(id);
          }
          if (pairedReadFails && method == 'readSnapshot') {
            failedPairs++;
            throw StateError('Synthetic paired cache read failure.');
          }
          if ((pairedReadFails || (rejectedPair && !pendingReconnect)) &&
              method == 'acquireFetch') {
            reading.complete();
            await release.future;
            if (acquisitionFails) {
              throw StateError('Synthetic fetch acquisition failure.');
            }
          }
          if (method != 'acquire' || arguments['action'] != 'read') return;
          credentialReads++;
          if (finalLeaseFails) return;
          if (activatesAfterProbe) {
            if (credentialReads == 2) {
              throw StateError('Synthetic credential read failure.');
            }
            return;
          }
          if (rejectedPair || pendingReconnect) {
            if (!pendingReconnect && credentialReads > 2) {
              throw StateError('Synthetic credential read failure.');
            }
            return;
          }
          if (!pairedReadFails) {
            reading.complete();
            await release.future;
          }
          if (!pairedReadFails || credentialReads > 1) {
            throw StateError('Synthetic credential read failure.');
          }
        };
        final capture = _SurfaceCapture();
        final calls = _bindSurfaces(capture: capture);
        final failures = <(String, Object)>[];
        PhoneLiveBindings createLive(
          ConnectionCachePlatform platform,
          _CursorPlanTransport transport,
        ) => PhoneLiveBindings.create(
          secureStorage: secure,
          cachePlatform: platform,
          cursorClient: CursorPlanClient(
            http: ProviderReportingHttp(transport: transport),
          ),
        );
        Future<void> run(PhoneLiveBindings live) => providerSyncOnce(
          debugBuild: false,
          load:
              (owner) => loadProviderSyncWork(
                owner,
                createLive: () => live,
                readWindows: (_) => const [],
              ),
          logFailure: (step, error, _) => failures.add((step, error)),
        );

        if (reconnectAfterPair) {
          await createLive(
            bridge.platform('seed'),
            const _CursorPlanTransport(40),
          ).repository.load();
        }
        var requests = 0;
        final olderLive = createLive(
          older,
          _CursorPlanTransport(40, onRequest: () => requests++),
        );
        final pending = run(olderLive);
        try {
          await Future.any([
            reading.future,
            pending.then<void>((_) {
              throw StateError('Headless load finished before the barrier.');
            }),
          ]);
          if (reconnectAfterPair) {
            expect(pairReply, containsPair('valid', true));
            expect(pairReply, containsPair('rowId', isA<String>()));
          }
          if (finalLeaseFails) {
            expect(pairReply, containsPair('valid', true));
            expect(failedSecureReads, 1);
            expect(finalLeaseReply, finalLeaseThrows);
          }
          if (rejectedPair) expect(pairReply, containsPair('valid', false));
          if (activatesAfterProbe) {
            expect(initialMode, 'deleted');
            expect(pairReply, isNull);
          }
          if (rejectedPair || pendingReconnect) {
            expect(await foreground.readVersion(id), isNull);
            if (pendingReconnect) {
              expect(credentialMode, 'pending');
              expect(
                await foreground.completeReconnect(
                  id,
                  'synthetic-reconnect',
                  reconnect!,
                ),
                isTrue,
              );
            } else {
              await foreground.writeSecret(id, 'synthetic-reconnect');
            }
          }
          final publishedVersion = (await foreground.readVersion(id))!;
          expect(
            publishedVersion.sameCache(version),
            !(rejectedPair || pendingReconnect || activatesAfterProbe),
          );
          final newerLive = createLive(
            bridge.platform('newer'),
            const _CursorPlanTransport(70),
          );
          await run(newerLive);
          expect(failures, isEmpty);
          expect(_watchUsage(capture.watchSummaries.single), {
            cursorOwnPoolId: 70,
          });
          expect(capture.widgetData['row_0_percent'], '30% left');
          expect(capture.widgetData['stale'], '0');
          final foregroundSnapshot =
              reconnectAfterPair || finalLeaseFails
                  ? await newerLive.repository.load()
                  : null;
          final published = Map.of(capture.widgetData);
          final dispatched = List.of(calls);
          release.complete();
          await pending;

          expect(calls, dispatched);
          expect(capture.widgetData, published);
          expect(failedPairs, pairedReadFails ? 1 : 0);
          expect(
            credentialReads,
            rejectedPair
                ? 3
                : (reconnectAfterPair ||
                        activatesAfterProbe ||
                        finalLeaseFails ||
                        (pairedReadFails && !acquisitionFails)
                    ? 2
                    : 1),
          );
          expect(requests, 0);
          expect(
            (await foreground.readVersion(id))?.sameCache(publishedVersion),
            isTrue,
          );
          final (step, error) = failures.single;
          expect(step, 'setup');
          final failure = error as DashboardLoadException;
          if (readThrows) {
            expect(failure.issue, DashboardSyncIssue.credentialUnavailable);
            final outcome = failure.reportingOutcomes.single;
            expect(outcome.connection, id);
            expect(outcome.category, ReportingOutcomeCategory.localReadFailure);
            expect(outcome.source, ReportingOutcomeSource.local);
            expect(outcome.credentialVersion, isNull);
          } else {
            expect(failure.details, 'Connection changed during refresh.');
            expect(failure.reportingOutcomes, isEmpty);
          }
          expect(
            failure.snapshotOrdering[id.storageKey]?.selectionUnverified,
            isTrue,
          );
          expect(await olderLive.repository.isFailureCurrent(failure), isFalse);
          if (foregroundSnapshot != null) {
            expect(
              foregroundSnapshot.accounts.single.allowances
                  .singleWhere(
                    (allowance) => allowance.id == 'cursor-plan-models',
                  )
                  .usedPercent,
              70,
            );
            expect(
              await newerLive.repository.isSnapshotCurrent(foregroundSnapshot),
              isTrue,
            );
          }
        } finally {
          if (!release.isCompleted) release.complete();
          await pending;
        }
      });
    }
    test(
      'a valid empty cache pair cannot qualify a later Codex storage failure',
      () async {
        final secure = FakeSecureStorage();
        final platform = ObservingCachePlatform(bridge.platform('worker'));
        final key = ProviderConnections.codexPlan.storageKey;
        final now = DateTime.utc(2026, 11, 5);
        await SecureCodexAccountStore(
          storage: secure,
          platform: platform,
        ).write(
          CodexAccountSession(
            accessToken: 'synthetic-access',
            refreshToken: 'synthetic-refresh',
            accountId: 'synthetic-account',
            refreshedAt: now,
          ),
        );
        Object? cachePair;
        platform.onComplete = (method, arguments, result) {
          if (arguments['connection'] == key && method == 'readSnapshot') {
            cachePair = result;
          }
        };
        var codexReads = 0;
        platform.beforeInvoke = (method, arguments) {
          if (arguments['connection'] != key ||
              method != 'acquire' ||
              arguments['action'] != 'read') {
            return;
          }
          if (++codexReads == 2) {
            throw StateError('Synthetic Codex credential read failure.');
          }
        };
        var requests = 0;
        final live = PhoneLiveBindings.create(
          secureStorage: secure,
          cachePlatform: platform,
          codexClient: CodexAccountClient(
            transport: _RejectedCodexTransport(),
            clock: () => now,
          ),
          cursorClient: CursorPlanClient(
            http: ProviderReportingHttp(
              transport: _CursorPlanTransport(70, onRequest: () => requests++),
            ),
          ),
        );
        await live.credentialStore.writeSecret(
          ProviderConnections.cursorPlan,
          'synthetic-session',
        );
        final calls = _bindSurfaces();
        final failures = <(String, Object)>[];
        await providerSyncOnce(
          debugBuild: false,
          load:
              (owner) => loadProviderSyncWork(
                owner,
                createLive: () => live,
                readWindows: (_) => const [],
              ),
          logFailure: (step, error, _) => failures.add((step, error)),
        );

        expect(cachePair, containsPair('valid', true));
        expect(cachePair, containsPair('order', isA<String>()));
        expect((cachePair as Map)['snapshot'], isNull);
        expect(codexReads, 2);
        expect(requests, 1);
        expect(calls, isEmpty);
        final (step, error) = failures.single;
        expect(step, 'setup');
        final failure = error as DashboardLoadException;
        expect(failure.issue, DashboardSyncIssue.codexUnavailable);
        expect(failure.snapshotOrdering[key]?.selectionUnverified, isTrue);
        expect(await live.repository.isFailureCurrent(failure), isFalse);
      },
    );
    for (final providerFails in [false, true]) {
      final scenario =
          providerFails ? 'current provider failure' : 'unverified selection';
      test('headless widget stale handling after $scenario', () async {
        const id = ProviderConnections.openAiPlatform;
        final secure = FakeSecureStorage();
        final foreground = SecureProviderCredentialStore(
          storage: secure,
          platform: bridge.platform('ui'),
        );
        await foreground.writeSecret(id, 'synthetic-reporting-key');
        final version = (await foreground.readVersion(id))!;
        final platform = ObservingCachePlatform(bridge.platform('headless'));
        var selectionReads = 0;
        var stored = false;
        platform.beforeInvoke = (method, arguments) {
          if (method != 'readSnapshot' ||
              arguments['connection'] != id.storageKey ||
              arguments['forSelection'] != true) {
            return;
          }
          selectionReads++;
          // The first read selects the fetched report. Fail the final paired
          // reread after the aggregate's fallback has completed.
          if (!providerFails && selectionReads == 2) {
            throw StateError('Synthetic final paired read failure.');
          }
        };
        platform.onComplete = (method, arguments, result) {
          if (method == 'writeSnapshot' &&
              arguments['connection'] == id.storageKey &&
              result is Map) {
            stored = result['status'] == 'stored';
          }
        };
        final capture = _SurfaceCapture()..widgetData.addAll(_priorWidgetRows);
        final calls = _bindSurfaces(capture: capture);
        final failures = <(String, Object)>[];
        final live = PhoneLiveBindings.create(
          secureStorage: secure,
          cachePlatform: platform,
          openAiClient: OpenAiReportingClient(
            http: ProviderReportingHttp(
              transport: _OpenAiReportingTransport(
                providerFails: providerFails,
              ),
            ),
          ),
        );
        await providerSyncOnce(
          debugBuild: false,
          load: (owner) => loadProviderSyncWork(owner, createLive: () => live),
          logFailure: (step, error, _) => failures.add((step, error)),
        );

        expect((await foreground.readVersion(id))?.sameCache(version), isTrue);
        expect(selectionReads, providerFails ? 1 : 2);
        expect(stored, !providerFails);
        final (step, error) = failures.single;
        expect(step, 'setup');
        final failure = error as DashboardLoadException;
        if (providerFails) {
          expect(failure.issue, DashboardSyncIssue.providerUnavailable);
          final stale = {..._priorWidgetRows, 'stale': '1'};
          expect(calls, ['markStale', 'updateWidget']);
          expect(capture.widgetData, stale);
          expect(capture.redraws, [stale]);
        } else {
          expect(failure.details, 'Connection changed during refresh.');
          expect(calls, isEmpty);
          expect(capture.widgetData, _priorWidgetRows);
          expect(capture.redraws, isEmpty);
        }
      });
    }
    for (final rejectStamp in [false, true]) {
      final boundary = rejectStamp ? 'stamp' : 'reread';
      test(
        'retired Cursor plan $boundary preserves the newer widget and watch',
        () async {
          const id = ProviderConnections.cursorPlan;
          const sibling = ProviderConnections.openAiPlatform;
          final secure = FakeSecureStorage();
          final foreground = SecureProviderCredentialStore(
            storage: secure,
            platform: bridge.platform('ui'),
          );
          await foreground.writeSecret(id, 'synthetic-old-session');
          if (rejectStamp)
            await foreground.writeSecret(sibling, 'synthetic-key');
          final oldVersion = (await foreground.readVersion(id))!;
          final reachedBoundary = Completer<void>();
          final resumeBoundary = Completer<void>();
          final released = Completer<void>();
          final resumeOld = Completer<void>();
          final siblingReleased = Completer<void>();
          final platform = ObservingCachePlatform(bridge.platform('old'));
          int? oldEra;
          var admitted = false;
          var emptyCache = false;
          var siblingStored = false;
          var validAfterRelease = false;
          bool? selectionValid;
          platform.onComplete = (method, arguments, result) async {
            if (arguments['connection'] == sibling.storageKey) {
              if (method == 'writeSnapshot') {
                siblingStored = (result as Map)['status'] == 'stored';
              }
              if (method == 'releaseFetch') siblingReleased.complete();
            }
            if (arguments['connection'] != id.storageKey) return;
            if (method == 'claimAutomatic')
              admitted = (result as Map)['admitted'] == true;
            if (method == 'stampFetch') oldEra = (result as Map)['era'] as int;
            if (method == 'releaseFetch') {
              released.complete();
              if (rejectStamp) await resumeOld.future;
            }
            if (method == 'valid' && released.isCompleted) {
              validAfterRelease = result == true;
            }
            if (method == 'readSnapshot' && arguments['forSelection'] == true) {
              selectionValid = (result as Map)['valid'] as bool;
            }
            if (method == 'readSnapshot' && arguments['forSelection'] != true) {
              final pair = result as Map;
              emptyCache = pair['valid'] == true && pair['snapshot'] == null;
            }
          };
          platform.beforeInvoke = (method, arguments) async {
            if (arguments['connection'] != id.storageKey ||
                reachedBoundary.isCompleted) {
              return;
            }
            final atBoundary =
                rejectStamp
                    ? method == 'stampFetch'
                    : method == 'readSnapshot' &&
                        arguments['forSelection'] == true;
            if (!atBoundary) return;
            reachedBoundary.complete();
            await resumeBoundary.future;
          };
          await SecurePhoneWidgetPreferenceStore().write(
            const PhoneWidgetPreferences(selectedIds: [cursorOwnPoolId]),
          );
          await SecureWatchRingPreferenceStore().write(
            const WatchRingPreferences(selectedIds: [cursorOwnPoolId]),
          );
          final capture = _SurfaceCapture();
          final calls = _bindSurfaces(capture: capture);
          final failures = <(String, Object)>[];
          Future<void> run(ConnectionCachePlatform native, int usedPercent) =>
              providerSyncOnce(
                debugBuild: false,
                load:
                    (owner) => loadProviderSyncWork(
                      owner,
                      createLive:
                          () => PhoneLiveBindings.create(
                            secureStorage: secure,
                            cachePlatform: native,
                            openAiClient: OpenAiReportingClient(
                              http: ProviderReportingHttp(
                                transport: const _OpenAiReportingTransport(
                                  providerFails: false,
                                ),
                              ),
                            ),
                            cursorClient: CursorPlanClient(
                              http: ProviderReportingHttp(
                                transport: _CursorPlanTransport(usedPercent),
                              ),
                            ),
                          ),
                      readWindows: (_) => const [],
                    ),
                logFailure: (step, error, _) => failures.add((step, error)),
              );
          final old = run(platform, 40);
          final finishedEarly = old.then<void>((_) {
            throw StateError(
              'Old load finished before its held cache operation.',
            );
          });
          try {
            await Future.any([reachedBoundary.future, finishedEarly]);
            expect(admitted, isTrue);
            expect(emptyCache, isTrue);
            expect(released.isCompleted, !rejectStamp);
            if (rejectStamp) {
              await Future.any([siblingReleased.future, finishedEarly]);
              expect(siblingStored, isTrue);
            } else {
              expect(validAfterRelease, isTrue);
              expect(oldEra, isNotNull);
            }
            expect(calls, isEmpty);

            await foreground.writeSecret(id, 'synthetic-new-session');
            if (rejectStamp) {
              resumeBoundary.complete();
              await Future.any([released.future, finishedEarly]);
              expect(oldEra, isNull);
            }
            await run(bridge.platform('new'), 70);
            expect(failures, isEmpty);
            final acceptedWidget = Map.of(capture.widgetData);
            expect(acceptedWidget['row_count'], 1);
            expect(acceptedWidget['row_0_percent'], '30% left');
            expect(acceptedWidget['stale'], '0');
            expect(_watchUsage(capture.watchSummaries.single), {
              cursorOwnPoolId: 70,
            });

            if (!resumeBoundary.isCompleted) resumeBoundary.complete();
            resumeOld.complete();
            await old;
            expect(selectionValid, rejectStamp ? isNull : isFalse);
            expect(calls, ['syncWatchSummary', 'publish', 'updateWidget']);
            expect(capture.widgetData, acceptedWidget);
            expect(capture.redraws, [acceptedWidget]);
            final (step, error) = failures.single;
            expect(step, 'setup');
            final failure = error as DashboardLoadException;
            expect(failure.details, 'Connection changed during refresh.');
            expect(
              failure.connectionVersions[id.storageKey],
              oldVersion.values,
            );
            expect(failure.snapshotOrdering[id.storageKey]?.attemptEra, oldEra);
            if (rejectStamp) {
              expect(
                failure.snapshotOrdering[sibling.storageKey]?.payload,
                isNotNull,
              );
            }
          } finally {
            if (!resumeBoundary.isCompleted) resumeBoundary.complete();
            if (!resumeOld.isCompleted) resumeOld.complete();
            await old;
          }
        },
      );
    }
    for (final (newerWins, failedCheck, throwsValidation, outcome) in [
      (false, null, false, 'unchanged empty cache'),
      (true, null, false, 'newer snapshot'),
      (false, 1, true, 'unavailable selection validation'),
      (false, 2, false, 'rejected outer validation'),
      (false, 2, true, 'unavailable outer validation'),
    ]) {
      test('headless cadence failure settles with $outcome', () async {
        final innerConnection = failedCheck == 2;
        final id =
            innerConnection
                ? ProviderConnections.openAiPlatform
                : ProviderConnections.cursorPlan;
        final key = id.storageKey;
        final secure = FakeSecureStorage();
        final credentials = SecureProviderCredentialStore(
          storage: secure,
          platform: bridge.platform('ui'),
        );
        await credentials.writeSecret(id, 'synthetic-session');
        final version = (await credentials.readVersion(id))!;
        final released = Completer<void>();
        final resume = Completer<void>();
        final older = ObservingCachePlatform(bridge.platform('failed'));
        String? emptyCacheOrder;
        Object? admissionVersion;
        Map<String, Object?>? failedValidation;
        var selectionChecks = 0;
        final validationResults = <Object?>[];
        var stampAttempts = 0;
        var requests = 0;
        older.beforeInvoke = (method, arguments) async {
          if (method == 'validAll' &&
              (arguments['emptyCacheOrders'] as Map?)?[key] != null) {
            if (++selectionChecks == failedCheck) {
              failedValidation = Map.of(arguments);
              if (throwsValidation) {
                throw StateError('Synthetic order validation failure.');
              }
              // Let the inner repository confirm the failure. The next
              // validation belongs to the link handling it as a fallback.
              arguments['rejectValidation'] = true;
            }
          }
          if (arguments['connection'] != key) return;
          if (method == 'stampFetch') stampAttempts++;
          if (method != 'claimAutomatic') return;
          admissionVersion = arguments['expected'];
          // Queue the fault and reset around just this native claim.
          await Future.wait([
            bridge.invoke('test', 'failCommit', {'value': true}),
            bridge.invoke('failed', method, arguments),
            bridge.invoke('test', 'failCommit', {'value': false}),
          ]);
        };
        older.onComplete = (method, arguments, result) async {
          if (method == 'validAll' &&
              (arguments['emptyCacheOrders'] as Map?)?[key] != null) {
            validationResults.add(result);
          }
          if (arguments['connection'] != key) return;
          if (method == 'readSnapshot' && arguments['forSelection'] != true) {
            final pair = result as Map;
            if (pair['valid'] == true && pair['snapshot'] == null) {
              emptyCacheOrder = pair['order'] as String?;
            }
          }
          if (method != 'releaseFetch') return;
          released.complete();
          await resume.future;
        };
        PhoneLiveBindings bindings(
          ConnectionCachePlatform platform,
          _CursorPlanTransport transport,
        ) => PhoneLiveBindings.create(
          secureStorage: secure,
          cachePlatform: platform,
          cursorClient: CursorPlanClient(
            http: ProviderReportingHttp(transport: transport),
          ),
          openAiClient: OpenAiReportingClient(
            http: ProviderReportingHttp(
              transport: _OpenAiReportingTransport(
                providerFails: true,
                onRequest: () => requests++,
              ),
            ),
          ),
        );

        await SecurePhoneWidgetPreferenceStore().write(
          const PhoneWidgetPreferences(selectedIds: [cursorOwnPoolId]),
        );
        await SecureWatchRingPreferenceStore().write(
          const WatchRingPreferences(selectedIds: [cursorOwnPoolId]),
        );
        final capture = _SurfaceCapture()..widgetData.addAll(_priorWidgetRows);
        final calls = _bindSurfaces(capture: capture);
        final failures = <(String, Object)>[];
        Future<void> run(PhoneLiveBindings live) => providerSyncOnce(
          debugBuild: false,
          load:
              (owner) => loadProviderSyncWork(
                owner,
                createLive: () => live,
                readWindows: (_) => const [],
              ),
          logFailure: (step, error, _) => failures.add((step, error)),
        );
        final observations = <ConnectionReportingUpdate>[];
        final failed = bindings(
          older,
          _CursorPlanTransport(40, onRequest: () => requests++),
        );
        final old = run(
          PhoneLiveBindings(
            credentialStore: failed.credentialStore,
            codexAccountService: failed.codexAccountService,
            claudeAccountService: failed.claudeAccountService,
            repository: _ObservedRepository(
              failed.repository,
              observations.add,
            ),
          ),
        );

        try {
          await Future.any([
            released.future,
            old.then<void>((_) {
              throw StateError('Cadence failure settled before release.');
            }),
          ]);
          expect(admissionVersion, version.values);
          expect(emptyCacheOrder, isNotNull);
          expect(calls, isEmpty);

          if (newerWins) {
            final newer = ObservingCachePlatform(bridge.platform('newer'));
            Object? write;
            newer.onComplete = (method, arguments, result) {
              if (method == 'writeSnapshot' && arguments['connection'] == key) {
                write = result;
              }
            };
            await run(bindings(newer, const _CursorPlanTransport(70)));
            expect(write, containsPair('status', 'stored'));
            expect(
              (await credentials.readVersion(id))?.sameCache(version),
              isTrue,
            );
            expect(failures, isEmpty);
            expect(capture.widgetData['row_0_percent'], '30% left');
            expect(capture.widgetData['stale'], '0');
            expect(_watchUsage(capture.watchSummaries.single), {
              cursorOwnPoolId: 70,
            });
          }

          final published = Map.of(capture.widgetData);
          resume.complete();
          await old;
          expect(stampAttempts, 0);
          expect(requests, 0);
          expect(observations, isEmpty);
          final (step, error) = failures.single;
          expect(step, 'setup');
          final failure = error as DashboardLoadException;
          expect(failure.connectionVersions[key], version.values);
          expect(failure.snapshotOrdering[key]?.attemptEra, isNull);
          expect(
            failure.snapshotOrdering[key]?.emptyCacheOrder,
            emptyCacheOrder,
          );
          expect(failure.issue, DashboardSyncIssue.credentialUnavailable);
          final feedback = failure.reportingOutcomes.single;
          expect(feedback.connection, id);
          expect(feedback.category, ReportingOutcomeCategory.localReadFailure);
          expect(feedback.source, ReportingOutcomeSource.local);
          expect(feedback.credentialVersion?.values, version.values);
          if (newerWins || failedCheck != null) {
            expect(failure.snapshotOrdering[key]?.selectionUnverified, isTrue);
            if (failedCheck != null) {
              expect(selectionChecks, failedCheck);
              expect(validationResults, [
                if (innerConnection) true,
                if (!throwsValidation) false,
              ]);
              expect(failedValidation, isNotNull);
              expect(
                await bridge.invoke('reader', 'validAll', failedValidation!),
                isTrue,
              );
              expect(calls, isEmpty);
            } else {
              expect(calls, ['syncWatchSummary', 'publish', 'updateWidget']);
            }
            expect(await failed.repository.isFailureCurrent(failure), isFalse);
            expect(capture.widgetData, published);
            expect(capture.redraws, [if (newerWins) published]);
          } else {
            expect(calls, ['markStale', 'updateWidget']);
            final stale = {..._priorWidgetRows, 'stale': '1'};
            expect(capture.widgetData, stale);
            expect(capture.redraws, [stale]);
          }
        } finally {
          if (!resume.isCompleted) resume.complete();
          await old;
        }
      });
    }
    test(
      'an unverified reporting key read cannot mark newer rows STALE',
      () async {
        const id = ProviderConnections.openAiPlatform;
        final key = id.storageKey;
        final budgetId = 'budget.$key.today';
        final secure = FakeSecureStorage();
        final credentials = SecureProviderCredentialStore(
          storage: secure,
          platform: bridge.platform('newer'),
        );
        await credentials.writeSecret(id, 'synthetic-reporting-key');
        await SecureAlertThresholdPreferenceStore().write(
          AlertThresholdPreferences(
            connections: {
              key: const ConnectionAlertThresholds(
                budget: ConnectionBudget(today: 1000),
              ),
            },
          ),
        );
        await SecurePhoneWidgetPreferenceStore().write(
          PhoneWidgetPreferences(selectedIds: [budgetId]),
        );
        await SecureWatchRingPreferenceStore().write(
          WatchRingPreferences(selectedIds: [budgetId]),
        );

        final older = ObservingCachePlatform(bridge.platform('older'));
        final released = Completer<void>();
        final resume = Completer<void>();
        var failedReads = 0;
        older.beforeInvoke = (method, arguments) {
          if (arguments['connection'] == key &&
              method == 'acquire' &&
              arguments['action'] == 'read') {
            failedReads++;
            throw StateError('Synthetic reporting credential read failure.');
          }
        };
        older.onComplete = (method, arguments, _) async {
          if (arguments['connection'] == key && method == 'releaseFetch') {
            released.complete();
            await resume.future;
          }
        };

        final capture = _SurfaceCapture();
        final calls = _bindSurfaces(capture: capture);
        final failures = <(String, Object)>[];
        PhoneLiveBindings bindings(
          ConnectionCachePlatform platform, {
          void Function()? onRequest,
        }) => PhoneLiveBindings.create(
          secureStorage: secure,
          cachePlatform: platform,
          openAiClient: OpenAiReportingClient(
            http: ProviderReportingHttp(
              transport: _OpenAiReportingTransport(
                providerFails: false,
                onRequest: onRequest,
              ),
            ),
          ),
        );
        Future<void> run(PhoneLiveBindings live) => providerSyncOnce(
          debugBuild: false,
          load:
              (owner) => loadProviderSyncWork(
                owner,
                createLive: () => live,
                readWindows: (_) => const [],
              ),
          logFailure: (step, error, _) => failures.add((step, error)),
        );

        var oldRequests = 0;
        final oldLive = bindings(older, onRequest: () => oldRequests++);
        final old = run(oldLive);
        try {
          await Future.any([
            released.future,
            old.then<void>((_) {
              throw StateError('Reporting load finished before release.');
            }),
          ]);
          await run(bindings(bridge.platform('newer')));
          expect(failures, isEmpty);
          expect(_watchUsage(capture.watchSummaries.single), {budgetId: 0});
          expect(capture.widgetData['row_count'], 1);
          expect(capture.widgetData['stale'], '0');
          final published = Map.of(capture.widgetData);

          resume.complete();
          await old;
          final (step, error) = failures.single;
          expect(step, 'setup');
          final failure = error as DashboardLoadException;
          expect(failure.issue, DashboardSyncIssue.credentialUnavailable);
          final outcome = failure.reportingOutcomes.single;
          expect(outcome.connection, id);
          expect(outcome.category, ReportingOutcomeCategory.localReadFailure);
          expect(outcome.source, ReportingOutcomeSource.local);
          expect(outcome.credentialVersion, isNull);
          expect(failure.snapshotOrdering[key]?.selectionUnverified, isTrue);
          expect(await oldLive.repository.isFailureCurrent(failure), isFalse);
          expect(failedReads, 1);
          expect(oldRequests, 0);
          expect(calls, ['syncWatchSummary', 'publish', 'updateWidget']);
          expect(capture.widgetData, published);
          expect(capture.redraws, [published]);
        } finally {
          if (!resume.isCompleted) resume.complete();
          await old;
        }
      },
    );
    for (final (preFetch, replyThrows) in [
      (false, false),
      (false, true),
      (true, true),
    ]) {
      final fault = replyThrows ? 'throws' : 'rejects the lease';
      final stage = preFetch ? 'pre-fetch' : 'final';
      final outcome = preFetch ? 'after a failed cache read' : 'after storing';
      final scenario = '$stage reporting fetch validation $fault $outcome';
      test(scenario, () async {
        const id = ProviderConnections.openAiPlatform;
        final key = id.storageKey;
        final budgetId = 'budget.$key.today';
        final secure = FakeSecureStorage();
        final credentials = SecureProviderCredentialStore(
          storage: secure,
          platform: bridge.platform('ui'),
        );
        await credentials.writeSecret(id, 'synthetic-reporting-key');
        final version = (await credentials.readVersion(id))!;
        await SecureAlertThresholdPreferenceStore().write(
          AlertThresholdPreferences(
            connections: {
              key: const ConnectionAlertThresholds(
                budget: ConnectionBudget(today: 1000),
              ),
            },
          ),
        );
        await SecurePhoneWidgetPreferenceStore().write(
          PhoneWidgetPreferences(selectedIds: [budgetId]),
        );
        await SecureWatchRingPreferenceStore().write(
          WatchRingPreferences(selectedIds: [budgetId]),
        );

        final older = ObservingCachePlatform(bridge.platform('old'));
        Object? writeResult;
        Object? writeStamp;
        Object? validation;
        var cacheReadFailed = false;
        bool isFaultBoundary(String method, Map<String, Object?> arguments) =>
            method == 'validFetch' &&
            arguments['connection'] == key &&
            (preFetch
                ? cacheReadFailed && validation == null
                : writeResult != null);
        older.beforeInvoke = (method, arguments) async {
          if (preFetch &&
              method == 'readSnapshot' &&
              arguments['connection'] == key) {
            cacheReadFailed = true;
            throw StateError('Synthetic paired cache read failure.');
          }
          if (isFaultBoundary(method, arguments) && !replyThrows) {
            await bridge.invoke('old', 'detach', {});
          }
        };
        older.onComplete = (method, arguments, result) {
          if (method == 'writeSnapshot' && arguments['connection'] == key) {
            writeStamp = arguments['stamp'];
            writeResult = result;
          }
          if (isFaultBoundary(method, arguments)) {
            validation = result;
            if (replyThrows) throw StateError('Synthetic fetch reply failure.');
          }
        };

        final capture = _SurfaceCapture();
        final calls = _bindSurfaces(capture: capture);
        final failures = <(String, Object)>[];
        final reachedFailure = Completer<void>();
        final resumeFailure = Completer<void>();
        var requests = 0;
        Future<void> run(
          ConnectionCachePlatform platform, {
          bool hold = false,
        }) => providerSyncOnce(
          debugBuild: false,
          load: (owner) async {
            try {
              return await loadProviderSyncWork(
                owner,
                createLive:
                    () => PhoneLiveBindings.create(
                      secureStorage: secure,
                      cachePlatform: platform,
                      openAiClient: OpenAiReportingClient(
                        http: ProviderReportingHttp(
                          transport: _OpenAiReportingTransport(
                            providerFails: false,
                            onRequest: () => requests++,
                          ),
                        ),
                      ),
                    ),
                readWindows: (_) => const [],
              );
            } catch (_) {
              if (hold) {
                reachedFailure.complete();
                await resumeFailure.future;
              }
              rethrow;
            }
          },
          logFailure: (step, error, _) => failures.add((step, error)),
        );

        final old = run(older, hold: true);
        try {
          await Future.any([
            reachedFailure.future,
            old.then<void>((_) {
              throw StateError('Old load finished without a setup failure.');
            }),
          ]);
          expect(cacheReadFailed, preFetch);
          expect(writeStamp, preFetch ? isNull : isA<String>());
          expect(
            writeResult,
            preFetch ? isNull : containsPair('status', 'stored'),
          );
          expect(validation, replyThrows);
          expect(requests, preFetch ? 0 : greaterThan(0));

          await bridge.invoke('test', 'setClock', {'value': 3600000});
          final newer = ObservingCachePlatform(bridge.platform('new'));
          Object? newWrite;
          newer.onComplete = (method, arguments, result) {
            if (method == 'writeSnapshot' && arguments['connection'] == key) {
              newWrite = result;
            }
          };
          await run(newer);
          expect(failures, isEmpty);
          expect(newWrite, containsPair('status', 'stored'));
          final publishedWidget = Map.of(capture.widgetData);
          final publishedWatch = capture.watchSummaries.single;
          expect(publishedWidget['row_count'], 1);
          expect(publishedWidget['stale'], '0');
          expect(_watchUsage(publishedWatch), {budgetId: 0});

          resumeFailure.complete();
          await old;
          expect(calls, ['syncWatchSummary', 'publish', 'updateWidget']);
          expect(capture.widgetData, publishedWidget);
          expect(capture.redraws, [publishedWidget]);
          expect(capture.watchSummaries, [publishedWatch]);
          final (step, error) = failures.single;
          expect(step, 'setup');
          final failure = error as DashboardLoadException;
          expect(failure.connectionVersions[key], version.values);
          expect(failure.snapshotOrdering[key]?.selectionUnverified, isTrue);
          expect(failure.reportingOutcomes, isEmpty);
          expect(
            await bridge.invoke('reader', 'validAll', {
              'versions': failure.connectionVersions,
            }),
            isTrue,
          );
        } finally {
          if (!resumeFailure.isCompleted) resumeFailure.complete();
          await old;
        }
      });
    }
    for (final duringFeedback in [true, false]) {
      final stage = duringFeedback ? 'early feedback' : 'final selection';
      test(
        'a Cursor validation exception during $stage settles once',
        () async {
          const id = ProviderConnections.cursorPlan;
          final key = id.storageKey;
          final secure = FakeSecureStorage();
          final credentials = SecureProviderCredentialStore(
            storage: secure,
            platform: bridge.platform('ui'),
          );
          await credentials.writeSecret(id, 'synthetic-session');
          final version = (await credentials.readVersion(id))!;
          await SecurePhoneWidgetPreferenceStore().write(
            const PhoneWidgetPreferences(selectedIds: [cursorOwnPoolId]),
          );
          await SecureWatchRingPreferenceStore().write(
            const WatchRingPreferences(selectedIds: [cursorOwnPoolId]),
          );

          final capture = _SurfaceCapture();
          final calls = _bindSurfaces(capture: capture);
          final failures = <(String, Object)>[];
          Future<void> run(ConnectionCachePlatform platform, int usage) =>
              providerSyncOnce(
                debugBuild: false,
                load:
                    (owner) => loadProviderSyncWork(
                      owner,
                      createLive:
                          () => PhoneLiveBindings.create(
                            secureStorage: secure,
                            cachePlatform: platform,
                            cursorClient: CursorPlanClient(
                              http: ProviderReportingHttp(
                                transport: _CursorPlanTransport(usage),
                              ),
                            ),
                          ),
                      readWindows: (_) => const [],
                    ),
                logFailure: (step, error, _) => failures.add((step, error)),
              );

          await run(bridge.platform('seed'), 40);
          expect(failures, isEmpty);
          expect(calls, ['syncWatchSummary', 'publish', 'updateWidget']);
          final priorWidget = Map.of(capture.widgetData);
          final priorWatch = capture.watchSummaries.single;
          expect(priorWidget['row_0_percent'], '60% left');
          expect(priorWidget['stale'], '0');
          expect(_watchUsage(priorWatch), {cursorOwnPoolId: 40});
          calls.clear();
          await bridge.invoke('test', 'setClock', {'value': 3600000});

          final native = ObservingCachePlatform(bridge.platform('headless'));
          var checks = 0;
          Object? stamped;
          Object? write;
          Map<String, Object?>? interruptedProof;
          Object? interruptedResult;
          native.onComplete = (method, arguments, result) {
            if (arguments['connection'] == key) {
              if (method == 'stampFetch') stamped = result;
              if (method == 'writeSnapshot') write = result;
            }
            if (method != 'validAll' ||
                (arguments['payloadOrders'] as Map?)?[key] == null ||
                ++checks != (duringFeedback ? 1 : 2)) {
              return;
            }
            interruptedProof = Map.of(arguments);
            interruptedResult = result;
            throw StateError('Synthetic native validation reply failure.');
          };
          await run(native, 70);

          expect(stamped, containsPair('stamp', isA<String>()));
          expect(write, containsPair('status', 'stored'));
          expect(interruptedResult, isTrue);
          final proof = interruptedProof!;
          expect((proof['versions'] as Map)[key], version.values);
          expect(await bridge.invoke('reader', 'validAll', proof), isTrue);
          if (duringFeedback) {
            expect(checks, greaterThan(1));
            expect(failures, isEmpty);
            expect(calls, ['syncWatchSummary', 'publish', 'updateWidget']);
            expect(capture.widgetData['row_0_percent'], '30% left');
            expect(capture.widgetData['stale'], '0');
            expect(capture.redraws, [priorWidget, capture.widgetData]);
            expect(capture.watchSummaries, hasLength(2));
            expect(_watchUsage(capture.watchSummaries.last), {
              cursorOwnPoolId: 70,
            });
          } else {
            expect(checks, 2);
            final (step, error) = failures.single;
            expect(step, 'setup');
            final failure = error as DashboardLoadException;
            expect(failure.details, 'Connection changed during refresh.');
            expect(failure.connectionVersions[key], version.values);
            expect(failure.snapshotOrdering[key]?.selectionUnverified, isTrue);
            expect(calls, isEmpty);
            expect(capture.widgetData, priorWidget);
            expect(capture.redraws, [priorWidget]);
            expect(capture.watchSummaries, [priorWatch]);
          }
        },
      );
    }
    test(
      'a validation error on a retired load preserves the corrected surfaces',
      () async {
        const id = ProviderConnections.cursorPlan;
        final key = id.storageKey;
        final secure = FakeSecureStorage();
        final foreground = SecureProviderCredentialStore(
          storage: secure,
          platform: bridge.platform('ui'),
        );
        await foreground.writeSecret(id, 'synthetic-session');
        final version = (await foreground.readVersion(id))!;
        final initial = DateTime.utc(2026, 1, 1);
        Future<void> setClock(DateTime at) async {
          await bridge.invoke('test', 'setClock', {
            'value': at.millisecondsSinceEpoch,
          });
        }

        await setClock(initial);
        final reachedReread = Completer<void>();
        final resumeReread = Completer<void>();
        final older = ObservingCachePlatform(bridge.platform('old'));
        var selectionReads = 0;
        Map<String, Object?>? failedValidation;
        older.beforeInvoke = (method, arguments) async {
          if (method == 'validAll' &&
              selectionReads == 2 &&
              failedValidation == null) {
            failedValidation = arguments;
            throw StateError('Synthetic order validation failure.');
          }
          if (arguments['connection'] != key) return;
          if (method == 'stampFetch') {
            // Keep the cadence anchor early enough to admit the corrected run.
            await setClock(initial.add(const Duration(days: 1)));
          }
          if (method == 'readSnapshot' && arguments['forSelection'] == true) {
            if (++selectionReads != 2) return;
            reachedReread.complete();
            await resumeReread.future;
          }
        };
        final corrected = ObservingCachePlatform(bridge.platform('corrected'));
        Object? correctedWrite;
        corrected.beforeInvoke = (method, arguments) async {
          if (method == 'writeSnapshot' && arguments['connection'] == key)
            await bridge.invoke('test', 'failCommit', {'value': true});
        };
        corrected.onComplete = (method, arguments, result) async {
          if (method != 'writeSnapshot' || arguments['connection'] != key) {
            return;
          }
          correctedWrite = result;
          await bridge.invoke('test', 'failCommit', {'value': false});
        };
        await SecurePhoneWidgetPreferenceStore().write(
          const PhoneWidgetPreferences(selectedIds: [cursorOwnPoolId]),
        );
        await SecureWatchRingPreferenceStore().write(
          const WatchRingPreferences(selectedIds: [cursorOwnPoolId]),
        );
        final capture = _SurfaceCapture();
        final calls = _bindSurfaces(capture: capture);
        final failures = <(String, Object)>[];
        Future<void> run(ConnectionCachePlatform platform, int usedPercent) =>
            providerSyncOnce(
              debugBuild: false,
              load:
                  (owner) => loadProviderSyncWork(
                    owner,
                    createLive:
                        () => PhoneLiveBindings.create(
                          secureStorage: secure,
                          cachePlatform: platform,
                          cursorClient: CursorPlanClient(
                            http: ProviderReportingHttp(
                              transport: _CursorPlanTransport(usedPercent),
                            ),
                          ),
                        ),
                    readWindows: (_) => const [],
                  ),
              logFailure: (step, error, _) => failures.add((step, error)),
            );
        final old = run(older, 40);
        try {
          await Future.any([
            reachedReread.future,
            old.then<void>((_) {
              throw StateError(
                'Old load finished before its selection reread.',
              );
            }),
          ]);
          await setClock(initial.add(const Duration(hours: 1)));
          await run(corrected, 70);
          expect(correctedWrite, containsPair('status', 'storageFailure'));
          expect(correctedWrite, containsPair('minimumEra', 1));
          expect(
            (await foreground.readVersion(id))?.sameCache(version),
            isTrue,
          );
          expect(failures, isEmpty);
          final published = Map.of(capture.widgetData);
          expect(published['row_0_percent'], '30% left');
          expect(published['stale'], '0');
          expect(_watchUsage(capture.watchSummaries.single), {
            cursorOwnPoolId: 70,
          });

          resumeReread.complete();
          await old;
          expect(calls, ['syncWatchSummary', 'publish', 'updateWidget']);
          expect(capture.widgetData, published);
          expect(capture.redraws, [published]);
          final (step, error) = failures.single;
          expect(step, 'setup');
          final failure = error as DashboardLoadException;
          expect(failure.details, 'Connection changed during refresh.');
          expect(failure.connectionVersions[key], version.values);
          final order = failure.snapshotOrdering[key]!;
          expect(order.attemptEra, 0);
          expect(order.payload?.era, 0);
          expect(order.selectionUnverified, isTrue);
          final validation = failedValidation!;
          expect(validation['attemptClockEras'], {key: 0});
          expect(
            await bridge.invoke('reader', 'validAll', {
              'versions': validation['versions'],
            }),
            isTrue,
          );
          expect(
            await bridge.invoke('reader', 'validAll', validation),
            isFalse,
          );
        } finally {
          if (!resumeReread.isCompleted) resumeReread.complete();
          await old;
          await bridge.invoke('test', 'failCommit', {'value': false});
        }
      },
    );
    for (final activate in [false, true]) {
      test('connection absence ownership guards late headless failure '
          '(activate: $activate)', () async {
        final secure = FakeSecureStorage();
        final foreground = SecureProviderCredentialStore(
          storage: secure,
          platform: bridge.platform('ui'),
        );
        await foreground.writeSecret(
          ProviderConnections.cursorPlatform,
          'synthetic-b',
        );
        final transport = _HeldFailingTransport();
        final captured = Completer<void>();
        final release = Completer<void>();
        var staleWrites = 0;
        final failures = <String>[];
        final run = providerSyncOnce(
          debugBuild: false,
          load: (owner) async {
            try {
              return await loadProviderSyncWork(
                owner,
                createLive:
                    () => PhoneLiveBindings.create(
                      secureStorage: secure,
                      cachePlatform: bridge.platform('headless'),
                      cursorReportingClient: CursorPlatformClient(
                        http: ProviderReportingHttp(transport: transport),
                      ),
                    ),
              );
            } catch (_) {
              captured.complete();
              await release.future;
              rethrow;
            }
          },
          markWidgetStale: ({required isCurrent}) async {
            staleWrites++;
          },
          logFailure: (step, _, _) => failures.add(step),
        );
        try {
          await transport.started.future;
          transport.release.complete();
          await captured.future;
          if (activate)
            await foreground.writeSecret(
              ProviderConnections.cursorPlan,
              'synthetic-a',
            );
          release.complete();
          await run;
          expect(failures, ['setup']);
          expect(staleWrites, activate ? 0 : 1);
        } finally {
          if (!transport.release.isCompleted) transport.release.complete();
          if (!release.isCompleted) release.complete();
          await run;
        }
      });
    }
    test(
      'wholly skipped headless collection does not call surface plugins',
      () async {
        final live = PhoneLiveBindings.create(
          cachePlatform: bridge.platform('headless'),
        );
        final poll = AutomaticPollContext();
        poll.skipped['openai.platform'] = AutomaticPollSkipped(
          'openai.platform',
          CredentialVersion({}),
          DateTime.utc(2026, 11, 6),
        );
        final work = await poll.run(
          () => loadProviderSyncWork(
            HeadlessLiveOwner(),
            watchRingStore: _WatchRead(() async => throw StateError('Skipped')),
            widgetStore: _WidgetRead(() async => throw StateError('Skipped')),
            createLive:
                () => PhoneLiveBindings(
                  credentialStore: live.credentialStore,
                  codexAccountService: live.codexAccountService,
                  claudeAccountService: live.claudeAccountService,
                  repository: ValueDashboardRepository(
                    DashboardSnapshot.empty(),
                  ),
                ),
          ),
        );
        // No channel handlers: a publication would reach a missing plugin.
        await work!.syncWatch();
        await work.syncWidget();
        await work.syncAlerts();
        expect(poll.whollySkipped, isTrue);
      },
    );
    for (final change in ['kept', 'removed', 'replaced']) {
      final effect = change == 'kept' ? 'marks rows STALE' : 'skips STALE';
      test('late Live failure with $change credentials $effect', () async {
        final secure = FakeSecureStorage();
        const id = ProviderConnections.cursorPlatform;
        // The foreground isolate owns credential changes.
        final foreground = SecureProviderCredentialStore(
          storage: secure,
          platform: bridge.platform('ui'),
        );
        await foreground.writeSecret(id, 'synthetic-saved-credential-0000');
        final transport = _HeldFailingTransport();
        final headless = _HeadlessRun();
        final run = headless.sync(
          () => PhoneLiveBindings.create(
            secureStorage: secure,
            cachePlatform: bridge.platform('headless'),
            cursorReportingClient: CursorPlatformClient(
              http: ProviderReportingHttp(transport: transport),
            ),
          ),
          debugData: _DebugData(false),
        );
        await transport.started.future;
        switch (change) {
          case 'removed':
            await foreground.deleteSecret(id);
          case 'replaced':
            await foreground.writeSecret(id, 'synthetic-new-credential-0000');
        }
        transport.release.complete();
        await run;
        // Admitted credentials and any captured absence both guard the failure.
        expect(headless.failures, ['setup']);
        expect(headless.staleWrites, change == 'kept' ? 1 : 0);
      });
    }
    final catalogue = providerConnectionCatalog();
    for (final (row, credential) in [
      for (final row in catalogue)
        (row, 'synthetic-saved-credential-000000000000000000'),
      (
        catalogue.firstWhere(
          (row) => row.id == ProviderConnections.anthropicPlatform,
        ),
        'sk-ant-admin01-synthetic',
      ),
    ]) {
      test(
        'headless records ${row.id.storageKey}${credential.startsWith('sk-ant-admin') ? ' local rejection' : ''} before a failed snapshot load',
        () async {
          final secure = FakeSecureStorage();
          final platform = bridge.platform('collection');
          final now = DateTime.utc(2026, 11, 5, 12);
          if (row.id == ProviderConnections.codexPlan) {
            await SecureCodexAccountStore(
              storage: secure,
              platform: platform,
            ).write(
              CodexAccountSession(
                accessToken: 'e30.eyJleHAiOjQxMDI0NDQ4MDB9.synthetic',
                refreshToken: 'synthetic-refresh',
                accountId: 'synthetic-account',
                refreshedAt: now,
              ),
            );
          } else if (row.id == ProviderConnections.claudePlan) {
            await SecureClaudeAccountStore(
              storage: secure,
              platform: platform,
            ).write(
              ClaudeAccountSession(
                accessToken: 'synthetic-access',
                refreshToken: 'synthetic-refresh',
                accountId: 'synthetic-account',
                expiresAt: now.add(const Duration(days: 1)),
              ),
            );
          } else {
            await SecureProviderCredentialStore(
              storage: secure,
              platform: platform,
            ).writeSecret(row.id, credential);
          }
          final reporting = _RejectedReportingTransport();
          PhoneLiveBindings createLive() {
            final http = ProviderReportingHttp(transport: reporting);
            return PhoneLiveBindings.create(
              secureStorage: secure,
              cachePlatform: platform,
              codexClient: CodexAccountClient(
                transport: _RejectedCodexTransport(),
                clock: () => now,
              ),
              claudeClient: ClaudeAccountClient(
                transport: const _StubClaudeTransport(),
                clock: () => now,
              ),
              openAiClient: OpenAiReportingClient(http: http),
              anthropicClient: AnthropicReportingClient(http: http),
              cursorClient: CursorPlanClient(http: http),
              cursorReportingClient: CursorPlatformClient(http: http),
            );
          }

          final failures = <Object>[];
          await providerSyncOnce(
            load:
                (owner) => loadProviderSyncWork(owner, createLive: createLive),
            markWidgetStale: ({required isCurrent}) async {},
            logFailure: (_, error, _) => failures.add(error),
          );
          expect(failures, hasLength(1));
          final notices = NativeConnectionRejectionNoticeStore(
            platform: platform,
          );
          final event = (await notices.read()).single;
          expect(event.connection, row.id);
          expect(event.dismissed, isFalse);
          if (credential.startsWith('sk-ant-admin')) expect(reporting.calls, 0);
          final live = createLive();
          if (row.id == ProviderConnections.codexPlan) {
            expect(await live.codexAccountService.isConnected(), isFalse);
          } else if (row.id == ProviderConnections.claudePlan) {
            expect(await live.claudeAccountService.isConnected(), isFalse);
          } else {
            expect(await live.credentialStore.readSecret(row.id), isNotNull);
          }
          if (row.id == ProviderConnections.cursorPlan) {
            expect(
              (failures.single as DashboardLoadException).reportingOutcomes,
              isEmpty,
            );
          }
          final observed = <ConnectionReportingUpdate>[];
          if (row.id == ProviderConnections.codexPlan ||
              row.id == ProviderConnections.claudePlan) {
            expect(
              (await live.repository.loadObserved(observed.add)).accounts,
              isEmpty,
            );
          } else {
            await expectLater(
              live.repository.loadObserved(observed.add),
              throwsA(isA<DashboardLoadException>()),
            );
          }
          expect(
            observed.where(
              (update) => update.connection == ProviderConnections.cursorPlan,
            ),
            isEmpty,
          );
          await bridge.invoke('test', 'restart', {});
          expect(
            (await NativeConnectionRejectionNoticeStore(
                  platform: bridge.platform('cold'),
                ).read())
                .single
                .eventId,
            event.eventId,
          );
        },
      );
    }
    test(
      'paused bindings omit Claude plan during offline fallback and recovery',
      () async {
        const plan = ProviderConnections.claudePlan;
        const organization = ProviderConnections.anthropicPlatform;
        const paste = 'wardpulse.anthropic.plan.secret';
        final secure = FakeSecureStorage();
        final now = DateTime.utc(2026, 11, 21, 12);
        final platform = bridge.platform('seed');
        await bridge.invoke('test', 'setClock', {
          'value': now.millisecondsSinceEpoch,
        });
        final store = SecureClaudeAccountStore(
          storage: secure,
          platform: platform,
        );
        await store.write(
          ClaudeAccountSession(
            accessToken: 'fake-expired',
            refreshToken: 'fake-refresh',
            accountId: 'fake-upgrade-account',
            expiresAt: now,
          ),
        );
        final secrets = SecureProviderCredentialStore(
          storage: secure,
          platform: platform,
        );
        await secrets.writeSecret(organization, 'fake-console-reporting-key');
        await secrets.writeSecret(
          ProviderConnections.cursorPlan,
          'fake-cursor-session',
        );
        final personalRequests = <String>[];
        var organizationRequests = 0;
        var cursorRequests = 0;
        PhoneLiveBindings create(
          String owner, {
          required bool paused,
          bool cursorOffline = false,
        }) => PhoneLiveBindings.create(
          claudePlanPaused: paused,
          secureStorage: secure,
          cachePlatform: bridge.platform(owner),
          claudeClient: ClaudeAccountClient(
            clock: () => now,
            transport: _UpgradeClaudeTransport(personalRequests),
          ),
          anthropicClient: AnthropicReportingClient(
            http: ProviderReportingHttp(
              transport: _OpenAiReportingTransport(
                providerFails: false,
                onRequest: () => organizationRequests++,
              ),
            ),
          ),
          cursorClient: CursorPlanClient(
            http: ProviderReportingHttp(
              transport: _CursorPlanTransport(
                40,
                offline: cursorOffline,
                onRequest: () => cursorRequests++,
              ),
            ),
          ),
        );

        final debug = create('debug', paused: false);
        final debugSnapshot = await debug.repository.load();
        expect(
          debugSnapshot.accounts.map((account) => account.connection),
          containsAll([
            plan.storageKey,
            organization.storageKey,
            'cursor.plan',
          ]),
        );
        expect(personalRequests, [
          'POST /v1/oauth/token',
          'GET /api/oauth/usage',
        ]);
        const rules = AlertThresholdPreferences(
          connections: {
            'anthropic.plan': ConnectionAlertThresholds(
              plan: AlertPercentThreshold(at: 30),
            ),
          },
        );
        expect(applyUserAlertSettings(debugSnapshot, rules).alerts, isNotEmpty);
        await SecureAlertThresholdPreferenceStore().write(rules);
        final planAccount = debugSnapshot.accounts.singleWhere(
          (account) => account.connection == plan.storageKey,
        );
        final historyOwner = planAccount.historyOwner!;
        final window = planAccount.allowances.singleWhere(
          (allowance) => allowance.id == 'claude-five-hour',
        );
        final key = (
          accountId: planAccount.accountId,
          historyOwner: historyOwner,
          allowanceId: window.id,
        );
        final history = SecureRecoveryWatchlistStore();
        await history.writeObserved(
          [key],
          {historyOwner},
          requirements: {key: window.recoveryRequirements!},
        );
        await SecureRecoveryNotificationPreferenceStore().write(true);
        final saved = await history.readPendingOwners({historyOwner});
        final recoverable =
            reconcilePlanRecoveries(
              debugSnapshot,
              saved.pending,
            ).recoveries.single;
        expect(recoverable.allowanceId, key.allowanceId);
        expect(recoverable.historyOwner, historyOwner);

        final expired = (await store.readVersioned())!;
        await store.refresh(
          ClaudeAccountSession(
            accessToken: expired.value.accessToken,
            refreshToken: expired.value.refreshToken,
            accountId: expired.value.accountId,
            expiresAt: now,
          ),
          expired.version,
        );
        secure.values[paste] = 'fake-old-paste';
        final version = (await store.readVersioned())!.version;
        expect(
          await platform.invoke('readSnapshot', {
            'connection': plan.storageKey,
            'expected': version.values,
          }),
          isNotNull,
        );
        for (final (field, value) in [
          ('rejectionEvent', version.values['committedConnection']),
          ('rejectionDismissed', 'false'),
        ]) {
          await bridge.invoke('test', 'setDisk', {
            'key': '${plan.storageKey}.$field',
            'value': value,
          });
        }
        expect((await debug.rejectionNotices.read()).single.connection, plan);

        personalRequests.clear();
        final foreground = create('foreground', paused: true);
        // Admission stays closed even before startup retirement reaches storage.
        final foregroundSnapshot = await foreground.repository.load();
        expect(
          foregroundSnapshot.accounts.map((account) => account.connection),
          unorderedEquals([organization.storageKey, 'cursor.plan']),
        );
        expect(
          foregroundSnapshot.connectionVersions,
          isNot(contains(plan.storageKey)),
        );
        expect(await foreground.rejectionNotices.read(), isEmpty);
        expect(await foreground.claudeAccountService.isConnected(), isFalse);
        expect(
          foreground.claudeAccountService.startLogin,
          throwsA(isA<ClaudeAccountException>()),
        );
        expect(await foreground.claudeAccountService.fetchReport(), isNull);
        await foreground.claudeAccountService.disconnect();
        expect(personalRequests, isEmpty);

        final notificationPlatform = FlutterLocalNotificationsPlatform.instance;
        final targetPlatform = debugDefaultTargetPlatformOverride;
        const channel = MethodChannel(
          'dexterous.com/flutter/local_notifications',
        );
        final messenger =
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        final posted = <int>[];
        addTearDown(() {
          try {
            messenger.setMockMethodCallHandler(channel, null);
            channel.setMethodCallHandler(null);
          } finally {
            FlutterLocalNotificationsPlatform.instance = notificationPlatform;
            debugDefaultTargetPlatformOverride = targetPlatform;
          }
        });
        AndroidFlutterLocalNotificationsPlugin.registerWith();
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        messenger.setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'show')
            posted.add((call.arguments as Map)['id'] as int);
          return true;
        });
        await LocalRecoveryNotifier().notify(recoverable);
        expect(posted, [recoveryNotificationId(recoverable)]);
        posted.clear();

        final capture = _SurfaceCapture();
        _bindSurfaces(capture: capture);
        final failures = <Object>[];
        final organizationBeforeHeadless = organizationRequests;
        final cursorBeforeHeadless = cursorRequests;
        secure.failDeleteKey = paste;
        expect(
          await runHeadlessProviderTask(
            HeadlessProviderSync.taskName,
            sync:
                () => providerSyncOnce(
                  debugBuild: false,
                  load:
                      (owner) => loadProviderSyncWork(
                        owner,
                        createLive:
                            () => create(
                              'headless',
                              paused: true,
                              cursorOffline: true,
                            ),
                        watchRingStore: _WatchRead(
                          () async => const WatchRingPreferences(
                            selectedIds: [claudePlanRingId, cursorOwnPoolId],
                          ),
                        ),
                        widgetStore: _WidgetRead(
                          () async => const PhoneWidgetPreferences(
                            selectedIds: [_ordinaryWidgetId, cursorOwnPoolId],
                          ),
                        ),
                      ),
                  logFailure: (_, error, _) => failures.add(error),
                ),
          ),
          isTrue,
        );
        expect(failures, isEmpty);
        expect(personalRequests, isEmpty);
        expect(organizationRequests, greaterThan(organizationBeforeHeadless));
        expect(cursorRequests, cursorBeforeHeadless + 1);
        expect(secure.values[paste], 'fake-old-paste');
        expect(
          await platform.invoke('readSnapshot', {
            'connection': plan.storageKey,
            'expected': version.values,
          }),
          isNull,
        );
        expect(_watchUsage(capture.watchSummaries.single), {
          cursorOwnPoolId: 40,
        });
        expect(capture.watchSummaries.single['alerts'], isEmpty);
        expect(capture.watchSummaries.single['isStale'], isTrue);
        expect(
          (capture.watchSummaries.single['allowances'] as List).map(
            (allowance) => (allowance as Map)['label'],
          ),
          everyElement(startsWith('Cursor · ')),
        );
        expect(posted, isEmpty);
        expect((await history.readOwners({historyOwner})).keys, [key]);
        expect(capture.redraws.single, containsPair('row_count', 1));
        expect(capture.redraws.single, containsPair('row_0_family', 'Cursor'));
        expect(
          capture.redraws.single,
          containsPair('row_0_percent', '60% left'),
        );
        expect(capture.redraws.single, containsPair('stale', '1'));
        expect(
          await secrets.readSecret(organization),
          'fake-console-reporting-key',
        );
      },
    );

    test(
      'headless Claude rejection retires after the replacement stores a live report',
      () async {
        const id = ProviderConnections.claudePlan;
        final secure = FakeSecureStorage();
        final now = DateTime.utc(2026, 11, 21, 12);
        final store = SecureClaudeAccountStore(
          storage: secure,
          platform: bridge.platform('ui'),
        );
        ClaudeAccountSession session(String token) => ClaudeAccountSession(
          accessToken: token,
          refreshToken: 'synthetic-refresh',
          accountId: 'synthetic-account',
          expiresAt: now.add(const Duration(days: 1)),
        );
        PhoneLiveBindings createLive(
          ConnectionCachePlatform platform,
          ClaudeHttpResponse response,
        ) => PhoneLiveBindings.create(
          secureStorage: secure,
          cachePlatform: platform,
          claudeClient: ClaudeAccountClient(
            transport: _StubClaudeTransport(response),
            clock: () => now,
          ),
        );

        await bridge.invoke('test', 'setClock', {
          'value': now.millisecondsSinceEpoch,
        });
        await store.write(session('synthetic-rejected'));
        final headless = createLive(
          bridge.platform('headless'),
          const ClaudeHttpResponse(statusCode: 401, body: '{}'),
        );
        final failures = <Object>[];
        await providerSyncOnce(
          debugBuild: false,
          load:
              (owner) =>
                  loadProviderSyncWork(owner, createLive: () => headless),
          markWidgetStale: ({required isCurrent}) async {},
          logFailure: (_, error, _) => failures.add(error),
        );
        final event = (await headless.rejectionNotices.read()).single;
        expect(event.connection, id);
        expect(event.dismissed, isFalse);
        expect((failures.single as DashboardLoadException).syncRejection, (
          connection: id.storageKey,
          eventId: event.eventId,
        ));
        expect(await store.read(), isNull);

        await store.write(session('synthetic-replacement'));
        final replacement = (await store.readVersioned())!.version;
        expect(replacement.values['committedConnection'], isA<String>());
        expect(replacement.values['committedConnection'], isNot(event.eventId));
        final unavailable = createLive(
          bridge.platform('foreground'),
          const ClaudeHttpResponse(statusCode: 503, body: '{}'),
        );
        final notices = unavailable.rejectionNotices;
        final afterReconnect = (await notices.read()).single;
        expect(afterReconnect.eventId, event.eventId);
        expect(afterReconnect.dismissed, isFalse);
        await expectLater(
          unavailable.repository.load(),
          throwsA(
            isA<DashboardLoadException>().having(
              (error) => error.issue,
              'issue',
              DashboardSyncIssue.claudeUnavailable,
            ),
          ),
        );
        expect((await notices.read()).single.dismissed, isFalse);

        final platform = ObservingCachePlatform(bridge.platform('foreground'));
        String? stamp;
        Object? write;
        platform.onComplete = (method, arguments, result) {
          if (method != 'writeSnapshot' ||
              arguments['connection'] != id.storageKey) {
            return;
          }
          stamp = arguments['stamp'] as String?;
          write = result;
        };
        final live = createLive(
          platform,
          const ClaudeHttpResponse(
            statusCode: 200,
            body: '{"five_hour":{"utilization":42}}',
          ),
        );
        final snapshot = await live.repository.load();
        expect(snapshot.accounts.single.connection, id.storageKey);
        expect(snapshot.accounts.single.allowances.single.usedPercent, 42);
        expect(stamp, isNotEmpty);
        expect(write, containsPair('status', 'stored'));

        await bridge.invoke('test', 'restart', {});
        final cold = bridge.platform('cold');
        final encoded = await cold.invoke('readSnapshot', {
          'connection': id.storageKey,
          'expected': replacement.values,
        });
        final cached = DashboardSnapshot.fromJsonString(encoded as String);
        expect(cached.accounts.single.allowances.single.usedPercent, 42);
        final coldNotices = NativeConnectionRejectionNoticeStore(
          platform: cold,
        );
        final recovered = (await coldNotices.read()).single;
        expect(recovered.eventId, event.eventId);
        expect(
          recovered.dismissed,
          isTrue,
          reason: 'The stored report retires the earlier warning.',
        );
      },
    );
  });

  test(
    'headless validates ownership immediately before each surface',
    () async {
      final attempts = <String>[];
      var current = true;
      await providerSyncOnce(
        load:
            (_) async => ProviderSyncWork(
              isCurrent: () async => current,
              syncWatch: () async {
                attempts.add('watch');
                current = false;
              },
              syncWidget: () async {
                attempts.add('widget');
              },
              syncRecoveries: () async {
                attempts.add('recovery');
              },
              syncAlerts: () async {
                attempts.add('alerts');
              },
            ),
      );
      expect(attempts, ['watch']);
    },
  );
  test(
    'retired headless snapshot cannot reach any surface or recovery',
    () async {
      final attempts = <String>[];
      await providerSyncOnce(
        load:
            (_) async => ProviderSyncWork(
              isCurrent: () async => false,
              syncWatch: () async {
                attempts.add('watch');
              },
              syncWidget: () async {
                attempts.add('widget');
              },
              syncRecoveries: () async {
                attempts.add('recovery');
              },
              syncAlerts: () async {
                attempts.add('alerts');
              },
            ),
      );
      expect(attempts, isEmpty);
    },
  );

  test('missing watch plugin does not skip widget or recovery work', () async {
    final attempts = <String>[];
    final failures = <_RecordedFailure>[];
    final snapshot = DashboardSnapshot.empty(
      generatedAt: DateTime.utc(2026, 10, 4),
    );

    await providerSyncOnce(
      load:
          (_) async => ProviderSyncWork(
            syncWatch: () async {
              attempts.add('watch');
              // No mock handler: this is the real headless failure mode that used
              // to stop the tick at the activity-owned channel.
              await const MethodChannelWatchSyncService().sync(
                snapshot,
                const WatchRingPreferences(),
              );
            },
            syncWidget: () async {
              attempts.add('widget');
            },
            syncRecoveries: () async {
              attempts.add('recovery');
            },
            syncAlerts: () async {
              attempts.add('alerts');
            },
          ),
      logFailure: (step, error, stackTrace) {
        failures.add((step: step, error: error, stackTrace: stackTrace));
      },
    );

    expect(attempts, ['watch', 'widget', 'recovery', 'alerts']);
    expect(failures, hasLength(1));
    expect(failures.single.step, 'watch');
    expect(failures.single.error, isA<MissingPluginException>());
    expect(failures.single.stackTrace.toString(), isNotEmpty);
  });

  for (final failedStep in ['watch', 'widget', 'recovery', 'alerts']) {
    test(
      '$failedStep failure leaves every step attempted exactly once',
      () async {
        final attempts = {'watch': 0, 'widget': 0, 'recovery': 0, 'alerts': 0};
        final failures = <_RecordedFailure>[];

        Future<void> attempt(String step) async {
          attempts[step] = attempts[step]! + 1;
          if (step == failedStep) {
            throw StateError('$step unavailable');
          }
        }

        await providerSyncOnce(
          load:
              (_) async => ProviderSyncWork(
                syncWatch: () => attempt('watch'),
                syncWidget: () => attempt('widget'),
                syncRecoveries: () => attempt('recovery'),
                syncAlerts: () => attempt('alerts'),
              ),
          logFailure: (step, error, stackTrace) {
            failures.add((step: step, error: error, stackTrace: stackTrace));
          },
        );

        expect(attempts, {'watch': 1, 'widget': 1, 'recovery': 1, 'alerts': 1});
        expect(failures, hasLength(1));
        expect(failures.single.step, failedStep);
        expect(failures.single.error, isA<StateError>());
        expect(failures.single.stackTrace.toString(), isNotEmpty);
      },
    );
  }

  test('setup failure is logged while the recognized task succeeds', () async {
    final failures = <_RecordedFailure>[];

    final succeeded = await runHeadlessProviderTask(
      HeadlessProviderSync.taskName,
      sync:
          () => providerSyncOnce(
            load: (_) async => throw StateError('credentials unavailable'),
            markWidgetStale: ({required isCurrent}) async {},
            logFailure: (step, error, stackTrace) {
              failures.add((step: step, error: error, stackTrace: stackTrace));
            },
          ),
    );

    expect(succeeded, isTrue);
    expect(failures, hasLength(1));
    expect(failures.single.step, 'setup');
    expect(failures.single.error, isA<StateError>());
    expect(failures.single.stackTrace.toString(), isNotEmpty);
  });

  test(
    'provider load failure marks retained widget rows stale and redraws',
    () async {
      final data = <String, Object?>{
        'row_count': 1,
        'empty': '0',
        'stale': '0',
        'row_0_percent': '46% left',
        'row_0_label': 'Claude plan',
      };
      final original = Map<String, Object?>.from(data);
      final capture = _SurfaceCapture()..widgetData.addAll(data);
      _bindSurfaces(capture: capture);
      final failures = <String>[];
      final succeeded = await runHeadlessProviderTask(
        HeadlessProviderSync.taskName,
        sync:
            () => providerSyncOnce(
              load: (_) async => throw const DashboardLoadException(),
              logFailure: (step, _, _) => failures.add(step),
            ),
      );

      expect(succeeded, isTrue);
      expect(failures, ['setup']);
      expect(capture.widgetData, {...original, 'stale': '1'});
      expect(capture.redraws, hasLength(1));
    },
  );

  test(
    'stale widget delivery failure is logged independently from setup',
    () async {
      final failures = <String>[];
      final succeeded = await runHeadlessProviderTask(
        HeadlessProviderSync.taskName,
        sync:
            () => providerSyncOnce(
              load: (_) async => throw const DashboardLoadException(),
              markWidgetStale: ({required isCurrent}) async {
                throw StateError('Widget unavailable');
              },
              logFailure: (step, _, _) => failures.add(step),
            ),
      );
      expect(succeeded, isTrue);
      expect(failures, ['setup', 'widget']);
    },
  );

  group('headless saved surface choices', () {
    test(
      'headless watch replacement publishes the saved Fable selection',
      () async {
        final snapshot = _surfaceSnapshot();
        final watchStore = SecureWatchRingPreferenceStore();
        const initial = WatchRingPreferences(selectedIds: [claudePlanRingId]);
        const edited = WatchRingPreferences(selectedIds: [claudeFableRingId]);
        expect(
          resolveWatchRings(
            snapshot,
            initial,
          ).map((ring) => (ring.id, ring.usedPercent)),
          [(claudePlanRingId, 40)],
        );
        expect(
          resolveWatchRings(
            snapshot,
            edited,
          ).map((ring) => (ring.id, ring.usedPercent)),
          [(claudeFableRingId, 90)],
        );
        await watchStore.write(initial);
        await SecurePhoneWidgetPreferenceStore().write(_bothWidgetChoices);
        final capture = _SurfaceCapture();
        _bindSurfaces(capture: capture);
        final headless = _HeadlessRun();
        final live = _LiveFixture(snapshot: snapshot);
        final run = runHeadlessProviderTask(
          HeadlessProviderSync.taskName,
          sync: () => headless.sync(live.create),
        );
        addTearDown(() async {
          if (!live.release.isCompleted) live.release.complete();
          await run;
        });
        await live.started.future;
        await watchStore.write(edited);
        live.release.complete();
        expect(await run, isTrue);

        expect(live.loads, 1);
        expect(headless.failures, isEmpty);
        expect(headless.staleWrites, 0);
        expect(capture.watchSummaries, hasLength(1));
        expect(_watchUsage(capture.watchSummaries.single), {
          claudeFableRingId: 90,
        });
        expect(
          capture.watchSummaries.single['creditsGlance'],
          containsPair('text', '1.2K'),
        );
        _expectWidgetRows(capture);
      },
    );

    test(
      'headless explicit empty watch selection suppresses rings and credits',
      () async {
        final snapshot = _surfaceSnapshot();
        final watchStore = SecureWatchRingPreferenceStore();
        const initial = WatchRingPreferences(
          selectedIds: [claudePlanRingId, claudeFableRingId],
        );
        final populated =
            jsonDecode(
                  WatchDashboardSummaryPayload.fromSnapshot(
                    snapshot,
                    initial,
                  ).encode(),
                )
                as Map<String, dynamic>;
        expect(_watchUsage(populated), {
          claudePlanRingId: 40,
          claudeFableRingId: 90,
        });
        expect(populated['creditsGlance'], containsPair('text', '1.2K'));
        await watchStore.write(initial);
        await SecurePhoneWidgetPreferenceStore().write(_bothWidgetChoices);
        final capture = _SurfaceCapture();
        _bindSurfaces(capture: capture);
        final headless = _HeadlessRun();
        final live = _LiveFixture(snapshot: snapshot);
        final run = runHeadlessProviderTask(
          WorkmanagerRecoveryWakeScheduler.taskName,
          sync: () => headless.sync(live.create),
        );
        addTearDown(() async {
          if (!live.release.isCompleted) live.release.complete();
          await run;
        });
        await live.started.future;
        await watchStore.write(const WatchRingPreferences(selectedIds: []));
        live.release.complete();
        expect(await run, isTrue);

        expect(live.loads, 1);
        expect(headless.failures, isEmpty);
        expect(headless.staleWrites, 0);
        expect(capture.watchSummaries, hasLength(1));
        expect(capture.watchSummaries.single['rings'], isEmpty);
        expect(capture.watchSummaries.single['creditsGlance'], isNull);
        _expectWidgetRows(capture);
      },
    );

    test(
      'headless widget removal publishes only the saved Fable row',
      () async {
        final snapshot = _surfaceSnapshot();
        final widgetStore = SecurePhoneWidgetPreferenceStore();
        const edited = PhoneWidgetPreferences(selectedIds: [claudeFableRingId]);
        expect(
          resolvePhoneWidgetMetrics(
            snapshot,
            _bothWidgetChoices,
          ).map((metric) => (metric.id, metric.usedPercent)),
          [(_ordinaryWidgetId, 40), (claudeFableRingId, 90)],
        );
        expect(
          resolvePhoneWidgetMetrics(
            snapshot,
            edited,
          ).map((metric) => (metric.id, metric.usedPercent)),
          [(claudeFableRingId, 90)],
        );
        await widgetStore.write(_bothWidgetChoices);
        await SecureWatchRingPreferenceStore().write(
          const WatchRingPreferences(
            selectedIds: [claudePlanRingId, claudeFableRingId],
          ),
        );
        final capture = _SurfaceCapture()..widgetData.addAll(_priorWidgetRows);
        _bindSurfaces(capture: capture);
        final headless = _HeadlessRun();
        final live = _LiveFixture(snapshot: snapshot);
        final run = runHeadlessProviderTask(
          HeadlessProviderSync.taskName,
          sync: () => headless.sync(live.create),
        );
        addTearDown(() async {
          if (!live.release.isCompleted) live.release.complete();
          await run;
        });
        await live.started.future;
        await widgetStore.write(edited);
        live.release.complete();
        expect(await run, isTrue);

        expect(live.loads, 1);
        expect(headless.failures, isEmpty);
        expect(headless.staleWrites, 0);
        expect(capture.watchSummaries, hasLength(1));
        final rings = capture.watchSummaries.single['rings'] as List;
        expect(rings, hasLength(1));
        expect(rings.single['id'], claudePlanRingId);
        expect(rings.single['usedPercent'], 40);
        expect(rings.single['split']['id'], claudeFableRingId);
        expect(rings.single['split']['usedPercent'], 90);
        expect(_watchUsage(capture.watchSummaries.single), {
          claudePlanRingId: 40,
          claudeFableRingId: 90,
        });
        _expectWidgetRows(capture, includeOrdinary: false);
      },
    );

    test(
      'Mock observed during the watch selection read retires publication',
      () async {
        final capture = _SurfaceCapture()..widgetData.addAll(_priorWidgetRows);
        final calls = _bindSurfaces(capture: capture);
        final reading = Completer<void>();
        final releaseRead = Completer<void>();
        final live = _LiveFixture(snapshot: _surfaceSnapshot())
          ..release.complete();
        final headless = _HeadlessRun();
        final run = runHeadlessProviderTask(
          HeadlessProviderSync.taskName,
          sync:
              () => headless.sync(
                live.create,
                watchRingStore: _WatchRead(() async {
                  reading.complete();
                  await releaseRead.future;
                  return SecureWatchRingPreferenceStore().read();
                }),
              ),
        );
        addTearDown(() async {
          if (!releaseRead.isCompleted) releaseRead.complete();
          await run;
        });
        await reading.future;
        expect(live.loads, 1);
        expect(calls, isEmpty);
        await SecureDebugDataPreferenceStore().writeMockDataEnabled(true);
        releaseRead.complete();
        expect(await run, isTrue);
        expect(calls, isEmpty);
        expect(capture.widgetData, _priorWidgetRows);
        expect(headless.failures, isEmpty);
        expect(headless.staleWrites, 0);
        expect(
          await const FlutterSecureStorage().read(
            key: 'wardpulse.recovery.exhaustedWindows',
          ),
          isNull,
        );
      },
    );

    for (final validationThrows in [false, true]) {
      final fault = validationThrows ? 'throw' : 'rejection';
      test(
        'a transient watch provenance $fault retires the invocation',
        () async {
          await SecureWatchRingPreferenceStore().write(
            const WatchRingPreferences(selectedIds: [claudePlanRingId]),
          );
          await SecurePhoneWidgetPreferenceStore().write(_bothWidgetChoices);
          final capture =
              _SurfaceCapture()..widgetData.addAll(_priorWidgetRows);
          final calls = _bindSurfaces(capture: capture);
          final headless = _HeadlessRun();
          var watchRead = false;
          var checksAfterWatchRead = 0;
          var widgetReads = 0;
          final live =
              _LiveFixture(snapshot: _surfaceSnapshot())
                ..validate = (_) {
                  if (!watchRead || ++checksAfterWatchRead > 1) return true;
                  if (validationThrows) {
                    throw StateError('Synthetic watch provenance failure.');
                  }
                  return false;
                }
                ..release.complete();
          await headless.sync(
            live.create,
            watchRingStore: _WatchRead(() async {
              watchRead = true;
              return SecureWatchRingPreferenceStore().read();
            }),
            widgetStore: _WidgetRead(() async {
              widgetReads++;
              return SecurePhoneWidgetPreferenceStore().read();
            }),
          );
          expect(watchRead, isTrue);
          expect(checksAfterWatchRead, 1);
          expect(widgetReads, 0);
          expect(headless.failures, validationThrows ? ['watch'] : isEmpty);
          expect(headless.staleWrites, 0);
          expect(calls, isEmpty);
          expect(capture.widgetData, _priorWidgetRows);

          await headless.sync(live.create);
          expect(live.loads, 2);
          expect(capture.watchSummaries, hasLength(1));
          _expectWidgetRows(capture);
        },
      );
    }

    test(
      'replaced provenance during the widget selection read preserves dispatched watch',
      () async {
        await SecureWatchRingPreferenceStore().write(
          const WatchRingPreferences(
            selectedIds: [claudePlanRingId, claudeFableRingId],
          ),
        );
        final capture = _SurfaceCapture()..widgetData.addAll(_priorWidgetRows);
        final calls = _bindSurfaces(capture: capture);
        final reading = Completer<void>();
        final releaseRead = Completer<void>();
        final live = _LiveFixture(snapshot: _surfaceSnapshot())
          ..release.complete();
        final headless = _HeadlessRun();
        final run = runHeadlessProviderTask(
          WorkmanagerRecoveryWakeScheduler.taskName,
          sync:
              () => headless.sync(
                live.create,
                widgetStore: _WidgetRead(() async {
                  reading.complete();
                  await releaseRead.future;
                  return SecurePhoneWidgetPreferenceStore().read();
                }),
              ),
        );
        addTearDown(() async {
          if (!releaseRead.isCompleted) releaseRead.complete();
          await run;
        });
        await reading.future;
        expect(live.loads, 1);
        expect(calls, ['syncWatchSummary']);
        expect(_watchUsage(capture.watchSummaries.single), {
          claudePlanRingId: 40,
          claudeFableRingId: 90,
        });
        live.current = false;
        releaseRead.complete();
        expect(await run, isTrue);
        expect(calls, ['syncWatchSummary']);
        expect(capture.watchSummaries, hasLength(1));
        expect(capture.widgetData, _priorWidgetRows);
        expect(capture.redraws, isEmpty);
        expect(headless.failures, isEmpty);
        expect(headless.staleWrites, 0);
        expect(
          await const FlutterSecureStorage().read(
            key: 'wardpulse.recovery.exhaustedWindows',
          ),
          isNull,
        );
      },
    );

    for (final surface in ['watch', 'widget']) {
      test(
        '$surface selection read failure retains output and publishes its sibling',
        () async {
          await SecureWatchRingPreferenceStore().write(
            const WatchRingPreferences(
              selectedIds: [claudePlanRingId, claudeFableRingId],
            ),
          );
          await SecurePhoneWidgetPreferenceStore().write(_bothWidgetChoices);
          final priorWatch = <String, dynamic>{
            'rings': [
              {'id': claudePlanRingId, 'usedPercent': 20, 'split': null},
            ],
          };
          final capture =
              _SurfaceCapture()
                ..watchSummaries.add(priorWatch)
                ..widgetData.addAll(_priorWidgetRows);
          final calls = _bindSurfaces(capture: capture);
          final live = _LiveFixture(snapshot: _surfaceSnapshot())
            ..release.complete();
          final headless = _HeadlessRun();
          expect(
            await runHeadlessProviderTask(
              HeadlessProviderSync.taskName,
              sync:
                  () => headless.sync(
                    live.create,
                    watchRingStore:
                        surface == 'watch'
                            ? _WatchRead(
                              () async =>
                                  throw StateError('Watch choice unavailable'),
                            )
                            : null,
                    widgetStore:
                        surface == 'widget'
                            ? _WidgetRead(
                              () async =>
                                  throw StateError('Widget choice unavailable'),
                            )
                            : null,
                  ),
            ),
            isTrue,
          );

          expect(live.loads, 1);
          expect(headless.failures, [surface]);
          expect(headless.staleWrites, 0);
          if (surface == 'watch') {
            expect(capture.watchSummaries, [priorWatch]);
            expect(calls, isNot(contains('syncWatchSummary')));
            _expectWidgetRows(capture);
          } else {
            expect(capture.watchSummaries, hasLength(2));
            expect(_watchUsage(capture.watchSummaries.last), {
              claudePlanRingId: 40,
              claudeFableRingId: 90,
            });
            expect(calls, ['syncWatchSummary']);
            expect(capture.widgetData, _priorWidgetRows);
            expect(capture.redraws, isEmpty);
          }
          // A surface failure must still allow recovery bookkeeping to finish.
          expect(
            await const FlutterSecureStorage().read(
              key: 'wardpulse.recovery.exhaustedWindows',
            ),
            '[]',
          );
        },
      );
    }
  });

  group('debug Mock ownership', () {
    final tasks = [
      HeadlessProviderSync.taskName,
      WorkmanagerRecoveryWakeScheduler.taskName,
    ];
    for (final task in tasks) {
      for (final unreadable in [false, true]) {
        final choice = unreadable ? 'an unreadable' : 'a saved';
        test('$task with $choice Mock choice skips before Live', () async {
          // Saved by the production store, whose exact `true` means Mock.
          if (!unreadable)
            await SecureDebugDataPreferenceStore().writeMockDataEnabled(true);
          final debugData = unreadable ? _DebugData(null) : null;
          final surfaces = _bindSurfaces();
          final headless = _HeadlessRun();
          var created = 0;
          PhoneLiveBindings createLive() {
            created++;
            // No credentials: Live would publish an empty dashboard.
            return PhoneLiveBindings.create(secureStorage: FakeSecureStorage());
          }

          final succeeded = await runHeadlessProviderTask(
            task,
            sync: () => headless.sync(createLive, debugData: debugData),
          );
          expect(succeeded, isTrue);
          expect(created, 0);
          expect(surfaces, isEmpty);
          expect(headless.failures, isEmpty);
          expect(headless.staleWrites, 0);
        });
      }
    }

    test('Mock saved during awaited setup retires before collection', () async {
      final debugData = _DebugData(false);
      debugData.beforeRead = () {
        if (debugData.reads == 2) debugData.mock = true;
      };
      final surfaces = _bindSurfaces();
      final live = _LiveFixture()..release.complete();
      final headless = _HeadlessRun();
      await headless.sync(live.create, debugData: debugData);
      expect(live.created, 1);
      expect(live.loads, 0);
      expect(surfaces, isEmpty);
      expect(headless.failures, isEmpty);
      expect(headless.staleWrites, 0);
    });

    for (final fail in [false, true]) {
      final outcome = fail ? 'failing' : 'successful';
      test('held $outcome Live load crossing into Mock is retired', () async {
        final debugData = _DebugData(false);
        final surfaces = _bindSurfaces();
        final headless = _HeadlessRun();
        final held = _LiveFixture(fail: fail);
        final run = headless.sync(held.create, debugData: debugData);
        await held.started.future;
        debugData.mock = true;
        held.release.complete();
        await run;
        expect(surfaces, isEmpty);
        expect(headless.failures, isEmpty);
        expect(headless.staleWrites, 0);

        // Retirement belongs to that invocation; Mock-off work starts afresh.
        debugData.mock = false;
        final next = _LiveFixture(fail: fail)..release.complete();
        await headless.sync(next.create, debugData: debugData);
        expect(next.loads, 1);
        if (fail) {
          expect(headless.failures, ['setup']);
          expect(headless.staleWrites, 1);
        } else {
          expect(surfaces, containsAll(['syncWatchSummary', 'updateWidget']));
        }
      });
    }

    test('credentials replaced after a held failure skip STALE', () async {
      final debugData = _DebugData(false);
      final headless = _HeadlessRun();
      final held = _LiveFixture(fail: true);
      // The first mode check after the failed load observes the replacement.
      debugData.beforeRead = () {
        if (held.release.isCompleted) held.current = false;
      };
      final run = headless.sync(held.create, debugData: debugData);
      await held.started.future;
      held.release.complete();
      await run;
      expect(headless.failures, ['setup']);
      expect(headless.staleWrites, 0);
    });

    for (final replaced in [false, true]) {
      final credentials = replaced ? 'replaced' : 'kept';
      final outcome = replaced ? 'leave rows unmarked' : 'mark rows STALE';
      test('$credentials before STALE $outcome', () async {
        final data = <String, Object?>{
          'row_count': 1,
          'empty': '0',
          'stale': '0',
        };
        final held = _LiveFixture(fail: true)..release.complete();
        final capture = _SurfaceCapture()..widgetData.addAll(data);
        final calls = _bindSurfaces(capture: capture);
        final failures = <String>[];
        await providerSyncOnce(
          load: (owner) => loadProviderSyncWork(owner, createLive: held.create),
          markWidgetStale: ({required isCurrent}) async {
            if (replaced) held.current = false;
            await HomeWidgetPhoneWidgetSyncService.markExistingRowsStale(
              isCurrent: isCurrent,
            );
          },
          logFailure: (step, _, _) => failures.add(step),
          debugData: _DebugData(false),
        );
        expect(failures, ['setup']);
        expect(capture.widgetData['stale'], replaced ? '0' : '1');
        expect(calls.contains('updateWidget'), !replaced);
      });
    }

    for (final validationThrows in [false, true]) {
      final outcome = validationThrows ? 'unavailable' : 'rejected';
      test('recovery with $outcome proof cannot mark rows STALE', () async {
        final snapshot = _surfaceSnapshot().withStaleStatus(
          syncIssue: DashboardSyncIssue.credentialUnavailable,
        );
        final validationError = StateError('Synthetic validation failure.');
        var checks = 0;
        final live =
            _LiveFixture(snapshot: snapshot)
              ..validate = (_) {
                if (++checks > 1) return true;
                if (validationThrows) throw validationError;
                return false;
              }
              ..release.complete();
        final capture = _SurfaceCapture()..widgetData.addAll(_priorWidgetRows);
        final calls = _bindSurfaces(capture: capture);
        final failures = <(String, Object)>[];
        await providerSyncOnce(
          load: (owner) => loadProviderSyncWork(owner, createLive: live.create),
          logFailure: (step, error, _) => failures.add((step, error)),
          debugData: _DebugData(false),
        );
        expect(live.loads, 1);
        expect(checks, 1);
        final (step, error) = failures.single;
        expect(step, 'setup');
        if (validationThrows) {
          expect(error, same(validationError));
        } else {
          expect(
            error,
            isA<StateError>().having(
              (error) => error.message,
              'message',
              'Connection changed during refresh.',
            ),
          );
        }
        expect(calls, isEmpty);
        expect(capture.widgetData, _priorWidgetRows);
        expect(capture.redraws, isEmpty);
      });
    }

    test('Mock saved between surfaces stops the remaining effects', () async {
      final debugData = _DebugData(false);
      final surfaces = _bindSurfaces();
      debugData.beforeRead = () {
        if (surfaces.isNotEmpty) debugData.mock = true;
      };
      final headless = _HeadlessRun();
      final live = _LiveFixture()..release.complete();
      await headless.sync(live.create, debugData: debugData);
      expect(surfaces, ['syncWatchSummary']);
      expect(headless.failures, isEmpty);
      expect(headless.staleWrites, 0);
    });

    // After the redraw: the recovery step's guard, then its own checks after
    // the awaited preference and watchlist reads.
    for (final check in [2, 3]) {
      test('Mock seen at recovery check $check stops bookkeeping', () async {
        final debugData = _DebugData(false);
        final surfaces = _bindSurfaces();
        var sinceRedraw = 0;
        debugData.beforeRead = () {
          if (surfaces.contains('updateWidget') && ++sinceRedraw == check)
            debugData.mock = true;
        };
        final headless = _HeadlessRun();
        final live = _LiveFixture()..release.complete();
        await headless.sync(live.create, debugData: debugData);
        expect(surfaces, containsAll(['syncWatchSummary', 'updateWidget']));
        expect(headless.failures, isEmpty);
        // A Live write would leave even an empty watchlist behind.
        final watchlist = await const FlutterSecureStorage().read(
          key: 'wardpulse.recovery.exhaustedWindows',
        );
        expect(watchlist, isNull);
      });
    }

    final modes = <(bool, bool?)>[(true, false), (false, true), (false, null)];
    for (final (debugBuild, saved) in modes) {
      final build = debugBuild ? 'debug' : 'release';
      final choice = saved == null ? 'unreadable' : 'saved $saved';
      test('$build Live publishes with a $choice Mock choice', () async {
        final debugData = _DebugData(saved);
        final surfaces = _bindSurfaces();
        final headless = _HeadlessRun();
        final live = _LiveFixture()..release.complete();
        await headless.sync(
          live.create,
          debugData: debugData,
          debugBuild: debugBuild,
        );
        expect(live.loads, 1);
        expect(surfaces, containsAll(['syncWatchSummary', 'updateWidget']));
        expect(debugData.reads, debugBuild ? isPositive : 0);
      });
    }
  });
}

typedef _RecordedFailure = ({String step, Object error, StackTrace stackTrace});

final class _OpenAiReportingTransport implements ProviderHttpTransport {
  const _OpenAiReportingTransport({
    required this.providerFails,
    this.onRequest,
  });

  final bool providerFails;
  final void Function()? onRequest;

  @override
  Future<ProviderHttpResponse> get(
    Uri uri, {
    required Map<String, String> headers,
  }) async {
    onRequest?.call();
    return providerFails
        ? const ProviderHttpResponse(statusCode: 500, headers: {}, body: '{}')
        : const ProviderHttpResponse(
          statusCode: 200,
          headers: {},
          body: '{"object":"page","data":[],"has_more":false}',
        );
  }

  @override
  Future<ProviderHttpResponse> post(
    Uri uri, {
    required Map<String, String> headers,
    String? body,
  }) => get(uri, headers: headers);
}

final class _CursorPlanTransport implements ProviderHttpTransport {
  const _CursorPlanTransport(
    this.usedPercent, {
    this.onRequest,
    this.offline = false,
  });

  final int usedPercent;
  final void Function()? onRequest;
  final bool offline;

  @override
  Future<ProviderHttpResponse> get(
    Uri uri, {
    required Map<String, String> headers,
  }) async {
    onRequest?.call();
    if (offline) throw TimeoutException('Synthetic Cursor offline.');
    return ProviderHttpResponse(
      statusCode: 200,
      headers: const {},
      body: jsonEncode({
        'membershipType': 'pro_plus',
        'individualUsage': {
          'plan': {
            'enabled': true,
            'autoPercentUsed': usedPercent,
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

final class _RejectedReportingTransport implements ProviderHttpTransport {
  int calls = 0;
  @override
  Future<ProviderHttpResponse> get(
    Uri uri, {
    required Map<String, String> headers,
  }) async {
    calls++;
    return const ProviderHttpResponse(statusCode: 401, headers: {}, body: '{}');
  }

  @override
  Future<ProviderHttpResponse> post(
    Uri uri, {
    required Map<String, String> headers,
    String? body,
  }) => get(uri, headers: headers);
}

/// Holds the first provider request, then answers with a server error.
final class _HeldFailingTransport implements ProviderHttpTransport {
  final started = Completer<void>();
  final release = Completer<void>();

  @override
  Future<ProviderHttpResponse> get(
    Uri uri, {
    required Map<String, String> headers,
  }) async {
    if (!started.isCompleted) started.complete();
    await release.future;
    return const ProviderHttpResponse(statusCode: 500, headers: {}, body: '{}');
  }

  @override
  Future<ProviderHttpResponse> post(
    Uri uri, {
    required Map<String, String> headers,
    String? body,
  }) => get(uri, headers: headers);
}

final class _RejectedCodexTransport implements CodexHttpTransport {
  @override
  Future<CodexHttpResponse> send(
    String method,
    Uri uri, {
    required Map<String, String> headers,
    String? body,
  }) async => const CodexHttpResponse(statusCode: 401, body: '{}');
}

final class _StubClaudeTransport implements ClaudeHttpTransport {
  const _StubClaudeTransport([
    this.response = const ClaudeHttpResponse(statusCode: 401, body: '{}'),
  ]);

  final ClaudeHttpResponse response;

  @override
  Future<ClaudeHttpResponse> send(
    String method,
    Uri uri, {
    required Map<String, String> headers,
    String? body,
    Duration? timeout,
  }) async => response;
}

final class _UpgradeClaudeTransport implements ClaudeHttpTransport {
  const _UpgradeClaudeTransport(this.requests);

  final List<String> requests;

  @override
  Future<ClaudeHttpResponse> send(
    String method,
    Uri uri, {
    required Map<String, String> headers,
    String? body,
    Duration? timeout,
  }) async {
    requests.add('$method ${uri.path}');
    return switch (method) {
      'POST' => const ClaudeHttpResponse(
        statusCode: 200,
        body:
            '{"access_token":"fake-renewed","refresh_token":"fake-rotated","expires_in":3600}',
      ),
      'GET' => const ClaudeHttpResponse(
        statusCode: 200,
        body: '{"five_hour":{"utilization":42},"seven_day":{"utilization":38}}',
      ),
      _ => throw StateError('Unexpected test request.'),
    };
  }
}

final class _ObservedRepository extends DashboardRepository {
  const _ObservedRepository(this._delegate, this._observer);

  final DashboardRepository _delegate;
  final ReportingObserver _observer;

  @override
  Future<DashboardSnapshot> load() => _delegate.loadObserved(_observer);

  @override
  Future<bool> isSnapshotCurrent(DashboardSnapshot snapshot) =>
      _delegate.isSnapshotCurrent(snapshot);
}

/// One headless run through the production loader, recording its effects.
final class _HeadlessRun {
  final failures = <String>[];
  var staleWrites = 0;

  Future<void> sync(
    PhoneLiveBindings Function() createLive, {
    DebugDataPreferenceStore? debugData,
    bool debugBuild = true,
    WatchRingPreferenceStore? watchRingStore,
    PhoneWidgetPreferenceStore? widgetStore,
  }) {
    return providerSyncOnce(
      load:
          (owner) => loadProviderSyncWork(
            owner,
            createLive: createLive,
            watchRingStore: watchRingStore,
            widgetStore: widgetStore,
            // Neither empty nor 40%/90% fixture snapshots have spent windows.
            readWindows: (_) => const [],
          ),
      logFailure: (step, _, _) => failures.add(step),
      markWidgetStale: ({required isCurrent}) async {
        staleWrites++;
      },
      debugBuild: debugBuild,
      debugData: debugData,
    );
  }
}

final class _DebugData implements DebugDataPreferenceStore {
  _DebugData(this.mock);

  /// `null` makes the saved choice unreadable.
  bool? mock;
  void Function()? beforeRead;
  var reads = 0;

  @override
  Future<bool> readMockDataEnabled() async {
    reads++;
    beforeRead?.call();
    final value = mock;
    if (value == null) throw StateError('Sanitized debug preference failure.');
    return value;
  }

  @override
  Future<void> writeMockDataEnabled(bool value) async {
    mock = value;
  }
}

/// Production bindings whose one repository load can be held or failed.
final class _LiveFixture {
  _LiveFixture({this.fail = false, this.snapshot});

  final bool fail;
  final DashboardSnapshot? snapshot;
  final started = Completer<void>();
  final release = Completer<void>();
  var created = 0;
  var loads = 0;

  /// Repository provenance; `false` models replaced credentials.
  var current = true;
  bool Function(DashboardSnapshot)? validate;

  PhoneLiveBindings create() {
    created++;
    final live = PhoneLiveBindings.create(secureStorage: FakeSecureStorage());
    return PhoneLiveBindings(
      credentialStore: live.credentialStore,
      codexAccountService: live.codexAccountService,
      claudeAccountService: live.claudeAccountService,
      repository: _HeldRepository(this),
    );
  }
}

final class _HeldRepository extends DashboardRepository {
  _HeldRepository(this._fixture);

  final _LiveFixture _fixture;

  @override
  Future<DashboardSnapshot> load() async {
    _fixture.loads++;
    if (!_fixture.started.isCompleted) _fixture.started.complete();
    await _fixture.release.future;
    if (_fixture.fail) throw const DashboardLoadException();
    return _fixture.snapshot ?? DashboardSnapshot.empty();
  }

  @override
  Future<bool> isSnapshotCurrent(DashboardSnapshot snapshot) async =>
      _fixture.validate?.call(snapshot) ?? _fixture.current;
}

/// Records watch and widget plugin calls; both succeed.
List<String> _bindSurfaces({_SurfaceCapture? capture}) {
  final output = capture ?? _SurfaceCapture();
  final calls = <String>[];
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const channels = [
    MethodChannel('app.wardpulse/watch_sync'),
    MethodChannel('home_widget'),
    MethodChannel('app.wardpulse/widget_publication'),
  ];
  for (final channel in channels) {
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      if (call.method == 'syncWatchSummary') {
        output.watchSummaries.add(
          jsonDecode(call.arguments as String) as Map<String, dynamic>,
        );
        return null;
      }
      switch (call.method) {
        case 'publish':
          output.widgetData.addAll(
            Map<String, Object?>.from(call.arguments as Map),
          );
          return true;
        case 'markStale':
          if ((output.widgetData['row_count'] as int? ?? 0) <= 0 ||
              output.widgetData['empty'] == '1') {
            return null;
          }
          output.widgetData['stale'] = '1';
          return true;
        case 'updateWidget':
          output.redraws.add(Map.of(output.widgetData));
          return true;
        default:
          throw MissingPluginException();
      }
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
  }
  return calls;
}

final class _SurfaceCapture {
  final watchSummaries = <Map<String, dynamic>>[];
  final widgetData = <String, Object?>{};
  final redraws = <Map<String, Object?>>[];
}

const _ordinaryWidgetId = 'allowance.claude.claude-five-hour';
const _bothWidgetChoices = PhoneWidgetPreferences(
  selectedIds: [_ordinaryWidgetId, claudeFableRingId],
);
const _priorWidgetRows = <String, Object?>{
  'row_count': 2,
  'empty': '0',
  'stale': '0',
  'row_0_kind': 'allowance',
  'row_0_family': 'Claude',
  'row_0_pool': 'Fable weekly',
  'row_0_label': 'Claude · Fable',
  'row_0_percent': '30% left',
  'row_1_kind': 'allowance',
  'row_1_family': 'Claude',
  'row_1_pool': '5h',
  'row_1_label': 'Claude · 5h',
  'row_1_percent': '80% left',
};

Map<String, num> _watchUsage(Map<String, dynamic> summary) {
  final usage = <String, num>{};
  for (final ring in summary['rings'] as List) {
    usage[ring['id'] as String] = ring['usedPercent'] as num;
    final split = ring['split'];
    if (split != null)
      usage[split['id'] as String] = split['usedPercent'] as num;
  }
  return usage;
}

void _expectWidgetRows(_SurfaceCapture capture, {bool includeOrdinary = true}) {
  final rows = [
    ('Fable weekly', 'Claude · Fable', '10% left'),
    if (includeOrdinary) ('5h', 'Claude · 5h', '60% left'),
  ];
  final data = capture.widgetData;
  expect(data['row_count'], rows.length);
  expect(data['stale'], '0');
  expect(data['empty'], '0');
  for (final (i, (pool, label, percent)) in rows.indexed) {
    expect(data['row_${i}_kind'], 'allowance');
    expect(data['row_${i}_family'], 'Claude');
    expect(data['row_${i}_pool'], pool);
    expect(data['row_${i}_label'], label);
    expect(data['row_${i}_percent'], percent);
  }
  for (var i = rows.length; i < phoneWidgetSlotCount; i++) {
    final cleared = data.entries.where(
      (entry) => entry.key.startsWith('row_${i}_'),
    );
    expect(cleared, isNotEmpty);
    expect(cleared.map((entry) => entry.value), everyElement(''));
  }
  expect(capture.redraws, hasLength(1));
  expect(capture.redraws.single, data);
}

DashboardSnapshot _surfaceSnapshot() {
  final base =
      DashboardSnapshot.empty(generatedAt: DateTime.utc(2026, 11, 9)).toJson();
  return DashboardSnapshot.fromJson({
    ...base,
    'accounts': [
      {
        'accountId': 'claude-local',
        'provider': 'claude',
        'connection': ProviderConnections.claudePlan.storageKey,
        'status': 'ok',
        'today': base['todayTotal'],
        'week': base['weekTotal'],
        'month': base['monthTotal'],
        'credits': <Object?>[],
        'buckets': <Object?>[],
        'modelBreakdown': <Object?>[],
        'lastSuccessfulSyncAt': '2026-11-09T00:00:00Z',
        'allowances': [
          for (final (id, label, usedPercent, windowMinutes) in [
            ('claude-five-hour', '5h', 40.0, 300),
            ('claude-seven-day-fable', 'Fable weekly', 90.0, 10080),
          ])
            {
              'id': id,
              'source': 'plan',
              'label': label,
              'usedPercent': usedPercent,
              'used': null,
              'limit': null,
              'remaining': null,
              'unlimited': false,
              'windowMinutes': windowMinutes,
              'resetsAt': null,
              'status': 'ok',
            },
          {
            'id': 'claude-extra-usage',
            'source': 'purchased',
            'label': 'Extra usage',
            'usedPercent': null,
            'used': null,
            'limit': null,
            'remaining': {'value': '1200', 'unit': 'credits'},
            'unlimited': false,
            'windowMinutes': null,
            'resetsAt': null,
            'status': 'ok',
          },
        ],
      },
    ],
  });
}

final class _WatchRead implements WatchRingPreferenceStore {
  _WatchRead(this.load);

  final Future<WatchRingPreferences> Function() load;

  @override
  Future<WatchRingPreferences> read() => load();

  @override
  Future<void> write(WatchRingPreferences value) =>
      throw UnsupportedError('Read-only test store.');
}

final class _WidgetRead implements PhoneWidgetPreferenceStore {
  _WidgetRead(this.load);

  final Future<PhoneWidgetPreferences> Function() load;

  @override
  Future<PhoneWidgetPreferences> read() => load();

  @override
  Future<void> write(PhoneWidgetPreferences value) =>
      throw UnsupportedError('Read-only test store.');
}
