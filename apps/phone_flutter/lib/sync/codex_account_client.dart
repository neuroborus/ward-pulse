import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../providers/codex_account_store.dart';

enum CodexAccountFailure {
  authentication,
  permissionDenied,
  rateLimited,
  unavailable,
  invalidResponse,
  cancelled,
}

typedef CodexSessionChanged = Future<void> Function(CodexAccountSession value);

final class CodexAccountException implements Exception {
  const CodexAccountException(this.failure, [this.details]);

  final CodexAccountFailure failure;
  final String? details;
}

final class CodexDeviceCode {
  const CodexDeviceCode({
    required this.verificationUri,
    required this.userCode,
    required this.deviceAuthId,
    required this.pollInterval,
  });

  final Uri verificationUri;
  final String userCode;
  final String deviceAuthId;
  final Duration pollInterval;
}

final class CodexReportResult {
  const CodexReportResult({required this.session, required this.reportJson});

  final CodexAccountSession session;
  final String reportJson;
}

abstract interface class CodexHttpTransport {
  Future<CodexHttpResponse> send(
    String method,
    Uri uri, {
    required Map<String, String> headers,
    String? body,
  });
}

final class CodexHttpResponse {
  const CodexHttpResponse({required this.statusCode, required this.body});

  final int statusCode;
  final String body;
}

final class IoCodexHttpTransport implements CodexHttpTransport {
  IoCodexHttpTransport({HttpClient? client})
    : _client = client ?? (HttpClient()..connectionTimeout = _timeout);

  static const _timeout = Duration(seconds: 30);
  static const _maximumResponseBytes = 1024 * 1024;

  final HttpClient _client;

  @override
  Future<CodexHttpResponse> send(
    String method,
    Uri uri, {
    required Map<String, String> headers,
    String? body,
  }) async {
    final request = await _client.openUrl(method, uri).timeout(_timeout);
    headers.forEach(request.headers.set);
    if (body != null) {
      request.write(body);
    }
    final response = await request.close().timeout(_timeout);
    final bytes = <int>[];
    await for (final chunk in response.timeout(_timeout)) {
      if (bytes.length + chunk.length > _maximumResponseBytes) {
        throw const CodexAccountException(
          CodexAccountFailure.invalidResponse,
          'Response exceeds 1 MiB.',
        );
      }
      bytes.addAll(chunk);
    }

    return CodexHttpResponse(
      statusCode: response.statusCode,
      body: utf8.decode(bytes),
    );
  }
}

final class CodexAccountClient {
  CodexAccountClient({
    CodexHttpTransport? transport,
    Uri? issuer,
    Uri? backend,
    DateTime Function()? clock,
    Future<void> Function(Duration)? delay,
  }) : _transport = transport ?? IoCodexHttpTransport(),
       _issuer = issuer ?? Uri.parse('https://auth.openai.com'),
       _backend = backend ?? Uri.parse('https://chatgpt.com/backend-api'),
       _clock = clock ?? DateTime.now,
       _delay = delay ?? Future<void>.delayed;

  static const _clientId = 'app_EMoamEEZ73f0CkXaXp7hrann';
  static const _loginTimeout = Duration(minutes: 15);
  static const _refreshInterval = Duration(days: 8);
  static const _refreshWindow = Duration(minutes: 5);

  final CodexHttpTransport _transport;
  final Uri _issuer;
  final Uri _backend;
  final DateTime Function() _clock;
  final Future<void> Function(Duration) _delay;

  Future<CodexDeviceCode> requestDeviceCode() async {
    final response = await _send(
      'POST',
      _issuer.resolve('/api/accounts/deviceauth/usercode'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({'client_id': _clientId}),
    );
    _requireSuccess(response, 'Codex sign-in');
    final json = _jsonMap(response.body, 'Codex sign-in');
    final interval = switch (json['interval']) {
      final num value => _integerValue(value),
      final String value => int.tryParse(value),
      _ => null,
    };
    final deviceAuthId = _nonEmptyString(json['device_auth_id']);
    final userCode = _nonEmptyString(json['user_code'] ?? json['usercode']);
    if (deviceAuthId == null || userCode == null || interval == null) {
      throw const CodexAccountException(
        CodexAccountFailure.invalidResponse,
        'Codex sign-in · Invalid device-code response',
      );
    }

    return CodexDeviceCode(
      verificationUri: _issuer.resolve('/codex/device'),
      userCode: userCode,
      deviceAuthId: deviceAuthId,
      pollInterval: Duration(seconds: interval.clamp(1, 30)),
    );
  }

  Future<CodexAccountSession> completeDeviceLogin(
    CodexDeviceCode deviceCode, {
    required Future<void> cancelled,
  }) async {
    final startedAt = _clock().toUtc();
    while (_clock().toUtc().difference(startedAt) < _loginTimeout) {
      final response = await _send(
        'POST',
        _issuer.resolve('/api/accounts/deviceauth/token'),
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode({
          'device_auth_id': deviceCode.deviceAuthId,
          'user_code': deviceCode.userCode,
        }),
      );
      if (response.statusCode == HttpStatus.ok) {
        final json = _jsonMap(response.body, 'Codex sign-in');
        return _exchangeAuthorizationCode(
          authorizationCode: _requiredResponseString(
            json,
            'authorization_code',
            'Codex sign-in',
          ),
          codeVerifier: _requiredResponseString(
            json,
            'code_verifier',
            'Codex sign-in',
          ),
        );
      }
      if (response.statusCode != HttpStatus.forbidden &&
          response.statusCode != HttpStatus.notFound) {
        _requireSuccess(response, 'Codex sign-in');
      }
      final wasCancelled = await Future.any([
        _delay(deviceCode.pollInterval).then((_) => false),
        cancelled.then((_) => true),
      ]);
      if (wasCancelled) {
        throw const CodexAccountException(CodexAccountFailure.cancelled);
      }
    }

    throw const CodexAccountException(
      CodexAccountFailure.authentication,
      'Codex sign-in · Device code expired',
    );
  }

  Future<CodexReportResult> fetchReport(
    CodexAccountSession session, {
    CodexSessionChanged? onSessionChanged,
  }) async {
    var current = session;
    if (_needsRefresh(current)) {
      current = await _refresh(current);
      await onSessionChanged?.call(current);
    }

    try {
      return await _fetchReport(current);
    } on CodexAccountException catch (error) {
      if (error.failure != CodexAccountFailure.authentication) {
        rethrow;
      }
      current = await _refresh(current);
      await onSessionChanged?.call(current);
      return _fetchReport(current);
    }
  }

  Future<void> revoke(CodexAccountSession session) async {
    await _send(
      'POST',
      _issuer.resolve('/oauth/revoke'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({
        'token': session.refreshToken,
        'token_type_hint': 'refresh_token',
        'client_id': _clientId,
      }),
    );
  }

  Future<CodexAccountSession> _exchangeAuthorizationCode({
    required String authorizationCode,
    required String codeVerifier,
  }) async {
    final response = await _send(
      'POST',
      _issuer.resolve('/oauth/token'),
      headers: const {'Content-Type': 'application/x-www-form-urlencoded'},
      body:
          Uri(
            queryParameters: {
              'grant_type': 'authorization_code',
              'code': authorizationCode,
              'redirect_uri':
                  _issuer.resolve('/deviceauth/callback').toString(),
              'client_id': _clientId,
              'code_verifier': codeVerifier,
            },
          ).query,
    );
    _requireSuccess(response, 'Codex sign-in');
    final json = _jsonMap(response.body, 'Codex sign-in');
    final idToken = _requiredResponseString(json, 'id_token', 'Codex sign-in');

    return CodexAccountSession(
      accessToken: _requiredResponseString(
        json,
        'access_token',
        'Codex sign-in',
      ),
      refreshToken: _requiredResponseString(
        json,
        'refresh_token',
        'Codex sign-in',
      ),
      accountId: _accountId(idToken),
      refreshedAt: _clock().toUtc(),
    );
  }

  Future<CodexAccountSession> _refresh(CodexAccountSession session) async {
    final response = await _send(
      'POST',
      _issuer.resolve('/oauth/token'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({
        'client_id': _clientId,
        'grant_type': 'refresh_token',
        'refresh_token': session.refreshToken,
      }),
    );
    _requireRefreshSuccess(response);
    final json = _jsonMap(response.body, 'Codex token refresh');
    final accessToken = _nonEmptyString(json['access_token']);
    if (accessToken == null) {
      throw const CodexAccountException(
        CodexAccountFailure.invalidResponse,
        'Codex token refresh · Missing access token',
      );
    }
    final idToken = _nonEmptyString(json['id_token']);
    final accountId = idToken == null ? session.accountId : _accountId(idToken);
    if (accountId != session.accountId) {
      throw const CodexAccountException(
        CodexAccountFailure.authentication,
        'Codex token refresh · Account changed',
      );
    }

    return CodexAccountSession(
      accessToken: accessToken,
      refreshToken:
          _nonEmptyString(json['refresh_token']) ?? session.refreshToken,
      accountId: accountId,
      refreshedAt: _clock().toUtc(),
    );
  }

  Future<CodexReportResult> _fetchReport(CodexAccountSession session) async {
    final headers = {
      'Accept': 'application/json',
      'Authorization': 'Bearer ${session.accessToken}',
      'ChatGPT-Account-Id': session.accountId,
      'User-Agent': 'wardpulse',
    };
    final responses = await Future.wait([
      _send('GET', _backend.resolve('/wham/usage'), headers: headers),
      _send('GET', _backend.resolve('/wham/profiles/me'), headers: headers),
    ]);
    _requireSuccess(responses[0], 'Codex limits');
    _requireSuccess(responses[1], 'Codex activity');

    final limits = _jsonMap(responses[0].body, 'Codex limits');
    final profile = _jsonMap(responses[1].body, 'Codex activity');
    final report = {
      'generatedAt': _clock().toUtc().toIso8601String(),
      'rateLimits': {'rateLimits': _normalizeRateLimits(limits)},
      'usage': {'dailyUsageBuckets': _normalizeDailyBuckets(profile)},
    };
    return CodexReportResult(session: session, reportJson: jsonEncode(report));
  }

  Map<String, dynamic> _normalizeRateLimits(Map<String, dynamic> response) {
    final rateLimit = _optionalMap(response['rate_limit']);
    final credits = _optionalMap(response['credits']);
    return {
      'limitId': 'codex',
      'limitName': null,
      'primary': _normalizeWindow(rateLimit?['primary_window']),
      'secondary': _normalizeWindow(rateLimit?['secondary_window']),
      'credits':
          credits == null
              ? null
              : {
                'hasCredits': credits['has_credits'] == true,
                'unlimited': credits['unlimited'] == true,
                'balance': _stringValue(credits['balance']),
              },
      'planType': _nonEmptyString(response['plan_type']),
      'rateLimitReachedType': response['rate_limit_reached_type'],
    };
  }

  Map<String, dynamic>? _normalizeWindow(Object? value) {
    final window = _optionalMap(value);
    if (window == null) {
      return null;
    }
    final usedPercent = window['used_percent'];
    final durationSeconds = window['limit_window_seconds'];
    final resetsAt = window['reset_at'];
    final duration =
        durationSeconds is num ? _integerValue(durationSeconds) : null;
    final reset = resetsAt is num ? _integerValue(resetsAt) : null;
    if (usedPercent is! num ||
        !usedPercent.isFinite ||
        usedPercent < 0 ||
        duration == null ||
        duration <= 0 ||
        reset == null) {
      throw const CodexAccountException(
        CodexAccountFailure.invalidResponse,
        'Codex limits · Invalid rate-limit window',
      );
    }

    return {
      'usedPercent': usedPercent,
      'windowDurationMins': (duration + 59) ~/ 60,
      'resetsAt': reset,
    };
  }

  List<Map<String, dynamic>> _normalizeDailyBuckets(
    Map<String, dynamic> response,
  ) {
    final stats = _optionalMap(response['stats']);
    if (stats == null) {
      throw const CodexAccountException(
        CodexAccountFailure.invalidResponse,
        'Codex activity · Missing stats',
      );
    }
    final values = stats['daily_usage_buckets'];
    if (values == null) {
      return const [];
    }
    if (values is! List) {
      throw const CodexAccountException(
        CodexAccountFailure.invalidResponse,
        'Codex activity · Invalid daily usage',
      );
    }

    return values
        .skip(values.length > 31 ? values.length - 31 : 0)
        .map((value) {
          final bucket = _optionalMap(value);
          final startDate = _nonEmptyString(bucket?['start_date']);
          final tokens = bucket?['tokens'];
          final tokenCount = tokens is num ? _integerValue(tokens) : null;
          if (startDate == null || tokenCount == null || tokenCount < 0) {
            throw const CodexAccountException(
              CodexAccountFailure.invalidResponse,
              'Codex activity · Invalid daily usage',
            );
          }
          return {'startDate': startDate, 'tokens': tokenCount};
        })
        .toList(growable: false);
  }

  bool _needsRefresh(CodexAccountSession session) {
    final now = _clock().toUtc();
    final expiresAt = _jwtExpiration(session.accessToken);
    return now.difference(session.refreshedAt) >= _refreshInterval ||
        (expiresAt != null && !expiresAt.isAfter(now.add(_refreshWindow)));
  }

  Future<CodexHttpResponse> _send(
    String method,
    Uri uri, {
    required Map<String, String> headers,
    String? body,
  }) async {
    try {
      return await _transport.send(method, uri, headers: headers, body: body);
    } on CodexAccountException {
      rethrow;
    } on IOException {
      throw CodexAccountException(
        CodexAccountFailure.unavailable,
        '${_endpointLabel(uri)} · Network error',
      );
    } on TimeoutException {
      throw CodexAccountException(
        CodexAccountFailure.unavailable,
        '${_endpointLabel(uri)} · Request timed out',
      );
    } on Object catch (error) {
      throw CodexAccountException(
        CodexAccountFailure.unavailable,
        '${_endpointLabel(uri)} · Unexpected ${error.runtimeType}',
      );
    }
  }

  void _requireSuccess(CodexHttpResponse response, String endpoint) {
    if (response.statusCode == HttpStatus.ok) {
      return;
    }
    final details =
        '$endpoint · HTTP ${response.statusCode}${_safeError(response.body)}';
    if (response.statusCode == HttpStatus.unauthorized) {
      throw CodexAccountException(CodexAccountFailure.authentication, details);
    }
    if (response.statusCode == HttpStatus.forbidden) {
      throw CodexAccountException(
        CodexAccountFailure.permissionDenied,
        details,
      );
    }
    if (response.statusCode == HttpStatus.tooManyRequests) {
      throw CodexAccountException(CodexAccountFailure.rateLimited, details);
    }
    throw CodexAccountException(CodexAccountFailure.unavailable, details);
  }

  void _requireRefreshSuccess(CodexHttpResponse response) {
    if (response.statusCode == HttpStatus.ok) {
      return;
    }
    final code = _safeErrorCode(response.body);
    final details =
        'Codex token refresh · HTTP ${response.statusCode}${code == null ? '' : ' · $code'}';
    if (response.statusCode == HttpStatus.unauthorized ||
        _permanentRefreshErrors.contains(code)) {
      throw CodexAccountException(CodexAccountFailure.authentication, details);
    }
    if (response.statusCode == HttpStatus.forbidden) {
      throw CodexAccountException(
        CodexAccountFailure.permissionDenied,
        details,
      );
    }
    if (response.statusCode == HttpStatus.tooManyRequests) {
      throw CodexAccountException(CodexAccountFailure.rateLimited, details);
    }
    throw CodexAccountException(CodexAccountFailure.unavailable, details);
  }
}

Map<String, dynamic> _jsonMap(String source, String endpoint) {
  final Object? value;
  try {
    value = jsonDecode(source);
  } on FormatException {
    throw CodexAccountException(
      CodexAccountFailure.invalidResponse,
      '$endpoint · Invalid JSON',
    );
  }
  if (value is! Map<String, dynamic>) {
    throw CodexAccountException(
      CodexAccountFailure.invalidResponse,
      '$endpoint · Expected an object',
    );
  }
  return value;
}

Map<String, dynamic>? _optionalMap(Object? value) {
  return value is Map<String, dynamic> ? value : null;
}

String _requiredResponseString(
  Map<String, dynamic> json,
  String key,
  String endpoint,
) {
  final value = _nonEmptyString(json[key]);
  if (value == null) {
    throw CodexAccountException(
      CodexAccountFailure.invalidResponse,
      '$endpoint · Missing $key',
    );
  }
  return value;
}

String? _nonEmptyString(Object? value) {
  return value is String && value.trim().isNotEmpty ? value : null;
}

String? _stringValue(Object? value) {
  return switch (value) {
    final String value when value.isNotEmpty => value,
    final num value => value.toString(),
    _ => null,
  };
}

String _accountId(String idToken) {
  final payload = _jwtPayload(idToken);
  final claims = _optionalMap(payload['https://api.openai.com/auth']);
  final accountId = _nonEmptyString(claims?['chatgpt_account_id']);
  if (accountId == null) {
    throw const CodexAccountException(
      CodexAccountFailure.invalidResponse,
      'Codex sign-in · Missing account identity',
    );
  }
  return accountId;
}

DateTime? _jwtExpiration(String token) {
  try {
    final value = _jwtPayload(token)['exp'];
    final seconds = value is num ? _integerValue(value) : null;
    return seconds != null
        ? DateTime.fromMillisecondsSinceEpoch(seconds * 1000, isUtc: true)
        : null;
  } on CodexAccountException {
    return null;
  }
}

Map<String, dynamic> _jwtPayload(String token) {
  final parts = token.split('.');
  if (parts.length != 3) {
    throw const CodexAccountException(
      CodexAccountFailure.invalidResponse,
      'Codex sign-in · Invalid token',
    );
  }
  try {
    final json = jsonDecode(
      utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
    );
    if (json is Map<String, dynamic>) {
      return json;
    }
  } on FormatException {
    // Converted to a stable response error below.
  }
  throw const CodexAccountException(
    CodexAccountFailure.invalidResponse,
    'Codex sign-in · Invalid token',
  );
}

String _endpointLabel(Uri uri) {
  if (uri.path.endsWith('/usage')) {
    return 'Codex limits';
  }
  if (uri.path.endsWith('/profiles/me')) {
    return 'Codex activity';
  }
  return 'Codex sign-in';
}

String _safeError(String source) {
  final code = _safeErrorCode(source);
  return code == null ? '' : ' · $code';
}

String? _safeErrorCode(String source) {
  try {
    final json = jsonDecode(source);
    final error = json is Map<String, dynamic> ? json['error'] : null;
    final code = switch (error) {
      final Map<String, dynamic> value =>
        _safeToken(value['code']) ?? _safeToken(value['type']),
      final String value => _nonEmptyString(value),
      _ => null,
    };
    return _safeToken(code);
  } on FormatException {
    return null;
  }
}

String? _safeToken(Object? value) {
  return value is String &&
          value.isNotEmpty &&
          value.length <= 80 &&
          _safeTokenPattern.hasMatch(value)
      ? value
      : null;
}

int? _integerValue(num value) {
  return value.isFinite && value == value.truncateToDouble()
      ? value.toInt()
      : null;
}

final _safeTokenPattern = RegExp(r'^[A-Za-z0-9_.-]+$');
const _permanentRefreshErrors = {
  'invalid_grant',
  'refresh_token_expired',
  'refresh_token_reused',
  'refresh_token_revoked',
};
