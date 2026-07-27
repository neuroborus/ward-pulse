import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ward_pulse_phone/dashboard/dashboard_models.dart';
import 'package:ward_pulse_phone/settings/watch_ring_preferences.dart';
import 'package:ward_pulse_phone/widget/phone_widget_preferences.dart';

void main() {
  test('defaults are unset and clamp to medium slot count', () {
    const prefs = PhoneWidgetPreferences();
    expect(prefs.usesDefaults, isTrue);
    expect(prefs.migratedIds, isEmpty);
    expect(phoneWidgetSlotCount, greaterThan(watchRingSlotCount));
  });

  test('migrate keeps purchased meters and collapses Claude plan windows', () {
    final migrated = migratePhoneWidgetSelectedIds([
      'allowance.claude.claude-five-hour',
      'allowance.claude.claude-extra-usage',
      'budget.today',
      'allowance.claude.claude-seven-day',
    ]);
    expect(migrated, [
      claudePlanRingId,
      'allowance.claude.claude-extra-usage',
      'budget.today',
    ]);
  });

  test('phone widget catalog includes purchased meters', () {
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
    expect(widgetIds, contains(claudePlanRingId));
    expect(widgetIds, contains('allowance.claude.claude-extra-usage'));
    expect(watchIds, isNot(contains('allowance.claude.claude-extra-usage')));
  });
}
