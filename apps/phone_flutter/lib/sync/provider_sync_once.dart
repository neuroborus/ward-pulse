import 'dart:developer' as developer;

import 'package:flutter/widgets.dart';

import '../dashboard/apply_alert_settings.dart';
import '../dashboard/dashboard_models.dart';
import '../dashboard/dashboard_repository.dart';
import '../dashboard/phone_live_bindings.dart';
import '../dashboard/plan_recoveries.dart';
import '../providers/connection_lifecycle.dart';
import '../settings/alert_notification_preferences.dart';
import '../settings/alert_threshold_preferences.dart';
import '../settings/recovery_notification_preferences.dart';
import '../settings/watch_ring_preferences.dart';
import '../widget/phone_widget_preferences.dart';
import '../widget/phone_widget_sync.dart';
import 'data_mode.dart';
import 'manual_refresh_window.dart';
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

/// One Live operation, with credential/snapshot provenance bound after loading.
final class HeadlessLiveOwner {
  HeadlessLiveOwner(this.operation);

  final DataModeOperation operation;
  var _modeRetired = false;
  var _provenanceRetired = false;
  Future<bool> Function()? _provenance;

  void bindProvenance(Future<bool> Function() provenance) {
    _provenance = provenance;
  }

  Future<bool> isCurrent() async =>
      await isLive() && await _isProvenanceCurrent();

  Future<bool> _isProvenanceCurrent() async {
    if (_provenanceRetired) return false;
    final provenance = _provenance;
    if (provenance == null) return true;
    try {
      if (await provenance()) return !_provenanceRetired;
    } catch (_) {
      _provenanceRetired = true;
      rethrow;
    }
    _provenanceRetired = true;
    return false;
  }

  Future<bool> isLive() async {
    if (_modeRetired || operation.mode.synthetic) return false;
    if (await operation.isCurrent()) return !_modeRetired;
    _modeRetired = true;
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
/// leaves every surface, including STALE, untouched.
Future<void> providerSyncOnce({
  ProviderSyncWorkLoader load = loadProviderSyncWork,
  ProviderSyncFailureLogger logFailure = _logProviderSyncFailure,
  ProviderSyncStaleMarker markWidgetStale =
      HomeWidgetPhoneWidgetSyncService.markExistingRowsStale,
  DataModeAuthority? modeAuthority,
}) async {
  WidgetsFlutterBinding.ensureInitialized();

  final DataModeOperation operation;
  try {
    operation =
        await (modeAuthority ?? MethodChannelDataModeAuthority()).begin();
  } on DataModeRetired {
    return;
  } catch (error, stackTrace) {
    logFailure('setup', error, stackTrace);
    return;
  }
  if (operation.mode.synthetic) return;

  final owner = HeadlessLiveOwner(operation);
  final poll = AutomaticPollContext.current ?? AutomaticPollContext();
  await operation.run(() async {
    final ProviderSyncWork? loaded;
    try {
      loaded = await poll.run(() => load(owner));
    } catch (error, stackTrace) {
      await _attemptProviderSyncStep('setup', () async {
        if (!await owner.isLive()) return;
        logFailure('setup', error, stackTrace);
        if (!poll.whollySkipped) {
          await _attemptProviderSyncStep('widget', () async {
            if (await owner.isCurrent()) {
              await markWidgetStale(isCurrent: owner.isCurrent);
            }
          }, logFailure);
        }
      }, logFailure);
      return;
    }
    if (loaded == null) return;
    final work = loaded;

    Future<void> step(String name, Future<void> Function() effect) =>
        _attemptProviderSyncStep(name, () async {
          if (await owner.isLive() && await work.isCurrent()) await effect();
        }, logFailure);

    // Surfaces first, then bookkeeping. A failed surface never blocks its sibling.
    await step('watch', work.syncWatch);
    await step('widget', work.syncWidget);
    await step('recovery', work.syncRecoveries);
    await step('alerts', work.syncAlerts);
  });
}

/// Asks [owner] before Live bindings exist and again after each awaited stage.
Future<ProviderSyncWork?> loadProviderSyncWork(
  HeadlessLiveOwner owner, {
  PhoneLiveBindings Function()? createLive,
  WatchRingPreferenceStore? watchRingStore,
  PhoneWidgetPreferenceStore? widgetStore,
  ReadExhaustedWindows readWindows = exhaustedWindows,
}) async {
  if (!await owner.isLive()) return null;
  final live = (createLive ?? PhoneLiveBindings.create)();
  // Paused builds retire saved Claude plan credentials before provider work.
  if (!await owner.operation.guard(live.retirePausedClaudePlan)) return null;
  final poll = AutomaticPollContext.current ?? AutomaticPollContext();
  final alertThresholds = await SecureAlertThresholdPreferenceStore().read();
  if (!await owner.isLive()) return null;
  final DashboardSnapshot loaded;
  try {
    loaded = await poll.run(live.repository.load);
  } catch (error) {
    // Keep rejected-load absence evidence alongside every admitted credential.
    final failure = DashboardSnapshot.empty()
        .withReportingOutcomes(
          error is DashboardLoadException ? error.reportingOutcomes : const [],
        )
        .withConnectionVersions(
          mergeConnectionVersions([
            if (error is DashboardLoadException) error.connectionVersions,
            {
              for (final MapEntry(:key, :value)
                  in poll.admittedVersions.entries)
                key: value.values,
            },
          ]),
          snapshotOrdering:
              error is DashboardLoadException ? error.snapshotOrdering : null,
        );
    owner.bindProvenance(() => live.repository.isSnapshotCurrent(failure));
    // A load that ends after its generation retires cannot mark STALE.
    if (!await owner.isLive()) return null;
    rethrow;
  }
  final snapshot = applyUserAlertSettings(loaded, alertThresholds);
  owner.bindProvenance(() => live.repository.isSnapshotCurrent(snapshot));
  final isCurrent = owner.isCurrent;

  if (!await owner.isLive()) return null;
  if (!await owner._isProvenanceCurrent()) {
    throw StateError('Connection changed during refresh.');
  }
  return ProviderSyncWork(
    isCurrent: owner._isProvenanceCurrent,
    syncWatch: () async {
      if (poll.whollySkipped) return;
      final ringPreferences =
          await (watchRingStore ?? SecureWatchRingPreferenceStore()).read();
      // A claim whose credential retired during the poll no longer owns its
      // cadence and cannot hold the healthy siblings in cooldown.
      final owned = <DateTime>[];
      for (final MapEntry(key: connection, value: at)
          in poll.automaticAt.entries.toList()) {
        final version =
            poll.admittedVersions[connection] ??
            poll.skipped[connection]?.version;
        if (version == null) continue;
        try {
          if (!await live.repository.ownsAutomaticCadence(
            connection,
            version,
          )) {
            continue;
          }
        } catch (_) {
          // Unavailable proof keeps the floor.
        }
        owned.add(at);
      }
      if (!await isCurrent()) return;
      await MethodChannelWatchSyncService(
        claudePlanPaused: live.claudePlanPaused,
      ).sync(
        snapshot,
        ringPreferences,
        // A publication that is not wholly skipped follows an admitted claim.
        // Its confirmed anchor, which native corrects after a clock rollback,
        // is the owned attempt; a retained report's time may predate the
        // rollback.
        manualRefreshAnchorAt: ManualRefreshWindow.anchorAt(
          reportAt: owned.isEmpty ? snapshot.generatedAt : null,
          attempts: owned,
        ),
        isCurrent: isCurrent,
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
      final preferences = SecureRecoveryNotificationPreferenceStore();
      var notifications = false;
      try {
        notifications = await preferences.read();
      } catch (_) {
        // Delivery preferences cannot block publication or recovery tracking.
      }
      if (!await isCurrent()) return;
      final delivery = RecoveryDeliveryAdmission(
        preferences: preferences,
        platform: live.cachePlatform,
      );
      await syncPlanRecoveries(
        snapshot,
        SecureRecoveryWatchlistStore(
          postLedger: NativeRecoveryPostLedger(platform: live.cachePlatform),
        ),
        LocalRecoveryNotifier(),
        const WorkmanagerRecoveryWakeScheduler(),
        notifications: notifications,
        // The foreground saves the switch. Its revision and this report's
        // provenance are proven in one native step; the owner's sticky proof
        // is not retired by a save.
        admitDelivery:
            () => delivery.admit(
              () async =>
                  await owner.isLive() &&
                  await live.repository.isSnapshotCurrent(snapshot),
            ),
        readWindows: readWindows,
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
