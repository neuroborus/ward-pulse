import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../dashboard/dashboard_models.dart';
import '../dashboard/plan_recoveries.dart';
import 'notification_coordinator.dart';

/// Tells the reader a plan window is usable again.
///
/// An interface, not a channel call, for the same reason `WatchSyncService` is
/// one: host tests carry no Android to post to.
abstract interface class RecoveryNotifier {
  Future<void> notify(PlanRecovery recovery);

  /// Asks Android for permission to post at all (13+), and answers whether it
  /// may now.
  ///
  /// Foreground transport only. DashboardHost coordinates startup and explicit
  /// Settings retries; the poll that posts never requests permission.
  Future<bool> requestPermission();
}

/// Says nothing, for hosts with nowhere to say it: tests, and any build without
/// the Android side wired up.
final class SilentRecoveryNotifier implements RecoveryNotifier {
  const SilentRecoveryNotifier();

  @override
  Future<void> notify(PlanRecovery recovery) async {}

  @override
  Future<bool> requestPermission() async => true;
}

/// Posts through the local notification plugin.
///
/// A plugin rather than a channel of our own: the wake that matters fires with
/// the app closed, in the WorkManager background isolate, and only pub plugins
/// are registered there. An app-level channel lives in the Activity's engine
/// alone.
final class LocalRecoveryNotifier implements RecoveryNotifier {
  LocalRecoveryNotifier({
    FlutterLocalNotificationsPlugin? plugin,
    PhoneNotificationCoordinator? coordinator,
  }) : _coordinator =
           coordinator ?? PhoneNotificationCoordinator(plugin: plugin);

  final PhoneNotificationCoordinator _coordinator;

  @override
  Future<void> notify(PlanRecovery recovery) async {
    await _coordinator.ensureReady();
    await _coordinator.plugin.show(
      id: recoveryNotificationId(recovery),
      title: recoveryNotificationTitle(recovery),
      body: recoveryNotificationBody,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          recoveryNotificationChannel.id,
          recoveryNotificationChannel.name,
          channelDescription: recoveryNotificationChannel.description,
          sound: phoneNotificationSound,
          category: AndroidNotificationCategory.status,
          // Preserve the recovery channel's existing importance: a window the
          // reader had exhausted is usable again.
          importance: Importance.high,
          priority: Priority.high,
        ),
      ),
    );
  }

  @override
  Future<bool> requestPermission() async {
    await _coordinator.ensureReady();
    final granted =
        await _coordinator.android?.requestNotificationsPermission();
    // Null means no Android implementation answered — nothing was refused, so
    // the switch has no bad news to report.
    return granted ?? true;
  }
}

/// What a recovery says on a locked screen: the family and the window's own
/// name, nothing else.
///
/// Family first, because two subscriptions can both call a window "Weekly
/// plan" and the reader is being interrupted to learn which one is back. Kept
/// out of the plugin call so the rule in `SECURITY_MODEL.md` — no credentials,
/// no account ids, no spend, no raw provider fields — is something a test can
/// read rather than something a reviewer has to.
String recoveryNotificationTitle(PlanRecovery recovery) {
  return '${providerDisplayLabel(recovery.provider)} · ${recovery.label}';
}

/// The whole message. A recovery has one thing to say and says it.
const recoveryNotificationBody = 'Usable again.';

/// The notification a window owns, so a second telling replaces the first
/// rather than stacking beside it. A replacement can still alert again; a
/// stable identity does not prove no repost or exactly-once delivery.
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
