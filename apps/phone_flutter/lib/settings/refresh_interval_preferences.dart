import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../sync/poll_cadence.dart';

/// Global refresh interval chosen in Settings (minutes).
final class RefreshIntervalPreference {
  const RefreshIntervalPreference({
    this.minutes = PollCadence.defaultRefreshMinutes,
  });

  final int minutes;

  Duration get interval => Duration(minutes: minutes);
}

abstract interface class RefreshIntervalPreferenceStore {
  Future<RefreshIntervalPreference> read();

  Future<void> write(RefreshIntervalPreference value);
}

final class SecureRefreshIntervalPreferenceStore
    implements RefreshIntervalPreferenceStore {
  SecureRefreshIntervalPreferenceStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static const _key = 'wardpulse.refresh.intervalMinutes';

  final FlutterSecureStorage _storage;

  @override
  Future<RefreshIntervalPreference> read() async {
    final parsed = int.tryParse(await _storage.read(key: _key) ?? '');
    if (parsed == null) {
      return const RefreshIntervalPreference();
    }
    return RefreshIntervalPreference(minutes: PollCadence.clampMinutes(parsed));
  }

  @override
  Future<void> write(RefreshIntervalPreference value) {
    return _storage.write(
      key: _key,
      value: PollCadence.clampMinutes(value.minutes).toString(),
    );
  }
}

final class DefaultRefreshIntervalPreferenceStore
    implements RefreshIntervalPreferenceStore {
  const DefaultRefreshIntervalPreferenceStore();

  @override
  Future<RefreshIntervalPreference> read() async =>
      const RefreshIntervalPreference();

  @override
  Future<void> write(RefreshIntervalPreference value) async {}
}
