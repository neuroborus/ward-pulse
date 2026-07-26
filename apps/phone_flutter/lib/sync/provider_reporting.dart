import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import '../dashboard/dashboard_models.dart';
import 'provider_sync_logger.dart';

enum ProviderReportingFailure {
  authentication,
  permissionDenied,
  rateLimited,
  unavailable,
  invalidResponse,
}

/// Reporting failure with details that never carry raw provider payloads.
final class ProviderReportingException implements Exception {
  const ProviderReportingException(this.failure, {this.details});

  final ProviderReportingFailure failure;
  final String? details;

  @override
  String toString() => 'Provider reporting failed: ${failure.name}.';
}

abstract interface class ProviderHttpTransport {
  Future<ProviderHttpResponse> get(
    Uri uri, {
    required Map<String, String> headers,
  });

  Future<ProviderHttpResponse> post(
    Uri uri, {
    required Map<String, String> headers,
    String? body,
  });
}

final class ProviderHttpResponse {
  const ProviderHttpResponse({
    required this.statusCode,
    required this.headers,
    required this.body,
  });

  final int statusCode;

  /// Lower-cased response header names.
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
  }) {
    return _send(() => _client.getUrl(uri), headers);
  }

  @override
  Future<ProviderHttpResponse> post(
    Uri uri, {
    required Map<String, String> headers,
    String? body,
  }) {
    return _send(() => _client.postUrl(uri), headers, body: body);
  }

  Future<ProviderHttpResponse> _send(
    Future<HttpClientRequest> Function() open,
    Map<String, String> headers, {
    String? body,
  }) async {
    final request = await open().timeout(_timeout);
    headers.forEach(request.headers.set);
    if (body != null) {
      // Declared length keeps the request unchunked for provider gateways.
      final bytes = utf8.encode(body);
      request.contentLength = bytes.length;
      request.add(bytes);
    }
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

/// Shared retry and status mapping for every provider reporting client.
final class ProviderReportingHttp {
  ProviderReportingHttp({
    ProviderHttpTransport? transport,
    Future<void> Function(Duration)? delay,
    double Function()? random,
    DateTime Function()? clock,
  }) : _transport = transport ?? IoProviderHttpTransport(),
       _delay = delay ?? Future<void>.delayed,
       _random = random ?? Random().nextDouble,
       _clock = clock ?? DateTime.now;

  static const _maxRetries = 2;

  /// A provider-mandated wait longer than this is left to the next scheduled
  /// sync, which is minutes away, instead of stalling the refresh in progress.
  static const _maxRetryDelay = Duration(seconds: 5);

  final ProviderHttpTransport _transport;
  final Future<void> Function(Duration) _delay;
  final double Function() _random;
  final DateTime Function() _clock;

  Future<ProviderHttpResponse> get(
    Uri uri, {
    required Map<String, String> headers,
    required String label,
  }) {
    return _send(() => _transport.get(uri, headers: headers), label: label);
  }

  Future<ProviderHttpResponse> post(
    Uri uri, {
    required Map<String, String> headers,
    String? body,
    required String label,
  }) {
    return _send(
      () => _transport.post(uri, headers: headers, body: body),
      label: label,
    );
  }

  Future<ProviderHttpResponse> _send(
    Future<ProviderHttpResponse> Function() request, {
    required String label,
  }) async {
    for (var attempt = 0; ; attempt += 1) {
      final ProviderHttpResponse response;
      try {
        response = await request();
      } on IOException {
        throw ProviderReportingException(
          ProviderReportingFailure.unavailable,
          details: '$label · Network error',
        );
      } on TimeoutException {
        throw ProviderReportingException(
          ProviderReportingFailure.unavailable,
          details: '$label · Request timed out',
        );
      }

      if (response.statusCode == HttpStatus.tooManyRequests &&
          attempt < _maxRetries) {
        final wait = _retryDelay(response, attempt);
        if (wait <= _maxRetryDelay) {
          await _delay(wait);
          continue;
        }
      }

      return switch (response.statusCode) {
        HttpStatus.ok => response,
        HttpStatus.unauthorized =>
          throw ProviderReportingException(
            ProviderReportingFailure.authentication,
            details: reportResponseDetails(label, response),
          ),
        HttpStatus.forbidden =>
          throw ProviderReportingException(
            ProviderReportingFailure.permissionDenied,
            details: reportResponseDetails(label, response),
          ),
        HttpStatus.tooManyRequests =>
          throw ProviderReportingException(
            ProviderReportingFailure.rateLimited,
            details: reportResponseDetails(label, response),
          ),
        _ =>
          throw ProviderReportingException(
            ProviderReportingFailure.unavailable,
            details: reportResponseDetails(label, response),
          ),
      };
    }
  }

  Duration _retryDelay(ProviderHttpResponse response, int attempt) {
    final retryAfter = response.headers['retry-after']?.trim();
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
}

/// Failure details safe to log: endpoint, status, and sanitized provider tokens.
String reportResponseDetails(
  String label,
  ProviderHttpResponse response, {
  String? reason,
}) {
  final parts = <String>[
    label,
    'HTTP ${response.statusCode}',
    if (_errorCode(response.body) case final code?) code,
    if (_safeToken(response.headers['x-request-id']) case final requestId?)
      'request $requestId',
    if (reason != null) reason,
  ];
  return parts.join(' · ');
}

/// Decodes a provider response body that must carry a JSON object.
Map<String, dynamic> decodeReportObject(String body) {
  final Object? decoded;
  try {
    decoded = jsonDecode(body);
  } on FormatException catch (error) {
    throw ProviderReportingException(
      ProviderReportingFailure.invalidResponse,
      details: 'Invalid JSON · ${error.message}',
    );
  }
  if (decoded is! Map<String, dynamic>) {
    throw const ProviderReportingException(
      ProviderReportingFailure.invalidResponse,
      details: 'Expected a JSON object',
    );
  }
  return decoded;
}

ProviderSyncEvent reportingSyncEvent(ProviderReportingFailure failure) {
  return switch (failure) {
    ProviderReportingFailure.authentication =>
      ProviderSyncEvent.authenticationRequired,
    ProviderReportingFailure.permissionDenied =>
      ProviderSyncEvent.permissionDenied,
    ProviderReportingFailure.rateLimited => ProviderSyncEvent.rateLimited,
    ProviderReportingFailure.unavailable => ProviderSyncEvent.unavailable,
    ProviderReportingFailure.invalidResponse =>
      ProviderSyncEvent.invalidResponse,
  };
}

DashboardSyncIssue reportingIssue(ProviderReportingFailure failure) {
  return switch (failure) {
    ProviderReportingFailure.authentication =>
      DashboardSyncIssue.authentication,
    ProviderReportingFailure.permissionDenied =>
      DashboardSyncIssue.permissionDenied,
    ProviderReportingFailure.rateLimited => DashboardSyncIssue.rateLimited,
    ProviderReportingFailure.unavailable =>
      DashboardSyncIssue.providerUnavailable,
    ProviderReportingFailure.invalidResponse =>
      DashboardSyncIssue.invalidResponse,
  };
}

String encodeBasicAuth(String username) {
  final token = base64Encode(utf8.encode('$username:'));
  return 'Basic $token';
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

final _safeTokenPattern = RegExp(r'^[A-Za-z0-9_.-]+$');

String? _safeToken(Object? value) {
  if (value is! String || value.length > 128) {
    return null;
  }
  return _safeTokenPattern.hasMatch(value) ? value : null;
}
