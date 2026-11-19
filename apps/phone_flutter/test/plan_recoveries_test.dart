import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ward_pulse_bindings/ward_pulse_bindings.dart';
import 'package:ward_pulse_phone/dashboard/dashboard_models.dart';
import 'package:ward_pulse_phone/dashboard/plan_recoveries.dart';
import 'package:ward_pulse_phone/providers/codex_account_store.dart';
import 'package:ward_pulse_phone/sync/codex_account_client.dart';

void main() {
  test(
    'raw root collisions retain learned requirements through FFI and history',
    () async {
      final at = DateTime.utc(2026, 7, 19, 12);
      final primary = <String, dynamic>{
        'used_percent': 100,
        'limit_window_seconds': 18000,
        'reset_at': 1784480400,
      };
      const secondary = {
        'used_percent': 20,
        'limit_window_seconds': 604800,
        'reset_at': 1784980800,
      };
      final root = <String, dynamic>{
        'allowed': true,
        'limit_reached': false,
        'primary_window': primary,
        'secondary_window': null,
      };
      final raw = <String, dynamic>{'rate_limit': root};
      Future<Map<String, dynamic>> normalize() async {
        final result = await CodexAccountClient(
          transport: _UsageTransport(raw),
          clock: () => at,
        ).fetchReport(
          CodexAccountSession(
            accessToken: 'synthetic-access',
            refreshToken: 'synthetic-refresh',
            accountId: 'synthetic-account',
            refreshedAt: at,
          ),
        );
        return jsonDecode(result.reportJson) as Map<String, dynamic>;
      }

      DashboardSnapshot qualify(Map<String, dynamic> report) {
        // Use actual Rust serde/qualification, then the fixed phone codecs.
        final snapshot = DashboardSnapshot.fromJsonString(
          normalizeCodexReportJson(jsonEncode(report)),
        );
        return DashboardSnapshot.fromJsonString(snapshot.toJsonString());
      }

      final initial = reconcilePlanRecoveries(qualify(await normalize()), []);
      final key = initial.pending.single.key;
      expect(key, (
        accountId: 'codex-local',
        allowanceId: 'codex-primary',
        historyOwner: null,
      ));
      expect(initial.pending.single.requirements!.allowanceIds, [
        'codex-primary',
      ]);
      expect(initial.pending.single.requirements!.complete, isTrue);
      expect(initial.recoveries, isEmpty);

      primary['used_percent'] = 10;
      raw['additional_rate_limits'] = [
        {
          'metered_feature': 'codex',
          'rate_limit': {
            'allowed': true,
            'limit_reached': false,
            'primary_window': {...primary, 'used_percent': 90},
            'secondary_window': secondary,
          },
        },
      ];
      final collisionReport = await normalize();
      final collision = qualify(collisionReport);
      const pairIds = ['codex-primary', 'codex-secondary'];
      final allowances = collision.accounts.single.allowances;
      expect(allowances.map((value) => value.id), pairIds);
      expect(allowances.map((value) => value.usedPercent), [10, 20]);
      expect(allowances.map((value) => value.windowMinutes), [300, 10080]);
      expect(allowances.map((value) => value.resetsAt), [
        DateTime.utc(2026, 7, 19, 17),
        DateTime.utc(2026, 7, 25, 12),
      ]);
      for (final allowance in allowances) {
        expect(allowance.recoveryRequirements!.allowanceIds, pairIds);
        expect(allowance.recoveryRequirements!.complete, isFalse);
        expect(allowance.used, isNull);
        expect(allowance.limit, isNull);
        expect(allowance.remaining, isNull);
      }
      final blocked = reconcilePlanRecoveries(collision, initial.pending);
      expect(blocked.recoveries, isEmpty);
      expect(blocked.pending.single.key, key);
      expect(blocked.pending.single.requirements!.allowanceIds, pairIds);
      expect(blocked.pending.single.requirements!.complete, isFalse);
      final reloaded = decodePendingRecoveries(
        encodePendingRecoveries(blocked.pending),
      );
      expect(reloaded.single.requirements!.allowanceIds, pairIds);
      expect(reloaded.single.requirements!.complete, isFalse);

      // The supported legacy representation must carry the same collision facts.
      (collisionReport['rateLimits'] as Map).remove('rateLimitsByLimitId');
      final legacyCollision = reconcilePlanRecoveries(
        qualify(collisionReport),
        initial.pending,
      );
      expect(legacyCollision.recoveries, isEmpty);
      expect(
        legacyCollision.pending.single.requirements!.allowanceIds,
        pairIds,
      );
      expect(legacyCollision.pending.single.requirements!.complete, isFalse);

      raw.remove('additional_rate_limits');
      final singleton = qualify(await normalize());
      expect(
        singleton
            .accounts
            .single
            .allowances
            .single
            .recoveryRequirements!
            .complete,
        isTrue,
      );
      final narrowed = reconcilePlanRecoveries(singleton, reloaded);
      expect(narrowed.recoveries, isEmpty);
      expect(narrowed.pending.single.key, key);
      expect(narrowed.pending.single.requirements!.allowanceIds, pairIds);
      expect(narrowed.pending.single.requirements!.complete, isFalse);
      // A unique singleton can recover history that never learned the sibling.
      expect(
        reconcilePlanRecoveries(
          singleton,
          initial.pending,
        ).recoveries.single.allowanceId,
        key.allowanceId,
      );
      raw['additional_rate_limits'] = [
        {'metered_feature': 'unrecognized', 'rate_limit': null},
      ];
      expect(
        reconcilePlanRecoveries(
          qualify(await normalize()),
          initial.pending,
        ).recoveries.single.allowanceId,
        key.allowanceId,
      );
      raw.remove('additional_rate_limits');

      for (final status in [
        (allowed: false, reached: false),
        (allowed: true, reached: true),
      ]) {
        root['allowed'] = status.allowed;
        root['limit_reached'] = status.reached;
        expect(
          reconcilePlanRecoveries(
            qualify(await normalize()),
            initial.pending,
          ).recoveries,
          isEmpty,
        );
      }
      root['allowed'] = true;
      root['limit_reached'] = false;
      primary['used_percent'] = 100;
      raw['credits'] = {
        'has_credits': true,
        'unlimited': true,
        'balance': '12.5',
      };
      final purchased = qualify(await normalize());
      expect(purchased.accounts.single.allowances.last.unlimited, isTrue);
      expect(
        reconcilePlanRecoveries(purchased, initial.pending).recoveries,
        isEmpty,
      );

      raw.remove('credits');
      primary['used_percent'] = 10;
      root['secondary_window'] = secondary;
      final completeReport = await normalize();
      final recovered = reconcilePlanRecoveries(
        qualify(completeReport),
        narrowed.pending,
      );
      expect(recovered.pending, isEmpty);
      expect(recovered.recoveries.single.allowanceId, key.allowanceId);
      final legacyRoot =
          (completeReport['rateLimits'] as Map)['rateLimits'] as Map;
      legacyRoot.remove('evidence');
      final lossy = qualify(completeReport);
      expect(lossy.accounts.single.allowances.first.usedPercent, 10);
      expect(
        lossy.accounts.single.allowances.first.recoveryRequirements!.complete,
        isFalse,
      );
      expect(
        reconcilePlanRecoveries(lossy, initial.pending).recoveries,
        isEmpty,
      );
    },
  );

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
                'requirements': {
                  'allowanceIds': [1],
                  'complete': true,
                },
              },
            ]),
          ).single;
      expect(invalid.key, key);
      expect(invalid.requirements, isNull);
    },
  );

  test('fixed snapshot codecs preserve requirements and raw reset facts', () {
    final snapshot = DashboardSnapshot.fromJsonString(
      File('../../fixtures/snapshots/dashboard_today.json').readAsStringSync(),
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

final class _UsageTransport implements CodexHttpTransport {
  _UsageTransport(this.raw);

  final Map<String, dynamic> raw;

  @override
  Future<CodexHttpResponse> send(
    String method,
    Uri uri, {
    required Map<String, String> headers,
    String? body,
  }) async {
    final response = switch (uri.path) {
      '/backend-api/wham/usage' => raw,
      '/backend-api/wham/profiles/me' => {
        'stats': {'daily_usage_buckets': []},
      },
      _ => throw StateError('Unexpected synthetic request.'),
    };
    return CodexHttpResponse(statusCode: 200, body: jsonEncode(response));
  }
}
