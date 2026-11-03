import 'dart:convert';

import '../providers/cursor_session_token.dart';
import 'provider_reporting.dart';
import 'report_period.dart';

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
    if (!start.isBefore(end))
      return (usage: const <String>[], costs: const <String>[]);

    final utcEnd = end.toUtc();
    final midnight = DateTime.utc(utcEnd.year, utcEnd.month, utcEnd.day);
    // Cost selection compares daily bucket ends, including today's next midnight.
    final costMidnight =
        utcEnd == midnight ? midnight : midnight.add(const Duration(days: 1));
    final costEnd = costMidnight.add(const Duration(seconds: 1));
    final usage = <String>[];
    if (start.isBefore(midnight)) {
      usage.addAll(
        await _fetchPages(
          path: '/v1/organizations/usage_report/messages',
          adminApiKey: adminApiKey,
          start: start,
          end: midnight,
          bucketWidth: '1d',
          limit: 31,
          groupByModel: true,
          label: 'Usage',
        ),
      );
    }
    usage.addAll(
      await _fetchPages(
        path: '/v1/organizations/usage_report/messages',
        adminApiKey: adminApiKey,
        start: start.isAfter(midnight) ? start : midnight,
        end: utcEnd,
        bucketWidth: '1m',
        limit: 1440,
        groupByModel: true,
        label: 'Usage',
      ),
    );
    final costs = await _fetchPages(
      path: '/v1/organizations/cost_report',
      adminApiKey: adminApiKey,
      start: start,
      end: costEnd,
      bucketWidth: '1d',
      limit: 31,
      groupByModel: false,
      label: 'Costs',
    );
    return (usage: List<String>.unmodifiable(usage), costs: costs);
  }

  Future<List<String>> _fetchPages({
    required String path,
    required String adminApiKey,
    required DateTime start,
    required DateTime end,
    required String bucketWidth,
    required int limit,
    required bool groupByModel,
    required String label,
  }) async {
    if (!start.isBefore(end)) return const [];

    final pages = <String>[];
    final seen = <String>{};
    String? cursor;

    do {
      final parameters = <String, dynamic>{
        'starting_at': start.toUtc().toIso8601String(),
        'ending_at': end.toUtc().toIso8601String(),
        'bucket_width': bucketWidth,
        'limit': '$limit',
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
      if (hasMore) {
        if (next is! String || next.isEmpty) {
          throw const ProviderReportingException(
            ProviderReportingFailure.invalidResponse,
            details: 'Invalid pagination cursor',
          );
        }
        cursor = next;
      } else {
        cursor = null;
      }
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
      headers: {'Cookie': '$cursorSessionCookieName=$sessionToken'},
      label: 'Cursor usage',
    );
    return response.body;
  }
}

final class CursorPlatformClient {
  CursorPlatformClient({ProviderReportingHttp? http, Uri? baseUri})
    : _http = http ?? ProviderReportingHttp(),
      _baseUri = baseUri ?? Uri.parse('https://api.cursor.com');

  /// Daily usage window kept in step with the dashboard usage history.
  static const _usageWindow = Duration(days: 14);

  static const _eventPageSize = 1000;

  /// Stops runaway paging when a team reports an implausible page count.
  static const _maxEventPages = 100;

  final ProviderReportingHttp _http;
  final Uri _baseUri;

  Future<({List<String> dailyUsage, List<String> usageEvents})> fetchReports({
    required String adminApiKey,
    required ReportPeriodBounds period,
  }) async {
    final end = period.endExclusiveMs;
    final start = end - _usageWindow.inMilliseconds;
    final auth = encodeBasicAuth(adminApiKey);

    final daily = await _http.post(
      _baseUri.replace(path: '/teams/daily-usage-data'),
      headers: {'Authorization': auth, 'Content-Type': 'application/json'},
      body: jsonEncode({'startDate': start, 'endDate': end}),
      label: 'Cursor daily usage',
    );
    final events =
        period.requestStartMs < end
            ? await _fetchUsageEventPages(auth: auth, period: period)
            : const <String>[];
    return (dailyUsage: [daily.body], usageEvents: events);
  }

  Future<List<String>> _fetchUsageEventPages({
    required String auth,
    required ReportPeriodBounds period,
  }) async {
    final pages = <String>[];
    int? advertisedPages;
    int? advertisedRows;
    var rows = 0;

    for (var page = 1; page <= _maxEventPages; page++) {
      final response = await _http.post(
        _baseUri.replace(path: '/teams/filtered-usage-events'),
        headers: {'Authorization': auth, 'Content-Type': 'application/json'},
        body: jsonEncode({
          'startDate': period.requestStartMs,
          'endDate': period.endExclusiveMs - 1,
          'page': page,
          'pageSize': _eventPageSize,
        }),
        label: 'Cursor usage events',
      );
      final body = decodeReportObject(response.body);
      // Inspect exact numeric lexemes too: a fractional echo can round to an
      // integer during jsonDecode. Quoted JSON strings are consumed unchanged.
      final lexemes = decodeReportObject(
        response.body.replaceAllMapped(
          _jsonStringOrNumber,
          (match) => match[0]!.startsWith('"') ? match[0]! : '"${match[0]}"',
        ),
      );
      final events = body['usageEvents'];
      final pagination = body['pagination'];
      final echo = body['period'];
      if (events is! List || pagination is! Map || echo is! Map) {
        throw _invalidEventPagination;
      }
      final pageLexemes = lexemes['pagination'] as Map;
      final periodLexemes = lexemes['period'] as Map;
      final total = _eventInteger(
        body['totalUsageEventsCount'],
        lexemes['totalUsageEventsCount'],
      );
      final count = _eventInteger(
        pagination['numPages'],
        pageLexemes['numPages'],
      );
      final current = _eventInteger(
        pagination['currentPage'],
        pageLexemes['currentPage'],
      );
      final size = _eventInteger(
        pagination['pageSize'],
        pageLexemes['pageSize'],
      );
      final next = pagination['hasNextPage'];
      final previous = pagination['hasPreviousPage'];
      if (total == null ||
          total < 0 ||
          count == null ||
          current == null ||
          size != _eventPageSize ||
          events.length > _eventPageSize ||
          next is! bool ||
          previous is! bool ||
          _eventInteger(echo['startDate'], periodLexemes['startDate']) !=
              period.requestStartMs ||
          _eventInteger(echo['endDate'], periodLexemes['endDate']) !=
              period.endExclusiveMs - 1) {
        throw _invalidEventPagination;
      }
      final terminalEmpty =
          page == 1 &&
          total == 0 &&
          events.isEmpty &&
          !next &&
          !previous &&
          (count == 0 || count == 1) &&
          (current == 0 || current == 1);
      if (!terminalEmpty &&
          (count < 1 ||
              current != page ||
              current > count ||
              previous != (current > 1) ||
              next != (current < count))) {
        throw _invalidEventPagination;
      }
      if ((advertisedPages != null && advertisedPages != count) ||
          (advertisedRows != null && advertisedRows != total)) {
        throw _invalidEventPagination;
      }
      advertisedPages = count;
      advertisedRows = total;
      rows += events.length;
      if (rows > total || (!next && rows != total)) {
        throw _invalidEventPagination;
      }
      // Preserve decimal lexemes; metadata inspection must never rewrite pages.
      pages.add(response.body);
      if (!next) return List.unmodifiable(pages);
    }
    throw _invalidEventPagination;
  }

  static int? _eventInteger(Object? value, Object? lexeme) {
    if (value is! num || lexeme is! String) return null;
    final match = _decimalNumber.firstMatch(lexeme);
    if (match == null) return null;
    final fraction = match[3] ?? '';
    var digits = '${match[2]}$fraction'.replaceFirst(RegExp(r'^0+'), '');
    if (digits.isEmpty) return 0;
    final exponent = int.tryParse(match[4] ?? '0');
    if (exponent == null ||
        exponent < -digits.length ||
        exponent > fraction.length + 19)
      return null;
    final scale = fraction.length - exponent;
    if (scale > 0) {
      if (scale > digits.length || !digits.endsWith('0' * scale)) return null;
      digits = digits.substring(0, digits.length - scale);
    } else if (scale < 0) {
      if (digits.length - scale > 19) return null;
      digits += '0' * -scale;
    }
    return int.tryParse('${match[1]}$digits');
  }

  static final _jsonStringOrNumber = RegExp(
    r'"(?:[^"\\]|\\.)*"|-?(?:0|[1-9][0-9]*)(?:\.[0-9]+)?(?:[eE][+-]?[0-9]+)?',
  );
  static final _decimalNumber = RegExp(
    r'^(-?)([0-9]+)(?:\.([0-9]+))?(?:[eE]([+-]?[0-9]+))?$',
  );

  static const _invalidEventPagination = ProviderReportingException(
    ProviderReportingFailure.invalidResponse,
    details: 'Invalid Cursor usage-event pagination',
  );
}
