import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:ward_pulse_phone/providers/cursor_plan_row.dart';
import 'package:ward_pulse_phone/providers/provider_connection_row.dart';
import 'package:ward_pulse_phone/dashboard/dashboard_load.dart';
import 'package:ward_pulse_phone/dashboard/dashboard_models.dart';
import 'package:ward_pulse_phone/dashboard/dashboard_repository.dart';
import 'package:ward_pulse_phone/dashboard/connection_snapshot_cache.dart';
import 'package:ward_pulse_phone/dashboard/merging_connection_repository.dart';
import 'package:ward_pulse_phone/dashboard/codex_dashboard_repository.dart';
import 'package:ward_pulse_phone/dashboard/claude_dashboard_repository.dart';
import 'package:ward_pulse_phone/providers/connection_lifecycle.dart';
import 'package:ward_pulse_phone/providers/connection_rejection_notice.dart';
import 'package:ward_pulse_phone/providers/claude_account_service.dart';
import 'package:ward_pulse_phone/providers/claude_account_store.dart';
import 'package:ward_pulse_phone/providers/codex_account_service.dart';
import 'package:ward_pulse_phone/providers/codex_account_store.dart';
import 'package:ward_pulse_phone/providers/provider_connection.dart';
import 'package:ward_pulse_phone/providers/provider_credential_store.dart';
import 'package:ward_pulse_phone/sync/claude_account_client.dart';
import 'package:ward_pulse_phone/sync/codex_account_client.dart';
import 'package:ward_pulse_phone/sync/provider_sync_logger.dart';
import 'package:ward_pulse_phone/sync/automatic_poll.dart';

import 'connection_cache_test_support.dart';

void main() {
  late NativeCacheTestBridge bridge;
  late FakeSecureStorage secure;
  final now = DateTime.utc(2026, 10, 13, 9);
  setUpAll(() async {
    bridge = await NativeCacheTestBridge.start();
  });
  tearDownAll(() => bridge.close());
  setUp(() async {
    await bridge.reset();
    secure = FakeSecureStorage();
  });
  ConnectionCredentialStorage store(String owner) =>
      ConnectionCredentialStorage(
        connection: 'cursor.plan',
        legacyKey: 'wardpulse.cursor.plan.secret',
        principal: (value) => value,
        storage: secure,
        platform: bridge.platform(owner),
      );

  SecureProviderCredentialStore reportingStore(String owner) =>
      SecureProviderCredentialStore(
        storage: secure,
        platform: bridge.platform(owner),
      );

  group('connection absence ownership', () {
    for (final completion in ['missing', 'deleted']) {
      test('activation retires a held completed $completion reply', () async {
        if (completion == 'deleted') await store('setup').delete();
        final completed = Completer<void>();
        final release = Completer<void>();
        final platform = ObservingCachePlatform(bridge.platform('reader'));
        final credentials = ConnectionCredentialStorage(
          connection: 'cursor.plan',
          legacyKey: 'wardpulse.cursor.plan.secret',
          principal: (value) => value,
          storage: secure,
          platform: platform,
        );
        platform.onComplete = (method, args, result) async {
          if (method == 'finish' &&
              result is Map &&
              result['mode'] == 'deleted') {
            completed.complete();
            await release.future;
          }
        };
        final repository = MergingConnectionRepository(
          cache: ConnectionSnapshotCache(
            connection: 'cursor.plan',
            platform: platform,
            readCredentialVersion: () async => null,
          ),
          fallback: const NoProvidersDashboardRepository(),
          loadReport: () async {
            await credentials.read();
            return null;
          },
          normalizeReport: (value) => value,
          mapError: (_) => const DashboardLoadException(),
          logger: const NullProviderSyncLogger(),
        );
        final loading = CapturedDashboardLoad.capture(repository.load);
        try {
          await completed.future;
          await store('activation').write('synthetic-new');
          release.complete();
          final result = await loading;
          DashboardLoadException? failure;
          try {
            result.value;
          } on DashboardLoadException catch (error) {
            failure = error;
          }
          expect(failure, isNotNull);
          expect(await repository.isFailureCurrent(failure!), isFalse);
          expect((await store('readback').read())!.value, 'synthetic-new');
        } finally {
          if (!release.isCompleted) release.complete();
          await loading;
        }
      });
    }

    for (final kind in [
      'parse',
      'identity',
      'unavailable',
      'failed completion',
      'accountless active',
      'pending',
    ]) {
      test('$kind does not establish absence', () async {
        var rejectPrincipal = false;
        final platform = ObservingCachePlatform(bridge.platform('reader'));
        final credentials = ConnectionCredentialStorage(
          connection: 'cursor.plan',
          legacyKey: 'wardpulse.cursor.plan.secret',
          principal: (value) {
            if (rejectPrincipal)
              throw const FormatException('Synthetic invalid session.');
            return value;
          },
          storage: secure,
          platform: platform,
        );
        if (kind == 'parse') {
          secure.values['wardpulse.cursor.plan.secret'] = 'synthetic-malformed';
          rejectPrincipal = true;
        } else if (kind == 'identity' || kind == 'accountless active') {
          await credentials.write('synthetic-active');
          if (kind == 'identity') {
            final read = (await credentials.read())!;
            final lease =
                await bridge.invoke('probe', 'acquire', {
                      'connection': 'cursor.plan',
                      'action': 'read',
                    })
                    as Map;
            await bridge.invoke('probe', 'finish', {
              'connection': 'cursor.plan',
              'lease': lease['lease'],
              'operation': 'release',
            });
            secure.values[lease['slot'] as String] = 'synthetic-other';
            expect(await credentials.isCurrent(read.version), isTrue);
          }
        } else if (kind == 'pending') {
          await credentials.beginReconnect();
        }
        secure.failRead = kind == 'unavailable';
        var completedMissing = false;
        platform.onComplete = (method, args, result) {
          if (method == 'finish' &&
              result is Map &&
              result['mode'] == 'deleted')
            completedMissing = true;
        };
        if (kind == 'failed completion') {
          await bridge.invoke('test', 'failCommit', {'value': true});
        }
        VersionedCredential<String>? actualRead;
        final repository = MergingConnectionRepository(
          cache: ConnectionSnapshotCache(
            connection: 'cursor.plan',
            platform: platform,
            readCredentialVersion: () async => null,
          ),
          fallback: const NoProvidersDashboardRepository(),
          loadReport: () async {
            actualRead = await credentials.read();
            return null;
          },
          normalizeReport: (value) => value,
          mapError: (_) => const DashboardLoadException(),
          logger: const NullProviderSyncLogger(),
        );
        final captured = await CapturedDashboardLoad.capture(repository.load);
        expect(captured.connectionVersions, isEmpty);
        if (kind == 'accountless active') {
          final snapshot = captured.value;
          expect(actualRead?.value, 'synthetic-active');
          expect(snapshot.accounts, isEmpty);
          expect(snapshot.snapshotOrdering, isEmpty);
          expect(await repository.isSnapshotCurrent(snapshot), isTrue);
        } else {
          final failure = captured.loadException;
          expect(failure, isNotNull);
          expect(
            failure!.snapshotOrdering['cursor.plan']?.selectionUnverified,
            isTrue,
          );
          expect(await repository.isFailureCurrent(failure), isFalse);
        }
        expect(completedMissing, kind == 'parse' || kind == 'identity');
      });
    }
  });

  for (final outcome in [
    'pending',
    'reconnected',
    'unreadable',
    'cancelled',
    'pasted',
    'barrier',
    'invalid-paste',
  ]) {
    testWidgets(
      'late disconnect settlement respects $outcome evidence',
      (tester) async {
        await tester.runAsync(() async {
          const id = ProviderConnections.cursorPlan;
          final observed = Completer<void>();
          final release = Completer<void>();
          final deleting = Completer<void>();
          final resumeDeletion = Completer<void>();
          final platform = _RecordingPlatform(bridge.platform('row'));
          final credentials = SecureProviderCredentialStore(
            storage: secure,
            platform: platform,
          );
          await credentials.writeSecret(id, 'synthetic-old');
          var changed = 0;
          final ready = Completer<void>();
          secure.beforeDelete = (key) async {
            if (key == 'wardpulse.cursor.plan.label') {
              observed.complete();
              await release.future;
            }
          };
          secure.failDeleteKey = 'wardpulse.cursor.plan.label';
          Future<void>? editing;
          Future<void>? recovery;
          try {
            await tester.pumpWidget(
              MaterialApp(
                home: Scaffold(
                  body: CursorPlanRow(
                    connection: providerConnectionCatalog().firstWhere(
                      (row) => row.id == id,
                    ),
                    credentialStore: credentials,
                    signIn: (_) async => null,
                    onInitialRead: () => () => ready.complete(),
                    onCredentialsChanged: () => changed++,
                    buildControls:
                        ({leading = const [], required status}) => (
                          actions: leading,
                          status: status,
                        ),
                  ),
                ),
              ),
            );
            await ready.future;
            await tester.pumpAndSettle();
            final help =
                tester
                    .widget<IconButton>(
                      find.descendant(
                        of: find.byType(CursorPlanRow),
                        matching: find.byWidgetPredicate(
                          (widget) =>
                              widget is IconButton &&
                              widget.tooltip == 'About Cursor plan sign-in',
                        ),
                      ),
                    )
                    .onPressed!;
            if (outcome == 'barrier') {
              await bridge.invoke('test', 'failCommit', {'value': true});
            } else if (outcome == 'invalid-paste') {
              platform.onInvoke = (method, args) async {
                if (method == 'acquire' && args['action'] == 'delete') {
                  deleting.complete();
                  await resumeDeletion.future;
                }
              };
            }
            editing =
                (tester
                            .widget<ProviderConnectionRow>(
                              find.byType(ProviderConnectionRow),
                            )
                            .onTap
                        as dynamic)()
                    as Future<void>;
            await tester.pumpAndSettle();
            await tester.tap(find.text('Disconnect'));
            if (outcome == 'invalid-paste') {
              await deleting.future;
              await tester.pump();
              expect(
                tester
                    .widget<IconButton>(
                      find.descendant(
                        of: find.byType(CursorPlanRow),
                        matching: find.byWidgetPredicate(
                          (widget) =>
                              widget is IconButton &&
                              widget.tooltip == 'About Cursor plan sign-in',
                        ),
                      ),
                    )
                    .onPressed,
                isNull,
              );
              // A callback retained from the previous frame is guarded too.
              await (help as dynamic)();
              await tester.pump();
              expect(find.text('Advanced paste'), findsNothing);
              expect(changed, 0);
              resumeDeletion.complete();
            }
            if (outcome != 'barrier') {
              await observed.future;
              expect(changed, 1);
              if (outcome == 'invalid-paste') {
                await tester.pumpAndSettle();
                recovery = (help as dynamic)() as Future<void>;
                await tester.pumpAndSettle();
                await tester.tap(find.text('Advanced paste'));
                await tester.pumpAndSettle();
                await tester.enterText(find.byType(TextFormField), 'invalid');
                await tester.tap(find.text('Save'));
                await recovery;
                await tester.pumpAndSettle();
                expect(
                  find.text('That does not look like a Cursor session token'),
                  findsOneWidget,
                );
                ScaffoldMessenger.of(
                  tester.element(find.byType(CursorPlanRow)),
                ).removeCurrentSnackBar();
              } else if ([
                'unreadable',
                'cancelled',
                'pasted',
              ].contains(outcome)) {
                platform.onInvoke = (method, args) {
                  if (method == 'acquire' && args['action'] == 'read') {
                    throw StateError('Synthetic lifecycle observation failure');
                  }
                };
              } else {
                final newer = reportingStore('new-owner');
                final ticket = await newer.beginReconnect(id);
                if (outcome == 'reconnected') {
                  expect(
                    await newer.completeReconnect(id, 'synthetic-new', ticket),
                    isTrue,
                  );
                }
              }
            }
            release.complete();
            await editing;
            await tester.pumpAndSettle();
            expect(changed, outcome == 'barrier' ? 0 : 1);
            expect(
              find.textContaining('Disconnected, but'),
              outcome == 'invalid-paste' ? findsOneWidget : findsNothing,
            );
            expect(
              find.text(
                outcome == 'invalid-paste'
                    ? 'Not connected'
                    : outcome == 'reconnected'
                    ? 'Connected'
                    : 'Unavailable · Retry check',
              ),
              findsOneWidget,
            );
            if (outcome != 'invalid-paste') {
              expect(find.text('Not connected'), findsNothing);
            }
            if (outcome == 'cancelled') {
              platform.onInvoke = null;
              recovery =
                  (tester
                              .widget<ProviderConnectionRow>(
                                find.byType(ProviderConnectionRow),
                              )
                              .onTap
                          as dynamic)()
                      as Future<void>;
              await recovery;
              await tester.pumpAndSettle();
              expect(find.text('Unavailable · Retry check'), findsOneWidget);
              expect(find.byType(RowProgress), findsNothing);
              expect(changed, 1);
            }
            if (outcome == 'pasted') {
              platform.onInvoke = null;
              recovery =
                  (tester
                              .widget<IconButton>(
                                find.descendant(
                                  of: find.byType(CursorPlanRow),
                                  matching: find.byWidgetPredicate(
                                    (widget) =>
                                        widget is IconButton &&
                                        widget.tooltip ==
                                            'About Cursor plan sign-in',
                                  ),
                                ),
                              )
                              .onPressed
                          as dynamic)()
                      as Future<void>;
              await tester.pumpAndSettle();
              await tester.tap(find.text('Advanced paste'));
              await tester.pumpAndSettle();
              await tester.enterText(
                find.byType(TextFormField),
                'synthetic-user::synthetic-session',
              );
              await tester.tap(find.text('Save'));
              await recovery;
              await tester.pumpAndSettle();
              expect(find.text('Connected'), findsOneWidget);
              expect(find.text('Unavailable · Retry check'), findsNothing);
              expect(changed, 2);
            }
            if (!['reconnected', 'pasted', 'invalid-paste'].contains(outcome)) {
              platform.onInvoke = null;
              final deletes = secure.deleted.length;
              final retry =
                  tester
                      .widget<TextButton>(
                        find.widgetWithText(
                          TextButton,
                          'Unavailable · Retry check',
                        ),
                      )
                      .onPressed!;
              await (retry as dynamic)();
              await tester.pumpAndSettle();
              expect(
                find.text(
                  outcome == 'unreadable'
                      ? 'Not connected'
                      : 'Unavailable · Retry check',
                ),
                findsOneWidget,
              );
              expect(secure.deleted.length, deletes);
            }
          } finally {
            if (!resumeDeletion.isCompleted) resumeDeletion.complete();
            if (!release.isCompleted) release.complete();
            platform.onInvoke = null;
            if (find.byType(AlertDialog).evaluate().isNotEmpty) {
              Navigator.of(tester.element(find.byType(AlertDialog))).pop();
            }
            await tester.pumpWidget(const SizedBox());
            if (editing != null) await editing;
            if (recovery != null) await recovery;
          }
        });
      },
      timeout: const Timeout(Duration(seconds: 60)),
    );
  }

  test(
    'successful retirement is synchronous, exact and releases observation',
    () async {
      final access = store('ui');
      await access.write('synthetic-old');
      final old = (await access.read())!.version;
      await access.write('synthetic-current');
      var notified = 0;
      await access.delete(expected: old, onRetired: (_) => notified++);
      expect(notified, 0);
      CredentialVersion? receipt;
      await access.delete(
        onRetired: (stamp) {
          receipt = stamp;
          notified++;
        },
      );
      expect(notified, 1);
      await expectLater(
        access.observeLifecycle((mode, stamp) {
          expect(mode, 'deleted');
          expect(stamp!.values, receipt!.values);
          throw StateError('Synthetic consumer failure');
        }),
        throwsStateError,
      );
      await store(
        'other',
      ).observeLifecycle((mode, _) => expect(mode, 'deleted'));
    },
  );

  test(
    'Codex disconnect retires the managed owner when encrypted reads fail',
    () async {
      const id = ProviderConnections.codexPlan;
      const siblingId = ProviderConnections.openAiPlatform;
      final platform = ObservingCachePlatform(bridge.platform('codex'));
      final codex = SecureCodexAccountStore(
        storage: secure,
        platform: platform,
      );
      final sibling = reportingStore('sibling');
      final session = CodexAccountSession(
        accessToken: 'synthetic-access',
        refreshToken: 'synthetic-refresh',
        accountId: 'synthetic-account',
        refreshedAt: now,
      );
      await codex.write(session);
      await sibling.writeSecret(siblingId, 'synthetic-reporting-key');
      final readKeys = <String>[];
      secure.onRead = (key, _) => readKeys.add(key);
      final old = (await codex.readVersioned())!.version;
      final slot = readKeys.singleWhere(
        (key) => secure.values[key] == jsonEncode(session.toJson()),
      );
      final siblingVersion = (await sibling.readVersion(siblingId))!;
      ConnectionSnapshotCache cache(
        String connection,
        Future<CredentialVersion?> Function() readVersion,
      ) => ConnectionSnapshotCache(
        connection: connection,
        platform: bridge.platform('cache'),
        readCredentialVersion: readVersion,
      );
      final oldCache = cache(
        id.storageKey,
        () async => (await codex.readVersioned())?.version,
      );
      final siblingCache = cache(
        siblingId.storageKey,
        () => sibling.readVersion(siblingId),
      );
      final normalized = _connectionSnapshot(id.storageKey, 'codex', now);
      final siblingSnapshot = _connectionSnapshot(
        siblingId.storageKey,
        'openai',
        now,
      );
      await codex.observeLifecycle((mode, stamp) {
        expect(mode, 'active');
        expect(stamp!.values, old.values);
      });
      expect(await codex.isCurrent(old), isTrue);
      expect(await oldCache.store(normalized, old), isTrue);
      expect((await oldCache.capture()).snapshot, isNotNull);
      expect(await siblingCache.store(siblingSnapshot, siblingVersion), isTrue);
      final siblingBefore = (await siblingCache.capture()).snapshot!;

      final events = <String>[];
      platform.onComplete = (method, args, result) {
        events.add('$method:${args['action'] ?? args['operation']}:$result');
      };
      secure.failReadKey = slot;
      secure.onRead = (key, completion) {
        if (key == slot) {
          unawaited(
            completion.then<void>(
              (_) => events.add('encrypted-read-succeeded'),
              onError: (Object error, StackTrace stack) {
                events.add('encrypted-read-failed');
              },
            ),
          );
        }
      };
      var requests = 0;
      final client = CodexAccountClient(
        transport: _CodexTransport((uri, headers, body) async {
          requests++;
          return _usageResponse(uri);
        }),
        clock: () => now,
      );
      final service = MobileCodexAccountService(store: codex, client: client);
      final receipts = <CredentialVersion>[];
      Object? serviceError;
      try {
        await service.disconnect(onRetired: receipts.add);
        events.add('service-completed');
      } catch (error) {
        serviceError = error;
        events.add('service-failed');
      }
      String? mode;
      CredentialVersion? stamp;
      await codex.observeLifecycle((observedMode, observedStamp) {
        mode = observedMode;
        stamp = observedStamp;
      });
      final current = await codex.isCurrent(old);
      final eligible = await oldCache.valid(old);
      final retained = (await oldCache.capture(expected: old)).snapshot;
      final latePublished = await oldCache.store(normalized, old);
      secure.failReadKey = null;
      final recovered = await codex.readVersioned();
      final recoveredConnected = await service.isConnected();
      final recoveredReport = await service.fetchReport();
      await bridge.invoke('test', 'restart', {});
      final cold = SecureCodexAccountStore(
        storage: secure,
        platform: bridge.platform('cold'),
      );
      final coldService = MobileCodexAccountService(
        store: cold,
        client: client,
      );
      final coldRead = await cold.readVersioned();
      final coldConnected = await coldService.isConnected();
      final coldReport = await coldService.fetchReport();
      final coldCache = cache(
        id.storageKey,
        () async => (await cold.readVersioned())?.version,
      );
      final coldCurrent = await cold.isCurrent(old);
      final coldEligible = await coldCache.valid(old);
      final coldSnapshot = (await coldCache.capture(expected: old)).snapshot;
      final coldPublished = await coldCache.store(normalized, old);
      final siblingAfter = (await siblingCache.capture()).snapshot;
      final siblingSecret = await sibling.readSecret(siblingId);
      final siblingCurrent = await sibling.readVersion(siblingId);
      stdout.writeln(
        'CODEX-READ-ORACLE ${jsonEncode({'mode': mode, 'current': current, 'cacheEligible': eligible, 'retainedCache': retained != null, 'latePublished': latePublished, 'coldCurrent': coldCurrent, 'coldCacheEligible': coldEligible, 'coldCache': coldSnapshot != null, 'coldPublished': coldPublished, 'encryptedReadFailed': events.contains('encrypted-read-failed'), 'receipts': receipts.length, 'siblingUnchanged': siblingSecret == 'synthetic-reporting-key' && siblingAfter?.toJsonString() == siblingBefore.toJsonString() && jsonEncode(siblingCurrent?.values) == jsonEncode(siblingVersion.values)})}',
      );

      // OLD reaches this joint oracle with its owner/cache still eligible.
      expect(
        [
          mode,
          current,
          eligible,
          retained,
          latePublished,
          recovered,
          recoveredConnected,
          recoveredReport,
          coldRead,
          coldConnected,
          coldReport,
          coldCurrent,
          coldEligible,
          coldSnapshot,
          coldPublished,
        ],
        [
          'deleted',
          false,
          false,
          null,
          false,
          null,
          false,
          null,
          null,
          false,
          null,
          false,
          false,
          null,
          false,
        ],
        reason: 'Codex encrypted-read retirement oracle;',
      );
      expect(serviceError, isNull);
      expect(events, contains('encrypted-read-failed'));
      expect(receipts, hasLength(1));
      expect(stamp!.values, receipts.single.values);
      expect([
        stamp!.generation,
        stamp!.revision,
        stamp!.epoch,
      ], everyElement(isNotEmpty));
      expect(requests, 0, reason: 'Unreadable material cannot be revoked.');
      expect(siblingSecret, 'synthetic-reporting-key');
      expect(siblingCurrent!.values, siblingVersion.values);
      expect(siblingAfter!.toJsonString(), siblingBefore.toJsonString());
    },
    timeout: const Timeout(Duration(seconds: 45)),
  );

  test('Codex failed delete barrier never reports retirement', () async {
    final platform = ObservingCachePlatform(bridge.platform('codex'));
    final codex = SecureCodexAccountStore(storage: secure, platform: platform);
    await codex.write(
      CodexAccountSession(
        accessToken: 'synthetic-access',
        refreshToken: 'synthetic-refresh',
        accountId: 'synthetic-account',
        refreshedAt: now,
      ),
    );
    final keys = <String>[];
    secure.onRead = (key, _) => keys.add(key);
    final original = (await codex.readVersioned())!;
    final slot = keys.single;
    ConnectionSnapshotCache cache(SecureCodexAccountStore store) =>
        ConnectionSnapshotCache(
          connection: 'openai.plan',
          platform: bridge.platform('cache'),
          readCredentialVersion:
              () async => (await store.readVersioned())?.version,
        );
    final snapshot = _connectionSnapshot('openai.plan', 'codex', now);
    expect(await cache(codex).store(snapshot, original.version), isTrue);
    final before = (await cache(codex).capture()).snapshot!;
    String? readLease;
    var readReleased = false, faultAfterRelease = false;
    platform.onComplete = (method, args, result) {
      if (method == 'acquire' && args['action'] == 'read') {
        readLease = (result! as Map)['lease'] as String;
      }
      if (method == 'finish' &&
          args['lease'] == readLease &&
          args['operation'] == 'release') {
        readReleased = true;
      }
    };
    platform.beforeInvoke = (method, args) async {
      if (method == 'acquire' && args['action'] == 'delete') {
        faultAfterRelease = readReleased;
        await bridge.invoke('test', 'failCommit', {'value': true});
      }
    };
    secure.failReadKey = slot;
    final receipts = <CredentialVersion>[];
    var requests = 0;
    final service = MobileCodexAccountService(
      store: codex,
      client: CodexAccountClient(
        transport: _CodexTransport((uri, headers, body) async {
          requests++;
          return _usageResponse(uri);
        }),
        clock: () => now,
      ),
    );
    Object? serviceError;
    try {
      await service.disconnect(onRetired: receipts.add);
    } catch (error) {
      serviceError = error;
    } finally {
      await bridge.invoke('test', 'failCommit', {'value': false});
      secure.failReadKey = null;
      platform.beforeInvoke = null;
    }
    Object? observationError;
    String? mode;
    try {
      await codex.observeLifecycle((value, _) => mode = value);
    } catch (error) {
      observationError = error;
    }
    final current = await codex.isCurrent(original.version);
    await bridge.invoke('test', 'restart', {});
    final cold = SecureCodexAccountStore(
      storage: secure,
      platform: bridge.platform('cold'),
    );
    final recovered = await cold.readVersioned();
    final recoveredCache = (await cache(cold).capture()).snapshot;
    expect(faultAfterRelease, isTrue);
    expect(
      serviceError,
      isA<CodexAccountException>().having(
        (error) => error.failure,
        'failure',
        CodexAccountFailure.unavailable,
      ),
    );
    expect(receipts, isEmpty);
    expect(requests, 0);
    expect(observationError, isStateError);
    expect(mode, isNull);
    expect(current, isFalse);
    expect(recovered!.value.toJson(), original.value.toJson());
    expect(recovered.version.values, original.version.values);
    expect(recoveredCache!.toJsonString(), before.toJsonString());
  });

  test(
    'OAuth removals forward retirement before secure cleanup fails',
    () async {
      final codex = SecureCodexAccountStore(
        storage: secure,
        platform: bridge.platform('codex'),
      );
      final claude = SecureClaudeAccountStore(
        storage: secure,
        platform: bridge.platform('claude'),
      );
      await codex.write(
        CodexAccountSession(
          accessToken: 'synthetic-access',
          refreshToken: 'synthetic-refresh',
          accountId: 'synthetic-account',
          refreshedAt: now,
        ),
      );
      await claude.write(
        ClaudeAccountSession(
          accessToken: 'synthetic-access',
          refreshToken: 'synthetic-refresh',
          accountId: 'synthetic-account',
          expiresAt: now,
        ),
      );
      for (final (remove, observe, key) in [
        (
          MobileCodexAccountService(store: codex).disconnect,
          codex.observeLifecycle,
          'wardpulse.codex.account-session',
        ),
        (
          MobileClaudeAccountService(store: claude).disconnect,
          claude.observeLifecycle,
          'wardpulse.claude.account-session',
        ),
      ]) {
        secure.failDeleteKey = key;
        CredentialVersion? receipt;
        await expectLater(
          remove(onRetired: (stamp) => receipt = stamp),
          throwsA(anything),
        );
        await observe((mode, stamp) {
          expect(mode, 'deleted');
          expect(stamp!.values, receipt!.values);
        });
      }
    },
  );

  test(
    'retained-session notices survive lifecycle changes and exact dismissal',
    () async {
      final access = store('session');
      final notices = NativeConnectionRejectionNoticeStore(
        platform: bridge.platform('notices'),
      );
      expect(await notices.read(), isEmpty);
      await access.write('synthetic-session');
      var captured = (await access.read())!;
      expect(
        await access.serializeFetch(
          () => access.rejectAuthentication(captured.version),
        ),
        isTrue,
      );
      final first = (await notices.read()).single;
      expect(await notices.dismiss(first), isTrue);
      await bridge.invoke('test', 'restart', {});
      captured = (await store('cold').read())!;
      expect(
        await access.serializeFetch(
          () => access.rejectAuthentication(captured.version),
        ),
        isTrue,
      );
      expect((await notices.read()).single.dismissed, isTrue);
      await access.write('synthetic-session');
      expect((await notices.read()).single.eventId, first.eventId);
      captured = (await access.read())!;
      await access.serializeFetch(
        () => access.rejectAuthentication(captured.version),
      );
      final second = (await notices.read()).single;
      expect(second.eventId, isNot(first.eventId));
      expect(await notices.dismiss(first), isFalse);
      await access.delete();
      expect(await store('cold2').read(), isNull);
      expect((await notices.read()).single.dismissed, isFalse);
      await bridge.invoke('test', 'restart', {});
      expect((await notices.read()).single.eventId, second.eventId);
      await notices.dismiss(second);
      await bridge.invoke('test', 'restart', {});
      expect(
        (await notices.read()).where((notice) => !notice.dismissed),
        isEmpty,
      );
    },
  );

  test(
    'notice-only storage failure preserves valid credentials and confirmed view',
    () async {
      final access = store('session');
      final notices = NativeConnectionRejectionNoticeStore(
        platform: bridge.platform('notices'),
      );
      await access.write('synthetic-session');
      final captured = (await access.read())!;
      await access.serializeFetch(
        () => access.rejectAuthentication(captured.version),
      );
      final event = (await notices.read()).single;
      await bridge.invoke('test', 'failCommit', {'value': true});
      await expectLater(notices.dismiss(event), throwsStateError);
      expect((await notices.read()).single.dismissed, isFalse);
      expect(await access.isCurrent(captured.version), isTrue);
      await bridge.invoke('test', 'failCommit', {'value': false});
      expect((await store('cold').read())?.value, 'synthetic-session');
    },
  );

  test(
    'optional reporting access retains only immutable read provenance',
    () async {
      const id = ProviderConnections.openAiPlatform;
      final credentials = reportingStore('reporting');
      final VersionedProviderCredentialStore capability = credentials;
      final access = capability.credentialAccess(id)!;
      expect(
        capability.credentialAccess(ProviderConnections.codexPlan),
        isNull,
      );
      expect(
        capability.credentialAccess(ProviderConnections.claudePlan),
        isNull,
      );
      await credentials.writeSecret(id, ' fake-current ');
      final read = (await access.read())!;
      expect(read.value, 'fake-current');
      expect((await credentials.readVersion(id))?.values, read.version.values);
      final original = Map.of(read.version.values);
      expect(
        original.keys,
        unorderedEquals([
          'generation',
          'revision',
          'identity',
          'epoch',
          'committedConnection',
        ]),
      );
      final outcome = ConnectionReportingOutcome(
        connection: id,
        category: ReportingOutcomeCategory.success,
        source: ReportingOutcomeSource.live,
        freshness: ReportingOutcomeFreshness.current,
        credentialVersion: read.version,
      );
      expect(
        () => outcome.credentialVersion!.values.clear(),
        throwsUnsupportedError,
      );
      final otherRevision = CredentialVersion({
        ...original,
        'revision': 'different-revision',
      });
      expect(read.version.sameCache(otherRevision), isTrue);
      expect(await access.isCurrent(otherRevision), isTrue);

      // Even an explicit replacement with the same value retires the old stamp.
      final replacement = reportingStore('replacement');
      await replacement.writeSecret(id, 'fake-current');
      final current = (await access.read())!;
      expect(read.version.sameCache(current.version), isFalse);
      expect(await access.isCurrent(read.version), isFalse);
      expect(await access.isCurrent(current.version), isTrue);
      expect(outcome.credentialVersion!.values, original);
      await replacement.deleteSecret(id);
      expect(await access.isCurrent(current.version), isFalse);
      expect(await access.read(), isNull);
    },
  );

  for (final failure in ['label', 'retired slot']) {
    test(
      'reporting removal stays retired after $failure cleanup fails',
      () async {
        const id = ProviderConnections.openAiPlatform;
        final credentials = reportingStore('reporting');
        await credentials.writeSecret(id, 'synthetic-key');
        await credentials.writeLabel(id, 'Synthetic label');
        final version =
            (await credentials.credentialAccess(id)!.read())!.version;
        final failedKey =
            failure == 'label'
                ? 'wardpulse.openai.admin-api-key.label'
                : secure.values.keys.singleWhere(
                  (key) => key.startsWith('wardpulse.connection.'),
                );
        secure.failDeleteKey = failedKey;
        CredentialVersion? receipt;
        final deleting = credentials.deleteSecret(
          id,
          onRetired: (stamp) {
            receipt = stamp;
            expect(secure.deleted, isNot(contains(failedKey)));
          },
        );
        await expectLater(deleting, throwsStateError);
        expect(receipt, isNotNull);
        await credentials.credentialAccess(id)!.observeLifecycle((mode, stamp) {
          expect(mode, 'deleted');
          expect(stamp!.values, receipt!.values);
        });
        expect(await reportingStore('cold').readSecret(id), isNull);
        expect(
          await credentials.credentialAccess(id)!.isCurrent(version),
          isFalse,
        );
        expect(secure.values[failedKey], isNotNull);
        secure.failDeleteKey = null;
        // A normal retry finishes both native-retired cleanup and label removal.
        await reportingStore('cold').deleteSecret(id);
        expect(secure.values[failedKey], isNull);
      },
    );
  }

  test(
    'reporting absence differs from a failed local read and releases storage',
    () async {
      const id = ProviderConnections.cursorPlatform;
      final credentials = reportingStore('reporting');
      final access = credentials.credentialAccess(id)!;
      Future<String?> readSecret(ProviderCredentialStore source) =>
          readConnectionSecret(
            store: source,
            id: id,
            logger: const NullProviderSyncLogger(),
          );
      expect(await access.read(), isNull);
      expect(await readSecret(credentials), isNull);
      expect(await readSecret(const EmptyProviderCredentialStore()), isNull);
      await credentials.writeSecret(id, 'fake-saved');
      secure.failRead = true;
      await expectLater(access.read(), throwsStateError);
      await expectLater(
        readSecret(credentials),
        throwsA(
          isA<DashboardLoadException>()
              .having(
                (error) => error.issue,
                'issue',
                DashboardSyncIssue.credentialUnavailable,
              )
              .having((error) => error.details, 'safe details', isNull)
              .having(
                (error) => error.reportingOutcomes.single.connection,
                'connection',
                id,
              )
              .having(
                (error) => error.reportingOutcomes.single.category,
                'category',
                ReportingOutcomeCategory.localReadFailure,
              )
              .having(
                (error) => error.reportingOutcomes.single.source,
                'source',
                ReportingOutcomeSource.local,
              )
              .having(
                (error) => error.reportingOutcomes.single.credentialVersion,
                'unavailable provenance',
                isNull,
              ),
        ),
      );
      secure.failRead = false;
      expect((await access.read())?.value, 'fake-saved');
    },
  );

  test(
    'reporting fetch ownership serializes reads without holding a storage transaction',
    () async {
      const id = ProviderConnections.anthropicPlatform;
      final credentials = reportingStore('reporting-a');
      await credentials.writeSecret(id, 'fake-old');
      final a = credentials.credentialAccess(id)!;
      final queued = Completer<void>();
      final platform = _RecordingPlatform(bridge.platform('reporting-b'))
        ..onInvoke = (method, _) {
          if (method == 'acquireFetch') queued.complete();
        };
      final b =
          SecureProviderCredentialStore(
            storage: secure,
            platform: platform,
          ).credentialAccess(id)!;
      final entered = Completer<CredentialVersion>();
      final release = Completer<void>();
      final loadingA = a.serializeFetch(() async {
        final read = (await a.read())!;
        entered.complete(read.version);
        await release.future;
        return ConnectionReportingOutcome(
          connection: id,
          category: ReportingOutcomeCategory.authenticationRejected,
          source: ReportingOutcomeSource.live,
          credentialVersion: read.version,
        );
      });
      final original = await entered.future;
      var bEntered = false;
      final loadingB = b.serializeFetch(() async {
        bEntered = true;
        return (await b.read())!;
      });
      await queued.future;
      // User replacement commits while A's simulated network request is held.
      await credentials.writeSecret(id, 'fake-new');
      expect(bEntered, isFalse);
      expect(await a.isCurrent(original), isFalse);
      release.complete();
      final oldResult = await loadingA;
      final newRead = await loadingB;
      expect(oldResult.credentialVersion, same(original));
      expect(await a.isCurrent(oldResult.credentialVersion!), isFalse);
      expect(newRead.value, 'fake-new');
      expect(await b.isCurrent(newRead.version), isTrue);
    },
  );

  test(
    'reporting fetch ownership releases on errors and rejects detached completion',
    () async {
      const id = ProviderConnections.openAiPlatform;
      final credentials = reportingStore('reporting-a');
      await credentials.writeSecret(id, 'fake-current');
      final a = credentials.credentialAccess(id)!;
      final b = reportingStore('reporting-b').credentialAccess(id)!;
      await expectLater(
        a.serializeFetch<void>(
          () async => throw StateError('Sanitized failure.'),
        ),
        throwsStateError,
      );
      expect(await b.serializeFetch(() => b.read()), isNotNull);

      final entered = Completer<void>();
      final release = Completer<void>();
      final loading = a.serializeFetch(() async {
        await a.read();
        entered.complete();
        await release.future;
      });
      final rejected = expectLater(loading, throwsStateError);
      await entered.future;
      await bridge.invoke('reporting-a', 'detach', {});
      expect(await b.serializeFetch(() => b.read()), isNotNull);
      release.complete();
      await rejected;
      expect(await b.serializeFetch(() => b.read()), isNotNull);
    },
  );

  test(
    'installed legacy credential survives cancelled and superseded reconnect',
    () async {
      secure.values['wardpulse.cursor.plan.secret'] = 'fake-installed';
      final a = await store('ui').beginReconnect();
      final b = await store('second').beginReconnect();
      expect(await store('ui').completeReconnect('fake-delayed-A', a), isFalse);
      await store('second').cancelReconnect(b);
      final restored = (await store('cold').read())!;
      expect(restored.value, 'fake-installed');
      expect(restored.version.generation, b.generation);
      expect(restored.version.generation, isNot(a.generation));
      expect(secure.values.values, isNot(contains('fake-delayed-A')));
      final old = await store('old').beginReconnect();
      final newer = await store('new').beginReconnect();
      expect(
        await store('new').completeReconnect('fake-new-account', newer),
        isTrue,
      );
      expect(
        await store('old').completeReconnect('fake-late-account', old),
        isFalse,
      );
      await store('old').cancelReconnect(old);
      final current = (await store('cold').read())!;
      expect(current.value, 'fake-new-account');
      expect(current.version.generation, newer.generation);
      expect(await store('cold').isCurrent(restored.version), isFalse);
      expect(secure.values.values, isNot(contains('fake-late-account')));
    },
  );
  test(
    'cancelled reconnect preserves guarded backup through cold missing-copy recovery',
    () async {
      const legacy = 'wardpulse.cursor.plan.secret';
      secure.values[legacy] = 'fake-installed';
      final migrated = (await store('ui').read())!;
      final ticket = await store('ui').beginReconnect();
      await store('ui').cancelReconnect(ticket);
      secure.values.removeWhere(
        (key, _) => key.startsWith('wardpulse.connection.'),
      );
      await bridge.invoke('test', 'restart', {});
      final recovered = (await store('cold').read())!;
      expect(recovered.value, 'fake-installed');
      expect(recovered.version.generation, ticket.generation);
      expect(recovered.version.generation, isNot(migrated.version.generation));
      expect(secure.values[legacy], 'fake-installed');
    },
  );
  test(
    'cold migration backup repairs a missing copied slot without resurrecting deletion',
    () async {
      const legacy = 'wardpulse.cursor.plan.secret';
      secure.values[legacy] = 'fake-installed';
      final original = (await store('ui').read())!;
      secure.values.removeWhere(
        (key, _) => key.startsWith('wardpulse.connection.'),
      );
      await bridge.invoke('test', 'restart', {});
      final repaired = (await store('cold').read())!;
      expect(repaired.value, 'fake-installed');
      expect(repaired.version.generation, original.version.generation);
      expect(repaired.version.revision, isNot(original.version.revision));
      secure.failDeleteKey = legacy;
      await expectLater(store('cold').delete(), throwsStateError);
      expect(await store('new-engine').read(), isNull);
    },
  );
  test(
    'first cancelled login stays empty, while migration failures preserve legacy recovery',
    () async {
      final first = await store('ui').beginReconnect();
      await store('ui').cancelReconnect(first);
      expect(await store('cold').read(), isNull);
      await bridge.reset();
      secure.values['wardpulse.cursor.plan.secret'] = 'fake-installed';
      secure.failWrite = true;
      await expectLater(store('ui').read(), throwsStateError);
      secure.failWrite = false;
      await bridge.invoke('test', 'restart', {});
      expect((await store('cold').read())?.value, 'fake-installed');
    },
  );
  test(
    'failed barrier leaves secure values untouched; explicit retry recovers',
    () async {
      await store('ui').write('fake-current');
      final before = Map<String, String>.from(secure.values);
      final deleted = secure.deleted.length;
      await bridge.invoke('test', 'failCommit', {'value': true});
      var notifications = 0;
      await expectLater(
        store('ui').delete(onRetired: (_) => notifications++),
        throwsStateError,
      );
      expect(notifications, 0);
      expect(secure.values, before);
      expect(secure.deleted.length, deleted);
      await bridge.invoke('test', 'failCommit', {'value': false});
      await store('retry').write('fake-new');
      expect((await store('cold').read())?.value, 'fake-new');
    },
  );
  test(
    'failed legacy deletion is retried by a fresh store after tombstone',
    () async {
      const legacy = 'wardpulse.cursor.plan.secret';
      secure.values[legacy] = 'fake-installed';
      await store('ui').read();
      secure.failDeleteKey = legacy;
      await expectLater(store('ui').delete(), throwsStateError);
      expect(secure.values[legacy], 'fake-installed');
      secure.failDeleteKey = null;
      expect(await store('cold').read(), isNull);
      expect(secure.values[legacy], isNull);
    },
  );
  test(
    'secure write/delete ordering spans independent store instances',
    () async {
      await store('ui').write('fake-first');
      final entered = Completer<void>();
      final release = Completer<void>();
      secure.beforeWrite = (_) async {
        entered.complete();
        await release.future;
      };
      final replacement = store('ui').write('fake-replacement');
      await entered.future;
      final deletion = store('worker').delete();
      await Future<void>.delayed(Duration.zero);
      expect(secure.values.values, contains('fake-first'));
      release.complete();
      await replacement;
      await deletion;
      expect(await store('cold').read(), isNull);
      expect(secure.values.values, isNot(contains('fake-replacement')));
    },
  );
  test(
    'detached pending SDK write cannot clobber new reconnect and cleans after restart',
    () async {
      await store('ui').write('fake-first');
      final entered = Completer<void>();
      final release = Completer<void>();
      secure.beforeWrite = (_) async {
        entered.complete();
        await release.future;
      };
      final delayed = store('ui').write('fake-late');
      final failed = expectLater(delayed, throwsStateError);
      await entered.future;
      await bridge.invoke('ui', 'detach', {});
      secure.beforeWrite = null;
      await store('new').write('fake-current');
      release.complete();
      await failed;
      expect((await store('cold').read())?.value, 'fake-current');
      expect(secure.values.values, contains('fake-late'));
      await bridge.invoke('test', 'restart', {});
      expect((await store('cold2').read())?.value, 'fake-current');
      expect(secure.values.values, isNot(contains('fake-late')));
    },
  );
  test(
    'Claude pasted-token cleanup retries durably without rotating OAuth',
    () async {
      final account = SecureClaudeAccountStore(
        storage: secure,
        platform: bridge.platform('oauth'),
      );
      await account.write(
        ClaudeAccountSession(
          accessToken: 'fake-OAuth',
          refreshToken: 'fake-refresh',
          expiresAt: now.add(const Duration(hours: 1)),
          accountId: 'fake-account',
        ),
      );
      final before = (await account.readVersioned())!.version;
      const paste = 'wardpulse.anthropic.plan.secret';
      secure.values[paste] = 'fake-old-paste';
      secure.failDeleteKey = paste;
      final pasted = SecureProviderCredentialStore(
        storage: secure,
        platform: bridge.platform('paste'),
      );
      await expectLater(
        pasted.deleteLegacySecret(ProviderConnections.claudePlan),
        throwsStateError,
      );
      secure.failDeleteKey = null;
      final after =
          await SecureClaudeAccountStore(
            storage: secure,
            platform: bridge.platform('cold'),
          ).readVersioned();
      expect(after?.value.accessToken, 'fake-OAuth');
      expect(after?.version.values, before.values);
      expect(secure.values[paste], isNull);
    },
  );
  test(
    'OAuth refresh retires the migration backup for the old credential revision',
    () async {
      const legacy = 'wardpulse.claude.account-session';
      final old = ClaudeAccountSession(
        accessToken: 'fake-old',
        refreshToken: 'fake-old-refresh',
        expiresAt: now.add(const Duration(hours: 1)),
        accountId: 'fake-account',
      );
      secure.values[legacy] = jsonEncode(old.toJson());
      final account = SecureClaudeAccountStore(
        storage: secure,
        platform: bridge.platform('oauth'),
      );
      final migrated = (await account.readVersioned())!;
      final changed = await account.refresh(
        ClaudeAccountSession(
          accessToken: 'fake-new',
          refreshToken: 'fake-new-refresh',
          expiresAt: now.add(const Duration(hours: 2)),
          accountId: 'fake-account',
        ),
        migrated.version,
      );
      expect(changed?.generation, migrated.version.generation);
      expect(changed?.revision, isNot(migrated.version.revision));
      secure.failDeleteKey = legacy;
      secure.values.removeWhere(
        (key, _) => key.startsWith('wardpulse.connection.'),
      );
      expect(
        await SecureClaudeAccountStore(
          storage: secure,
          platform: bridge.platform('cold'),
        ).readVersioned(),
        isNull,
      );
      expect(secure.values[legacy], isNotNull);
    },
  );
  test(
    'real secure account operations carry scoped fetch proof; user delete does not',
    () async {
      final platform = _RecordingPlatform(bridge.platform('oauth'));
      final account = SecureClaudeAccountStore(
        storage: secure,
        platform: platform,
      );
      final initial = ClaudeAccountSession(
        accessToken: 'fake-old',
        refreshToken: 'fake-refresh',
        expiresAt: now.add(const Duration(hours: 1)),
        accountId: 'fake-account',
      );
      await account.write(initial);
      final refreshed = Completer<void>();
      final release = Completer<void>();
      final fetch = account.serializeFetch(() async {
        final old = (await account.readVersioned())!;
        await account.refresh(initial, old.version);
        refreshed.complete();
        await release.future;
      });
      final failed = expectLater(fetch, throwsStateError);
      await refreshed.future;
      final refreshArgs =
          platform.calls
              .lastWhere(
                (call) =>
                    call.method == 'acquire' &&
                    call.arguments['action'] == 'refresh',
              )
              .arguments;
      expect(refreshArgs['fetchTicket'], isA<String>());
      await account.delete();
      final deleteArgs =
          platform.calls
              .lastWhere(
                (call) =>
                    call.method == 'acquire' &&
                    call.arguments['action'] == 'delete',
              )
              .arguments;
      expect(deleteArgs.containsKey('fetchTicket'), isFalse);
      // A detached owner invalidates even an otherwise completed network scope.
      await bridge.invoke('oauth', 'detach', {});
      release.complete();
      await failed;
    },
  );

  test(
    'Claude expired refresh failure cannot delete a newer explicit login',
    () async {
      final entered = Completer<void>();
      final release = Completer<_Response>();
      var tokenRequests = 0;
      var usageRequests = 0;
      String? tokenBody;
      final a = _runtime('claude', secure, bridge.platform('A'), now, (
        uri,
        headers,
        body,
      ) async {
        if (!entered.isCompleted) entered.complete();
        if (uri.path.endsWith('/token')) {
          tokenRequests++;
          tokenBody = body;
          return release.future;
        }
        usageRequests++;
        return _usageResponse(uri);
      });
      await a.write('fake-old-account', 'old', expired: true);
      final loading = a.fetch();
      final failed = expectLater(
        loading,
        throwsA(
          isA<ClaudeAccountException>()
              .having(
                (error) => error.failure,
                'failure',
                ClaudeAccountFailure.cancelled,
              )
              .having((error) => error.details, 'details', isNull),
        ),
      );
      await entered.future;
      final b = _runtime('claude', secure, bridge.platform('B'), now, (
        uri,
        headers,
        body,
      ) async {
        fail('Unexpected request from the newer login');
      });
      late final CredentialVersion newerVersion;
      try {
        await b.write('fake-new-account', 'new');
        newerVersion = (await b.read())!.version;
      } finally {
        release.complete((status: 400, body: '{"error":"invalid_grant"}'));
        await failed;
      }

      expect(
        await NativeConnectionRejectionNoticeStore(
          platform: bridge.platform('notices'),
        ).read(),
        isEmpty,
      );
      expect(tokenRequests, 1);
      expect(usageRequests, 0);
      expect(Uri.splitQueryString(tokenBody!)['grant_type'], 'refresh_token');
      final retained = (await b.read())!;
      expect(retained.value, 'new');
      expect(retained.version.values, newerVersion.values);
    },
  );

  test(
    'failed Claude sign-in retains the session; only fresh authorization replaces it',
    () async {
      final tokenBodies = <String?>[];
      final tokens = jsonEncode({
        'access_token': 'fake-replacement',
        'refresh_token': 'fake-replacement-refresh',
        'expires_in': 3600,
      });
      final account = SecureClaudeAccountStore(
        storage: secure,
        platform: bridge.platform('ui'),
      );
      await account.write(
        ClaudeAccountSession(
          accessToken: 'fake-confirmed',
          refreshToken: 'fake-refresh',
          expiresAt: now.add(const Duration(hours: 1)),
          accountId: 'fake-account',
        ),
      );
      final service = MobileClaudeAccountService(
        store: account,
        client: ClaudeAccountClient(
          transport: _ClaudeTransport((uri, headers, body) async {
            tokenBodies.add(body);
            return (status: 200, body: tokens);
          }),
          clock: () => now,
          // Seeded: each attempt draws its own deterministic PKCE pair.
          random: Random(1),
        ),
      );

      final failed = await service.startLogin();
      await expectLater(
        failed.completeWithCode('CODE#'),
        throwsA(
          isA<ClaudeAccountException>().having(
            (error) => error.failure,
            'failure',
            ClaudeAccountFailure.invalidResponse,
          ),
        ),
      );
      expect(tokenBodies, isEmpty);
      final retained =
          await SecureClaudeAccountStore(
            storage: secure,
            platform: bridge.platform('cold'),
          ).read();
      expect(retained?.accessToken, 'fake-confirmed');
      // Even a matching code cannot revive the spent attempt or its ticket.
      await expectLater(
        failed.completeWithCode('fake-code#${failed.authorization.state}'),
        throwsA(
          isA<ClaudeAccountException>().having(
            (error) => error.failure,
            'failure',
            ClaudeAccountFailure.cancelled,
          ),
        ),
      );
      expect(tokenBodies, isEmpty);

      final fresh = await service.startLogin();
      expect(fresh.authorization.state, isNot(failed.authorization.state));
      await fresh.completeWithCode('fresh-code#${fresh.authorization.state}');
      final exchange = Uri.splitQueryString(tokenBodies.single!);
      expect(exchange['code'], 'fresh-code');
      expect(exchange['code_verifier'], fresh.authorization.codeVerifier);
      final replaced =
          await SecureClaudeAccountStore(
            storage: secure,
            platform: bridge.platform('cold'),
          ).read();
      expect(replaced?.accessToken, 'fake-replacement');
    },
  );

  test('typed plan retirement keeps the sibling storage outcome', () async {
    const planId = ProviderConnections.claudePlan;
    const siblingId = ProviderConnections.anthropicPlatform;
    final siblingStore = reportingStore('reporting');
    await siblingStore.writeSecret(siblingId, 'synthetic-key');
    final siblingVersion = (await siblingStore.readVersion(siblingId))!;
    final siblingCache = ConnectionSnapshotCache(
      connection: siblingId.storageKey,
      platform: bridge.platform('reporting'),
      readCredentialVersion: () => siblingStore.readVersion(siblingId),
    );
    expect(
      await siblingCache.store(
        _connectionSnapshot(siblingId.storageKey, 'claude', now),
        siblingVersion,
      ),
      isTrue,
    );
    final before = await siblingCache.capture();
    expect(before.record?.rowId, isA<String>());
    final sibling = MergingConnectionRepository(
      cache: siblingCache,
      connection: siblingId,
      credentialStore: siblingStore,
      fallback: const NoProvidersDashboardRepository(),
      loadCredentialReport:
          (_) async => fail('The reporting key is unreadable.'),
      normalizeReport: (report) => report,
      mapError: (_) => const DashboardLoadException(),
      logger: const NullProviderSyncLogger(),
    );
    const owner = 'retiring-plan';
    final platform = ObservingCachePlatform(bridge.platform(owner));
    final plan = _runtime('claude', secure, platform, now, (_, _, _) async {
      fail('The plan credential is unreadable.');
    }, fallback: sibling);
    await plan.write('synthetic-account', 'synthetic-token');
    final repository = plan.cachelessRepository();
    platform.beforeInvoke = (method, _) async {
      if (method == 'validFetch') await bridge.invoke(owner, 'detach', {});
    };
    final ownershipChecks = <Object?>[];
    platform.onComplete = (method, _, result) {
      if (method == 'validFetch') ownershipChecks.add(result);
    };

    secure.failRead = true;
    final captured = await CapturedDashboardLoad.capture(repository.load);
    secure.failRead = false;

    expect(ownershipChecks, [false]);
    final failure = captured.loadException!;
    expect(failure.issue, DashboardSyncIssue.claudeUnavailable);
    expect(failure.details, 'Claude plan · Secure storage unavailable');
    expect(failure.syncRejection, isNull);
    expect(failure.reportingOutcomes.map((outcome) => outcome.connection), [
      siblingId,
      planId,
    ]);
    for (final outcome in failure.reportingOutcomes) {
      expect(outcome.category, ReportingOutcomeCategory.localReadFailure);
      expect(outcome.source, ReportingOutcomeSource.local);
      expect(outcome.credentialVersion, isNull);
    }
    expect(failure.connectionVersions, isEmpty);
    expect(
      failure.snapshotOrdering.keys,
      unorderedEquals([planId.storageKey, siblingId.storageKey]),
    );
    expect(
      failure.snapshotOrdering.values.map((order) => order.selectionUnverified),
      everyElement(isTrue),
    );
    expect(await repository.isFailureCurrent(failure), isFalse);
    final after = await siblingCache.capture();
    expect(after.version?.values, before.version?.values);
    expect(after.observation, before.observation);
    expect(after.snapshot?.toJson(), before.snapshot?.toJson());
  });

  for (final family in ['claude', 'codex']) {
    _Runtime runtime(String owner, _ResponseHandler handler) =>
        _runtime(family, secure, bridge.platform(owner), now, handler);
    test('$family cacheless plan observes actual managed absence', () async {
      final id =
          family == 'codex'
              ? ProviderConnections.codexPlan.storageKey
              : ProviderConnections.claudePlan.storageKey;
      final observed = ObservingCachePlatform(bridge.platform('cacheless'));
      final session = _runtime(family, secure, observed, now, (_, _, _) async {
        fail(
          'An absent or unreadable session must never make a provider request.',
        );
      });
      final repository = session.cachelessRepository();

      await session.disconnect();
      final missing = await repository.load();
      expect(missing.accounts, isEmpty);
      expect(missing.connectionVersions.keys, [id]);
      expect(
        CredentialVersion(missing.connectionVersions[id]!).isAbsent,
        isTrue,
      );
      expect(await repository.isSnapshotCurrent(missing), isTrue);

      observed.beforeInvoke = (method, _) {
        if (method == 'validAll') {
          throw StateError('Synthetic lifecycle validation failure.');
        }
      };
      final rejected = await CapturedDashboardLoad.capture(repository.load);
      observed.beforeInvoke = null;
      final rejectedAbsence = rejected.loadException!;
      expect(rejectedAbsence.connectionVersions, missing.connectionVersions);
      expect(rejectedAbsence.snapshotOrdering[id]?.selectionUnverified, isTrue);
      expect(await repository.isFailureCurrent(rejectedAbsence), isFalse);
      expect(await repository.isSnapshotCurrent(missing), isTrue);

      await session.write('synthetic-account', 'synthetic-token');
      expect(await repository.isSnapshotCurrent(missing), isFalse);
      final ownershipChecks = <Object?>[];
      observed.onComplete = (method, _, result) {
        if (method == 'validFetch') ownershipChecks.add(result);
      };
      secure.failRead = true;
      final unreadable = await CapturedDashboardLoad.capture(repository.load);
      secure.failRead = false;
      expect(ownershipChecks, [true]);
      final storageFailure = unreadable.loadException;
      expect(
        storageFailure?.issue,
        family == 'codex'
            ? DashboardSyncIssue.codexUnavailable
            : DashboardSyncIssue.claudeUnavailable,
      );
      expect(storageFailure!.connectionVersions, isEmpty);
      expect(storageFailure.snapshotOrdering[id]?.selectionUnverified, isTrue);
      expect(await repository.isFailureCurrent(storageFailure), isFalse);

      final platform = bridge.platform('reconnect');
      if (family == 'codex') {
        await SecureCodexAccountStore(
          storage: secure,
          platform: platform,
        ).beginReconnect();
      } else {
        await SecureClaudeAccountStore(
          storage: secure,
          platform: platform,
        ).beginReconnect();
      }
      final pending = await CapturedDashboardLoad.capture(repository.load);
      final failure = pending.loadException;
      expect(failure, isNotNull);
      expect(failure!.connectionVersions, isEmpty);
      expect(failure.snapshotOrdering[id]?.selectionUnverified, isTrue);
      expect(await repository.isFailureCurrent(failure), isFalse);
    });
    test(
      '$family manual first failure survives later cache adoption and automatic denial',
      () async {
        final id = family == 'codex' ? 'openai.plan' : 'anthropic.plan';
        var limited = true, requests = 0;
        Future<_Response> response(
          Uri uri,
          Map<String, String> headers,
          String? body,
        ) async {
          requests++;
          return limited ? (status: 429, body: '{}') : _usageResponse(uri);
        }

        final manual = runtime('manual', response);
        await manual.write('synthetic-account', 'synthetic-token');
        final version = (await manual.read())!.version;
        final empty = DashboardSnapshot.empty(generatedAt: now);
        final normalized = DashboardSnapshot.fromJson({
          ...empty.toJson(),
          'accounts': [
            {
              'accountId': 'synthetic-account',
              'provider': family,
              'connection': id,
              'status': 'ok',
              'today': empty.todayTotal.toJson(),
              'week': empty.weekTotal.toJson(),
              'month': empty.monthTotal.toJson(),
              'credits': <Object>[],
              'allowances': <Object>[],
              'buckets': <Object>[],
              'modelBreakdown': <Object>[],
              'lastSuccessfulSyncAt': now.toIso8601String(),
            },
          ],
        });
        ConnectionSnapshotCache cache(String owner) => ConnectionSnapshotCache(
          connection: id,
          platform: bridge.platform(owner),
          readCredentialVersion:
              () async => (await runtime(owner, response).read())?.version,
        );
        DashboardRepository repository(String owner, _Runtime session) =>
            family == 'codex'
                ? codexDashboardRepository(
                  accountService: const EmptyCodexAccountService(),
                  fallback: const NoProvidersDashboardRepository(),
                  cache: cache(owner),
                  loadReport: session.fetch,
                  normalizeReport: (_) => normalized.toJsonString(),
                  logger: const NullProviderSyncLogger(),
                )
                : claudeDashboardRepository(
                  accountService: const EmptyClaudeAccountService(),
                  fallback: const NoProvidersDashboardRepository(),
                  cache: cache(owner),
                  loadReport: session.fetch,
                  normalizeReport: (_) => normalized.toJsonString(),
                  logger: const NullProviderSyncLogger(),
                );
        final foreground = repository('manual', manual);
        final failed = await CapturedDashboardLoad.capture(foreground.load);
        expect(
          () => failed.value,
          throwsA(
            isA<DashboardLoadException>().having(
              (error) => error.issue,
              'issue',
              DashboardSyncIssue.rateLimited,
            ),
          ),
        );
        expect(
          failed.reportingOutcomes.single.credentialVersion!.values,
          version.values,
        );
        expect((await cache('manual').capture()).snapshot, isNull);
        limited = false;
        AutomaticPollContext periodic() => AutomaticPollContext(
          readInterval: () async => const Duration(minutes: 5),
        );
        final worker = repository('headless', runtime('headless', response));
        await periodic().run(worker.load);
        final before = requests;
        final poll = periodic();
        final retained = await poll.run(foreground.load);
        expect(requests, before);
        expect(poll.whollySkipped, isTrue);
        expect(retained.syncIssue, DashboardSyncIssue.rateLimited);
        expect(retained.generatedAt, now);
        expect(retained.accounts.single.status, ProviderStatus.stale);
        expect(retained.accounts.single.lastSuccessfulSyncAt, now);
        expect(
          retained.reportingOutcomes.single.source,
          ReportingOutcomeSource.cache,
        );
        expect(
          retained.reportingOutcomes.single.credentialVersion!.values,
          version.values,
        );
      },
    );
    test(
      '$family recreated automatic clients skip before expired-token refresh; manual bypasses',
      () async {
        var calls = 0;
        Future<_Response> response(
          Uri uri,
          Map<String, String> headers,
          String? body,
        ) async {
          calls++;
          return _usageResponse(uri);
        }

        final foreground = runtime('foreground', response);
        await foreground.write('synthetic-account', 'synthetic-token');
        final id = family == 'codex' ? 'openai.plan' : 'anthropic.plan';
        DateTime anchor(int milliseconds) =>
            DateTime.fromMillisecondsSinceEpoch(milliseconds, isUtc: true);
        AutomaticPollContext periodic() => AutomaticPollContext(
          readInterval: () async => const Duration(minutes: 60),
        );
        final first = periodic();
        await first.run(foreground.fetch);
        expect(first.automaticAt, {id: anchor(0)});
        final before = calls;
        await bridge.invoke('test', 'setClock', {'value': 1000});
        final expired = _runtime(
          family,
          secure,
          bridge.platform('headless'),
          now.add(const Duration(days: 2)),
          response,
        );
        final denied = periodic();
        await expectLater(
          denied.run(expired.fetch),
          throwsA(isA<AutomaticPollSkipped>()),
        );
        // A denial reports the durable start rather than its own time.
        expect(denied.automaticAt, {id: anchor(0)});
        expect(calls, before);
        await foreground.fetch();
        expect(calls, greaterThan(before));
        await bridge.invoke('test', 'setClock', {'value': 300000});
        final reset = AutomaticPollContext(
          origin: AutomaticPollOrigin.resetWake,
          readInterval: () async => const Duration(minutes: 60),
        );
        await reset.run(foreground.fetch);
        expect(reset.automaticAt, {id: anchor(300000)});
        final afterReset = calls;
        await bridge.invoke('test', 'setClock', {'value': 600000});
        final later = periodic();
        await expectLater(
          later.run(foreground.fetch),
          throwsA(isA<AutomaticPollSkipped>()),
        );
        expect(later.automaticAt, {id: anchor(300000)});
        expect(calls, afterReset);
      },
    );
    test(
      '$family owned rejection persists after credential-null refresh and restart',
      () async {
        final a = runtime(
          'auth',
          (uri, headers, body) async => (status: 401, body: '{}'),
        );
        await a.write('synthetic-account', 'synthetic-token');
        await expectLater(a.fetch(), throwsA(anything));
        expect(await a.read(), isNull);
        final notices = NativeConnectionRejectionNoticeStore(
          platform: bridge.platform('notices'),
        );
        final event = (await notices.read()).single;
        expect(
          event.connection,
          family == 'claude'
              ? ProviderConnections.claudePlan
              : ProviderConnections.codexPlan,
        );
        expect(event.dismissed, isFalse);
        expect(await a.fetch(), isNull);
        await bridge.invoke('test', 'restart', {});
        final cold = runtime(
          'cold',
          (uri, headers, body) async => fail('No saved credential may fetch'),
        );
        expect(await cold.fetch(), isNull);
        expect((await notices.read()).single.eventId, event.eventId);
        await cold.write('synthetic-account', 'synthetic-token');
        final disconnected = runtime(
          'disconnect',
          (uri, headers, body) async => _usageResponse(uri),
        );
        await disconnected.disconnect();
        expect((await notices.read()).single.eventId, event.eventId);
      },
    );
    test(
      '$family permission failure retains credential without auth evidence',
      () async {
        final a = runtime(
          'permission',
          (uri, headers, body) async => (status: 403, body: '{}'),
        );
        await a.write('synthetic-account', 'synthetic-token');
        await expectLater(a.fetch(), throwsA(anything));
        expect(await a.read(), isNotNull);
        expect(
          await NativeConnectionRejectionNoticeStore(
            platform: bridge.platform('notices'),
          ).read(),
          isEmpty,
        );
      },
    );
    test(
      '$family cross-engine fetch exclusion rereads refreshed session',
      () async {
        final entered = Completer<void>();
        final release = Completer<_Response>();
        var bTokenRequests = 0;
        final a = runtime('A', (uri, headers, body) async {
          if (uri.path.endsWith('/token')) {
            entered.complete();
            return release.future;
          }
          return _usageResponse(uri);
        });
        await a.write('fake-account', 'old', expired: true);
        final before = (await a.read())!.version;
        final loadingA = a.fetch();
        await entered.future;
        final b = runtime('B', (uri, headers, body) async {
          if (uri.path.endsWith('/token')) {
            bTokenRequests++;
            return (status: 401, body: '{}');
          }
          expect(headers['Authorization'], contains('new'));
          return _usageResponse(uri);
        });
        final loadingB = b.fetch();
        await Future<void>.delayed(Duration.zero);
        expect(bTokenRequests, 0);
        release.complete((
          status: 200,
          body: jsonEncode({
            'access_token':
                family == 'codex'
                    ? _jwt(now.add(const Duration(days: 1)), 'new')
                    : 'new',
            'refresh_token': 'fake-new-refresh',
            'expires_in': 3600,
          }),
        ));
        expect(await loadingA, isNotNull);
        expect(await loadingB, isNotNull);
        expect(bTokenRequests, 0);
        final after = (await b.read())!;
        expect(after.version.generation, before.generation);
        expect(after.version.revision, isNot(before.revision));
      },
    );
    test(
      '$family stale auth failure cannot delete a newer explicit login',
      () async {
        final entered = Completer<void>();
        final release = Completer<_Response>();
        final a = runtime('A', (uri, headers, body) async {
          if (uri.path.endsWith('/token')) return (status: 401, body: '{}');
          if (uri.path.endsWith('/usage')) {
            entered.complete();
            return release.future;
          }
          return _usageResponse(uri);
        });
        await a.write('fake-old-account', 'old');
        final loading = a.fetch();
        final failed = expectLater(loading, throwsA(anything));
        await entered.future;
        final b = runtime(
          'B',
          (uri, headers, body) async => _usageResponse(uri),
        );
        await b.write('fake-new-account', 'new');
        release.complete((status: 401, body: '{}'));
        await failed;
        expect((await b.read())?.value, contains('new'));
      },
    );
    test(
      '$family disconnect commits before the held network returns',
      () async {
        final entered = Completer<void>();
        final release = Completer<_Response>();
        final a = runtime('A', (uri, headers, body) async {
          if (uri.path.endsWith('/usage')) {
            entered.complete();
            return release.future;
          }
          return _usageResponse(uri);
        });
        await a.write('fake-account', 'old');
        final loading = a.fetch();
        final failed = expectLater(loading, throwsA(anything));
        await entered.future;
        await a.disconnect();
        expect(await a.read(), isNull);
        release.complete(
          _usageResponse(Uri.parse('https://invalid.test/usage')),
        );
        await failed;
        expect(
          await runtime(
            'cold',
            (uri, headers, body) async => _usageResponse(uri),
          ).read(),
          isNull,
        );
      },
    );
  }
}

typedef _Response = ({int status, String body});

DashboardSnapshot _connectionSnapshot(
  String connection,
  String provider,
  DateTime now,
) {
  final empty = DashboardSnapshot.empty(generatedAt: now);
  return DashboardSnapshot.fromJson({
    ...empty.toJson(),
    'accounts': [
      {
        'accountId': 'synthetic-account',
        'provider': provider,
        'connection': connection,
        'status': 'ok',
        'today': empty.todayTotal.toJson(),
        'week': empty.weekTotal.toJson(),
        'month': empty.monthTotal.toJson(),
        'credits': <Object>[],
        'allowances': <Object>[],
        'buckets': <Object>[],
        'modelBreakdown': <Object>[],
        'lastSuccessfulSyncAt': now.toIso8601String(),
      },
    ],
  });
}

typedef _ResponseHandler =
    Future<_Response> Function(Uri, Map<String, String>, String?);

final class _Runtime {
  const _Runtime({
    required this.write,
    required this.read,
    required this.fetch,
    required this.disconnect,
    required this.cachelessRepository,
  });
  final Future<void> Function(String account, String token, {bool expired})
  write;
  final Future<VersionedCredential<String>?> Function() read;
  final Future<String?> Function() fetch;
  final Future<void> Function() disconnect;
  final DashboardRepository Function() cachelessRepository;
}

_Runtime _runtime(
  String family,
  FakeSecureStorage secure,
  ConnectionCachePlatform platform,
  DateTime now,
  _ResponseHandler handler, {
  DashboardRepository fallback = const NoProvidersDashboardRepository(),
}) {
  if (family == 'claude') {
    final store = SecureClaudeAccountStore(storage: secure, platform: platform);
    final service = MobileClaudeAccountService(
      store: store,
      client: ClaudeAccountClient(
        transport: _ClaudeTransport(handler),
        clock: () => now,
      ),
    );
    return _Runtime(
      write:
          (account, token, {expired = false}) => store.write(
            ClaudeAccountSession(
              accessToken: token,
              refreshToken: 'fake-refresh',
              expiresAt: now.add(
                expired ? const Duration(minutes: 1) : const Duration(hours: 1),
              ),
              accountId: account,
            ),
          ),
      read: () async {
        final value = await store.readVersioned();
        return value == null
            ? null
            : VersionedCredential(value.value.accessToken, value.version);
      },
      fetch: service.fetchReport,
      disconnect: service.disconnect,
      cachelessRepository:
          () => claudeDashboardRepository(
            accountService: service,
            fallback: fallback,
            logger: const NullProviderSyncLogger(),
          ),
    );
  }
  final store = SecureCodexAccountStore(storage: secure, platform: platform);
  final service = MobileCodexAccountService(
    store: store,
    client: CodexAccountClient(
      transport: _CodexTransport(handler),
      clock: () => now,
    ),
  );
  return _Runtime(
    write:
        (account, token, {expired = false}) => store.write(
          CodexAccountSession(
            accessToken: _jwt(
              now.add(
                expired ? const Duration(days: -1) : const Duration(days: 1),
              ),
              token,
            ),
            refreshToken: 'fake-refresh',
            accountId: account,
            refreshedAt: now,
          ),
        ),
    read: () async {
      final value = await store.readVersioned();
      return value == null
          ? null
          : VersionedCredential(value.value.accessToken, value.version);
    },
    fetch: service.fetchReport,
    disconnect: service.disconnect,
    cachelessRepository:
        () => codexDashboardRepository(
          accountService: service,
          fallback: fallback,
          logger: const NullProviderSyncLogger(),
        ),
  );
}

String _jwt(DateTime expires, String label) {
  String encode(Object json) =>
      base64UrlEncode(utf8.encode(jsonEncode(json))).replaceAll('=', '');
  return '${encode({'alg': 'none'})}.${encode({'exp': expires.millisecondsSinceEpoch ~/ 1000})}.$label';
}

_Response _usageResponse(Uri uri) => (
  status: 200,
  body: jsonEncode(
    uri.path.endsWith('/profiles/me')
        ? {
          'stats': {'daily_usage_buckets': <Object>[]},
        }
        : uri.path.contains('/wham/')
        ? {
          'rate_limit': null,
          'credits': {'has_credits': false, 'unlimited': false, 'balance': '0'},
        }
        : <String, Object?>{},
  ),
);

final class _ClaudeTransport implements ClaudeHttpTransport {
  const _ClaudeTransport(this.handler);
  final _ResponseHandler handler;
  @override
  Future<ClaudeHttpResponse> send(
    String method,
    Uri uri, {
    required Map<String, String> headers,
    String? body,
    Duration? timeout,
  }) async {
    final result = await handler(uri, headers, body);
    return ClaudeHttpResponse(statusCode: result.status, body: result.body);
  }
}

final class _CodexTransport implements CodexHttpTransport {
  const _CodexTransport(this.handler);
  final _ResponseHandler handler;
  @override
  Future<CodexHttpResponse> send(
    String method,
    Uri uri, {
    required Map<String, String> headers,
    String? body,
  }) async {
    final result = await handler(uri, headers, body);
    return CodexHttpResponse(statusCode: result.status, body: result.body);
  }
}

final class _RecordingPlatform implements ConnectionCachePlatform {
  _RecordingPlatform(this.delegate);
  final ConnectionCachePlatform delegate;
  final calls = <({String method, Map<String, Object?> arguments})>[];
  FutureOr<void> Function(String, Map<String, Object?>)? onInvoke;
  @override
  Future<Object?> invoke(String method, Map<String, Object?> arguments) async {
    calls.add((method: method, arguments: Map.of(arguments)));
    await onInvoke?.call(method, arguments);
    return delegate.invoke(method, arguments);
  }
}
