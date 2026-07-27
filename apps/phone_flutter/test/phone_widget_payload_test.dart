import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ward_pulse_phone/dashboard/dashboard_models.dart';
import 'package:ward_pulse_phone/widget/phone_widget_payload.dart';
import 'package:ward_pulse_phone/widget/phone_widget_preferences.dart';

void main() {
  final snapshot = DashboardSnapshot.fromJsonString(
    File('../../fixtures/snapshots/dashboard_today.json').readAsStringSync(),
  );

  test('builds remaining rows from available percent metrics', () {
    final payload = buildPhoneWidgetPayload(
      snapshot,
      const PhoneWidgetPreferences(),
    );
    expect(payload.stale, isFalse);
    expect(payload.rows, isNotEmpty);
    for (final row in payload.rows) {
      expect(row.remainingPercent, inInclusiveRange(0, 100));
      expect(row.line, contains('% left ·'));
    }
  });

  test('marks stale when overall status is stale', () {
    final stale = snapshot.withStaleStatus(
      syncIssue: DashboardSyncIssue.authentication,
    );
    final payload = buildPhoneWidgetPayload(
      stale,
      const PhoneWidgetPreferences(),
    );
    expect(payload.stale, isTrue);
  });

  test('empty selection yields empty payload', () {
    final payload = buildPhoneWidgetPayload(
      snapshot,
      const PhoneWidgetPreferences(selectedIds: []),
    );
    expect(payload.isEmpty, isTrue);
    expect(payload.rows, isEmpty);
  });

  test('family accents map metric ids', () {
    expect(phoneWidgetAccentArgb('budget.today'), greaterThan(0));
    expect(
      phoneWidgetAccentArgb('allowance.claude.plan'),
      isNot(phoneWidgetAccentArgb('budget.today')),
    );
  });

  test('keeps exhausted Cursor Models as 0% left beside Other Models', () {
    final cursor =
        snapshot.primaryAccount!.toJson()
          ..['accountId'] = 'cursor-local'
          ..['provider'] = 'cursor'
          ..['status'] = 'rateLimited'
          ..['allowances'] = [
            {
              'id': 'cursor-plan-models',
              'source': 'plan',
              'label': 'Cursor Models',
              'usedPercent': 100.0,
              'used': null,
              'limit': null,
              'remaining': null,
              'unlimited': false,
              'windowMinutes': null,
              'resetsAt': null,
              'status': 'rateLimited',
            },
            {
              'id': 'cursor-plan-other',
              'source': 'plan',
              'label': 'Other Models',
              'usedPercent': 40.0,
              'used': null,
              'limit': null,
              'remaining': null,
              'unlimited': false,
              'windowMinutes': null,
              'resetsAt': null,
              'status': 'ok',
            },
          ]
          ..['buckets'] = <Object>[]
          ..['modelBreakdown'] = <Object>[];
    final withCursor = DashboardSnapshot.fromJson({
      ...snapshot.toJson(),
      'accounts': [cursor],
      'todayTotal': {
        'period': 'today',
        'spent': null,
        'limit': null,
        'remaining': null,
        'usedPercent': null,
        'projectedTotal': null,
        'status': 'unknown',
        'statusExplanation': null,
      },
      'weekTotal': {
        'period': 'week',
        'spent': null,
        'limit': null,
        'remaining': null,
        'usedPercent': null,
        'projectedTotal': null,
        'status': 'unknown',
        'statusExplanation': null,
      },
      'monthTotal': {
        'period': 'month',
        'spent': null,
        'limit': null,
        'remaining': null,
        'usedPercent': null,
        'projectedTotal': null,
        'status': 'unknown',
        'statusExplanation': null,
      },
    });

    final payload = buildPhoneWidgetPayload(
      withCursor,
      const PhoneWidgetPreferences(),
    );
    expect(
      payload.rows.map((row) => row.label),
      containsAll(['Cursor Models', 'Other Models']),
    );
    expect(
      payload.rows
          .firstWhere((row) => row.label == 'Cursor Models')
          .remainingPercent,
      0,
    );
  });
}
