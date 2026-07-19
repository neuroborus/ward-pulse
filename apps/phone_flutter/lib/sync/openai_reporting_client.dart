import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

enum OpenAiReportingFailure {
  authentication,
  permissionDenied,
  rateLimited,
  unavailable,
  invalidResponse,
}

final class OpenAiReportingException implements Exception {
  const OpenAiReportingException(this.failure, {this.details});

  final OpenAiReportingFailure failure;
  final String? details;

  @override
  String toString() => 'OpenAI reporting request failed: ${failure.name}.';
}

final class OpenAiReportingPages {
  const OpenAiReportingPages({required this.usage, required this.costs});

  final List<String> usage;
  final List<String> costs;
}

abstract interface class ProviderHttpTransport {
  Future<ProviderHttpResponse> get(
    Uri uri, {
    required Map<String, String> headers,
  });
}

final class ProviderHttpResponse {
  const ProviderHttpResponse({
    required this.statusCode,
    required this.headers,
    required this.body,
  });

  final int statusCode;
  final Map<String, String> headers;
  final String body;
}

final class IoProviderHttpTransport implements ProviderHttpTransport {
  IoProviderHttpTransport({HttpClient? client})
    : _client = client ?? (HttpClient()..connectionTimeout = _timeout);

  static const _timeout = Duration(seconds: 30);

  final HttpClient _client;

  @override
  Future<ProviderHttpResponse> get(
    Uri uri, {
    required Map<String, String> headers,
  }) async {
    final request = await _client.getUrl(uri).timeout(_timeout);
    headers.forEach(request.headers.set);
    final response = await request.close().timeout(_timeout);
    final responseHeaders = <String, String>{};
    response.headers.forEach((name, values) {
      responseHeaders[name.toLowerCase()] = values.join(',');
    });

    return ProviderHttpResponse(
      statusCode: response.statusCode,
      headers: responseHeaders,
      body: await response.transform(utf8.decoder).join().timeout(_timeout),
    );
  }
}

final class OpenAiReportingClient {
  OpenAiReportingClient({
    ProviderHttpTransport? transport,
    Uri? baseUri,
    Future<void> Function(Duration)? delay,
    double Function()? random,
    DateTime Function()? clock,
  }) : _transport = transport ?? IoProviderHttpTransport(),
       _baseUri = baseUri ?? Uri.parse('https://api.openai.com'),
       _delay = delay ?? Future<void>.delayed,
       _random = random ?? Random().nextDouble,
       _clock = clock ?? DateTime.now;

  static const _maxRetries = 2;

  final ProviderHttpTransport _transport;
  final Uri _baseUri;
  final Future<void> Function(Duration) _delay;
  final double Function() _random;
  final DateTime Function() _clock;

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
      final response = await _getWithRetry(
        _baseUri.replace(path: path, queryParameters: parameters),
        adminApiKey,
      );
      final page = _parsePage(response, path: path);
      pages.add(response.body);
      cursor = page.hasMore ? page.nextPage : null;

      if (page.hasMore &&
          (cursor == null || cursor.isEmpty || !seenCursors.add(cursor))) {
        throw const OpenAiReportingException(
          OpenAiReportingFailure.invalidResponse,
          details: 'Reporting pagination returned a repeated or empty cursor.',
        );
      }
    } while (cursor != null);

    return List.unmodifiable(pages);
  }

  Future<ProviderHttpResponse> _getWithRetry(
    Uri uri,
    String adminApiKey,
  ) async {
    for (var attempt = 0; attempt <= _maxRetries; attempt += 1) {
      final ProviderHttpResponse response;
      try {
        response = await _transport.get(
          uri,
          headers: {'Authorization': 'Bearer $adminApiKey'},
        );
      } on IOException {
        throw OpenAiReportingException(
          OpenAiReportingFailure.unavailable,
          details: '${_endpointLabel(uri.path)} · Network error',
        );
      } on TimeoutException {
        throw OpenAiReportingException(
          OpenAiReportingFailure.unavailable,
          details: '${_endpointLabel(uri.path)} · Request timed out',
        );
      }

      if (response.statusCode == HttpStatus.tooManyRequests &&
          attempt < _maxRetries) {
        await _delay(_retryDelay(response, attempt));
        continue;
      }

      return switch (response.statusCode) {
        HttpStatus.ok => response,
        HttpStatus.unauthorized =>
          throw OpenAiReportingException(
            OpenAiReportingFailure.authentication,
            details: _responseDetails(uri.path, response),
          ),
        HttpStatus.forbidden =>
          throw OpenAiReportingException(
            OpenAiReportingFailure.permissionDenied,
            details: _responseDetails(uri.path, response),
          ),
        HttpStatus.tooManyRequests =>
          throw OpenAiReportingException(
            OpenAiReportingFailure.rateLimited,
            details: _responseDetails(uri.path, response),
          ),
        _ =>
          throw OpenAiReportingException(
            OpenAiReportingFailure.unavailable,
            details: _responseDetails(uri.path, response),
          ),
      };
    }

    throw const OpenAiReportingException(OpenAiReportingFailure.rateLimited);
  }

  Duration _retryDelay(ProviderHttpResponse response, int attempt) {
    final retryAfter =
        response.headers.entries
            .where((entry) => entry.key.toLowerCase() == 'retry-after')
            .map((entry) => entry.value.trim())
            .firstOrNull;
    final seconds = int.tryParse(retryAfter ?? '');
    if (seconds != null && seconds >= 0) {
      return Duration(seconds: seconds);
    }
    if (retryAfter != null) {
      try {
        final until = HttpDate.parse(retryAfter).difference(_clock().toUtc());
        if (!until.isNegative) {
          return until;
        }
      } on FormatException {
        // Fall through to exponential backoff.
      }
    }

    final baseMilliseconds = 1000 * (1 << attempt);
    final jitter = 0.5 + (_random().clamp(0.0, 1.0) * 0.5);
    return Duration(milliseconds: (baseMilliseconds * jitter).round());
  }

  _PageMetadata _parsePage(
    ProviderHttpResponse response, {
    required String path,
  }) {
    final Object? value;
    try {
      value = jsonDecode(response.body);
    } on FormatException {
      throw OpenAiReportingException(
        OpenAiReportingFailure.invalidResponse,
        details: _responseDetails(path, response, reason: 'Invalid JSON'),
      );
    }

    if (value is! Map<String, dynamic>) {
      throw OpenAiReportingException(
        OpenAiReportingFailure.invalidResponse,
        details: _responseDetails(path, response, reason: 'Expected an object'),
      );
    }
    if (value['data'] is! List) {
      throw OpenAiReportingException(
        OpenAiReportingFailure.invalidResponse,
        details: _responseDetails(path, response, reason: 'Missing data array'),
      );
    }
    final hasMore = value['has_more'];
    final nextPage = value['next_page'];
    if (hasMore is! bool) {
      throw OpenAiReportingException(
        OpenAiReportingFailure.invalidResponse,
        details: _responseDetails(
          path,
          response,
          reason: 'Missing pagination flag',
        ),
      );
    }
    if (nextPage != null && nextPage is! String) {
      throw OpenAiReportingException(
        OpenAiReportingFailure.invalidResponse,
        details: _responseDetails(
          path,
          response,
          reason: 'Invalid pagination cursor',
        ),
      );
    }

    return _PageMetadata(hasMore: hasMore, nextPage: nextPage as String?);
  }

  String _responseDetails(
    String path,
    ProviderHttpResponse response, {
    String? reason,
  }) {
    final parts = <String>[
      _endpointLabel(path),
      'HTTP ${response.statusCode}',
      if (_errorCode(response.body) case final code?) code,
      if (_safeToken(response.headers['x-request-id']) case final requestId?)
        'request $requestId',
      if (reason != null) reason,
    ];
    return parts.join(' · ');
  }

  String _endpointLabel(String path) {
    return path.endsWith('/costs') ? 'Costs' : 'Usage';
  }

  String? _errorCode(String body) {
    try {
      final value = jsonDecode(body);
      if (value case {'error': final Map<String, dynamic> error}) {
        return _safeToken(error['code']) ?? _safeToken(error['type']);
      }
    } on FormatException {
      return null;
    }
    return null;
  }

  String? _safeToken(Object? value) {
    if (value is! String || value.length > 128) {
      return null;
    }
    return RegExp(r'^[A-Za-z0-9_.-]+$').hasMatch(value) ? value : null;
  }
}

final class _PageMetadata {
  const _PageMetadata({required this.hasMore, required this.nextPage});

  final bool hasMore;
  final String? nextPage;
}
