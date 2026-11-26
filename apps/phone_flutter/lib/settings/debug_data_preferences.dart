import 'package:flutter_secure_storage/flutter_secure_storage.dart';

abstract interface class DebugDataPreferenceStore {
  Future<bool> readMockDataEnabled();

  Future<void> writeMockDataEnabled(bool value);
}

final class SecureDebugDataPreferenceStore implements DebugDataPreferenceStore {
  SecureDebugDataPreferenceStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static const _key = 'wardpulse.debug.mockData';

  final FlutterSecureStorage _storage;

  @override
  Future<bool> readMockDataEnabled() async {
    return await _storage.read(key: _key) == 'true';
  }

  @override
  Future<void> writeMockDataEnabled(bool value) {
    return _storage.write(key: _key, value: value.toString());
  }
}
