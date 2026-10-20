import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ward_pulse_phone/app/ward_pulse_app.dart';
import 'package:ward_pulse_phone/app/ward_pulse_theme.dart';
import 'package:ward_pulse_phone/dashboard/dashboard_repository.dart';

void main() {
  // FontLoader registration lasts for the engine, so keep this case isolated.
  testWidgets('full navigation labels fit at 360dp and retain 411dp layout', (
    tester,
  ) async {
    // Ahem's square glyphs cannot represent the phone's width boundary.
    await tester.runAsync(() async {
      final flutterRoot = Directory(Platform.environment['FLUTTER_ROOT']!).uri;
      final loader = FontLoader('Roboto');
      for (final weight in ['Regular', 'Medium']) {
        loader.addFont(
          File.fromUri(
            flutterRoot.resolve(
              'bin/cache/artifacts/material_fonts/Roboto-$weight.ttf',
            ),
          ).readAsBytes().then((bytes) => ByteData.sublistView(bytes)),
        );
      }
      await loader.load();
    });
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(411, 800);
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    const labels = [
      'Dashboard',
      'Watchface',
      'Widget',
      'Providers',
      'Settings',
    ];
    List<({Rect selection, double baseline, Rect icon, Rect indicator})>
    measure(String scene) {
      final sceneContext = '$scene at ${tester.view.physicalSize.width}dp';
      final bar = find.byType(NavigationBar);
      expect(bar, findsOneWidget, reason: sceneContext);
      final barRect = tester.getRect(bar);
      expect(
        barRect.size,
        Size(tester.view.physicalSize.width, 80),
        reason: '$sceneContext: bar $barRect',
      );
      final destinations = find.descendant(
        of: bar,
        matching: find.byType(NavigationDestination),
      );
      expect(destinations, findsNWidgets(labels.length));
      final measurements =
          <({Rect selection, double baseline, Rect icon, Rect indicator})>[];
      final allocations = <({Rect label, Rect icon, Rect indicator})>[];
      for (var index = 0; index < labels.length; index++) {
        final label = labels[index];
        final destination = destinations.at(index);
        final destinationRect = tester.getRect(destination);
        expect(
          destinationRect.width,
          closeTo(barRect.width / labels.length, 0.001),
          reason:
              '$sceneContext: $label destination $destinationRect, bar $barRect',
        );
        final text = find.descendant(
          of: destination,
          matching: find.text(label),
        );
        expect(text, findsOneWidget, reason: '$sceneContext: $label');
        final paragraph = tester.renderObject<RenderParagraph>(text);
        final context =
            '$sceneContext, scale ${paragraph.textScaler.scale(1)}, $label';
        final origin = paragraph.localToGlobal(Offset.zero);
        final paragraphRect = origin & paragraph.size;
        final paragraphContext =
            '$context: paragraph [${paragraphRect.left}, ${paragraphRect.top}, '
            '${paragraphRect.right}, ${paragraphRect.bottom}], '
            'size ${paragraph.size}, constraints ${paragraph.constraints}';
        expect(
          paragraph.text.toPlainText(includeSemanticsLabels: false),
          label,
          reason: paragraphContext,
        );
        expect(paragraph.childCount, 0, reason: paragraphContext);
        final destinationContext =
            '$paragraphContext, destination $destinationRect';
        expect(paragraphRect.isEmpty, isFalse, reason: destinationContext);
        expect(
          paragraphRect.left,
          greaterThanOrEqualTo(destinationRect.left),
          reason: destinationContext,
        );
        expect(
          paragraphRect.top,
          greaterThanOrEqualTo(destinationRect.top),
          reason: destinationContext,
        );
        expect(
          paragraphRect.right,
          lessThanOrEqualTo(destinationRect.right),
          reason: destinationContext,
        );
        expect(
          paragraphRect.bottom,
          lessThanOrEqualTo(destinationRect.bottom),
          reason: destinationContext,
        );
        // Replay RenderParagraph's width semantics and effective text settings.
        // Allocation and layout checks do not prove every painted pixel fits.
        final painter = TextPainter(
          text: paragraph.text,
          textAlign: paragraph.textAlign,
          textDirection: paragraph.textDirection,
          textScaler: paragraph.textScaler,
          maxLines: paragraph.maxLines,
          ellipsis: paragraph.overflow == TextOverflow.ellipsis ? '\u2026' : null,
          locale: paragraph.locale,
          strutStyle: paragraph.strutStyle,
          textWidthBasis: paragraph.textWidthBasis,
          textHeightBehavior: paragraph.textHeightBehavior,
        );
        try {
          final maxWidth =
              paragraph.softWrap || paragraph.overflow == TextOverflow.ellipsis
                  ? paragraph.constraints.maxWidth
                  : double.infinity;
          painter.layout(
            minWidth: paragraph.constraints.minWidth,
            maxWidth: maxWidth,
          );
          final lines = painter.computeLineMetrics();
          final layoutContext =
              '$paragraphContext, replay minWidth ${paragraph.constraints.minWidth}, '
              'maxWidth $maxWidth, size ${painter.size}, '
              'lines ${lines.length}, truncated ${painter.didExceedMaxLines}';
          expect(lines, hasLength(1), reason: layoutContext);
          expect(painter.didExceedMaxLines, isFalse, reason: layoutContext);
          expect(paragraph.didExceedMaxLines, isFalse, reason: layoutContext);
          expect(
            painter.width,
            lessThanOrEqualTo(paragraph.size.width),
            reason: layoutContext,
          );
          expect(
            painter.height,
            lessThanOrEqualTo(paragraph.size.height),
            reason: layoutContext,
          );
        } finally {
          painter.dispose();
        }
        final singleLineSize = Size(
          paragraph.getMaxIntrinsicWidth(double.infinity),
          paragraph.getMaxIntrinsicHeight(double.infinity),
        );
        expect(
          singleLineSize.width,
          lessThanOrEqualTo(paragraph.size.width + 0.001),
          reason:
              '$paragraphContext, single-line width ${singleLineSize.width}',
        );
        expect(
          singleLineSize.height,
          lessThanOrEqualTo(paragraph.size.height + 0.001),
          reason:
              '$paragraphContext, single-line height ${singleLineSize.height}',
        );
        final boxes = paragraph.getBoxesForSelection(
          TextSelection(baseOffset: 0, extentOffset: label.length),
        );
        expect(boxes, hasLength(1), reason: paragraphContext);
        expect(paragraph.textScaler.scale(10), closeTo(13, 0.001));
        // Selection boxes measure layout, not pixel ink or paint clipping.
        final selection = boxes.single.toRect().shift(origin);
        final selectionContext =
            '$context: selection [${selection.left}, ${selection.top}, '
            '${selection.right}, ${selection.bottom}]';
        expect(selection.isEmpty, isFalse, reason: selectionContext);
        for (var offset = 0; offset < label.length; offset++) {
          final characterBoxes = paragraph.getBoxesForSelection(
            TextSelection(baseOffset: offset, extentOffset: offset + 1),
          );
          expect(characterBoxes, hasLength(1), reason: '$context[$offset]');
          final character = characterBoxes.single.toRect().shift(origin);
          final characterContext =
              '$context[$offset] "${label[offset]}": selection '
              '[${character.left}, ${character.top}, '
              '${character.right}, ${character.bottom}]';
          expect(character.isEmpty, isFalse, reason: characterContext);
          expect(
            character.top,
            closeTo(selection.top, 0.001),
            reason: '$characterContext, full selection top ${selection.top}',
          );
          expect(
            character.bottom,
            closeTo(selection.bottom, 0.001),
            reason:
                '$characterContext, full selection bottom ${selection.bottom}',
          );
        }
        final baseline = paragraph.getDryBaseline(
          paragraph.constraints,
          TextBaseline.alphabetic,
        );
        final baselineContext =
            '$paragraphContext, alphabetic baseline $baseline, '
            'constraints ${paragraph.constraints}';
        expect(baseline, isNotNull, reason: baselineContext);
        expect(baseline!.isFinite, isTrue, reason: baselineContext);
        final icon = find.descendant(
          of: destination,
          matching: find.byType(Icon),
        );
        final indicator = find.descendant(
          of: destination,
          matching: find.byType(NavigationIndicator),
        );
        expect(icon, findsOneWidget, reason: context);
        expect(indicator, findsOneWidget, reason: context);
        final iconRect = tester.getRect(icon);
        final indicatorRect = tester.getRect(indicator);
        allocations.add((
          label: paragraphRect,
          icon: iconRect,
          indicator: indicatorRect,
        ));
        final relativeOrigin = Offset(destinationRect.center.dx, barRect.top);
        final measurement = (
          selection: selection.shift(-relativeOrigin),
          baseline: origin.dy + baseline - barRect.top,
          icon: iconRect.shift(-relativeOrigin),
          indicator: indicatorRect.shift(-relativeOrigin),
        );
        if (measurements.isNotEmpty) {
          expect(
            measurement.baseline,
            closeTo(measurements.first.baseline, 0.001),
            reason: context,
          );
          expect(
            measurement.icon,
            rectMoreOrLessEquals(measurements.first.icon, epsilon: 0.001),
            reason: context,
          );
          expect(
            measurement.indicator,
            rectMoreOrLessEquals(measurements.first.indicator, epsilon: 0.001),
            reason: context,
          );
          expect(
            measurement.selection.height,
            closeTo(measurements.first.selection.height, 0.001),
            reason: context,
          );
        }
        measurements.add(measurement);
      }
      for (var index = 0; index < allocations.length; index++) {
        final allocation = allocations[index];
        for (var other = 0; other < allocations.length; other++) {
          final neighbor = allocations[other];
          final context =
              '$sceneContext: ${labels[index]} allocation ${allocation.label}, '
              '${labels[other]} allocation ${neighbor.label}, '
              'icon ${neighbor.icon}, indicator ${neighbor.indicator}';
          if (other > index) {
            expect(
              allocation.label.overlaps(neighbor.label),
              isFalse,
              reason: context,
            );
          }
          expect(
            allocation.label.overlaps(neighbor.icon),
            isFalse,
            reason: context,
          );
          expect(
            allocation.label.overlaps(neighbor.indicator),
            isFalse,
            reason: context,
          );
        }
      }
      return measurements;
    }

    const app = WardPulseApp(repository: NoProvidersDashboardRepository());
    await tester.pumpWidget(app);
    await tester.pumpAndSettle();
    final destinations =
        tester.widget<NavigationBar>(find.byType(NavigationBar)).destinations;
    // A stock Material bar is the reference for ordinary-width typography
    // and for icon/indicator geometry at both widths. Establish it before
    // app geometry assertions so an app failure cannot hide the reference.
    await tester.pumpWidget(
      MaterialApp(
        theme: wardPulseLightTheme,
        home: Scaffold(
          bottomNavigationBar: NavigationBar(destinations: destinations),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final reference = measure('stock');

    await tester.pumpWidget(app);
    await tester.pumpAndSettle();
    final ordinary = measure('app');
    expect(ordinary, reference);
    tester.view.physicalSize = const Size(360, 800);
    await tester.pumpAndSettle();
    final narrow = measure('app');
    for (var index = 0; index < labels.length; index++) {
      expect(
        narrow[index].icon,
        rectMoreOrLessEquals(reference[index].icon, epsilon: 0.001),
      );
      expect(
        narrow[index].indicator,
        rectMoreOrLessEquals(reference[index].indicator, epsilon: 0.001),
      );
      expect(
        narrow[index].selection.width,
        lessThan(reference[index].selection.width),
      );
    }

    // A measurably larger common candidate must fail at least one label;
    // this guards against replacing measured fitting with a small fixed size.
    var largerWouldWrap = false;
    double? commonFontSize;
    final largerLayouts = <String>[];
    for (final label in labels) {
      final text = find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text(label),
      );
      expect(text, findsOneWidget, reason: 'larger candidate: $label');
      final paragraph = tester.renderObject<RenderParagraph>(text);
      final context =
          'larger candidate: $label, allocation ${paragraph.size}, '
          'constraints ${paragraph.constraints}';
      expect(paragraph.text, isA<TextSpan>(), reason: context);
      final span = paragraph.text as TextSpan;
      expect(span.text, label, reason: context);
      expect(span.children, isNull, reason: context);
      expect(span.style, isNotNull, reason: context);
      final style = span.style!;
      expect(style.fontSize, isNotNull, reason: context);
      final fontSize = style.fontSize!;
      expect(fontSize.isFinite, isTrue, reason: context);
      expect(fontSize, greaterThan(0), reason: context);
      commonFontSize ??= fontSize;
      expect(fontSize, commonFontSize, reason: context);
      final painter = TextPainter(
        text: TextSpan(
          text: label,
          style: style.copyWith(fontSize: fontSize + 0.02),
        ),
        textAlign: paragraph.textAlign,
        textDirection: paragraph.textDirection,
        textScaler: paragraph.textScaler,
        maxLines: paragraph.maxLines,
        ellipsis: paragraph.overflow == TextOverflow.ellipsis ? '\u2026' : null,
        locale: paragraph.locale,
        strutStyle: paragraph.strutStyle,
        textWidthBasis: paragraph.textWidthBasis,
        textHeightBehavior: paragraph.textHeightBehavior,
      );
      try {
        painter.layout();
        largerLayouts.add(
          '$label fontSize ${fontSize + 0.02}, layout ${painter.size}, '
          'constraints ${paragraph.constraints}',
        );
        largerWouldWrap |= painter.width > paragraph.constraints.maxWidth;
      } finally {
        painter.dispose();
      }
    }
    expect(
      largerWouldWrap,
      isTrue,
      reason:
          '360dp common font size $commonFontSize, increment 0.02: '
          '${largerLayouts.join('; ')}',
    );

    // Settle the other long label's selected style without duplicating the
    // existing tests of what each destination opens.
    await tester.tap(find.text('Watchface'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
      1,
    );
    expect(measure('selected app'), narrow);
    tester.view.physicalSize = const Size(411, 800);
    await tester.pumpAndSettle();
    expect(measure('selected app'), reference);
    expect(tester.takeException(), isNull);
  });
}
