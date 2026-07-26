import 'dart:convert';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:ward_pulse_phone/providers/claude_account_service.dart';
import 'package:ward_pulse_phone/providers/claude_account_store.dart';
import 'package:ward_pulse_phone/sync/claude_account_client.dart';

void main() {
  final now = DateTime.utc(2026, 7, 26, 12);

  test('persists a rotated session before loading the report', () async {
    final store = _MemoryStore(
      ClaudeAccountSession(
        accessToken: 'old-access',
        refreshToken: 'old-refresh',
        expiresAt: now.add(const Duration(minutes: 1)),
        accountId: 'acct-1',
      ),
    );
    final transport = _QueueTransport([
      _jsonResponse({
        'access_token': 'sk-ant-oat01-new',
        'refresh_token': 'sk-ant-ort01-rotated',
        'expires_in': 28800,
      }),
      const ClaudeHttpResponse(statusCode: 500, body: '{}'),
    ]);
    final service = MobileClaudeAccountService(
      store: store,
      client: ClaudeAccountClient(transport: transport, clock: () => now),
    );

    await expectLater(
      service.fetchReport(),
      throwsA(isA<ClaudeAccountException>()),
    );

    expect(store.value?.refreshToken, 'sk-ant-ort01-rotated');
  });

  test('completes PKCE login into secure storage', () async {
    final store = _MemoryStore(null);
    final transport = _QueueTransport([
      _jsonResponse({
        'access_token': 'sk-ant-oat01-access',
        'refresh_token': 'sk-ant-ort01-refresh',
        'expires_in': 28800,
        'account': {'uuid': 'acct-9'},
      }),
    ]);
    final service = MobileClaudeAccountService(
      store: store,
      client: ClaudeAccountClient(
        transport: transport,
        clock: () => now,
        random: _FixedRandom(),
      ),
    );

    final attempt = await service.startLogin();
    await attempt.completeWithCode('AUTHCODE#${attempt.authorization.state}');

    expect(await service.isConnected(), isTrue);
    expect(store.value?.accountId, 'acct-9');
  });
}

class _MemoryStore implements ClaudeAccountStore {
  _MemoryStore(this.value);

  ClaudeAccountSession? value;

  @override
  Future<ClaudeAccountSession?> read() async => value;

  @override
  Future<void> write(ClaudeAccountSession next) async {
    value = next;
  }

  @override
  Future<void> delete() async {
    value = null;
  }
}

class _FixedRandom implements Random {
  @override
  int nextInt(int max) => 1;

  @override
  double nextDouble() => 0;

  @override
  bool nextBool() => false;
}

class _QueueTransport implements ClaudeHttpTransport {
  _QueueTransport(this._responses);

  final List<ClaudeHttpResponse> _responses;

  @override
  Future<ClaudeHttpResponse> send(
    String method,
    Uri uri, {
    required Map<String, String> headers,
    String? body,
    Duration? timeout,
  }) async {
    if (_responses.isEmpty) {
      fail('Unexpected $method ${uri.path}');
    }
    return _responses.removeAt(0);
  }
}

ClaudeHttpResponse _jsonResponse(Map<String, Object?> json) {
  return ClaudeHttpResponse(statusCode: 200, body: jsonEncode(json));
}
