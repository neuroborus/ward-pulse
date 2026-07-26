import 'dart:io' show Platform;
import 'dart:ui' show DartPluginRegistrant;

import 'package:workmanager/workmanager.dart';

import 'poll_cadence.dart';
import 'provider_sync_once.dart';

/// WorkManager-backed sync after Android reclaims the UI isolate.
///
/// Cadence is [PollCadence.headlessInterval] (at least 15 minutes). While the
/// app process is alive, the in-process timer still honors the full 5–60
/// minute slider.
abstract final class HeadlessProviderSync {
  static const uniqueName = 'wardpulse.providerSync';
  static const taskName = 'providerSync';

  static Future<void> ensureInitialized() async {
    if (!_isAndroidHost) {
      return;
    }
    await Workmanager().initialize(callbackDispatcher);
  }

  /// Enqueue or replace the periodic headless sync for [preferred] slider value.
  static Future<void> schedule(Duration preferred) async {
    if (!_isAndroidHost) {
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

  /// Real Android OS host — not Flutter's simulated [defaultTargetPlatform]
  /// (tests on Linux report Android as the target but are not Android hosts).
  static bool get _isAndroidHost {
    try {
      return Platform.isAndroid;
    } catch (_) {
      return false;
    }
  }
}

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    // Background isolate — register plugins before secure storage / channels.
    DartPluginRegistrant.ensureInitialized();
    if (task == HeadlessProviderSync.taskName) {
      await providerSyncOnce();
    }
    return true;
  });
}
