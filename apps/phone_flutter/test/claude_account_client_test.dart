import 'dart:convert';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:ward_pulse_phone/providers/claude_account_store.dart';
import 'package:ward_pulse_phone/sync/claude_account_client.dart';

void main() {
  final now = DateTime.utc(2026, 7, 26, 12);

  test('builds a PKCE authorize URL for the Claude Code client', () {
    final client = ClaudeAccountClient(
      clock: () => now,
      random: _FixedRandom(),
    );
    final request = client.beginAuthorization();

    expect(request.authorizationUri.host, 'claude.ai');
    expect(
      request.authorizationUri.queryParameters['client_id'],
      ClaudeAccountClient.clientId,
    );
    expect(
      request.authorizationUri.queryParameters['code_challenge_method'],
      'S256',
    );
    expect(
      request.authorizationUri.queryParameters['redirect_uri'],
      ClaudeAccountClient.redirectUri,
    );
    expect(request.codeVerifier, isNotEmpty);
    expect(request.state, isNotEmpty);
  });

  test('exchanges CODE#STATE for a session', () async {
    final transport = _QueueTransport([
      _jsonResponse({
        'access_token': 'sk-ant-oat01-access',
        'refresh_token': 'sk-ant-ort01-refresh',
        'expires_in': 28800,
        'account': {'uuid': 'acct-1'},
      }),
    ]);
    final client = ClaudeAccountClient(
      transport: transport,
      clock: () => now,
      random: _FixedRandom(),
    );
    final request = client.beginAuthorization();
    final session = await client.exchangeAuthorizationCode(
      request: request,
      pastedCode: 'AUTHCODE#${request.state}',
    );

    expect(session.accessToken, 'sk-ant-oat01-access');
    expect(session.refreshToken, 'sk-ant-ort01-refresh');
    expect(session.accountId, 'acct-1');
    expect(session.expiresAt, now.add(const Duration(seconds: 28800)));
    expect(transport.bodies.single, contains('grant_type=authorization_code'));
    expect(transport.bodies.single, contains('code=AUTHCODE'));
  });

  test('rejects a mismatched state in CODE#STATE', () async {
    final client = ClaudeAccountClient(
      transport: _QueueTransport([]),
      clock: () => now,
      random: _FixedRandom(),
    );
    final request = client.beginAuthorization();

    await expectLater(
      client.exchangeAuthorizationCode(
        request: request,
        pastedCode: 'AUTHCODE#other-state',
      ),
      throwsA(
        isA<ClaudeAccountException>().having(
          (error) => error.failure,
          'failure',
          ClaudeAccountFailure.invalidResponse,
        ),
      ),
    );
  });

  test('refreshes before usage when the access token is near expiry', () async {
    final transport = _QueueTransport([
      _jsonResponse({
        'access_token': 'sk-ant-oat01-new',
        'refresh_token': 'sk-ant-ort01-rotated',
        'expires_in': 28800,
      }),
      _jsonResponse({
        'five_hour': {'utilization': 10},
        'seven_day': {'utilization': 20},
      }),
    ]);
    final client = ClaudeAccountClient(transport: transport, clock: () => now);
    final sessions = <ClaudeAccountSession>[];
    final result = await client.fetchReport(
      ClaudeAccountSession(
        accessToken: 'old-access',
        refreshToken: 'old-refresh',
        expiresAt: now.add(const Duration(minutes: 1)),
        accountId: 'acct-1',
      ),
      onSessionChanged: (session) async {
        sessions.add(session);
      },
    );

    expect(sessions, hasLength(1));
    expect(sessions.single.refreshToken, 'sk-ant-ort01-rotated');
    expect(result.session.accessToken, 'sk-ant-oat01-new');
    expect(result.reportJson, contains('"accountId":"acct-1"'));
    expect(transport.methods, ['POST', 'GET']);
    expect(
      transport.headers[1]['Authorization'],
      'Bearer sk-ant-oat01-new',
    );
    expect(transport.headers[1]['anthropic-beta'], 'oauth-2025-04-20');
    expect(transport.headers[1]['User-Agent'], contains('claude-code'));
  });

  test('maps a forbidden usage response to permission denied', () async {
    final transport = _QueueTransport([
      const ClaudeHttpResponse(statusCode: 403, body: '{}'),
    ]);
    final client = ClaudeAccountClient(transport: transport, clock: () => now);

    await expectLater(
      client.fetchReport(
        ClaudeAccountSession(
          accessToken: 'access',
          refreshToken: 'refresh',
          expiresAt: now.add(const Duration(hours: 1)),
          accountId: 'acct-1',
        ),
        onSessionChanged: (_) async {},
      ),
      throwsA(
        isA<ClaudeAccountException>().having(
          (error) => error.failure,
          'failure',
          ClaudeAccountFailure.permissionDenied,
        ),
      ),
    );
  });
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
  final bodies = <String?>[];
  final methods = <String>[];
  final headers = <Map<String, String>>[];

  @override
  Future<ClaudeHttpResponse> send(
    String method,
    Uri uri, {
    required Map<String, String> headers,
    String? body,
    Duration? timeout,
  }) async {
    methods.add(method);
    bodies.add(body);
    this.headers.add(headers);
    if (_responses.isEmpty) {
      fail('Unexpected $method ${uri.path}');
    }
    return _responses.removeAt(0);
  }
}

ClaudeHttpResponse _jsonResponse(Map<String, Object?> json) {
  return ClaudeHttpResponse(statusCode: 200, body: jsonEncode(json));
}
