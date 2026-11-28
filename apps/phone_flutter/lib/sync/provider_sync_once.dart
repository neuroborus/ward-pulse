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

/// Pauses before a headless publication reads the settled settings revision
/// again while a save is in flight.
typedef SettingsSaveWait = Future<void> Function();

Future<void> _awaitSettingsSave() =>
    Future<void>.delayed(const Duration(milliseconds: 250));

/// How many pauses a headless publication waits through for a save in flight.
const _settingsSaveWaits = 8;

/// Publications under a newer settled revision after a surface's refusal.
const _settingsRetries = 2;

/// Publishes a surface's [DashboardSnapshot] under a claim; `false` when
/// native refused it.
typedef _SettledPublication =
    Future<bool> Function(PhoneWidgetPublicationInput, DashboardSnapshot);

/// One Live operation, with credential/snapshot provenance bound after loading.
final class HeadlessLiveOwner {
  HeadlessLiveOwner(this.operation);

  final DataModeOperation operation;

  /// The launcher claim taken before setup read settings or providers.
  PhoneWidgetPublicationInput? publication;
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
      // Claimed before any fallible setup, so a failure marks only the
      // committed rows it observed.
      owner.publication = await PhoneWidgetPublicationInput.begin();
      loaded = await poll.run(() => load(owner));
    } catch (error, stackTrace) {
      await _attemptProviderSyncStep('setup', () async {
        if (!await owner.isLive()) return;
        logFailure('setup', error, stackTrace);
        final publication = owner.publication;
        if (!poll.whollySkipped && publication != null) {
          await _attemptProviderSyncStep('widget', () async {
            if (!await owner.isCurrent()) return;
            await publication.run(
              () => markWidgetStale(isCurrent: owner.isCurrent),
            );
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
  SettingsSaveWait awaitSettingsSave = _awaitSettingsSave,
}) async {
  if (!await owner.isLive()) return null;
  final live = (createLive ?? PhoneLiveBindings.create)();
  // Paused builds retire saved Claude plan credentials before provider work.
  if (!await owner.operation.guard(live.retirePausedClaudePlan)) return null;
  final poll = AutomaticPollContext.current ?? AutomaticPollContext();
  // Ordered before the settings and provider reads it publishes.
  final publication =
      owner.publication ??= await PhoneWidgetPublicationInput.begin();
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
  // Retained cadence-skipped input is accepted too; a newer acceptance in any
  // engine refuses this load's publications.
  final accepted = await publication.accept(snapshot);

  // A refusal caused only by a settings save is never final: a surface is
  // rebuilt from [loaded] with the settings read again and sent under the
  // revision the saves settled, once those in flight settle. A refusal under
  // an unchanged revision, such as a newer accepted load's, is final.
  Future<void> retryUnderSettledSettings(_SettledPublication publish) async {
    if ((publication.load ?? -1) < 0) return;
    var revision = publication.settingsRevision;
    for (var retry = 0; retry < _settingsRetries; retry++) {
      if (!await isCurrent()) return;
      final settled = await _settledRevision(awaitSettingsSave, isCurrent);
      if (settled == null || settled == revision) return;
      revision = settled;
      final rules = await SecureAlertThresholdPreferenceStore().read();
      if (!await isCurrent()) return;
      if (await publish(
        publication.withSettingsRevision(settled),
        applyUserAlertSettings(loaded, rules),
      )) {
        return;
      }
    }
  }

  return ProviderSyncWork(
    isCurrent: owner._isProvenanceCurrent,
    syncWatch: () async {
      final watchSync = MethodChannelWatchSyncService(
        claudePlanPaused: live.claudePlanPaused,
      );
      // A newer acceptance in any engine owns Wear, as it owns the widget.
      if (!accepted) return;
      // A cadence-skipped poll still seeds Wear's first v10 summary, after an
      // upgrade or a mode transition, from the retained input.
      if (poll.whollySkipped && await watchSync.isEstablished()) return;
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
      // A publication that is not wholly skipped follows an admitted claim.
      // Its confirmed anchor, which native corrects after a clock rollback,
      // is the owned attempt; a retained report's time may predate the
      // rollback.
      final anchorAt = ManualRefreshWindow.anchorAt(
        reportAt: owned.isEmpty ? snapshot.generatedAt : null,
        attempts: owned,
      );
      // The ring choice was read after this load began, so a later save that
      // may change the summary, or a newer accepted load, refuses it natively.
      Future<bool> send(
        PhoneWidgetPublicationInput claim,
        DashboardSnapshot input,
        WatchRingPreferences rings,
      ) async {
        try {
          await claim.run(
            () => watchSync.sync(
              input,
              rings,
              manualRefreshAnchorAt: anchorAt,
              isCurrent: isCurrent,
            ),
          );
        } on WatchSummarySuperseded {
          return false;
        }
        return true;
      }

      if (await send(publication, snapshot, ringPreferences)) return;
      await retryUnderSettledSettings((claim, rebuilt) async {
        final rings =
            await (watchRingStore ?? SecureWatchRingPreferenceStore()).read();
        return !await isCurrent() || await send(claim, rebuilt, rings);
      });
    },
    syncWidget: () async {
      // An upgrade, a mode return or a widget still owed a frame publishes
      // the retained input once, even when cadence skipped every provider.
      if (!accepted ||
          (poll.whollySkipped && await publication.isEstablished())) {
        return;
      }
      final preferenceStore = widgetStore ?? SecurePhoneWidgetPreferenceStore();
      final widgetPreferences = await preferenceStore.read();
      if (!await isCurrent()) return;
      Future<bool> publish(
        PhoneWidgetPublicationInput claim,
        DashboardSnapshot input,
        PhoneWidgetPreferences preferences,
      ) {
        return claim.run(
          () => HomeWidgetPhoneWidgetSyncService().sync(
            input,
            preferences,
            isCurrent: isCurrent,
          ),
        );
      }

      if (await publish(publication, snapshot, widgetPreferences)) return;
      await retryUnderSettledSettings((claim, rebuilt) async {
        final preferences = await preferenceStore.read();
        return !await isCurrent() || await publish(claim, rebuilt, preferences);
      });
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

/// The settled settings revision, read again after each [wait] while a save is
/// in flight; `null` without a native order, once [isCurrent] retires, or
/// when a save outlasts the bound.
Future<int?> _settledRevision(
  SettingsSaveWait wait,
  Future<bool> Function() isCurrent,
) async {
  var waits = 0;
  while (true) {
    final revision =
        (await PhoneWidgetPublicationInput.begin()).settingsRevision;
    if (revision == null) return null;
    if (revision >= 0) return revision;
    if (waits++ == _settingsSaveWaits || !await isCurrent()) return null;
    await wait();
  }
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
