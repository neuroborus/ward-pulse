import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ward_pulse_phone/dashboard/dashboard_models.dart';
import 'package:ward_pulse_phone/settings/watch_ring_preferences.dart';
import 'package:ward_pulse_phone/widget/phone_widget_preferences.dart';

void main() {
  test('defaults are unset and clamp to large slot count', () {
    const prefs = PhoneWidgetPreferences();
    expect(prefs.usesDefaults, isTrue);
    expect(prefs.migratedIds, isEmpty);
    expect(phoneWidgetSlotCount, 6);
    expect(phoneWidgetSlotCount, greaterThan(watchRingSlotCount));
  });

  test('migrate expands collapsed Claude plan alias to window ids', () {
    final migrated = migratePhoneWidgetSelectedIds([
      claudePlanRingId,
      'allowance.cursor.cursor-plan-models',
    ]);
    expect(migrated.first, 'allowance.claude.claude-five-hour');
    expect(migrated, contains('allowance.claude.claude-seven-day'));
    expect(migrated, contains('allowance.cursor.cursor-plan-models'));
    expect(migrated, isNot(contains(claudePlanRingId)));
    expect(migrated.length, lessThanOrEqualTo(phoneWidgetSlotCount));
  });

  test('migrate keeps Claude windows and purchased meters expanded', () {
    final migrated = migratePhoneWidgetSelectedIds([
      'allowance.claude.claude-five-hour',
      'allowance.claude.claude-extra-usage',
      'budget.today',
      'allowance.claude.claude-seven-day',
      claudePlanRingId,
    ]);
    expect(migrated, [
      'allowance.claude.claude-five-hour',
      'allowance.claude.claude-extra-usage',
      'budget.today',
      'allowance.claude.claude-seven-day',
      'allowance.claude.claude-seven-day-opus',
      'allowance.claude.claude-seven-day-sonnet',
    ]);
    expect(migrated, isNot(contains(claudePlanRingId)));
  });

  test('phone widget catalog expands Claude windows and purchased meters', () {
    final base = DashboardSnapshot.fromJsonString(
      File('../../fixtures/snapshots/dashboard_today.json').readAsStringSync(),
    );
    final mock = Map<String, Object?>.from(
      (base.toJson()['accounts'] as List).first as Map,
    );
    final claude = {
      ...mock,
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
          'id': 'claude-seven-day',
          'source': 'plan',
          'label': 'Weekly',
          'usedPercent': 55.0,
          'used': null,
          'limit': null,
          'remaining': null,
          'unlimited': false,
          'windowMinutes': 10080,
          'resetsAt': null,
          'status': 'ok',
        },
        {
          'id': 'claude-extra-usage',
          'source': 'purchased',
          'label': 'Extra usage',
          'usedPercent': 20.0,
          'used': null,
          'limit': null,
          'remaining': null,
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
    final snapshot = DashboardSnapshot.fromJson({
      ...base.toJson(),
      'accounts': [claude],
    });

    final widgetIds = phoneWidgetCatalog(snapshot).map((m) => m.id).toSet();
    final watchIds = watchRingCatalog(snapshot).map((m) => m.id).toSet();
    expect(widgetIds, contains('allowance.claude.claude-five-hour'));
    expect(widgetIds, contains('allowance.claude.claude-seven-day'));
    expect(widgetIds, contains('allowance.claude.claude-extra-usage'));
    expect(widgetIds, isNot(contains(claudePlanRingId)));
    expect(watchIds, contains(claudePlanRingId));
    expect(watchIds, isNot(contains('allowance.claude.claude-extra-usage')));
  });

  test('defaults prefer plan windows including exhausted Cursor pools', () {
    final base = DashboardSnapshot.fromJsonString(
      File('../../fixtures/snapshots/dashboard_today.json').readAsStringSync(),
    );
    final account = Map<String, Object?>.from(base.primaryAccount!.toJson());
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
          'id': 'claude-seven-day',
          'source': 'plan',
          'label': 'Weekly',
          'usedPercent': 55.0,
          'used': null,
          'limit': null,
          'remaining': null,
          'unlimited': false,
          'windowMinutes': 10080,
          'resetsAt': null,
          'status': 'ok',
        },
        {
          'id': 'claude-extra-usage',
          'source': 'purchased',
          'label': 'Extra usage',
          'usedPercent': 10.0,
          'used': null,
          'limit': null,
          'remaining': null,
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
    final cursor = {
      ...account,
      'accountId': 'cursor-local',
      'provider': 'cursor',
      'status': 'rateLimited',
      'allowances': [
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
      ],
      'buckets': <Object?>[],
      'modelBreakdown': <Object?>[],
      'credits': <Object?>[],
    };
    final snapshot = DashboardSnapshot.fromJson({
      ...base.toJson(),
      'accounts': [claude, cursor],
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

    final labels =
        resolvePhoneWidgetMetrics(
          snapshot,
          const PhoneWidgetPreferences(),
        ).map((m) => m.label).toList();
    expect(
      labels,
      containsAll(['5h', 'Weekly', 'Cursor Models', 'Other Models']),
    );
    expect(labels.indexOf('5h'), lessThan(labels.indexOf('Extra usage')));

    // The preview names families too, or two `Weekly plan` rows read alike.
    expect(
      phoneWidgetPayloadSubtitle(snapshot, const PhoneWidgetPreferences()),
      contains('Cursor · Other Models'),
    );
  });
}
