import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';

import '../providers/claude_account_store.dart';

enum ClaudeAccountFailure {
  authentication,
  permissionDenied,
  rateLimited,
  unavailable,
  invalidResponse,
  cancelled,
}

typedef ClaudeSessionChanged =
    Future<void> Function(ClaudeAccountSession value);

final class ClaudeAccountException implements Exception {
  const ClaudeAccountException(this.failure, [this.details]);

  final ClaudeAccountFailure failure;
  final String? details;
}

/// Pending PKCE authorization for Claude Code-compatible OAuth.
final class ClaudeAuthorizationRequest {
  const ClaudeAuthorizationRequest({
    required this.authorizationUri,
    required this.codeVerifier,
    required this.state,
  });

  final Uri authorizationUri;
  final String codeVerifier;
  final String state;
}

final class ClaudeReportResult {
  const ClaudeReportResult({required this.session, required this.reportJson});

  final ClaudeAccountSession session;
  final String reportJson;
}

abstract interface class ClaudeHttpTransport {
  Future<ClaudeHttpResponse> send(
    String method,
    Uri uri, {
    required Map<String, String> headers,
    String? body,
    Duration? timeout,
  });
}

final class ClaudeHttpResponse {
  const ClaudeHttpResponse({required this.statusCode, required this.body});

  final int statusCode;
  final String body;
}

final class IoClaudeHttpTransport implements ClaudeHttpTransport {
  IoClaudeHttpTransport({HttpClient? client})
    : _client = client ?? (HttpClient()..connectionTimeout = _defaultTimeout);

  static const _defaultTimeout = Duration(seconds: 30);
  static const _maximumResponseBytes = 1024 * 1024;

  final HttpClient _client;

  @override
  Future<ClaudeHttpResponse> send(
    String method,
    Uri uri, {
    required Map<String, String> headers,
    String? body,
    Duration? timeout,
  }) async {
    final deadline = timeout ?? _defaultTimeout;
    try {
      final request = await _client.openUrl(method, uri).timeout(deadline);
      headers.forEach(request.headers.set);
      if (body != null) {
        final bytes = utf8.encode(body);
        request.contentLength = bytes.length;
        request.add(bytes);
      }
      final response = await request.close().timeout(deadline);
      final bytes = <int>[];
      await for (final chunk in response.timeout(deadline)) {
        if (bytes.length + chunk.length > _maximumResponseBytes) {
          throw const ClaudeAccountException(
            ClaudeAccountFailure.invalidResponse,
            'Response exceeds 1 MiB.',
          );
        }
        bytes.addAll(chunk);
      }

      return ClaudeHttpResponse(
        statusCode: response.statusCode,
        body: utf8.decode(bytes),
      );
    } on ClaudeAccountException {
      rethrow;
    } on TimeoutException {
      throw ClaudeAccountException(
        ClaudeAccountFailure.unavailable,
        '${_endpointLabel(uri)} · Timed out',
      );
    } on SocketException {
      throw ClaudeAccountException(
        ClaudeAccountFailure.unavailable,
        '${_endpointLabel(uri)} · Network unavailable',
      );
    } on ArgumentError catch (error) {
      throw ClaudeAccountException(
        ClaudeAccountFailure.invalidResponse,
        '${_endpointLabel(uri)} · Invalid request (${error.message})',
      );
    }
  }
}

/// Phone-owned Claude Code OAuth (PKCE). Anthropic has no device-code grant yet.
final class ClaudeAccountClient {
  ClaudeAccountClient({
    ClaudeHttpTransport? transport,
    Uri? authorizeUri,
    Uri? tokenUri,
    Uri? apiBase,
    DateTime Function()? clock,
    Random? random,
  }) : _transport = transport ?? IoClaudeHttpTransport(),
       _authorizeUri =
           authorizeUri ?? Uri.parse('https://claude.ai/oauth/authorize'),
       _tokenUri =
           tokenUri ?? Uri.parse('https://platform.claude.com/v1/oauth/token'),
       _apiBase = apiBase ?? Uri.parse('https://api.anthropic.com'),
       _clock = clock ?? DateTime.now,
       _random = random ?? Random.secure();

  static const clientId = '9d1c250a-e61b-44d9-88ed-5944d1962f5e';
  static const redirectUri = 'https://platform.claude.com/oauth/code/callback';
  static const _scope =
      'user:inference user:profile user:sessions:claude_code user:mcp_servers';
  static const _tokenTimeout = Duration(seconds: 120);
  static const _refreshWindow = Duration(minutes: 5);

  final ClaudeHttpTransport _transport;
  final Uri _authorizeUri;
  final Uri _tokenUri;
  final Uri _apiBase;
  final DateTime Function() _clock;
  final Random _random;

  ClaudeAuthorizationRequest beginAuthorization() {
    final verifier = _randomBase64Url(32);
    final state = _randomBase64Url(32);
    final challenge = base64UrlEncode(
      sha256.convert(utf8.encode(verifier)).bytes,
    ).replaceAll('=', '');
    final uri = _authorizeUri.replace(
      queryParameters: {
        'code': 'true',
        'client_id': clientId,
        'response_type': 'code',
        'redirect_uri': redirectUri,
        'scope': _scope,
        'code_challenge': challenge,
        'code_challenge_method': 'S256',
        'state': state,
      },
    );
    return ClaudeAuthorizationRequest(
      authorizationUri: uri,
      codeVerifier: verifier,
      state: state,
    );
  }

  Future<ClaudeAccountSession> exchangeAuthorizationCode({
    required ClaudeAuthorizationRequest request,
    required String pastedCode,
  }) async {
    final parsed = _parsePastedCode(pastedCode, expectedState: request.state);
    final body =
        Uri(
          queryParameters: {
            'grant_type': 'authorization_code',
            'code': parsed.code,
            'redirect_uri': redirectUri,
            'client_id': clientId,
            'code_verifier': request.codeVerifier,
            'state': parsed.state,
          },
        ).query;
    final response = await _transport.send(
      'POST',
      _tokenUri,
      headers: const {
        'Content-Type': 'application/x-www-form-urlencoded',
        'Accept': 'application/json',
      },
      body: body,
      timeout: _tokenTimeout,
    );
    _requireSuccess(response, 'Claude sign-in');
    return _sessionFromTokenResponse(response.body, label: 'Claude sign-in');
  }

  Future<ClaudeReportResult> fetchReport(
    ClaudeAccountSession session, {
    required ClaudeSessionChanged onSessionChanged,
  }) async {
    var current = session;
    if (_needsRefresh(current)) {
      current = await refresh(current);
      await onSessionChanged(current);
    }

    try {
      return await _reportFor(current);
    } on ClaudeAccountException catch (error) {
      if (error.failure != ClaudeAccountFailure.authentication) {
        rethrow;
      }
      current = await refresh(current);
      await onSessionChanged(current);
      return _reportFor(current);
    }
  }

  Future<ClaudeAccountSession> refresh(ClaudeAccountSession session) async {
    final body =
        Uri(
          queryParameters: {
            'grant_type': 'refresh_token',
            'refresh_token': session.refreshToken,
            'client_id': clientId,
          },
        ).query;
    final response = await _transport.send(
      'POST',
      _tokenUri,
      headers: const {
        'Content-Type': 'application/x-www-form-urlencoded',
        'Accept': 'application/json',
      },
      body: body,
      timeout: _tokenTimeout,
    );
    // Invalid/rotated refresh tokens come back as 401/403 — drop the session.
    if (response.statusCode == 401 || response.statusCode == 403) {
      throw const ClaudeAccountException(
        ClaudeAccountFailure.authentication,
        'Claude sign-in · Session expired',
      );
    }
    _requireSuccess(response, 'Claude token refresh');
    // Anthropic rotates refresh tokens; never keep the previous one.
    return _sessionFromTokenResponse(
      response.body,
      label: 'Claude token refresh',
      fallbackAccountId: session.accountId,
    );
  }

  Future<ClaudeReportResult> _reportFor(ClaudeAccountSession session) async {
    final usage = await _fetchUsage(session.accessToken);
    return ClaudeReportResult(
      session: session,
      reportJson: jsonEncode({
        ...usage,
        'accountId': session.accountId,
        'generatedAt': _clock().toUtc().toIso8601String(),
      }),
    );
  }

  Future<Map<String, dynamic>> _fetchUsage(String accessToken) async {
    final response = await _transport.send(
      'GET',
      _apiBase.replace(path: '/api/oauth/usage'),
      headers: {
        'Authorization': 'Bearer $accessToken',
        'anthropic-beta': 'oauth-2025-04-20',
        'anthropic-version': '2023-06-01',
        'User-Agent': 'claude-code/2.0.0',
        'Accept': 'application/json',
      },
    );
    _requireSuccess(response, 'Claude usage');
    return _jsonMap(response.body, 'Claude usage');
  }

  bool _needsRefresh(ClaudeAccountSession session) {
    return !session.expiresAt.isAfter(_clock().toUtc().add(_refreshWindow));
  }

  ClaudeAccountSession _sessionFromTokenResponse(
    String body, {
    required String label,
    String? fallbackAccountId,
  }) {
    final json = _jsonMap(body, label);
    final accessToken = _nonEmptyString(json['access_token']);
    final refreshToken = _nonEmptyString(json['refresh_token']);
    if (accessToken == null || refreshToken == null) {
      throw ClaudeAccountException(
        ClaudeAccountFailure.invalidResponse,
        '$label · Missing tokens',
      );
    }
    final expiresIn = switch (json['expires_in']) {
      final num value => value.toInt(),
      final String value => int.tryParse(value),
      _ => null,
    };
    if (expiresIn == null || expiresIn <= 0) {
      throw ClaudeAccountException(
        ClaudeAccountFailure.invalidResponse,
        '$label · Missing expires_in',
      );
    }
    final account = json['account'];
    final accountId =
        (account is Map<String, dynamic>
            ? _nonEmptyString(account['uuid'])
            : null) ??
        fallbackAccountId ??
        'claude-local';
    return ClaudeAccountSession(
      accessToken: accessToken,
      refreshToken: refreshToken,
      expiresAt: _clock().toUtc().add(Duration(seconds: expiresIn)),
      accountId: accountId,
    );
  }

  void _requireSuccess(ClaudeHttpResponse response, String label) {
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return;
    }
    throw ClaudeAccountException(
      _failureForStatus(response.statusCode),
      '$label · HTTP ${response.statusCode}',
    );
  }

  ClaudeAccountFailure _failureForStatus(int status) {
    return switch (status) {
      401 => ClaudeAccountFailure.authentication,
      403 => ClaudeAccountFailure.permissionDenied,
      429 => ClaudeAccountFailure.rateLimited,
      _ when status >= 500 => ClaudeAccountFailure.unavailable,
      _ => ClaudeAccountFailure.invalidResponse,
    };
  }

  Map<String, dynamic> _jsonMap(String body, String label) {
    try {
      final json = jsonDecode(body);
      if (json is Map<String, dynamic>) {
        return json;
      }
    } on FormatException {
      // Fall through.
    }
    throw ClaudeAccountException(
      ClaudeAccountFailure.invalidResponse,
      '$label · Invalid JSON',
    );
  }

  String? _nonEmptyString(Object? value) {
    if (value is! String) {
      return null;
    }
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  String _randomBase64Url(int byteLength) {
    final bytes = List<int>.generate(
      byteLength,
      (_) => _random.nextInt(256),
      growable: false,
    );
    return base64UrlEncode(bytes).replaceAll('=', '');
  }

  ({String code, String state}) _parsePastedCode(
    String pasted, {
    required String expectedState,
  }) {
    final trimmed = pasted.trim();
    if (trimmed.isEmpty) {
      throw const ClaudeAccountException(
        ClaudeAccountFailure.invalidResponse,
        'Claude sign-in · Paste the authorization code',
      );
    }
    final hash = trimmed.indexOf('#');
    if (hash >= 0) {
      final code = trimmed.substring(0, hash).trim();
      final state = trimmed.substring(hash + 1).trim();
      if (code.isEmpty || state.isEmpty) {
        throw const ClaudeAccountException(
          ClaudeAccountFailure.invalidResponse,
          'Claude sign-in · Invalid authorization code',
        );
      }
      if (state != expectedState) {
        throw const ClaudeAccountException(
          ClaudeAccountFailure.invalidResponse,
          'Claude sign-in · State mismatch — restart sign-in',
        );
      }
      return (code: code, state: state);
    }
    return (code: trimmed, state: expectedState);
  }
}

String _endpointLabel(Uri uri) {
  final path = uri.path.isEmpty ? '/' : uri.path;
  return path;
}
