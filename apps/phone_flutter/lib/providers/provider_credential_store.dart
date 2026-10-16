import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'provider_connection.dart';
import 'connection_lifecycle.dart';

/// Local secret and label storage for plan/platform connections.
abstract interface class ProviderCredentialStore {
  Future<String?> readSecret(ProviderConnectionId id);

  Future<void> writeSecret(ProviderConnectionId id, String value);

  Future<void> deleteSecret(ProviderConnectionId id);

  Future<String?> readLabel(ProviderConnectionId id);

  Future<void> writeLabel(ProviderConnectionId id, String? value);
}

abstract interface class ReconnectProviderCredentialStore {
  Future<CredentialVersion> beginReconnect(ProviderConnectionId id);
  Future<bool> completeReconnect(
    ProviderConnectionId id,
    String value,
    CredentialVersion ticket,
  );
  Future<void> cancelReconnect(
    ProviderConnectionId id,
    CredentialVersion ticket,
  );
}

abstract interface class LegacyProviderCredentialCleanup {
  Future<void> deleteLegacySecret(ProviderConnectionId id);
}

final class SecureProviderCredentialStore
    implements
        ProviderCredentialStore,
        ReconnectProviderCredentialStore,
        LegacyProviderCredentialCleanup {
  SecureProviderCredentialStore({
    FlutterSecureStorage? storage,
    ConnectionCachePlatform? platform,
  }) : _storage = storage ?? const FlutterSecureStorage(),
       _platform = platform ?? const MethodChannelConnectionCachePlatform();

  /// Stable keys for OpenAI keep existing installs working.
  static const _legacyOpenAiKey = 'wardpulse.openai.admin-api-key';
  static const _legacyOpenAiLabel = 'wardpulse.openai.admin-api-key.label';

  final FlutterSecureStorage _storage;
  final ConnectionCachePlatform _platform;
  bool _isOAuth(ProviderConnectionId id) =>
      id == ProviderConnections.codexPlan ||
      id == ProviderConnections.claudePlan;
  ConnectionCredentialStorage _credentials(ProviderConnectionId id) =>
      ConnectionCredentialStorage(
        connection: id.storageKey,
        legacyKey: _secretKey(id),
        storage: _storage,
        platform: _platform,
        principal: (value) => value.trim(),
      );
  Future<CredentialVersion?> readVersion(ProviderConnectionId id) async =>
      (await _credentials(id).read())?.version;
  @override
  Future<CredentialVersion> beginReconnect(ProviderConnectionId id) =>
      _credentials(id).beginReconnect();
  @override
  Future<bool> completeReconnect(
    ProviderConnectionId id,
    String value,
    CredentialVersion ticket,
  ) => _credentials(id).completeReconnect(value.trim(), ticket);
  @override
  Future<void> cancelReconnect(
    ProviderConnectionId id,
    CredentialVersion ticket,
  ) => _credentials(id).cancelReconnect(ticket);
  @override
  Future<void> deleteLegacySecret(ProviderConnectionId id) =>
      _credentials(id).deleteLegacyPastedSecret();

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
    final value =
        (_isOAuth(id)
                ? await _storage.read(key: _secretKey(id))
                : (await _credentials(id).read())?.value)
            ?.trim();
    return value == null || value.isEmpty ? null : value;
  }

  @override
  Future<void> writeSecret(ProviderConnectionId id, String value) {
    return _isOAuth(id)
        ? _storage.write(key: _secretKey(id), value: value.trim())
        : _credentials(id).write(value.trim());
  }

  @override
  Future<void> deleteSecret(ProviderConnectionId id) async {
    if (_isOAuth(id)) {
      await deleteLegacySecret(id);
    } else {
      await _credentials(id).delete();
    }
    await _storage.delete(key: _labelKey(id));
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
