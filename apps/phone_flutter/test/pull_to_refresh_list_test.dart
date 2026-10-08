import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ward_pulse_phone/app/pull_to_refresh_list.dart';

void main() {
  testWidgets('a pull opens a gap, spins in it, and reloads', (tester) async {
    var reloads = 0;
    // Held open, because the gap lasts exactly as long as the reload does.
    final reload = Completer<void>();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PullToRefreshList(
            onRefresh: () {
              reloads++;
              return reload.future;
            },
            children: const [
              SizedBox(height: 400, child: Text('first row')),
              SizedBox(height: 400, child: Text('second row')),
            ],
          ),
        ),
      ),
    );

    final firstRowTop = tester.getTopLeft(find.text('first row')).dy;

    await tester.drag(
      find.text('first row'),
      const Offset(0, 300),
      touchSlopY: 0,
    );
    await tester.pump();
    expect(find.byType(RefreshProgressIndicator), findsOneWidget);

    // Once the reload starts, the list moves down by the gap the spinner turns
    // in — the point of this widget: nothing of the content is covered. The
    // indicator settles first, so the gap opens a few frames after the release.
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      tester.getTopLeft(find.text('first row')).dy,
      greaterThan(firstRowTop),
    );

    expect(reloads, 1);

    // The gap closes once the reload lands.
    reload.complete();
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.text('first row')).dy, firstRowTop);
  });

  testWidgets('a tab shorter than its viewport still answers a pull', (
    tester,
  ) async {
    var reloads = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PullToRefreshList(
            onRefresh: () async => reloads++,
            children: const [Text('only row')],
          ),
        ),
      ),
    );

    await tester.drag(
      find.text('only row'),
      const Offset(0, 300),
      touchSlopY: 0,
    );
    await tester.pumpAndSettle();

    expect(reloads, 1);
  });
}
