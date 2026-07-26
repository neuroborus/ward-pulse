import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'provider_connection.dart';

/// Local secret and label storage for plan/platform connections.
abstract interface class ProviderCredentialStore {
  Future<String?> readSecret(ProviderConnectionId id);

  Future<void> writeSecret(ProviderConnectionId id, String value);

  Future<void> deleteSecret(ProviderConnectionId id);

  Future<String?> readLabel(ProviderConnectionId id);

  Future<void> writeLabel(ProviderConnectionId id, String? value);
}

final class SecureProviderCredentialStore implements ProviderCredentialStore {
  SecureProviderCredentialStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  /// Stable keys for OpenAI keep existing installs working.
  static const _legacyOpenAiKey = 'wardpulse.openai.admin-api-key';
  static const _legacyOpenAiLabel = 'wardpulse.openai.admin-api-key.label';

  final FlutterSecureStorage _storage;

  String _secretKey(ProviderConnectionId id) {
    if (id == ProviderConnections.openAiPlatform) {
      return _legacyOpenAiKey;
    }
    return 'wardpulse.${id.storageKey}.secret';
  }

  String _labelKey(ProviderConnectionId id) {
    if (id == ProviderConnections.openAiPlatform) {
      return _legacyOpenAiLabel;
    }
    return 'wardpulse.${id.storageKey}.label';
  }

  @override
  Future<String?> readSecret(ProviderConnectionId id) async {
    final value = (await _storage.read(key: _secretKey(id)))?.trim();
    return value == null || value.isEmpty ? null : value;
  }

  @override
  Future<void> writeSecret(ProviderConnectionId id, String value) {
    return _storage.write(key: _secretKey(id), value: value.trim());
  }

  @override
  Future<void> deleteSecret(ProviderConnectionId id) {
    return Future.wait([
      _storage.delete(key: _secretKey(id)),
      _storage.delete(key: _labelKey(id)),
    ]);
  }

  @override
  Future<String?> readLabel(ProviderConnectionId id) async {
    final value = (await _storage.read(key: _labelKey(id)))?.trim();
    return value == null || value.isEmpty ? null : value;
  }

  @override
  Future<void> writeLabel(ProviderConnectionId id, String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return _storage.delete(key: _labelKey(id));
    }
    return _storage.write(key: _labelKey(id), value: trimmed);
  }
}

final class EmptyProviderCredentialStore implements ProviderCredentialStore {
  const EmptyProviderCredentialStore();

  @override
  Future<String?> readSecret(ProviderConnectionId id) async => null;

  @override
  Future<void> writeSecret(ProviderConnectionId id, String value) async {}

  @override
  Future<void> deleteSecret(ProviderConnectionId id) async {}

  @override
  Future<String?> readLabel(ProviderConnectionId id) async => null;

  @override
  Future<void> writeLabel(ProviderConnectionId id, String? value) async {}
}
