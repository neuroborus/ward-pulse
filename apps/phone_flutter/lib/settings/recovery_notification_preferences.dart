import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Whether WardPulse may say a plan window is usable again.
///
/// One switch for the whole product, not a rule per connection: a recovery has
/// no threshold to set — it either happened or it did not.
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
/// On until told otherwise: interrupting is the point of the feature, an unset
/// store means the reader has not opinionated yet, and Android still gates the
/// post behind its own permission.
bool recoveryNotificationsFrom(String? stored) => stored != 'false';
