import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ward_pulse_phone/app/ward_pulse_app.dart';
import 'package:ward_pulse_phone/dashboard/apply_alert_settings.dart';
import 'package:ward_pulse_phone/dashboard/dashboard_models.dart';
import 'package:ward_pulse_phone/dashboard/dashboard_load.dart';
import 'package:ward_pulse_phone/providers/connection_lifecycle.dart';
import 'package:ward_pulse_phone/sync/provider_reporting.dart';
import 'package:ward_pulse_phone/dashboard/plan_recoveries.dart';
import 'package:ward_pulse_phone/dashboard/provider_status_color.dart';
import 'package:ward_pulse_phone/dashboard/dashboard_repository.dart';
import 'package:ward_pulse_phone/dashboard/dashboard_screen.dart';
import 'package:ward_pulse_phone/dashboard/merging_connection_repository.dart';
import 'package:ward_pulse_phone/providers/provider_connection.dart';
import 'package:ward_pulse_phone/providers/alert_threshold_dialogs.dart';
import 'package:ward_pulse_phone/providers/provider_connection_row.dart';
import 'package:ward_pulse_phone/providers/providers_screen.dart';
import 'package:ward_pulse_phone/providers/provider_credential_store.dart';
import 'package:ward_pulse_phone/settings/alert_threshold_preferences.dart';
import 'package:ward_pulse_phone/settings/alert_notification_preferences.dart';
import 'package:ward_pulse_phone/settings/notification_permission_preferences.dart';
import 'package:ward_pulse_phone/settings/settings_screen.dart';
import 'package:ward_pulse_phone/sync/alert_notifications.dart';
import 'package:ward_pulse_phone/sync/notification_coordinator.dart';
import 'package:ward_pulse_phone/sync/headless_provider_sync.dart';
import 'package:ward_pulse_phone/settings/alert_percent_threshold_editor.dart';
import 'package:ward_pulse_phone/settings/watch_ring_preferences.dart';
import 'package:ward_pulse_phone/settings/debug_data_preferences.dart';
import 'package:ward_pulse_phone/settings/refresh_interval_preferences.dart';
import 'package:ward_pulse_phone/widget/phone_widget_preferences.dart';
import 'package:ward_pulse_phone/widget/phone_widget_sync.dart';
import 'package:ward_pulse_phone/sync/poll_cadence.dart';
import 'package:ward_pulse_phone/sync/provider_sync_scheduler.dart';
import 'package:ward_pulse_phone/sync/provider_sync_logger.dart';
import 'package:ward_pulse_phone/settings/recovery_notification_preferences.dart';
import 'package:ward_pulse_phone/sync/recovery_notifications.dart';
import 'package:ward_pulse_phone/sync/recovery_wake.dart';
import 'package:ward_pulse_phone/sync/recovery_watchlist.dart';
import 'package:ward_pulse_phone/sync/watch_sync_service.dart';
import 'package:ward_pulse_phone/watchface/watchface_screen.dart';

import 'connection_cache_test_support.dart';

void main() {
  for (final failed in [false, true]) {
    testWidgets(
      'default-On bootstrap is independent of ${failed ? 'failed' : 'held'} provider loading',
      (tester) async {
        await _notificationLifecycle(tester, AppLifecycleState.resumed);
        final pending = Completer<DashboardSnapshot>();
        final snapshot = DashboardSnapshot.empty();
        final repository =
            _PublicationRepository(snapshot)
              ..failLoad = failed
              ..response = failed ? null : pending.future;
        final storage = FakeSecureStorage();
        var requests = 0;
        var statusReads = 0;
        var allowed = true;
        final decision = Completer<bool>();
        final coordinator = PhoneNotificationCoordinator(
          attempts: SecureNotificationPermissionAttemptStore(storage: storage),
          initialize: () async {},
          requestPermission: () async {
            requests++;
            return decision.future;
          },
          readStatus: () async {
            statusReads++;
            return allowed;
          },
        );
        try {
          await tester.pumpWidget(
            _notificationApp(coordinator, repository: repository),
          );
          await tester.pump();
          expect(repository.loads, 1);
          expect(requests, 1);
          expect(
            await SecureNotificationPermissionAttemptStore(
              storage: storage,
            ).read(),
            isTrue,
          );
          await tester.tap(find.text('Settings'));
          await tester.pumpAndSettle();
          expect(statusReads, 1);
          expect(find.text('Notifications are blocked'), findsNothing);
          allowed = false;
          decision.complete(false);
          await tester.pumpAndSettle();
          expect(statusReads, 2);
          expect(find.text('Notifications are blocked'), findsOneWidget);
          expect(requests, 1);
        } finally {
          await tester.pumpWidget(const SizedBox());
          if (!decision.isCompleted) decision.complete(false);
          if (!pending.isCompleted) pending.complete(snapshot);
          await tester.pump();
        }
      },
    );
  }

  for (final choices in [(false, false), (true, false), (false, true)]) {
    testWidgets(
      'blocked warning preserves saved choices $choices without asking',
      (tester) async {
        if (choices == (false, false)) {
          tester.view.physicalSize = const Size(320, 800);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
        }
        await _notificationLifecycle(tester, AppLifecycleState.resumed);
        final storage = FakeSecureStorage();
        final attempts = SecureNotificationPermissionAttemptStore(
          storage: storage,
        );
        await attempts.write(true);
        var writes = 0;
        storage.beforeWrite = (_) async {
          writes++;
        };
        final alerts = _NotificationChoice()..enabled = choices.$1;
        final recoveries = _NotificationChoice()..enabled = choices.$2;
        var requests = 0;
        final coordinator = PhoneNotificationCoordinator(
          attempts: attempts,
          initialize: () async {},
          requestPermission: () async {
            requests++;
            return false;
          },
          readStatus: () async => false,
        );
        await tester.pumpWidget(
          _notificationApp(coordinator, alerts: alerts, recoveries: recoveries),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Settings'));
        await tester.pumpAndSettle();
        expect(find.text('Notifications are blocked'), findsOneWidget);
        await tester.ensureVisible(find.text('Enable notifications'));
        expect(tester.takeException(), isNull);
        final settings = tester.widget<SettingsScreen>(
          find.byType(SettingsScreen),
        );
        expect(settings.alertNotificationsEnabled, choices.$1);
        expect(settings.recoveryNotificationsEnabled, choices.$2);
        expect(alerts.writes + recoveries.writes, 0);
        expect(requests, 0);
        expect(writes, 0);
        expect(await attempts.read(), isTrue);
        expect(storage.deleted, isEmpty);
      },
    );
  }

  testWidgets(
    'Settings entry and resumed return read actual status, failures stay unknown',
    (tester) async {
      await _notificationLifecycle(tester, AppLifecycleState.resumed);
      final reads = <Completer<bool?>>[];
      final storage = FakeSecureStorage();
      var requests = 0;
      final coordinator = PhoneNotificationCoordinator(
        attempts: SecureNotificationPermissionAttemptStore(storage: storage),
        initialize: () async {},
        requestPermission: () async {
          requests++;
          return false;
        },
        readStatus: () {
          final read = Completer<bool?>();
          reads.add(read);
          return read.future;
        },
      );
      try {
        await tester.pumpWidget(
          _notificationApp(
            coordinator,
            alerts: _NotificationChoice()..enabled = false,
            recoveries: _NotificationChoice()..enabled = false,
          ),
        );
        await tester.pumpAndSettle();
        expect(reads, isEmpty);
        await tester.tap(find.text('Settings'));
        await tester.pump();
        expect(reads, hasLength(1));
        expect(find.text('Notifications are blocked'), findsNothing);
        reads[0].complete(false);
        await tester.pumpAndSettle();
        expect(find.text('Notifications are blocked'), findsOneWidget);
        await _notificationLifecycle(tester, AppLifecycleState.inactive);
        await tester.pump();
        expect(reads, hasLength(1));
        await _notificationLifecycle(tester, AppLifecycleState.resumed);
        await tester.pump();
        expect(reads, hasLength(2));
        expect(find.text('Notifications are blocked'), findsNothing);
        reads[1].complete(true);
        await tester.pumpAndSettle();
        expect(find.text('Notifications are blocked'), findsNothing);
        await tester.tap(find.text('Dashboard'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Settings'));
        await tester.pump();
        expect(reads, hasLength(3));
        reads[2].complete(null);
        await tester.pumpAndSettle();
        expect(find.text('Notifications are blocked'), findsNothing);
        await _notificationLifecycle(tester, AppLifecycleState.inactive);
        await _notificationLifecycle(tester, AppLifecycleState.resumed);
        await tester.pump();
        expect(reads, hasLength(4));
        reads[3].completeError(StateError('Status unavailable.'));
        await tester.pumpAndSettle();
        expect(find.text('Notifications are blocked'), findsNothing);
        expect(requests, 0);
        expect(storage.values, isEmpty);
        expect(storage.deleted, isEmpty);
      } finally {
        await tester.pumpWidget(const SizedBox());
        for (final read in reads) {
          if (!read.isCompleted) read.complete(null);
        }
        await tester.pump();
      }
    },
  );

  testWidgets(
    'status rejects older reads, replaced coordinators and disposed results',
    (tester) async {
      await _notificationLifecycle(tester, AppLifecycleState.resumed);
      final oldReads = <Completer<bool?>>[];
      final newReads = <Completer<bool?>>[];
      final alerts = _NotificationChoice()..enabled = false;
      final recoveries = _NotificationChoice()..enabled = false;
      PhoneNotificationCoordinator coordinator(List<Completer<bool?>> reads) =>
          PhoneNotificationCoordinator(
            initialize: () async {},
            readStatus: () {
              final read = Completer<bool?>();
              reads.add(read);
              return read.future;
            },
          );
      final oldCoordinator = coordinator(oldReads);
      final newCoordinator = coordinator(newReads);
      Future<void> resume() async {
        await _notificationLifecycle(tester, AppLifecycleState.inactive);
        await _notificationLifecycle(tester, AppLifecycleState.resumed);
        await tester.pump();
      }

      try {
        await tester.pumpWidget(
          _notificationApp(
            oldCoordinator,
            alerts: alerts,
            recoveries: recoveries,
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Settings'));
        await tester.pump();
        await resume();
        expect(oldReads, hasLength(2));
        oldReads[1].complete(true);
        await tester.pumpAndSettle();
        oldReads[0].complete(false);
        await tester.pumpAndSettle();
        expect(find.text('Notifications are blocked'), findsNothing);
        await resume();
        expect(oldReads, hasLength(3));
        await tester.pumpWidget(
          _notificationApp(
            newCoordinator,
            alerts: alerts,
            recoveries: recoveries,
          ),
        );
        expect(newReads, hasLength(1));
        newReads[0].complete(true);
        await tester.pumpAndSettle();
        oldReads[2].complete(false);
        await tester.pumpAndSettle();
        expect(find.text('Notifications are blocked'), findsNothing);
        await resume();
        expect(newReads, hasLength(2));
        await tester.pumpWidget(const SizedBox());
        newReads[1].complete(false);
        await tester.pump();
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox());
        for (final read in [...oldReads, ...newReads]) {
          if (!read.isCompleted) read.complete(null);
        }
        await tester.pump();
      }
    },
  );

  for (final alert in [true, false]) {
    testWidgets(
      '${alert ? 'alert' : 'recovery'} permission decision refreshes status with provider load held',
      (tester) async {
        await _notificationLifecycle(tester, AppLifecycleState.resumed);
        final snapshot = DashboardSnapshot.empty();
        final load = Completer<DashboardSnapshot>();
        final decision = Completer<bool>();
        final storage = FakeSecureStorage();
        final alerts = _NotificationChoice()..enabled = false;
        final recoveries = _NotificationChoice()..enabled = false;
        var requests = 0;
        var allowed = true;
        final coordinator = PhoneNotificationCoordinator(
          attempts: SecureNotificationPermissionAttemptStore(storage: storage),
          initialize: () async {},
          requestPermission: () {
            requests++;
            return decision.future;
          },
          readStatus: () async => allowed,
        );
        try {
          await tester.pumpWidget(
            _notificationApp(
              coordinator,
              repository: _PublicationRepository(snapshot)
                ..response = load.future,
              alerts: alerts,
              recoveries: recoveries,
            ),
          );
          await tester.pump();
          await tester.tap(find.text('Settings'));
          await tester.pumpAndSettle();
          final settings = tester.widget<SettingsScreen>(
            find.byType(SettingsScreen),
          );
          expect(find.text('Notifications are blocked'), findsNothing);
          final changing =
              alert
                  ? settings.onAlertNotificationsChanged(true)
                  : settings.onRecoveryNotificationsChanged(true);
          await tester.pump();
          expect(requests, 1);
          allowed = false;
          decision.complete(alert);
          expect(await changing, alert);
          await tester.pumpAndSettle();
          expect(find.text('Notifications are blocked'), findsOneWidget);
          expect(alerts.enabled, alert);
          expect(recoveries.enabled, !alert);
          expect(requests, 1);
          expect(
            await SecureNotificationPermissionAttemptStore(
              storage: storage,
            ).read(),
            isTrue,
          );
        } finally {
          await tester.pumpWidget(const SizedBox());
          if (!decision.isCompleted) decision.complete(false);
          if (!load.isCompleted) load.complete(snapshot);
          await tester.pump();
        }
      },
    );
  }

  for (final outcome in [true, false, null, 'exception']) {
    testWidgets(
      'notification settings navigation $outcome guards duplicates and preserves policy',
      (tester) async {
        await _notificationLifecycle(tester, AppLifecycleState.resumed);
        final storage = FakeSecureStorage();
        var writes = 0;
        storage.beforeWrite = (_) async {
          writes++;
        };
        final alerts = _NotificationChoice()..enabled = false;
        final recoveries = _NotificationChoice()..enabled = false;
        var opens = 0;
        var reads = 0;
        var requests = 0;
        var allowed = false;
        var opening = Completer<bool?>();
        final coordinator = PhoneNotificationCoordinator(
          attempts: SecureNotificationPermissionAttemptStore(storage: storage),
          initialize: () async {},
          requestPermission: () async {
            requests++;
            return false;
          },
          readStatus: () async {
            reads++;
            return allowed;
          },
          openSettings: () {
            opens++;
            return opening.future;
          },
        );
        Future<void> tapAction() async {
          await tester.ensureVisible(find.text('Enable notifications'));
          await tester.tap(find.text('Enable notifications'));
        }

        try {
          await tester.pumpWidget(
            _notificationApp(
              coordinator,
              alerts: alerts,
              recoveries: recoveries,
            ),
          );
          await tester.pumpAndSettle();
          await tester.tap(find.text('Settings'));
          await tester.pumpAndSettle();
          await tapAction();
          await tapAction();
          await tester.pump();
          expect(opens, 1);
          expect(
            tester
                .widget<TextButton>(
                  find.widgetWithText(TextButton, 'Enable notifications'),
                )
                .onPressed,
            isNull,
          );
          await tester.tap(find.text('Dashboard'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Settings'));
          await tester.pumpAndSettle();
          await tapAction();
          expect(
            opens,
            1,
          ); // The coordinator also guards a remounted Settings tab.
          if (outcome == 'exception') {
            opening.completeError(StateError('Settings unavailable.'));
          } else {
            opening.complete(outcome as bool?);
          }
          await tester.pumpAndSettle();
          expect(reads, 2); // Launch completion is not a status read or grant.
          expect(find.text('Notifications are blocked'), findsOneWidget);
          expect(
            find.text('Could not open Android notification settings'),
            outcome == true ? findsNothing : findsOneWidget,
          );
          expect(
            tester
                .widget<TextButton>(
                  find.widgetWithText(TextButton, 'Enable notifications'),
                )
                .onPressed,
            isNotNull,
          );
          if (outcome == true) {
            await _notificationLifecycle(tester, AppLifecycleState.inactive);
            await _notificationLifecycle(tester, AppLifecycleState.resumed);
            await tester.pumpAndSettle();
            expect(find.text('Notifications are blocked'), findsOneWidget);
            allowed = true;
            await _notificationLifecycle(tester, AppLifecycleState.inactive);
            await _notificationLifecycle(tester, AppLifecycleState.resumed);
            await tester.pumpAndSettle();
            expect(find.text('Notifications are blocked'), findsNothing);
          } else {
            opening = Completer<bool?>();
            await tapAction();
            expect(opens, 2);
            opening.complete(true);
            await tester.pumpAndSettle();
            expect(find.text('Notifications are blocked'), findsOneWidget);
          }
          expect(alerts.enabled, isFalse);
          expect(recoveries.enabled, isFalse);
          expect(alerts.writes + recoveries.writes, 0);
          expect(requests, 0);
          expect(writes, 0);
          expect(storage.values, isEmpty);
          expect(storage.deleted, isEmpty);
        } finally {
          await tester.pumpWidget(const SizedBox());
          if (!opening.isCompleted) opening.complete(false);
          await tester.pump();
        }
      },
    );
  }

  for (final choices in [(false, false), (true, false), (false, true)]) {
    testWidgets('bootstrap respects saved delivery choices $choices', (
      tester,
    ) async {
      await _notificationLifecycle(tester, AppLifecycleState.resumed);
      final storage = FakeSecureStorage();
      final alerts = SecureAlertNotificationPreferenceStore(storage: storage);
      final recoveries = SecureRecoveryNotificationPreferenceStore(
        storage: storage,
      );
      await alerts.write(choices.$1);
      await recoveries.write(choices.$2);
      var requests = 0;
      var initializations = 0;
      PhoneNotificationCoordinator coordinator() =>
          PhoneNotificationCoordinator(
            attempts: SecureNotificationPermissionAttemptStore(
              storage: storage,
            ),
            initialize: () async {
              initializations++;
            },
            requestPermission: () async {
              requests++;
              return false;
            },
          );
      for (var mount = 0; mount < 2; mount++) {
        await tester.pumpWidget(
          _notificationApp(
            coordinator(),
            alerts: alerts,
            recoveries: recoveries,
          ),
        );
        await tester.pumpAndSettle();
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
      }
      expect(requests, choices.$1 || choices.$2 ? 1 : 0);
      expect(initializations, 2); // Includes both saved Off, before any post.
      expect(await alerts.read(), choices.$1);
      expect(await recoveries.read(), choices.$2);
    });
  }

  for (final refresh in [false, true]) {
    for (final failed in [false, true]) {
      testWidgets(
        '${refresh ? 'refresh' : 'initial'} ${failed ? 'failed' : 'held'} choices cannot authorize an ask from cached On${refresh && !failed ? ' after saved Off' : ''}',
        (tester) async {
          await _notificationLifecycle(tester, AppLifecycleState.inactive);
          final alerts = _NotificationChoice();
          final recoveries = _NotificationChoice();
          final affected = refresh ? recoveries : alerts;
          final release = Completer<void>();
          var requests = 0;
          final coordinator = PhoneNotificationCoordinator(
            attempts: SecureNotificationPermissionAttemptStore(
              storage: FakeSecureStorage(),
            ),
            initialize: () async {},
            requestPermission: () async {
              requests++;
              return false;
            },
          );
          void delayRead() {
            affected.failRead = failed;
            affected.hold = failed ? null : release.future;
          }

          Future<void>? refreshing;
          try {
            if (!refresh) delayRead();
            await tester.pumpWidget(
              _notificationApp(
                coordinator,
                alerts: alerts,
                recoveries: recoveries,
              ),
            );
            if (refresh) {
              await tester.pumpAndSettle();
              await tester.tap(find.text('Settings'));
              await tester.pumpAndSettle();
              delayRead();
              refreshing =
                  tester
                      .widget<SettingsScreen>(find.byType(SettingsScreen))
                      .onRefresh();
            }
            await tester.pump();
            if (refresh && !failed) {
              final settings = tester.widget<SettingsScreen>(
                find.byType(SettingsScreen),
              );
              await settings.onAlertNotificationsChanged(false);
              await settings.onRecoveryNotificationsChanged(false);
            }
            await _notificationLifecycle(tester, AppLifecycleState.resumed);
            expect(
              requests,
              0,
            ); // Resumed alone is insufficient without its frame.
            if (!refresh && !failed) {
              release.complete();
              await tester.idle();
              expect(
                requests,
                0,
              ); // Choices are resolved; no resumed frame yet.
            }
            await tester.pump();
            expect(requests, !refresh && !failed ? 1 : 0);
            if (!release.isCompleted) release.complete();
            await refreshing;
            await tester.pumpAndSettle();
            expect(requests, failed || refresh ? 0 : 1);
            if (failed) {
              affected.failRead = false;
              await tester.tap(find.text('Settings'));
              await tester.pumpAndSettle();
              await tester
                  .widget<SettingsScreen>(find.byType(SettingsScreen))
                  .onRefresh();
              await tester.pumpAndSettle();
              expect(requests, 1);
            }
          } finally {
            await tester.pumpWidget(const SizedBox());
            if (!release.isCompleted) release.complete();
            await refreshing;
            await _notificationLifecycle(tester, AppLifecycleState.resumed);
            await tester.pump();
          }
        },
      );
    }
  }

  for (final dispose in [false, true]) {
    testWidgets(
      'foreground readiness is rechecked after initialization (${dispose ? 'disposed' : 'paused'})',
      (tester) async {
        await _notificationLifecycle(tester, AppLifecycleState.resumed);
        final ready = Completer<void>();
        var requests = 0;
        final coordinator = PhoneNotificationCoordinator(
          attempts: SecureNotificationPermissionAttemptStore(
            storage: FakeSecureStorage(),
          ),
          initialize: () => ready.future,
          requestPermission: () async {
            requests++;
            return true;
          },
        );
        try {
          await tester.pumpWidget(_notificationApp(coordinator));
          await tester.pumpAndSettle();
          expect(requests, 0);
          if (dispose) {
            await tester.pumpWidget(const SizedBox());
          } else {
            await _notificationLifecycle(tester, AppLifecycleState.paused);
          }
          ready.complete();
          await tester.pump();
          expect(requests, 0);
          await _notificationLifecycle(tester, AppLifecycleState.resumed);
          if (dispose) await tester.pumpWidget(_notificationApp(coordinator));
          await tester.pumpAndSettle();
          expect(requests, 1);
        } finally {
          await tester.pumpWidget(const SizedBox());
          if (!ready.isCompleted) ready.complete();
          await _notificationLifecycle(tester, AppLifecycleState.resumed);
          await tester.pump();
        }
      },
    );
  }

  testWidgets(
    'changed-Off choices cancel a durable preparation without losing explicit retry',
    (tester) async {
      await _notificationLifecycle(tester, AppLifecycleState.resumed);
      final claimed = Completer<void>();
      final release = Completer<void>();
      final storage =
          FakeSecureStorage()
            ..beforeWrite = (_) async {
              if (!claimed.isCompleted) claimed.complete();
              await release.future;
            };
      var requests = 0;
      final attempts = SecureNotificationPermissionAttemptStore(
        storage: storage,
      );
      final coordinator = PhoneNotificationCoordinator(
        attempts: attempts,
        initialize: () async {},
        requestPermission: () async {
          requests++;
          return false;
        },
      );
      final alerts = _NotificationChoice();
      final recoveries = _NotificationChoice();
      try {
        await tester.pumpWidget(
          _notificationApp(coordinator, alerts: alerts, recoveries: recoveries),
        );
        await tester.pumpAndSettle();
        expect(claimed.isCompleted, isTrue);
        await tester.tap(find.text('Settings'));
        await tester.pumpAndSettle();
        final settings = tester.widget<SettingsScreen>(
          find.byType(SettingsScreen),
        );
        await settings.onAlertNotificationsChanged(false);
        await settings.onRecoveryNotificationsChanged(false);
        release.complete();
        await tester.pumpAndSettle();
        expect(requests, 0);
        expect(await attempts.read(), isFalse);
        expect(await settings.onAlertNotificationsChanged(true), isFalse);
        await tester.pumpAndSettle();
        expect(requests, 1);
        expect(await attempts.read(), isTrue);
        expect(recoveries.enabled, isFalse);
      } finally {
        await tester.pumpWidget(const SizedBox());
        if (!release.isCompleted) release.complete();
        await tester.pump();
      }
    },
  );

  testWidgets('schedules foreground and injected headless work together', (
    tester,
  ) async {
    final app = WardPulseApp(
      repository: ValueDashboardRepository(DashboardSnapshot.empty()),
    );
    expect(app.scheduleHeadlessSync, HeadlessProviderSync.schedule);
    final foreground = _ManualProviderSyncScheduler();
    addTearDown(foreground.dispose);
    final headless = <Duration>[];
    await tester.pumpWidget(
      WardPulseApp(
        repository: app.repository,
        syncScheduler: foreground,
        scheduleHeadlessSync: (interval) async => headless.add(interval),
      ),
    );
    await tester.pumpAndSettle();
    expect(foreground.scheduledInterval, isNotNull);
    expect(headless, [foreground.scheduledInterval]);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });

  for (final brightness in Brightness.values) {
    testWidgets(
      'app bar keeps the WardPulse mark and title in ${brightness.name}',
      (tester) async {
        tester.platformDispatcher.platformBrightnessTestValue = brightness;
        addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);

        await tester.pumpWidget(
          WardPulseApp(repository: const NoProvidersDashboardRepository()),
        );
        await tester.pumpAndSettle();

        final appBar = find.byType(AppBar);
        final leading = tester.widget<AppBar>(appBar).leading;
        expect(leading, isA<Center>());
        final mark = (leading! as Center).child;
        expect(mark, isA<Image>());
        final image = mark! as Image;
        final asset = image.image as AssetImage;

        expect(asset.assetName, 'assets/brand/wardpulse.png');
        expect(image.width, 32);
        expect(image.height, 32);
        expect(image.excludeFromSemantics, isTrue);
        expect(
          find.descendant(of: appBar, matching: find.text('WardPulse')),
          findsOneWidget,
        );
        expect(Theme.of(tester.element(appBar)).brightness, brightness);
      },
    );
  }

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
      find.byKey(const ValueKey('source-expense.today')),
      -300,
      scrollable: dashboard,
    );
    expect(find.text('Today'), findsWidgets);

    await tester.tap(find.text('Providers'));
    await tester.pumpAndSettle();

    // Which family sits where is the tab's own business
    // (providers_screen_test.dart); this test only asks that the catalog
    // opened, so it scrolls to the row instead of assuming a position.
    await tester.scrollUntilVisible(
      find.text('Codex plan'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Codex plan'), findsOneWidget);
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

  testWidgets(
    'Wear refresh failure retains the warm live connection as stale',
    (tester) async {
      final snapshot = _asConnection(
        DashboardSnapshot.fromJsonString(
          File(
            '../../fixtures/snapshots/dashboard_today.json',
          ).readAsStringSync(),
        ),
      );
      var failReport = false;
      final repository = MergingConnectionRepository(
        fallback: const NoProvidersDashboardRepository(),
        loadReport: () async {
          if (failReport) {
            throw StateError('Network unavailable');
          }
          return 'report';
        },
        normalizeReport: (_) => snapshot.toJsonString(),
        mapError: (_) => const DashboardLoadException(),
        logger: const NullProviderSyncLogger(),
      );
      final watch = _FakeWatchSyncService();
      await tester.pumpWidget(
        WardPulseApp(repository: repository, watchSyncService: watch),
      );
      await tester.pumpAndSettle();
      expect(
        watch.syncedSnapshots.last.accounts.single.accountId,
        'anthropic-platform',
      );

      failReport = true;
      watch.refreshHandler!();
      await tester.pumpAndSettle();

      final retained = watch.syncedSnapshots.last;
      expect(retained.overallStatus, ProviderStatus.stale);
      expect(retained.syncIssue, DashboardSyncIssue.dashboardUnavailable);
      expect(retained.generatedAt, snapshot.generatedAt);
      expect(retained.accounts.single.accountId, 'anthropic-platform');
      expect(retained.accounts.single.status, ProviderStatus.stale);
      expect(
        retained.accounts.single.today.toJson(),
        snapshot.accounts.single.today.toJson(),
      );
      expect(find.text('Usage dashboard'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

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

  testWidgets('Settings sync reports invalid saved capacity without queuing', (
    tester,
  ) async {
    const ids = [
      codexPlanRingId,
      codexSparkRingId,
      cursorOwnPoolId,
      cursorOtherPoolId,
      claudePlanRingId,
      claudeFableRingId,
    ];
    final store =
        _MemoryWatchRingStore()
          ..value = const WatchRingPreferences(selectedIds: ids);
    final published = <String>[];
    const channel = MethodChannel('app.wardpulse/watch_sync');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'syncWatchSummary');
      published.add(call.arguments as String);
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    await tester.pumpWidget(
      WardPulseApp(
        repository: ValueDashboardRepository(
          _threePairDashboard(fableUsed: null),
        ),
        watchRingPreferenceStore: store,
      ),
    );
    await tester.pumpAndSettle();
    expect(published, isEmpty);
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Send to watch'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -160));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Sync'));
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.widgetWithText(ListTile, 'Send to watch'),
        matching: find.text(
          'Watch updates paused · correct ring choices to resume',
        ),
      ),
      findsOneWidget,
    );
    expect(find.text('Watch summary queued'), findsNothing);
    expect(published, isEmpty);
    expect(store.value.selectedIds, ids);
    expect(tester.takeException(), isNull);
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
      find.widgetWithText(ListTile, 'Watch summary'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Diagnostics'), findsOneWidget);
    expect(find.text('Sync'), findsWidgets);
    expect(find.text('Watch summary'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Help'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.widgetWithText(ListTile, 'Help'), findsOneWidget);
  });

  testWidgets('Settings keeps Help and Legal without snapshot or debug', (
    tester,
  ) async {
    await tester.pumpWidget(
      WardPulseApp(
        repository: const _FailingDashboardRepository(
          DashboardSyncIssue.dashboardUnavailable,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();

    expect(find.text('Debug'), findsNothing);
    expect(find.text('Diagnostics'), findsNothing);
    await tester.scrollUntilVisible(
      find.text('Help'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.widgetWithText(ListTile, 'Help'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Legal'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Legal'), findsOneWidget);
    expect(
      find.text(
        'WardPulse is an independent usage monitor. It is not affiliated with, '
        'endorsed by, or sponsored by OpenAI, Anthropic, Cursor, Google, or any '
        'other provider. Product names are trademarks of their respective owners.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('Settings Help opens the public guide in an external browser', (
    tester,
  ) async {
    const channel = MethodChannel('plugins.flutter.io/url_launcher');
    final messenger = tester.binding.defaultBinaryMessenger;
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return true;
    });

    await tester.pumpWidget(
      WardPulseApp(repository: const NoProvidersDashboardRepository()),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Help'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Help'));
    await tester.pumpAndSettle();

    expect(calls, hasLength(1));
    expect(calls.single.method, 'launch');
    expect(
      calls.single.arguments,
      allOf(
        containsPair('url', 'https://neuroborus.github.io/ward-pulse/'),
        containsPair('useWebView', false),
        containsPair('useSafariVC', false),
        containsPair('universalLinksOnly', false),
        containsPair('headers', isEmpty),
      ),
    );
    expect(find.byType(SnackBar), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final throwsException in [false, true]) {
    for (final disposeBeforeCompletion in [false, true]) {
      testWidgets(
        'Settings Help handles '
        '${throwsException ? 'a platform exception' : 'a false launch result'}'
        '${disposeBeforeCompletion ? ' after disposal' : ''}',
        (tester) async {
          const channel = MethodChannel('plugins.flutter.io/url_launcher');
          final messenger = tester.binding.defaultBinaryMessenger;
          addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
          final completion = Completer<bool>();
          final calls = <MethodCall>[];
          messenger.setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            return completion.future;
          });

          await tester.pumpWidget(
            WardPulseApp(repository: const NoProvidersDashboardRepository()),
          );
          await tester.pumpAndSettle();
          await tester.tap(find.text('Settings'));
          await tester.pumpAndSettle();
          await tester.scrollUntilVisible(
            find.text('Help'),
            300,
            scrollable: find.byType(Scrollable).first,
          );
          await tester.tap(find.text('Help'));
          await tester.pump();
          expect(calls, hasLength(1));
          expect(calls.single.method, 'launch');
          expect(find.byType(SnackBar), findsNothing);

          if (disposeBeforeCompletion) {
            await tester.pumpWidget(const SizedBox.shrink());
          }
          if (throwsException) {
            completion.completeError(PlatformException(code: 'launch_failed'));
          } else {
            completion.complete(false);
          }
          await tester.pumpAndSettle();

          expect(tester.takeException(), isNull);
          expect(
            find.text('Could not open the browser'),
            disposeBeforeCompletion ? findsNothing : findsOneWidget,
          );
        },
      );
    }
  }

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

  for (final trigger in ['refresh', 'scheduled']) {
    testWidgets(
      '$trigger rechecks revision after delayed ownership validation',
      (tester) async {
        final live = DashboardSnapshot.fromJsonString(
          File(
            '../../fixtures/snapshots/dashboard_today.json',
          ).readAsStringSync(),
        );
        final repository = _PublicationRepository(live);
        final watch = _FakeWatchSyncService();
        final scheduler = _ManualProviderSyncScheduler();
        addTearDown(scheduler.dispose);
        await tester.pumpWidget(
          WardPulseApp(
            repository: repository,
            watchSyncService: watch,
            syncScheduler: scheduler,
          ),
        );
        await tester.pumpAndSettle();
        repository.delayNextValidation = true;
        if (trigger == 'refresh') {
          await tester.tap(find.byTooltip('Refresh'));
        } else {
          scheduler.tick();
        }
        await tester.pump();
        await tester.pump();
        expect(repository.validationStarted, isTrue);
        repository.snapshot = DashboardSnapshot.empty();
        await tester.tap(find.byTooltip('Refresh'));
        await tester.pumpAndSettle();
        expect(watch.syncedSnapshots.last.accounts, isEmpty);
        repository.validation.complete(true);
        await tester.pumpAndSettle();
        expect(watch.syncedSnapshots.last.accounts, isEmpty);
        expect(find.text('Connect a provider'), findsWidgets);
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets('delayed alert write cannot reinstate a removed account', (
    tester,
  ) async {
    final live = DashboardSnapshot.fromJsonString(
      File('../../fixtures/snapshots/dashboard_today.json').readAsStringSync(),
    );
    final repository = _PublicationRepository(live);
    final scheduler = _ManualProviderSyncScheduler();
    addTearDown(scheduler.dispose);
    final store = _DelayedAlertThresholdStore();
    final watch = _FakeWatchSyncService();
    final phoneWidget = _FakePhoneWidgetSyncService();
    final inputs = <DashboardSnapshot>[];
    await tester.pumpWidget(
      WardPulseApp(
        repository: repository,
        syncScheduler: scheduler,
        watchSyncService: watch,
        phoneWidgetSyncService: phoneWidget,
        alertThresholdStore: store,
        applyAlertSettings: (current, _) {
          inputs.add(current);
          return current;
        },
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Providers'));
    await tester.pumpAndSettle();
    final button = find.descendant(
      of: find.ancestor(
        of: find.text('Platform reporting'),
        matching: find.byType(ProviderConnectionRow),
      ),
      matching: find.byWidgetPredicate(
        (widget) => widget is IconButton && widget.tooltip == 'Budget limits',
      ),
    );
    await tester.scrollUntilVisible(
      button,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(button.hitTestable(), findsOneWidget);
    await tester.tap(button);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '25');
    await tester.tap(find.text('Save'));
    await tester.pump();
    expect(store.started, isTrue);
    repository.snapshot = DashboardSnapshot.empty();
    scheduler.tick();
    await tester.pump();
    await tester.pump();
    store.release.complete();
    await tester.pumpAndSettle();
    expect(watch.syncedSnapshots.last.accounts, isEmpty);
    expect(phoneWidget.syncedSnapshots.last.accounts, isEmpty);
    await tester
        .widget<ProvidersScreen>(find.byType(ProvidersScreen))
        .onAlertThresholdsChanged(
          (current) => current.withConnection(
            ProviderConnections.codexPlan,
            const ConnectionAlertThresholds(
              plan: AlertPercentThreshold(at: 70),
            ),
          ),
        );
    await tester.pumpAndSettle();
    expect(inputs.last.accounts, isEmpty);
    expect(watch.syncedSnapshots.last.accounts, isEmpty);
    expect(phoneWidget.syncedSnapshots.last.accounts, isEmpty);
    await tester.tap(find.text('Dashboard'));
    await tester.pumpAndSettle();
    expect(find.text('Connect a provider'), findsWidgets);
    expect(
      store.value
          .forConnection(ProviderConnections.openAiPlatform)
          .budget
          .today,
      2500,
    );
  });

  testWidgets('alert edits reevaluate owned input and publish both surfaces', (
    tester,
  ) async {
    final source = _alertTestSnapshot();
    final repository = _PublicationRepository(source);
    final scheduler = _ManualProviderSyncScheduler();
    addTearDown(scheduler.dispose);
    final watch = _FakeWatchSyncService();
    final phoneWidget = _FakePhoneWidgetSyncService();
    final store = _MemoryAlertThresholdStore();
    store.value = store.value.withConnection(
      ProviderConnections.codexPlan,
      const ConnectionAlertThresholds(plan: AlertPercentThreshold(at: 70)),
    );
    final inputs = <DashboardSnapshot>[];
    await tester.pumpWidget(
      WardPulseApp(
        repository: repository,
        syncScheduler: scheduler,
        watchSyncService: watch,
        phoneWidgetSyncService: phoneWidget,
        alertThresholdStore: store,
        applyAlertSettings: (snapshot, settings) {
          inputs.add(snapshot);
          // Deliberately nonidentity: proves shell reevaluation, not native math.
          return applyUserAlertSettings(
            snapshot,
            settings,
            applyJson: (input, _) {
              final json = jsonDecode(input) as Map<String, dynamic>;
              final accounts = json['accounts'] as List;
              final account = accounts.first as Map<String, dynamic>;
              final windows = account['allowances'] as List;
              final rules = settings.forConnection(
                ProviderConnections.codexPlan,
              );
              final at = (rules.planWindows['window-a'] ?? rules.plan).at;
              if (windows.isNotEmpty && at != null && at <= 75) {
                account['status'] = 'warning';
                (windows.first as Map<String, dynamic>)['status'] = 'warning';
                json['alerts'] = [
                  {'severity': 'warning', 'message': 'Configured window alert'},
                ];
              }
              return jsonEncode(json);
            },
          );
        },
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Providers'));
    await tester.pumpAndSettle();

    void expectPublished(bool crossed) {
      final snapshot = watch.syncedSnapshots.last;
      expect(phoneWidget.syncedSnapshots.last, same(snapshot));
      expect(
        snapshot.accounts.first.status,
        crossed ? ProviderStatus.warning : ProviderStatus.ok,
      );
      expect(
        snapshot.accounts.first.allowances.single.status,
        crossed ? ProviderStatus.warning : ProviderStatus.ok,
      );
      expect(snapshot.alerts, crossed ? isNotEmpty : isEmpty);
      expect(snapshot.accounts.skip(1).map((account) => account.status), [
        ProviderStatus.warning,
        ProviderStatus.rateLimited,
        ProviderStatus.authRequired,
      ]);
      expect(snapshot.todayTotal.toJson(), source.todayTotal.toJson());
      expect(snapshot.accounts.first.today.status, ProviderStatus.warning);
      expect(snapshot.syncIssue, repository.snapshot.syncIssue);
      expect(snapshot.syncDetails, repository.snapshot.syncDetails);
      expect(
        snapshot.connectionVersions,
        repository.snapshot.connectionVersions,
      );
      expect(snapshot.reportingOutcomes, repository.snapshot.reportingOutcomes);
    }

    expectPublished(true);
    const edits = [
      // Explicit Off suppresses the enabled fallback.
      ConnectionAlertThresholds(
        plan: AlertPercentThreshold(at: 70),
        planWindows: {'window-a': AlertPercentThreshold()},
      ),
      // Removing that entry resumes inheritance.
      ConnectionAlertThresholds(plan: AlertPercentThreshold(at: 70)),
      ConnectionAlertThresholds(plan: AlertPercentThreshold(at: 90)),
      ConnectionAlertThresholds(
        planWindows: {'window-a': AlertPercentThreshold(at: 70)},
      ),
      ConnectionAlertThresholds(
        planWindows: {'window-a': AlertPercentThreshold()},
      ),
    ];
    for (var index = 0; index < edits.length; index++) {
      // Either failed delivery must leave the other independent path usable.
      watch.fail = index == 0;
      phoneWidget.fail = index == 1;
      await tester
          .widget<ProvidersScreen>(find.byType(ProvidersScreen))
          .onAlertThresholdsChanged(
            (current) => current.withConnection(
              ProviderConnections.codexPlan,
              edits[index],
            ),
          );
      await tester.pumpAndSettle();
      expectPublished(index == 1 || index == 3);
      expect(repository.loads, 1);
      expect(inputs, everyElement(same(source)));
      expect(watch.syncedSnapshots, hasLength(index + 2));
      expect(phoneWidget.syncedSnapshots, hasLength(index + 2));
    }
    watch.fail = false;
    phoneWidget.fail = false;

    // A missing window keeps its rule; the same ID returns with a new label.
    repository.snapshot = _alertTestSnapshot(includeWindow: false);
    scheduler.tick();
    await tester.pumpAndSettle();
    await tester
        .widget<ProvidersScreen>(find.byType(ProvidersScreen))
        .onAlertThresholdsChanged(
          (current) => current.withConnection(
            ProviderConnections.codexPlan,
            const ConnectionAlertThresholds(
              planWindows: {'window-a': AlertPercentThreshold(at: 70)},
            ),
          ),
        );
    await tester.pumpAndSettle();
    expect(inputs.last, same(repository.snapshot));
    expect(watch.syncedSnapshots.last.alerts, isEmpty);
    repository.snapshot = _alertTestSnapshot(windowLabel: 'Renamed');
    scheduler.tick();
    await tester.pumpAndSettle();
    expectPublished(true);
    expect(inputs.last, same(repository.snapshot));
    expect(
      watch.syncedSnapshots.last.accounts.first.allowances.single.label,
      'Renamed',
    );
    expect(repository.loads, 3);
    expect(
      AlertThresholdPreferences.decode(store.value.encode())
          .forConnection(ProviderConnections.codexPlan)
          .planWindows['window-a']!
          .at,
      70,
    );
    expect(tester.takeException(), isNull);
  });

  for (final refreshFirst in [true, false]) {
    testWidgets(
      'in-flight refresh converges with alert save (refresh first: $refreshFirst)',
      (tester) async {
        final source = _alertTestSnapshot();
        final newer = _alertTestSnapshot(windowLabel: 'New data');
        final repository = _PublicationRepository(source);
        final store = _DelayedAlertThresholdStore();
        final watch = _FakeWatchSyncService();
        final phoneWidget = _FakePhoneWidgetSyncService();
        await tester.pumpWidget(
          WardPulseApp(
            repository: repository,
            alertThresholdStore: store,
            watchSyncService: watch,
            phoneWidgetSyncService: phoneWidget,
            applyAlertSettings:
                (snapshot, settings) => applyUserAlertSettings(
                  snapshot,
                  settings,
                  applyJson:
                      (input, _) => jsonEncode({
                        ...jsonDecode(input) as Map<String, dynamic>,
                        'alerts': [
                          {
                            'severity': 'warning',
                            'message': 'Configured alert',
                          },
                        ],
                      }),
                ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Providers'));
        await tester.pumpAndSettle();
        final refresh = Completer<DashboardSnapshot>();
        repository.response = refresh.future;
        await tester.tap(find.byTooltip('Refresh'));
        await tester.pumpAndSettle();
        expect(repository.loads, 2);

        final save = tester
            .widget<ProvidersScreen>(find.byType(ProvidersScreen))
            .onAlertThresholdsChanged(
              (current) => current.withConnection(
                ProviderConnections.codexPlan,
                const ConnectionAlertThresholds(
                  plan: AlertPercentThreshold(at: 70),
                ),
              ),
            );
        await tester.pump();
        expect(store.started, isTrue);
        if (refreshFirst) {
          refresh.complete(newer);
          await tester.pumpAndSettle();
        }
        store.release.complete();
        await save;
        await tester.pumpAndSettle();
        if (!refreshFirst) {
          // The edit is visible while the original foreground future is pending.
          await tester.tap(find.text('Dashboard'));
          await tester.pumpAndSettle();
          final interim =
              tester
                  .widget<DashboardScreen>(find.byType(DashboardScreen))
                  .snapshot;
          expect(interim.accounts.first.allowances.single.label, 'Window A');
          expect(interim.alerts.single.message, 'Configured alert');
          refresh.complete(newer);
          await tester.pumpAndSettle();
        } else {
          await tester.tap(find.text('Dashboard'));
          await tester.pumpAndSettle();
        }

        final displayed =
            tester
                .widget<DashboardScreen>(find.byType(DashboardScreen))
                .snapshot;
        expect(displayed.accounts.first.allowances.single.label, 'New data');
        expect(displayed.alerts.single.message, 'Configured alert');
        expect(displayed.toJson(), watch.syncedSnapshots.last.toJson());
        expect(displayed.toJson(), phoneWidget.syncedSnapshots.last.toJson());
        expect(repository.loads, 2);
        expect(
          store.value.forConnection(ProviderConnections.codexPlan).plan.at,
          70,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final failure in ['evaluation', 'persistence']) {
    testWidgets('$failure failure preserves state and releases queued edits', (
      tester,
    ) async {
      final store = _MemoryAlertThresholdStore();
      final watch = _FakeWatchSyncService();
      final phoneWidget = _FakePhoneWidgetSyncService();
      var failEvaluation = false;
      await tester.pumpWidget(
        WardPulseApp(
          repository: ValueDashboardRepository(_alertTestSnapshot()),
          watchSyncService: watch,
          phoneWidgetSyncService: phoneWidget,
          alertThresholdStore: store,
          applyAlertSettings: (snapshot, _) {
            if (failEvaluation) {
              failEvaluation = false;
              throw StateError('Evaluation unavailable');
            }
            return snapshot;
          },
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Providers'));
      await tester.pumpAndSettle();
      final providers = tester.widget<ProvidersScreen>(
        find.byType(ProvidersScreen),
      );
      final previous = watch.syncedSnapshots.single;
      failEvaluation = failure == 'evaluation';
      store.failNextWrite = failure == 'persistence';
      final failed = providers.onAlertThresholdsChanged(
        (current) => current.withConnection(
          ProviderConnections.codexPlan,
          const ConnectionAlertThresholds(plan: AlertPercentThreshold(at: 70)),
        ),
      );
      final observedFailure = expectLater(failed, throwsStateError);
      final queued = providers.onAlertThresholdsChanged((current) {
        expect(current.connections, isEmpty);
        expect(store.value.connections, isEmpty);
        expect(store.writes, failure == 'evaluation' ? 0 : 1);
        expect(watch.syncedSnapshots, [previous]);
        expect(phoneWidget.syncedSnapshots, [previous]);
        return current.withConnection(
          ProviderConnections.cursorPlan,
          const ConnectionAlertThresholds(plan: AlertPercentThreshold(at: 90)),
        );
      });
      await observedFailure;
      await queued;
      await tester.pumpAndSettle();
      expect(
        store.value.forConnection(ProviderConnections.codexPlan).isEnabled,
        isFalse,
      );
      expect(
        store.value.forConnection(ProviderConnections.cursorPlan).plan.at,
        90,
      );
      expect(watch.syncedSnapshots, hasLength(2));
      expect(phoneWidget.syncedSnapshots, hasLength(2));
      expect(
        tester
            .widget<ProvidersScreen>(find.byType(ProvidersScreen))
            .alertThresholds
            .toJson(),
        store.value.toJson(),
      );
      expect(tester.takeException(), isNull);
    });
  }

  for (final failureFirst in [true, false]) {
    testWidgets(
      'alert save updates scheduled fallback (failure first: $failureFirst)',
      (tester) async {
        final source = _alertTestSnapshot();
        final repository = _PublicationRepository(source);
        final store = _DelayedAlertThresholdStore();
        store.value = store.value.withConnection(
          ProviderConnections.codexPlan,
          const ConnectionAlertThresholds(plan: AlertPercentThreshold(at: 70)),
        );
        final scheduler = _ManualProviderSyncScheduler();
        addTearDown(scheduler.dispose);
        final watch = _FakeWatchSyncService();
        final phoneWidget = _FakePhoneWidgetSyncService();
        final inputs = <DashboardSnapshot>[];
        await tester.pumpWidget(
          WardPulseApp(
            repository: repository,
            alertThresholdStore: store,
            syncScheduler: scheduler,
            watchSyncService: watch,
            phoneWidgetSyncService: phoneWidget,
            applyAlertSettings: (snapshot, settings) {
              inputs.add(snapshot);
              return applyUserAlertSettings(
                snapshot,
                settings,
                applyJson:
                    (input, _) => jsonEncode({
                      ...jsonDecode(input) as Map<String, dynamic>,
                      'alerts': [
                        {'severity': 'warning', 'message': 'Configured alert'},
                      ],
                    }),
              );
            },
          ),
        );
        await tester.pumpAndSettle();
        expect(watch.syncedSnapshots.single.alerts, isNotEmpty);
        await tester.tap(find.text('Providers'));
        await tester.pumpAndSettle();
        final save = tester
            .widget<ProvidersScreen>(find.byType(ProvidersScreen))
            .onAlertThresholdsChanged(
              (current) => current.withConnection(
                ProviderConnections.codexPlan,
                const ConnectionAlertThresholds(),
              ),
            );
        await tester.pump();
        expect(store.started, isTrue);
        final refresh = Completer<DashboardSnapshot>();
        repository.response = refresh.future;
        scheduler.tick();
        await tester.pumpAndSettle();
        expect(repository.loads, 2);
        if (failureFirst) {
          refresh.completeError(const DashboardLoadException());
          await tester.pumpAndSettle();
        }
        store.release.complete();
        await save;
        await tester.pumpAndSettle();
        if (!failureFirst) {
          refresh.completeError(const DashboardLoadException());
          await tester.pumpAndSettle();
        }
        await tester.tap(find.text('Dashboard'));
        await tester.pumpAndSettle();
        final displayed =
            tester
                .widget<DashboardScreen>(find.byType(DashboardScreen))
                .snapshot;
        expect(displayed.toJson(), source.toJson());
        expect(displayed.alerts, isEmpty);
        expect(watch.syncedSnapshots.last.toJson(), displayed.toJson());
        expect(phoneWidget.syncedSnapshots.last.toJson(), displayed.toJson());
        expect(watch.syncedSnapshots, hasLength(2));
        expect(phoneWidget.syncedSnapshots, hasLength(2));
        expect(inputs, [source, source]);
        expect(store.value.hasEnabledRules, isFalse);
        expect(repository.loads, 2);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'alert write rechecks ownership before publishing either surface',
    (tester) async {
      final source = _alertTestSnapshot();
      final repository = _PublicationRepository(source);
      final store = _DelayedAlertThresholdStore();
      final watch = _FakeWatchSyncService();
      final phoneWidget = _FakePhoneWidgetSyncService();
      await tester.pumpWidget(
        WardPulseApp(
          repository: repository,
          alertThresholdStore: store,
          watchSyncService: watch,
          phoneWidgetSyncService: phoneWidget,
          applyAlertSettings: (snapshot, _) => snapshot,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Providers'));
      await tester.pumpAndSettle();
      final save = tester
          .widget<ProvidersScreen>(find.byType(ProvidersScreen))
          .onAlertThresholdsChanged(
            (current) => current.withConnection(
              ProviderConnections.codexPlan,
              const ConnectionAlertThresholds(
                plan: AlertPercentThreshold(at: 70),
              ),
            ),
          );
      await tester.pump();
      expect(store.started, isTrue);
      repository.current = false;
      store.release.complete();
      await save;
      await tester.pumpAndSettle();
      expect(watch.syncedSnapshots, [source]);
      expect(phoneWidget.syncedSnapshots, [source]);
      expect(
        store.value.forConnection(ProviderConnections.codexPlan).plan.at,
        70,
      );
      expect(repository.loads, 1);
      expect(tester.takeException(), isNull);
    },
  );

  for (final retirement in [
    'foreground',
    'scheduled',
    'credentials',
    'fallback',
  ]) {
    testWidgets('$retirement load keeps only usable owned alert input', (
      tester,
    ) async {
      final source = _alertTestSnapshot();
      final repository = _PublicationRepository(source);
      final scheduler = _ManualProviderSyncScheduler();
      addTearDown(scheduler.dispose);
      final watch = _FakeWatchSyncService();
      final phoneWidget = _FakePhoneWidgetSyncService();
      final inputs = <DashboardSnapshot>[];
      await tester.pumpWidget(
        WardPulseApp(
          repository: repository,
          syncScheduler: scheduler,
          watchSyncService: watch,
          phoneWidgetSyncService: phoneWidget,
          applyAlertSettings: (snapshot, _) {
            inputs.add(snapshot);
            return snapshot;
          },
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Providers'));
      await tester.pumpAndSettle();
      repository.failLoad = true;
      repository.current = retirement != 'scheduled';
      if (retirement == 'credentials') {
        tester
            .widget<ProvidersScreen>(find.byType(ProvidersScreen))
            .onCredentialsChanged();
      } else if (retirement == 'foreground') {
        await tester.tap(find.byTooltip('Refresh'));
      } else {
        scheduler.tick();
      }
      await tester.pumpAndSettle();
      await tester
          .widget<ProvidersScreen>(find.byType(ProvidersScreen))
          .onAlertThresholdsChanged(
            (current) => current.withConnection(
              ProviderConnections.codexPlan,
              const ConnectionAlertThresholds(
                plan: AlertPercentThreshold(at: 70),
              ),
            ),
          );
      await tester.pumpAndSettle();
      final retained = retirement == 'fallback';
      expect(inputs, retained ? [source, source] : [source]);
      expect(watch.syncedSnapshots, retained ? [source, source] : [source]);
      expect(
        phoneWidget.syncedSnapshots,
        retained ? [source, source] : [source],
      );
      expect(
        tester
            .widget<ProvidersScreen>(find.byType(ProvidersScreen))
            .alertThresholds
            .forConnection(ProviderConnections.codexPlan)
            .plan
            .at,
        70,
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('a reload keeps the dashboard on screen', (tester) async {
    final snapshot = DashboardSnapshot.fromJsonString(
      File('../../fixtures/snapshots/dashboard_today.json').readAsStringSync(),
    );

    await tester.pumpWidget(
      WardPulseApp(repository: ValueDashboardRepository(snapshot)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Usage dashboard'), findsOneWidget);

    // The refresh used to blank the tab and draw it again, which read as a
    // flicker over the numbers the reader was looking at.
    await tester.tap(find.byTooltip('Refresh'));
    await tester.pump();
    expect(find.text('Usage dashboard'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);

    await tester.pumpAndSettle();
    expect(find.text('Usage dashboard'), findsOneWidget);
  });

  testWidgets(
    'missing saved choices remain visible and removable after a failed load',
    (tester) async {
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

      expect(find.text('No metrics yet'), findsOneWidget);
      expect(find.textContaining('3 of 3 slots used'), findsOneWidget);
      final saved = find.widgetWithText(CheckboxListTile, 'Codex plan');
      expect(tester.widget<CheckboxListTile>(saved).value, isTrue);
      expect(tester.widget<CheckboxListTile>(saved).onChanged, isNotNull);
      await tester.ensureVisible(saved);
      await tester.tap(saved);
      await tester.pumpAndSettle();
      expect(store.value.selectedIds, [
        'budget.anthropic.platform.today',
        'budget.anthropic.platform.week',
      ]);
      expect(find.textContaining('2 of 3 slots used'), findsOneWidget);
    },
  );

  for (final (ids, reason) in [
    (
      [
        codexPlanRingId,
        codexSparkRingId,
        cursorOwnPoolId,
        cursorOtherPoolId,
        claudePlanRingId,
      ],
      'two paired bands',
    ),
    (
      [codexPlanRingId, cursorOwnPoolId, 'budget.anthropic.plan.today'],
      '3 bands',
    ),
  ]) {
    testWidgets('Watchface rejects an addition over $reason without saving', (
      tester,
    ) async {
      final writes = <WatchRingPreferences>[];
      await tester.pumpWidget(
        _watchPicker(
          snapshot: _threePairDashboard(),
          initial: WatchRingPreferences(selectedIds: ids),
          onChanged: writes.add,
        ),
      );
      final fable = find.widgetWithText(CheckboxListTile, 'Fable');
      expect(tester.widget<CheckboxListTile>(fable).value, isFalse);
      expect(tester.widget<CheckboxListTile>(fable).onChanged, isNull);
      expect(
        find.descendant(of: fable, matching: find.textContaining(reason)),
        findsOneWidget,
      );
      await tester.ensureVisible(fable);
      await tester.tap(fable);
      await tester.pumpAndSettle();
      expect(writes, isEmpty);
    });
  }

  testWidgets(
    'invalid saved choices allow unavailable and missing removals until corrected',
    (tester) async {
      const ids = [
        codexPlanRingId,
        codexSparkRingId,
        cursorOwnPoolId,
        cursorOtherPoolId,
        claudePlanRingId,
        claudeFableRingId,
        'missing.metric',
      ];
      final writes = <WatchRingPreferences>[];
      await tester.pumpWidget(
        _watchPicker(
          snapshot: _threePairDashboard(fableUsed: null),
          initial: const WatchRingPreferences(selectedIds: ids),
          onChanged: writes.add,
        ),
      );
      expect(find.text('Correct ring choices'), findsOneWidget);
      expect(
        find.textContaining('phone and widget updates continue'),
        findsOneWidget,
      );
      final fable = find.widgetWithText(CheckboxListTile, 'Fable');
      expect(tester.widget<CheckboxListTile>(fable).onChanged, isNotNull);
      await tester.ensureVisible(fable);
      await tester.pumpAndSettle();
      await tester.tap(fable);
      await tester.pumpAndSettle();
      expect(
        writes.single.selectedIds,
        ids.where((id) => id != claudeFableRingId),
      );
      expect(find.text('Correct ring choices'), findsOneWidget);
      final missing = find.widgetWithText(
        CheckboxListTile,
        'Saved metric: missing.metric',
      );
      expect(tester.widget<CheckboxListTile>(missing).value, isTrue);
      expect(tester.widget<CheckboxListTile>(missing).onChanged, isNotNull);
      await tester.ensureVisible(missing);
      await tester.pumpAndSettle();
      await tester.tap(missing);
      await tester.pumpAndSettle();
      expect(
        writes.last.selectedIds,
        ids.where((id) => id != claudeFableRingId && id != 'missing.metric'),
      );
      expect(find.text('Correct ring choices'), findsNothing);
      expect(tester.widget<CheckboxListTile>(fable).onChanged, isNull);
    },
  );

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
    // Budget rings are per connection, and the connection is a heading now.
    expect(find.text('Anthropic'), findsWidgets);

    await tester.scrollUntilVisible(
      find.text('Anthropic'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    // Defaults select available metrics; toggling Today off persists an explicit list.
    final todayTile =
        find.widgetWithText(CheckboxListTile, 'Today').hitTestable().first;
    // A full stack greys every unpicked row; the count is what tells that
    // apart from a fault, so it has to follow the selection.
    expect(find.textContaining('3 of 3 slots used'), findsOneWidget);
    await tester.tap(todayTile);
    await tester.pumpAndSettle();

    expect(store.value.selectedIds, isNotNull);
    expect(find.textContaining('2 of 3 slots used'), findsOneWidget);
  });

  testWidgets('a metric with nothing to show stays listed and refuses a tap', (
    tester,
  ) async {
    final source = DashboardSnapshot.fromJsonString(
      File('../../fixtures/snapshots/dashboard_today.json').readAsStringSync(),
    );
    final account =
        Map<String, Object?>.from(source.primaryAccount!.toJson())
          ..['accountId'] = 'anthropic-platform'
          ..['provider'] = 'claude'
          ..['connection'] = 'anthropic.platform'
          // No limit set for the month, so the ring has no percentage to draw.
          ..['month'] = {
            'period': 'month',
            'spent': {'minorUnits': 2500, 'currency': 'USD'},
            'limit': null,
            'remaining': null,
            'usedPercent': null,
            'projectedTotal': null,
            'status': 'ok',
          };
    final snapshot = DashboardSnapshot.fromJson({
      ...source.toJson(),
      'accounts': [account],
    });

    await tester.pumpWidget(
      WardPulseApp(
        repository: ValueDashboardRepository(snapshot),
        watchRingPreferenceStore: _MemoryWatchRingStore(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Watchface'));
    await tester.pumpAndSettle();

    final month = find.widgetWithText(CheckboxListTile, 'Month');
    await tester.scrollUntilVisible(
      month,
      200,
      scrollable: find.byType(Scrollable).first,
    );

    // Still under its connection, saying why it cannot be picked, and the box
    // refuses the tap — sunk rather than hidden.
    expect(month, findsOneWidget);
    expect(
      find.descendant(
        of: month,
        matching: find.byTooltip(
          'Set this period’s limit under Providers · Budget limits.',
        ),
      ),
      findsOneWidget,
    );
    expect(tester.widget<CheckboxListTile>(month).onChanged, isNull);
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
    // The picker is an outline now, so the preview sits below its headings.
    await tester.scrollUntilVisible(
      find.text('Next widget payload'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Next widget payload'), findsOneWidget);
    expect(find.textContaining('independent of Watchface'), findsOneWidget);
    // Its own copy of the count, on a screen with six slots instead of three.
    expect(find.textContaining('of 6 slots used'), findsOneWidget);

    // The connection is a heading here now, so its rows carry only the period.
    expect(find.text('Anthropic'), findsWidgets);
    final todayTile =
        find.widgetWithText(CheckboxListTile, 'Today').hitTestable().first;
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

    Finder platformButton(String tooltip) => find.descendant(
      of: find.ancestor(
        of: find.text('Platform reporting'),
        matching: find.byType(ProviderConnectionRow),
      ),
      matching: find.byWidgetPredicate(
        (widget) => widget is IconButton && widget.tooltip == tooltip,
      ),
    );

    // The limit comes first: a percentage is meaningless without one.
    await tester.scrollUntilVisible(
      platformButton('Budget limits'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(platformButton('Budget limits').hitTestable(), findsOneWidget);
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

  testWidgets(
    'owned window catalogue ignores watch selection and survives failed writes',
    (tester) async {
      final base = _alertTestSnapshot();
      final account = base.primaryAccount!.toJson();
      Map<String, dynamic> allowance(
        String id,
        String label, {
        AllowanceSource source = AllowanceSource.plan,
      }) {
        return AllowanceState(
          id: id,
          source: source,
          label: label,
          usedPercent: null,
          used: null,
          limit: null,
          remaining: null,
          windowMinutes: null,
          resetsAt: null,
          status: ProviderStatus.ok,
        ).toJson();
      }

      final snapshot = DashboardSnapshot.fromJson({
        ...base.toJson(),
        'accounts': [
          {
            ...account,
            'allowances': [
              for (var i = 0; i < 3; i++) allowance('dynamic-$i', 'Window $i'),
              allowance(
                'purchased',
                'Purchased pool',
                source: AllowanceSource.purchased,
              ),
            ],
          },
          {
            ...account,
            'accountId': 'reporting',
            'connection': 'openai.platform',
            'allowances': [allowance('sibling', 'Sibling window')],
          },
        ],
      });
      final repository = _PublicationRepository(snapshot);
      final store = _MemoryAlertThresholdStore();
      final ringStore =
          _MemoryWatchRingStore()
            ..value = const WatchRingPreferences(selectedIds: []);
      await tester.pumpWidget(
        WardPulseApp(
          repository: repository,
          alertThresholdStore: store,
          watchRingPreferenceStore: ringStore,
          applyAlertSettings: (current, _) => current,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Providers'));
      await tester.pumpAndSettle();
      Future<void> open() async {
        tester
            .state<ScrollableState>(find.byType(Scrollable).first)
            .position
            .jumpTo(0);
        await tester.pumpAndSettle();
        final action = find.descendant(
          of: find.widgetWithText(ProviderConnectionRow, 'Codex plan'),
          matching: find.byTooltip('Alert thresholds'),
        );
        await tester.scrollUntilVisible(
          action,
          300,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        await tester.tap(action);
        await tester.pumpAndSettle();
      }

      Finder editor() =>
          find.widgetWithText(AlertPercentThresholdEditor, 'Window 2');
      Future<void> custom17() async {
        final dropdown = find.descendant(
          of: editor(),
          matching: find.byType(DropdownButton<int?>),
        );
        await tester.ensureVisible(dropdown);
        await tester.pumpAndSettle();
        await tester.tap(dropdown);
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Custom % left').last);
        await tester.tap(find.text('Custom % left').last);
        await tester.pumpAndSettle();
        final field = find.descendant(
          of: editor(),
          matching: find.byType(TextFormField),
        );
        await tester.ensureVisible(field);
        await tester.enterText(field, '17');
      }

      await open();
      final dialog = tester.widget<ConnectionAlertsDialog>(
        find.byType(ConnectionAlertsDialog),
      );
      expect(dialog.planWindows.map((value) => value.id), [
        'dynamic-0',
        'dynamic-1',
        'dynamic-2',
      ]);
      expect(
        dialog.planWindows.every((value) => value.usedPercent == null),
        isTrue,
      );
      expect(find.text('Sibling window'), findsNothing);
      expect(find.text('Purchased pool'), findsNothing);
      await custom17();
      store.failNextWrite = true;
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(store.value.connections, isEmpty);
      expect(find.text('Could not update alert thresholds'), findsOneWidget);
      ScaffoldMessenger.of(
        tester.element(find.byType(ProvidersScreen)),
      ).hideCurrentSnackBar();
      await tester.pumpAndSettle();
      await open();
      expect(
        tester.widget<AlertPercentThresholdEditor>(editor()).usePlanDefault,
        isTrue,
      );
      await custom17();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(
        store.value
            .forConnection(ProviderConnections.codexPlan)
            .planWindows['dynamic-2']!
            .at,
        83,
      );
      expect(repository.loads, 1);

      // Reload persisted rules after an authoritative failure: no fabricated windows.
      repository.failLoad = true;
      await tester.tap(find.byTooltip('Refresh'));
      await tester.pumpAndSettle();
      await open();
      expect(find.text('Plan'), findsOneWidget);
      expect(find.text('Purchased'), findsOneWidget);
      expect(find.text('Plan window · dynamic-2'), findsOneWidget);
      expect(
        tester
            .widget<ConnectionAlertsDialog>(find.byType(ConnectionAlertsDialog))
            .planWindows,
        isEmpty,
      );
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      repository.failLoad = false;
      await tester.tap(find.byTooltip('Refresh'));
      await tester.pumpAndSettle();
      await open();
      final reopened = tester.widget<AlertPercentThresholdEditor>(editor());
      expect(reopened.value.at, 83);
      expect(reopened.usePlanDefault, isFalse);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

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

    final alerts = find.descendant(
      of: find.widgetWithText(ProviderConnectionRow, 'Codex plan'),
      matching: find.byTooltip('Alert thresholds'),
    );
    await tester.scrollUntilVisible(
      alerts,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(alerts);
    await tester.pumpAndSettle();
    expect(alerts.hitTestable(), findsOneWidget);
    await tester.tap(alerts);
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
    // Nothing deviates, so the app bar says nothing at all
    // (PHONE_DASHBOARD_DESIGN.md).
    expect(find.byType(Badge), findsNothing);
  });

  testWidgets('labels previous dashboard data as stale', (tester) async {
    final snapshot = DashboardSnapshot.fromJsonString(
      File('../../fixtures/snapshots/dashboard_today.json').readAsStringSync(),
    ).withStaleStatus(syncIssue: DashboardSyncIssue.authentication);

    await tester.pumpWidget(
      WardPulseApp(repository: ValueDashboardRepository(snapshot)),
    );
    await tester.pumpAndSettle();

    // Staleness is an account state, so no card carries a glyph for it: the
    // family answers with a count and the app bar with a way in — never the
    // same mark twice down the screen (PHONE_DASHBOARD_DESIGN.md).
    expect(find.byIcon(Icons.schedule), findsNothing);
    expect(find.byTooltip('Stale'), findsWidgets);
    expect(find.byTooltip('Go to stale'), findsOneWidget);
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
    final appBarMark = find.byTooltip('Go to stale');
    expect(
      tester
          .widget<Badge>(
            find.descendant(of: appBarMark, matching: find.byType(Badge)),
          )
          .backgroundColor,
      providerStatusChipColors(
        Theme.of(tester.element(appBarMark)).colorScheme,
        ProviderStatus.stale,
      ).fill,
    );
  });

  testWidgets('the app-bar mark opens the Dashboard at the first problem', (
    tester,
  ) async {
    final snapshot =
        DashboardSnapshot.fromJsonString(
          File(
            '../../fixtures/snapshots/dashboard_today.json',
          ).readAsStringSync(),
        ).withStaleStatus();

    await tester.pumpWidget(
      WardPulseApp(repository: ValueDashboardRepository(snapshot)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    expect(find.text('Refresh interval'), findsOneWidget);

    // A rollup earns its place by leading somewhere, so it works from any tab.
    await tester.tap(find.byTooltip('Go to stale'));
    await tester.pumpAndSettle();

    // Settings is gone and the flagged section is the thing on screen — the
    // dashboard title has scrolled off above it, which is the point.
    expect(find.text('Refresh interval'), findsNothing);
    expect(find.byTooltip('Stale'), findsWidgets);
    expect(find.text('Usage dashboard'), findsNothing);

    // The request is spent: coming back later is an ordinary visit, not a
    // repeat of a tap the reader made once.
    await tester.tap(find.text('Providers'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dashboard'));
    await tester.pumpAndSettle();
    expect(find.text('Usage dashboard'), findsOneWidget);
  });

  testWidgets(
    'saved-key check survives tab disposal and a failed Label write',
    (tester) async {
      final store = _MemoryCredentialStore()..failLabelWrite = true;
      final writeRelease = Completer<void>();
      store.pendingWrite = writeRelease.future;
      final response = Completer<String>();
      var requests = 0;
      final repository = _reportingRepository(store, (_) {
        requests++;
        return response.future;
      });
      await tester.pumpWidget(
        WardPulseApp(repository: repository, credentialStore: store),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Providers'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Organization reporting'));
      await tester.pumpAndSettle();
      await tester.enterText(_credentialValueField(), 'synthetic-key');
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Label (optional)'),
        'Synthetic label',
      );
      await tester.tap(find.text('Save'));
      await tester.pump();
      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();
      expect(requests, 0);
      writeRelease.complete();
      await tester.pumpAndSettle();
      expect(requests, 1);
      expect(find.text('Key saved. Could not update label.'), findsOneWidget);
      response.completeError(
        const ProviderReportingException(
          ProviderReportingFailure.authentication,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Providers'));
      await tester.pumpAndSettle();
      expect(find.text('Key rejected'), findsOneWidget);
      expect(
        find.textContaining('Anthropic · Organization reporting'),
        findsWidgets,
      );
      expect(find.text('synthetic-key'), findsNothing);
      expect(requests, 1);
    },
  );

  testWidgets(
    'manual and automatic refresh do not duplicate an active saved-key check',
    (tester) async {
      final store = _MemoryCredentialStore();
      final response = Completer<String>();
      final scheduler = _ManualProviderSyncScheduler();
      addTearDown(scheduler.dispose);
      var requests = 0;
      final repository = _reportingRepository(store, (_) {
        requests++;
        return response.future;
      });
      await tester.pumpWidget(
        WardPulseApp(
          repository: repository,
          credentialStore: store,
          syncScheduler: scheduler,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Providers'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Organization reporting'));
      await tester.pumpAndSettle();
      await tester.enterText(_credentialValueField(), 'synthetic-key');
      await tester.tap(find.text('Save'));
      await tester.pump();
      await tester.pump();
      expect(requests, 1);
      expect(find.text('Checking…'), findsOneWidget);
      expect(
        tester
            .widget<IconButton>(find.widgetWithIcon(IconButton, Icons.refresh))
            .onPressed,
        isNull,
      );
      final row = tester.widget<ProviderConnectionRow>(
        find.widgetWithText(ProviderConnectionRow, 'Organization reporting'),
      );
      expect(row.onTap, isNull);
      scheduler.tick();
      await tester.pump();
      expect(requests, 1);
      response.complete(DashboardSnapshot.empty().toJsonString());
      await tester.pumpAndSettle();
      expect(find.text('Connected'), findsOneWidget);
      expect(requests, 1);
    },
  );

  for (final previousSuccess in [false, true]) {
    testWidgets(
      'scheduled all-failed retries replace ${previousSuccess ? 'a later' : 'the initial'} Dashboard failure',
      (tester) async {
        final store = _MemoryCredentialStore();
        await store.writeSecret(
          ProviderConnections.anthropicPlatform,
          'synthetic-key',
        );
        final scheduler = _ManualProviderSyncScheduler();
        addTearDown(scheduler.dispose);
        ProviderReportingFailure? failure =
            previousSuccess ? null : ProviderReportingFailure.authentication;
        var requests = 0;
        final repository = _reportingRepository(store, (_) async {
          requests++;
          if (failure != null) throw ProviderReportingException(failure);
          return DashboardSnapshot.empty().toJsonString();
        });
        await tester.pumpWidget(
          WardPulseApp(
            repository: repository,
            credentialStore: store,
            syncScheduler: scheduler,
          ),
        );
        await tester.pumpAndSettle();
        if (previousSuccess) {
          repository.invalidate();
          failure = ProviderReportingFailure.authentication;
          await tester.tap(find.byTooltip('Refresh'));
          await tester.pumpAndSettle();
        }
        expect(
          find.textContaining(
            'Anthropic · Organization reporting: Key rejected',
          ),
          findsOneWidget,
        );
        await tester.tap(find.text('Providers'));
        await tester.pumpAndSettle();
        expect(find.text('Key rejected'), findsOneWidget);
        failure = ProviderReportingFailure.permissionDenied;
        scheduler.tick();
        await tester.pumpAndSettle();
        expect(find.text('Access denied'), findsOneWidget);
        await tester.tap(find.text('Dashboard'));
        await tester.pumpAndSettle();
        expect(
          find.textContaining(
            'Anthropic · Organization reporting: Access denied',
          ),
          findsOneWidget,
        );
        expect(find.textContaining('Key rejected'), findsNothing);
        expect(requests, previousSuccess ? 3 : 2);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('Remove retires Dashboard data even when local cleanup fails', (
    tester,
  ) async {
    final store = _MemoryCredentialStore()..failDeleteAfterRetirement = true;
    await store.writeSecret(
      ProviderConnections.anthropicPlatform,
      'synthetic-key',
    );
    await store.writeLabel(
      ProviderConnections.anthropicPlatform,
      'Synthetic label',
    );
    final json =
        DashboardSnapshot.fromJsonString(
          File(
            '../../fixtures/snapshots/dashboard_today.json',
          ).readAsStringSync(),
        ).toJson();
    final account = (json['accounts'] as List).single as Map;
    account['provider'] = 'claude';
    account['connection'] = ProviderConnections.anthropicPlatform.storageKey;
    final live = DashboardSnapshot.fromJson(json);
    var requests = 0;
    final repository = _reportingRepository(store, (_) async {
      requests++;
      return live.toJsonString();
    });
    final watch = _FakeWatchSyncService();
    await tester.pumpWidget(
      WardPulseApp(
        repository: repository,
        credentialStore: store,
        watchSyncService: watch,
      ),
    );
    await tester.pumpAndSettle();
    expect(watch.syncedSnapshots.last.accounts, isNotEmpty);
    await tester.tap(find.text('Providers'));
    await tester.pumpAndSettle();
    expect(find.text('Connected'), findsOneWidget);
    await tester.tap(find.text('Synthetic label'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();
    expect(
      find.text('Connection removed. Could not finish local cleanup.'),
      findsOneWidget,
    );
    expect(find.text('Connected'), findsNothing);
    expect(
      await store.readSecret(ProviderConnections.anthropicPlatform),
      isNull,
    );
    expect(watch.syncedSnapshots.last.accounts, isEmpty);
    await tester.tap(find.text('Dashboard'));
    await tester.pumpAndSettle();
    expect(find.text('Connect a provider'), findsOneWidget);
    expect(requests, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('open Providers follows automatic and manual reporting results', (
    tester,
  ) async {
    final store = _MemoryCredentialStore();
    await store.writeSecret(
      ProviderConnections.anthropicPlatform,
      'synthetic-key',
    );
    final scheduler = _ManualProviderSyncScheduler();
    addTearDown(scheduler.dispose);
    ProviderReportingFailure? failure;
    var requests = 0;
    final repository = _reportingRepository(store, (_) async {
      requests++;
      if (failure != null) throw ProviderReportingException(failure);
      return DashboardSnapshot.empty().toJsonString();
    });
    await tester.pumpWidget(
      WardPulseApp(
        repository: repository,
        credentialStore: store,
        syncScheduler: scheduler,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Providers'));
    await tester.pumpAndSettle();
    expect(find.text('Connected'), findsOneWidget);
    failure = ProviderReportingFailure.permissionDenied;
    scheduler.tick();
    await tester.pumpAndSettle();
    expect(find.text('Access denied'), findsOneWidget);
    failure = ProviderReportingFailure.unavailable;
    await tester.tap(find.byTooltip('Refresh'));
    await tester.pumpAndSettle();
    expect(find.text('Could not check'), findsOneWidget);
    expect(find.text('Key rejected'), findsNothing);
    expect(requests, 3);
  });

  testWidgets(
    'refresh retires externally removed outcomes and keeps current sibling feedback',
    (tester) async {
      final store = _MemoryCredentialStore();
      const rejected = ProviderConnections.anthropicPlatform;
      const sibling = ProviderConnections.cursorPlatform;
      await store.writeSecret(rejected, 'synthetic-rejected');
      await store.writeSecret(sibling, 'synthetic-sibling');
      final live = _PublicationRepository(
        DashboardSnapshot.fromJsonString(
          File(
            '../../fixtures/snapshots/dashboard_today.json',
          ).readAsStringSync(),
        ),
      );
      final scheduler = _ManualProviderSyncScheduler();
      addTearDown(scheduler.dispose);
      var rejectedRequests = 0;
      var siblingRequests = 0;
      final repository = _reportingRepository(
        store,
        (_) async {
          rejectedRequests++;
          throw const ProviderReportingException(
            ProviderReportingFailure.authentication,
          );
        },
        fallback: _reportingRepository(
          store,
          (_) async {
            siblingRequests++;
            throw const ProviderReportingException(
              ProviderReportingFailure.permissionDenied,
            );
          },
          connection: sibling,
          fallback: live,
        ),
      );
      await tester.pumpWidget(
        WardPulseApp(
          repository: repository,
          credentialStore: store,
          syncScheduler: scheduler,
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Anthropic · Organization reporting: Key rejected'),
        findsOneWidget,
      );
      expect(find.text('Edit key'), findsNWidgets(2));

      // Another lifecycle owner removes the key without the app's callback.
      await store.deleteSecret(rejected);
      scheduler.tick();
      await tester.pumpAndSettle();
      expect(find.textContaining('Key rejected'), findsNothing);
      expect(
        find.textContaining('Cursor · Team Admin API: Access denied'),
        findsOneWidget,
      );
      expect(find.text('Edit key'), findsOneWidget);
      expect(find.text('Connect a provider'), findsNothing);
      expect(rejectedRequests, 1);
      expect(siblingRequests, 2);
      await tester.tap(find.text('Providers'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Organization reporting'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(
        find.descendant(
          of: find.widgetWithText(
            ProviderConnectionRow,
            'Organization reporting',
          ),
          matching: find.text('Not connected'),
        ),
        findsOneWidget,
      );

      await store.deleteSecret(sibling);
      live.snapshot = DashboardSnapshot.empty();
      await tester.tap(find.text('Dashboard'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Refresh'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Key rejected'), findsNothing);
      expect(find.textContaining('Access denied'), findsNothing);
      expect(find.text('Edit key'), findsNothing);
      expect(find.text('Connect a provider'), findsOneWidget);
      expect(rejectedRequests, 1);
      expect(siblingRequests, 2);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('failed key storage never checks or blames the provider', (
    tester,
  ) async {
    final store = _MemoryCredentialStore()..failKeyWrite = true;
    var requests = 0;
    final repository = _reportingRepository(store, (_) async {
      requests++;
      return DashboardSnapshot.empty().toJsonString();
    });
    await tester.pumpWidget(
      WardPulseApp(repository: repository, credentialStore: store),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Providers'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Organization reporting'));
    await tester.pumpAndSettle();
    await tester.enterText(_credentialValueField(), 'synthetic-key');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Could not update credential'), findsOneWidget);
    expect(find.text('Key rejected'), findsNothing);
    expect(
      await store.readSecret(ProviderConnections.anthropicPlatform),
      isNull,
    );
    expect(requests, 0);
  });

  testWidgets(
    'initial all-failed feedback repairs the exact row despite labels and ordering',
    (tester) async {
      final store = _MemoryCredentialStore();
      const ids = [
        ProviderConnections.cursorPlatform,
        ProviderConnections.openAiPlatform,
        ProviderConnections.anthropicPlatform,
      ];
      for (final id in ids) {
        await store.writeSecret(id, 'synthetic-key');
        await store.writeLabel(id, 'Shared label');
      }
      final outcomes = [
        for (final id in ids)
          ConnectionReportingOutcome(
            connection: id,
            category: ReportingOutcomeCategory.authenticationRejected,
            source: ReportingOutcomeSource.live,
            credentialVersion: store.version(id),
            freshness: ReportingOutcomeFreshness.current,
          ),
      ];
      await tester.pumpWidget(
        WardPulseApp(
          repository: _OutcomeFailureRepository(outcomes),
          credentialStore: store,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Connect a provider'), findsNothing);
      for (final outcome in outcomes) {
        expect(
          find.textContaining('${outcome.connectionLabel}: Key rejected'),
          findsOneWidget,
        );
      }
      final repair = find.descendant(
        of:
            find
                .ancestor(
                  of: find.textContaining(
                    'Anthropic · Organization reporting: Key rejected',
                  ),
                  matching: find.byType(Column),
                )
                .first,
        matching: find.widgetWithText(TextButton, 'Edit key'),
      );
      await tester.ensureVisible(repair);
      await tester.pumpAndSettle();
      expect(repair.hitTestable(), findsOneWidget);
      await tester.tap(repair);
      await tester.pumpAndSettle();
      expect(
        find.widgetWithText(AlertDialog, 'Anthropic · Organization reporting'),
        findsOneWidget,
      );
      expect(
        tester.widget<TextFormField>(_credentialValueField()).controller!.text,
        isEmpty,
      );
      expect(find.text('Remove'), findsOneWidget);
    },
  );

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
    await tester.enterText(_credentialValueField(), 'secret-admin-key');
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
    await tester.scrollUntilVisible(
      find.text('Not verified'),
      -300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Not verified'), findsOneWidget);
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
    expect(find.text('Codex plan'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('Platform reporting'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Platform reporting'));
    await tester.pumpAndSettle();
    await tester.enterText(_credentialValueField(), 'secret-admin-key');
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Label (optional)'),
      'Work org key',
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(credentialStore.openAiSecret, 'secret-admin-key');
    expect(credentialStore.openAiLabel, 'Work org key');
    await tester.scrollUntilVisible(
      find.text('Work org key'),
      -300,
      scrollable: find.byType(Scrollable).first,
    );
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
    await tester.ensureVisible(
      find.widgetWithText(ProviderConnectionRow, 'Work org key'),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Work org key'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();

    expect(credentialStore.openAiSecret, isNull);
    expect(credentialStore.openAiLabel, isNull);
    await tester.scrollUntilVisible(
      find.text('Platform reporting'),
      300,
      scrollable: providersList,
    );
    await tester.pumpAndSettle();
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
    expect(find.text('Not verified'), findsOneWidget);
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
        'about every 15 minutes in the background (Android may delay updates)',
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
    expect(
      find.textContaining('about every 20 minutes in the background'),
      findsOneWidget,
    );

    final sixtyIndex = PollCadence.refreshIntervalStopIndex(60).toDouble();
    tester.widget<Slider>(slider).onChanged!(sixtyIndex);
    await tester.pump();
    expect(preferences.value.minutes, 20);
    expect(
      find.textContaining('Every 60 minutes while WardPulse is open'),
      findsOneWidget,
    );
    expect(
      find.textContaining('about every 60 minutes in the background'),
      findsOneWidget,
    );
    tester.widget<Slider>(slider).onChangeEnd!(sixtyIndex);
    await tester.pumpAndSettle();
    expect(preferences.value.minutes, 60);
    expect(
      find.textContaining('about every 60 minutes in the background'),
      findsOneWidget,
    );

    final fiveIndex = PollCadence.refreshIntervalStopIndex(5).toDouble();
    tester.widget<Slider>(slider).onChanged!(fiveIndex);
    await tester.pump();
    expect(preferences.value.minutes, 60);
    expect(
      find.textContaining('Every 5 minutes while WardPulse is open'),
      findsOneWidget,
    );
    expect(
      find.textContaining('about every 15 minutes in the background'),
      findsOneWidget,
    );
    tester.widget<Slider>(slider).onChangeEnd!(fiveIndex);
    await tester.pumpAndSettle();
    expect(preferences.value.minutes, 5);
    expect(
      find.textContaining('about every 15 minutes in the background'),
      findsOneWidget,
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
      matching: find.byType(ProviderConnectionRow),
    );
    final adminTile = find.ancestor(
      of: find.text('Team Admin API'),
      matching: find.byType(ProviderConnectionRow),
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
    // Which family sits where is the tab's own business
    // (providers_screen_test.dart); this test only asks that the catalog
    // opened, so it scrolls to the row instead of assuming a position.
    await tester.scrollUntilVisible(
      find.text('Codex plan'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Codex plan'), findsOneWidget);
  });

  for (final failure in ['cache clear', 'preference write']) {
    for (final owned in [true, false]) {
      testWidgets('mock $failure failure retains only owned data ($owned)', (
        tester,
      ) async {
        final source = _alertTestSnapshot();
        final repository = _PublicationRepository(source);
        final preferences = _MemoryDebugDataPreferenceStore();
        final watch = _FakeWatchSyncService();
        final phoneWidget = _FakePhoneWidgetSyncService();
        final inputs = <DashboardSnapshot>[];
        await tester.pumpWidget(
          WardPulseApp(
            repository: repository,
            debugDataAvailable: true,
            debugDataPreferenceStore: preferences,
            watchSyncService: watch,
            phoneWidgetSyncService: phoneWidget,
            applyAlertSettings: (snapshot, _) {
              inputs.add(snapshot);
              return snapshot;
            },
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
        expect(toggle.hitTestable(), findsOneWidget);
        repository.failClear = failure == 'cache clear';
        preferences.failWrite = failure == 'preference write';
        repository.current = owned;
        await tester.tap(toggle);
        await tester.pumpAndSettle();
        expect(find.text('Could not update mock data setting'), findsOneWidget);
        expect(tester.widget<SwitchListTile>(toggle).value, isFalse);
        expect(preferences.value, isFalse);
        expect(preferences.writes, failure == 'cache clear' ? 0 : 1);
        expect(repository.loads, 1);

        await tester.tap(find.text('Providers'));
        await tester.pumpAndSettle();
        await tester
            .widget<ProvidersScreen>(find.byType(ProvidersScreen))
            .onAlertThresholdsChanged(
              (current) => current.withConnection(
                ProviderConnections.codexPlan,
                const ConnectionAlertThresholds(
                  plan: AlertPercentThreshold(at: 70),
                ),
              ),
            );
        await tester.pumpAndSettle();
        expect(inputs, owned ? [source, source] : [source]);
        expect(watch.syncedSnapshots, owned ? [source, source] : [source]);
        expect(
          phoneWidget.syncedSnapshots,
          owned ? [source, source] : [source],
        );
        await tester.tap(find.text('Dashboard'));
        await tester.pumpAndSettle();
        if (owned) {
          expect(
            tester
                .widget<DashboardScreen>(find.byType(DashboardScreen))
                .snapshot
                .toJson(),
            source.toJson(),
          );
        } else {
          expect(find.byType(DashboardScreen), findsNothing);
        }
        expect(repository.loads, 1);
        expect(tester.takeException(), isNull);
      });
    }
  }

  for (final trigger in ['scheduled', 'foreground']) {
    testWidgets('mock mode write survives an overlapping $trigger refresh', (
      tester,
    ) async {
      final live = _PublicationRepository(_alertTestSnapshot());
      final mock = _PublicationRepository(
        _alertTestSnapshot(windowLabel: 'Mock data'),
      );
      final preferences = _MemoryDebugDataPreferenceStore();
      final scheduler = _ManualProviderSyncScheduler();
      addTearDown(scheduler.dispose);
      final watch = _FakeWatchSyncService();
      final phoneWidget = _FakePhoneWidgetSyncService();
      await tester.pumpWidget(
        WardPulseApp(
          repository: DebugDashboardRepository(
            live: live,
            mock: mock,
            preferences: preferences,
          ),
          debugDataAvailable: true,
          debugDataPreferenceStore: preferences,
          syncScheduler: scheduler,
          watchSyncService: watch,
          phoneWidgetSyncService: phoneWidget,
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
      expect(toggle.hitTestable(), findsOneWidget);
      final release = Completer<void>();
      preferences.pendingWrite = release.future;
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(preferences.writes, 1);
      expect(preferences.value, isFalse);
      if (trigger == 'scheduled') {
        scheduler.tick();
      } else {
        await tester.tap(find.byTooltip('Refresh'));
      }
      await tester.pumpAndSettle();
      release.complete();
      await tester.pumpAndSettle();
      expect(preferences.value, isTrue);
      expect(tester.widget<SwitchListTile>(toggle).value, isTrue);
      expect(watch.mockModes.last, isTrue);
      await tester.tap(find.text('Dashboard'));
      await tester.pumpAndSettle();
      final displayed =
          tester.widget<DashboardScreen>(find.byType(DashboardScreen)).snapshot;
      expect(displayed.accounts.first.allowances.single.label, 'Mock data');
      expect(displayed.toJson(), mock.snapshot.toJson());
      expect(displayed.toJson(), watch.syncedSnapshots.last.toJson());
      expect(displayed.toJson(), phoneWidget.syncedSnapshots.last.toJson());
      expect(live.loads, trigger == 'scheduled' ? 2 : 1);
      expect(mock.loads, 1);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'demo data leaves nothing for a recovery to be measured against',
    (tester) async {
      final source = DashboardSnapshot.fromJsonString(
        File(
          '../../fixtures/snapshots/dashboard_today.json',
        ).readAsStringSync(),
      );
      final preferences = _MemoryDebugDataPreferenceStore();
      await preferences.writeMockDataEnabled(true);
      final watchlist =
          _MemoryRecoveryWatchlistStore()
            ..keys = const [(accountId: 'codex-demo', allowanceId: 'weekly')];

      await tester.pumpWidget(
        WardPulseApp(
          repository: DebugDashboardRepository(
            live: ValueDashboardRepository(source),
            mock: ValueDashboardRepository(source),
            preferences: preferences,
          ),
          debugDataAvailable: true,
          debugDataPreferenceStore: preferences,
          recoveryWatchlistStore: watchlist,
        ),
      );
      await tester.pumpAndSettle();

      // Invented windows must not survive the demo: kept, they would make the
      // first live poll afterwards look like a recovery.
      expect(watchlist.keys, isEmpty);
    },
  );

  testWidgets('the recovery switch is on, and says when Android blocks it', (
    tester,
  ) async {
    final store = _MemoryRecoveryNotificationStore();
    final notifier = _BlockedRecoveryNotifier();

    await tester.pumpWidget(
      WardPulseApp(
        repository: ValueDashboardRepository(
          DashboardSnapshot.empty(generatedAt: DateTime.utc(2026, 8, 17)),
        ),
        recoveryNotificationStore: store,
        recoveryNotifier: notifier,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();

    final toggle = find.widgetWithText(SwitchListTile, 'Plan recovery');
    await tester.scrollUntilVisible(
      toggle,
      300,
      scrollable: find.byType(Scrollable).first,
    );

    // This isolated switch fixture has no startup coordinator.
    expect(tester.widget<SwitchListTile>(toggle).value, isTrue);

    // Off and on again, so the ask runs with Android refusing it.
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(store.enabled, isFalse);
    await tester.tap(toggle);
    await tester.pumpAndSettle();

    expect(store.enabled, isTrue);
    expect(notifier.asked, 1);
    // The reader said yes and Android said no; leaving the switch on without a
    // word would promise an interruption that cannot arrive.
    expect(
      find.text('Android is blocking WardPulse notifications'),
      findsOneWidget,
    );
  });

  testWidgets(
    'alert delivery choice persists and explicit Off to On reports denial',
    (tester) async {
      final storage = FakeSecureStorage();
      final store = SecureAlertNotificationPreferenceStore(storage: storage);
      final recovery = _MemoryRecoveryNotificationStore()..enabled = false;
      final notifier = _FakeAlertNotifier();
      Widget app() => WardPulseApp(
        repository: ValueDashboardRepository(DashboardSnapshot.empty()),
        alertNotificationStore: store,
        alertNotifier: notifier,
        recoveryNotificationStore: recovery,
      );
      Future<void> openSettings() async {
        await tester.tap(find.text('Settings'));
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.widgetWithText(SwitchListTile, 'Alert notifications'),
          300,
          scrollable: find.byType(Scrollable).first,
        );
      }

      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      await openSettings();
      final toggle = find.widgetWithText(SwitchListTile, 'Alert notifications');
      expect(tester.widget<SwitchListTile>(toggle).value, isTrue);
      expect(notifier.asked, 0);
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(await store.read(), isFalse);
      storage.failRead = true;
      final refresh =
          tester
              .widget<SettingsScreen>(find.byType(SettingsScreen))
              .onRefresh();
      await tester.pumpAndSettle();
      await refresh;
      expect(tester.widget<SwitchListTile>(toggle).value, isFalse);
      storage.failRead = false;
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      await openSettings();
      expect(tester.widget<SwitchListTile>(toggle).value, isFalse);
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(await store.read(), isTrue);
      expect(recovery.enabled, isFalse);
      expect(notifier.asked, 1);
      expect(
        find.text('Android is blocking WardPulse notifications'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'scheduled acceptance runs recovery and alerts independently of a failed preference',
    (tester) async {
      const key = AlertConditionKey(
        provider: 'claude',
        accountId: 'account-a',
        connection: 'anthropic.plan',
        target: AllowanceAlertTarget(
          source: AllowanceSource.plan,
          id: 'weekly',
        ),
      );
      DashboardSnapshot source(AlertCondition condition) =>
          DashboardSnapshot.fromJson({
            ...DashboardSnapshot.empty().toJson(),
            'alertConditions': [condition.toJson()],
          });
      final repository = _PublicationRepository(
        source(const AlertCondition.clear(key: key)),
      );
      final recovery = _MemoryRecoveryWatchlistStore();
      final preference = _MemoryRecoveryNotificationStore()..failRead = true;
      final notifier = _FakeAlertNotifier();
      final watch = _FakeWatchSyncService();
      final widget = _FakePhoneWidgetSyncService();
      final scheduler = _ManualProviderSyncScheduler();
      addTearDown(scheduler.dispose);
      await tester.pumpWidget(
        WardPulseApp(
          repository: repository,
          applyAlertSettings: (snapshot, _) => snapshot,
          syncScheduler: scheduler,
          watchSyncService: watch,
          phoneWidgetSyncService: widget,
          recoveryWatchlistStore: recovery,
          recoveryNotificationStore: preference,
          alertConditionStore: _MemoryAlertConditions(),
          alertNotifier: notifier,
        ),
      );
      await tester.pumpAndSettle();
      expect(recovery.reads, 1);
      repository.snapshot = source(
        const AlertCondition.crossed(
          key: key,
          alert: AlertSummary(
            severity: 'warning',
            message: 'Configured threshold',
          ),
        ),
      );
      scheduler.tick();
      await tester.pumpAndSettle();
      expect(recovery.reads, 2);
      expect(notifier.posts, [key]);
      expect(watch.syncedSnapshots, hasLength(2));
      expect(widget.syncedSnapshots, hasLength(2));
    },
  );

  testWidgets('a threshold edit retains the consumed notification identity', (
    tester,
  ) async {
    final source = _alertTestSnapshot(usedPercent: 90);
    final account = source.accounts.first;
    final window = account.allowances.single;
    final key = AlertConditionKey(
      provider: account.provider,
      accountId: account.accountId,
      connection: account.connection!,
      target: AllowanceAlertTarget(source: window.source, id: window.id),
    );
    final rules = _MemoryAlertThresholdStore();
    rules.value = rules.value.withConnection(
      ProviderConnections.codexPlan,
      const ConnectionAlertThresholds(plan: AlertPercentThreshold(at: 80)),
    );
    final notifier = _FakeAlertNotifier();
    final markers = _MemoryAlertConditions();
    final scheduler = _ManualProviderSyncScheduler();
    addTearDown(scheduler.dispose);
    try {
      await tester.pumpWidget(
        WardPulseApp(
          repository: ValueDashboardRepository(source),
          alertThresholdStore: rules,
          alertConditionStore: markers,
          alertNotifier: notifier,
          syncScheduler: scheduler,
          watchSyncService: _FakeWatchSyncService(),
          phoneWidgetSyncService: _FakePhoneWidgetSyncService(),
          readExhaustedWindows: (_) => const [],
          readPlanRecoveries: (_, _) => const [],
          applyAlertSettings: (snapshot, settings) {
            final at =
                settings.forConnection(ProviderConnections.codexPlan).plan.at;
            final used = snapshot.accounts.first.allowances.single.usedPercent!;
            final crossed = AlertCondition.crossed(
              key: key,
              alert: const AlertSummary(
                severity: 'warning',
                message: 'Configured window',
              ),
            );
            return DashboardSnapshot.fromJson({
              ...snapshot.toJson(),
              'alertConditions': [
                if (at != null)
                  (used >= at ? crossed : AlertCondition.clear(key: key))
                      .toJson(),
              ],
            });
          },
        ),
      );
      await tester.pumpAndSettle();
      expect(notifier.posts, [key]);
      expect(notifier.bodies, ['Reached your alert threshold: 20% left.']);
      expect(markers.values[key], isTrue);

      await tester.tap(find.text('Providers'));
      await tester.pumpAndSettle();
      await tester
          .widget<ProvidersScreen>(find.byType(ProvidersScreen))
          .onAlertThresholdsChanged(
            (current) => current.withConnection(
              ProviderConnections.codexPlan,
              const ConnectionAlertThresholds(
                plan: AlertPercentThreshold(at: 85),
              ),
            ),
          );
      await tester.pumpAndSettle();
      expect(
        rules.value.forConnection(ProviderConnections.codexPlan).plan.at,
        85,
      );
      expect(notifier.posts, [key]);
      expect(notifier.bodies, ['Reached your alert threshold: 20% left.']);
      expect(markers.values, {key: true});
    } finally {
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    }
  });

  testWidgets(
    'a read begun during a delivery toggle cannot replace the saved Off',
    (tester) async {
      final store = _DelayedAlertPreferenceStore();
      await tester.pumpWidget(
        WardPulseApp(
          repository: ValueDashboardRepository(DashboardSnapshot.empty()),
          alertNotificationStore: store,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();
      final settings = tester.widget<SettingsScreen>(
        find.byType(SettingsScreen),
      );
      store
        ..holdRead = true
        ..holdWrite = true;
      final saving = settings.onAlertNotificationsChanged(false);
      await store.writeStarted.future;
      final refreshing = settings.onRefresh();
      await store.readStarted.future;
      store.releaseWrite.complete();
      await saving;
      store.releaseRead.complete();
      await refreshing;
      await tester.pumpAndSettle();
      final toggle = find.widgetWithText(SwitchListTile, 'Alert notifications');
      await tester.scrollUntilVisible(
        toggle,
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(store.enabled, isFalse);
      expect(tester.widget<SwitchListTile>(toggle).value, isFalse);
    },
  );

  testWidgets(
    'saved Alert Off suppresses an older On read without replaying the crossing',
    (tester) async {
      const key = AlertConditionKey(
        provider: 'claude',
        accountId: 'account-a',
        connection: 'anthropic.plan',
        target: AllowanceAlertTarget(
          source: AllowanceSource.plan,
          id: 'weekly',
        ),
      );
      DashboardSnapshot source(AlertCondition condition) =>
          DashboardSnapshot.fromJson({
            ...DashboardSnapshot.empty().toJson(),
            'alertConditions': [condition.toJson()],
          });
      final clear = source(const AlertCondition.clear(key: key));
      final crossed = source(
        const AlertCondition.crossed(
          key: key,
          alert: AlertSummary(
            severity: 'warning',
            message: 'Configured threshold',
          ),
        ),
      );
      final repository = _PublicationRepository(clear);
      final preference = _DelayedAlertPreferenceStore();
      final markers = _MemoryAlertConditions();
      final notifier = _FakeAlertNotifier();
      final scheduler = _ManualProviderSyncScheduler();
      addTearDown(scheduler.dispose);
      try {
        await tester.pumpWidget(
          WardPulseApp(
            repository: repository,
            applyAlertSettings: (snapshot, _) => snapshot,
            alertNotificationStore: preference,
            alertConditionStore: markers,
            alertNotifier: notifier,
            watchSyncService: _FakeWatchSyncService(),
            syncScheduler: scheduler,
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Settings'));
        await tester.pumpAndSettle();
        final settings = tester.widget<SettingsScreen>(
          find.byType(SettingsScreen),
        );
        repository.snapshot = crossed;
        preference.holdRead = true;
        scheduler.tick();
        await tester.pump();
        await preference.readStarted.future;
        expect(markers.values[key], isTrue);
        await settings.onAlertNotificationsChanged(false);
        expect(preference.enabled, isFalse);
        preference.holdRead = false;
        preference.releaseRead.complete();
        await tester.pumpAndSettle();
        expect(notifier.posts, isEmpty);
        expect(markers.values[key], isTrue);

        repository.snapshot = clear;
        scheduler.tick();
        await tester.pumpAndSettle();
        expect(markers.values[key], isFalse);
        repository.snapshot = crossed;
        scheduler.tick();
        await tester.pumpAndSettle();
        expect(markers.values[key], isTrue);
        expect(notifier.posts, isEmpty);

        await settings.onAlertNotificationsChanged(true);
        scheduler.tick();
        await tester.pumpAndSettle();
        expect(notifier.posts, isEmpty);
        expect(markers.values[key], isTrue);
        repository.snapshot = clear;
        scheduler.tick();
        await tester.pumpAndSettle();
        expect(markers.values[key], isFalse);
        repository.snapshot = crossed;
        scheduler.tick();
        await tester.pumpAndSettle();
        expect(notifier.posts, [key]);
      } finally {
        preference.holdRead = false;
        if (!preference.releaseRead.isCompleted)
          preference.releaseRead.complete();
        try {
          await tester.pumpWidget(const SizedBox());
        } finally {
          await tester.pumpAndSettle();
        }
      }
    },
  );

  testWidgets(
    'saved Recovery Off during validation preserves tracking and wake work',
    (tester) async {
      const window = (accountId: 'account-a', allowanceId: 'weekly');
      final repository = _PublicationRepository(DashboardSnapshot.empty());
      final preference = _MemoryRecoveryNotificationStore();
      final watchlist = _MemoryRecoveryWatchlistStore();
      final notifier = _BlockedRecoveryNotifier();
      final wake = _RecordingRecoveryWake();
      final scheduler = _ManualProviderSyncScheduler();
      addTearDown(scheduler.dispose);
      var spent = true;
      try {
        await tester.pumpWidget(
          WardPulseApp(
            repository: repository,
            recoveryNotificationStore: preference,
            recoveryWatchlistStore: watchlist,
            recoveryNotifier: notifier,
            recoveryWake: wake,
            watchSyncService: _FakeWatchSyncService(),
            readExhaustedWindows: (_) => spent ? const [window] : const [],
            readPlanRecoveries:
                (_, remembered) => [
                  for (final key in remembered)
                    (
                      accountId: key.accountId,
                      provider: 'claude',
                      allowanceId: key.allowanceId,
                      label: 'Weekly plan',
                      resetsAt: null,
                    ),
                ],
            syncScheduler: scheduler,
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Settings'));
        await tester.pumpAndSettle();
        final settings = tester.widget<SettingsScreen>(
          find.byType(SettingsScreen),
        );
        expect(watchlist.keys, const [window]);
        expect(wake.cancelled, 1);
        spent = false;
        preference.beforeRead = () {
          preference.beforeRead = null;
          repository.delayNextValidation = true;
        };
        scheduler.tick();
        await tester.pump();
        await repository.validationEntered.future;
        await settings.onRecoveryNotificationsChanged(false);
        expect(preference.enabled, isFalse);
        expect(watchlist.keys, const [window]);
        repository.validation.complete(true);
        await tester.pumpAndSettle();
        expect(notifier.reported, isEmpty);
        expect(watchlist.reads, 2);
        expect(watchlist.keys, isEmpty);
        expect(wake.cancelled, 2);
        expect(wake.booked, isEmpty);
      } finally {
        if (!repository.validation.isCompleted)
          repository.validation.complete(true);
        try {
          await tester.pumpWidget(const SizedBox());
        } finally {
          await tester.pumpAndSettle();
        }
      }
    },
  );

  testWidgets(
    'scheduled delivery retains the rules used for its accepted observations',
    (tester) async {
      const key = AlertConditionKey(
        provider: 'claude',
        accountId: 'account-a',
        connection: 'anthropic.plan',
        target: AllowanceAlertTarget(
          source: AllowanceSource.plan,
          id: 'weekly',
        ),
      );
      DashboardSnapshot source(AlertCondition condition) =>
          DashboardSnapshot.fromJson({
            ...DashboardSnapshot.empty().toJson(),
            'alertConditions': [condition.toJson()],
          });
      final clear = source(const AlertCondition.clear(key: key));
      final repository = _PublicationRepository(clear);
      final rules =
          _MemoryAlertThresholdStore()
            ..value = const AlertThresholdPreferences(
              connections: {
                'anthropic.plan': ConnectionAlertThresholds(
                  plan: AlertPercentThreshold(at: 80),
                ),
              },
            );
      final notifier = _FakeAlertNotifier();
      final markers = _MemoryAlertConditions();
      final watch = _HoldingWatchSyncService();
      final scheduler = _ManualProviderSyncScheduler();
      addTearDown(scheduler.dispose);
      await tester.pumpWidget(
        WardPulseApp(
          repository: repository,
          applyAlertSettings: (snapshot, _) => snapshot,
          alertThresholdStore: rules,
          alertConditionStore: markers,
          alertNotifier: notifier,
          watchSyncService: watch,
          syncScheduler: scheduler,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();
      repository.snapshot = source(
        const AlertCondition.crossed(
          key: key,
          alert: AlertSummary(
            severity: 'warning',
            message: 'Configured threshold',
          ),
        ),
      );
      watch.hold = true;
      scheduler.tick();
      await tester.pump();
      await watch.entered.future;
      final nextLoad = Completer<DashboardSnapshot>();
      repository.response = nextLoad.future;
      rules.value = const AlertThresholdPreferences();
      final refreshing =
          tester
              .widget<SettingsScreen>(find.byType(SettingsScreen))
              .onRefresh();
      await tester.pump();
      final loadsBeforeRelease = repository.loads;
      watch.release.complete();
      await tester.pump();
      final consumedBeforeNextLoad = markers.values[key];
      watch.hold = false;
      nextLoad.complete(clear);
      await refreshing;
      await tester.pumpAndSettle();
      expect(loadsBeforeRelease, 3);
      expect(consumedBeforeNextLoad, isFalse);
      expect(notifier.posts, isEmpty);
    },
  );

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

Future<void> _notificationLifecycle(
  WidgetTester tester,
  AppLifecycleState state,
) async {
  await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
    SystemChannels.lifecycle.name,
    SystemChannels.lifecycle.codec.encodeMessage(
      'AppLifecycleState.${state.name}',
    ),
    (_) {},
  );
}

Widget _notificationApp(
  PhoneNotificationCoordinator coordinator, {
  DashboardRepository? repository,
  AlertNotificationPreferenceStore? alerts,
  RecoveryNotificationPreferenceStore? recoveries,
}) => WardPulseApp(
  repository: repository ?? ValueDashboardRepository(DashboardSnapshot.empty()),
  notificationCoordinator: coordinator,
  alertNotificationStore:
      alerts ?? const DefaultAlertNotificationPreferenceStore(),
  recoveryNotificationStore:
      recoveries ?? const DefaultRecoveryNotificationPreferenceStore(),
  scheduleHeadlessSync: (_) async {},
);

final class _NotificationChoice
    implements
        AlertNotificationPreferenceStore,
        RecoveryNotificationPreferenceStore {
  bool enabled = true;
  int writes = 0;
  bool failRead = false;
  Future<void>? hold;
  @override
  Future<bool> read() async {
    final value = enabled;
    await hold;
    if (failRead) throw StateError('Delivery choice unavailable.');
    return value;
  }

  @override
  Future<void> write(bool value) async {
    writes++;
    enabled = value;
  }
}

Finder _credentialValueField() => find.ancestor(
  of: find.byWidgetPredicate(
    (widget) =>
        widget is TextField &&
        (widget.decoration?.labelText?.startsWith('Value') ?? false),
  ),
  matching: find.byType(TextFormField),
);

/// Mock fixture as a real connection: mock accounts hold no metric slots.
DashboardSnapshot _asConnection(DashboardSnapshot snapshot) {
  final account =
      Map<String, Object?>.from(snapshot.primaryAccount!.toJson())
        ..['accountId'] = 'anthropic-platform'
        ..['provider'] = 'claude'
        ..['connection'] = ProviderConnections.anthropicPlatform.storageKey;
  return DashboardSnapshot.fromJson({
    ...snapshot.toJson(),
    'accounts': [account],
  });
}

DashboardSnapshot _alertTestSnapshot({
  bool includeWindow = true,
  String windowLabel = 'Window A',
  double usedPercent = 75,
}) {
  final empty = DashboardSnapshot.empty(
    generatedAt: DateTime.utc(2026, 10, 26),
  );
  final budget = {
    ...empty.todayTotal.toJson(),
    'spent': {'minorUnits': 2501, 'currency': 'USD'},
    'limit': {'minorUnits': 2500, 'currency': 'USD'},
    'remaining': {'minorUnits': -1, 'currency': 'USD'},
    'usedPercent': 100.04,
    'status': 'warning',
  };
  final account = {
    'accountId': 'plan-a',
    'provider': 'codex',
    'connection': ProviderConnections.codexPlan.storageKey,
    'status': 'ok',
    'today': budget,
    'week': empty.weekTotal.toJson(),
    'month': empty.monthTotal.toJson(),
    'credits': <Object>[],
    'allowances': [
      if (includeWindow)
        {
          'id': 'window-a',
          'source': 'plan',
          'label': windowLabel,
          'usedPercent': usedPercent,
          'status': 'ok',
        },
    ],
    'buckets': <Object>[],
    'modelBreakdown': <Object>[],
  };
  return DashboardSnapshot.fromJson({
        ...empty.toJson(),
        'overallStatus': 'authRequired',
        'todayTotal': budget,
        'accounts': [
          account,
          for (final status in ['warning', 'rateLimited', 'authRequired'])
            {
              ...account,
              'accountId': 'source-$status',
              'provider': 'claude',
              'connection': ProviderConnections.claudePlan.storageKey,
              'status': status,
              'allowances': <Object>[],
            },
        ],
      })
      .withConnectionVersions({
        ProviderConnections.codexPlan.storageKey: {'generation': 'g1'},
      })
      .withReportingOutcomes([
        const ConnectionReportingOutcome(
          connection: ProviderConnections.openAiPlatform,
          category: ReportingOutcomeCategory.accessDenied,
          source: ReportingOutcomeSource.live,
        ),
      ])
      .withSyncIssue(
        DashboardSyncIssue.permissionDenied,
        details: 'Sanitized source issue',
      );
}

class _MemoryRecoveryNotificationStore
    implements RecoveryNotificationPreferenceStore {
  bool enabled = true;
  bool failRead = false;
  void Function()? beforeRead;

  @override
  Future<bool> read() async {
    beforeRead?.call();
    if (failRead) throw StateError('Preference unavailable.');
    return enabled;
  }

  @override
  Future<void> write(bool value) async => enabled = value;
}

/// Android refusing the permission, which the switch alone cannot detect.
class _BlockedRecoveryNotifier implements RecoveryNotifier {
  var asked = 0;
  final reported = <PlanRecovery>[];

  @override
  Future<void> notify(PlanRecovery recovery) async => reported.add(recovery);

  @override
  Future<bool> requestPermission() async {
    asked++;
    return false;
  }
}

class _MemoryRecoveryWatchlistStore implements RecoveryWatchlistStore {
  List<WindowKey> keys = const [];
  int reads = 0;

  @override
  Future<List<WindowKey>> read() async {
    reads++;
    return keys;
  }

  @override
  Future<void> write(List<WindowKey> value) async => keys = value;
}

class _RecordingRecoveryWake implements RecoveryWakeScheduler {
  final booked = <DateTime>[];
  var cancelled = 0;

  @override
  Future<void> scheduleAt(DateTime resetsAt) async => booked.add(resetsAt);

  @override
  Future<void> cancel() async => cancelled++;
}

class _DelayedAlertPreferenceStore implements AlertNotificationPreferenceStore {
  bool enabled = true;
  bool holdRead = false;
  bool holdWrite = false;
  final readStarted = Completer<void>();
  final writeStarted = Completer<void>();
  final releaseRead = Completer<void>();
  final releaseWrite = Completer<void>();
  @override
  Future<bool> read() async {
    final captured = enabled;
    if (holdRead) {
      readStarted.complete();
      await releaseRead.future;
    }
    return captured;
  }

  @override
  Future<void> write(bool value) async {
    if (holdWrite) {
      writeStarted.complete();
      await releaseWrite.future;
    }
    enabled = value;
  }
}

class _MemoryAlertConditions implements AlertConditionStore {
  final values = <AlertConditionKey, bool>{};
  @override
  Future<bool> read(AlertConditionKey key) async => values[key] ?? false;
  @override
  Future<void> write(AlertConditionKey key, bool value) async =>
      values[key] = value;
}

class _FakeAlertNotifier implements AlertNotifier {
  int asked = 0;
  final posts = <AlertConditionKey>[];
  final bodies = <String>[];
  @override
  Future<bool> canPost() async => true;
  @override
  Future<bool> requestPermission() async {
    asked++;
    return false;
  }

  @override
  Future<void> notify(
    AlertConditionKey key, {
    required String title,
    required String body,
  }) async {
    posts.add(key);
    bodies.add(body);
  }
}

class _FakeWatchSyncService implements WatchSyncService {
  final syncedSnapshots = <DashboardSnapshot>[];
  final mockModes = <bool>[];
  bool fail = false;
  void Function()? refreshHandler;

  @override
  Future<void> sync(
    DashboardSnapshot snapshot,
    WatchRingPreferences ringPreferences, {
    DateTime? manualRefreshAnchorAt,
    bool mockDataMode = false,
  }) async {
    syncedSnapshots.add(snapshot);
    mockModes.add(mockDataMode);
    if (fail) throw StateError('Watch unavailable');
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

class _HoldingWatchSyncService extends _FakeWatchSyncService {
  bool hold = false;
  final entered = Completer<void>();
  final release = Completer<void>();
  @override
  Future<void> sync(
    DashboardSnapshot snapshot,
    WatchRingPreferences preferences, {
    DateTime? manualRefreshAnchorAt,
    bool mockDataMode = false,
  }) async {
    if (hold) {
      if (!entered.isCompleted) entered.complete();
      await release.future;
    }
    await super.sync(
      snapshot,
      preferences,
      manualRefreshAnchorAt: manualRefreshAnchorAt,
      mockDataMode: mockDataMode,
    );
  }
}

class _FakePhoneWidgetSyncService implements PhoneWidgetSyncService {
  final syncedSnapshots = <DashboardSnapshot>[];
  bool fail = false;

  @override
  Future<void> sync(
    DashboardSnapshot snapshot,
    PhoneWidgetPreferences preferences,
  ) async {
    syncedSnapshots.add(snapshot);
    if (fail) throw StateError('Widget unavailable');
  }
}

class _FailingWatchSyncService implements WatchSyncService {
  const _FailingWatchSyncService();

  @override
  Future<void> sync(
    DashboardSnapshot snapshot,
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

Widget _watchPicker({
  required DashboardSnapshot snapshot,
  required WatchRingPreferences initial,
  required ValueChanged<WatchRingPreferences> onChanged,
}) {
  var preferences = initial;
  return MaterialApp(
    home: Scaffold(
      body: StatefulBuilder(
        builder:
            (context, setState) => WatchfaceScreen(
              snapshot: snapshot,
              ringPreferences: preferences,
              onRefresh: () async {},
              onRingPreferencesChanged: (next) async {
                onChanged(next);
                setState(() => preferences = next);
              },
            ),
      ),
    ),
  );
}

/// Synthetic catalogue with all three supported pairs and an optional unknown half.
DashboardSnapshot _threePairDashboard({double? fableUsed = 90}) {
  final source = DashboardSnapshot.fromJsonString(
    File('../../fixtures/snapshots/dashboard_today.json').readAsStringSync(),
  );
  return DashboardSnapshot.fromJson(
    source.toJson()
      ..['accounts'] = [
        for (final (provider, connection, limits) in [
          (
            'claude',
            'anthropic.plan',
            [
              ('claude-five-hour', '5h', 40.0),
              ('claude-seven-day-fable', 'Fable weekly', fableUsed),
            ],
          ),
          (
            'codex',
            'openai.plan',
            [
              ('codex-primary', '5h', 30.0),
              ('spark-primary', 'Spark 5h', 20.0),
            ],
          ),
          (
            'cursor',
            'cursor.plan',
            [
              ('cursor-plan-models', 'Cursor Models', 70.0),
              ('cursor-plan-other', 'Other Models', 20.0),
            ],
          ),
        ])
          {
            ...source.primaryAccount!.toJson(),
            'provider': provider,
            'connection': connection,
            'allowances': [
              for (final (id, label, used) in limits)
                {
                  'id': id,
                  'label': label,
                  'source': 'plan',
                  'usedPercent': used,
                  'status': used == null ? 'unknown' : 'ok',
                },
            ],
          },
      ],
  );
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
  int writes = 0;
  bool failNextWrite = false;

  @override
  Future<AlertThresholdPreferences> read() async => value;

  @override
  Future<void> write(AlertThresholdPreferences next) async {
    writes++;
    if (failNextWrite) {
      failNextWrite = false;
      throw StateError('Storage unavailable');
    }
    value = next;
  }
}

class _MemoryCredentialStore
    implements ProviderCredentialStore, VersionedProviderCredentialStore {
  final _generations = <ProviderConnectionId, int>{};
  Future<void>? pendingWrite;
  bool failLabelWrite = false;
  bool failKeyWrite = false;
  bool failDeleteAfterRetirement = false;
  CredentialVersion version(ProviderConnectionId id) => CredentialVersion({
    'generation': '${_generations[id] ?? 0}',
    'revision': 'revision',
    'epoch': 'epoch',
    'identity': id.storageKey,
  });
  @override
  ConnectionCredentialAccess credentialAccess(ProviderConnectionId id) =>
      _MemoryCredentialAccess(this, id);
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
    await pendingWrite;
    if (failKeyWrite) throw StateError('Synthetic write failure');
    _generations[id] = (_generations[id] ?? 0) + 1;
    _secrets[id] = value;
  }

  @override
  Future<void> deleteSecret(ProviderConnectionId id) async {
    _generations[id] = (_generations[id] ?? 0) + 1;
    _secrets.remove(id);
    if (failDeleteAfterRetirement)
      throw StateError('Synthetic cleanup failure');
    _labels.remove(id);
  }

  @override
  Future<String?> readLabel(ProviderConnectionId id) async => _labels[id];

  @override
  Future<void> writeLabel(ProviderConnectionId id, String? value) async {
    if (failLabelWrite) throw StateError('Synthetic label failure');
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
  bool failWrite = false;
  int writes = 0;
  Future<void>? pendingWrite;

  @override
  Future<bool> readMockDataEnabled() async => value;

  @override
  Future<void> writeMockDataEnabled(bool value) async {
    writes++;
    if (failWrite) throw StateError('Debug preferences unavailable');
    final pending = pendingWrite;
    if (pending != null) await pending;
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

class _PublicationRepository extends DashboardRepository {
  _PublicationRepository(this.snapshot);
  DashboardSnapshot snapshot;
  int loads = 0;
  bool failLoad = false;
  bool failClear = false;
  Future<DashboardSnapshot>? response;
  bool current = true;
  bool delayNextValidation = false;
  bool validationStarted = false;
  final validationEntered = Completer<void>();
  final validation = Completer<bool>();
  @override
  Future<DashboardSnapshot> load() async {
    loads++;
    if (failLoad) throw const DashboardLoadException();
    if (response != null) return response!;
    return snapshot;
  }

  @override
  Future<void> clearPersistentSnapshots() async {
    if (failClear) throw StateError('Snapshot cache unavailable');
    await super.clearPersistentSnapshots();
  }

  // The failed request can be current after its previous data loses ownership.
  @override
  Future<bool> isFailureCurrent(DashboardLoadException failure) async => true;

  @override
  Future<bool> isSnapshotCurrent(DashboardSnapshot snapshot) async {
    if (delayNextValidation) {
      delayNextValidation = false;
      validationStarted = true;
      if (!validationEntered.isCompleted) validationEntered.complete();
      return validation.future;
    }
    return current;
  }
}

class _DelayedAlertThresholdStore implements AlertThresholdPreferenceStore {
  final release = Completer<void>();
  bool started = false;
  AlertThresholdPreferences value = const AlertThresholdPreferences();
  @override
  Future<AlertThresholdPreferences> read() async => value;
  @override
  Future<void> write(AlertThresholdPreferences next) async {
    started = true;
    await release.future;
    value = next;
  }
}

MergingConnectionRepository _reportingRepository(
  _MemoryCredentialStore store,
  Future<String> Function(String) fetch, {
  ProviderConnectionId connection = ProviderConnections.anthropicPlatform,
  DashboardRepository fallback = const NoProvidersDashboardRepository(),
}) => MergingConnectionRepository(
  connection: connection,
  credentialStore: store,
  loadCredentialReport: fetch,
  normalizeReport: (value) => value,
  fallback: fallback,
  logger: const NullProviderSyncLogger(),
  mapError: (error) => mapReportingError(error, const NullProviderSyncLogger()),
);

final class _MemoryCredentialAccess implements ConnectionCredentialAccess {
  const _MemoryCredentialAccess(this.store, this.id);
  final _MemoryCredentialStore store;
  final ProviderConnectionId id;
  @override
  Future<VersionedCredential<String>?> read() async {
    final value = await store.readSecret(id);
    return value == null ? null : VersionedCredential(value, store.version(id));
  }

  @override
  Future<bool> isCurrent(CredentialVersion expected) async =>
      await store.readSecret(id) != null &&
      expected.sameCache(store.version(id));
  @override
  Future<R> serializeFetch<R>(Future<R> Function() operation) => operation();
}

final class _OutcomeFailureRepository extends DashboardRepository {
  const _OutcomeFailureRepository(this.outcomes);
  final List<ConnectionReportingOutcome> outcomes;
  @override
  Future<DashboardSnapshot> load() async =>
      throw DashboardLoadException.withOutcomes(
        issue: DashboardSyncIssue.authentication,
        reportingOutcomes: outcomes,
      );
}
