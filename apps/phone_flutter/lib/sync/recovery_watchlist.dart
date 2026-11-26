import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../dashboard/dashboard_models.dart';
import '../dashboard/plan_recoveries.dart';
import '../providers/connection_lifecycle.dart';
import 'poll_cadence.dart';
import 'recovery_notifications.dart';
import 'recovery_wake.dart';
import 'automatic_poll.dart';
import 'data_mode.dart';

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

/// Additive context API; existing key-only stores remain valid test/legacy clients.
abstract interface class ContextualRecoveryWatchlistStore
    implements PartitionedRecoveryWatchlistStore {
  Future<({List<PendingRecovery> pending, Map<WindowKey, DateTime> resets})>
  readPendingOwners(Set<HistoryOwner?> owners);

  @override
  Future<void> writeObserved(
    List<WindowKey> keys,
    Set<HistoryOwner?> owners, {
    Map<WindowKey, DateTime> resets = const {},
    Map<WindowKey, RecoveryRequirements> requirements = const {},
  });
}

final class SecureRecoveryWatchlistStore
    implements ContextualRecoveryWatchlistStore {
  /// [postLedger] shares failed-write posts with every engine in the process;
  /// without it they are shared per [storage] within this isolate.
  SecureRecoveryWatchlistStore({
    FlutterSecureStorage? storage,
    RecoveryPostLedger? postLedger,
  }) : _storage = storage ?? const FlutterSecureStorage(),
       _postLedger = postLedger;

  static const _key = 'wardpulse.recovery.exhaustedWindows';

  final FlutterSecureStorage _storage;
  final RecoveryPostLedger? _postLedger;

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
    final result = await readPendingOwners(owners);
    return (
      keys: [for (final entry in result.pending) entry.key],
      resets: result.resets,
    );
  }

  @override
  Future<({List<PendingRecovery> pending, Map<WindowKey, DateTime> resets})>
  readPendingOwners(Set<HistoryOwner?> owners) async {
    final result = <PendingRecovery>[];
    final resets = <WindowKey, DateTime>{};
    for (final owner in owners) {
      final stored = await _storage.read(key: _ownerKey(owner));
      if (stored == null) continue;
      final pending = decodePendingRecoveries(stored);
      if (pending.isEmpty) continue;
      final values = jsonDecode(stored) as List<dynamic>;
      for (var i = 0; i < pending.length; i++) {
        final entry = pending[i];
        if (entry.key.historyOwner != owner) continue;
        result.add(entry);
        final value = (values[i] as Map<String, dynamic>)['resetsAt'];
        final reset = value is String ? DateTime.tryParse(value) : null;
        if (reset != null) resets[entry.key] = reset;
      }
    }
    return (pending: result, resets: resets);
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
    Map<WindowKey, RecoveryRequirements> requirements = const {},
  }) async {
    for (final owner in owners) {
      final values = [
        for (final key in keys)
          if (key.historyOwner == owner)
            {
              ...PendingRecovery(key, requirements: requirements[key]).toJson(),
              if (resets[key] != null)
                'resetsAt': resets[key]!.toUtc().toIso8601String(),
            },
      ];
      await _storage.write(key: _ownerKey(owner), value: jsonEncode(values));
    }
  }
}

Future<({List<PendingRecovery> pending, Map<WindowKey, DateTime> resets})>
_readPendingHistory(
  RecoveryWatchlistStore store,
  Set<HistoryOwner?> owners,
) async {
  if (store is ContextualRecoveryWatchlistStore) {
    return store.readPendingOwners(owners);
  }
  final history =
      store is PartitionedRecoveryWatchlistStore
          ? await store.readOwners(owners)
          : (keys: await store.read(), resets: <WindowKey, DateTime>{});
  return (
    pending: [for (final key in history.keys) PendingRecovery(key)],
    resets: history.resets,
  );
}

/// Reconcile captured evidence only. Never read today's credentials to relabel
/// a snapshot obtained earlier, including a skipped or retained observation.
Map<String, HistoryOwner?> _capturedOwners(
  DashboardSnapshot snapshot,
  AutomaticPollContext? poll,
) {
  final versions = <String, CredentialVersion>{};
  void add(
    String connection,
    CredentialVersion version, {
    bool allowAbsent = false,
  }) {
    if (version.values.containsKey('conflict') ||
        (version.isAbsent && !allowAbsent))
      throw const FormatException('Conflicting recovery provenance.');
    final previous = versions[connection];
    if (previous != null &&
        (!previous.sameCache(version) ||
            HistoryOwner.fromVersion(connection, previous) !=
                HistoryOwner.fromVersion(connection, version)))
      throw const FormatException('Conflicting recovery provenance.');
    versions[connection] = version;
  }

  snapshot.connectionVersions.forEach(
    (id, values) => add(id, CredentialVersion(values), allowAbsent: true),
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
      if (!entry.value.isAbsent)
        entry.key: HistoryOwner.fromVersion(entry.key, entry.value),
  };
  for (final account in snapshot.accounts) {
    final connection = account.connection;
    if (versions[connection]?.isAbsent == true)
      throw const FormatException('Conflicting recovery owner.');
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

/// Recovery occurrences submitted to Android whose history write then failed.
///
/// An occurrence names its window and saved reset, so it matches only the
/// pending entry the failed write left behind, never a later exhaustion.
abstract interface class RecoveryPostLedger {
  Future<Set<String>> read();

  Future<void> record(Iterable<String> occurrences);

  Future<void> forget(Iterable<String> occurrences);
}

/// Native memory every engine in this process shares, so a later engine or
/// headless isolate consumes the occurrence without posting it again.
///
/// A later process still relies on the stable notification id, as
/// notify-first allows.
final class NativeRecoveryPostLedger implements RecoveryPostLedger {
  const NativeRecoveryPostLedger({
    this.platform = const MethodChannelConnectionCachePlatform(),
  });

  final ConnectionCachePlatform platform;

  @override
  Future<Set<String>> read() async => <String>{
    ...((await platform.invoke('readUnrecordedRecoveries', {}) as List?) ??
            const [])
        .cast<String>(),
  };

  @override
  Future<void> record(Iterable<String> occurrences) => platform.invoke(
    'recordUnrecordedRecoveries',
    {'occurrences': occurrences.toList()},
  );

  @override
  Future<void> forget(Iterable<String> occurrences) => platform.invoke(
    'forgetUnrecordedRecoveries',
    {'occurrences': occurrences.toList()},
  );
}

/// The fallback: per backing storage within this isolate.
final class _LocalRecoveryPostLedger implements RecoveryPostLedger {
  _LocalRecoveryPostLedger(Object scope)
    : _posts = _localPosts[scope] ??= <String>{};

  static final _localPosts = Expando<Set<String>>();

  final Set<String> _posts;

  @override
  Future<Set<String>> read() async => <String>{..._posts};

  @override
  Future<void> record(Iterable<String> occurrences) async =>
      _posts.addAll(occurrences);

  @override
  Future<void> forget(Iterable<String> occurrences) async =>
      _posts.removeAll(occurrences);
}

Future<(RecoveryPostLedger, Set<String>)> _openPostLedger(
  RecoveryWatchlistStore store,
) async {
  if (store is SecureRecoveryWatchlistStore) {
    if (store._postLedger case final ledger?) {
      try {
        return (ledger, await ledger.read());
      } catch (_) {
        // A host with no native engine keeps this isolate's evidence.
      }
    }
  }
  final local = _LocalRecoveryPostLedger(
    store is SecureRecoveryWatchlistStore ? store._storage : store,
  );
  return (local, await local.read());
}

/// Forgets [receipts] in [partitions] whose occurrence history read now no
/// longer holds: that window has moved on, so its next recovery must post.
/// Also returns the occurrences still pending, so a run whose earlier read
/// another run has since consumed or replaced neither posts nor writes from it.
///
/// Call under the mode-effect lease. A receipt is recorded only after its
/// failed write left the occurrence durable, so a read after the receipt
/// cannot miss it.
Future<({Set<String> receipts, Set<String> pending})> _pruneReceipts(
  RecoveryPostLedger ledger,
  Set<String> receipts,
  RecoveryWatchlistStore store,
  Set<HistoryOwner?> partitions,
) async {
  final history = await _readPendingHistory(store, partitions);
  final durable = _pendingOccurrences(history);
  final read = {for (final owner in partitions) _historyPartition(owner)};
  final settled = {
    for (final receipt in receipts)
      if (read.contains(receipt.substring(0, receipt.indexOf('|'))) &&
          !durable.contains(receipt))
        receipt,
  };
  if (settled.isEmpty) return (receipts: receipts, pending: durable);
  try {
    await ledger.forget(settled.toList());
  } catch (_) {
    // A later look retries; unmatched evidence still cannot suppress a post.
  }
  return (receipts: receipts.difference(settled), pending: durable);
}

Set<String> _pendingOccurrences(
  ({List<PendingRecovery> pending, Map<WindowKey, DateTime> resets}) history,
) => {
  for (final entry in history.pending)
    _postOccurrence(entry.key, history.resets[entry.key]),
};

String _historyPartition(HistoryOwner? owner) =>
    owner == null
        ? ''
        : base64Url.encode(utf8.encode(jsonEncode(owner.toJson())));

String _postOccurrence(WindowKey key, DateTime? reset) {
  final window = jsonEncode([
    key.accountId,
    key.allowanceId,
    reset?.toUtc().toIso8601String(),
  ]);
  return '${_historyPartition(key.historyOwner)}|$window';
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
/// [isDeliveryEnabled] checks the latest choice just before posting, after the
/// final [isCurrent] proof. A caller whose choice changes in its own isolate
/// answers without awaiting, so ownership cannot move before submission.
/// [admitDelivery] instead answers in one step after that proof: `true` posts,
/// `false` mutes, and `null` leaves the window pending. A caller in another
/// isolate proves the observation there; the foreground answers `null` once a
/// mode switch has begun.
/// A recovery whose post retirement interrupted stays pending and keeps its
/// reset wake; muted, refused and submitted ones are remembered as consumed. An
/// acknowledged post whose history write fails is kept in the store's
/// [RecoveryPostLedger] so a later look consumes it without posting again.
///
/// [rethrowFailures] lets a caller with its own per-step guard record an outer
/// storage or scheduling failure. Foreground callers retain the best-effort
/// default.
Future<void> syncPlanRecoveries(
  DashboardSnapshot snapshot,
  RecoveryWatchlistStore store,
  RecoveryNotifier notifier,
  RecoveryWakeScheduler wake, {
  bool notifications = true,
  Future<bool> Function()? isDeliveryEnabled,
  Future<bool?> Function()? admitDelivery,
  ReadPlanRecoveries readRecoveries = planRecoveries,
  ReadExhaustedWindows readWindows = exhaustedWindows,
  ReconcilePlanRecoveries? reconcile,
  DateTime Function() now = DateTime.now,
  bool rethrowFailures = false,
  AutomaticPollContext? poll,
  Future<bool> Function()? isCurrent,
}) async {
  if (DataModeOperation.current?.allowsLiveWork == false) return;
  try {
    if (isCurrent != null && !await isCurrent()) return;
    final owners = _capturedOwners(snapshot, poll);
    final observedOwners = <HistoryOwner?>{
      for (final entry in owners.entries)
        if (poll?.observes(entry.key) != false &&
            poll?.retainedAccountIds[entry.key]?.isNotEmpty != true)
          entry.value,
      if (owners.isEmpty) null,
    };
    final capturedHistory = await _readPendingHistory(store, {
      null,
      ...owners.values,
    });
    final rememberedPending =
        capturedHistory.pending
            .where(
              (entry) =>
                  entry.key.historyOwner == null ||
                  owners.containsValue(entry.key.historyOwner),
            )
            .toList();
    final remembered = [for (final entry in rememberedPending) entry.key];
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
    final eligiblePending = [
      for (final entry in rememberedPending)
        if (observedHistory.contains(entry.key)) entry,
    ];
    final observedSnapshot = snapshot.withAccounts([
      for (final account in snapshot.accounts)
        if (observedAccounts.contains((
          accountId: account.accountId,
          historyOwner: account.historyOwner,
        )))
          account,
    ]);
    // Raw exhaustion remains separate scheduling evidence, even when a target
    // stays pending after its own window clears.
    final currentSpent =
        poll?.whollySkipped == true
            ? <WindowKey>[]
            : readWindows(observedSnapshot);
    final RecoveryReconciliation result;
    if (poll?.whollySkipped == true) {
      result = (pending: eligiblePending, recoveries: <PlanRecovery>[]);
    } else if (reconcile != null ||
        (readRecoveries == planRecoveries && readWindows == exhaustedWindows)) {
      result = (reconcile ?? reconcilePlanRecoveries)(
        observedSnapshot,
        eligiblePending,
      );
    } else {
      // Preserve the old injectable seams for key-only clients. Production uses
      // the single Rust reconciliation above, including while delivery is muted.
      final recovered =
          observedHistory.isNotEmpty &&
                  (notifications ||
                      observedHistory.any((key) => key.historyOwner != null))
              ? readRecoveries(observedSnapshot, observedHistory)
              : <PlanRecovery>[];
      final keys = {
        ...currentSpent,
        for (final key in observedHistory)
          if (key.historyOwner != null &&
              !recovered.any(
                (item) =>
                    item.accountId == key.accountId &&
                    item.historyOwner == key.historyOwner &&
                    item.allowanceId == key.allowanceId,
              ))
            key,
      };
      result = (
        pending: [
          for (final key in keys)
            eligiblePending.where((entry) => entry.key == key).firstOrNull ??
                PendingRecovery(key),
        ],
        recoveries: recovered,
      );
    }
    bool eligible(WindowKey key) =>
        key.historyOwner != null ? observed(key) : !partial || observed(key);
    final returnedPending =
        result.pending.where((entry) => eligible(entry.key)).toList();
    final recoveries =
        result.recoveries
            .where(
              (item) => observedHistory.contains((
                accountId: item.accountId,
                historyOwner: item.historyOwner,
                allowanceId: item.allowanceId,
              )),
            )
            .toList();
    final protected =
        remembered
            .where(
              (key) =>
                  (key.historyOwner != null &&
                      !observedOwners.contains(key.historyOwner)) ||
                  (partial && !observed(key)),
            )
            .toList();
    final pending =
        poll?.whollySkipped == true
            ? rememberedPending
            : [
              ...returnedPending,
              for (final entry in rememberedPending)
                if (protected.contains(entry.key)) entry,
            ];
    final spent = [for (final entry in pending) entry.key].toSet().toList();
    final unresolved = spent.where(
      (key) =>
          key.historyOwner != null &&
          observedHistory.contains(key) &&
          !currentSpent.contains(key),
    );
    // Reset instants are scheduling evidence, separate from Rust's edge keys.
    // Keep the last known reset while a window is missing or unknown, so a
    // sibling's later reset cannot replace its pending wake after a restart.
    final resets = <WindowKey, DateTime>{
      for (final key in spent)
        if (capturedHistory.resets[key] != null)
          key: capturedHistory.resets[key]!,
    };
    for (final account in snapshot.accounts) {
      final accountObserved = observedAccounts.contains((
        accountId: account.accountId,
        historyOwner: account.historyOwner,
      ));
      for (final window in account.allowances) {
        final key = (
          accountId: account.accountId,
          historyOwner: account.historyOwner,
          allowanceId: window.id,
        );
        final reset = window.resetsAt;
        // Retained facts may fill a missing scheduling hint for an exact
        // protected key, but cannot replace its saved reset or admit history.
        if (spent.contains(key) &&
            reset != null &&
            (accountObserved ||
                (protected.contains(key) && !resets.containsKey(key))))
          resets[key] = reset;
      }
    }
    if (isCurrent != null && !await isCurrent()) return;
    final interrupted = <WindowKey>{};
    if (poll?.whollySkipped != true) {
      var posting =
          notifications && observedHistory.isNotEmpty && recoveries.isNotEmpty;
      if (posting && notifier is LocalRecoveryNotifier) {
        try {
          // Plugin setup and its retries stay outside the lease a switch
          // waits for.
          await notifier.prepare();
        } catch (_) {
          // An unready plugin fails every post, as a refused post does; the
          // history and wake still move on.
          posting = false;
        }
      }
      String occurrence(WindowKey key) =>
          _postOccurrence(key, capturedHistory.resets[key]);
      final submitted = <WindowKey>{};
      var written = false;
      // One lease covers the posts and the write that remembers them, so a
      // switch cannot leave a submitted recovery pending to sound again.
      await DataModeOperation.guardCurrent(() async {
        // Receipts change only under the lease, so a run a switch retired
        // cannot erase one a newer run recorded.
        final (ledger, receipts) = await _openPostLedger(store);
        // A store that saves resets can hold a replacement occurrence of the
        // same window, so it is reread even when no receipt is outstanding.
        final refreshed =
            receipts.isEmpty && store is! PartitionedRecoveryWatchlistStore
                ? null
                : await _pruneReceipts(ledger, receipts, store, {
                  null,
                  ...owners.values,
                });
        final unrecorded = refreshed?.receipts ?? receipts;
        if (refreshed != null) {
          // Another run consumed or replaced an occurrence after this run's
          // history read. That read can authorize no post and no write; the
          // newer record and its wake stay as they are.
          final captured = _pendingOccurrences(capturedHistory);
          if (refreshed.pending.length != captured.length ||
              !refreshed.pending.containsAll(captured)) {
            return;
          }
        }
        for (final recovery in posting ? recoveries : const <PlanRecovery>[]) {
          final key = (
            accountId: recovery.accountId,
            historyOwner: recovery.historyOwner,
            allowanceId: recovery.allowanceId,
          );
          // Already submitted by a run whose history write failed.
          if (unrecorded.contains(occurrence(key))) {
            submitted.add(key);
            continue;
          }
          var owned = true;
          var allowed = false;
          Future<bool> canPost() async {
            // A proof that throws before submission leaves the window pending.
            owned = false;
            owned = isCurrent == null || await isCurrent();
            if (!owned) return false;
            if (admitDelivery != null) {
              owned = false;
              final admitted = await admitDelivery();
              owned = admitted != null;
              allowed = admitted == true;
            } else {
              // The choice is read after the final repository proof, so one
              // saved while that proof runs still suppresses the post.
              allowed = isDeliveryEnabled == null || await isDeliveryEnabled();
            }
            return allowed;
          }

          try {
            if (notifier is LocalRecoveryNotifier) {
              await notifier.notifyIfCurrent(recovery, canPost);
            } else if (await canPost()) {
              await notifier.notify(recovery);
            }
            // Only a post Android acknowledged may suppress a later one.
            if (allowed) submitted.add(key);
          } catch (_) {
            // Each window is reported on its own: a notifier that refuses
            // one must not silence the rest, and must not stop the list
            // below from moving on. A stuck list would go on missing every
            // later window.
          }
          // Retirement, unlike muting or refusal, leaves the window pending.
          if (!owned) interrupted.add(key);
        }
        // The lease keeps the generation current; a submitted post is
        // remembered even while a pending switch makes ownership read stale.
        if (submitted.isEmpty && isCurrent != null && !await isCurrent()) {
          return;
        }
        final kept = [
          ...pending,
          for (final entry in eligiblePending)
            if (interrupted.contains(entry.key)) entry,
        ];
        final keys = [for (final entry in kept) entry.key].toSet().toList();
        final keptResets = {
          ...resets,
          for (final key in interrupted)
            if (capturedHistory.resets[key] != null)
              key: capturedHistory.resets[key]!,
        };
        try {
          if (store is ContextualRecoveryWatchlistStore) {
            await store.writeObserved(
              keys,
              observedOwners,
              resets: keptResets,
              requirements: {
                for (final entry in kept)
                  if (entry.requirements != null)
                    entry.key: entry.requirements!,
              },
            );
          } else if (store is PartitionedRecoveryWatchlistStore) {
            await store.writeObserved(keys, observedOwners, resets: keptResets);
          } else {
            await store.write(keys);
          }
        } catch (_) {
          // Android already has these; a later look must not post them again.
          if (submitted.isNotEmpty) {
            try {
              await ledger.record(submitted.map(occurrence).toList());
            } catch (_) {
              // The stable notification id remains the fallback.
            }
          }
          rethrow;
        }
        // This write consumed every submitted occurrence.
        final recorded = submitted.map(occurrence).where(unrecorded.contains);
        if (recorded.isNotEmpty) {
          try {
            await ledger.forget(recorded.toList());
          } catch (_) {
            // A later look forgets occurrences its history no longer holds.
          }
        }
        written = true;
      }, isCurrent: isCurrent);
      if (!written) return;
      // A window the post left pending keeps its wake, as its history does.
      for (final key in interrupted) {
        if (!spent.contains(key)) spent.add(key);
        if (capturedHistory.resets[key] case final reset?) resets[key] = reset;
      }
    }
    // Booked from the reset instant rather than left to the next poll, which
    // the cadence would make up to an interval late. `null` covers every case
    // with nothing to wake for: nothing spent, nothing saying when it rolls,
    // and a reset already behind because the provider has not caught up.
    //
    // Count the reset floor from the window's own native cadence anchor so
    // another connection's start cannot push the wake back. A load with no
    // anchor, such as a manual one, counts the floor from itself.
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
      // An overdue reset can still need a wake if this load did not observe
      // the connection and both its native anchor and last success precede the
      // reset. The anchor can record a start or a clock correction.
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
      // Cancelling an obsolete wake leaves recovery history intact.
      if (poll?.whollySkipped != true &&
          unresolved.isEmpty &&
          interrupted.isEmpty &&
          !protectedWakePending)
        await DataModeOperation.guardCurrent(wake.cancel, isCurrent: isCurrent);
    } else {
      // Natural resets use the floor above; denied work keeps its native due
      // time rather than adding another full floor after a skipped load.
      final due = soonest;
      await DataModeOperation.guardCurrent(
        () => wake.scheduleAt(due),
        isCurrent: isCurrent,
      );
    }
  } catch (error, stackTrace) {
    if (rethrowFailures) {
      Error.throwWithStackTrace(error, stackTrace);
    }
    // A foreground poll must never crash over bookkeeping; the next one writes
    // the list again. Headless sync rethrows into its per-step guard to log it.
  }
}
