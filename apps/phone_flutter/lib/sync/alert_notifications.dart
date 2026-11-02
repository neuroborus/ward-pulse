import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../dashboard/dashboard_models.dart';
import '../settings/alert_notification_preferences.dart';
import 'notification_coordinator.dart';

abstract interface class AlertConditionStore {
  Future<bool> read(AlertConditionKey key);
  Future<void> write(AlertConditionKey key, bool consumed);
}

final class SecureAlertConditionStore implements AlertConditionStore {
  SecureAlertConditionStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;
  String _key(AlertConditionKey key) =>
      'wardpulse.alerts.consumed.${alertNotificationTag(key)}';

  @override
  Future<bool> read(AlertConditionKey key) async {
    final stored = await _storage.read(key: _key(key));
    if (stored == null) return false;
    if (stored == 'true') return true;
    throw const FormatException('Invalid alert bookkeeping.');
  }

  @override
  Future<void> write(AlertConditionKey key, bool consumed) =>
      consumed
          ? _storage.write(key: _key(key), value: 'true')
          : _storage.delete(key: _key(key));
}

final class DisabledAlertConditionStore implements AlertConditionStore {
  const DisabledAlertConditionStore();

  @override
  Future<bool> read(AlertConditionKey key) async => true;

  @override
  Future<void> write(AlertConditionKey key, bool consumed) async {}
}

abstract interface class AlertNotifier {
  /// Initializes the plugin and checks permission without requesting it.
  Future<bool> canPost();
  Future<bool> requestPermission();
  Future<void> notify(AlertConditionKey key, {required String title});
}

final class SilentAlertNotifier implements AlertNotifier {
  const SilentAlertNotifier();

  @override
  Future<bool> canPost() async => false;
  @override
  Future<bool> requestPermission() async => true;
  @override
  Future<void> notify(AlertConditionKey key, {required String title}) async {}
}

final class LocalAlertNotifier implements AlertNotifier {
  LocalAlertNotifier({
    FlutterLocalNotificationsPlugin? plugin,
    PhoneNotificationCoordinator? coordinator,
  }) : _coordinator =
           coordinator ?? PhoneNotificationCoordinator(plugin: plugin);

  final PhoneNotificationCoordinator _coordinator;

  @override
  Future<bool> canPost() async {
    await _coordinator.ensureReady();
    return await _coordinator.android?.areNotificationsEnabled() ?? false;
  }

  @override
  Future<bool> requestPermission() async {
    await _coordinator.ensureReady();
    return await _coordinator.android?.requestNotificationsPermission() ??
        false;
  }

  // canPost prepares the plugin before the caller's final ownership/preference
  // guard. There is no further asynchronous setup between that guard and show.
  @override
  Future<void> notify(AlertConditionKey key, {required String title}) =>
      _coordinator.plugin.show(
        id: alertNotificationId,
        title: title,
        body: alertNotificationBody,
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            alertNotificationChannel.id,
            alertNotificationChannel.name,
            channelDescription: alertNotificationChannel.description,
            tag: alertNotificationTag(key),
            category: AndroidNotificationCategory.status,
          ),
        ),
      );
}

const alertNotificationId = 0;
const alertNotificationBody = 'Reached your alert threshold.';

/// Canonical typed-key JSON avoids delimiter ambiguity. This is addressing,
/// never eligibility; account identifiers do not appear in notification text.
String alertNotificationTag(AlertConditionKey key) =>
    'wardpulse.alert.${sha256.convert(utf8.encode(jsonEncode(key.toJson())))}';

String alertNotificationTitle(
  DashboardSnapshot snapshot,
  AlertConditionKey key,
) {
  final target = key.target;
  var label = switch (target) {
    BudgetAlertTarget(:final period) => switch (period) {
      AlertBudgetPeriod.today => 'Today budget',
      AlertBudgetPeriod.week => 'Weekly budget',
      AlertBudgetPeriod.month => 'Monthly budget',
    },
    AllowanceAlertTarget(:final source) =>
      source == AllowanceSource.plan ? 'Plan window' : 'Purchased usage',
  };
  if (target is AllowanceAlertTarget) {
    ProviderSnapshot? account;
    for (final candidate in snapshot.accounts) {
      if (candidate.provider != key.provider ||
          candidate.accountId != key.accountId)
        continue;
      if (candidate.connection == key.connection) {
        account = candidate;
        break;
      }
      // A legacy account can supply copy only when no exact owner is present.
      if (candidate.connection == null) account ??= candidate;
    }
    if (account != null) {
      for (final allowance in account.allowances) {
        if (allowance.source == target.source &&
            allowance.id == target.id &&
            allowance.label.trim().isNotEmpty)
          label = allowance.label.trim();
      }
    }
  }
  return '${providerDisplayLabel(key.provider)} · $label';
}

Future<bool> _alwaysCurrent() async => true;
bool _alwaysAccepted() => true;

/// Consume before posting, with per-condition failure isolation. A successful
/// claim followed by plugin failure/crash can lose delivery until positive clear.
/// The queue is isolate-local: secure storage has no atomic cross-isolate claim,
/// so overlapping workers can duplicate attempts or race clear/consumed writes.
final class AlertNotificationDelivery {
  const AlertNotificationDelivery({
    required this.preferences,
    required this.conditions,
    required this.notifier,
  });

  final AlertNotificationPreferenceStore preferences;
  final AlertConditionStore conditions;
  final AlertNotifier notifier;
  static Future<void>? _pending;

  /// [isDeliveryEnabled] gates posting only; accepted observations still update
  /// consumed markers while delivery is off.
  Future<void> sync(
    DashboardSnapshot snapshot, {
    bool mockData = false,
    Future<bool> Function() isCurrent = _alwaysCurrent,
    bool Function() isAccepted = _alwaysAccepted,
    bool Function() isDeliveryEnabled = _alwaysAccepted,
  }) async {
    if (mockData) return;
    final previous = _pending;
    final done = Completer<void>();
    _pending = done.future;
    try {
      if (previous != null) await previous;
      for (final condition in snapshot.alertConditions) {
        if (condition.state == AlertConditionState.unknown) continue;
        try {
          if (!isAccepted() || !await isCurrent() || !isAccepted()) return;
          if (condition.state == AlertConditionState.clear) {
            await conditions.write(condition.key, false);
            continue;
          }
          if (await conditions.read(condition.key)) continue;
          if (!await isCurrent() || !isAccepted()) return;
          await conditions.write(condition.key, true);
          // Muted/denied crossings are consumed too: enabling delivery later
          // never replays a backlog. A preference read failure cannot post.
          if (!await notifier.canPost()) continue;
          if (!await preferences.read() ||
              !await isCurrent() ||
              !isDeliveryEnabled() ||
              !isAccepted())
            continue;
          await notifier.notify(
            condition.key,
            title: alertNotificationTitle(snapshot, condition.key),
          );
        } catch (_) {
          // A failed read/claim suppresses this condition; siblings still run.
        }
      }
    } finally {
      if (identical(_pending, done.future)) _pending = null;
      done.complete();
    }
  }
}
