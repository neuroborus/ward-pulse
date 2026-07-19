import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ward_pulse_phone/providers/codex_account_store.dart';
import 'package:ward_pulse_phone/sync/codex_account_client.dart';

void main() {
  test('completes the Codex device-code flow', () async {
    final transport = _QueueTransport([
      _jsonResponse({
        'device_auth_id': 'device-id',
        'user_code': 'ABCD-1234',
        'interval': '5',
      }),
      const CodexHttpResponse(statusCode: 403, body: '{}'),
      _jsonResponse({
        'authorization_code': 'authorization-code',
        'code_challenge': 'challenge',
        'code_verifier': 'verifier',
      }),
      _jsonResponse({
        'id_token': _jwt(accountId: 'account-1'),
        'access_token': _jwt(expiresAt: DateTime.utc(2026, 8)),
        'refresh_token': 'refresh-token',
      }),
    ]);
    final client = CodexAccountClient(
      transport: transport,
      clock: () => DateTime.utc(2026, 7, 19),
      delay: (_) async {},
    );

    final code = await client.requestDeviceCode();
    final session = await client.completeDeviceLogin(
      code,
      cancelled: Completer<void>().future,
    );

    expect(code.userCode, 'ABCD-1234');
    expect(session.accountId, 'account-1');
    expect(session.refreshToken, 'refresh-token');
    expect(transport.requests[0].uri.path, '/api/accounts/deviceauth/usercode');
    expect(transport.requests.last.body, contains('code_verifier=verifier'));
  });

  test('normalizes direct Codex limits and recent token activity', () async {
    final buckets = List.generate(35, (index) {
      return {
        'start_date': DateTime.utc(
          2026,
          6,
          1,
        ).add(Duration(days: index)).toIso8601String().substring(0, 10),
        'tokens': index,
      };
    });
    final transport = _QueueTransport([
      _jsonResponse({
        'plan_type': 'plus',
        'rate_limit': {
          'primary_window': {
            'used_percent': 8,
            'limit_window_seconds': 604800,
            'reset_at': 1785092130,
          },
          'secondary_window': null,
        },
        'credits': {'has_credits': true, 'unlimited': false, 'balance': '12.5'},
      }),
      _jsonResponse({
        'stats': {'daily_usage_buckets': buckets},
      }),
    ]);
    final client = CodexAccountClient(
      transport: transport,
      clock: () => DateTime.utc(2026, 7, 19),
    );
    final session = CodexAccountSession(
      accessToken: _jwt(expiresAt: DateTime.utc(2026, 8)),
      refreshToken: 'refresh-token',
      accountId: 'account-1',
      refreshedAt: DateTime.utc(2026, 7, 19),
    );

    final result = await client.fetchReport(session);
    final report = jsonDecode(result.reportJson) as Map<String, dynamic>;
    final limits =
        (report['rateLimits'] as Map<String, dynamic>)['rateLimits']
            as Map<String, dynamic>;
    final activity =
        (report['usage'] as Map<String, dynamic>)['dailyUsageBuckets'] as List;

    expect(
      (limits['primary'] as Map<String, dynamic>)['windowDurationMins'],
      10080,
    );
    expect((limits['credits'] as Map<String, dynamic>)['balance'], '12.5');
    expect(activity, hasLength(31));
    expect(transport.requests.first.headers['ChatGPT-Account-Id'], 'account-1');
    expect(
      transport.requests.first.headers['Authorization'],
      startsWith('Bearer '),
    );
  });

  test('refreshes an expired access token before loading usage', () async {
    final refreshedAccessToken = _jwt(expiresAt: DateTime.utc(2026, 8));
    final transport = _QueueTransport([
      _jsonResponse({
        'access_token': refreshedAccessToken,
        'refresh_token': 'rotated-refresh-token',
      }),
      _jsonResponse({
        'rate_limit': null,
        'credits': {'has_credits': false, 'unlimited': false, 'balance': '0'},
      }),
      _jsonResponse({
        'stats': {'daily_usage_buckets': <Object>[]},
      }),
    ]);
    final client = CodexAccountClient(
      transport: transport,
      clock: () => DateTime.utc(2026, 7, 19),
    );
    final session = CodexAccountSession(
      accessToken: _jwt(expiresAt: DateTime.utc(2026, 7, 18)),
      refreshToken: 'refresh-token',
      accountId: 'account-1',
      refreshedAt: DateTime.utc(2026, 7, 19),
    );

    final result = await client.fetchReport(session);

    expect(result.session.accessToken, refreshedAccessToken);
    expect(result.session.refreshToken, 'rotated-refresh-token');
    expect(transport.requests.first.uri.path, '/oauth/token');
    expect(
      jsonDecode(transport.requests.first.body!)['grant_type'],
      'refresh_token',
    );
  });

  test('accepts an account without token activity', () async {
    final transport = _QueueTransport([
      _jsonResponse({'rate_limit': null, 'credits': null}),
      _jsonResponse({
        'stats': {'daily_usage_buckets': null},
      }),
    ]);
    final client = CodexAccountClient(
      transport: transport,
      clock: () => DateTime.utc(2026, 7, 19),
    );
    final session = CodexAccountSession(
      accessToken: _jwt(expiresAt: DateTime.utc(2026, 8)),
      refreshToken: 'refresh-token',
      accountId: 'account-1',
      refreshedAt: DateTime.utc(2026, 7, 19),
    );

    final result = await client.fetchReport(session);
    final report = jsonDecode(result.reportJson) as Map<String, dynamic>;
    final activity =
        (report['usage'] as Map<String, dynamic>)['dailyUsageBuckets'] as List;

    expect(activity, isEmpty);
  });

  test('does not expose arbitrary backend error text', () async {
    final transport = _QueueTransport([
      const CodexHttpResponse(
        statusCode: 500,
        body: '{"error":"user@example.com private detail"}',
      ),
      _jsonResponse({
        'stats': {'daily_usage_buckets': <Object>[]},
      }),
    ]);
    final client = CodexAccountClient(
      transport: transport,
      clock: () => DateTime.utc(2026, 7, 19),
    );

    await expectLater(
      client.fetchReport(
        CodexAccountSession(
          accessToken: _jwt(expiresAt: DateTime.utc(2026, 8)),
          refreshToken: 'refresh-token',
          accountId: 'account-1',
          refreshedAt: DateTime.utc(2026, 7, 19),
        ),
      ),
      throwsA(
        isA<CodexAccountException>().having(
          (error) => error.details,
          'details',
          allOf(contains('HTTP 500'), isNot(contains('private detail'))),
        ),
      ),
    );
  });

  test(
    'classifies a revoked refresh token as authentication failure',
    () async {
      final client = CodexAccountClient(
        transport: _QueueTransport([
          const CodexHttpResponse(
            statusCode: 400,
            body: '{"error":{"code":"refresh_token_revoked"}}',
          ),
        ]),
        clock: () => DateTime.utc(2026, 7, 19),
      );

      await expectLater(
        client.fetchReport(
          CodexAccountSession(
            accessToken: _jwt(expiresAt: DateTime.utc(2026, 7, 18)),
            refreshToken: 'refresh-token',
            accountId: 'account-1',
            refreshedAt: DateTime.utc(2026, 7, 19),
          ),
        ),
        throwsA(
          isA<CodexAccountException>().having(
            (error) => error.failure,
            'failure',
            CodexAccountFailure.authentication,
          ),
        ),
      );
    },
  );
}

final class _QueueTransport implements CodexHttpTransport {
  _QueueTransport(this._responses);

  final List<CodexHttpResponse> _responses;
  final List<_Request> requests = [];

  @override
  Future<CodexHttpResponse> send(
    String method,
    Uri uri, {
    required Map<String, String> headers,
    String? body,
  }) async {
    requests.add(_Request(uri: uri, headers: headers, body: body));
    return _responses.removeAt(0);
  }
}

final class _Request {
  const _Request({required this.uri, required this.headers, this.body});

  final Uri uri;
  final Map<String, String> headers;
  final String? body;
}

CodexHttpResponse _jsonResponse(Map<String, dynamic> value) {
  return CodexHttpResponse(statusCode: 200, body: jsonEncode(value));
}

String _jwt({String? accountId, DateTime? expiresAt}) {
  final payload = {
    if (accountId != null)
      'https://api.openai.com/auth': {'chatgpt_account_id': accountId},
    if (expiresAt != null) 'exp': expiresAt.millisecondsSinceEpoch ~/ 1000,
  };
  final encode =
      (Object value) =>
          base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
  return '${encode({'alg': 'none'})}.${encode(payload)}.signature';
}
