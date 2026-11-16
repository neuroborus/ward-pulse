import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ward_pulse_phone/dashboard/dashboard_models.dart';
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
      (
        accountId: 'claude-local',
        allowanceId: 'claude-weekly',
        historyOwner: null,
      ),
      (
        accountId: 'claude-local',
        allowanceId: 'claude-session',
        historyOwner: null,
      ),
    ]);
    expect(jsonDecode(encodeWindowKeys(keys)), golden['exhausted']);
  });

  test('owned keys and recoveries retain their private scope through JSON', () {
    final ownerJson = {
      'connection': 'anthropic.plan',
      'identity': List.filled(64, 'a').join(),
    };
    final owner = HistoryOwner.fromJson(ownerJson);
    final encoded = [
      {
        ...(golden['exhausted'] as List).first as Map<String, dynamic>,
        'historyOwner': ownerJson,
      },
    ];
    final keys = decodeWindowKeys(jsonEncode(encoded));
    expect(keys.single.historyOwner, owner);
    expect(jsonDecode(encodeWindowKeys(keys)), encoded);
    expect(decodeWindowKeys(encodeWindowKeys(keys)).toSet(), keys.toSet());
    final legacy = decodeWindowKeys(jsonEncode(golden['exhausted'])).first;
    expect(keys.single.accountId, legacy.accountId);
    expect(keys.single.allowanceId, legacy.allowanceId);
    expect(keys.single, isNot(legacy));
    final different = decodeWindowKeys(
      jsonEncode([
        {
          ...encoded.single,
          'historyOwner': {...ownerJson, 'identity': 'other'},
        },
      ]),
    );
    expect(different.single, isNot(keys.single));

    final recovery = planRecoveryFromJson({
      ...(golden['recoveries'] as List).first as Map<String, dynamic>,
      'historyOwner': ownerJson,
    });
    expect(recovery.historyOwner, owner);
    expect(recovery.label, (golden['recoveries'] as List).first['label']);
  });

  test('a recovery keeps its label when the reset instant is unreadable', () {
    // The core passes provider instants through, so a broken one reaches here;
    // losing the window over it would cost the whole poll's bookkeeping.
    final recovery = planRecoveryFromJson({
      'accountId': 'claude-local',
      'provider': 'claude',
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
