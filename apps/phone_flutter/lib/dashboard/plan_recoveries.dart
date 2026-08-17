import 'dart:convert';

import 'package:ward_pulse_bindings/ward_pulse_bindings.dart';

import 'dashboard_models.dart';

/// One plan window, named the only way it is unique: allowance ids repeat
/// across accounts, so the account travels with them.
typedef WindowKey = ({String accountId, String allowanceId});

/// A window that was spent and has room again.
///
/// `accountId` keys the notification so a repeat replaces it; it is never part
/// of what a reader sees.
typedef PlanRecovery =
    ({String accountId, String allowanceId, String label, DateTime? resetsAt});

/// Windows `snapshot` reports as spent (Rust core in production; a test seam
/// everywhere else, since host tests load no `.so`).
typedef ReadExhaustedWindows =
    List<WindowKey> Function(DashboardSnapshot snapshot);

/// Windows from `exhausted` that `snapshot` reports usable again (Rust core in
/// production; a test seam everywhere else, since host tests load no `.so`).
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

/// Asks the core which of [exhausted] have room again in [snapshot].
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

/// Window keys as the core reads them, ready to be stored between polls.
String encodeWindowKeys(List<WindowKey> keys) {
  return jsonEncode([
    for (final key in keys)
      {'accountId': key.accountId, 'allowanceId': key.allowanceId},
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
      ),
  ];
}

/// One recovery as the core writes it. Exposed for the round-trip test that
/// keeps this side and the Rust side describing the same payload.
PlanRecovery planRecoveryFromJson(Map<String, dynamic> json) {
  final resetsAt = json['resetsAt'];
  return (
    accountId: json['accountId'] as String,
    allowanceId: json['allowanceId'] as String,
    label: json['label'] as String,
    // `tryParse`, because the core passes provider instants through rather than
    // rejecting them (`DateTimeUtc`). An unreadable one leaves the window with
    // no reset instant — still real news, just nothing to schedule a wake for —
    // while throwing here would take the whole poll's bookkeeping with it.
    resetsAt: resetsAt is String ? DateTime.tryParse(resetsAt) : null,
  );
}
