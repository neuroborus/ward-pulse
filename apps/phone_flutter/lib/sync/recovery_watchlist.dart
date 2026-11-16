import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../dashboard/dashboard_models.dart';
import '../dashboard/plan_recoveries.dart';
import '../providers/connection_lifecycle.dart';
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

/// Writes only the captured observations' partitions, including empty ones.
abstract interface class PartitionedRecoveryWatchlistStore
    implements RecoveryWatchlistStore {
  Future<({List<WindowKey> keys, Map<WindowKey, DateTime> resets})> readOwners(
    Set<HistoryOwner?> owners,
  );
  Future<void> writeObserved(
    List<WindowKey> keys,
    Set<HistoryOwner?> owners, {
    Map<WindowKey, DateTime> resets = const {},
  });
}

final class SecureRecoveryWatchlistStore
    implements RecoveryWatchlistStore, PartitionedRecoveryWatchlistStore {
  SecureRecoveryWatchlistStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static const _key = 'wardpulse.recovery.exhaustedWindows';

  final FlutterSecureStorage _storage;

  String _ownerKey(HistoryOwner? owner) =>
      owner == null
          ? _key
          : '$_key.owner.${base64Url.encode(utf8.encode(jsonEncode(owner.toJson())))}';

  @override
  Future<List<WindowKey>> read() async {
    final stored = await _storage.readAll();
    final result = <WindowKey>[];
    for (final entry in stored.entries) {
      if (entry.key != _key && !entry.key.startsWith('$_key.owner.')) continue;
      // A misplaced key cannot import another partition's history.
      result.addAll(
        decodeWindowKeys(
          entry.value,
        ).where((key) => _ownerKey(key.historyOwner) == entry.key),
      );
    }
    return result;
  }

  @override
  Future<({List<WindowKey> keys, Map<WindowKey, DateTime> resets})> readOwners(
    Set<HistoryOwner?> owners,
  ) async {
    final result = <WindowKey>[];
    final resets = <WindowKey, DateTime>{};
    for (final owner in owners) {
      final stored = await _storage.read(key: _ownerKey(owner));
      if (stored == null) continue;
      final keys = decodeWindowKeys(stored);
      if (keys.isEmpty) continue;
      final values = jsonDecode(stored) as List<dynamic>;
      for (var i = 0; i < keys.length; i++) {
        final key = keys[i];
        if (key.historyOwner != owner) continue;
        result.add(key);
        final value = (values[i] as Map<String, dynamic>)['resetsAt'];
        final reset = value is String ? DateTime.tryParse(value) : null;
        if (reset != null) resets[key] = reset;
      }
    }
    return (keys: result, resets: resets);
  }

  @override
  Future<void> write(List<WindowKey> keys) => writeObserved(keys, {
    if (keys.isEmpty) null,
    for (final key in keys) key.historyOwner,
  });

  @override
  Future<void> writeObserved(
    List<WindowKey> keys,
    Set<HistoryOwner?> owners, {
    Map<WindowKey, DateTime> resets = const {},
  }) async {
    for (final owner in owners) {
      final partition = keys.where((key) => key.historyOwner == owner).toList();
      final values = jsonDecode(encodeWindowKeys(partition)) as List<dynamic>;
      for (var i = 0; i < partition.length; i++) {
        final reset = resets[partition[i]];
        if (reset != null)
          (values[i] as Map<String, dynamic>)['resetsAt'] =
              reset.toUtc().toIso8601String();
      }
      await _storage.write(key: _ownerKey(owner), value: jsonEncode(values));
    }
  }
}

/// Reconcile captured evidence only. Never read today's credentials to relabel
/// a snapshot obtained earlier, including a skipped or retained observation.
Map<String, HistoryOwner?> _capturedOwners(
  DashboardSnapshot snapshot,
  AutomaticPollContext? poll,
) {
  final versions = <String, CredentialVersion>{};
  void add(String connection, CredentialVersion version) {
    final previous = versions[connection];
    if (previous != null &&
        (!previous.sameCache(version) ||
            HistoryOwner.fromVersion(connection, previous) !=
                HistoryOwner.fromVersion(connection, version)))
      throw const FormatException('Conflicting recovery provenance.');
    versions[connection] = version;
  }

  snapshot.connectionVersions.forEach(
    (id, values) => add(id, CredentialVersion(values)),
  );
  for (final outcome in snapshot.reportingOutcomes) {
    final version = outcome.credentialVersion;
    if (version != null) add(outcome.connection.storageKey, version);
  }
  for (final entry
      in poll?.admittedVersions.entries ??
          <MapEntry<String, CredentialVersion>>[]) {
    add(entry.key, entry.value);
  }
  for (final entry
      in poll?.skipped.entries ?? <MapEntry<String, AutomaticPollSkipped>>[]) {
    add(entry.key, entry.value.version);
  }
  final owners = {
    for (final entry in versions.entries)
      entry.key: HistoryOwner.fromVersion(entry.key, entry.value),
  };
  for (final account in snapshot.accounts) {
    final connection = account.connection;
    if (connection == null) {
      if (account.historyOwner != null)
        throw const FormatException('Unqualified recovery owner.');
      continue;
    }
    if (account.historyOwner != owners[connection])
      throw const FormatException('Conflicting recovery owner.');
    owners.putIfAbsent(connection, () => null);
  }
  return owners;
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
/// [mockData] clears only unbound demo/legacy history and reports nothing.
/// Qualified live partitions survive; demo observations never bind an owner.
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
    if (isCurrent != null && !await isCurrent()) return;
    if (mockData) {
      // Demo data cannot establish or clear a qualified live owner's history.
      final liveHistory =
          (await store.read())
              .where((key) => key.historyOwner != null)
              .toList();
      if (isCurrent != null && !await isCurrent()) return;
      if (store is PartitionedRecoveryWatchlistStore) {
        await store.writeObserved(const [], {null});
      } else {
        await store.write(liveHistory);
      }
      if (isCurrent != null && !await isCurrent()) return;
      if (liveHistory.isEmpty) await wake.cancel();
      return;
    }
    final owners = _capturedOwners(snapshot, poll);
    final observedOwners = <HistoryOwner?>{
      for (final entry in owners.entries)
        if (poll?.observes(entry.key) != false &&
            poll?.retainedAccountIds[entry.key]?.isNotEmpty != true)
          entry.value,
      if (owners.isEmpty) null,
    };
    // An edge needs a past. With nothing remembered there is nothing to have
    // left, and asking the core would serialize the whole snapshot to be told
    // so — on most polls, since most of the time nothing is spent.
    final capturedHistory =
        store is PartitionedRecoveryWatchlistStore
            ? await store.readOwners({null, ...owners.values})
            : (keys: await store.read(), resets: <WindowKey, DateTime>{});
    final remembered =
        capturedHistory.keys
            .where(
              (key) =>
                  key.historyOwner == null ||
                  owners.containsValue(key.historyOwner),
            )
            .toList();
    if (isCurrent != null && !await isCurrent()) return;
    final observedAccounts = {
      for (final account in snapshot.accounts)
        if (poll == null ||
            (poll.observes(account.connection ?? '') &&
                !(account.connection == null
                    ? poll.retainedAccountIds.values.any(
                      (ids) => ids.contains(account.accountId),
                    )
                    : poll.retainedAccountIds[account.connection]?.contains(
                          account.accountId,
                        ) ==
                        true)))
          (accountId: account.accountId, historyOwner: account.historyOwner),
    };
    bool observed(WindowKey key) =>
        observedOwners.contains(key.historyOwner) &&
        (key.historyOwner != null ||
            observedAccounts.contains((
              accountId: key.accountId,
              historyOwner: key.historyOwner,
            )));
    final partial = poll != null && poll.skipped.isNotEmpty;
    final observedHistory =
        remembered
            .where(
              (key) =>
                  key.historyOwner != null
                      ? observed(key)
                      : !partial || observed(key),
            )
            .toList();
    final recoveries =
        observedHistory.isNotEmpty &&
                poll?.whollySkipped != true &&
                (notifications ||
                    observedHistory.any((key) => key.historyOwner != null))
            ? readRecoveries(snapshot, observedHistory)
            : <PlanRecovery>[];
    if (notifications &&
        observedHistory.isNotEmpty &&
        poll?.whollySkipped != true) {
      for (final recovery in recoveries) {
        if (isCurrent != null && !await isCurrent()) return;
        try {
          if (notifier is LocalRecoveryNotifier) {
            await notifier.notifyIfCurrent(
              recovery,
              isCurrent ?? () async => true,
            );
          } else {
            await notifier.notify(recovery);
          }
        } catch (_) {
          // Each window is reported on its own: a notifier that refuses one
          // must not silence the rest, and must not stop the list below from
          // moving on. A stuck list would go on missing every later window.
        }
      }
    }
    final protected =
        remembered
            .where(
              (key) =>
                  (key.historyOwner != null &&
                      !observedOwners.contains(key.historyOwner)) ||
                  (partial && !observed(key)),
            )
            .toList();
    final currentSpent =
        poll?.whollySkipped == true
            ? <WindowKey>[]
            : readWindows(snapshot)
                .where(
                  (key) =>
                      key.historyOwner != null
                          ? observed(key)
                          : !partial || observed(key),
                )
                .toList();
    // Missing/unknown observations have no recovery decision. Preserve owned
    // history until Rust sees usable capacity, even while delivery is muted.
    final unresolved = observedHistory.where(
      (key) =>
          key.historyOwner != null &&
          !currentSpent.contains(key) &&
          !recoveries.any(
            (recovery) =>
                recovery.accountId == key.accountId &&
                recovery.historyOwner == key.historyOwner &&
                recovery.allowanceId == key.allowanceId,
          ),
    );
    final spent =
        poll?.whollySkipped == true
            ? remembered
            : [...currentSpent, ...unresolved, ...protected].toSet().toList();
    // Reset instants are scheduling evidence, separate from Rust's edge keys.
    // Keep the last known reset while a window is missing or unknown, so a
    // sibling's later reset cannot replace its pending wake after a restart.
    final resets = <WindowKey, DateTime>{
      for (final key in spent)
        if (capturedHistory.resets[key] != null)
          key: capturedHistory.resets[key]!,
    };
    for (final account in snapshot.accounts) {
      for (final window in account.allowances) {
        final key = (
          accountId: account.accountId,
          historyOwner: account.historyOwner,
          allowanceId: window.id,
        );
        final reset = window.resetsAt;
        if (spent.contains(key) && reset != null) resets[key] = reset;
      }
    }
    if (isCurrent != null && !await isCurrent()) return;
    if (poll?.whollySkipped != true) {
      if (store is PartitionedRecoveryWatchlistStore) {
        await store.writeObserved(spent, observedOwners, resets: resets);
      } else {
        await store.write(spent);
      }
    }
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
    var protectedWakePending = false;
    for (final key in spent) {
      final reset = resets[key];
      final account =
          snapshot.accounts
              .where(
                (account) =>
                    account.accountId == key.accountId &&
                    account.historyOwner == key.historyOwner,
              )
              .firstOrNull;
      final connection =
          key.historyOwner?.connection ??
          account?.connection ??
          poll?.retainedAccountIds.entries
              .where((entry) => entry.value.contains(key.accountId))
              .firstOrNull
              ?.key;
      // A reset already behind still counts for a connection this load did not
      // observe if neither its native start nor its last success is as late:
      // the booked wake has not served it, so it stays due instead of being
      // cancelled or replaced by another connection's later reset. A later
      // start, even a failed one, or a later success, such as a manual one,
      // served it.
      final anchor = connection == null ? null : poll?.automaticAt[connection];
      final seen = account?.lastSuccessfulSyncAt;
      if (key.historyOwner != null &&
          protected.contains(key) &&
          (reset == null ||
              reset.isAfter(instant) ||
              ((anchor == null || anchor.isBefore(reset)) &&
                  (seen == null || seen.isBefore(reset)))))
        protectedWakePending = true;
      if (reset == null) continue;
      final overdue =
          anchor != null &&
          !observedAccounts.contains((
            accountId: key.accountId,
            historyOwner: key.historyOwner,
          )) &&
          !reset.isAfter(instant) &&
          anchor.isBefore(reset) &&
          (seen == null || seen.isBefore(reset));
      var due = overdue ? instant : (reset.isAfter(instant) ? reset : null);
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
        for (final key in remembered) {
          if (key.historyOwner != null
              ? key.historyOwner != owners[entry.key]
              : !ids.contains(key.accountId) &&
                  !snapshot.accounts.any(
                    (account) =>
                        account.connection == entry.key &&
                        account.accountId == key.accountId &&
                        account.historyOwner == null,
                  ))
            continue;
          final at = resets[key];
          if (at != null && (reset == null || at.isBefore(reset))) reset = at;
        }
        final pending =
            reset != null ||
            (ids.isEmpty &&
                protected.any((key) => key.historyOwner == owners[entry.key]));
        final eligible = entry.value.nextEligible;
        final due = reset != null && reset.isAfter(eligible) ? reset : eligible;
        if (pending && (soonest == null || due.isBefore(soonest)))
          soonest = due;
      }
    }
    if (isCurrent != null && !await isCurrent()) return;
    if (soonest == null) {
      // Unresolved or unserved owned history still protects its earlier wake.
      // Serving a known reset removes wake protection, not recovery history.
      if (poll?.whollySkipped != true &&
          unresolved.isEmpty &&
          !protectedWakePending)
        await wake.cancel();
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
