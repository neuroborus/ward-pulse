import 'package:flutter_test/flutter_test.dart';
import 'package:ward_pulse_phone/dashboard/connected_capabilities.dart';
import 'package:ward_pulse_phone/dashboard/dashboard_models.dart';

void main() {
  test('derives plan and spend capabilities from connected providers', () {
    final openAi = ConnectedCapabilities.fromAccounts([_account('openai')]);
    expect(openAi.showBudgets, isTrue);
    expect(openAi.showAllowances, isFalse);
    expect(openAi.showPlanGap, isTrue);
    expect(openAi.showSpendGap, isFalse);
    expect(openAi.showModelUsage, isTrue);

    final codex = ConnectedCapabilities.fromAccounts([_account('codex')]);
    expect(codex.showBudgets, isFalse);
    expect(codex.showAllowances, isTrue);
    expect(codex.showPlanGap, isFalse);
    expect(codex.showSpendGap, isTrue);
    expect(codex.showModelUsage, isFalse);

    final both = ConnectedCapabilities.fromAccounts([
      _account('openai'),
      _account('codex'),
    ]);
    expect(both.showBudgets, isTrue);
    expect(both.showAllowances, isTrue);
    expect(both.showPlanGap, isFalse);
    expect(both.showSpendGap, isFalse);
  });

  test('treats mock as a full dashboard without capability gaps', () {
    final mock = ConnectedCapabilities.fromAccounts([_account('mock')]);
    expect(mock.isMock, isTrue);
    expect(mock.showBudgets, isTrue);
    expect(mock.showPlanGap, isFalse);
    expect(mock.showSpendGap, isFalse);
  });

  test('keeps Claude and Cursor plan-only out of spend surfaces', () {
    final claudePlan = ConnectedCapabilities.fromAccounts([
      _account('claude', allowances: true),
    ]);
    expect(claudePlan.showAllowances, isTrue);
    expect(claudePlan.showBudgets, isFalse);
    expect(claudePlan.showSpendGap, isTrue);
    expect(claudePlan.showUsageHistory, isFalse);
    expect(claudePlan.showModelUsage, isFalse);

    final cursorTeam = ConnectedCapabilities.fromAccounts([
      _account('cursor', spent: true, buckets: true),
    ]);
    expect(cursorTeam.showBudgets, isTrue);
    expect(cursorTeam.showAllowances, isFalse);
    expect(cursorTeam.showUsageHistory, isTrue);
    expect(cursorTeam.showPlanGap, isTrue);
  });
}

ProviderSnapshot _account(
  String provider, {
  bool allowances = false,
  bool spent = false,
  bool buckets = false,
}) {
  return ProviderSnapshot.fromJson({
    'accountId': '$provider-local',
    'provider': provider,
    'status': 'ok',
    'today': _budget('today', spent: spent),
    'week': _budget('week'),
    'month': _budget('month'),
    'credits': <Object>[],
    'allowances':
        allowances
            ? [
              {
                'id': '$provider-plan',
                'label': 'Plan',
                'source': 'plan',
                'used': {'value': '1', 'unit': 'tokens'},
                'limit': {'value': '10', 'unit': 'tokens'},
                'remaining': {'value': '9', 'unit': 'tokens'},
                'usedPercent': 10,
                'unlimited': false,
                'windowMinutes': null,
                'resetsAt': null,
                'status': 'ok',
              },
            ]
            : <Object>[],
    'buckets':
        buckets
            ? [
              {
                'startAt': '2026-07-01T00:00:00Z',
                'endAt': '2026-07-02T00:00:00Z',
                'cost': null,
                'inputTokens': null,
                'outputTokens': null,
                'cachedTokens': null,
                'totalTokens': null,
                'requests': 1,
                'model': null,
                'project': null,
                'user': null,
              },
            ]
            : <Object>[],
    'modelBreakdown': <Object>[],
    'lastSuccessfulSyncAt': null,
    'lastError': null,
  });
}

Map<String, Object?> _budget(String period, {bool spent = false}) => {
  'period': period,
  'spent': spent ? {'minorUnits': 100, 'currency': 'USD'} : null,
  'limit': null,
  'remaining': null,
  'usedPercent': null,
  'projectedTotal': null,
  'status': spent ? 'ok' : 'unknown',
};
