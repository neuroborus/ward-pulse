import 'provider_reporting.dart';

final class OpenAiReportingPages {
  const OpenAiReportingPages({required this.usage, required this.costs});

  final List<String> usage;
  final List<String> costs;
}

final class OpenAiReportingClient {
  OpenAiReportingClient({ProviderReportingHttp? http, Uri? baseUri})
    : _http = http ?? ProviderReportingHttp(),
      _baseUri = baseUri ?? Uri.parse('https://api.openai.com');

  final ProviderReportingHttp _http;
  final Uri _baseUri;

  Future<OpenAiReportingPages> fetchDailyReports({
    required String adminApiKey,
    required DateTime start,
    required DateTime end,
  }) async {
    final usage = _fetchPages(
      path: '/v1/organization/usage/completions',
      adminApiKey: adminApiKey,
      start: start,
      end: end,
      groupByModel: true,
    );
    final costs = _fetchPages(
      path: '/v1/organization/costs',
      adminApiKey: adminApiKey,
      start: start,
      end: end,
      groupByModel: false,
    );
    final pages = await Future.wait([usage, costs]);

    return OpenAiReportingPages(usage: pages[0], costs: pages[1]);
  }

  Future<List<String>> _fetchPages({
    required String path,
    required String adminApiKey,
    required DateTime start,
    required DateTime end,
    required bool groupByModel,
  }) async {
    final label = _endpointLabel(path);
    final pages = <String>[];
    final seenCursors = <String>{};
    String? cursor;

    do {
      final parameters = <String, dynamic>{
        'start_time': '${start.toUtc().millisecondsSinceEpoch ~/ 1000}',
        'end_time': '${end.toUtc().millisecondsSinceEpoch ~/ 1000}',
        'bucket_width': '1d',
        'limit': '31',
        if (groupByModel) 'group_by': const ['model'],
        if (cursor != null) 'page': cursor,
      };
      final response = await _http.get(
        _baseUri.replace(path: path, queryParameters: parameters),
        headers: {'Authorization': 'Bearer $adminApiKey'},
        label: label,
      );
      final page = _parsePage(response, label: label);
      pages.add(response.body);
      cursor = page.hasMore ? page.nextPage : null;

      if (page.hasMore &&
          (cursor == null || cursor.isEmpty || !seenCursors.add(cursor))) {
        throw ProviderReportingException(
          ProviderReportingFailure.invalidResponse,
          details: reportResponseDetails(
            label,
            response,
            reason: 'Repeated or empty pagination cursor',
          ),
        );
      }
    } while (cursor != null);

    return List.unmodifiable(pages);
  }

  _PageMetadata _parsePage(
    ProviderHttpResponse response, {
    required String label,
  }) {
    ProviderReportingException invalid(String reason) {
      return ProviderReportingException(
        ProviderReportingFailure.invalidResponse,
        details: reportResponseDetails(label, response, reason: reason),
      );
    }

    final Map<String, dynamic> page;
    try {
      page = decodeReportObject(response.body);
    } on ProviderReportingException catch (error) {
      throw invalid(error.details ?? 'Invalid response');
    }
    if (page['data'] is! List) {
      throw invalid('Missing data array');
    }
    final hasMore = page['has_more'];
    if (hasMore is! bool) {
      throw invalid('Missing pagination flag');
    }
    final nextPage = page['next_page'];
    if (nextPage != null && nextPage is! String) {
      throw invalid('Invalid pagination cursor');
    }

    return _PageMetadata(hasMore: hasMore, nextPage: nextPage as String?);
  }

  String _endpointLabel(String path) {
    return path.endsWith('/costs') ? 'Costs' : 'Usage';
  }
}

final class _PageMetadata {
  const _PageMetadata({required this.hasMore, required this.nextPage});

  final bool hasMore;
  final String? nextPage;
}
