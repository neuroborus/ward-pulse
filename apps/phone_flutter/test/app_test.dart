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
import 'package:ward_pulse_phone/settings/consumption_display_preferences.dart';
import 'package:ward_pulse_phone/settings/watch_ring_preferences.dart';
import 'package:ward_pulse_phone/settings/debug_data_preferences.dart';
import 'package:ward_pulse_phone/settings/refresh_interval_preferences.dart';
import 'package:ward_pulse_phone/sync/poll_cadence.dart';
import 'package:ward_pulse_phone/sync/provider_sync_scheduler.dart';
import 'package:ward_pulse_phone/sync/watch_sync_service.dart';

void main() {
  testWidgets('renders mock history and opens provider details', (
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

    expect(find.text('Mock'), findsOneWidget);
    await tester.tap(find.text('Mock'));
    await tester.pumpAndSettle();

    expect(find.textContaining('mock-local'), findsOneWidget);
    expect(find.text('Today'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Usage history'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('4 buckets'), findsOneWidget);
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
    expect(find.text('Stale'), findsWidgets);
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
    await tester.tap(find.text('Settings'));
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
    await tester.tap(find.text('Settings'));
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

    final settingsList = find.descendant(
      of: find.byType(ListView),
      matching: find.byType(Scrollable),
    );
    await tester.scrollUntilVisible(
      find.text('Anthropic'),
      300,
      scrollable: settingsList,
    );
    expect(find.text('Anthropic'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('Cursor'),
      300,
      scrollable: settingsList,
    );
    expect(find.text('Cursor'), findsOneWidget);
    expect(find.text('Not connected'), findsWidgets);

    await tester.scrollUntilVisible(
      find.text('Work org key'),
      300,
      scrollable: settingsList,
    );
    await tester.tap(find.text('Work org key'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();

    expect(credentialStore.openAiSecret, isNull);
    expect(credentialStore.openAiLabel, isNull);
    expect(find.text('Platform reporting'), findsOneWidget);
  });

  testWidgets('keeps credential settings available after a load failure', (
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
    await tester.tap(find.text('Settings'));
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

  testWidgets('shows plan and purchased by default and can hide purchases', (
    tester,
  ) async {
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
    final preferences = _MemoryDisplayPreferenceStore();

    await tester.pumpWidget(
      WardPulseApp(
        repository: ValueDashboardRepository(DashboardSnapshot.fromJson(json)),
        displayPreferenceStore: preferences,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Weekly plan'), findsOneWidget);
    expect(find.text('Purchased credits'), findsOneWidget);

    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(SwitchListTile, 'Platform spend'), findsOneWidget);
    await tester.tap(find.widgetWithText(SwitchListTile, 'Purchased usage'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dashboard'));
    await tester.pumpAndSettle();

    expect(preferences.value.purchased, isFalse);
    expect(preferences.value.plan, isTrue);
    expect(preferences.value.platform, isTrue);
    expect(find.text('Weekly plan'), findsOneWidget);
    expect(find.text('Purchased credits'), findsNothing);
  });

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
      find.textContaining('Every ${PollCadence.defaultRefreshMinutes} minutes'),
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
    await tester.tap(find.text('Settings'));
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
    final mock = DashboardSnapshot.fromJsonString(
      File('../../fixtures/snapshots/dashboard_today.json').readAsStringSync(),
    );
    final liveJson = mock.toJson();
    (liveJson['accounts'] as List).first['provider'] = 'openai';
    final live = DashboardSnapshot.fromJson(liveJson);
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
    expect(find.text('Mock'), findsOneWidget);
    expect(find.text('OpenAI'), findsNothing);
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

class _FakeWatchSyncService implements WatchSyncService {
  final syncedSnapshots = <DashboardSnapshot>[];

  @override
  Future<void> sync(
    DashboardSnapshot snapshot,
    ConsumptionDisplayPreferences displayPreferences,
    WatchRingPreferences ringPreferences, {
    DateTime? manualRefreshAnchorAt,
  }) async {
    syncedSnapshots.add(snapshot);
  }

  @override
  void bindWatchRefreshListener(void Function() onRefresh) {}

  @override
  void unbindWatchRefreshListener() {}
}

class _FailingWatchSyncService implements WatchSyncService {
  const _FailingWatchSyncService();

  @override
  Future<void> sync(
    DashboardSnapshot snapshot,
    ConsumptionDisplayPreferences displayPreferences,
    WatchRingPreferences ringPreferences, {
    DateTime? manualRefreshAnchorAt,
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

class _MemoryDisplayPreferenceStore
    implements ConsumptionDisplayPreferenceStore {
  ConsumptionDisplayPreferences value = const ConsumptionDisplayPreferences();

  @override
  Future<ConsumptionDisplayPreferences> read() async => value;

  @override
  Future<void> write(ConsumptionDisplayPreferences value) async {
    this.value = value;
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
