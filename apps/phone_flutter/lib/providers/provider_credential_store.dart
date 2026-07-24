import 'package:flutter_secure_storage/flutter_secure_storage.dart';

abstract interface class ProviderCredentialStore {
  Future<String?> readOpenAiAdminKey();

  Future<void> writeOpenAiAdminKey(String value);

  Future<void> deleteOpenAiAdminKey();

  /// Plain display metadata for the OpenAI Platform Admin API key.
  ///
  /// Stored beside the credential reference, never concatenated into the key
  /// value and never sent to the watch.
  Future<String?> readOpenAiAdminKeyLabel();

  Future<void> writeOpenAiAdminKeyLabel(String? value);
}

final class SecureProviderCredentialStore implements ProviderCredentialStore {
  SecureProviderCredentialStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static const _openAiAdminKey = 'wardpulse.openai.admin-api-key';
  static const _openAiAdminKeyLabel = 'wardpulse.openai.admin-api-key.label';

  final FlutterSecureStorage _storage;

  @override
  Future<String?> readOpenAiAdminKey() async {
    final value = (await _storage.read(key: _openAiAdminKey))?.trim();
    return value == null || value.isEmpty ? null : value;
  }

  @override
  Future<void> writeOpenAiAdminKey(String value) {
    return _storage.write(key: _openAiAdminKey, value: value.trim());
  }

  @override
  Future<void> deleteOpenAiAdminKey() {
    return Future.wait([
      _storage.delete(key: _openAiAdminKey),
      _storage.delete(key: _openAiAdminKeyLabel),
    ]);
  }

  @override
  Future<String?> readOpenAiAdminKeyLabel() async {
    final value = (await _storage.read(key: _openAiAdminKeyLabel))?.trim();
    return value == null || value.isEmpty ? null : value;
  }

  @override
  Future<void> writeOpenAiAdminKeyLabel(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return _storage.delete(key: _openAiAdminKeyLabel);
    }
    return _storage.write(key: _openAiAdminKeyLabel, value: trimmed);
  }
}

final class EmptyProviderCredentialStore implements ProviderCredentialStore {
  const EmptyProviderCredentialStore();

  @override
  Future<String?> readOpenAiAdminKey() async => null;

  @override
  Future<void> writeOpenAiAdminKey(String value) async {}

  @override
  Future<void> deleteOpenAiAdminKey() async {}

  @override
  Future<String?> readOpenAiAdminKeyLabel() async => null;

  @override
  Future<void> writeOpenAiAdminKeyLabel(String? value) async {}
}
