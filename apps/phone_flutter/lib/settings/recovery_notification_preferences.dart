import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Whether WardPulse may say a plan window is usable again.
///
/// One independent recovery switch for all connections. Threshold notification
/// delivery has its own preference; neither control changes recovery tracking.
abstract interface class RecoveryNotificationPreferenceStore {
  Future<bool> read();

  Future<void> write(bool enabled);
}

final class SecureRecoveryNotificationPreferenceStore
    implements RecoveryNotificationPreferenceStore {
  SecureRecoveryNotificationPreferenceStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static const _key = 'wardpulse.recovery.notify';

  final FlutterSecureStorage _storage;

  @override
  Future<bool> read() async =>
      recoveryNotificationsFrom(await _storage.read(key: _key));

  @override
  Future<void> write(bool enabled) {
    return _storage.write(key: _key, value: enabled.toString());
  }
}

/// Reads on and remembers nothing, for hosts with no storage: tests, and builds
/// where a recovery has nowhere to arrive anyway.
final class DefaultRecoveryNotificationPreferenceStore
    implements RecoveryNotificationPreferenceStore {
  const DefaultRecoveryNotificationPreferenceStore();

  @override
  Future<bool> read() async => true;

  @override
  Future<void> write(bool enabled) async {}
}

/// Reads the stored switch, defaulting to on.
///
/// Preserves the existing stored-value parsing. Secure storage errors propagate
/// to callers, which mute delivery without persisting a fallback. Android still
/// gates posts behind its own permission.
bool recoveryNotificationsFrom(String? stored) => stored != 'false';
