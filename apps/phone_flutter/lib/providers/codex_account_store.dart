import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'connection_lifecycle.dart';

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

final class SecureCodexAccountStore
    implements CodexAccountStore, VersionedAccountStore<CodexAccountSession> {
  SecureCodexAccountStore({
    FlutterSecureStorage? storage,
    ConnectionCachePlatform? platform,
  }) : _storage = storage ?? const FlutterSecureStorage(),
       _platform = platform ?? const MethodChannelConnectionCachePlatform();
  static const _sessionKey = 'wardpulse.codex.account-session';
  static const _legacyCompanionKey = 'wardpulse.codex-companion.config';
  final FlutterSecureStorage _storage;
  final ConnectionCachePlatform _platform;
  late final ConnectionCredentialStorage _credentials =
      ConnectionCredentialStorage(
        connection: 'openai.plan',
        legacyKey: _sessionKey,
        storage: _storage,
        platform: _platform,
        principal:
            (encoded) =>
                CodexAccountSession.fromJson(
                  Map<String, dynamic>.from(jsonDecode(encoded) as Map),
                ).accountId.trim(),
      );
  @override
  Future<bool> isCurrent(CredentialVersion expected) =>
      _credentials.isCurrent(expected);
  @override
  Future<R> serializeFetch<R>(Future<R> Function() operation) =>
      _credentials.serializeFetch(operation);
  @override
  Future<VersionedCredential<CodexAccountSession>?> readVersioned() async {
    final value = await _credentials.read();
    return value == null
        ? null
        : VersionedCredential(
          CodexAccountSession.fromJson(
            Map<String, dynamic>.from(jsonDecode(value.value) as Map),
          ),
          value.version,
        );
  }

  @override
  Future<CodexAccountSession?> read() async => (await readVersioned())?.value;
  @override
  Future<void> write(CodexAccountSession value) =>
      _credentials.write(jsonEncode(value.toJson()));
  @override
  Future<void> delete() async {
    await _credentials.delete();
    await _storage.delete(key: _legacyCompanionKey);
  }

  @override
  Future<void> deleteIfCurrent(CredentialVersion expected) =>
      _credentials.delete(expected);
  @override
  Future<CredentialVersion?> refresh(
    CodexAccountSession value,
    CredentialVersion expected,
  ) => _credentials.refresh(jsonEncode(value.toJson()), expected);
  @override
  Future<CredentialVersion> beginReconnect() => _credentials.beginReconnect();
  @override
  Future<bool> completeReconnect(
    CodexAccountSession value,
    CredentialVersion ticket,
  ) => _credentials.completeReconnect(jsonEncode(value.toJson()), ticket);
  @override
  Future<void> cancelReconnect(CredentialVersion ticket) =>
      _credentials.cancelReconnect(ticket);
}

String _requiredString(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! String || value.trim().isEmpty) {
    throw const FormatException('Invalid Codex account session.');
  }
  return value;
}
