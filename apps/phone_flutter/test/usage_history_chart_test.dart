import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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

  testWidgets('separates a wrapped history title from its bucket count', (
    tester,
  ) async {
    const size = Size(411, 900);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    const title = 'Anthropic · Organization reporting · Usage history';
    final buckets = List.generate(
      5,
      (index) => _bucket(DateTime.utc(2026, 7, 12 + index), 1),
    );

    await tester.pumpWidget(
      MaterialApp(
        builder:
            (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(1.6)),
              child: child!,
            ),
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(16),
            child: UsageHistoryChart(buckets: buckets, title: title),
          ),
        ),
      ),
    );

    final titleFinder = find.text(title);
    final countFinder = find.text('5 buckets');
    expect(titleFinder, findsOneWidget);
    expect(countFinder, findsOneWidget);
    expect(
      tester.getRect(countFinder).left - tester.getRect(titleFinder).right,
      greaterThanOrEqualTo(8),
    );

    for (final text in [title, '5 buckets']) {
      final finder = find.text(text);
      final paragraph = tester.renderObject<RenderParagraph>(finder);
      final bounds = (Offset.zero & paragraph.size).inflate(0.001);
      final boxes = paragraph.getBoxesForSelection(
        TextSelection(baseOffset: 0, extentOffset: text.length),
      );
      expect(paragraph.didExceedMaxLines, isFalse);
      expect(paragraph.textScaler.scale(10), closeTo(16, 0.001));
      expect(boxes, isNotEmpty);
      if (text == title) {
        expect(boxes.last.bottom, greaterThan(boxes.first.bottom));
      }
      for (var offset = 0; offset < text.length; offset++) {
        if (text[offset] == ' ') continue;
        final glyphs = paragraph.getBoxesForSelection(
          TextSelection(baseOffset: offset, extentOffset: offset + 1),
        );
        expect(glyphs, hasLength(1));
        final glyphBounds = glyphs.single.toRect();
        expect(glyphBounds.isEmpty, isFalse);
        expect(bounds.intersect(glyphBounds), glyphBounds);
      }
      final rect = tester.getRect(finder);
      expect((Offset.zero & size).intersect(rect), rect);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('plots Cursor-style request buckets without inventing cost', (
    tester,
  ) async {
    final buckets = [
      _requestBucket(DateTime.utc(2026, 7, 18), 77),
      _requestBucket(DateTime.utc(2026, 7, 19), 110),
    ];

    final painter = await _pumpChart(tester, buckets);

    expect(find.text('187 requests'), findsOneWidget);
    expect(find.text('No totals'), findsNothing);
    expect(find.text('2026-07-18'), findsOneWidget);
    expect(find.text('2026-07-20'), findsOneWidget);
    expect(
      await tester.runAsync(() => _primaryPixelCount(painter)),
      greaterThan(0),
    );
  });

  testWidgets('keeps known request bars without claiming a partial total', (
    tester,
  ) async {
    final painter = await _pumpChart(tester, [
      _requestBucket(DateTime.utc(2026, 7, 18), 7),
      _requestBucket(DateTime.utc(2026, 7, 19), null),
    ]);

    expect(find.text('No totals'), findsOneWidget);
    expect(find.text('7 requests'), findsNothing);
    expect(find.text('0 requests'), findsNothing);
    expect(
      await tester.runAsync(() => _primaryPixelCount(painter)),
      greaterThan(0),
    );
  });

  for (final scenario in [
    (requests: 0, label: '0 requests'),
    (requests: 1, label: '1 request'),
    (requests: null, label: 'No totals'),
  ]) {
    testWidgets('shows ${scenario.label} for request-only history', (
      tester,
    ) async {
      final painter = await _pumpChart(tester, [
        _requestBucket(DateTime.utc(2026, 7, 18), scenario.requests),
      ]);

      expect(find.text(scenario.label), findsOneWidget);
      expect(find.text('1 requests'), findsNothing);
      if (scenario.requests == null) {
        expect(find.text('0 requests'), findsNothing);
      }
      expect(
        await tester.runAsync(() => _primaryPixelCount(painter)),
        scenario.requests == 1 ? greaterThan(0) : 0,
      );
    });
  }

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

UsageBucket _requestBucket(DateTime start, int? requests) {
  return UsageBucket(
    startAt: start,
    endAt: start.add(const Duration(days: 1)),
    cost: null,
    inputTokens: null,
    outputTokens: null,
    cachedTokens: null,
    requests: requests,
    model: null,
  );
}
