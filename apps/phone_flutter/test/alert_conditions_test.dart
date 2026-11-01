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
