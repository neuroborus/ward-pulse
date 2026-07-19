import 'dart:ui' as ui;

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

  testWidgets('renders dense token history without inventing zero usage', (
    tester,
  ) async {
    final denseBuckets = List.generate(
      31,
      (index) => _tokenBucket(DateTime.utc(2026, 6, index + 1), index + 1),
    );
    final densePainter = await _pumpChart(tester, denseBuckets);

    expect(
      await tester.runAsync(() => _primaryPixelCount(densePainter)),
      greaterThan(0),
    );

    final zeroPainter = await _pumpChart(tester, [
      _tokenBucket(DateTime.utc(2026, 7), 0),
    ]);

    expect(await tester.runAsync(() => _primaryPixelCount(zeroPainter)), 0);
  });

  testWidgets('does not repaint unchanged values', (tester) async {
    final oldPainter = await _pumpChart(tester, [
      _tokenBucket(DateTime.utc(2026, 7), 42),
    ]);
    final newPainter = await _pumpChart(tester, [
      _tokenBucket(DateTime.utc(2026, 7), 42),
    ]);

    expect(newPainter.shouldRepaint(oldPainter), isFalse);
  });
}

Future<CustomPainter> _pumpChart(
  WidgetTester tester,
  List<UsageBucket> buckets,
) async {
  final colors = ColorScheme.fromSeed(seedColor: Colors.red).copyWith(
    primary: const Color(0xFFFF0000),
    outlineVariant: const Color(0xFF0000FF),
  );
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(colorScheme: colors),
      home: Scaffold(body: UsageHistoryChart(buckets: buckets)),
    ),
  );
  return tester
      .widget<CustomPaint>(find.byKey(const ValueKey('usage-history-bars')))
      .painter!;
}

Future<int> _primaryPixelCount(CustomPainter painter) async {
  const size = Size(240, 112);
  final recorder = ui.PictureRecorder();
  painter.paint(Canvas(recorder), size);
  final picture = recorder.endRecording();
  final image = await picture.toImage(size.width.toInt(), size.height.toInt());
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  image.dispose();
  picture.dispose();
  final bytes = data!.buffer.asUint8List();
  var count = 0;
  for (var offset = 0; offset < bytes.length; offset += 4) {
    if (bytes[offset] > 200 &&
        bytes[offset + 1] < 50 &&
        bytes[offset + 2] < 50 &&
        bytes[offset + 3] > 0) {
      count += 1;
    }
  }
  return count;
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

UsageBucket _tokenBucket(DateTime start, int tokens) {
  return UsageBucket(
    startAt: start,
    endAt: start.add(const Duration(days: 1)),
    cost: null,
    inputTokens: null,
    outputTokens: null,
    cachedTokens: null,
    reportedTotalTokens: tokens,
    requests: null,
    model: null,
  );
}
