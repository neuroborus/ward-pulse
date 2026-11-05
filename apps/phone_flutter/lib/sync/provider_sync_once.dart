import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../dashboard/apply_alert_settings.dart';
import '../dashboard/phone_live_bindings.dart';
import '../settings/alert_notification_preferences.dart';
import '../settings/alert_threshold_preferences.dart';
import '../settings/debug_data_preferences.dart';
import '../settings/recovery_notification_preferences.dart';
import '../settings/watch_ring_preferences.dart';
import '../widget/phone_widget_preferences.dart';
import '../widget/phone_widget_sync.dart';
import 'alert_notifications.dart';
import 'recovery_notifications.dart';
import 'recovery_wake.dart';
import 'recovery_watchlist.dart';
import 'watch_sync_service.dart';

Future<bool> _alwaysCurrent() async => true;
Future<void> _noAlertDelivery() async {}

typedef ProviderSyncWorkLoader = Future<ProviderSyncWork> Function();
typedef ProviderSyncFailureLogger =
    void Function(String step, Object error, StackTrace stackTrace);

/// Work that can proceed independently once a provider snapshot is available.
final class ProviderSyncWork {
  const ProviderSyncWork({
    required this.syncWatch,
    required this.syncWidget,
    required this.syncRecoveries,
    this.syncAlerts = _noAlertDelivery,
    this.isCurrent = _alwaysCurrent,
  });

  final Future<void> Function() syncWatch;
  final Future<void> Function() syncWidget;
  final Future<void> Function() syncRecoveries;
  final Future<void> Function() syncAlerts;
  final Future<bool> Function() isCurrent;
}

/// One provider sync + watch push with no UI (headless WorkManager tick).
///
/// Setup and delivery failures are recorded but swallowed so one surface never
/// prevents another from receiving the newest snapshot.
Future<void> providerSyncOnce({
  ProviderSyncWorkLoader load = loadProviderSyncWork,
  ProviderSyncFailureLogger logFailure = _logProviderSyncFailure,
  Future<void> Function() markWidgetStale =
      HomeWidgetPhoneWidgetSyncService.markExistingRowsStale,
}) async {
  WidgetsFlutterBinding.ensureInitialized();

  final ProviderSyncWork work;
  try {
    work = await load();
  } catch (error, stackTrace) {
    logFailure('setup', error, stackTrace);
    await _attemptProviderSyncStep('widget', markWidgetStale, logFailure);
    return;
  }

  await _attemptProviderSyncStep('watch', () async {
    if (await work.isCurrent()) await work.syncWatch();
  }, logFailure);
  await _attemptProviderSyncStep('widget', () async {
    if (await work.isCurrent()) await work.syncWidget();
  }, logFailure);
  // Bookkeeping last: reader-visible surfaces are pushed first, but neither
  // surface can prevent the recovery state from advancing.
  await _attemptProviderSyncStep('recovery', () async {
    if (await work.isCurrent()) await work.syncRecoveries();
  }, logFailure);
  await _attemptProviderSyncStep('alerts', () async {
    if (await work.isCurrent()) await work.syncAlerts();
  }, logFailure);
}

Future<ProviderSyncWork> loadProviderSyncWork({
  PhoneLiveBindings Function()? createLive,
}) async {
  final live = (createLive ?? PhoneLiveBindings.create)();
  final ringPreferences = await SecureWatchRingPreferenceStore().read();
  final widgetPreferences = await SecurePhoneWidgetPreferenceStore().read();
  final alertThresholds = await SecureAlertThresholdPreferenceStore().read();
  final snapshot = applyUserAlertSettings(
    await live.repository.load(),
    alertThresholds,
  );

  if (!await live.repository.isSnapshotCurrent(snapshot))
    throw StateError('Connection changed during refresh.');
  return ProviderSyncWork(
    isCurrent: () => live.repository.isSnapshotCurrent(snapshot),
    syncWatch:
        () => const MethodChannelWatchSyncService().sync(
          snapshot,
          ringPreferences,
        ),
    syncWidget:
        () => HomeWidgetPhoneWidgetSyncService().sync(
          snapshot,
          widgetPreferences,
        ),
    syncRecoveries: () async {
      var notifications = false;
      try {
        notifications =
            await SecureRecoveryNotificationPreferenceStore().read();
      } catch (_) {
        // Delivery preferences cannot block publication or recovery tracking.
      }
      if (!await live.repository.isSnapshotCurrent(snapshot)) return;
      await syncPlanRecoveries(
        snapshot,
        SecureRecoveryWatchlistStore(),
        LocalRecoveryNotifier(),
        const WorkmanagerRecoveryWakeScheduler(),
        notifications: notifications,
        rethrowFailures: true,
      );
    },
    syncAlerts:
        () => AlertNotificationDelivery(
          preferences: SecureAlertNotificationPreferenceStore(),
          conditions: SecureAlertConditionStore(),
          notifier: LocalAlertNotifier(),
        ).sync(
          snapshot,
          alertThresholds: alertThresholds,
          isCurrent: () async {
            if (kDebugMode &&
                await SecureDebugDataPreferenceStore().readMockDataEnabled())
              return false;
            // Rules can change while a headless load or bookkeeping is awaiting.
            // Defer this observation until work captures the new effective rules.
            final currentRules =
                await SecureAlertThresholdPreferenceStore().read();
            if (currentRules.encode() != alertThresholds.encode()) return false;
            return live.repository.isSnapshotCurrent(snapshot);
          },
        ),
  );
}

Future<void> _attemptProviderSyncStep(
  String step,
  Future<void> Function() run,
  ProviderSyncFailureLogger logFailure,
) async {
  try {
    await run();
  } catch (error, stackTrace) {
    logFailure(step, error, stackTrace);
  }
}

void _logProviderSyncFailure(String step, Object error, StackTrace stackTrace) {
  developer.log('Headless sync $step failed.', name: 'WardPulse.ProviderSync');
}
