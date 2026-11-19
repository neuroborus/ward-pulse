import 'dart:convert';

import 'package:ward_pulse_bindings/ward_pulse_bindings.dart';

import 'dashboard_models.dart';

/// One plan window, named the only way it is unique: allowance ids repeat
/// across accounts and accepted connection owners.
typedef WindowKey =
    ({String accountId, String allowanceId, HistoryOwner? historyOwner});

/// Additive persisted context; identity remains the existing flat window key.
class PendingRecovery {
  const PendingRecovery(this.key, {this.requirements});

  final WindowKey key;
  final RecoveryRequirements? requirements;

  Map<String, dynamic> toJson() => {
    'accountId': key.accountId,
    'allowanceId': key.allowanceId,
    if (key.historyOwner != null) 'historyOwner': key.historyOwner!.toJson(),
    if (requirements != null) 'requirements': requirements!.toJson(),
  };
}

typedef RecoveryReconciliation =
    ({List<PendingRecovery> pending, List<PlanRecovery> recoveries});

typedef ReconcilePlanRecoveries =
    RecoveryReconciliation Function(
      DashboardSnapshot snapshot,
      List<PendingRecovery> pending,
    );

RecoveryReconciliation reconcilePlanRecoveries(
  DashboardSnapshot snapshot,
  List<PendingRecovery> pending,
) {
  final result =
      jsonDecode(
            reconcilePlanRecoveriesJson(
              snapshot.toJsonString(),
              encodePendingRecoveries(pending),
            ),
          )
          as Map<String, dynamic>;
  return (
    pending: decodePendingRecoveries(jsonEncode(result['pending'])),
    recoveries: [
      for (final value in result['recoveries'] as List)
        planRecoveryFromJson(value as Map<String, dynamic>),
    ],
  );
}

String encodePendingRecoveries(List<PendingRecovery> pending) =>
    jsonEncode([for (final entry in pending) entry.toJson()]);

List<PendingRecovery> decodePendingRecoveries(String json) {
  final keys = decodeWindowKeys(json);
  if (keys.isEmpty) return const [];
  final values = jsonDecode(json) as List;
  return [
    for (var i = 0; i < keys.length; i++)
      PendingRecovery(
        keys[i],
        requirements: RecoveryRequirements.maybeFromJson(
          (values[i] as Map<String, dynamic>)['requirements'],
        ),
      ),
  ];
}

/// A window that was spent and has room again.
///
/// `accountId` and ownership key the notification so a repeat replaces it;
/// neither is part of what a reader sees. `provider` is: two subscriptions can both call a
/// window "Weekly plan", and the family is what tells them apart.
typedef PlanRecovery =
    ({
      String accountId,
      HistoryOwner? historyOwner,
      String provider,
      String allowanceId,
      String label,
      DateTime? resetsAt,
    });

/// Windows `snapshot` reports as spent (Rust core by default; injectable in tests).
typedef ReadExhaustedWindows =
    List<WindowKey> Function(DashboardSnapshot snapshot);

/// Remembered targets whose applicable Plan capacity is usable (Rust core by
/// default; injectable in tests).
typedef ReadPlanRecoveries =
    List<PlanRecovery> Function(
      DashboardSnapshot snapshot,
      List<WindowKey> exhausted,
    );

/// Asks the core which windows are spent right now.
///
/// The rule lives there and only there: the phone remembers the answer between
/// polls but never decides what "exhausted" means.
List<WindowKey> exhaustedWindows(DashboardSnapshot snapshot) {
  return _decodeWindowKeys(exhaustedWindowsJson(snapshot.toJsonString()));
}

/// Asks the core which of [exhausted] have usable applicable capacity in [snapshot].
List<PlanRecovery> planRecoveries(
  DashboardSnapshot snapshot,
  List<WindowKey> exhausted,
) {
  final recoveries = jsonDecode(
    planRecoveriesJson(snapshot.toJsonString(), encodeWindowKeys(exhausted)),
  );
  return [
    for (final recovery in recoveries as List<dynamic>)
      planRecoveryFromJson(recovery as Map<String, dynamic>),
  ];
}

/// The soonest a window in [exhausted] is expected to roll [after] a given
/// instant, or `null` when none of them says.
///
/// Only instants still ahead count. A reset already behind means the provider
/// has not caught up with its own clock — Cursor aggregates about hourly — and
/// booking a wake for it would put the phone in a five-minute loop against a
/// window that keeps reading spent. The ordinary cadence covers that case.
///
/// Reading, not judging: the core decides which windows are spent, and the
/// shell decides when to look again — scheduling is the shell's side of the
/// boundary, as the poll cadence already is.
DateTime? nextResetAmong(
  DashboardSnapshot snapshot,
  List<WindowKey> exhausted, {
  required DateTime after,
}) {
  DateTime? soonest;
  for (final account in snapshot.accounts) {
    for (final allowance in account.allowances) {
      final isExhausted = exhausted.any(
        (key) =>
            key.accountId == account.accountId &&
            key.historyOwner == account.historyOwner &&
            key.allowanceId == allowance.id,
      );
      final resetsAt = allowance.resetsAt;
      if (!isExhausted || resetsAt == null || !resetsAt.isAfter(after)) {
        continue;
      }
      if (soonest == null || resetsAt.isBefore(soonest)) {
        soonest = resetsAt;
      }
    }
  }
  return soonest;
}

/// Window keys as the core reads them, ready to be stored between polls.
String encodeWindowKeys(List<WindowKey> keys) {
  return jsonEncode([
    for (final key in keys)
      {
        'accountId': key.accountId,
        'allowanceId': key.allowanceId,
        if (key.historyOwner != null)
          'historyOwner': key.historyOwner!.toJson(),
      },
  ]);
}

/// Inverse of [encodeWindowKeys]; anything unreadable reads as "nothing was
/// remembered", which costs one missed recovery rather than a crash on launch.
///
/// Unreadable covers more than unparseable text: a store holding `null`, an
/// object, or entries without the two fields parses fine and then fails on the
/// cast, and that failure would land on a background poll where nobody sees it.
List<WindowKey> decodeWindowKeys(String json) {
  try {
    return _decodeWindowKeys(json);
  } on FormatException {
    return const [];
  } on TypeError {
    return const [];
  }
}

List<WindowKey> _decodeWindowKeys(String json) {
  return [
    for (final key in jsonDecode(json) as List<dynamic>)
      (
        accountId: (key as Map<String, dynamic>)['accountId'] as String,
        allowanceId: key['allowanceId'] as String,
        historyOwner:
            key['historyOwner'] == null
                ? null
                : HistoryOwner.fromJson(
                  key['historyOwner'] as Map<String, dynamic>,
                ),
      ),
  ];
}

/// One recovery as the core writes it. Exposed for the round-trip test that
/// keeps this side and the Rust side describing the same payload.
PlanRecovery planRecoveryFromJson(Map<String, dynamic> json) {
  final resetsAt = json['resetsAt'];
  return (
    accountId: json['accountId'] as String,
    historyOwner:
        json['historyOwner'] == null
            ? null
            : HistoryOwner.fromJson(
              json['historyOwner'] as Map<String, dynamic>,
            ),
    provider: json['provider'] as String,
    allowanceId: json['allowanceId'] as String,
    label: json['label'] as String,
    // `tryParse`, because the core passes provider instants through rather than
    // rejecting them (`DateTimeUtc`). An unreadable one leaves the window with
    // no reset instant — still real news, just nothing to schedule a wake for —
    // while throwing here would take the whole poll's bookkeeping with it.
    resetsAt: resetsAt is String ? DateTime.tryParse(resetsAt) : null,
  );
}
