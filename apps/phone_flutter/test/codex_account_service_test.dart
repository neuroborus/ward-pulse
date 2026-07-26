import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ward_pulse_phone/providers/codex_account_service.dart';
import 'package:ward_pulse_phone/providers/codex_account_store.dart';
import 'package:ward_pulse_phone/sync/codex_account_client.dart';

void main() {
  final now = DateTime.utc(2026, 7, 19);

  test('persists a rotated session before loading the report', () async {
    final store = _MemoryStore(_expiredSession(now));
    final transport = _QueueTransport([
      _jsonResponse({
        'access_token': _jwt(expiresAt: DateTime.utc(2026, 8)),
        'refresh_token': 'rotated-refresh-token',
      }),
      const CodexHttpResponse(statusCode: 500, body: '{}'),
      _jsonResponse({
        'stats': {'daily_usage_buckets': <Object>[]},
      }),
    ]);
    final service = MobileCodexAccountService(
      store: store,
      client: CodexAccountClient(transport: transport, clock: () => now),
    );

    await expectLater(
      service.fetchReport(),
      throwsA(isA<CodexAccountException>()),
    );

    expect(store.value?.refreshToken, 'rotated-refresh-token');
  });

  test('serializes concurrent refreshes', () async {
    final store = _MemoryStore(_expiredSession(now));
    final transport = _QueueTransport([
      _jsonResponse({
        'access_token': _jwt(expiresAt: DateTime.utc(2026, 8)),
        'refresh_token': 'rotated-refresh-token',
      }),
      _limitsResponse(),
      _activityResponse(),
      _limitsResponse(),
      _activityResponse(),
    ]);
    final service = MobileCodexAccountService(
      store: store,
      client: CodexAccountClient(transport: transport, clock: () => now),
    );

    final reports = await Future.wait([
      service.fetchReport(),
      service.fetchReport(),
    ]);

    expect(reports, everyElement(isNotNull));
    expect(
      transport.requests.where((uri) => uri.path == '/oauth/token'),
      hasLength(1),
    );
  });

  test('keeps the session after a permission failure', () async {
    final session = _activeSession(now);
    final store = _MemoryStore(session);
    final service = MobileCodexAccountService(
      store: store,
      client: CodexAccountClient(
        transport: _QueueTransport([
          const CodexHttpResponse(statusCode: 403, body: '{}'),
          _activityResponse(),
        ]),
        clock: () => now,
      ),
    );

    await expectLater(
      service.fetchReport(),
      throwsA(
        isA<CodexAccountException>().having(
          (error) => error.failure,
          'failure',
          CodexAccountFailure.permissionDenied,
        ),
      ),
    );

    expect(store.value, same(session));
  });

  test('normalizes secure storage failures', () async {
    final service = MobileCodexAccountService(
      store: _FailingStore(),
      client: CodexAccountClient(clock: () => now),
    );

    await expectLater(
      service.isConnected(),
      throwsA(
        isA<CodexAccountException>()
            .having(
              (error) => error.failure,
              'failure',
              CodexAccountFailure.unavailable,
            )
            .having(
              (error) => error.details,
              'details',
              'Codex account · Secure storage unavailable',
            ),
      ),
    );
  });

  test('removes a malformed stored session', () async {
    final store = _MalformedStore();
    final service = MobileCodexAccountService(
      store: store,
      client: CodexAccountClient(clock: () => now),
    );

    expect(await service.isConnected(), isFalse);
    expect(store.deleted, isTrue);
  });
}

final class _MemoryStore implements CodexAccountStore {
  _MemoryStore(this.value);

  CodexAccountSession? value;

  @override
  Future<CodexAccountSession?> read() async => value;

  @override
  Future<void> write(CodexAccountSession value) async {
    this.value = value;
  }

  @override
  Future<void> delete() async {
    value = null;
  }
}

final class _FailingStore implements CodexAccountStore {
  @override
  Future<CodexAccountSession?> read() => Future.error(StateError('storage'));

  @override
  Future<void> write(CodexAccountSession value) =>
      Future.error(StateError('storage'));

  @override
  Future<void> delete() => Future.error(StateError('storage'));
}

final class _MalformedStore implements CodexAccountStore {
  bool deleted = false;

  @override
  Future<CodexAccountSession?> read() {
    throw const FormatException('malformed session');
  }

  @override
  Future<void> write(CodexAccountSession value) async {}

  @override
  Future<void> delete() async {
    deleted = true;
  }
}

final class _QueueTransport implements CodexHttpTransport {
  _QueueTransport(this._responses);

  final List<CodexHttpResponse> _responses;
  final List<Uri> requests = [];

  @override
  Future<CodexHttpResponse> send(
    String method,
    Uri uri, {
    required Map<String, String> headers,
    String? body,
  }) async {
    requests.add(uri);
    return _responses.removeAt(0);
  }
}

CodexAccountSession _expiredSession(DateTime now) {
  return CodexAccountSession(
    accessToken: _jwt(expiresAt: now.subtract(const Duration(days: 1))),
    refreshToken: 'refresh-token',
    accountId: 'account-1',
    refreshedAt: now,
  );
}

CodexAccountSession _activeSession(DateTime now) {
  return CodexAccountSession(
    accessToken: _jwt(expiresAt: now.add(const Duration(days: 1))),
    refreshToken: 'refresh-token',
    accountId: 'account-1',
    refreshedAt: now,
  );
}

CodexHttpResponse _limitsResponse() {
  return _jsonResponse({
    'rate_limit': null,
    'credits': {'has_credits': false, 'unlimited': false, 'balance': '0'},
  });
}

CodexHttpResponse _activityResponse() {
  return _jsonResponse({
    'stats': {'daily_usage_buckets': <Object>[]},
  });
}

CodexHttpResponse _jsonResponse(Map<String, dynamic> value) {
  return CodexHttpResponse(statusCode: 200, body: jsonEncode(value));
}

String _jwt({required DateTime expiresAt}) {
  final encode =
      (Object value) =>
          base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
  return '${encode({'alg': 'none'})}.${encode({'exp': expiresAt.millisecondsSinceEpoch ~/ 1000})}.signature';
}
