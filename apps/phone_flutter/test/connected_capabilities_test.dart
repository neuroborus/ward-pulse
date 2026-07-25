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
}

ProviderSnapshot _account(String provider) {
  return ProviderSnapshot.fromJson({
    'accountId': '$provider-local',
    'provider': provider,
    'status': 'ok',
    'today': _budget('today'),
    'week': _budget('week'),
    'month': _budget('month'),
    'credits': <Object>[],
    'allowances': <Object>[],
    'buckets': <Object>[],
    'modelBreakdown': <Object>[],
    'lastSuccessfulSyncAt': null,
    'lastError': null,
  });
}

Map<String, Object?> _budget(String period) => {
  'period': period,
  'spent': null,
  'limit': null,
  'remaining': null,
  'usedPercent': null,
  'projectedTotal': null,
  'status': 'unknown',
};
