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
import 'package:ward_pulse_phone/settings/watch_ring_preferences.dart';
import 'package:ward_pulse_phone/sync/headless_provider_sync.dart';
import 'package:ward_pulse_phone/sync/provider_sync_once.dart';
import 'package:ward_pulse_phone/sync/watch_sync_service.dart';
import 'package:ward_pulse_phone/sync/automatic_poll.dart';
import 'package:ward_pulse_phone/sync/recovery_wake.dart';

import 'connection_cache_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'setup failure after wholly skipped work cannot mark the widget stale',
    () async {
      var staleWrites = 0;
      await providerSyncOnce(
        load: () async {
          final poll = AutomaticPollContext.current!;
          poll.skipped['openai.platform'] = AutomaticPollSkipped(
            'openai.platform',
            CredentialVersion({}),
            DateTime.utc(2026, 11, 6),
          );
          throw StateError('Synthetic post-load failure');
        },
        markWidgetStale: () async {
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
        await work.syncWatch();
        await work.syncWidget();
        await work.syncAlerts();
        expect(poll.whollySkipped, isTrue);
      },
    );
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
            load: () => loadProviderSyncWork(createLive: createLive),
            markWidgetStale: () async {},
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
            () async => ProviderSyncWork(
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
            () async => ProviderSyncWork(
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
          () async => ProviderSyncWork(
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
              () async => ProviderSyncWork(
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
            load: () async => throw StateError('credentials unavailable'),
            markWidgetStale: () async {},
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
      var redraws = 0;
      const channel = MethodChannel('home_widget');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, (call) async {
        final args = Map<String, Object?>.from(call.arguments as Map);
        switch (call.method) {
          case 'getWidgetData':
            return data[args['id']] ?? args['defaultValue'];
          case 'saveWidgetData':
            data[args['id']! as String] = args['data'];
            return true;
          case 'updateWidget':
            redraws += 1;
            return true;
          default:
            throw MissingPluginException();
        }
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      final failures = <String>[];
      final succeeded = await runHeadlessProviderTask(
        HeadlessProviderSync.taskName,
        sync:
            () => providerSyncOnce(
              load: () async => throw const DashboardLoadException(),
              logFailure: (step, _, _) => failures.add(step),
            ),
      );

      expect(succeeded, isTrue);
      expect(failures, ['setup']);
      expect(data, {...original, 'stale': '1'});
      expect(redraws, 1);
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
              load: () async => throw const DashboardLoadException(),
              markWidgetStale:
                  () async => throw StateError('Widget unavailable'),
              logFailure: (step, _, _) => failures.add(step),
            ),
      );
      expect(succeeded, isTrue);
      expect(failures, ['setup', 'widget']);
    },
  );
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
