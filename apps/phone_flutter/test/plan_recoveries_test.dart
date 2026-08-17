import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ward_pulse_phone/dashboard/plan_recoveries.dart';

void main() {
  // The golden the Rust side builds from; parsing it here is what keeps the two
  // ends of the FFI boundary describing the same payload.
  final golden =
      jsonDecode(
            File(
              '../../fixtures/snapshots/plan_recovery.json',
            ).readAsStringSync(),
          )
          as Map<String, dynamic>;

  test('window keys survive the trip to storage and back', () {
    final keys = decodeWindowKeys(jsonEncode(golden['exhausted']));

    expect(keys, [
      (accountId: 'claude-local', allowanceId: 'claude-weekly'),
      (accountId: 'claude-local', allowanceId: 'claude-session'),
    ]);
    expect(jsonDecode(encodeWindowKeys(keys)), golden['exhausted']);
  });

  test('a recovery keeps its label when the reset instant is unreadable', () {
    // The core passes provider instants through, so a broken one reaches here;
    // losing the window over it would cost the whole poll's bookkeeping.
    final recovery = planRecoveryFromJson({
      'accountId': 'claude-local',
      'allowanceId': 'claude-weekly',
      'label': 'Weekly plan',
      'resetsAt': 'whenever',
    });

    expect(recovery.label, 'Weekly plan');
    expect(recovery.resetsAt, isNull);
  });

  test('a store nothing can read counts as nothing remembered', () {
    // One missed recovery beats a crash on a background poll, and the next one
    // refills the list anyway. Readable-but-wrong counts as unreadable: those
    // parse and then fail on the cast.
    expect(decodeWindowKeys('not json'), isEmpty);
    expect(decodeWindowKeys('null'), isEmpty);
    expect(decodeWindowKeys('{}'), isEmpty);
    expect(decodeWindowKeys('[{"accountId": "claude-local"}]'), isEmpty);
  });
}
