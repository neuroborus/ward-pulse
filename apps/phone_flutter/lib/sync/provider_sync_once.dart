import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../dashboard/apply_alert_settings.dart';
import '../dashboard/dashboard_models.dart';
import '../dashboard/dashboard_repository.dart';
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
import 'automatic_poll.dart';

Future<bool> _alwaysCurrent() async => true;
Future<void> _noAlertDelivery() async {}

/// Loads work owned by [owner], or `null` once that owner has retired.
typedef ProviderSyncWorkLoader =
    Future<ProviderSyncWork?> Function(HeadlessLiveOwner owner);
typedef ProviderSyncFailureLogger =
    void Function(String step, Object error, StackTrace stackTrace);
typedef ProviderSyncStaleMarker =
    Future<void> Function({required PhoneWidgetSyncGuard isCurrent});

/// Whether one headless invocation still owns Live publications.
///
/// Debug Mock data belongs to the foreground app. A saved Mock choice, or one
/// that cannot be read, retires the invocation for good; the next invocation
/// asks again. Release builds never read the debug preference. Once a
/// repository result is bound, it also owns credential/snapshot provenance.
final class HeadlessLiveOwner {
  HeadlessLiveOwner({
    bool debugBuild = kDebugMode,
    DebugDataPreferenceStore? debugData,
  }) : _debugData =
           debugBuild ? debugData ?? SecureDebugDataPreferenceStore() : null;

  final DebugDataPreferenceStore? _debugData;
  var _retired = false;
  Future<bool> Function()? _provenance;

  /// Binds later currentness to the repository result now being handled.
  void bindProvenance(Future<bool> Function() provenance) {
    _provenance = provenance;
  }

  /// Mode first: the bound provenance stays the final validation.
  Future<bool> isCurrent() async {
    if (!await isLive()) return false;
    final provenance = _provenance;
    return provenance == null || await provenance();
  }

  Future<bool> isLive() async {
    final debugData = _debugData;
    if (_retired) return false;
    if (debugData == null) return true;
    try {
      if (!await debugData.readMockDataEnabled()) return !_retired;
    } catch (_) {
      // An unreadable choice may be Mock: never publish Live data over it.
    }
    _retired = true;
    return false;
  }
}

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
/// prevents another from receiving the newest snapshot. A retired invocation
/// is not a failure: it leaves every surface, including STALE, untouched.
Future<void> providerSyncOnce({
  ProviderSyncWorkLoader load = loadProviderSyncWork,
  ProviderSyncFailureLogger logFailure = _logProviderSyncFailure,
  ProviderSyncStaleMarker markWidgetStale =
      HomeWidgetPhoneWidgetSyncService.markExistingRowsStale,
  bool debugBuild = kDebugMode,
  DebugDataPreferenceStore? debugData,
}) async {
  WidgetsFlutterBinding.ensureInitialized();

  final owner = HeadlessLiveOwner(debugBuild: debugBuild, debugData: debugData);
  final poll = AutomaticPollContext.current ?? AutomaticPollContext();
  final ProviderSyncWork? loaded;
  try {
    loaded = await poll.run(() => load(owner));
  } catch (error, stackTrace) {
    logFailure('setup', error, stackTrace);
    // Obsolete failures and rejected snapshots cannot mark newer rows STALE.
    if (!poll.whollySkipped)
      await _attemptProviderSyncStep('widget', () async {
        if (await owner.isCurrent())
          await markWidgetStale(isCurrent: owner.isCurrent);
      }, logFailure);
    return;
  }
  if (loaded == null) return;
  // Effect closures lose the deferred local's promotion: capture non-null work.
  final work = loaded;

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

/// Asks [owner] before Live bindings exist and again after each awaited stage.
Future<ProviderSyncWork?> loadProviderSyncWork(
  HeadlessLiveOwner owner, {
  PhoneLiveBindings Function()? createLive,
  WatchRingPreferenceStore? watchRingStore,
  PhoneWidgetPreferenceStore? widgetStore,
}) async {
  if (!await owner.isLive()) return null;
  final live = (createLive ?? PhoneLiveBindings.create)();
  final poll = AutomaticPollContext.current ?? AutomaticPollContext();
  final alertThresholds = await SecureAlertThresholdPreferenceStore().read();
  if (!await owner.isLive()) return null;
  final DashboardSnapshot loaded;
  try {
    loaded = await poll.run(live.repository.load);
  } catch (error) {
    // Repositories strip an obsolete failure of its stamps, so the credentials
    // this invocation admitted must still own it as well.
    final failure = DashboardSnapshot.empty()
        .withReportingOutcomes(
          error is DashboardLoadException ? error.reportingOutcomes : const [],
        )
        .withConnectionVersions({
          for (final MapEntry(:key, :value) in poll.admittedVersions.entries)
            key: value.values,
        });
    owner.bindProvenance(() => live.repository.isSnapshotCurrent(failure));
    // A load that ends after Mock took over is retired, not a Live failure.
    if (!await owner.isLive()) return null;
    rethrow;
  }
  final snapshot = applyUserAlertSettings(loaded, alertThresholds);
  owner.bindProvenance(() => live.repository.isSnapshotCurrent(snapshot));
  final isCurrent = owner.isCurrent;

  if (!await owner.isLive()) return null;
  if (!await live.repository.isSnapshotCurrent(snapshot))
    throw StateError('Connection changed during refresh.');
  return ProviderSyncWork(
    isCurrent: isCurrent,
    syncWatch: () async {
      if (poll.whollySkipped) return;
      final ringPreferences =
          await (watchRingStore ?? SecureWatchRingPreferenceStore()).read();
      if (!await isCurrent()) return;
      await const MethodChannelWatchSyncService().sync(
        snapshot,
        ringPreferences,
      );
    },
    syncWidget: () async {
      if (poll.whollySkipped) return;
      final widgetPreferences =
          await (widgetStore ?? SecurePhoneWidgetPreferenceStore()).read();
      if (!await isCurrent()) return;
      await HomeWidgetPhoneWidgetSyncService().sync(
        snapshot,
        widgetPreferences,
        isCurrent: isCurrent,
      );
    },
    syncRecoveries: () async {
      var notifications = false;
      try {
        notifications =
            await SecureRecoveryNotificationPreferenceStore().read();
      } catch (_) {
        // Delivery preferences cannot block publication or recovery tracking.
      }
      if (!await isCurrent()) return;
      await syncPlanRecoveries(
        snapshot,
        SecureRecoveryWatchlistStore(),
        LocalRecoveryNotifier(),
        const WorkmanagerRecoveryWakeScheduler(),
        notifications: notifications,
        rethrowFailures: true,
        poll: poll,
        isCurrent: isCurrent,
      );
    },
    syncAlerts:
        () => AlertNotificationDelivery(
          preferences: SecureAlertNotificationPreferenceStore(),
          conditions: SecureAlertConditionStore(),
          notifier: LocalAlertNotifier(),
        ).sync(
          snapshot,
          poll: poll,
          alertThresholds: alertThresholds,
          isCurrent: () async {
            // Rules can change while a headless load or bookkeeping is awaiting.
            // Defer this observation until work captures the new effective rules.
            final currentRules =
                await SecureAlertThresholdPreferenceStore().read();
            if (currentRules.encode() != alertThresholds.encode()) return false;
            return isCurrent();
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
