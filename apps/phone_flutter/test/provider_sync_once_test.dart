import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
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
import 'package:ward_pulse_phone/dashboard/dashboard_models.dart';
import 'package:ward_pulse_phone/dashboard/dashboard_repository.dart';
import 'package:ward_pulse_phone/settings/debug_data_preferences.dart';
import 'package:ward_pulse_phone/settings/watch_ring_preferences.dart';
import 'package:ward_pulse_phone/sync/headless_provider_sync.dart';
import 'package:ward_pulse_phone/sync/provider_sync_once.dart';
import 'package:ward_pulse_phone/sync/watch_sync_service.dart';
import 'package:ward_pulse_phone/sync/automatic_poll.dart';
import 'package:ward_pulse_phone/sync/recovery_wake.dart';
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
    setUpAll(() async {
      bridge = await NativeCacheTestBridge.start();
    });
    tearDownAll(() => bridge.close());
    setUp(() async {
      FlutterSecureStorage.setMockInitialValues({});
      await bridge.reset();
    });
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
        // The repository strips an obsolete failure of its stamps; only the
        // admitted credentials can still reject it.
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
                transport: _RejectedClaudeTransport(),
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

    test('a rejected Live snapshot cannot mark rows STALE', () async {
      final surfaces = _bindSurfaces();
      final headless = _HeadlessRun();
      final live = _LiveFixture()..release.complete();
      live.current = false;
      await headless.sync(live.create, debugData: _DebugData(false));
      expect(live.loads, 1);
      expect(surfaces, isEmpty);
      expect(headless.failures, ['setup']);
      expect(headless.staleWrites, 0);
    });

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

final class _RejectedClaudeTransport implements ClaudeHttpTransport {
  @override
  Future<ClaudeHttpResponse> send(
    String method,
    Uri uri, {
    required Map<String, String> headers,
    String? body,
    Duration? timeout,
  }) async => const ClaudeHttpResponse(statusCode: 401, body: '{}');
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
      _fixture.current;
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
