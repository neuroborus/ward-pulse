import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ward_pulse_phone/app/ward_pulse_app.dart';
import 'package:ward_pulse_phone/dashboard/dashboard_models.dart';
import 'package:ward_pulse_phone/dashboard/dashboard_repository.dart';
import 'package:ward_pulse_phone/providers/provider_credential_store.dart';
import 'package:ward_pulse_phone/settings/consumption_display_preferences.dart';
import 'package:ward_pulse_phone/settings/debug_data_preferences.dart';
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
    expect(find.text('Today'), findsWidgets);

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

    await tester.tap(find.text('Providers'));
    await tester.pumpAndSettle();

    expect(find.text('Mock'), findsOneWidget);
    await tester.tap(find.text('Mock'));
    await tester.pumpAndSettle();

    expect(find.text('mock-local'), findsOneWidget);
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

    expect(find.text('Stale'), findsOneWidget);
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
    final staleIcon = find.byIcon(Icons.schedule);
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

    expect(find.text('Not set'), findsWidgets);
    await tester.tap(find.text('OpenAI Platform credential'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), 'secret-admin-key');
    expect(
      tester.widget<TextField>(find.byType(TextField)).obscureText,
      isTrue,
    );
    await tester.tap(find.byTooltip('Show API key'));
    await tester.pump();
    expect(
      tester.widget<TextField>(find.byType(TextField)).obscureText,
      isFalse,
    );
    expect(find.byTooltip('Hide API key'), findsOneWidget);
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(credentialStore.value, 'secret-admin-key');
    expect(find.text('••••••••'), findsOneWidget);
    expect(find.text('secret-admin-key'), findsNothing);
  });

  testWidgets('keeps credential settings available after a load failure', (
    tester,
  ) async {
    final credentialStore = _MemoryCredentialStore('invalid-admin-key');

    await tester.pumpWidget(
      WardPulseApp(
        repository: const _FailingDashboardRepository(
          DashboardSyncIssue.authentication,
          'Usage · HTTP 401 · invalid_api_key',
        ),
        credentialStore: credentialStore,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Dashboard unavailable'), findsOneWidget);
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

    expect(find.text('OpenAI Platform credential'), findsOneWidget);
    expect(find.text('••••••••'), findsOneWidget);
    await tester.tap(find.text('OpenAI Platform credential'));
    await tester.pumpAndSettle();
    expect(find.text('Remove'), findsOneWidget);
  });

  testWidgets('shows plan usage by default and can include purchases', (
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
    expect(find.text('Purchased credits'), findsNothing);

    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(SwitchListTile, 'Purchased usage'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dashboard'));
    await tester.pumpAndSettle();

    expect(preferences.value.purchased, isTrue);
    expect(find.text('Weekly plan'), findsOneWidget);
    expect(find.text('Purchased credits'), findsOneWidget);
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
  ) async {
    syncedSnapshots.add(snapshot);
  }
}

class _FailingWatchSyncService implements WatchSyncService {
  const _FailingWatchSyncService();

  @override
  Future<void> sync(
    DashboardSnapshot snapshot,
    ConsumptionDisplayPreferences displayPreferences,
  ) {
    return Future.error(StateError('Watch unavailable'));
  }
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
  _MemoryCredentialStore([this.value]);

  String? value;

  @override
  Future<String?> readOpenAiAdminKey() async => value;

  @override
  Future<void> writeOpenAiAdminKey(String value) async {
    this.value = value;
  }

  @override
  Future<void> deleteOpenAiAdminKey() async {
    value = null;
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
