import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ward_pulse_phone/dashboard/dashboard_models.dart';
import 'package:ward_pulse_phone/widget/phone_widget_payload.dart';
import 'package:ward_pulse_phone/widget/phone_widget_preferences.dart';

void main() {
  final snapshot = DashboardSnapshot.fromJsonString(
    File('../../fixtures/snapshots/dashboard_today.json').readAsStringSync(),
  );

  test('builds remaining rows and omits exhausted metrics', () {
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
    expect(
      phoneWidgetAccentArgb('budget.today'),
      greaterThan(0),
    );
    expect(
      phoneWidgetAccentArgb('allowance.claude.plan'),
      isNot(phoneWidgetAccentArgb('budget.today')),
    );
  });
}
