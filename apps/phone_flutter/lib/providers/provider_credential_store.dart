import 'package:flutter_secure_storage/flutter_secure_storage.dart';

abstract interface class ProviderCredentialStore {
  Future<String?> readOpenAiAdminKey();

  Future<void> writeOpenAiAdminKey(String value);

  Future<void> deleteOpenAiAdminKey();
}

final class SecureProviderCredentialStore implements ProviderCredentialStore {
  SecureProviderCredentialStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static const _openAiAdminKey = 'wardpulse.openai.admin-api-key';

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
    return _storage.delete(key: _openAiAdminKey);
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
}
