import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ward_pulse_phone/charts/usage_history_chart.dart';
import 'package:ward_pulse_phone/dashboard/dashboard_models.dart';

void main() {
  testWidgets('shows the total and dates for daily buckets', (tester) async {
    final buckets = [
      _bucket(DateTime.utc(2026, 7, 12), 120),
      _bucket(DateTime.utc(2026, 7, 13), 230),
    ];

    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: UsageHistoryChart(buckets: buckets))),
    );

    expect(find.text('USD 3.50'), findsOneWidget);
    expect(find.text('2026-07-12'), findsOneWidget);
    expect(find.text('2026-07-14'), findsOneWidget);
  });
}

UsageBucket _bucket(DateTime start, int minorUnits) {
  return UsageBucket(
    startAt: start,
    endAt: start.add(const Duration(days: 1)),
    cost: Money(minorUnits: minorUnits, currency: 'USD'),
    inputTokens: null,
    outputTokens: null,
    cachedTokens: null,
    requests: null,
    model: null,
  );
}
