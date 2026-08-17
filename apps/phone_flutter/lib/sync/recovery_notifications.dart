import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../dashboard/dashboard_models.dart';
import '../dashboard/plan_recoveries.dart';

/// Tells the reader a plan window is usable again.
///
/// An interface, not a channel call, for the same reason `WatchSyncService` is
/// one: host tests carry no Android to post to.
abstract interface class RecoveryNotifier {
  Future<void> notify(PlanRecovery recovery);
}

/// Says nothing, for hosts with nowhere to say it: tests, and any build without
/// the Android side wired up.
final class SilentRecoveryNotifier implements RecoveryNotifier {
  const SilentRecoveryNotifier();

  @override
  Future<void> notify(PlanRecovery recovery) async {}
}

/// Posts through the local notification plugin.
///
/// A plugin rather than a channel of our own: the wake that matters fires with
/// the app closed, in the WorkManager background isolate, and only pub plugins
/// are registered there. An app-level channel lives in the Activity's engine
/// alone.
final class LocalRecoveryNotifier implements RecoveryNotifier {
  LocalRecoveryNotifier({FlutterLocalNotificationsPlugin? plugin})
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  /// One channel for the one thing this product interrupts a reader for.
  static const _channelId = 'wardpulse.plan_recovery';
  static const _channelName = 'Plan recovery';
  static const _channelDescription =
      'A plan window you had run out of is usable again.';

  final FlutterLocalNotificationsPlugin _plugin;
  bool _ready = false;

  @override
  Future<void> notify(PlanRecovery recovery) async {
    await _ensureReady();
    await _plugin.show(
      id: recoveryNotificationId(recovery),
      // Family first, because two subscriptions can both call a window
      // "Weekly plan" and the reader is being interrupted to learn which.
      title: '${providerDisplayLabel(recovery.provider)} · ${recovery.label}',
      body: 'Usable again.',
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription: _channelDescription,
          category: AndroidNotificationCategory.status,
          // High, because this is the one thing the product interrupts for: a
          // window the reader has been waiting on is usable again. At the
          // default the notification would wait quietly in the shade, which is
          // the opposite of what the phase decided it is worth.
          importance: Importance.high,
          priority: Priority.high,
        ),
      ),
    );
  }

  Future<void> _ensureReady() async {
    if (_ready) {
      return;
    }
    await _plugin.initialize(
      settings: const InitializationSettings(
        // The launcher mark, because the product has no separate status icon.
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
    );
    _ready = true;
  }
}

/// The notification a window owns, so a second telling replaces the first
/// rather than stacking beside it — which is what makes a repeat harmless, and
/// a repeat is what the reporting order deliberately risks.
///
/// Computed here rather than taken from `hashCode`: Dart does not promise a
/// string keeps its hash between runs, and an id that drifted across launches
/// would leave the reader with two notifications for one window.
int recoveryNotificationId(PlanRecovery recovery) {
  // FNV-1a, folded into the positive 31 bits an Android notification id uses.
  var hash = 0x811c9dc5;
  final key = '${recovery.accountId}|${recovery.allowanceId}';
  for (final unit in key.codeUnits) {
    hash = ((hash ^ unit) * 0x01000193) & 0xffffffff;
  }
  return hash & 0x7fffffff;
}
