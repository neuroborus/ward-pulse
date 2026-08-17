import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../dashboard/dashboard_models.dart';
import '../dashboard/plan_recoveries.dart';

/// The plan windows that were spent when the phone last looked.
///
/// A recovery is an edge, and an edge needs a past. The process does not
/// survive between polls, so the past lives here — as the core's own window
/// keys, never as a second idea of what "exhausted" means.
abstract interface class RecoveryWatchlistStore {
  Future<List<WindowKey>> read();

  Future<void> write(List<WindowKey> keys);
}

final class SecureRecoveryWatchlistStore implements RecoveryWatchlistStore {
  SecureRecoveryWatchlistStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static const _key = 'wardpulse.recovery.exhaustedWindows';

  final FlutterSecureStorage _storage;

  @override
  Future<List<WindowKey>> read() async {
    final stored = await _storage.read(key: _key);
    if (stored == null) {
      return const [];
    }
    return decodeWindowKeys(stored);
  }

  @override
  Future<void> write(List<WindowKey> keys) {
    return _storage.write(key: _key, value: encodeWindowKeys(keys));
  }
}

/// Remembers nothing, for hosts with no storage to speak of: tests and any
/// build where a recovery would have nowhere to arrive.
final class DisabledRecoveryWatchlistStore implements RecoveryWatchlistStore {
  const DisabledRecoveryWatchlistStore();

  @override
  Future<List<WindowKey>> read() async => const [];

  @override
  Future<void> write(List<WindowKey> keys) async {}
}

/// Records which windows [snapshot] reports as spent.
///
/// Called from both places a fresh snapshot appears — the headless tick and the
/// foreground load — because they are separate paths, exactly as the watch and
/// widget pushes are. Failures are swallowed: a snapshot the phone could not
/// remember costs one missed recovery, never a crashed poll.
///
/// [mockData] empties the list instead of filling it. Demo windows are invented,
/// so remembering them would make the first live poll after leaving demo mode
/// look like a recovery — a notification about something that never ran out.
Future<void> rememberExhaustedWindows(
  DashboardSnapshot snapshot,
  RecoveryWatchlistStore store, {
  bool mockData = false,
}) async {
  try {
    await store.write(mockData ? const [] : exhaustedWindows(snapshot));
  } catch (_) {
    // Nothing to say here: the next poll writes the list again.
  }
}
