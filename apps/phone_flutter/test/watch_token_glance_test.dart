import 'package:flutter_test/flutter_test.dart';
import 'package:ward_pulse_phone/dashboard/dashboard_models.dart';
import 'package:ward_pulse_phone/sync/watch_token_glance.dart';

void main() {
  test('compacts token counts for glanceable surfaces', () {
    expect(compactTokenCount(420), '420');
    expect(compactTokenCount(12_400), '12.4K');
    expect(compactTokenCount(999_949), '999.9K');
    expect(compactTokenCount(999_950), '1M');
    expect(compactTokenCount(1_400_000), '1.4M');
    expect(compactTokenCount(999_949_999), '999.9M');
    expect(compactTokenCount(999_950_000), '1B');
    expect(compactTokenCount(1_400_000_000), '1.4B');
    expect(compactTokenCount(1_400_000_000_000), '1.4T');
  });

  test('resolves today tokens from a live provider bucket', () {
    final snapshot = DashboardSnapshot.fromJson({
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
          'allowances': <Object>[],
          'buckets': [
            {
              'startAt': '2026-07-25T00:00:00Z',
              'endAt': '2026-07-26T00:00:00Z',
              'cost': null,
              'inputTokens': null,
              'outputTokens': null,
              'cachedTokens': null,
              'totalTokens': 1_401_695_877,
              'requests': null,
              'model': null,
              'project': null,
              'user': null,
            },
          ],
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

    final glance = resolveWatchTokenGlance(snapshot);
    expect(glance, isNotNull);
    expect(glance!.text, '1.4B TOK');
    expect(glance.label, 'Today tokens');
    expect(glance.provider, 'codex');
  });

  test('omits token glance when today totals are zero', () {
    final snapshot = DashboardSnapshot.fromJson({
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
          'allowances': <Object>[],
          'buckets': [
            {
              'startAt': '2026-07-25T00:00:00Z',
              'endAt': '2026-07-26T00:00:00Z',
              'cost': null,
              'inputTokens': null,
              'outputTokens': null,
              'cachedTokens': null,
              'totalTokens': 0,
              'requests': null,
              'model': null,
              'project': null,
              'user': null,
            },
          ],
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

    expect(resolveWatchTokenGlance(snapshot), isNull);
  });

  test('skips mock accounts for token glance', () {
    final snapshot = DashboardSnapshot.fromJson({
      'generatedAt': '2026-06-27T18:42:00Z',
      'overallStatus': 'ok',
      'accounts': [
        {
          'accountId': 'mock-local',
          'provider': 'mock',
          'status': 'ok',
          'today': _unknownBudget('today'),
          'week': _unknownBudget('week'),
          'month': _unknownBudget('month'),
          'credits': <Object>[],
          'allowances': <Object>[],
          'buckets': [
            {
              'startAt': '2026-06-27T00:00:00Z',
              'endAt': '2026-06-28T00:00:00Z',
              'cost': null,
              'inputTokens': 1000,
              'outputTokens': 200,
              'cachedTokens': null,
              'totalTokens': 1200,
              'requests': null,
              'model': null,
              'project': null,
              'user': null,
            },
          ],
          'modelBreakdown': <Object>[],
          'lastSuccessfulSyncAt': null,
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

    expect(resolveWatchTokenGlance(snapshot), isNull);
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
