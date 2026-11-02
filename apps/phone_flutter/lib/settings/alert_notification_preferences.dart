import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Delivery only; configured thresholds remain independent on Providers.
abstract interface class AlertNotificationPreferenceStore {
  Future<bool> read();
  Future<void> write(bool enabled);
}

final class SecureAlertNotificationPreferenceStore
    implements AlertNotificationPreferenceStore {
  SecureAlertNotificationPreferenceStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static const _key = 'wardpulse.alerts.notify';
  final FlutterSecureStorage _storage;

  @override
  Future<bool> read() async {
    final stored = await _storage.read(key: _key);
    // Unset is on. Unrecognized stored data cannot authorize a post.
    return stored == null || stored == 'true';
  }

  @override
  Future<void> write(bool enabled) =>
      _storage.write(key: _key, value: enabled.toString());
}

final class DefaultAlertNotificationPreferenceStore
    implements AlertNotificationPreferenceStore {
  const DefaultAlertNotificationPreferenceStore();

  @override
  Future<bool> read() async => true;

  @override
  Future<void> write(bool enabled) async {}
}
