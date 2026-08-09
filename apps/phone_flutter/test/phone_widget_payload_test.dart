import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ward_pulse_phone/dashboard/dashboard_models.dart';
import 'package:ward_pulse_phone/dashboard/provider_status_color.dart';
import 'package:ward_pulse_phone/widget/phone_widget_payload.dart';
import 'package:ward_pulse_phone/widget/phone_widget_preferences.dart';

void main() {
  final snapshot = DashboardSnapshot.fromJsonString(
    File('../../fixtures/snapshots/dashboard_today.json').readAsStringSync(),
  );

  test('builds remaining rows from available percent metrics', () {
    final payload = buildPhoneWidgetPayload(
      _asConnection(snapshot),
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

  test('family accents follow the family named in the metric id', () {
    final claude = providerFamilyColor('claude').toARGB32();
    expect(phoneWidgetAccentArgb('allowance.claude.plan'), claude);
    // A budget ring carries its connection, so it takes that family too.
    expect(phoneWidgetAccentArgb('budget.anthropic.platform.month'), claude);
    expect(
      phoneWidgetAccentArgb('budget.openai.platform.today'),
      providerFamilyColor('codex').toARGB32(),
    );
    // No family named in the id: fall back to the neutral budget accent.
    expect(
      phoneWidgetAccentArgb('budget.mock.plan.today'),
      familyBudgetColor.toARGB32(),
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
      containsAll(['Cursor Models', 'Cursor · Other Models']),
    );
    expect(
      payload.rows
          .firstWhere((row) => row.label == 'Cursor Models')
          .remainingPercent,
      0,
    );
  });

  test('appends per-provider purchased credits like Wear Glance', () {
    final account = Map<String, Object?>.from(
      snapshot.primaryAccount!.toJson(),
    );
    final claude = {
      ...account,
      'accountId': 'claude-1',
      'provider': 'claude',
      'allowances': [
        {
          'id': 'claude-five-hour',
          'source': 'plan',
          'label': '5h',
          'usedPercent': 40.0,
          'used': null,
          'limit': null,
          'remaining': null,
          'unlimited': false,
          'windowMinutes': 300,
          'resetsAt': null,
          'status': 'ok',
        },
        {
          'id': 'claude-extra-usage',
          'source': 'purchased',
          'label': 'Extra usage',
          'usedPercent': 20.0,
          'used': {'value': '80', 'unit': 'credits'},
          'limit': {'value': '100', 'unit': 'credits'},
          'remaining': {'value': '320', 'unit': 'credits'},
          'unlimited': false,
          'windowMinutes': null,
          'resetsAt': null,
          'status': 'ok',
        },
      ],
      'buckets': <Object?>[],
      'modelBreakdown': <Object?>[],
      'credits': <Object?>[],
    };
    final withCredits = DashboardSnapshot.fromJson({
      ...snapshot.toJson(),
      'accounts': [claude],
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
      withCredits,
      const PhoneWidgetPreferences(
        selectedIds: ['allowance.claude.claude-five-hour'],
      ),
    );
    expect(payload.rows, hasLength(1));
    expect(payload.rows.single.creditsSuffix, '320 credits');
    expect(payload.rows.single.percentText, '60% left');
    expect(payload.rows.single.label, 'Claude · 5h');
    expect(payload.rows.single.line, '60% left · Claude · 5h · 320 credits');
    expect(
      phoneWidgetCreditsSuffix(withCredits, 'budget.anthropic.platform.today'),
      isNull,
      reason: 'budget rings track spend, not a credit pool',
    );
    expect(
      phoneWidgetCreditsSuffix(
        withCredits,
        'allowance.claude.claude-extra-usage',
      ),
      isNull,
      reason: 'purchased-meter rows are the credit pool; do not repeat credits',
    );
  });
}

/// Mock fixture as a real connection: mock accounts hold no metric slots.
DashboardSnapshot _asConnection(DashboardSnapshot snapshot) {
  final account =
      Map<String, Object?>.from(snapshot.primaryAccount!.toJson())
        ..['accountId'] = 'anthropic-platform'
        ..['provider'] = 'claude'
        ..['connection'] = 'anthropic.platform';
  return DashboardSnapshot.fromJson({
    ...snapshot.toJson(),
    'accounts': [account],
  });
}
