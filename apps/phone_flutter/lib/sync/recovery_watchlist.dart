import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../dashboard/dashboard_models.dart';
import '../dashboard/plan_recoveries.dart';
import 'poll_cadence.dart';
import 'recovery_notifications.dart';
import 'recovery_wake.dart';
import 'automatic_poll.dart';

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
/// can see the edge. Notifying first risks a repeat instead. Stable IDs replace
/// the visible post but do not prevent another sound or prove no repost.
/// Overlapping isolates can race reads/writes; recovery remains best effort.
///
/// [notifications] off silences the telling and nothing else: the windows are
/// still tracked and the wake is still booked, because the switch turns off an
/// interruption, not an eye.
///
/// [mockData] empties the list instead of filling it, and reports nothing. Demo
/// windows are invented, so remembering them would make the first live poll
/// after leaving demo mode look like a recovery.
///
/// [rethrowFailures] lets a caller with its own per-step guard record an outer
/// storage or scheduling failure. Foreground callers retain the best-effort
/// default.
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
  bool rethrowFailures = false,
  AutomaticPollContext? poll,
  Future<bool> Function()? isCurrent,
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
    if (isCurrent != null && !await isCurrent()) return;
    final observedAccounts = {
      for (final account in snapshot.accounts)
        if (poll == null ||
            (poll.observes(account.connection ?? '') &&
                !poll.retainedAccountIds.values.any(
                  (ids) => ids.contains(account.accountId),
                )))
          account.accountId,
    };
    final partial = poll != null && poll.skipped.isNotEmpty;
    final observedHistory =
        !partial
            ? remembered
            : remembered
                .where((key) => observedAccounts.contains(key.accountId))
                .toList();
    if (notifications &&
        observedHistory.isNotEmpty &&
        poll?.whollySkipped != true) {
      for (final recovery in readRecoveries(snapshot, observedHistory)) {
        if (isCurrent != null && !await isCurrent()) return;
        try {
          await notifier.notify(recovery);
        } catch (_) {
          // Each window is reported on its own: a notifier that refuses one
          // must not silence the rest, and must not stop the list below from
          // moving on. A stuck list would go on missing every later window.
        }
      }
    }
    final protected =
        poll == null || poll.skipped.isEmpty
            ? <WindowKey>[]
            : remembered
                .where((key) => !observedAccounts.contains(key.accountId))
                .toList();
    final spent =
        poll?.whollySkipped == true
            ? remembered
            : [
              ...readWindows(snapshot).where(
                (key) => !partial || observedAccounts.contains(key.accountId),
              ),
              ...protected,
            ];
    if (isCurrent != null && !await isCurrent()) return;
    if (poll?.whollySkipped != true) await store.write(spent);
    // Booked from the reset instant rather than left to the next poll, which
    // the cadence would make up to an interval late. `null` covers every case
    // with nothing to wake for: nothing spent, nothing saying when it rolls,
    // and a reset already behind because the provider has not caught up.
    //
    // Never sooner than the reset floor of the window's own connection, counted
    // from that connection's native start: a denied load, or one that started
    // another connection, must not push the wake back. A load with no such
    // start, such as a manual one, counts the floor from itself.
    final instant = now();
    DateTime? soonest;
    for (final account in snapshot.accounts) {
      final keys = [
        for (final key in spent)
          if (key.accountId == account.accountId) key,
      ];
      final connection =
          account.connection ??
          poll?.retainedAccountIds.entries
              .where((entry) => entry.value.contains(account.accountId))
              .firstOrNull
              ?.key;
      // A reset already behind still counts for a connection this load did not
      // observe if neither its native start nor its last success is as late:
      // the booked wake has not served it, so it stays due instead of being
      // cancelled or replaced by another connection's later reset. A later
      // start, even a failed one, or a later success, such as a manual one,
      // served it.
      final anchor = connection == null ? null : poll?.automaticAt[connection];
      final seen = account.lastSuccessfulSyncAt;
      final overdue =
          anchor != null &&
          !observedAccounts.contains(account.accountId) &&
          account.allowances.any((window) {
            final at = window.resetsAt;
            return at != null &&
                !at.isAfter(instant) &&
                anchor.isBefore(at) &&
                (seen == null || seen.isBefore(at)) &&
                keys.any((key) => key.allowanceId == window.id);
          });
      var due =
          overdue ? instant : nextResetAmong(snapshot, keys, after: instant);
      if (due == null) continue;
      final floor =
          (connection == null ? null : poll?.resetEligibleAt(connection)) ??
          instant.add(const Duration(minutes: PollCadence.minRefreshMinutes));
      if (due.isBefore(floor)) due = floor;
      if (soonest == null || due.isBefore(soonest)) soonest = due;
    }
    if (poll?.origin == AutomaticPollOrigin.resetWake) {
      for (final entry in poll!.skipped.entries) {
        final ids = poll.retainedAccountIds[entry.key] ?? const <String>{};
        DateTime? reset;
        for (final account in snapshot.accounts.where(
          (account) =>
              ids.contains(account.accountId) ||
              account.connection == entry.key,
        )) {
          for (final window in account.allowances) {
            final at = window.resetsAt;
            if (at != null &&
                remembered.any(
                  (key) =>
                      key.accountId == account.accountId &&
                      key.allowanceId == window.id,
                ) &&
                (reset == null || at.isBefore(reset)))
              reset = at;
          }
        }
        final pending = reset != null || (ids.isEmpty && protected.isNotEmpty);
        final eligible = entry.value.nextEligible;
        final due = reset != null && reset.isAfter(eligible) ? reset : eligible;
        if (pending && (soonest == null || due.isBefore(soonest)))
          soonest = due;
      }
    }
    if (isCurrent != null && !await isCurrent()) return;
    if (soonest == null) {
      if (poll?.whollySkipped != true) await wake.cancel();
    } else {
      // Natural resets use the floor above; denied work keeps its native due
      // time rather than adding another full floor after a skipped load.
      await wake.scheduleAt(soonest);
    }
  } catch (error, stackTrace) {
    if (rethrowFailures) {
      Error.throwWithStackTrace(error, stackTrace);
    }
    // A foreground poll must never crash over bookkeeping; the next one writes
    // the list again. Headless sync rethrows into its per-step guard to log it.
  }
}
