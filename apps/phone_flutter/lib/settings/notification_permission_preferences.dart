import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// An attempted bootstrap, not a history of Android's permission decisions.
abstract interface class NotificationPermissionAttemptStore {
  Future<bool> read();
  Future<void> write(bool attempted);
}

final class SecureNotificationPermissionAttemptStore
    implements NotificationPermissionAttemptStore {
  SecureNotificationPermissionAttemptStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;
  static const _key = 'wardpulse.notifications.permissionAttempted';

  @override
  Future<bool> read() async {
    final value = await _storage.read(key: _key);
    if (value == null) return false;
    if (value == 'true') return true;
    throw const FormatException('Invalid notification permission bookkeeping.');
  }

  @override
  Future<void> write(bool attempted) =>
      attempted
          ? _storage.write(key: _key, value: 'true')
          : _storage.delete(key: _key);
}
