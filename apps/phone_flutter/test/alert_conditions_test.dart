import 'package:flutter_test/flutter_test.dart';
import 'package:ward_pulse_phone/dashboard/dashboard_models.dart';

void main() {
  const keyJson = {
    'provider': 'claude',
    'accountId': 'account-a',
    'connection': 'anthropic.plan',
    'target': {'kind': 'allowance', 'source': 'plan', 'id': 'shared-id'},
  };

  test('legacy and explicitly empty observations keep the old JSON shape', () {
    final legacy =
        DashboardSnapshot.empty(
          generatedAt: DateTime.utc(2026, 10, 16),
        ).toJson();
    expect(legacy, isNot(contains('alertConditions')));
    for (final json in [
      legacy,
      {...legacy, 'alertConditions': <Object>[]},
    ]) {
      final decoded = DashboardSnapshot.fromJson(json);
      expect(decoded.alertConditions, isEmpty);
      expect(decoded.toJson(), legacy);
    }
  });

  test(
    'history owners survive account copies and qualify typed key equality',
    () {
      final ownerJson = {
        'connection': 'anthropic.plan',
        'identity': List.filled(64, 'a').join(),
      };
      final base =
          DashboardSnapshot.empty(
            generatedAt: DateTime.utc(2026, 10, 16),
          ).toJson();
      final encoded = {
        ...base,
        'accounts': [
          {
            'accountId': 'account-a',
            'provider': 'claude',
            'connection': 'anthropic.plan',
            'historyOwner': ownerJson,
            'status': 'ok',
            'today': base['todayTotal'],
            'week': base['weekTotal'],
            'month': base['monthTotal'],
            'credits': <Object>[],
            'allowances': <Object>[],
            'buckets': <Object>[],
            'modelBreakdown': <Object>[],
            'lastSuccessfulSyncAt': null,
            'lastError': null,
          },
        ],
        'alertConditions': [
          {
            'key': {...keyJson, 'historyOwner': ownerJson},
            'state': 'unknown',
          },
        ],
      };
      final snapshot = DashboardSnapshot.fromJson(encoded);
      final key = snapshot.alertConditions.single.key;
      expect(snapshot.toJson(), encoded);
      expect(key.historyOwner, snapshot.accounts.single.historyOwner);
      expect(key, AlertConditionKey.fromJson(key.toJson()));
      final otherKeys = [
        AlertConditionKey.fromJson(keyJson),
        for (final owner in [
          {...ownerJson, 'identity': List.filled(64, 'b').join()},
          {...ownerJson, 'connection': 'other-connection'},
        ])
          AlertConditionKey.fromJson({...keyJson, 'historyOwner': owner}),
      ];
      expect({
        key,
        AlertConditionKey.fromJson(key.toJson()),
        ...otherKeys,
      }, hasLength(4));
      for (final copy in [
        DashboardSnapshot.fromJsonString(snapshot.toJsonString()),
        snapshot.withStaleStatus(),
        snapshot.withSyncIssue(DashboardSyncIssue.rateLimited),
        snapshot.withConnectionVersions(const {}),
        snapshot.withReportingOutcomes(const []),
      ]) {
        expect(copy.accounts.single.historyOwner, key.historyOwner);
        expect(copy.accounts.single.toJson()['historyOwner'], ownerJson);
        expect(copy.alertConditions.single.key, key);
        expect(copy.watchSummary.toJson(), isNot(contains('historyOwner')));
      }
    },
  );

  test('typed observations round-trip and survive every snapshot copy', () {
    const alert = {
      'severity': 'warning',
      'message': 'Identical threshold copy',
    };
    final encoded = {
      ...DashboardSnapshot.empty(
        generatedAt: DateTime.utc(2026, 10, 16),
      ).toJson(),
      'alerts': [alert, alert],
      'alertConditions': [
        {'key': keyJson, 'state': 'crossed', 'alert': alert},
        {
          'key': {
            ...keyJson,
            'target': {
              'kind': 'allowance',
              'source': 'purchased',
              'id': 'shared-id',
            },
          },
          'state': 'crossed',
          'alert': alert,
        },
        {
          'key': {
            ...keyJson,
            'target': {'kind': 'budget', 'period': 'week'},
          },
          'state': 'clear',
        },
        {
          'key': {
            ...keyJson,
            'target': {'kind': 'budget', 'period': 'month'},
          },
          'state': 'unknown',
        },
      ],
    };
    final snapshot = DashboardSnapshot.fromJson(encoded);
    expect(snapshot.toJson(), encoded);
    expect(snapshot.alertConditions.map((condition) => condition.state), [
      AlertConditionState.crossed,
      AlertConditionState.crossed,
      AlertConditionState.clear,
      AlertConditionState.unknown,
    ]);
    final keys =
        snapshot.alertConditions.map((condition) => condition.key).toSet();
    expect(keys, hasLength(4));
    expect(keys, contains(AlertConditionKey.fromJson(keyJson)));
    for (final entry
        in {
          'provider': 'codex',
          'accountId': 'account-b',
          'connection': 'other-connection',
        }.entries) {
      expect(
        AlertConditionKey.fromJson({...keyJson, entry.key: entry.value}),
        isNot(snapshot.alertConditions.first.key),
      );
    }
    for (final copy in [
      snapshot.withStaleStatus(),
      snapshot.withSyncIssue(DashboardSyncIssue.rateLimited),
      snapshot.withConnectionVersions({
        'anthropic.plan': {'revision': 'r1'},
      }),
      snapshot.withReportingOutcomes(const []),
    ]) {
      expect(copy.toJson()['alertConditions'], encoded['alertConditions']);
      expect(
        copy.alertConditions.map((condition) => condition.key).toSet(),
        keys,
      );
    }
  });

  test(
    'unrecognized observations are rejected instead of inferred as clear',
    () {
      expect(
        () => AlertCondition.fromJson({'key': keyJson, 'state': 'unsupported'}),
        throwsArgumentError,
      );
      expect(
        () => AlertCondition.fromJson({
          'key': {
            ...keyJson,
            'target': {'kind': 'unsupported'},
          },
          'state': 'clear',
        }),
        throwsFormatException,
      );
      expect(
        () => AlertCondition.fromJson({
          'key': keyJson,
          'state': 'unknown',
          'alert': {
            'severity': 'warning',
            'message': 'Not a crossed observation',
          },
        }),
        throwsFormatException,
      );
    },
  );
}
