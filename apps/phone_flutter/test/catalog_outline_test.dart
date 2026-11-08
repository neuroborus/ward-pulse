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
  testWidgets(
    'known uncapped spend can be selected only in the widget picker',
    (tester) async {
      final snapshot = DashboardSnapshot.fromJson({
        ...DashboardSnapshot.empty().toJson(),
        'accounts': [
          {
            'accountId': 'local-report',
            'provider': 'claude',
            'connection': 'anthropic.platform',
            'status': 'ok',
            'credits': <Object>[],
            'buckets': <Object>[],
            'modelBreakdown': <Object>[],
            'allowances': <Object>[],
            for (final period in ['today', 'week', 'month'])
              period: {
                ...BudgetState.unknownPeriod(period).toJson(),
                if (period == 'today')
                  'spent': const Money(minorUnits: 0, currency: 'USD').toJson(),
              },
          },
        ],
      });
      List<String>? saved;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: WidgetScreen(
              snapshot: snapshot,
              preferences: const PhoneWidgetPreferences(selectedIds: []),
              onPreferencesChanged: (update) async {
                saved =
                    update(
                      const PhoneWidgetPreferences(selectedIds: []),
                    ).selectedIds;
              },
              onRefresh: () async {},
            ),
          ),
        ),
      );
      final today = find.widgetWithText(CheckboxListTile, 'Today');
      expect(tester.widget<CheckboxListTile>(today).onChanged, isNotNull);
      await tester.ensureVisible(today);
      await tester.tap(today);
      await tester.pump();
      expect(saved, ['budget.anthropic.platform.today']);
      final watchMetric = watchRingCatalog(
        snapshot,
      ).singleWhere((m) => m.id.endsWith('.today'));
      expect(watchMetric.isAvailable, isFalse);
    },
  );

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
            onPreferencesChanged: (update) async {
              saved =
                  update(
                    const PhoneWidgetPreferences(selectedIds: selected),
                  ).selectedIds;
            },
            onRefresh: () async {},
          );
        } else {
          picker = WatchfaceScreen(
            snapshot: snapshot,
            reportingOutcomes: reportingOutcomes,
            ringPreferences: const WatchRingPreferences(selectedIds: selected),
            onRingPreferencesChanged: (update) async {
              saved =
                  update(
                    const WatchRingPreferences(selectedIds: selected),
                  ).selectedIds;
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

  testWidgets('saved unavailable Extra usage stays removable', (tester) async {
    const selected = ['allowance.claude.claude-extra-usage'];
    final snapshots = <DashboardSnapshot?>[
      null,
      DashboardSnapshot.empty(),
      for (final percent in [null, -1.0, double.nan, double.infinity])
        DashboardSnapshot.fromJson({
          ...DashboardSnapshot.empty().toJson(),
          'accounts': [
            {
              'accountId': 'claude-local',
              'provider': 'claude',
              'connection': 'anthropic.plan',
              'status': 'ok',
              'credits': <Object>[],
              'buckets': <Object>[],
              'modelBreakdown': <Object>[],
              for (final period in ['today', 'week', 'month'])
                period: BudgetState.unknownPeriod(period).toJson(),
              'allowances': [
                {
                  'id': 'claude-extra-usage',
                  'status': 'ok',
                  'source': 'purchased',
                  'label': 'Extra usage',
                  'usedPercent': percent,
                  'limit': null,
                },
              ],
            },
          ],
        }),
    ];
    for (final data in snapshots) {
      List<String>? saved;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: WidgetScreen(
              snapshot: data,
              preferences: const PhoneWidgetPreferences(selectedIds: selected),
              onPreferencesChanged: (update) async {
                saved =
                    update(
                      const PhoneWidgetPreferences(selectedIds: selected),
                    ).selectedIds;
              },
              onRefresh: () async {},
            ),
          ),
        ),
      );
      final row = find.byWidgetPredicate(
        (widget) => widget is CheckboxListTile && widget.value == true,
      );
      expect(row, findsOneWidget);
      expect(tester.widget<CheckboxListTile>(row).onChanged, isNotNull);
      await tester.ensureVisible(row);
      await tester.tap(row);
      await tester.pump();
      expect(saved, isEmpty);
    }
  });

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
