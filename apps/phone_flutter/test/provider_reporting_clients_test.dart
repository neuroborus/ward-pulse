import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ward_pulse_phone/sync/provider_reporting.dart';
import 'package:ward_pulse_phone/sync/provider_reporting_clients.dart';

void main() {
  group('AnthropicReportingClient', () {
    test('paginates usage and cost reports without exposing the key', () async {
      final transport = _FakeTransport({
        '/v1/organizations/usage_report/messages': [
          _response(_page(hasMore: true, nextPage: 'usage-2')),
          _response(_page()),
        ],
        '/v1/organizations/cost_report': [_response(_page())],
      });
      final client = AnthropicReportingClient(
        http: ProviderReportingHttp(transport: transport),
      );

      final reports = await client.fetchDailyReports(
        adminApiKey: 'secret-admin-key',
        start: DateTime.utc(2026, 7, 1),
        end: DateTime.utc(2026, 7, 19, 12),
      );

      expect(reports.usage, hasLength(2));
      expect(reports.costs, hasLength(1));
      final usageRequests =
          transport.requests
              .where((request) => request.uri.path.endsWith('/messages'))
              .toList();
      expect(usageRequests[0].headers['x-api-key'], 'secret-admin-key');
      expect(usageRequests[0].headers.containsKey('Authorization'), isFalse);
      expect(usageRequests[0].uri.queryParameters['bucket_width'], '1d');
      expect(usageRequests[0].uri.queryParametersAll['group_by[]'], ['model']);
      expect(usageRequests[1].uri.queryParameters['page'], 'usage-2');
      final costRequests =
          transport.requests
              .where((request) => request.uri.path.endsWith('/cost_report'))
              .toList();
      expect(costRequests.single.uri.queryParametersAll['group_by[]'], null);
      expect(reports.usage.join(), isNot(contains('secret-admin-key')));
    });

    test('maps an unauthorized usage response to authentication', () async {
      final transport = _FakeTransport({
        '/v1/organizations/usage_report/messages': [
          const ProviderHttpResponse(
            statusCode: HttpStatus.unauthorized,
            headers: {},
            body: '{"error":"sensitive provider detail"}',
          ),
        ],
        '/v1/organizations/cost_report': [_response(_page())],
      });
      final client = AnthropicReportingClient(
        http: ProviderReportingHttp(transport: transport),
      );

      await expectLater(
        client.fetchDailyReports(
          adminApiKey: 'secret-admin-key',
          start: DateTime.utc(2026, 7, 1),
          end: DateTime.utc(2026, 7, 19, 12),
        ),
        throwsA(
          isA<ProviderReportingException>()
              .having(
                (error) => error.failure,
                'failure',
                ProviderReportingFailure.authentication,
              )
              .having(
                (error) => error.details,
                'safe details',
                allOf(
                  contains('Usage'),
                  contains('HTTP 401'),
                  isNot(contains('sensitive provider detail')),
                ),
              ),
        ),
      );
    });
  });

  group('ClaudeUsageClient', () {
    test('sends the OAuth token and Claude Code headers', () async {
      final transport = _FakeTransport({
        '/api/oauth/usage': [_response('{"five_hour":{}}')],
      });
      final client = ClaudeUsageClient(
        http: ProviderReportingHttp(transport: transport),
      );

      final body = await client.fetchUsage(oauthToken: 'secret-oauth-token');

      expect(body, '{"five_hour":{}}');
      final request = transport.requests.single;
      expect(request.headers['Authorization'], 'Bearer secret-oauth-token');
      expect(request.headers['anthropic-beta'], 'oauth-2025-04-20');
      expect(request.headers['User-Agent'], contains('claude-code'));
    });

    test('maps a forbidden response to permission denied', () async {
      final transport = _FakeTransport({
        '/api/oauth/usage': [
          const ProviderHttpResponse(
            statusCode: HttpStatus.forbidden,
            headers: {},
            body: '{}',
          ),
        ],
      });
      final client = ClaudeUsageClient(
        http: ProviderReportingHttp(transport: transport),
      );

      await expectLater(
        client.fetchUsage(oauthToken: 'secret-oauth-token'),
        throwsA(
          isA<ProviderReportingException>().having(
            (error) => error.failure,
            'failure',
            ProviderReportingFailure.permissionDenied,
          ),
        ),
      );
    });
  });

  group('CursorPlanClient', () {
    test('sends the session token as a cookie', () async {
      final transport = _FakeTransport({
        '/api/usage-summary': [_response('{"plan":{}}')],
      });
      final client = CursorPlanClient(
        http: ProviderReportingHttp(transport: transport),
      );

      final body = await client.fetchUsageSummary(
        sessionToken: 'secret-session-token',
      );

      expect(body, '{"plan":{}}');
      final request = transport.requests.single;
      expect(
        request.headers['Cookie'],
        'WorkosCursorSessionToken=secret-session-token',
      );
    });

    test('retries after a rate limited response without Retry-After', () async {
      final transport = _FakeTransport({
        '/api/usage-summary': [
          const ProviderHttpResponse(
            statusCode: HttpStatus.tooManyRequests,
            headers: {},
            body: '{}',
          ),
          _response('{"plan":{}}'),
        ],
      });
      final delays = <Duration>[];
      final client = CursorPlanClient(
        http: ProviderReportingHttp(
          transport: transport,
          delay: (duration) async => delays.add(duration),
          random: () => 0,
        ),
      );

      final body = await client.fetchUsageSummary(
        sessionToken: 'secret-session-token',
      );

      expect(body, '{"plan":{}}');
      expect(delays, [const Duration(milliseconds: 500)]);
    });
  });

  group('CursorPlatformClient', () {
    test('uses Basic auth and paginates spend pages', () async {
      final transport = _FakeTransport({
        '/teams/daily-usage-data': [_response('{"data":[]}')],
        '/teams/spend': [
          _response(
            '{"teamMemberSpend":[{"overallSpendCents":100}],"totalPages":2}',
          ),
          _response(
            '{"teamMemberSpend":[{"overallSpendCents":50}],"totalPages":2}',
          ),
        ],
      });
      final client = CursorPlatformClient(
        http: ProviderReportingHttp(transport: transport),
        clock: () => DateTime.utc(2026, 7, 19, 12),
      );

      final reports = await client.fetchReports(adminApiKey: 'secret-team-key');

      expect(reports.dailyUsage, ['{"data":[]}']);
      expect(reports.spend, hasLength(2));
      final expectedAuth = encodeBasicAuth('secret-team-key');
      for (final request in transport.requests) {
        expect(request.headers['Authorization'], expectedAuth);
      }
      final spendBodies =
          transport.requestBodies
              .where((body) => body != null && body.contains('pageSize'))
              .toList();
      expect(jsonDecode(spendBodies[0]!), {'page': 1, 'pageSize': 100});
      expect(jsonDecode(spendBodies[1]!), {'page': 2, 'pageSize': 100});
    });

    test('maps a server error to unavailable', () async {
      final transport = _FakeTransport({
        '/teams/daily-usage-data': [
          const ProviderHttpResponse(
            statusCode: HttpStatus.internalServerError,
            headers: {},
            body: '{}',
          ),
        ],
        '/teams/spend': [_response('{}')],
      });
      final client = CursorPlatformClient(
        http: ProviderReportingHttp(transport: transport),
      );

      await expectLater(
        client.fetchReports(adminApiKey: 'secret-team-key'),
        throwsA(
          isA<ProviderReportingException>().having(
            (error) => error.failure,
            'failure',
            ProviderReportingFailure.unavailable,
          ),
        ),
      );
    });
  });
}

ProviderHttpResponse _response(String body) {
  return ProviderHttpResponse(
    statusCode: HttpStatus.ok,
    headers: const {},
    body: body,
  );
}

String _page({bool hasMore = false, String? nextPage}) {
  return jsonEncode({
    'has_more': hasMore,
    'next_page': nextPage,
    'data': <Object>[],
  });
}

final class _FakeTransport implements ProviderHttpTransport {
  _FakeTransport(Map<String, List<ProviderHttpResponse>> responses)
    : _responses = {
        for (final entry in responses.entries)
          entry.key: List<ProviderHttpResponse>.from(entry.value),
      };

  final Map<String, List<ProviderHttpResponse>> _responses;
  final requests = <_Request>[];
  final requestBodies = <String?>[];

  @override
  Future<ProviderHttpResponse> get(
    Uri uri, {
    required Map<String, String> headers,
  }) async {
    requests.add(_Request(uri, Map.unmodifiable(headers)));
    requestBodies.add(null);
    return _take(uri);
  }

  @override
  Future<ProviderHttpResponse> post(
    Uri uri, {
    required Map<String, String> headers,
    String? body,
  }) async {
    requests.add(_Request(uri, Map.unmodifiable(headers)));
    requestBodies.add(body);
    return _take(uri);
  }

  ProviderHttpResponse _take(Uri uri) {
    final responses = _responses[uri.path];
    if (responses == null || responses.isEmpty) {
      throw StateError('No response configured for ${uri.path}');
    }
    return responses.removeAt(0);
  }
}

final class _Request {
  const _Request(this.uri, this.headers);

  final Uri uri;
  final Map<String, String> headers;
}
