import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ward_pulse_phone/app/catalog_outline.dart';
import 'package:ward_pulse_phone/dashboard/dashboard_models.dart';
import 'package:ward_pulse_phone/providers/provider_connection.dart';
import 'package:ward_pulse_phone/settings/watch_ring_preferences.dart';
import 'package:ward_pulse_phone/watchface/watchface_screen.dart';
import 'package:ward_pulse_phone/widget/phone_widget_preferences.dart';
import 'package:ward_pulse_phone/widget/widget_screen.dart';

void main() {
  WatchRingMetric metric(String id, String label) => WatchRingMetric(
    id: id,
    label: label,
    usedPercent: 10,
    status: ProviderStatus.ok,
  );

  for (final widgetPicker in [false, true]) {
    testWidgets('saved Anthropic budget removal: widget=$widgetPicker', (
      tester,
    ) async {
      const outcomes = [
        ConnectionReportingOutcome(
          connection: ProviderConnections.anthropicPlatform,
          category: ReportingOutcomeCategory.accessDenied,
          source: ReportingOutcomeSource.live,
        ),
      ];
      const selected = ['budget.anthropic.platform.week'];
      for (final (snapshot, hasOutcome) in <(DashboardSnapshot?, bool)>[
        (null, true),
        (DashboardSnapshot.empty(), true),
        (DashboardSnapshot.empty(), false),
      ]) {
        final reportingOutcomes =
            hasOutcome ? outcomes : const <ConnectionReportingOutcome>[];
        List<String>? saved;
        final Widget picker;
        if (widgetPicker) {
          picker = WidgetScreen(
            snapshot: snapshot,
            reportingOutcomes: reportingOutcomes,
            preferences: const PhoneWidgetPreferences(selectedIds: selected),
            onPreferencesChanged: (value) async {
              saved = value.selectedIds;
            },
            onRefresh: () async {},
          );
        } else {
          picker = WatchfaceScreen(
            snapshot: snapshot,
            reportingOutcomes: reportingOutcomes,
            ringPreferences: const WatchRingPreferences(selectedIds: selected),
            onRingPreferencesChanged: (value) async {
              saved = value.selectedIds;
            },
            onRefresh: () async {},
          );
        }
        await tester.pumpWidget(MaterialApp(home: Scaffold(body: picker)));
        final tiles = tester.widgetList<CheckboxListTile>(
          find.byType(CheckboxListTile),
        );
        expect(tiles, hasLength(hasOutcome ? 3 : 1));
        expect(tiles.where((tile) => tile.onChanged != null), hasLength(1));
        final selectedTile = find.byWidgetPredicate(
          (widget) => widget is CheckboxListTile && widget.value == true,
        );
        expect(selectedTile, findsOneWidget);
        await tester.ensureVisible(selectedTile);
        await tester.tap(selectedTile);
        await tester.pump();
        expect(saved, isEmpty);
      }
    });
  }

  testWidgets('one heading per kind, one per connection, rows under them', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: CatalogOutline(
              catalog: [
                metric('allowance.codex.codex-weekly', 'Weekly plan'),
                metric('budget.openai.plan.today', 'Today'),
                metric('budget.anthropic.platform.week', 'Week'),
              ],
              rowBuilder: (_, title) => ListTile(title: Text(title)),
            ),
          ),
        ),
      ),
    );

    // The plan allowance and the plan budget are the same subscription, so they
    // share one heading rather than appearing as two connections.
    expect(find.text('Plan'), findsOneWidget);
    expect(find.text('Codex'), findsOneWidget);
    expect(find.text('Platform'), findsOneWidget);
    expect(find.text('Anthropic'), findsOneWidget);

    // Rows keep only what tells them apart under that heading.
    expect(find.text('Weekly plan'), findsOneWidget);
    expect(find.text('Today'), findsOneWidget);
    expect(find.text('Week'), findsOneWidget);

    // Plan before Platform whatever order the catalog was built in: the
    // subscription is what a reader came to check.
    expect(
      tester.getTopLeft(find.text('Plan')).dy,
      lessThan(tester.getTopLeft(find.text('Platform')).dy),
    );
  });

  testWidgets('the declared kind order does not follow the catalog', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: CatalogOutline(
              // Platform first here, and it still lands second.
              catalog: [
                metric('budget.anthropic.platform.week', 'Week'),
                metric('allowance.codex.codex-weekly', 'Weekly plan'),
              ],
              rowBuilder: (_, title) => ListTile(title: Text(title)),
            ),
          ),
        ),
      ),
    );

    expect(
      tester.getTopLeft(find.text('Plan')).dy,
      lessThan(tester.getTopLeft(find.text('Platform')).dy),
    );
  });
}
