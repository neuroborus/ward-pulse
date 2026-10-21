import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'connection_lifecycle.dart';

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

final class SecureClaudeAccountStore
    implements ClaudeAccountStore, VersionedAccountStore<ClaudeAccountSession> {
  SecureClaudeAccountStore({
    FlutterSecureStorage? storage,
    ConnectionCachePlatform? platform,
  }) : _storage = storage ?? const FlutterSecureStorage(),
       _platform = platform ?? const MethodChannelConnectionCachePlatform();
  static const _sessionKey = 'wardpulse.claude.account-session';
  final FlutterSecureStorage _storage;
  final ConnectionCachePlatform _platform;
  late final ConnectionCredentialStorage _credentials =
      ConnectionCredentialStorage(
        connection: 'anthropic.plan',
        legacyKey: _sessionKey,
        storage: _storage,
        platform: _platform,
        principal:
            (encoded) =>
                ClaudeAccountSession.fromJson(
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
  Future<VersionedCredential<ClaudeAccountSession>?> readVersioned() async {
    final value = await _credentials.read();
    return value == null
        ? null
        : VersionedCredential(
          ClaudeAccountSession.fromJson(
            Map<String, dynamic>.from(jsonDecode(value.value) as Map),
          ),
          value.version,
        );
  }

  @override
  Future<ClaudeAccountSession?> read() async => (await readVersioned())?.value;
  @override
  Future<void> write(ClaudeAccountSession value) =>
      _credentials.write(jsonEncode(value.toJson()));
  @override
  Future<void> delete() async {
    await _credentials.delete();
  }

  @override
  Future<void> deleteIfCurrent(CredentialVersion expected) =>
      _credentials.delete(expected);
  @override
  Future<CredentialVersion?> refresh(
    ClaudeAccountSession value,
    CredentialVersion expected,
  ) => _credentials.refresh(jsonEncode(value.toJson()), expected);
  @override
  Future<CredentialVersion> beginReconnect() => _credentials.beginReconnect();
  @override
  Future<bool> completeReconnect(
    ClaudeAccountSession value,
    CredentialVersion ticket,
  ) => _credentials.completeReconnect(jsonEncode(value.toJson()), ticket);
  @override
  Future<void> cancelReconnect(CredentialVersion ticket) =>
      _credentials.cancelReconnect(ticket);
}

String _requiredString(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! String || value.trim().isEmpty) {
    throw const FormatException('Invalid Claude account session.');
  }
  return value;
}
