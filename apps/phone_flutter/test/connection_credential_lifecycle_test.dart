import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ward_pulse_phone/providers/connection_lifecycle.dart';
import 'package:ward_pulse_phone/providers/claude_account_service.dart';
import 'package:ward_pulse_phone/providers/claude_account_store.dart';
import 'package:ward_pulse_phone/providers/codex_account_service.dart';
import 'package:ward_pulse_phone/providers/codex_account_store.dart';
import 'package:ward_pulse_phone/providers/provider_connection.dart';
import 'package:ward_pulse_phone/providers/provider_credential_store.dart';
import 'package:ward_pulse_phone/sync/claude_account_client.dart';
import 'package:ward_pulse_phone/sync/codex_account_client.dart';

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
      await expectLater(store('ui').delete(), throwsStateError);
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

  for (final family in ['claude', 'codex']) {
    _Runtime runtime(String owner, _ResponseHandler handler) =>
        _runtime(family, secure, bridge.platform(owner), now, handler);
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
typedef _ResponseHandler =
    Future<_Response> Function(Uri, Map<String, String>, String?);

final class _Runtime {
  const _Runtime({
    required this.write,
    required this.read,
    required this.fetch,
    required this.disconnect,
  });
  final Future<void> Function(String account, String token, {bool expired})
  write;
  final Future<VersionedCredential<String>?> Function() read;
  final Future<String?> Function() fetch;
  final Future<void> Function() disconnect;
}

_Runtime _runtime(
  String family,
  FakeSecureStorage secure,
  ConnectionCachePlatform platform,
  DateTime now,
  _ResponseHandler handler,
) {
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
  @override
  Future<Object?> invoke(String method, Map<String, Object?> arguments) {
    calls.add((method: method, arguments: Map.of(arguments)));
    return delegate.invoke(method, arguments);
  }
}
