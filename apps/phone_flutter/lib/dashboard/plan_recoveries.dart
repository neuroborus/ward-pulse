import 'dart:convert';

import 'package:ward_pulse_bindings/ward_pulse_bindings.dart';

import 'dashboard_models.dart';

/// One plan window, named the only way it is unique: allowance ids repeat
/// across accounts, so the account travels with them.
typedef WindowKey = ({String accountId, String allowanceId});

/// Asks the core which windows are spent right now.
///
/// The rule lives there and only there: the phone remembers the answer between
/// polls but never decides what "exhausted" means.
List<WindowKey> exhaustedWindows(DashboardSnapshot snapshot) {
  return _decodeWindowKeys(exhaustedWindowsJson(snapshot.toJsonString()));
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
