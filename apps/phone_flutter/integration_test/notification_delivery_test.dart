import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:ward_pulse_phone/app/ward_pulse_app.dart';
import 'package:ward_pulse_phone/dashboard/apply_alert_settings.dart';
import 'package:ward_pulse_phone/dashboard/dashboard_models.dart';
import 'package:ward_pulse_phone/dashboard/dashboard_repository.dart';
import 'package:ward_pulse_phone/dashboard/plan_recoveries.dart';
import 'package:ward_pulse_phone/settings/alert_notification_preferences.dart';
import 'package:ward_pulse_phone/settings/alert_threshold_preferences.dart';
import 'package:ward_pulse_phone/settings/notification_permission_preferences.dart';
import 'package:ward_pulse_phone/settings/recovery_notification_preferences.dart';
import 'package:ward_pulse_phone/settings/settings_screen.dart';
import 'package:ward_pulse_phone/settings/watch_ring_preferences.dart';
import 'package:ward_pulse_phone/sync/alert_notifications.dart';
import 'package:ward_pulse_phone/sync/notification_coordinator.dart';
import 'package:ward_pulse_phone/sync/provider_sync_scheduler.dart';
import 'package:ward_pulse_phone/sync/recovery_notifications.dart';
import 'package:ward_pulse_phone/sync/recovery_wake.dart';
import 'package:ward_pulse_phone/sync/recovery_watchlist.dart';
import 'package:ward_pulse_phone/sync/watch_sync_service.dart';
import 'package:ward_pulse_phone/widget/phone_widget_navigation.dart';
import 'package:ward_pulse_phone/widget/phone_widget_sync.dart';

const _rules = AlertThresholdPreferences(
  connections: {
    'anthropic.plan': ConnectionAlertThresholds(
      plan: AlertPercentThreshold(at: 80),
    ),
  },
);

// Inline normalized inputs only. Rust supplies every condition and recovery.
DashboardSnapshot _source(double used) {
  final empty = DashboardSnapshot.empty(generatedAt: DateTime.utc(2026, 11, 2));
  final account = ProviderSnapshot(
    accountId: 'notification-integration-account',
    provider: 'claude',
    connection: 'anthropic.plan',
    status: ProviderStatus.ok,
    today: empty.todayTotal,
    week: empty.weekTotal,
    month: empty.monthTotal,
    credits: const [],
    buckets: const [],
    modelBreakdown: const [],
    lastSuccessfulSyncAt: null,
    allowances: [
      AllowanceState(
        id: 'notification-integration-weekly',
        source: AllowanceSource.plan,
        label: 'Weekly plan',
        usedPercent: used,
        used: null,
        limit: null,
        remaining: null,
        windowMinutes: 10080,
        resetsAt: null,
        status: ProviderStatus.ok,
      ),
    ],
  );
  return DashboardSnapshot.fromJson({
    ...empty.toJson(),
    'accounts': [account.toJson()],
  });
}

void main() {
  const firstForeground = bool.fromEnvironment(
    'WARDPULSE_NOTIFICATION_FIRST_FOREGROUND',
  );
  const grantedSound = bool.fromEnvironment(
    'WARDPULSE_NOTIFICATION_GRANTED_SOUND',
  );
  if (firstForeground && grantedSound) {
    throw ArgumentError('Notification case selectors are incompatible.');
  }
  final binding =
      IntegrationTestWidgetsFlutterBinding.ensureInitialized()
        ..framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  if (firstForeground) {
    _firstForegroundPermission(binding);
    return;
  }
  if (grantedSound) {
    _grantedSound(binding);
    return;
  }
  testWidgets(
    'isolated pipeline with real Rust and Android notifications',
    (tester) async {
      final plugin = FlutterLocalNotificationsPlugin();
      // This scenario proves denied delivery, not a startup request. Preserve
      // both default-On choices while explicitly handling the new bootstrap.
      final notifications = PhoneNotificationCoordinator(
        plugin: plugin,
        attempts: _PermissionAttempts()..handled = true,
      );
      final alerts = _Alerts(LocalAlertNotifier(coordinator: notifications));
      final recoveries = _Recoveries(
        LocalRecoveryNotifier(coordinator: notifications),
      );
      final alertChoice = _Choice();
      final recoveryChoice = _Choice();
      final markers = _Markers();
      final memory = _Windows();
      final wake = _Wake();
      final repository = _Repository(_source(20));
      final banner = ValueNotifier<({String text, VoidCallback next})?>(null);
      final key =
          applyUserAlertSettings(
            _source(20),
            _rules,
          ).alertConditions.single.key;
      final recovery =
          planRecoveries(_source(20), exhaustedWindows(_source(100))).single;
      final tag = alertNotificationTag(key);
      final recoveryId = recoveryNotificationId(recovery);
      final stages = <String>[];
      final oldPointers = binding.shouldPropagateDevicePointerEvents;
      binding.shouldPropagateDevicePointerEvents = true;

      bool isAlert(ActiveNotification n) =>
          n.id == alertNotificationId && n.tag == tag;
      bool isRecovery(ActiveNotification n) =>
          n.id == recoveryId && n.tag == null;
      Future<void> absent() async {
        final active = await plugin.getActiveNotifications();
        expect(
          active.any(isAlert),
          isFalse,
          reason: 'Case alert identity must be unused.',
        );
        expect(
          active.any(isRecovery),
          isFalse,
          reason: 'Case recovery identity must be unused.',
        );
      }

      Future<void> removeOwned() async {
        // A lost plugin reply can still leave a post. These case identities
        // were unused at preflight; reconcile attempted identities with Android.
        final active = await plugin.getActiveNotifications();
        await Future.wait([
          if (alerts.attempts > 0 && active.any(isAlert))
            plugin.cancel(id: alertNotificationId, tag: tag),
          if (recoveries.attempts > 0 && active.any(isRecovery))
            plugin.cancel(id: recoveryId),
        ]);
      }

      Future<void> barrier(String text) async {
        final continued = Completer<void>();
        banner.value = (
          text: text,
          next: () {
            if (!continued.isCompleted) continued.complete();
          },
        );
        await tester.pump();
        await tester.runAsync(() => continued.future);
        banner.value = null;
        stages.add(text);
        await tester.pump();
      }

      // An empty queued delivery awaits the app's earlier unawaited alert work;
      // it supplies no observations, bookkeeping, eligibility or posting effects.
      Future<void> drainAlerts() => AlertNotificationDelivery(
        preferences: alertChoice,
        conditions: markers,
        notifier: alerts,
      ).sync(DashboardSnapshot.empty());
      Future<void> publish(double used) async {
        wake.done = Completer<void>();
        repository.snapshot = _source(used);
        await tester
            .widget<SettingsScreen>(find.byType(SettingsScreen))
            .onRefresh();
        await wake.done.future;
        await drainAlerts();
        await tester.pumpAndSettle();
      }

      Future<void> visible(bool includeRecovery) async {
        final active = await plugin.getActiveNotifications();
        final alert = active.singleWhere(isAlert);
        expect(alert.channelId, 'wardpulse.alerts');
        expect(alert.title, 'Claude · Weekly plan');
        expect(alert.body, 'Reached your alert threshold: 20% left.');
        if (includeRecovery) {
          final recovered = active.singleWhere(isRecovery);
          expect(recovered.channelId, 'wardpulse.plan_recovery');
          expect(recovered.title, 'Claude · Weekly plan');
          expect(recovered.body, recoveryNotificationBody);
        }
      }

      try {
        // Initialize without requesting permission; OS denial precedes launch.
        expect(await alerts.canPost(), isFalse);
        await absent(); // Never displace a pre-existing notification.
        await tester.pumpWidget(
          MaterialApp(
            home: Stack(
              children: [
                WardPulseApp(
                  repository: repository,
                  watchSyncService: _NoWatch(),
                  phoneWidgetSyncService:
                      const DisabledPhoneWidgetSyncService(),
                  phoneWidgetNavigationService: _NoNavigation(),
                  syncScheduler: const DisabledProviderSyncScheduler(),
                  scheduleHeadlessSync: (_) async {},
                  alertThresholdStore: _Rules(),
                  alertNotificationStore: alertChoice,
                  alertConditionStore: markers,
                  alertNotifier: alerts,
                  notificationCoordinator: notifications,
                  recoveryNotificationStore: recoveryChoice,
                  recoveryWatchlistStore: memory,
                  recoveryNotifier: recoveries,
                  recoveryWake: wake,
                ),
                ValueListenableBuilder(
                  valueListenable: banner,
                  builder:
                      (context, value, _) =>
                          value == null
                              ? const SizedBox.shrink()
                              : Align(
                                alignment: Alignment.bottomCenter,
                                child: Material(
                                  child: SafeArea(
                                    child: Padding(
                                      padding: const EdgeInsets.all(16),
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(value.text),
                                          FilledButton(
                                            onPressed: value.next,
                                            child: const Text('Continue'),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                ),
              ],
            ),
          ),
        );
        await tester.pumpAndSettle();
        await wake.done.future;
        await drainAlerts();
        await tester.tap(find.text('Settings'));
        await tester.pumpAndSettle();
        await barrier(
          'READY: prelaunch denial and restoration receipts must already be retained. Keep Android notifications denied. '
          'Case alert: ID $alertNotificationId, tag $tag. Recovery: untagged ID $recoveryId. '
          'Inspect the clear baseline, then Continue.',
        );
        expect(await alerts.canPost(), isFalse);
        await absent();
        await publish(90);
        expect(markers.values[key], isTrue);
        expect(memory.keys, isEmpty);
        expect(alerts.attempts, 0);
        expect(recoveries.attempts, 0);
        await absent();
        await barrier(
          'DENIED ALERT: the 90 crossing is consumed. Inspect absence and retain private OS receipts. Keep Android denied, then Continue.',
        );
        expect(await alerts.canPost(), isFalse);
        await publish(100);
        expect(memory.keys, isNotEmpty);
        expect(markers.values[key], isTrue);
        expect(alerts.attempts, 0);
        await absent();
        await publish(20);
        expect(memory.keys, isEmpty);
        expect(markers.values.containsKey(key), isFalse);
        expect(alerts.attempts, 0);
        expect(
          recoveries.attempts,
          1,
        ); // Denied plugin completion or failure is not delivery proof.
        await absent();
        await barrier(
          'DENIED RECOVERY: exhausted 100 to usable 20 advanced tracking without a visible post. Retain private absence receipts; keep Android denied, then Continue.',
        );
        expect(await alerts.canPost(), isFalse);
        await publish(90);
        expect(await alerts.canPost(), isFalse);
        expect(markers.values[key], isTrue);
        expect(memory.keys, isEmpty);
        expect(alerts.attempts, 0);
        expect(recoveries.attempts, 1);
        await absent();
        await barrier(
          'GRANT: 90 is consumed again and recovery tracking is clear. Retain before/after PID, process-start and VM receipts; enable Android notifications ON once. '
          'Continue only after proving continuity and permission/channel policy. Never revoke during the remaining case.',
        );
        expect(await alerts.canPost(), isTrue);
        await publish(90);
        expect(markers.values[key], isTrue);
        expect(memory.keys, isEmpty);
        expect(alerts.attempts, 0);
        expect(recoveries.attempts, 1);
        await absent();
        await barrier(
          'NO BACKLOG: unchanged 90 caused neither alert nor recovery replay after the single grant. Retain absence and continuity receipts, then Continue with Android enabled.',
        );
        await publish(20);
        expect(markers.values.containsKey(key), isFalse);
        await publish(90);
        await barrier(
          'CROSSED: inspect alert UID/channel/tag/ID, post/update facts and original shade frame, then Continue.',
        );
        await visible(false);
        expect(alerts.attempts, 1);
        await publish(90);
        expect(
          alerts.attempts,
          1,
        ); // Adapter invocations, not proof of OS no-repost.
        await barrier(
          'UNCHANGED: compare OS post/update facts and shade with CROSSED. Stable counts alone prove no delivery guarantee. Continue.',
        );
        await publish(20);
        expect(markers.values.containsKey(key), isFalse);
        await barrier(
          'CLEAR: Rust observed clear and removed the consumed marker; the earlier visible post can remain. Continue to rearm.',
        );
        await publish(90);
        expect(alerts.attempts, 2);
        await barrier(
          'REARMED: inspect the new alert attempt and original shade frame, then Continue.',
        );
        await visible(false);
        await removeOwned();

        await publish(20);
        alertChoice.enabled = false;
        await publish(90);
        expect(markers.values[key], isTrue);
        alertChoice.enabled = true;
        await publish(90);
        expect(alerts.attempts, 2);
        await absent();
        await barrier(
          'MUTED ALERT: crossing was consumed; enabling delivery with an unchanged crossing did not call the adapter. Inspect absence, then Continue.',
        );
        recoveryChoice.enabled = false;
        await publish(100);
        expect(memory.keys, isNotEmpty);
        await publish(20);
        recoveryChoice.enabled = true;
        await publish(20);
        expect(recoveries.attempts, 1);
        await absent();
        await barrier(
          'MUTED RECOVERY: exhausted→usable advanced tracking without a new post/backlog. Inspect absence, keep Android enabled, then Continue.',
        );
        await publish(100);
        expect(memory.keys, isNotEmpty);
        expect(alerts.attempts, 3);
        expect(recoveries.attempts, 1);
        await barrier(
          'EXHAUSTED: inspect the alert and remembered spent window before recovery, then Continue.',
        );
        await visible(false);
        await publish(20);
        expect(recoveries.attempts, 2);
        expect(memory.keys, isEmpty);
        await barrier(
          'RECOVERED: inspect BOTH actual alert and recovery identities and original shade frames. Continue cleans only this case’s posts.',
        );
        await visible(true);
        binding.reportData = {
          'scope': 'injected pipeline / real FFI and Android adapters',
          'alert': {
            'channel': 'wardpulse.alerts',
            'id': alertNotificationId,
            'tag': tag,
            'adapterAttempts': alerts.attempts,
            'pluginCompletions': alerts.posts,
          },
          'recovery': {
            'channel': 'wardpulse.plan_recovery',
            'id': recoveryId,
            'tag': null,
            'adapterAttempts': recoveries.attempts,
            'pluginCompletions': recoveries.posts,
          },
          'barriers': stages,
        };
      } finally {
        try {
          try {
            await tester.pumpWidget(const SizedBox());
            await tester.pumpAndSettle();
            await drainAlerts();
          } finally {
            await removeOwned();
          }
        } finally {
          banner.dispose();
          binding.shouldPropagateDevicePointerEvents = oldPointers;
        }
      }
    },
    timeout: const Timeout(Duration(minutes: 18)),
  );
}

void _grantedSound(IntegrationTestWidgetsFlutterBinding binding) {
  testWidgets(
    'granted baseline with real Rust and Android notification sound witnesses',
    (tester) async {
      final elapsed = Stopwatch()..start();
      const baselineBy = Duration(seconds: 60);
      const recoveryReadyBy = Duration(seconds: 210);
      const finalEntryBy = Duration(seconds: 360);
      const observationsBy = Duration(seconds: 420);
      const completeBy = Duration(minutes: 8);
      binding.reportData = null;
      final plugin = FlutterLocalNotificationsPlugin();
      final previousPlatform = FlutterLocalNotificationsPlatform.instance;
      final previousPointers = binding.shouldPropagateDevicePointerEvents;
      final android = _ObservedAndroidNotifications();
      final permissionAttempts = _PermissionAttempts()..handled = true;
      final notifications = PhoneNotificationCoordinator(
        plugin: plugin,
        attempts: permissionAttempts,
      );
      late final _Alerts alerts;
      late final _Recoveries recoveries;
      final alertChoice = _Choice();
      final recoveryChoice = _Choice();
      final markers = _Markers();
      final memory = _Windows();
      final wake = _Wake();
      final repository = _Repository(_source(20));
      final banner = ValueNotifier<({String text, VoidCallback next})?>(null);
      final stages = <String>[];
      late AlertConditionKey key;
      late String tag;
      late int recoveryId;
      Map<String, Map<String, Object?>>? beforePolicy;
      bool identitiesUnused = false;
      bool mountingStarted = false;
      bool alertDispatched = false;
      bool recoveryDispatched = false;
      double? publishing;
      Duration? postingBy;
      Future<void>? pendingRefresh;
      Future<void>? pendingWake;

      void before(Duration cutoff, String phase) {
        if (elapsed.elapsed >= cutoff) {
          throw TimeoutException(
            '$phase missed its ${cutoff.inSeconds}s cutoff '
            'at ${elapsed.elapsedMilliseconds}ms; cleanup only.',
          );
        }
      }

      bool isAlert(ActiveNotification n) =>
          n.id == alertNotificationId && n.tag == tag;
      bool isRecovery(ActiveNotification n) =>
          n.id == recoveryId && n.tag == null;
      bool hasOwnedCopy(ActiveNotification n) =>
          n.title == 'Claude · Weekly plan' &&
          (isAlert(n)
              ? n.channelId == alertNotificationChannel.id &&
                  n.body == 'Reached your alert threshold: 20% left.'
              : isRecovery(n) &&
                  n.channelId == recoveryNotificationChannel.id &&
                  n.body == recoveryNotificationBody);

      // Compare the effective values returned by Android, not declarations or
      // sound object identity. OS blocking/playback still needs HOST evidence.
      Map<String, Object?> policy(AndroidNotificationChannel channel) => {
        'id': channel.id,
        'name': channel.name,
        'description': channel.description,
        'groupId': channel.groupId,
        'importance': channel.importance,
        'bypassDnd': channel.bypassDnd,
        'playSound': channel.playSound,
        'sound': channel.sound?.sound,
        'enableVibration': channel.enableVibration,
        'vibrationPattern': channel.vibrationPattern?.toList(),
        'showBadge': channel.showBadge,
        'enableLights': channel.enableLights,
        'ledColor': channel.ledColor?.toARGB32(),
        'audioAttributesUsage': channel.audioAttributesUsage,
      };
      Future<Map<String, Map<String, Object?>>> readPolicy() async {
        final channels = await android.getNotificationChannels();
        expect(channels, isNotNull, reason: 'Unknown existing channel policy.');
        return {
          for (final expected in [
            alertNotificationChannel,
            recoveryNotificationChannel,
          ])
            expected.id: policy(
              channels!.singleWhere((channel) => channel.id == expected.id),
            ),
        };
      }

      Future<void> unchangedPolicy() async {
        expect(await notifications.readAndroidNotificationStatus(), isTrue);
        expect(await readPolicy(), beforePolicy);
        expect(android.requests, 0);
        expect(permissionAttempts.handled, isTrue);
      }

      Future<void> vacant({bool alert = false, bool recovery = false}) async {
        final active = await plugin.getActiveNotifications();
        if (alert) {
          expect(
            active.where(isAlert),
            isEmpty,
            reason: 'The case alert identity must be absent.',
          );
        }
        if (recovery) {
          expect(
            active.where(isRecovery),
            isEmpty,
            reason: 'The next recovery identity must be unused.',
          );
        }
      }

      Future<void> visible({required bool recovery}) async {
        final active = await plugin.getActiveNotifications();
        expect(active.where((n) => isAlert(n) || isRecovery(n)), hasLength(1));
        expect(
          hasOwnedCopy(active.singleWhere(recovery ? isRecovery : isAlert)),
          isTrue,
        );
        await unchangedPolicy();
      }

      Future<void> barrier(
        String stage,
        String instructions,
        Duration cutoff,
      ) async {
        before(cutoff, stage);
        final continued = Completer<bool>();
        banner.value = (
          text:
              '$stage: $instructions '
              'Elapsed ${elapsed.elapsed.inSeconds}s; Continue before '
              '${cutoff.inSeconds}s from case start.',
          next: () {
            if (!continued.isCompleted) {
              continued.complete(elapsed.elapsed < cutoff);
            }
          },
        );
        try {
          await tester.pump();
          final success = await tester.runAsync(() async {
            before(cutoff, stage);
            final accepted = await continued.future.timeout(
              cutoff - elapsed.elapsed,
            );
            before(cutoff, stage);
            return accepted;
          });
          // Live runAsync reports exceptions and returns null. Never advance
          // merely because its returned Future completed.
          expect(
            success,
            isTrue,
            reason: '$stage did not receive a valid Continue.',
          );
          before(cutoff, stage);
        } finally {
          banner.value = null;
        }
        await tester.pump();
      }

      Future<void> drainAlerts() => AlertNotificationDelivery(
        preferences: alertChoice,
        conditions: markers,
        notifier: alerts,
      ).sync(DashboardSnapshot.empty());
      Future<void> publish(double used, Duration cutoff) async {
        before(cutoff, 'Prepare $used');
        await unchangedPolicy();
        // The retired alert must stay absent through 100 and recovery.
        await vacant(alert: true, recovery: used != 90);
        final refresh =
            tester
                .widget<SettingsScreen>(find.byType(SettingsScreen))
                .onRefresh;
        before(cutoff, 'Publish $used');
        publishing = used;
        postingBy = cutoff;
        wake.done = Completer<void>();
        pendingWake = wake.done.future;
        repository.snapshot = _source(used);
        pendingRefresh = Future<void>.sync(refresh);
        await pendingRefresh;
        // Never time out and abandon delivery. Unsettled work cannot produce
        // COMPLETE, even when the framework backstop has already failed.
        await pendingWake;
        await drainAlerts();
        await tester.pumpAndSettle();
      }

      void counts(int alertCount, int recoveryCount) {
        expect(alerts.attempts, alertCount);
        expect(alerts.posts, alertCount);
        expect(recoveries.attempts, recoveryCount);
        expect(recoveries.posts, recoveryCount);
      }

      Future<void> removeOwned() async {
        if (!identitiesUnused) return;
        final active = await plugin.getActiveNotifications();
        final changed = <ActiveNotification>[];
        final cancellations = <Future<void>>[];
        for (final post in active) {
          if (!(alertDispatched && isAlert(post)) &&
              !(recoveryDispatched && isRecovery(post)))
            continue;
          if (!hasOwnedCopy(post)) {
            changed.add(post); // Preserve any replacement we cannot attribute.
          } else {
            cancellations.add(plugin.cancel(id: post.id!, tag: post.tag));
          }
        }
        await Future.wait(cancellations);
        expect(
          changed,
          isEmpty,
          reason:
              'Changed case identities were preserved; cleanup is unproved.',
        );
        final remaining = await plugin.getActiveNotifications();
        expect(
          remaining.where(
            (n) =>
                (alertDispatched && isAlert(n)) ||
                (recoveryDispatched && isRecovery(n)),
          ),
          isEmpty,
        );
      }

      Future<void> guardPost({required bool alert}) async {
        final cutoff = postingBy;
        expect(
          publishing,
          alert ? 90 : 20,
          reason: 'No post is intended for this observation.',
        );
        if (cutoff == null)
          throw StateError('No intended publication deadline.');
        before(cutoff, 'Adapter publication');
        await unchangedPolicy();
        await vacant(alert: true, recovery: !alert);
        before(cutoff, 'Adapter publication');
        // A guard failure must not claim an identity it never dispatched.
        // A subsequent lost plugin reply still requires OS reconciliation.
        if (alert) {
          alertDispatched = true;
        } else {
          recoveryDispatched = true;
        }
      }

      alerts = _Alerts(
        LocalAlertNotifier(coordinator: notifications),
        beforePost: () => guardPost(alert: true),
      );
      recoveries = _Recoveries(
        LocalRecoveryNotifier(coordinator: notifications),
        beforePost: () => guardPost(alert: false),
      );
      FlutterLocalNotificationsPlatform.instance = android;
      try {
        key =
            applyUserAlertSettings(
              _source(20),
              _rules,
            ).alertConditions.single.key;
        final recovery =
            planRecoveries(_source(20), exhaustedWindows(_source(100))).single;
        tag = alertNotificationTag(key);
        recoveryId = recoveryNotificationId(recovery);
        // These inspections precede ensureReady/canPost and app initialization.
        expect(
          await notifications.readAndroidNotificationStatus(),
          isTrue,
          reason: 'HOST must qualify an already-granted baseline.',
        );
        beforePolicy = await readPolicy();
        await vacant(alert: true, recovery: true);
        identitiesUnused = true;
        before(baselineBy, 'Granted preflight');
        await notifications.ensureReady();
        expect(await alerts.canPost(), isTrue);
        await unchangedPolicy();
        binding.shouldPropagateDevicePointerEvents = true;
        mountingStarted = true;
        pendingWake = wake.done.future;
        await tester.pumpWidget(
          MaterialApp(
            home: Stack(
              children: [
                WardPulseApp(
                  repository: repository,
                  notificationCoordinator: notifications,
                  alertNotifier: alerts,
                  recoveryNotifier: recoveries,
                  alertThresholdStore: _Rules(),
                  alertNotificationStore: alertChoice,
                  recoveryNotificationStore: recoveryChoice,
                  alertConditionStore: markers,
                  recoveryWatchlistStore: memory,
                  recoveryWake: wake,
                  watchSyncService: _NoWatch(),
                  phoneWidgetSyncService:
                      const DisabledPhoneWidgetSyncService(),
                  phoneWidgetNavigationService: _NoNavigation(),
                  syncScheduler: const DisabledProviderSyncScheduler(),
                  scheduleHeadlessSync: (_) async {},
                ),
                ValueListenableBuilder(
                  valueListenable: banner,
                  builder:
                      (context, value, _) =>
                          value == null
                              ? const SizedBox.shrink()
                              : Align(
                                alignment: Alignment.bottomCenter,
                                child: Material(
                                  child: SafeArea(
                                    child: Padding(
                                      padding: const EdgeInsets.all(16),
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(value.text),
                                          FilledButton(
                                            onPressed: value.next,
                                            child: const Text('Continue'),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                ),
              ],
            ),
          ),
        );
        await tester.pumpAndSettle();
        await pendingWake;
        await drainAlerts();
        await tester.tap(find.text('Settings'));
        await tester.pumpAndSettle();
        counts(0, 0);
        expect(markers.values, isEmpty);
        expect(memory.keys, isEmpty);
        await vacant(alert: true, recovery: true);
        await unchangedPolicy();
        await barrier(
          'GRANTED READY',
          'Clear 20 is settled. Alert ID $alertNotificationId, tag $tag; '
              'recovery untagged ID $recoveryId. Arm the isolated alert capture '
              'before Continue publishes 90; retain the capture start time.',
          baselineBy,
        );
        await publish(90, baselineBy);
        counts(1, 0);
        expect(markers.values[key], isTrue);
        expect(memory.keys, isEmpty);
        // Plugin completion can precede OS visibility. The next Continue,
        // after HOST observes the post, synchronizes its identity assertions.
        await unchangedPolicy();
        before(recoveryReadyBy, 'Alert witness');
        stages.add('GRANTED READY');
        await barrier(
          'ALERT POSTED',
          'Retain the alert sound, actual OS post/time and original shade evidence. '
              'Continue validates and retires the alert before publishing 100 '
              'without a second alert.',
          recoveryReadyBy,
        );
        await visible(recovery: false);
        counts(1, 0);
        await removeOwned();
        counts(1, 0);
        expect(markers.values[key], isTrue);
        expect(memory.keys, isEmpty);
        await unchangedPolicy();
        await publish(100, recoveryReadyBy);
        counts(1, 0);
        expect(markers.values[key], isTrue);
        expect(memory.keys, exhaustedWindows(_source(100)));
        expect(memory.keys, isNotEmpty);
        await vacant(alert: true, recovery: true);
        await unchangedPolicy();
        before(recoveryReadyBy, 'Recovery preparation');
        stages.add('ALERT POSTED');
        await barrier(
          'RECOVERY READY',
          'Exhausted 100 is remembered; the earlier alert is absent. '
              'Arm the separate isolated recovery capture before Continue publishes 20; '
              'retain the capture start time.',
          finalEntryBy,
        );
        counts(1, 0);
        expect(markers.values[key], isTrue);
        expect(memory.keys, exhaustedWindows(_source(100)));
        await publish(20, finalEntryBy);
        counts(1, 1);
        expect(markers.values, isEmpty);
        expect(memory.keys, isEmpty);
        await unchangedPolicy();
        before(finalEntryBy, 'Final phase entry');
        stages.add('RECOVERY READY');
        await barrier(
          'RECOVERY POSTED',
          'Retain recovery sound, actual OS identity/time and original shade evidence '
              'alongside the earlier alert evidence. Continue finishes observations '
              'and starts owned teardown.',
          observationsBy,
        );
        counts(1, 1);
        expect(markers.values, isEmpty);
        expect(memory.keys, isEmpty);
        await visible(recovery: true);
        before(observationsBy, 'Final observations');
        stages.add('RECOVERY POSTED');
      } finally {
        try {
          try {
            if (mountingStarted) {
              await tester.pumpWidget(const SizedBox());
              await tester.pumpAndSettle();
            }
          } finally {
            // Future.wait settles every owned operation even when one fails.
            // No cancellation/reconciliation may race outstanding delivery.
            await Future.wait<void>([
              if (pendingRefresh != null) pendingRefresh!,
              if (pendingWake != null) pendingWake!,
              if (android.answer != null) android.answer!.then<void>((_) {}),
              drainAlerts(),
            ]);
          }
        } finally {
          try {
            await removeOwned();
          } finally {
            try {
              if (beforePolicy != null) await unchangedPolicy();
            } finally {
              binding.shouldPropagateDevicePointerEvents = previousPointers;
              FlutterLocalNotificationsPlatform.instance = previousPlatform;
              banner.dispose();
            }
          }
        }
      }
      before(completeBy, 'Cleanup/report');
      expect(tester.takeException(), isNull);
      stages.add('COMPLETE');
      binding.reportData = {
        'scope': 'granted baseline / real FFI and Android adapters',
        'completed': true,
        'alert': {
          'channel': alertNotificationChannel.id,
          'id': alertNotificationId,
          'tag': tag,
          'adapterAttempts': alerts.attempts,
          'pluginCompletions': alerts.posts,
        },
        'recovery': {
          'channel': recoveryNotificationChannel.id,
          'id': recoveryId,
          'tag': null,
          'adapterAttempts': recoveries.attempts,
          'pluginCompletions': recoveries.posts,
        },
        'barriers': List<String>.of(stages),
      };
    },
    timeout: const Timeout(Duration(minutes: 8)),
  );
}

void _firstForegroundPermission(IntegrationTestWidgetsFlutterBinding binding) {
  testWidgets(
    'first foreground requests the shared Android permission',
    (tester) async {
      final plugin = FlutterLocalNotificationsPlugin();
      final previousPlatform = FlutterLocalNotificationsPlatform.instance;
      final android = _ObservedAndroidNotifications();
      FlutterLocalNotificationsPlatform.instance = android;
      addTearDown(
        () => FlutterLocalNotificationsPlatform.instance = previousPlatform,
      );
      final attempts = _PermissionAttempts();
      final notifications = PhoneNotificationCoordinator(
        plugin: plugin,
        attempts: attempts,
      );
      final before = {
        for (final channel
            in await android.getNotificationChannels() ??
                <AndroidNotificationChannel>[])
          channel.id: channel,
      };
      expect(
        await android.areNotificationsEnabled(),
        isFalse,
        reason:
            'HOST must qualify a naturally requestable, ungranted baseline.',
      );
      final alerts = _Alerts(LocalAlertNotifier(coordinator: notifications));
      final recoveries = _Recoveries(
        LocalRecoveryNotifier(coordinator: notifications),
      );
      Widget app() => WardPulseApp(
        repository: _Repository(_source(20)),
        notificationCoordinator: notifications,
        alertNotifier: alerts,
        recoveryNotifier: recoveries,
        alertNotificationStore: _Choice(),
        recoveryNotificationStore: _Choice(),
        watchSyncService: _NoWatch(),
        phoneWidgetSyncService: const DisabledPhoneWidgetSyncService(),
        phoneWidgetNavigationService: _NoNavigation(),
        syncScheduler: const DisabledProviderSyncScheduler(),
        scheduleHeadlessSync: (_) async {},
      );
      try {
        await tester.pumpWidget(app());
        await tester.pump();
        await tester.runAsync(() => android.requested.future);
        // These application-context reads work while the actual Android dialog is
        // visible. HOST observes and denies that dialog; manual grant is no proof.
        final channels = await android.getNotificationChannels() ?? [];
        for (final expected in [
          alertNotificationChannel,
          recoveryNotificationChannel,
        ]) {
          final actual = channels.singleWhere(
            (channel) => channel.id == expected.id,
          );
          expect(actual.name, expected.name);
          expect(actual.description, expected.description);
          expect(
            actual.importance,
            before[expected.id]?.importance ?? expected.importance,
          );
        }
        expect(alerts.attempts, 0);
        expect(recoveries.attempts, 0);
        expect(await tester.runAsync(() => android.answer!), isFalse);
        await tester.pumpAndSettle();
        expect(attempts.handled, isTrue);
        await tester.tap(find.text('Settings'));
        await tester.pumpAndSettle();
        await tester
            .widget<SettingsScreen>(find.byType(SettingsScreen))
            .onRefresh();
        await tester.pumpAndSettle();
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
        await tester.pumpWidget(app());
        await tester.pumpAndSettle();
        expect(android.requests, 1);
        expect(await alerts.canPost(), isFalse);
        expect(alerts.attempts, 0);
        expect(recoveries.attempts, 0);
        binding.reportData = {
          'scope':
              'first foreground / real Android request; HOST dialog observation required',
          'requests': android.requests,
          'channelsBeforeCasePost': true,
          'refreshRemountNoSecondRequest': true,
        };
      } finally {
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
      }
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}

/// Observe the production dispatch without replacing its permission effect.
/// All platform work, including the actual Android dialog/result, stays real.
final class _ObservedAndroidNotifications
    extends AndroidFlutterLocalNotificationsPlugin {
  final requested = Completer<void>();
  Future<bool?>? answer;
  int requests = 0;

  @override
  Future<bool?> requestNotificationsPermission() {
    requests++;
    final result = super.requestNotificationsPermission();
    answer = result;
    if (!requested.isCompleted) requested.complete();
    return result;
  }
}

final class _PermissionAttempts implements NotificationPermissionAttemptStore {
  bool handled = false;
  @override
  Future<bool> read() async => handled;
  @override
  Future<void> write(bool value) async => handled = value;
}

final class _Repository extends DashboardRepository {
  _Repository(this.snapshot);
  DashboardSnapshot snapshot;
  @override
  Future<DashboardSnapshot> load() async => snapshot;
}

final class _Choice
    implements
        AlertNotificationPreferenceStore,
        RecoveryNotificationPreferenceStore {
  bool enabled = true;
  @override
  Future<bool> read() async => enabled;
  @override
  Future<void> write(bool value) async => enabled = value;
}

final class _Rules implements AlertThresholdPreferenceStore {
  AlertThresholdPreferences value = _rules;
  @override
  Future<AlertThresholdPreferences> read() async => value;
  @override
  Future<void> write(AlertThresholdPreferences next) async => value = next;
}

final class _Markers implements AlertConditionStore {
  final values = <AlertConditionKey, bool>{};
  @override
  Future<bool> read(AlertConditionKey key) async => values[key] ?? false;
  @override
  Future<void> write(AlertConditionKey key, bool consumed) async {
    if (consumed) {
      values[key] = true;
    } else {
      values.remove(key);
    }
  }
}

final class _Windows implements RecoveryWatchlistStore {
  List<WindowKey> keys = [];
  @override
  Future<List<WindowKey>> read() async => keys;
  @override
  Future<void> write(List<WindowKey> value) async => keys = value;
}

final class _Wake implements RecoveryWakeScheduler {
  Completer<void> done = Completer<void>();
  @override
  Future<void> cancel() async => done.complete();
  @override
  Future<void> scheduleAt(DateTime resetsAt) => cancel();
}

final class _Alerts implements AlertNotifier {
  _Alerts(this.real, {this.beforePost});
  final LocalAlertNotifier real;
  final Future<void> Function()? beforePost;
  int attempts = 0;
  int posts = 0;
  @override
  Future<bool> canPost() => real.canPost();
  @override
  Future<bool> requestPermission() => real.requestPermission();
  @override
  Future<void> notify(
    AlertConditionKey key, {
    required String title,
    required String body,
  }) async {
    attempts++;
    if (beforePost != null) await beforePost!();
    await real.notify(key, title: title, body: body);
    posts++;
  }
}

final class _Recoveries implements RecoveryNotifier {
  _Recoveries(this.real, {this.beforePost});
  final LocalRecoveryNotifier real;
  final Future<void> Function()? beforePost;
  int attempts = 0;
  int posts = 0;
  @override
  Future<bool> requestPermission() => real.requestPermission();
  @override
  Future<void> notify(PlanRecovery recovery) async {
    attempts++;
    if (beforePost != null) await beforePost!();
    await real.notify(recovery);
    posts++;
  }
}

final class _NoWatch implements WatchSyncService {
  @override
  void bindWatchRefreshListener(void Function() onRefresh) {}
  @override
  void unbindWatchRefreshListener() {}
  @override
  Future<void> sync(
    DashboardSnapshot snapshot,
    WatchRingPreferences ringPreferences, {
    DateTime? manualRefreshAnchorAt,
    bool mockDataMode = false,
  }) async {}
}

final class _NoNavigation implements PhoneWidgetNavigationService {
  @override
  void bind(void Function() openDashboard) {}
  @override
  void unbind() {}
}
