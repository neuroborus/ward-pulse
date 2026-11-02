import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'app/ward_pulse_app.dart';
import 'dashboard/dashboard_repository.dart';
import 'dashboard/phone_live_bindings.dart';
import 'settings/alert_notification_preferences.dart';
import 'settings/alert_threshold_preferences.dart';
import 'settings/recovery_notification_preferences.dart';
import 'settings/debug_data_preferences.dart';
import 'settings/refresh_interval_preferences.dart';
import 'settings/watch_ring_preferences.dart';
import 'widget/phone_widget_preferences.dart';
import 'widget/phone_widget_sync.dart';
import 'sync/alert_notifications.dart';
import 'sync/headless_provider_sync.dart';
import 'sync/provider_sync_scheduler.dart';
import 'sync/recovery_notifications.dart';
import 'sync/recovery_wake.dart';
import 'sync/recovery_watchlist.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await HeadlessProviderSync.ensureInitialized();
  final live = PhoneLiveBindings.create();
  final debugDataPreferenceStore = SecureDebugDataPreferenceStore();

  runApp(
    WardPulseApp(
      credentialStore: live.credentialStore,
      codexAccountService: live.codexAccountService,
      claudeAccountService: live.claudeAccountService,
      refreshIntervalStore: SecureRefreshIntervalPreferenceStore(),
      watchRingPreferenceStore: SecureWatchRingPreferenceStore(),
      phoneWidgetPreferenceStore: SecurePhoneWidgetPreferenceStore(),
      phoneWidgetSyncService: HomeWidgetPhoneWidgetSyncService(),
      alertThresholdStore: SecureAlertThresholdPreferenceStore(),
      alertNotificationStore: SecureAlertNotificationPreferenceStore(),
      alertConditionStore: SecureAlertConditionStore(),
      alertNotifier: LocalAlertNotifier(),
      syncScheduler: TimerProviderSyncScheduler(),
      debugDataAvailable: kDebugMode,
      debugDataPreferenceStore: debugDataPreferenceStore,
      recoveryWatchlistStore: SecureRecoveryWatchlistStore(),
      recoveryNotificationStore: SecureRecoveryNotificationPreferenceStore(),
      recoveryNotifier: LocalRecoveryNotifier(),
      recoveryWake: const WorkmanagerRecoveryWakeScheduler(),
      repository:
          kDebugMode
              ? DebugDashboardRepository(
                live: live.repository,
                preferences: debugDataPreferenceStore,
                mock: DemoDashboardRepository(
                  debugSeed: const String.fromEnvironment(
                    'WARD_PULSE_MOCK_SEED',
                  ),
                  debugAnchor:
                      const bool.hasEnvironment('WARD_PULSE_MOCK_ANCHOR')
                          ? const String.fromEnvironment(
                            'WARD_PULSE_MOCK_ANCHOR',
                          )
                          : null,
                ),
              )
              : live.repository,
    ),
  );
}
