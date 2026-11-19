import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ward_pulse_phone/dashboard/dashboard_models.dart';
import 'package:ward_pulse_phone/dashboard/plan_recoveries.dart';

void main() {
  test(
    'pending context is additive and malformed optional context retains identity',
    () {
      const key = (accountId: 'a', allowanceId: 'session', historyOwner: null);
      const pending = PendingRecovery(
        key,
        requirements: RecoveryRequirements(
          allowanceIds: ['session', 'weekly'],
          complete: false,
        ),
      );
      final decoded =
          decodePendingRecoveries(encodePendingRecoveries([pending])).single;
      expect(decoded.key, key);
      expect(decoded.requirements!.toJson(), pending.requirements!.toJson());
      expect(decodeWindowKeys(encodePendingRecoveries([pending])), [key]);
      expect(
        decodePendingRecoveries(encodeWindowKeys([key])).single.requirements,
        isNull,
      );
      final invalid =
          decodePendingRecoveries(
            jsonEncode([
              {
                ...pending.toJson(),
                'requirements': {'allowanceIds': [1], 'complete': true},
              },
            ]),
          ).single;
      expect(invalid.key, key);
      expect(invalid.requirements, isNull);
    },
  );

  test('fixed snapshot codecs preserve requirements and raw reset facts', () {
    final snapshot = DashboardSnapshot.fromJsonString(
      File(
        '../../fixtures/snapshots/dashboard_today.json',
      ).readAsStringSync(),
    );
    final json = snapshot.toJson();
    final account = (json['accounts'] as List).first as Map<String, dynamic>;
    account['allowances'] = [
      {
        'id': 'session',
        'source': 'plan',
        'label': 'Session',
        'usedPercent': 100,
        'used': null,
        'limit': null,
        'remaining': null,
        'windowMinutes': 300,
        'resetsAt': '2026-07-19T17:00:00.000Z',
        'status': 'rateLimited',
        'recoveryRequirements': {
          'allowanceIds': ['session', 'weekly'],
          'complete': false,
        },
      },
    ];
    final roundtrip = DashboardSnapshot.fromJsonString(
      DashboardSnapshot.fromJson(json).toJsonString(),
    );
    final allowance = roundtrip.accounts.first.allowances.single;
    expect(allowance.recoveryRequirements!.allowanceIds, ['session', 'weekly']);
    expect(allowance.recoveryRequirements!.complete, isFalse);
    expect(allowance.usedPercent, 100);
    expect(allowance.resetsAt, DateTime.utc(2026, 7, 19, 17));
  });

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
      'accountId': 'claude-local',
      'provider': 'claude',
      'allowanceId': 'claude-weekly',
      'label': 'Weekly plan',
      'resetsAt': null,
      'historyOwner': ownerJson,
    });
    expect(recovery.historyOwner, owner);
    expect(recovery.label, 'Weekly plan');
    // Weekly room does not restore a plan whose necessary session is exhausted.
    expect(golden['recoveries'], isEmpty);
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
