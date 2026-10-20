import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ward_pulse_phone/sync/provider_reporting.dart';
import 'package:ward_pulse_phone/sync/provider_reporting_clients.dart';

void main() {
  group('AnthropicReportingClient', () {
    test('splits UTC usage ranges and paginates both bucket widths', () async {
      final transport = _FakeTransport({
        '/v1/organizations/usage_report/messages': [
          _response(_page(hasMore: true, nextPage: 'daily-2')),
          _response(_page()),
          _response(_page(hasMore: true, nextPage: 'minute-2')),
          _response(_page()),
        ],
        '/v1/organizations/cost_report': [
          _response(_page(hasMore: true, nextPage: 'cost-2')),
          _response(_page()),
        ],
      });
      final client = AnthropicReportingClient(
        http: ProviderReportingHttp(transport: transport),
      );

      final reports = await client.fetchDailyReports(
        adminApiKey: 'secret-admin-key',
        start: DateTime.parse('2026-07-01T03:00:00+03:00'),
        end: DateTime.parse('2026-07-20T01:00:00+13:00'),
      );

      expect(reports.usage, hasLength(4));
      expect(reports.costs, hasLength(2));
      final usageRequests =
          transport.requests
              .where((request) => request.uri.path.endsWith('/messages'))
              .toList();
      for (final request in usageRequests) {
        expect(request.headers['x-api-key'], 'secret-admin-key');
        expect(request.headers['anthropic-version'], '2023-06-01');
        expect(request.headers.containsKey('Authorization'), isFalse);
        expect(request.uri.queryParametersAll['group_by[]'], ['model']);
      }
      expect(
        usageRequests.map((request) {
          final parameters = request.uri.queryParameters;
          return [
            parameters['starting_at'],
            parameters['ending_at'],
            parameters['bucket_width'],
            parameters['limit'],
            parameters['page'],
          ];
        }),
        [
          [
            '2026-07-01T00:00:00.000Z',
            '2026-07-19T00:00:00.000Z',
            '1d',
            '31',
            null,
          ],
          [
            '2026-07-01T00:00:00.000Z',
            '2026-07-19T00:00:00.000Z',
            '1d',
            '31',
            'daily-2',
          ],
          [
            '2026-07-19T00:00:00.000Z',
            '2026-07-19T12:00:00.000Z',
            '1m',
            '1440',
            null,
          ],
          [
            '2026-07-19T00:00:00.000Z',
            '2026-07-19T12:00:00.000Z',
            '1m',
            '1440',
            'minute-2',
          ],
        ],
      );
      final costRequests =
          transport.requests
              .where((request) => request.uri.path.endsWith('/cost_report'))
              .toList();
      for (final request in costRequests) {
        expect(request.uri.queryParametersAll['group_by[]'], null);
        expect(request.uri.queryParameters['bucket_width'], '1d');
        expect(request.uri.queryParameters['limit'], '31');
        expect(
          request.uri.queryParameters['starting_at'],
          '2026-07-01T00:00:00.000Z',
        );
        expect(
          request.uri.queryParameters['ending_at'],
          '2026-07-19T12:00:00.000Z',
        );
      }
      expect(costRequests[1].uri.queryParameters['page'], 'cost-2');
      expect(reports.usage.join(), isNot(contains('secret-admin-key')));
    });

    for (final scenario in [
      (
        name: 'midnight end has no current-day range',
        start: DateTime.utc(2026, 7, 18),
        end: DateTime.utc(2026, 7, 19),
        width: '1d',
        limit: '31',
      ),
      (
        name: 'current-day-only range retains its supplied start and end',
        start: DateTime.utc(2026, 7, 19, 0, 15),
        end: DateTime.utc(2026, 7, 19, 12, 34, 56),
        width: '1m',
        limit: '1440',
      ),
    ]) {
      test(scenario.name, () async {
        final transport = _FakeTransport({
          '/v1/organizations/usage_report/messages': [_response(_page())],
          '/v1/organizations/cost_report': [_response(_page())],
        });
        final client = AnthropicReportingClient(
          http: ProviderReportingHttp(transport: transport),
        );

        final reports = await client.fetchDailyReports(
          adminApiKey: 'synthetic-key',
          start: scenario.start,
          end: scenario.end,
        );

        expect(reports.usage, hasLength(1));
        expect(reports.costs, hasLength(1));
        final usageRequest = transport.requests.first;
        expect(usageRequest.uri.path, endsWith('/messages'));
        expect(
          usageRequest.uri.queryParameters['bucket_width'],
          scenario.width,
        );
        expect(usageRequest.uri.queryParameters['limit'], scenario.limit);
        for (final request in transport.requests) {
          expect(
            request.uri.queryParameters['starting_at'],
            scenario.start.toIso8601String(),
          );
          expect(
            request.uri.queryParameters['ending_at'],
            scenario.end.toIso8601String(),
          );
        }
        expect(transport.requests.last.uri.path, endsWith('/cost_report'));
      });
    }

    for (final start in [
      DateTime.utc(2026, 7, 19, 12),
      DateTime.utc(2026, 7, 20),
    ]) {
      test('skips an empty interval starting at $start', () async {
        final transport = _FakeTransport({});
        final client = AnthropicReportingClient(
          http: ProviderReportingHttp(transport: transport),
        );

        final reports = await client.fetchDailyReports(
          adminApiKey: 'synthetic-key',
          start: start,
          end: DateTime.utc(2026, 7, 19, 12),
        );

        expect(reports.usage, isEmpty);
        expect(reports.costs, isEmpty);
        expect(transport.requests, isEmpty);
      });
    }

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
    const missingScope = 'Team API key missing required scope: read:*';
    const invalidKey = 'Invalid API key';
    const unrelatedPermission = 'Insufficient permissions or scope';
    for (final scenario in [
      (
        name: 'explicit missing reporting scope',
        body: jsonEncode({'message': missingScope}),
        failure: ProviderReportingFailure.permissionDenied,
      ),
      (
        name: 'invalid key',
        body: jsonEncode({'message': invalidKey}),
        failure: ProviderReportingFailure.authentication,
      ),
      (
        name: 'malformed JSON',
        body: '{"message":"$missingScope"',
        failure: ProviderReportingFailure.authentication,
      ),
      (
        name: 'non-object JSON',
        body: jsonEncode([missingScope]),
        failure: ProviderReportingFailure.authentication,
      ),
      (
        name: 'non-string message',
        body: jsonEncode({
          'message': [missingScope],
        }),
        failure: ProviderReportingFailure.authentication,
      ),
      (
        name: 'nested message',
        body: jsonEncode({
          'error': {'message': missingScope},
        }),
        failure: ProviderReportingFailure.authentication,
      ),
      (
        name: 'unrelated permission text',
        body: jsonEncode({'message': unrelatedPermission}),
        failure: ProviderReportingFailure.authentication,
      ),
      (
        name: 'message containing the template',
        body: jsonEncode({'message': 'Unrelated: $missingScope'}),
        failure: ProviderReportingFailure.authentication,
      ),
    ]) {
      test(
        'classifies 401 ${scenario.name} without exposing details',
        () async {
          const apiKey = 'synthetic-team-key';
          final transport = _FakeTransport({
            '/teams/daily-usage-data': [
              ProviderHttpResponse(
                statusCode: HttpStatus.unauthorized,
                headers: const {},
                body: scenario.body,
              ),
            ],
          });
          final client = CursorPlatformClient(
            http: ProviderReportingHttp(transport: transport),
            clock: () => DateTime.utc(2026, 7, 19, 12),
          );
          final safeDiagnostics = allOf(
            isNot(contains(scenario.body)),
            isNot(contains(missingScope)),
            isNot(contains(invalidKey)),
            isNot(contains(unrelatedPermission)),
            isNot(contains(apiKey)),
            isNot(contains(encodeBasicAuth(apiKey))),
          );

          await expectLater(
            client.fetchReports(adminApiKey: apiKey),
            throwsA(
              isA<ProviderReportingException>()
                  .having((error) => error.failure, 'failure', scenario.failure)
                  .having(
                    (error) => error.details,
                    'safe details',
                    allOf('Cursor daily usage · HTTP 401', safeDiagnostics),
                  )
                  .having(
                    (error) => error.toString(),
                    'safe message',
                    safeDiagnostics,
                  ),
            ),
          );
          expect(transport.requests, hasLength(1));
        },
      );
    }

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
