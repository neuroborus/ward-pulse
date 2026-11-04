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
    expect(transport.headers[1]['Authorization'], 'Bearer sk-ant-oat01-new');
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

  test('rejects an expired refresh grant before loading usage', () async {
    const privateDescription = 'private-description-sentinel';
    const privateToken = 'private-token-sentinel';
    final transport = _QueueTransport([
      ClaudeHttpResponse(
        statusCode: 400,
        body: jsonEncode({
          'error': 'invalid_grant',
          'error_description': privateDescription,
          'refresh_token': privateToken,
        }),
      ),
    ]);
    final client = ClaudeAccountClient(transport: transport, clock: () => now);
    final sessions = <ClaudeAccountSession>[];

    await expectLater(
      client.fetchReport(
        ClaudeAccountSession(
          accessToken: 'old-access',
          refreshToken: privateToken,
          expiresAt: now.add(const Duration(minutes: 1)),
          accountId: 'acct-1',
        ),
        onSessionChanged: (session) async {
          sessions.add(session);
        },
      ),
      throwsA(
        isA<ClaudeAccountException>()
            .having(
              (error) => error.failure,
              'failure',
              ClaudeAccountFailure.authentication,
            )
            .having(
              (error) => error.details,
              'details',
              allOf(
                equals('Claude token refresh · HTTP 400 · invalid_grant'),
                isNot(contains(privateDescription)),
                isNot(contains(privateToken)),
              ),
            ),
      ),
    );

    expect(transport.methods, ['POST']);
    expect(
      Uri.splitQueryString(transport.bodies.single!)['grant_type'],
      'refresh_token',
    );
    expect(sessions, isEmpty);
  });

  test('stops after usage 401 and an expired refresh grant', () async {
    final transport = _QueueTransport([
      const ClaudeHttpResponse(statusCode: 401, body: '{}'),
      const ClaudeHttpResponse(
        statusCode: 400,
        body: '{"error":"invalid_grant"}',
      ),
    ]);
    final client = ClaudeAccountClient(transport: transport, clock: () => now);
    final sessions = <ClaudeAccountSession>[];

    await expectLater(
      client.fetchReport(
        ClaudeAccountSession(
          accessToken: 'access',
          refreshToken: 'refresh',
          expiresAt: now.add(const Duration(hours: 1)),
          accountId: 'acct-1',
        ),
        onSessionChanged: (session) async {
          sessions.add(session);
        },
      ),
      throwsA(
        isA<ClaudeAccountException>()
            .having(
              (error) => error.failure,
              'failure',
              ClaudeAccountFailure.authentication,
            )
            .having(
              (error) => error.details,
              'details',
              'Claude token refresh · HTTP 400 · invalid_grant',
            ),
      ),
    );

    expect(transport.methods, ['GET', 'POST']);
    expect(
      Uri.splitQueryString(transport.bodies[1]!)['grant_type'],
      'refresh_token',
    );
    expect(sessions, isEmpty);
  });

  final rejectedRefreshBodies = <String, String>{
    'unknown code': '{"error":"invalid_request"}',
    'malformed JSON': '{"error":"invalid_grant"',
    'array body': '[{"error":"invalid_grant"}]',
    'string body': '"invalid_grant"',
    'null body': 'null',
    'missing error': '{}',
    'null error': '{"error":null}',
    'numeric error': '{"error":400}',
    'boolean error': '{"error":true}',
    'array error': '{"error":["invalid_grant"]}',
    'object error': '{"error":{"error":"invalid_grant"}}',
    'description only': '{"error_description":"invalid_grant"}',
    'nested error': '{"nested":{"error":"invalid_grant"}}',
    'leading whitespace': '{"error":" invalid_grant"}',
    'trailing whitespace': '{"error":"invalid_grant "}',
    'case change': '{"error":"INVALID_GRANT"}',
  };
  for (final rejection in rejectedRefreshBodies.entries) {
    test('keeps refresh 400 ${rejection.key} as invalid response', () async {
      final transport = _QueueTransport([
        ClaudeHttpResponse(statusCode: 400, body: rejection.value),
      ]);
      final client = ClaudeAccountClient(
        transport: transport,
        clock: () => now,
      );

      await expectLater(
        client.refresh(
          ClaudeAccountSession(
            accessToken: 'access',
            refreshToken: 'refresh',
            expiresAt: now.add(const Duration(minutes: 1)),
            accountId: 'acct-1',
          ),
        ),
        throwsA(
          isA<ClaudeAccountException>()
              .having(
                (error) => error.failure,
                'failure',
                ClaudeAccountFailure.invalidResponse,
              )
              .having(
                (error) => error.details,
                'details',
                'Claude token refresh · HTTP 400',
              ),
        ),
      );

      expect(transport.methods, ['POST']);
    });
  }

  test('keeps usage 400 invalid_grant as invalid response', () async {
    final transport = _QueueTransport([
      const ClaudeHttpResponse(
        statusCode: 400,
        body: '{"error":"invalid_grant"}',
      ),
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
        onSessionChanged: (_) async {
          fail('Unexpected session change');
        },
      ),
      throwsA(
        isA<ClaudeAccountException>()
            .having(
              (error) => error.failure,
              'failure',
              ClaudeAccountFailure.invalidResponse,
            )
            .having(
              (error) => error.details,
              'details',
              'Claude usage · HTTP 400',
            ),
      ),
    );

    expect(transport.methods, ['GET']);
  });

  test('keeps sign-in 400 invalid_grant as invalid response', () async {
    final transport = _QueueTransport([
      const ClaudeHttpResponse(
        statusCode: 400,
        body: '{"error":"invalid_grant"}',
      ),
    ]);
    final client = ClaudeAccountClient(
      transport: transport,
      clock: () => now,
      random: _FixedRandom(),
    );
    final request = client.beginAuthorization();

    await expectLater(
      client.exchangeAuthorizationCode(
        request: request,
        pastedCode: 'AUTHCODE#${request.state}',
      ),
      throwsA(
        isA<ClaudeAccountException>()
            .having(
              (error) => error.failure,
              'failure',
              ClaudeAccountFailure.invalidResponse,
            )
            .having(
              (error) => error.details,
              'details',
              'Claude sign-in · HTTP 400',
            ),
      ),
    );

    expect(transport.methods, ['POST']);
    expect(
      Uri.splitQueryString(transport.bodies.single!)['grant_type'],
      'authorization_code',
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
