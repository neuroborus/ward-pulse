import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../dashboard/dashboard_models.dart';
import '../dashboard/plan_recoveries.dart';
import 'poll_cadence.dart';
import 'recovery_notifications.dart';
import 'recovery_wake.dart';

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

/// Tells the reader about windows that came back, then remembers what is spent
/// now.
///
/// Called from both places a fresh snapshot appears — the headless tick and the
/// foreground load — because they are separate paths, exactly as the watch and
/// widget pushes are.
///
/// **Notify first, remember second.** Remembering first would lose a recovery
/// for good if the process died in between: the key is gone and no later poll
/// can see the edge. Notifying first risks a repeat instead, and a repeat costs
/// nothing — the notification is keyed by the window and replaces its own
/// earlier copy. The same property is why the two paths need no lock when they
/// overlap: they read the same list, report the same windows, and write the
/// same answer.
///
/// [notifications] off silences the telling and nothing else: the windows are
/// still tracked and the wake is still booked, because the switch turns off an
/// interruption, not an eye.
///
/// [mockData] empties the list instead of filling it, and reports nothing. Demo
/// windows are invented, so remembering them would make the first live poll
/// after leaving demo mode look like a recovery.
Future<void> syncPlanRecoveries(
  DashboardSnapshot snapshot,
  RecoveryWatchlistStore store,
  RecoveryNotifier notifier,
  RecoveryWakeScheduler wake, {
  bool mockData = false,
  bool notifications = true,
  ReadPlanRecoveries readRecoveries = planRecoveries,
  ReadExhaustedWindows readWindows = exhaustedWindows,
  DateTime Function() now = DateTime.now,
}) async {
  try {
    if (mockData) {
      await store.write(const []);
      await wake.cancel();
      return;
    }
    // An edge needs a past. With nothing remembered there is nothing to have
    // left, and asking the core would serialize the whole snapshot to be told
    // so — on most polls, since most of the time nothing is spent.
    final remembered = await store.read();
    if (notifications && remembered.isNotEmpty) {
      for (final recovery in readRecoveries(snapshot, remembered)) {
        try {
          await notifier.notify(recovery);
        } catch (_) {
          // Each window is reported on its own: a notifier that refuses one
          // must not silence the rest, and must not stop the list below from
          // moving on. A stuck list would go on missing every later window.
        }
      }
    }
    final spent = readWindows(snapshot);
    await store.write(spent);
    // Booked from the reset instant rather than left to the next poll, which
    // the cadence would make up to an interval late. `null` covers every case
    // with nothing to wake for: nothing spent, nothing saying when it rolls,
    // and a reset already behind because the provider has not caught up.
    final soonest = nextResetAmong(snapshot, spent, after: now());
    if (soonest == null) {
      await wake.cancel();
    } else {
      // Never sooner than the poll floor after this one. A window resetting a
      // minute from now would otherwise send the woken poll straight back to a
      // provider, and `PollCadence` calls its lower bound the strictest hard
      // floor across connections — a wake is not an exemption from it.
      final floor = now().add(
        const Duration(minutes: PollCadence.minRefreshMinutes),
      );
      await wake.scheduleAt(soonest.isBefore(floor) ? floor : soonest);
    }
  } catch (_) {
    // A poll must never crash over bookkeeping; the next one writes the list
    // again.
  }
}
