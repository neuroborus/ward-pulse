import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ward_pulse_phone/app/ward_pulse_app.dart';
import 'package:ward_pulse_phone/dashboard/dashboard_models.dart';
import 'package:ward_pulse_phone/dashboard/dashboard_repository.dart';

void main() {
  testWidgets('renders the mock dashboard snapshot', (tester) async {
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
    expect(find.text('Mock'), findsWidgets);
    expect(find.text('mock-fast'), findsOneWidget);
    expect(find.text('No alerts'), findsOneWidget);
  });
}
