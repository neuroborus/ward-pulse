import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

final class ClaudeAccountSession {
  const ClaudeAccountSession({
    required this.accessToken,
    required this.refreshToken,
    required this.expiresAt,
    required this.accountId,
  });

  final String accessToken;
  final String refreshToken;
  final DateTime expiresAt;
  final String accountId;

  Map<String, dynamic> toJson() => {
    'accessToken': accessToken,
    'refreshToken': refreshToken,
    'expiresAt': expiresAt.toUtc().toIso8601String(),
    'accountId': accountId,
  };

  factory ClaudeAccountSession.fromJson(Map<String, dynamic> json) {
    return ClaudeAccountSession(
      accessToken: _requiredString(json, 'accessToken'),
      refreshToken: _requiredString(json, 'refreshToken'),
      expiresAt: DateTime.parse(_requiredString(json, 'expiresAt')).toUtc(),
      accountId: _requiredString(json, 'accountId'),
    );
  }
}

abstract interface class ClaudeAccountStore {
  Future<ClaudeAccountSession?> read();

  Future<void> write(ClaudeAccountSession value);

  Future<void> delete();
}

final class SecureClaudeAccountStore implements ClaudeAccountStore {
  SecureClaudeAccountStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static const _sessionKey = 'wardpulse.claude.account-session';

  final FlutterSecureStorage _storage;

  @override
  Future<ClaudeAccountSession?> read() async {
    final encoded = await _storage.read(key: _sessionKey);
    if (encoded == null) {
      return null;
    }

    final json = jsonDecode(encoded);
    if (json is! Map<String, dynamic>) {
      throw const FormatException('Invalid Claude account session.');
    }
    return ClaudeAccountSession.fromJson(json);
  }

  @override
  Future<void> write(ClaudeAccountSession value) async {
    await _storage.write(key: _sessionKey, value: jsonEncode(value.toJson()));
  }

  @override
  Future<void> delete() async {
    await _storage.delete(key: _sessionKey);
  }
}

String _requiredString(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! String || value.trim().isEmpty) {
    throw const FormatException('Invalid Claude account session.');
  }
  return value;
}
