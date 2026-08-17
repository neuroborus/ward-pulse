import 'dart:developer' as developer;

import 'package:flutter/widgets.dart';

import '../dashboard/apply_alert_settings.dart';
import '../dashboard/phone_live_bindings.dart';
import '../settings/alert_threshold_preferences.dart';
import '../settings/consumption_display_preferences.dart';
import '../settings/watch_ring_preferences.dart';
import '../widget/phone_widget_preferences.dart';
import '../widget/phone_widget_sync.dart';
import 'recovery_notifications.dart';
import 'recovery_wake.dart';
import 'recovery_watchlist.dart';
import 'watch_sync_service.dart';

/// One provider sync + watch push with no UI (headless WorkManager tick).
///
/// Failures are swallowed so a background tick never crashes the host.
Future<void> providerSyncOnce() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    final live = PhoneLiveBindings.create();
    final displayPreferences =
        await SecureConsumptionDisplayPreferenceStore().read();
    final ringPreferences = await SecureWatchRingPreferenceStore().read();
    final widgetPreferences = await SecurePhoneWidgetPreferenceStore().read();
    final alertThresholds = await SecureAlertThresholdPreferenceStore().read();
    final snapshot = applyUserAlertSettings(
      await live.repository.load(),
      alertThresholds,
    );
    await const MethodChannelWatchSyncService().sync(
      snapshot,
      displayPreferences,
      ringPreferences,
    );
    try {
      await HomeWidgetPhoneWidgetSyncService().sync(
        snapshot,
        widgetPreferences,
      );
    } catch (error) {
      // The outer catch would swallow this without a word; name the cause.
      developer.log(
        'headless sync could not update the widget: $error',
        name: phoneWidgetLogName,
      );
    }
    // Bookkeeping last: what the reader can see is pushed first, and a store
    // that stalls must not hold up the watch.
    await syncPlanRecoveries(
      snapshot,
      SecureRecoveryWatchlistStore(),
      LocalRecoveryNotifier(),
      const WorkmanagerRecoveryWakeScheduler(),
    );
  } catch (_) {
    // Automatic / headless sync keeps the last successful snapshot visible.
  }
}
