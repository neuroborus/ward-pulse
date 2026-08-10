import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ward_pulse_phone/app/ward_pulse_app.dart';
import 'package:ward_pulse_phone/dashboard/dashboard_models.dart';
import 'package:ward_pulse_phone/dashboard/dashboard_repository.dart';
import 'package:ward_pulse_phone/providers/provider_connection.dart';
import 'package:ward_pulse_phone/providers/provider_credential_store.dart';
import 'package:ward_pulse_phone/settings/alert_threshold_preferences.dart';
import 'package:ward_pulse_phone/settings/consumption_display_preferences.dart';
import 'package:ward_pulse_phone/settings/watch_ring_preferences.dart';
import 'package:ward_pulse_phone/settings/debug_data_preferences.dart';
import 'package:ward_pulse_phone/settings/refresh_interval_preferences.dart';
import 'package:ward_pulse_phone/widget/phone_widget_preferences.dart';
import 'package:ward_pulse_phone/sync/poll_cadence.dart';
import 'package:ward_pulse_phone/sync/provider_sync_scheduler.dart';
import 'package:ward_pulse_phone/sync/watch_sync_service.dart';

void main() {
  testWidgets('renders mock history and opens Providers catalog', (
    tester,
  ) async {
    final fixture =
        File(
          '../../fixtures/snapshots/dashboard_today.json',
        ).readAsStringSync();
    final snapshot = DashboardSnapshot.fromJsonString(fixture);

    await tester.pumpWidget(
      WardPulseApp(repository: ValueDashboardRepository(snapshot)),
    );
    await tester.pumpAndSettle();

    expect(find.text('WardPulse'), findsOneWidget);

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

    await tester.scrollUntilVisible(
      find.text('Platform spend'),
      300,
      scrollable: dashboard,
    );
    expect(find.text('Today'), findsWidgets);

    await tester.tap(find.text('Providers'));
    await tester.pumpAndSettle();

    expect(find.text('OpenAI'), findsOneWidget);
    expect(find.text('Anthropic'), findsOneWidget);
    expect(find.text('Cursor'), findsOneWidget);
    expect(find.text('Codex subscription'), findsOneWidget);
    expect(find.text('Not connected'), findsWidgets);
  });

  testWidgets('syncs an empty watch summary when no providers are connected', (
    tester,
  ) async {
    final watchSyncService = _FakeWatchSyncService();

    await tester.pumpWidget(
      WardPulseApp(
        repository: const NoProvidersDashboardRepository(),
        watchSyncService: watchSyncService,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Connect a provider'), findsOneWidget);
    expect(watchSyncService.syncedSnapshots, hasLength(1));
    expect(watchSyncService.syncedSnapshots.single.accounts, isEmpty);
  });

  testWidgets('Wear refresh reloads when the phone has no providers', (
    tester,
  ) async {
    final watchSyncService = _FakeWatchSyncService();
    var loads = 0;
    final repository = _CountingDashboardRepository(() {
      loads += 1;
      return DashboardSnapshot.empty(
        generatedAt: DateTime.utc(
          2026,
          7,
          26,
          12,
        ).subtract(Duration(minutes: loads == 1 ? 10 : 0)),
      );
    });

    await tester.pumpWidget(
      WardPulseApp(repository: repository, watchSyncService: watchSyncService),
    );
    await tester.pumpAndSettle();
    expect(loads, 1);
    expect(watchSyncService.syncedSnapshots, hasLength(1));

    watchSyncService.refreshHandler!();
    await tester.pumpAndSettle();

    expect(loads, 2);
    expect(watchSyncService.syncedSnapshots.length, greaterThanOrEqualTo(2));
  });

  testWidgets('queues a development watch sync', (tester) async {
    final snapshot = DashboardSnapshot.fromJsonString(
      File('../../fixtures/snapshots/dashboard_today.json').readAsStringSync(),
    );
    final watchSyncService = _FakeWatchSyncService();

    await tester.pumpWidget(
      WardPulseApp(
        repository: ValueDashboardRepository(snapshot),
        watchSyncService: watchSyncService,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    expect(watchSyncService.syncedSnapshots, [snapshot]);

    await tester.scrollUntilVisible(
      find.text('Send to watch'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -160));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Sync'));
    await tester.pumpAndSettle();

    expect(watchSyncService.syncedSnapshots, [snapshot, snapshot]);
    expect(find.text('Watch summary queued'), findsOneWidget);
  });

  testWidgets('Settings shows systemic sections without Watch display', (
    tester,
  ) async {
    final snapshot = DashboardSnapshot.fromJsonString(
      File('../../fixtures/snapshots/dashboard_today.json').readAsStringSync(),
    );

    await tester.pumpWidget(
      WardPulseApp(repository: ValueDashboardRepository(snapshot)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();

    expect(find.text('Display'), findsNothing);
    expect(find.text('Alerts'), findsNothing);
    expect(find.text('Refresh'), findsOneWidget);
    expect(find.text('Watch display'), findsNothing);
    expect(
      find.textContaining('Temporary until the Watchface tab'),
      findsNothing,
    );
    await tester.scrollUntilVisible(
      find.text('Diagnostics'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Diagnostics'), findsOneWidget);
    expect(find.text('Sync'), findsWidgets);
    expect(find.text('Watch summary'), findsOneWidget);
  });

  testWidgets('slot cards say where metrics come from when there are none', (
    tester,
  ) async {
    await tester.pumpWidget(
      WardPulseApp(repository: const NoProvidersDashboardRepository()),
    );
    await tester.pumpAndSettle();

    for (final tab in ['Watchface', 'Widget']) {
      await tester.tap(find.text(tab));
      await tester.pumpAndSettle();
      // A bare header card would read as a broken screen.
      expect(find.text('No metrics yet'), findsOneWidget, reason: tab);
      expect(find.byType(CheckboxListTile), findsNothing, reason: tab);
    }
  });

  testWidgets('slot count follows the rows, not a stored selection', (
    tester,
  ) async {
    final store =
        _MemoryWatchRingStore()
          ..value = const WatchRingPreferences(
            selectedIds: [
              'allowance.codex.plan',
              'budget.anthropic.platform.today',
              'budget.anthropic.platform.week',
            ],
          );

    await tester.pumpWidget(
      WardPulseApp(
        repository: const _FailingDashboardRepository(
          DashboardSyncIssue.providerUnavailable,
        ),
        watchRingPreferenceStore: store,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Watchface'));
    await tester.pumpAndSettle();

    // A failed load leaves no rows to tick, so counting the stored ids would
    // claim three slots the screen does not show.
    expect(find.text('No metrics yet'), findsOneWidget);
    expect(find.textContaining('0 of 3 slots used'), findsOneWidget);
  });

  testWidgets('Watchface tab owns ring slots and payload preview', (
    tester,
  ) async {
    final snapshot = _asConnection(
      DashboardSnapshot.fromJsonString(
        File(
          '../../fixtures/snapshots/dashboard_today.json',
        ).readAsStringSync(),
      ),
    );
    final store = _MemoryWatchRingStore();

    await tester.pumpWidget(
      WardPulseApp(
        repository: ValueDashboardRepository(snapshot),
        watchRingPreferenceStore: store,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Watchface'));
    await tester.pumpAndSettle();

    expect(find.text('Ring slots'), findsOneWidget);
    expect(find.text('Wear & watch face'), findsOneWidget);
    expect(find.text('Next watch payload'), findsOneWidget);
    // Budget rings are per connection, so the slot names it before the period.
    expect(find.text('Anthropic platform · Today'), findsWidgets);

    await tester.scrollUntilVisible(
      find.text('Anthropic platform · Today'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    // Defaults select available metrics; toggling Today off persists an explicit list.
    final todayTile = find.widgetWithText(
      CheckboxListTile,
      'Anthropic platform · Today',
    );
    expect(todayTile, findsOneWidget);
    // A full stack greys every unpicked row; the count is what tells that
    // apart from a fault, so it has to follow the selection.
    expect(find.textContaining('3 of 3 slots used'), findsOneWidget);
    await tester.tap(todayTile);
    await tester.pumpAndSettle();

    expect(store.value.selectedIds, isNotNull);
    expect(find.textContaining('2 of 3 slots used'), findsOneWidget);
  });

  testWidgets('Widget tab owns metrics independently of Watchface', (
    tester,
  ) async {
    final snapshot = _asConnection(
      DashboardSnapshot.fromJsonString(
        File(
          '../../fixtures/snapshots/dashboard_today.json',
        ).readAsStringSync(),
      ),
    );
    final store = _MemoryPhoneWidgetStore();

    await tester.pumpWidget(
      WardPulseApp(
        repository: ValueDashboardRepository(snapshot),
        phoneWidgetPreferenceStore: store,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Widget'));
    await tester.pumpAndSettle();

    expect(find.text('Widget metrics'), findsOneWidget);
    expect(find.text('Home screen widget'), findsOneWidget);
    expect(find.text('Next widget payload'), findsOneWidget);
    expect(find.textContaining('independent of Watchface'), findsOneWidget);
    // Its own copy of the count, on a screen with six slots instead of three.
    expect(find.textContaining('of 6 slots used'), findsOneWidget);

    final todayTile = find.widgetWithText(
      CheckboxListTile,
      'Anthropic platform · Today',
    );
    expect(todayTile, findsOneWidget);
    await tester.tap(todayTile);
    await tester.pumpAndSettle();

    expect(store.value.selectedIds, isNotNull);
  });

  testWidgets('Providers Platform row saves a budget limit and its alert', (
    tester,
  ) async {
    final snapshot = DashboardSnapshot.fromJsonString(
      File('../../fixtures/snapshots/dashboard_today.json').readAsStringSync(),
    );
    final store = _MemoryAlertThresholdStore();
    // A connection rule the budget dialog must not clobber on save.
    store.value = store.value.withConnection(
      ProviderConnections.codexPlan,
      const ConnectionAlertThresholds(plan: AlertPercentThreshold(at: 90)),
    );

    await tester.pumpWidget(
      WardPulseApp(
        repository: ValueDashboardRepository(snapshot),
        alertThresholdStore: store,
        // Widget tests do not load libward_pulse_ffi.so; prefs UI only.
        applyAlertSettings: (current, _) => current,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Providers'));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('Platform reporting'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    Finder platformButton(String tooltip) => find.descendant(
      of: find.ancestor(
        of: find.text('Platform reporting'),
        matching: find.byType(ListTile),
      ),
      matching: find.byTooltip(tooltip),
    );

    // The limit comes first: a percentage is meaningless without one.
    await tester.tap(platformButton('Budget limits'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Budget · Platform reporting'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, '25');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    await tester.tap(platformButton('Alert thresholds'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Alerts · Platform reporting'), findsOneWidget);
    expect(find.text('Today'), findsOneWidget);
    expect(find.text('Week'), findsOneWidget);
    expect(find.text('Month'), findsOneWidget);

    await tester.tap(find.text('Off').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('20% left').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(
      store.value.forConnection(ProviderConnections.openAiPlatform).today.at,
      80,
    );
    expect(
      store.value
          .forConnection(ProviderConnections.openAiPlatform)
          .budget
          .today,
      2500,
    );
    expect(
      store.value.forConnection(ProviderConnections.codexPlan).plan.at,
      90,
    );
  });

  testWidgets('Providers plan row can save connection alert thresholds', (
    tester,
  ) async {
    final snapshot = DashboardSnapshot.fromJsonString(
      File('../../fixtures/snapshots/dashboard_today.json').readAsStringSync(),
    );
    final store = _MemoryAlertThresholdStore();

    await tester.pumpWidget(
      WardPulseApp(
        repository: ValueDashboardRepository(snapshot),
        alertThresholdStore: store,
        applyAlertSettings: (current, _) => current,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Providers'));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('Codex subscription'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byTooltip('Alert thresholds').first);
    await tester.pumpAndSettle();

    expect(find.textContaining('Alerts ·'), findsOneWidget);
    // A plan connection offers window rules, not spend budgets.
    expect(find.text('Plan'), findsOneWidget);
    expect(find.text('Purchased'), findsOneWidget);
    expect(find.text('Today'), findsNothing);
    await tester.tap(find.text('Off').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('30% left').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(
      store.value.forConnection(ProviderConnections.codexPlan).plan.at,
      70,
    );
  });

  testWidgets('watch sync failure does not block the dashboard', (
    tester,
  ) async {
    final snapshot = DashboardSnapshot.fromJsonString(
      File('../../fixtures/snapshots/dashboard_today.json').readAsStringSync(),
    );

    await tester.pumpWidget(
      WardPulseApp(
        repository: ValueDashboardRepository(snapshot),
        watchSyncService: const _FailingWatchSyncService(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('WardPulse'), findsOneWidget);
    expect(find.text('Dashboard unavailable'), findsNothing);
  });

  testWidgets('labels previous dashboard data as stale', (tester) async {
    final snapshot = DashboardSnapshot.fromJsonString(
      File('../../fixtures/snapshots/dashboard_today.json').readAsStringSync(),
    ).withStaleStatus(syncIssue: DashboardSyncIssue.authentication);

    await tester.pumpWidget(
      WardPulseApp(repository: ValueDashboardRepository(snapshot)),
    );
    await tester.pumpAndSettle();

    // App bar overall status plus the provider plaque on the dashboard.
    expect(find.byTooltip('Stale'), findsWidgets);
    expect(find.byIcon(Icons.schedule), findsWidgets);
    expect(
      find.textContaining('Showing previous data · Updated'),
      findsOneWidget,
    );
    expect(
      find.text(DashboardSyncIssue.authentication.message),
      findsOneWidget,
    );
    expect(
      find.byTooltip(DashboardSyncIssue.authentication.message),
      findsWidgets,
    );
    final staleIcon = find.byIcon(Icons.schedule).first;
    expect(
      tester.widget<Icon>(staleIcon).color,
      Theme.of(tester.element(staleIcon)).colorScheme.tertiary,
    );
  });

  testWidgets('stores and masks an OpenAI Admin API key', (tester) async {
    final snapshot = DashboardSnapshot.fromJsonString(
      File('../../fixtures/snapshots/dashboard_today.json').readAsStringSync(),
    );
    final credentialStore = _MemoryCredentialStore();

    await tester.pumpWidget(
      WardPulseApp(
        repository: ValueDashboardRepository(snapshot),
        credentialStore: credentialStore,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Providers'));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('Platform reporting'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('Not connected'), findsWidgets);
    await tester.tap(find.text('Platform reporting'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextFormField).first,
      'secret-admin-key',
    );
    expect(
      tester.widget<TextField>(find.byType(TextField).first).obscureText,
      isTrue,
    );
    await tester.tap(find.byTooltip('Show value'));
    await tester.pump();
    expect(
      tester.widget<TextField>(find.byType(TextField).first).obscureText,
      isFalse,
    );
    expect(find.byTooltip('Hide value'), findsOneWidget);
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(credentialStore.openAiSecret, 'secret-admin-key');
    expect(find.text('Connected'), findsOneWidget);
    expect(find.text('secret-admin-key'), findsNothing);
  });

  testWidgets('saves an optional OpenAI Platform label', (tester) async {
    final snapshot = DashboardSnapshot.fromJsonString(
      File('../../fixtures/snapshots/dashboard_today.json').readAsStringSync(),
    );
    final credentialStore = _MemoryCredentialStore();

    await tester.pumpWidget(
      WardPulseApp(
        repository: ValueDashboardRepository(snapshot),
        credentialStore: credentialStore,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Providers'));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('OpenAI'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('OpenAI'), findsOneWidget);
    expect(find.text('Codex subscription'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('Platform reporting'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Platform reporting'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextFormField).at(0),
      'secret-admin-key',
    );
    await tester.enterText(find.byType(TextFormField).at(1), 'Work org key');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(credentialStore.openAiSecret, 'secret-admin-key');
    expect(credentialStore.openAiLabel, 'Work org key');
    expect(find.text('Work org key'), findsOneWidget);
    expect(find.text('Platform reporting'), findsNothing);

    final providersList = find.descendant(
      of: find.byType(ListView),
      matching: find.byType(Scrollable),
    );
    await tester.scrollUntilVisible(
      find.text('Anthropic'),
      300,
      scrollable: providersList,
    );
    expect(find.text('Anthropic'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('Cursor'),
      300,
      scrollable: providersList,
    );
    expect(find.text('Cursor'), findsOneWidget);
    expect(find.text('Not connected'), findsWidgets);

    await tester.scrollUntilVisible(
      find.text('Work org key'),
      300,
      scrollable: providersList,
    );
    await tester.tap(find.text('Work org key'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();

    expect(credentialStore.openAiSecret, isNull);
    expect(credentialStore.openAiLabel, isNull);
    expect(find.text('Platform reporting'), findsOneWidget);
  });

  testWidgets('keeps Providers catalog available after a load failure', (
    tester,
  ) async {
    final credentialStore = _MemoryCredentialStore('invalid-admin-key');
    final scheduler = _ManualProviderSyncScheduler();
    addTearDown(scheduler.dispose);

    await tester.pumpWidget(
      WardPulseApp(
        repository: const _FailingDashboardRepository(
          DashboardSyncIssue.authentication,
          'Usage · HTTP 401 · invalid_api_key',
        ),
        credentialStore: credentialStore,
        syncScheduler: scheduler,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Dashboard unavailable'), findsOneWidget);
    expect(scheduler.scheduledInterval, isNotNull);
    expect(
      find.text(DashboardSyncIssue.authentication.message),
      findsOneWidget,
    );
    expect(
      find.byTooltip(DashboardSyncIssue.authentication.message),
      findsOneWidget,
    );
    expect(find.text('Details'), findsOneWidget);
    await tester.tap(find.text('Details'));
    await tester.pumpAndSettle();
    expect(find.text('Error details'), findsOneWidget);
    expect(find.text('Usage · HTTP 401 · invalid_api_key'), findsOneWidget);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Providers'));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('Platform reporting'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('Platform reporting'), findsOneWidget);
    expect(find.text('Connected'), findsOneWidget);
    await tester.tap(find.text('Platform reporting'));
    await tester.pumpAndSettle();
    expect(find.text('Remove'), findsOneWidget);
  });

  testWidgets(
    'shows plan and purchased surfaces without Settings display toggles',
    (tester) async {
      final json =
          jsonDecode(
                File(
                  '../../fixtures/snapshots/dashboard_today.json',
                ).readAsStringSync(),
              )
              as Map<String, dynamic>;
      final account = (json['accounts'] as List).first as Map<String, dynamic>;
      account['provider'] = 'codex';
      account['allowances'] = [
        {
          'id': 'plan',
          'source': 'plan',
          'label': 'Weekly plan',
          'usedPercent': 84.0,
          'used': null,
          'limit': null,
          'remaining': null,
          'windowMinutes': 10080,
          'resetsAt': '2026-07-26T09:55:37Z',
          'status': 'warning',
        },
        {
          'id': 'purchased',
          'source': 'purchased',
          'label': 'Purchased credits',
          'usedPercent': null,
          'used': null,
          'limit': null,
          'remaining': {'value': '12.5', 'unit': 'credits'},
          'windowMinutes': null,
          'resetsAt': null,
          'status': 'ok',
        },
      ];

      await tester.pumpWidget(
        WardPulseApp(
          repository: ValueDashboardRepository(
            DashboardSnapshot.fromJson(json),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Weekly plan'), findsOneWidget);
      expect(find.text('Purchased credits'), findsOneWidget);

      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();
      expect(find.text('Display'), findsNothing);
      expect(find.text('Platform spend'), findsNothing);
      expect(find.text('Purchased usage'), findsNothing);
    },
  );

  testWidgets('persists the global refresh interval slider', (tester) async {
    final snapshot = DashboardSnapshot.fromJsonString(
      File('../../fixtures/snapshots/dashboard_today.json').readAsStringSync(),
    );
    final preferences = _MemoryRefreshIntervalPreferenceStore();

    await tester.pumpWidget(
      WardPulseApp(
        repository: ValueDashboardRepository(snapshot),
        refreshIntervalStore: preferences,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining(
        'Every ${PollCadence.defaultRefreshMinutes} minutes while WardPulse is open',
      ),
      findsOneWidget,
    );
    expect(
      find.textContaining(
        'at least every ${PollCadence.headlessMinRefreshMinutes} minutes '
        'in the background (Android limit)',
      ),
      findsOneWidget,
    );

    final slider = find.byType(Slider);
    await tester.ensureVisible(slider);
    await tester.pumpAndSettle();
    // Advance one segmented stop past the default (15 → 20).
    final sliderWidget = tester.widget<Slider>(slider);
    final nextIndex = (sliderWidget.value + 1).clamp(
      sliderWidget.min,
      sliderWidget.max,
    );
    sliderWidget.onChanged!(nextIndex);
    await tester.pump();
    sliderWidget.onChangeEnd!(nextIndex);
    await tester.pumpAndSettle();

    expect(preferences.value.minutes, 20);
    expect(
      PollCadence.refreshIntervalStops,
      contains(preferences.value.minutes),
    );
  });

  testWidgets('resyncs providers and the watch on a scheduled tick', (
    tester,
  ) async {
    final snapshot = DashboardSnapshot.fromJsonString(
      File('../../fixtures/snapshots/dashboard_today.json').readAsStringSync(),
    );
    final watchSyncService = _FakeWatchSyncService();
    final scheduler = _ManualProviderSyncScheduler();
    addTearDown(scheduler.dispose);

    await tester.pumpWidget(
      WardPulseApp(
        repository: ValueDashboardRepository(snapshot),
        watchSyncService: watchSyncService,
        syncScheduler: scheduler,
      ),
    );
    await tester.pumpAndSettle();

    expect(
      scheduler.scheduledInterval,
      const Duration(minutes: PollCadence.defaultRefreshMinutes),
    );
    expect(watchSyncService.syncedSnapshots, hasLength(1));

    scheduler.tick();
    await tester.pumpAndSettle();

    expect(watchSyncService.syncedSnapshots, hasLength(2));
  });

  testWidgets('shows Cursor freshness guidance on connection rows', (
    tester,
  ) async {
    final snapshot = DashboardSnapshot.fromJsonString(
      File('../../fixtures/snapshots/dashboard_today.json').readAsStringSync(),
    );

    await tester.pumpWidget(
      WardPulseApp(repository: ValueDashboardRepository(snapshot)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Providers'));
    await tester.pumpAndSettle();

    final settingsScrollable = find.descendant(
      of: find.byType(ListView),
      matching: find.byType(Scrollable),
    );
    await tester.scrollUntilVisible(
      find.text('Team Admin API'),
      300,
      scrollable: settingsScrollable,
    );

    final planTile = find.ancestor(
      of: find.text('Cursor plan'),
      matching: find.byType(ListTile),
    );
    final adminTile = find.ancestor(
      of: find.text('Team Admin API'),
      matching: find.byType(ListTile),
    );
    expect(
      find.descendant(
        of: planTile,
        matching: find.textContaining(PollCadence.cursorFreshnessNote),
      ),
      findsNothing,
    );
    expect(
      find.descendant(
        of: adminTile,
        matching: find.textContaining(PollCadence.cursorFreshnessNote),
      ),
      findsOneWidget,
    );
  });

  testWidgets('enables mock data only from the debug setting', (tester) async {
    final liveFixture = DashboardSnapshot.fromJsonString(
      File('../../fixtures/snapshots/dashboard_today.json').readAsStringSync(),
    );
    final liveJson = liveFixture.toJson();
    (liveJson['accounts'] as List).first['provider'] = 'openai';
    final live = DashboardSnapshot.fromJson(liveJson);
    final mockJson = liveFixture.toJson();
    final accounts = mockJson['accounts'] as List<dynamic>;
    accounts.first
      ..['provider'] = 'codex'
      ..['accountId'] = 'codex-demo';
    accounts.add({
      ...Map<String, dynamic>.from(accounts.first as Map),
      'provider': 'cursor',
      'accountId': 'cursor-demo',
    });
    final mock = DashboardSnapshot.fromJson(mockJson);
    final preferences = _MemoryDebugDataPreferenceStore();

    await tester.pumpWidget(
      WardPulseApp(
        repository: DebugDashboardRepository(
          live: ValueDashboardRepository(live),
          mock: ValueDashboardRepository(mock),
          preferences: preferences,
        ),
        debugDataAvailable: true,
        debugDataPreferenceStore: preferences,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();

    final toggle = find.widgetWithText(SwitchListTile, 'Mock data');
    await tester.scrollUntilVisible(
      toggle,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(tester.widget<SwitchListTile>(toggle).value, isFalse);

    await tester.tap(toggle);
    await tester.pumpAndSettle();

    expect(preferences.value, isTrue);
    await tester.tap(find.text('Providers'));
    await tester.pumpAndSettle();
    expect(find.text('OpenAI'), findsOneWidget);
    expect(find.text('Anthropic'), findsOneWidget);
    expect(find.text('Cursor'), findsOneWidget);
    expect(find.text('Codex subscription'), findsOneWidget);
  });

  testWidgets('hides mock data outside debug builds', (tester) async {
    await tester.pumpWidget(
      WardPulseApp(
        repository: ValueDashboardRepository(
          DashboardSnapshot.fromJsonString(
            File(
              '../../fixtures/snapshots/dashboard_today.json',
            ).readAsStringSync(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();

    expect(find.text('Mock data'), findsNothing);
  });
}

/// Mock fixture as a real connection: mock accounts hold no metric slots.
DashboardSnapshot _asConnection(DashboardSnapshot snapshot) {
  final account =
      Map<String, Object?>.from(snapshot.primaryAccount!.toJson())
        ..['accountId'] = 'anthropic-platform'
        ..['provider'] = 'claude'
        ..['connection'] = 'anthropic.platform';
  return DashboardSnapshot.fromJson({
    ...snapshot.toJson(),
    'accounts': [account],
  });
}

class _FakeWatchSyncService implements WatchSyncService {
  final syncedSnapshots = <DashboardSnapshot>[];
  void Function()? refreshHandler;

  @override
  Future<void> sync(
    DashboardSnapshot snapshot,
    ConsumptionDisplayPreferences displayPreferences,
    WatchRingPreferences ringPreferences, {
    DateTime? manualRefreshAnchorAt,
    bool mockDataMode = false,
  }) async {
    syncedSnapshots.add(snapshot);
  }

  @override
  void bindWatchRefreshListener(void Function() onRefresh) {
    refreshHandler = onRefresh;
  }

  @override
  void unbindWatchRefreshListener() {
    refreshHandler = null;
  }
}

class _FailingWatchSyncService implements WatchSyncService {
  const _FailingWatchSyncService();

  @override
  Future<void> sync(
    DashboardSnapshot snapshot,
    ConsumptionDisplayPreferences displayPreferences,
    WatchRingPreferences ringPreferences, {
    DateTime? manualRefreshAnchorAt,
    bool mockDataMode = false,
  }) {
    return Future.error(StateError('Watch unavailable'));
  }

  @override
  void bindWatchRefreshListener(void Function() onRefresh) {}

  @override
  void unbindWatchRefreshListener() {}
}

final class _FailingDashboardRepository extends DashboardRepository {
  const _FailingDashboardRepository(this.issue, [this.details]);

  final DashboardSyncIssue issue;
  final String? details;

  @override
  Future<DashboardSnapshot> load() {
    return Future.error(DashboardLoadException(issue: issue, details: details));
  }
}

final class _CountingDashboardRepository extends DashboardRepository {
  _CountingDashboardRepository(this._load);

  final DashboardSnapshot Function() _load;

  @override
  Future<DashboardSnapshot> load() async => _load();
}

class _MemoryPhoneWidgetStore implements PhoneWidgetPreferenceStore {
  PhoneWidgetPreferences value = const PhoneWidgetPreferences();

  @override
  Future<PhoneWidgetPreferences> read() async => value;

  @override
  Future<void> write(PhoneWidgetPreferences next) async {
    value = next;
  }
}

class _MemoryWatchRingStore implements WatchRingPreferenceStore {
  WatchRingPreferences value = const WatchRingPreferences();

  @override
  Future<WatchRingPreferences> read() async => value;

  @override
  Future<void> write(WatchRingPreferences next) async {
    value = next;
  }
}

class _MemoryAlertThresholdStore implements AlertThresholdPreferenceStore {
  AlertThresholdPreferences value = const AlertThresholdPreferences();

  @override
  Future<AlertThresholdPreferences> read() async => value;

  @override
  Future<void> write(AlertThresholdPreferences next) async {
    value = next;
  }
}

class _MemoryCredentialStore implements ProviderCredentialStore {
  _MemoryCredentialStore([String? openAiAdminKey]) {
    if (openAiAdminKey != null) {
      _secrets[ProviderConnections.openAiPlatform] = openAiAdminKey;
    }
  }

  final _secrets = <ProviderConnectionId, String>{};
  final _labels = <ProviderConnectionId, String>{};

  String? get openAiSecret => _secrets[ProviderConnections.openAiPlatform];

  String? get openAiLabel => _labels[ProviderConnections.openAiPlatform];

  @override
  Future<String?> readSecret(ProviderConnectionId id) async => _secrets[id];

  @override
  Future<void> writeSecret(ProviderConnectionId id, String value) async {
    _secrets[id] = value;
  }

  @override
  Future<void> deleteSecret(ProviderConnectionId id) async {
    _secrets.remove(id);
    _labels.remove(id);
  }

  @override
  Future<String?> readLabel(ProviderConnectionId id) async => _labels[id];

  @override
  Future<void> writeLabel(ProviderConnectionId id, String? value) async {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      _labels.remove(id);
      return;
    }
    _labels[id] = trimmed;
  }
}

class _MemoryDebugDataPreferenceStore implements DebugDataPreferenceStore {
  bool value = false;

  @override
  Future<bool> readMockDataEnabled() async => value;

  @override
  Future<void> writeMockDataEnabled(bool value) async {
    this.value = value;
  }
}

class _MemoryRefreshIntervalPreferenceStore
    implements RefreshIntervalPreferenceStore {
  RefreshIntervalPreference value = const RefreshIntervalPreference();

  @override
  Future<RefreshIntervalPreference> read() async => value;

  @override
  Future<void> write(RefreshIntervalPreference value) async {
    this.value = value;
  }
}

class _ManualProviderSyncScheduler implements ProviderSyncScheduler {
  final _ticks = StreamController<void>.broadcast();

  Duration? scheduledInterval;

  @override
  Stream<void> get ticks => _ticks.stream;

  @override
  Future<void> schedule(Duration interval) async {
    scheduledInterval = interval;
  }

  @override
  Future<void> cancel() async {}

  void tick() => _ticks.add(null);

  Future<void> dispose() => _ticks.close();
}
