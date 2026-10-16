import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ward_pulse_phone/app/ward_pulse_app.dart';
import 'package:ward_pulse_phone/dashboard/dashboard_models.dart';
import 'package:ward_pulse_phone/dashboard/dashboard_repository.dart';
import 'package:ward_pulse_phone/providers/alert_threshold_dialogs.dart';
import 'package:ward_pulse_phone/providers/provider_connection.dart';
import 'package:ward_pulse_phone/providers/provider_credential_store.dart';
import 'package:ward_pulse_phone/settings/alert_threshold_preferences.dart';
import 'package:ward_pulse_phone/settings/watch_ring_preferences.dart';
import 'package:ward_pulse_phone/sync/watch_sync_service.dart';
import 'package:ward_pulse_phone/widget/phone_widget_navigation.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannelPhoneWidgetNavigationService.channel;
  const service = MethodChannelPhoneWidgetNavigationService();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  Future<void> deliver(String method) async {
    await messenger.handlePlatformMessage(
      channel.name,
      channel.codec.encodeMethodCall(MethodCall(method)),
      null,
    );
  }

  tearDown(() {
    service.unbind();
    messenger.setMockMethodCallHandler(channel, null);
  });

  test(
    'handler is bound before readiness flushes a cold widget request',
    () async {
      var opens = 0;
      final ready = Completer<void>();
      messenger.setMockMethodCallHandler(channel, (call) async {
        expect(call.method, 'navigationChannelReady');
        await deliver('openDashboard');
        ready.complete();
        return null;
      });
      service.bind(() => opens++);
      await ready.future;
      expect(opens, 1);
    },
  );

  test('unknown methods and removed handlers cannot navigate', () async {
    messenger.setMockMethodCallHandler(channel, (_) async => null);
    var opens = 0;
    service.bind(() => opens++);
    await deliver('watchRefreshRequested');
    await deliver('unrelated');
    expect(opens, 0);
    await deliver('openDashboard');
    expect(opens, 1);
    service.unbind();
    await deliver('openDashboard');
    expect(opens, 1);
  });

  testWidgets('warm widget navigation leaves polling independent', (
    tester,
  ) async {
    final repository = _CountingRepository();
    final navigation = _Navigation();
    final watch = _WatchSync();
    await tester.pumpWidget(
      WardPulseApp(
        repository: repository,
        phoneWidgetNavigationService: navigation,
        watchSyncService: watch,
      ),
    );
    await tester.pumpAndSettle();
    expect(repository.loads, 1);
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
      4,
    );

    expect(tester.binding.hasScheduledFrame, isFalse);
    navigation.open!();
    expect(tester.binding.hasScheduledFrame, isTrue);
    await tester.pumpAndSettle();
    expect(
      tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
      0,
    );
    expect(repository.loads, 1);

    watch.refresh!();
    await tester.pumpAndSettle();
    expect(repository.loads, 2);
    await tester.pumpWidget(const SizedBox());
    expect(navigation.open, isNull);
    expect(watch.refresh, isNull);
  });

  testWidgets('early widget delivery preserves ordinary startup load', (
    tester,
  ) async {
    final repository = _CountingRepository();
    final navigation = _Navigation(deliverOnBind: true);
    await tester.pumpWidget(
      WardPulseApp(
        repository: repository,
        phoneWidgetNavigationService: navigation,
        watchSyncService: _WatchSync(),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
      0,
    );
    expect(repository.loads, 1);
  });

  testWidgets(
    'widget tap cancels an edited Budget dialog before changing tabs',
    (tester) async {
      final repository = _CountingRepository();
      final navigation = _Navigation();
      final thresholds = _ThresholdStore();
      final credentials = _Credentials();
      await tester.pumpWidget(
        WardPulseApp(
          repository: repository,
          phoneWidgetNavigationService: navigation,
          watchSyncService: _WatchSync(),
          alertThresholdStore: thresholds,
          credentialStore: credentials,
          applyAlertSettings: (snapshot, _) => snapshot,
        ),
      );
      await tester.pumpAndSettle();
      Future<void> openBudget() async {
        await tester.tap(find.text('Providers'));
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.text('Platform reporting'),
          300,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.tap(
          find.descendant(
            of: find.ancestor(
              of: find.text('Platform reporting'),
              matching: find.byType(ListTile),
            ),
            matching: find.byTooltip('Budget limits'),
          ),
        );
        await tester.pumpAndSettle();
      }

      await openBudget();
      await tester.enterText(find.byType(TextField).first, '25');
      navigation.open!();
      navigation.open!();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(ConnectionBudgetDialog), findsNothing);
      expect(
        tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
        0,
      );
      expect(thresholds.writes, 0);
      expect(thresholds.value.connections, isEmpty);
      expect(credentials.mutations, 0);
      expect(repository.loads, 1);

      // A later ordinary edit still saves; the canceled draft did not survive.
      await openBudget();
      expect(
        tester.widget<TextField>(find.byType(TextField).first).controller!.text,
        '',
      );
      await tester.enterText(find.byType(TextField).first, '12.50');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(thresholds.writes, 1);
      expect(
        thresholds.value
            .forConnection(ProviderConnections.openAiPlatform)
            .budget
            .today,
        1250,
      );
      expect(credentials.mutations, 0);
    },
  );

  testWidgets('widget cancels a pushed flow; watch refresh preserves it', (
    tester,
  ) async {
    final repository = _CountingRepository();
    final navigation = _Navigation();
    final watch = _WatchSync();
    final credentials = _Credentials();
    await tester.pumpWidget(
      WardPulseApp(
        repository: repository,
        phoneWidgetNavigationService: navigation,
        watchSyncService: watch,
        credentialStore: credentials,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    final result = Navigator.of(
      tester.element(find.byType(NavigationBar)),
    ).push<String>(
      MaterialPageRoute(
        builder:
            (_) =>
                const Scaffold(body: Center(child: Text('Pending fake flow'))),
      ),
    );
    await tester.pumpAndSettle();
    watch.refresh!();
    await tester.pumpAndSettle();
    expect(find.text('Pending fake flow'), findsOneWidget);
    expect(repository.loads, 2);
    navigation.open!();
    await tester.pumpAndSettle();
    expect(await result, isNull);
    expect(find.text('Pending fake flow'), findsNothing);
    expect(
      tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
      0,
    );
    expect(repository.loads, 2);
    expect(credentials.mutations, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('pending widget delivery does nothing after disposal', (
    tester,
  ) async {
    final navigation = _Navigation();
    await tester.pumpWidget(
      WardPulseApp(
        repository: _CountingRepository(),
        phoneWidgetNavigationService: navigation,
        watchSyncService: _WatchSync(),
      ),
    );
    await tester.pumpAndSettle();
    navigation.open!();
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
    expect(navigation.open, isNull);
  });
}

class _CountingRepository extends DashboardRepository {
  int loads = 0;

  @override
  Future<DashboardSnapshot> load() async {
    loads++;
    return DashboardSnapshot.empty(
      generatedAt: DateTime.now().subtract(const Duration(minutes: 10)),
    );
  }
}

class _Navigation implements PhoneWidgetNavigationService {
  _Navigation({this.deliverOnBind = false});
  final bool deliverOnBind;
  void Function()? open;

  @override
  void bind(void Function() openDashboard) {
    open = openDashboard;
    if (deliverOnBind) openDashboard();
  }

  @override
  void unbind() => open = null;
}

class _WatchSync implements WatchSyncService {
  void Function()? refresh;

  @override
  void bindWatchRefreshListener(void Function() onRefresh) =>
      refresh = onRefresh;

  @override
  void unbindWatchRefreshListener() => refresh = null;

  @override
  Future<void> sync(
    DashboardSnapshot snapshot,
    WatchRingPreferences ringPreferences, {
    DateTime? manualRefreshAnchorAt,
    bool mockDataMode = false,
  }) async {}
}

class _ThresholdStore implements AlertThresholdPreferenceStore {
  int writes = 0;
  AlertThresholdPreferences value = const AlertThresholdPreferences();

  @override
  Future<AlertThresholdPreferences> read() async => value;

  @override
  Future<void> write(AlertThresholdPreferences next) async {
    writes++;
    value = next;
  }
}

class _Credentials implements ProviderCredentialStore {
  int mutations = 0;

  @override
  Future<String?> readSecret(ProviderConnectionId id) async => null;

  @override
  Future<String?> readLabel(ProviderConnectionId id) async => null;

  @override
  Future<void> writeSecret(ProviderConnectionId id, String value) async =>
      mutations++;

  @override
  Future<void> writeLabel(ProviderConnectionId id, String? value) async =>
      mutations++;

  @override
  Future<void> deleteSecret(ProviderConnectionId id) async => mutations++;
}
