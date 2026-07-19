import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ward_pulse_phone/app/ward_pulse_app.dart';
import 'package:ward_pulse_phone/dashboard/dashboard_models.dart';
import 'package:ward_pulse_phone/dashboard/dashboard_repository.dart';
import 'package:ward_pulse_phone/providers/provider_credential_store.dart';
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

    await tester.tap(find.text('Sync').last);
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

    expect(find.text('Not set'), findsOneWidget);
    await tester.tap(find.text('OpenAI credential'));
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
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();

    expect(find.text('OpenAI credential'), findsOneWidget);
    expect(find.text('••••••••'), findsOneWidget);
    await tester.tap(find.text('OpenAI credential'));
    await tester.pumpAndSettle();
    expect(find.text('Remove'), findsOneWidget);
  });
}

class _FakeWatchSyncService implements WatchSyncService {
  final syncedSnapshots = <DashboardSnapshot>[];

  @override
  Future<void> sync(DashboardSnapshot snapshot) async {
    syncedSnapshots.add(snapshot);
  }
}

class _FailingWatchSyncService implements WatchSyncService {
  const _FailingWatchSyncService();

  @override
  Future<void> sync(DashboardSnapshot snapshot) {
    return Future.error(StateError('Watch unavailable'));
  }
}

final class _FailingDashboardRepository extends DashboardRepository {
  const _FailingDashboardRepository(this.issue);

  final DashboardSyncIssue issue;

  @override
  Future<DashboardSnapshot> load() {
    return Future.error(DashboardLoadException(issue));
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
