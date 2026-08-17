import 'dart:io' show Platform;
import 'dart:ui' show DartPluginRegistrant;

import 'package:workmanager/workmanager.dart';

import 'poll_cadence.dart';
import 'provider_sync_once.dart';
import 'recovery_wake.dart';

/// WorkManager-backed sync after Android reclaims the UI isolate.
///
/// Cadence is [PollCadence.headlessInterval] (at least 15 minutes). While the
/// app process is alive, the in-process timer still honors the full 5–60
/// minute slider.
abstract final class HeadlessProviderSync {
  static const uniqueName = 'wardpulse.providerSync';
  static const taskName = 'providerSync';

  static Future<void> ensureInitialized() async {
    if (!isAndroidHost) {
      return;
    }
    await Workmanager().initialize(callbackDispatcher);
  }

  /// Enqueue or replace the periodic headless sync for [preferred] slider value.
  static Future<void> schedule(Duration preferred) async {
    if (!isAndroidHost) {
      return;
    }
    await Workmanager().registerPeriodicTask(
      uniqueName,
      taskName,
      frequency: PollCadence.headlessInterval(preferred),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
      constraints: Constraints(networkType: NetworkType.connected),
    );
  }
}

/// Real Android OS host — not Flutter's simulated `defaultTargetPlatform`
/// (tests on Linux report Android as the target but are not Android hosts).
///
/// Anything that schedules work asks this first: on a host with no WorkManager,
/// booking is not a failure to report, it is a thing that does not apply.
bool get isAndroidHost {
  try {
    return Platform.isAndroid;
  } catch (_) {
    return false;
  }
}

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    // Background isolate — register plugins before secure storage / channels.
    DartPluginRegistrant.ensureInitialized();
    // Both names run the same poll: the periodic tick, and the wake booked for
    // a spent window's reset. A name without a branch here would "succeed"
    // without doing anything at all.
    if (task == HeadlessProviderSync.taskName ||
        task == WorkmanagerRecoveryWakeScheduler.taskName) {
      await providerSyncOnce();
    }
    return true;
  });
}
