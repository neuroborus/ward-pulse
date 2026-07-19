import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

final class CodexAccountSession {
  const CodexAccountSession({
    required this.accessToken,
    required this.refreshToken,
    required this.accountId,
    required this.refreshedAt,
  });

  final String accessToken;
  final String refreshToken;
  final String accountId;
  final DateTime refreshedAt;

  Map<String, dynamic> toJson() => {
    'accessToken': accessToken,
    'refreshToken': refreshToken,
    'accountId': accountId,
    'refreshedAt': refreshedAt.toUtc().toIso8601String(),
  };

  factory CodexAccountSession.fromJson(Map<String, dynamic> json) {
    return CodexAccountSession(
      accessToken: _requiredString(json, 'accessToken'),
      refreshToken: _requiredString(json, 'refreshToken'),
      accountId: _requiredString(json, 'accountId'),
      refreshedAt: DateTime.parse(_requiredString(json, 'refreshedAt')).toUtc(),
    );
  }
}

abstract interface class CodexAccountStore {
  Future<CodexAccountSession?> read();

  Future<void> write(CodexAccountSession value);

  Future<void> delete();
}

final class SecureCodexAccountStore implements CodexAccountStore {
  SecureCodexAccountStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static const _sessionKey = 'wardpulse.codex.account-session';
  static const _legacyCompanionKey = 'wardpulse.codex-companion.config';

  final FlutterSecureStorage _storage;

  @override
  Future<CodexAccountSession?> read() async {
    final encoded = await _storage.read(key: _sessionKey);
    if (encoded == null) {
      await _storage.delete(key: _legacyCompanionKey);
      return null;
    }

    final json = jsonDecode(encoded);
    if (json is! Map<String, dynamic>) {
      throw const FormatException('Invalid Codex account session.');
    }
    return CodexAccountSession.fromJson(json);
  }

  @override
  Future<void> write(CodexAccountSession value) async {
    await _storage.write(key: _sessionKey, value: jsonEncode(value.toJson()));
    await _storage.delete(key: _legacyCompanionKey);
  }

  @override
  Future<void> delete() async {
    await _storage.delete(key: _sessionKey);
    await _storage.delete(key: _legacyCompanionKey);
  }
}

String _requiredString(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! String || value.trim().isEmpty) {
    throw const FormatException('Invalid Codex account session.');
  }
  return value;
}
