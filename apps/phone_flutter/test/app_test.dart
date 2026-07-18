import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ward_pulse_phone/app/ward_pulse_app.dart';
import 'package:ward_pulse_phone/dashboard/dashboard_models.dart';
import 'package:ward_pulse_phone/dashboard/dashboard_repository.dart';

void main() {
  testWidgets('renders mock history and opens provider details', (tester) async {
    final fixture = File(
      '../../fixtures/snapshots/dashboard_today.json',
    ).readAsStringSync();
    final snapshot = DashboardSnapshot.fromJsonString(fixture);

    await tester.pumpWidget(
      WardPulseApp(repository: ValueDashboardRepository(snapshot)),
    );
    await tester.pumpAndSettle();

    expect(find.text('WardPulse'), findsOneWidget);
    expect(find.text('Today'), findsWidgets);

    final dashboard = find.byType(Scrollable).first;
    await tester.scrollUntilVisible(
      find.text('Usage history'),
      300,
      scrollable: dashboard,
    );
    expect(find.text('Usage history'), findsOneWidget);
    expect(find.text('4 buckets'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('mock-fast'),
      300,
      scrollable: dashboard,
    );
    expect(find.text('mock-fast'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('No alerts'),
      300,
      scrollable: dashboard,
    );
    expect(find.text('No alerts'), findsOneWidget);

    await tester.tap(find.text('Providers'));
    await tester.pumpAndSettle();

    expect(find.text('Mock'), findsOneWidget);
    await tester.tap(find.text('Mock'));
    await tester.pumpAndSettle();

    expect(find.text('mock-local'), findsOneWidget);
    expect(find.text('Today'), findsOneWidget);
  });
}
