import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ward_pulse_phone/app/ward_pulse_app.dart';
import 'package:ward_pulse_phone/dashboard/codex_dashboard_repository.dart';
import 'package:ward_pulse_phone/dashboard/connection_snapshot_cache.dart';
import 'package:ward_pulse_phone/dashboard/dashboard_models.dart';
import 'package:ward_pulse_phone/dashboard/dashboard_repository.dart';
import 'package:ward_pulse_phone/dashboard/plan_recoveries.dart';
import 'package:ward_pulse_phone/providers/codex_account_service.dart';
import 'package:ward_pulse_phone/providers/codex_account_store.dart';
import 'package:ward_pulse_phone/providers/connection_lifecycle.dart';
import 'package:ward_pulse_phone/settings/alert_threshold_preferences.dart';
import 'package:ward_pulse_phone/settings/notification_permission_preferences.dart';
import 'package:ward_pulse_phone/sync/codex_account_client.dart';
import 'package:ward_pulse_phone/sync/notification_coordinator.dart';
import 'package:ward_pulse_phone/sync/provider_sync_logger.dart';
import 'package:ward_pulse_phone/sync/recovery_notifications.dart';
import 'package:ward_pulse_phone/sync/recovery_watchlist.dart';

void main() {
  setUp(AndroidFlutterLocalNotificationsPlugin.registerWith);

  testWidgets(
    'foreground recovery retains newly necessary capacity across disk reload',
    (tester) async {
      final previous = FlutterLocalNotificationsPlatform.instance;
      AndroidFlutterLocalNotificationsPlugin.registerWith();
      const channel = MethodChannel(
        'dexterous.com/flutter/local_notifications',
      );
      final messenger = tester.binding.defaultBinaryMessenger;
      addTearDown(() {
        try {
          messenger.setMockMethodCallHandler(channel, null);
        } finally {
          FlutterLocalNotificationsPlatform.instance = previous;
        }
      });
      final posts = <Map<dynamic, dynamic>>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'show') posts.add(Map.of(call.arguments as Map));
        return true;
      });

      Future<T> runAsync<T>(Future<T> Function() action) async {
        late T value;
        Object? error;
        StackTrace? stackTrace;
        final completed = await tester.runAsync(() async {
          try {
            value = await action();
            return true;
          } catch (caught, stack) {
            error = caught;
            stackTrace = stack;
            return false;
          }
        });
        if (error != null) {
          Error.throwWithStackTrace(error!, stackTrace!);
        }
        if (completed != true) {
          throw tester.takeException() ??
              StateError('Asynchronous action did not complete.');
        }
        return value;
      }

      Directory? directory;
      Object? failure;
      StackTrace? failureStack;
      try {
        await runAsync(() async {
          directory = await Directory.systemTemp.createTemp(
            'wardpulse-recovery-',
          );
        });
        var storage = _DiskStorage(directory!);
        var store = SecureRecoveryWatchlistStore(storage: storage);
        const connection = 'openai.plan';
        final version = CredentialVersion({
          'generation': '1',
          'revision': '1',
          'epoch': '1',
          'identity': List.filled(64, 'a').join(),
          'committedConnection': 'synthetic-activation',
        });
        final owner = HistoryOwner.fromVersion(connection, version)!;
        final cache = ConnectionSnapshotCache(
          connection: connection,
          readCredentialVersion: () async => version,
        );
        final at = DateTime.utc(2026, 7, 19, 12);
        final transport = _UsageTransport();
        final client = CodexAccountClient(
          transport: transport,
          clock: () => at,
        );
        final session = CodexAccountSession(
          accessToken: 'synthetic-access',
          refreshToken: 'synthetic-refresh',
          accountId: 'synthetic-account',
          refreshedAt: at,
        );
        final repository = _StampedRepository(
          codexDashboardRepository(
            accountService: const EmptyCodexAccountService(),
            fallback: const NoProvidersDashboardRepository(),
            logger: const NullProviderSyncLogger(),
            loadReport:
                () async => (await client.fetchReport(session)).reportJson,
          ),
          cache,
          version,
        );
        await runAsync(
          () => SecureAlertThresholdPreferenceStore(storage: storage).write(
            const AlertThresholdPreferences(
              connections: {
                connection: ConnectionAlertThresholds(
                  plan: AlertPercentThreshold(at: 100),
                ),
              },
            ),
          ),
        );
        Widget app() {
          final coordinator = PhoneNotificationCoordinator(
            attempts: SecureNotificationPermissionAttemptStore(
              storage: storage,
            ),
          );
          return WardPulseApp(
            repository: repository,
            alertThresholdStore: SecureAlertThresholdPreferenceStore(
              storage: storage,
            ),
            recoveryWatchlistStore: store,
            recoveryNotifier: LocalRecoveryNotifier(coordinator: coordinator),
            notificationCoordinator: coordinator,
          );
        }

        Future<String> observe(Future<void> Function() action) async {
          final value = await runAsync(() async {
            final written = storage.arm();
            await action();
            final delivery = written.timeout(const Duration(seconds: 10));
            late String value;
            var completed = false;
            Object? error;
            StackTrace? stackTrace;
            unawaited(
              delivery.then<void>(
                (result) {
                  value = result;
                  completed = true;
                },
                onError: (Object caught, StackTrace stack) {
                  error = caught;
                  stackTrace = stack;
                  completed = true;
                },
              ),
            );
            while (!completed) {
              await tester.pump();
              if (!completed) await Future<void>.delayed(Duration.zero);
            }
            if (error != null) {
              Error.throwWithStackTrace(error!, stackTrace!);
            }
            return value;
          });
          await tester.pumpAndSettle(
            const Duration(milliseconds: 100),
            EnginePhase.sendSemanticsUpdate,
            const Duration(seconds: 5),
          );
          return value;
        }

        final initial = await observe(() => tester.pumpWidget(app()));
        transport.root['primary_window']['used_percent'] = 10;
        transport.root['secondary_window'] = {
          'used_percent': 100,
          'limit_window_seconds': 604800,
          'reset_at': 1784980800,
        };
        final blocked = await observe(
          () => tester.tap(find.byTooltip('Refresh')),
        );
        final earlyPosts = List<Map<dynamic, dynamic>>.of(posts);
        final loadedLibraries =
            File('/proc/self/maps')
                .readAsLinesSync()
                .where((line) => line.contains('/libward_pulse_ffi.so'))
                .map((line) => line.substring(line.indexOf('/')))
                .toSet()
                .toList();
        // Retain observations before any semantic assertion, including under OLD.
        await runAsync(() async {
          stdout.writeln(
            'PLAN_RECOVERY_BLOCKED ${jsonEncode({'pid': pid, 'loadedLibraries': loadedLibraries, 'initial': jsonDecode(initial), 'blocked': jsonDecode(blocked), 'pluginShows': earlyPosts})}',
          );
          await stdout.flush();
        });

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle(
          const Duration(milliseconds: 100),
          EnginePhase.sendSemanticsUpdate,
          const Duration(seconds: 5),
        );
        storage = _DiskStorage(directory!);
        store = SecureRecoveryWatchlistStore(storage: storage);
        final reloaded = await runAsync(
          () => store.readPendingOwners({owner}),
        );
        transport.root['secondary_window']['used_percent'] = 20;
        final recovered = await observe(() => tester.pumpWidget(app()));
        await runAsync(() async {
          stdout.writeln(
            'PLAN_RECOVERY_RELOADED ${jsonEncode({
              'pending': [for (final entry in reloaded.pending) entry.toJson()],
              'final': jsonDecode(recovered),
              'pluginShows': posts,
            })}',
          );
          await stdout.flush();
        });

        expect(
          loadedLibraries,
          isNotEmpty,
          reason: 'HOST library loading evidence',
        );
        expect(
          earlyPosts,
          isEmpty,
          reason:
              'necessary weekly capacity blocks premature normal notification',
        );
        final firstPending = decodePendingRecoveries(initial).single;
        expect(firstPending.requirements!.complete, isFalse);
        expect(firstPending.requirements!.allowanceIds, ['codex-primary']);
        final retained = reloaded.pending.singleWhere(
          (entry) => entry.key.allowanceId == 'codex-primary',
        );
        expect(retained.key, firstPending.key);
        expect(retained.requirements!.complete, isTrue);
        expect(retained.requirements!.allowanceIds, [
          'codex-primary',
          'codex-secondary',
        ]);
        expect(posts, hasLength(2));
        expect(posts.map((post) => post['id']).toSet(), hasLength(2));
        expect(
          posts.map((post) => post['id']),
          contains(
            recoveryNotificationId((
              accountId: retained.key.accountId,
              historyOwner: owner,
              provider: 'codex',
              allowanceId: 'codex-primary',
              label: '5-hour session',
              resetsAt: null,
            )),
          ),
        );
        for (final post in posts) {
          expect(post['body'], 'Usable again.');
          expect(
            (post['platformSpecifics'] as Map)['channelId'],
            'wardpulse.plan_recovery',
          );
        }
        expect(decodePendingRecoveries(recovered), isEmpty);
      } catch (error, stack) {
        failure = error;
        failureStack = stack;
      } finally {
        try {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pumpAndSettle(
            const Duration(milliseconds: 100),
            EnginePhase.sendSemanticsUpdate,
            const Duration(seconds: 5),
          );
        } catch (error, stack) {
          failure ??= error;
          failureStack ??= stack;
        }
        try {
          if (directory != null) {
            await runAsync(() => directory!.delete(recursive: true));
          }
        } catch (error, stack) {
          failure ??= error;
          failureStack ??= stack;
        }
      }
      if (failure != null) {
        Error.throwWithStackTrace(failure, failureStack!);
      }
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
    timeout: const Timeout(Duration(seconds: 60)),
  );
}

final class _StampedRepository extends DashboardRepository {
  _StampedRepository(this.delegate, this.cache, this.version);
  final DashboardRepository delegate;
  final ConnectionSnapshotCache cache;
  final CredentialVersion version;
  @override
  Future<DashboardSnapshot> load() async =>
      cache.stamp(await delegate.load(), version);
}

final class _UsageTransport implements CodexHttpTransport {
  final root = <String, dynamic>{
    'allowed': true,
    'limit_reached': false,
    'primary_window': {
      'used_percent': 100,
      'limit_window_seconds': 18000,
      'reset_at': 1784480400,
    },
    // Omitted weekly applicability is incomplete; the next report establishes it.
  };
  @override
  Future<CodexHttpResponse> send(
    String method,
    Uri uri, {
    required Map<String, String> headers,
    String? body,
  }) async {
    final response = switch (uri.path) {
      '/backend-api/wham/usage' => {'rate_limit': root},
      '/backend-api/wham/profiles/me' => {
        'stats': {'daily_usage_buckets': []},
      },
      _ => throw StateError('Unexpected synthetic request.'),
    };
    return CodexHttpResponse(statusCode: 200, body: jsonEncode(response));
  }
}

/// Test-only transport: production codecs/store read actual files on each call.
final class _DiskStorage extends FlutterSecureStorage {
  _DiskStorage(this.directory);
  final Directory directory;
  Completer<String>? _written;
  Future<String> arm() => (_written = Completer<String>()).future;
  File _file(String key) =>
      File('${directory.path}/${Uri.encodeComponent(key)}');
  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    final file = _file(key);
    return file.existsSync() ? file.readAsStringSync() : null;
  }

  @override
  Future<Map<String, String>> readAll({
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => {
    for (final file in directory.listSync().whereType<File>())
      Uri.decodeComponent(file.uri.pathSegments.last): file.readAsStringSync(),
  };
  @override
  Future<void> write({
    required String key,
    required String? value,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    final file = _file(key);
    if (value == null) {
      if (file.existsSync()) file.deleteSync();
    } else {
      file.writeAsStringSync(value, flush: true);
    }
    if (key.startsWith('wardpulse.recovery.exhaustedWindows') &&
        _written?.isCompleted == false) {
      _written!.complete(value!);
    }
  }
}
