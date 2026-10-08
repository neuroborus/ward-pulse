import 'package:flutter_test/flutter_test.dart';
import 'package:ward_pulse_phone/dashboard/dashboard_models.dart';
import 'package:ward_pulse_phone/sync/watch_credits_glance.dart';

void main() {
  test('compacts credit counts without a TOK suffix', () {
    expect(compactCreditCount(500), '500');
    expect(compactCreditCount(12.5), '12.5');
    expect(compactCreditCount(12_400), '12.4K');
    expect(compactCreditCount(1_400_000), '1.4M');
  });

  test('resolves remaining purchased credits', () {
    final snapshot = _snapshotWithPurchased(remaining: '500');
    final glance = resolveWatchCreditsGlance(snapshot);
    expect(glance, isNotNull);
    expect(glance!.text, '500');
    expect(glance.label, 'Credits left');
    expect(glance.provider, 'codex');
  });

  test('shows infinity for unlimited purchased credits', () {
    final snapshot = _snapshotWithPurchased(remaining: null, unlimited: true);
    final glance = resolveWatchCreditsGlance(snapshot);
    expect(glance?.text, '∞');
  });
}

DashboardSnapshot _snapshotWithPurchased({
  required String? remaining,
  bool unlimited = false,
}) {
  return DashboardSnapshot.fromJson({
    'generatedAt': '2026-07-25T12:00:00Z',
    'overallStatus': 'ok',
    'accounts': [
      {
        'accountId': 'codex-local',
        'provider': 'codex',
        'status': 'ok',
        'today': _unknownBudget('today'),
        'week': _unknownBudget('week'),
        'month': _unknownBudget('month'),
        'credits': <Object>[],
        'allowances': [
          {
            'id': 'purchased',
            'source': 'purchased',
            'label': 'Purchased credits',
            'usedPercent': null,
            'used': null,
            'limit': null,
            'remaining':
                remaining == null
                    ? null
                    : {'value': remaining, 'unit': 'credits'},
            'unlimited': unlimited,
            'windowMinutes': null,
            'resetsAt': null,
            'status': 'ok',
          },
        ],
        'buckets': <Object>[],
        'modelBreakdown': <Object>[],
        'lastSuccessfulSyncAt': '2026-07-25T12:00:00Z',
        'lastError': null,
      },
    ],
    'todayTotal': _unknownBudget('today'),
    'weekTotal': _unknownBudget('week'),
    'monthTotal': _unknownBudget('month'),
    'alerts': <Object>[],
    'watchSummary': {
      'todayUsedPercent': null,
      'weekUsedPercent': null,
      'status': 'ok',
    },
  });
}

Map<String, Object?> _unknownBudget(String period) => {
  'period': period,
  'spent': null,
  'limit': null,
  'remaining': null,
  'usedPercent': null,
  'projectedTotal': null,
  'status': 'unknown',
};
