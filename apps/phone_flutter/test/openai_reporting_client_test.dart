import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ward_pulse_phone/sync/openai_reporting_client.dart';

void main() {
  final start = DateTime.utc(2026, 7, 1);
  final end = DateTime.utc(2026, 7, 19, 12);

  test('fetches every usage and cost page without exposing the key', () async {
    final transport = _FakeTransport({
      '/v1/organization/usage/completions': [
        _response(_page(hasMore: true, nextPage: 'usage-2')),
        _response(_page()),
      ],
      '/v1/organization/costs': [_response(_page())],
    });
    final client = OpenAiReportingClient(transport: transport);

    final reports = await client.fetchDailyReports(
      adminApiKey: 'secret-admin-key',
      start: start,
      end: end,
    );

    expect(reports.usage, hasLength(2));
    expect(reports.costs, hasLength(1));
    final usageRequests =
        transport.requests
            .where((request) => request.uri.path.endsWith('/completions'))
            .toList();
    expect(usageRequests[0].uri.queryParametersAll['group_by'], ['model']);
    expect(usageRequests[0].uri.queryParameters['limit'], '31');
    expect(usageRequests[1].uri.queryParameters['page'], 'usage-2');
    expect(
      usageRequests[0].headers['Authorization'],
      'Bearer secret-admin-key',
    );
    expect(reports.usage.join(), isNot(contains('secret-admin-key')));
  });

  test('honors Retry-After before retrying a rate-limited page', () async {
    final delays = <Duration>[];
    final transport = _FakeTransport({
      '/v1/organization/usage/completions': [
        const ProviderHttpResponse(
          statusCode: HttpStatus.tooManyRequests,
          headers: {'retry-after': '2'},
          body: '{}',
        ),
        _response(_page()),
      ],
      '/v1/organization/costs': [_response(_page())],
    });
    final client = OpenAiReportingClient(
      transport: transport,
      delay: (duration) async => delays.add(duration),
    );

    await client.fetchDailyReports(
      adminApiKey: 'secret-admin-key',
      start: start,
      end: end,
    );

    expect(delays, [const Duration(seconds: 2)]);
  });

  test(
    'uses exponential backoff with jitter when Retry-After is absent',
    () async {
      final delays = <Duration>[];
      final transport = _FakeTransport({
        '/v1/organization/usage/completions': [
          const ProviderHttpResponse(
            statusCode: HttpStatus.tooManyRequests,
            headers: {},
            body: '{}',
          ),
          _response(_page()),
        ],
        '/v1/organization/costs': [_response(_page())],
      });
      final client = OpenAiReportingClient(
        transport: transport,
        delay: (duration) async => delays.add(duration),
        random: () => 0,
      );

      await client.fetchDailyReports(
        adminApiKey: 'secret-admin-key',
        start: start,
        end: end,
      );

      expect(delays, [const Duration(milliseconds: 500)]);
    },
  );

  test('maps authentication failures without response details', () async {
    final transport = _FakeTransport({
      '/v1/organization/usage/completions': [
        const ProviderHttpResponse(
          statusCode: HttpStatus.unauthorized,
          headers: {},
          body: '{"error":"sensitive provider detail"}',
        ),
      ],
      '/v1/organization/costs': [_response(_page())],
    });
    final client = OpenAiReportingClient(transport: transport);

    await expectLater(
      client.fetchDailyReports(
        adminApiKey: 'secret-admin-key',
        start: start,
        end: end,
      ),
      throwsA(
        isA<OpenAiReportingException>()
            .having(
              (error) => error.failure,
              'failure',
              OpenAiReportingFailure.authentication,
            )
            .having(
              (error) => error.toString(),
              'safe message',
              isNot(contains('sensitive provider detail')),
            ),
      ),
    );
  });

  test('distinguishes missing organization permission', () async {
    final transport = _FakeTransport({
      '/v1/organization/usage/completions': [
        const ProviderHttpResponse(
          statusCode: HttpStatus.forbidden,
          headers: {},
          body: '{"error":"sensitive provider detail"}',
        ),
      ],
      '/v1/organization/costs': [_response(_page())],
    });
    final client = OpenAiReportingClient(transport: transport);

    await expectLater(
      client.fetchDailyReports(
        adminApiKey: 'secret-admin-key',
        start: start,
        end: end,
      ),
      throwsA(
        isA<OpenAiReportingException>()
            .having(
              (error) => error.failure,
              'failure',
              OpenAiReportingFailure.permissionDenied,
            )
            .having(
              (error) => error.toString(),
              'safe message',
              isNot(contains('sensitive provider detail')),
            ),
      ),
    );
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
    'object': 'page',
    'data': <Object>[],
    'has_more': hasMore,
    'next_page': nextPage,
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

  @override
  Future<ProviderHttpResponse> get(
    Uri uri, {
    required Map<String, String> headers,
  }) async {
    requests.add(_Request(uri, Map.unmodifiable(headers)));
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
