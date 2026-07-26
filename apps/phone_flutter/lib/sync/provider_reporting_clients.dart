import 'dart:convert';

import 'provider_reporting.dart';

final class AnthropicReportingClient {
  AnthropicReportingClient({ProviderReportingHttp? http, Uri? baseUri})
    : _http = http ?? ProviderReportingHttp(),
      _baseUri = baseUri ?? Uri.parse('https://api.anthropic.com');

  final ProviderReportingHttp _http;
  final Uri _baseUri;

  Future<({List<String> usage, List<String> costs})> fetchDailyReports({
    required String adminApiKey,
    required DateTime start,
    required DateTime end,
  }) async {
    final usage = await _fetchPages(
      path: '/v1/organizations/usage_report/messages',
      adminApiKey: adminApiKey,
      start: start,
      end: end,
      groupByModel: true,
      label: 'Usage',
    );
    final costs = await _fetchPages(
      path: '/v1/organizations/cost_report',
      adminApiKey: adminApiKey,
      start: start,
      end: end,
      groupByModel: false,
      label: 'Costs',
    );
    return (usage: usage, costs: costs);
  }

  Future<List<String>> _fetchPages({
    required String path,
    required String adminApiKey,
    required DateTime start,
    required DateTime end,
    required bool groupByModel,
    required String label,
  }) async {
    final pages = <String>[];
    final seen = <String>{};
    String? cursor;

    do {
      final parameters = <String, dynamic>{
        'starting_at': start.toUtc().toIso8601String(),
        'ending_at': end.toUtc().toIso8601String(),
        'bucket_width': '1d',
        'limit': '31',
        if (groupByModel) 'group_by[]': 'model',
        if (cursor != null) 'page': cursor,
      };
      final response = await _http.get(
        _baseUri.replace(path: path, queryParameters: parameters),
        headers: {'x-api-key': adminApiKey, 'anthropic-version': '2023-06-01'},
        label: label,
      );
      pages.add(response.body);
      final page = decodeReportObject(response.body);
      final hasMore = page['has_more'] == true;
      final next = page['next_page'];
      cursor = hasMore && next is String && next.isNotEmpty ? next : null;
      if (cursor != null && !seen.add(cursor)) {
        throw const ProviderReportingException(
          ProviderReportingFailure.invalidResponse,
          details: 'Repeated pagination cursor',
        );
      }
    } while (cursor != null);

    return List.unmodifiable(pages);
  }
}

final class CursorPlanClient {
  CursorPlanClient({ProviderReportingHttp? http, Uri? baseUri})
    : _http = http ?? ProviderReportingHttp(),
      _baseUri = baseUri ?? Uri.parse('https://cursor.com');

  final ProviderReportingHttp _http;
  final Uri _baseUri;

  Future<String> fetchUsageSummary({required String sessionToken}) async {
    final response = await _http.get(
      _baseUri.replace(path: '/api/usage-summary'),
      headers: {'Cookie': 'WorkosCursorSessionToken=$sessionToken'},
      label: 'Cursor usage',
    );
    return response.body;
  }
}

final class CursorPlatformClient {
  CursorPlatformClient({
    ProviderReportingHttp? http,
    Uri? baseUri,
    DateTime Function()? clock,
  }) : _http = http ?? ProviderReportingHttp(),
       _baseUri = baseUri ?? Uri.parse('https://api.cursor.com'),
       _clock = clock ?? DateTime.now;

  /// Daily usage window kept in step with the dashboard usage history.
  static const _usageWindow = Duration(days: 14);

  static const _spendPageSize = 100;

  /// Stops runaway paging when a team reports an implausible page count.
  static const _maxSpendPages = 100;

  final ProviderReportingHttp _http;
  final Uri _baseUri;
  final DateTime Function() _clock;

  Future<({List<String> dailyUsage, List<String> spend})> fetchReports({
    required String adminApiKey,
  }) async {
    final now = _clock().toUtc();
    final end = now.millisecondsSinceEpoch;
    final start = now.subtract(_usageWindow).millisecondsSinceEpoch;
    final auth = encodeBasicAuth(adminApiKey);

    final daily = await _http.post(
      _baseUri.replace(path: '/teams/daily-usage-data'),
      headers: {'Authorization': auth, 'Content-Type': 'application/json'},
      body: jsonEncode({'startDate': start, 'endDate': end}),
      label: 'Cursor daily usage',
    );
    final spend = await _fetchSpendPages(auth: auth);
    return (dailyUsage: [daily.body], spend: spend);
  }

  Future<List<String>> _fetchSpendPages({required String auth}) async {
    final pages = <String>[];
    var page = 1;

    while (true) {
      final response = await _http.post(
        _baseUri.replace(path: '/teams/spend'),
        headers: {'Authorization': auth, 'Content-Type': 'application/json'},
        body: jsonEncode({'page': page, 'pageSize': _spendPageSize}),
        label: 'Cursor spend',
      );
      pages.add(response.body);

      final body = decodeReportObject(response.body);
      final totalPages = switch (body['totalPages']) {
        final num value => value.toInt(),
        // Treat a missing or unreadable count as the last page.
        _ => page,
      };
      if (page >= totalPages || page >= _maxSpendPages) {
        break;
      }
      page += 1;
    }

    return List.unmodifiable(pages);
  }
}
