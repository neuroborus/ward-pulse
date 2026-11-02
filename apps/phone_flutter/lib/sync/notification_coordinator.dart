import 'dart:async';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../settings/notification_permission_preferences.dart';

const phoneNotificationSound = RawResourceAndroidNotificationSound(
  'wardpulse_notification_click',
);

const alertNotificationChannel = AndroidNotificationChannel(
  'wardpulse.alerts',
  'Alert notifications',
  description: 'Your configured usage and budget thresholds.',
  importance: Importance.defaultImportance,
  sound: phoneNotificationSound,
);
const recoveryNotificationChannel = AndroidNotificationChannel(
  'wardpulse.plan_recovery',
  'Plan recovery',
  description: 'A plan window you had run out of is usable again.',
  importance: Importance.high,
  sound: phoneNotificationSound,
);

/// Shared by the foreground host and its notifiers, for the lifetime of main.
/// Background notifiers use readiness only; they never claim or request permission.
final class PhoneNotificationCoordinator {
  PhoneNotificationCoordinator({
    FlutterLocalNotificationsPlugin? plugin,
    NotificationPermissionAttemptStore? attempts,
    Future<void> Function()? initialize,
    Future<bool> Function()? requestPermission,
    Future<bool?> Function()? readStatus,
    Future<bool?> Function()? openSettings,
  }) : plugin = plugin ?? FlutterLocalNotificationsPlugin(),
       _attempts = attempts ?? SecureNotificationPermissionAttemptStore(),
       _initializeEffect = initialize,
       _requestEffect = requestPermission,
       _readStatusEffect = readStatus,
       _openSettingsEffect = openSettings;

  final FlutterLocalNotificationsPlugin plugin;
  final NotificationPermissionAttemptStore _attempts;
  final Future<void> Function()? _initializeEffect;
  final Future<bool> Function()? _requestEffect;
  final Future<bool?> Function()? _readStatusEffect;
  final Future<bool?> Function()? _openSettingsEffect;
  Future<void>? _initializing;
  Future<bool?>? _openingSettings;
  _PermissionOperation? _pending;
  bool _handled = false;

  AndroidFlutterLocalNotificationsPlugin? get android =>
      plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();

  Future<void> ensureReady() =>
      _initializing ??= _initialize().onError((Object error, stack) {
        _initializing = null;
        Error.throwWithStackTrace(error, stack);
      });

  /// Reads app-global enablement; null means unknown. Enabled does not establish
  /// channel policy or guarantee delivery.
  /// Inspection never initializes channels or claims a permission attempt.
  Future<bool?> readAndroidNotificationStatus() async {
    final effect = _readStatusEffect;
    if (effect != null) return effect();
    return await android?.areNotificationsEnabled();
  }

  /// The result describes navigation only, never a permission grant.
  Future<bool?> openAndroidNotificationSettings() =>
      _openingSettings ??= _openSettings().whenComplete(() {
        _openingSettings = null;
      });

  Future<bool?> _openSettings() async {
    final effect = _openSettingsEffect;
    if (effect != null) return effect();
    return await android?.openAppNotificationSettings();
  }

  Future<void> _initialize() async {
    final effect = _initializeEffect;
    if (effect != null) return effect();
    await plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
    );
    // Android preserves existing channel sound, blocking and user-selected
    // importance.
    await android?.createNotificationChannel(alertNotificationChannel);
    await android?.createNotificationChannel(recoveryNotificationChannel);
  }

  /// Null means no request was dispatched. Only a current foreground UI owner
  /// may supply eligibility; never call this from readiness or delivery work.
  Future<bool?> requestForeground({
    required bool Function() isEligible,
    bool automatic = false,
  }) async {
    if (!isEligible()) return null;
    final previous = _pending;
    if (previous != null) {
      final result = await previous.done.future;
      if (previous.dispatched) return result;
      // An aborted automatic preparation must not eat an explicit retry, or a
      // newer foreground owner's eligible bootstrap.
      return requestForeground(isEligible: isEligible, automatic: automatic);
    }
    final operation = _PermissionOperation();
    _pending = operation;
    bool? result;
    try {
      await ensureReady();
      if (!isEligible()) return null;
      if (automatic) {
        if (_handled) return null;
        final handled = await _attempts.read();
        if (!isEligible() || handled) return null;
        // A crash after this durable claim can consume the automatic opportunity.
        await _attempts.write(true);
        if (!isEligible()) {
          // Only our exclusive, definitely undispatched claim can be released.
          await _attempts.write(false);
          return null;
        }
      }
      if (!isEligible()) return null;
      operation.dispatched = true;
      _handled = true;
      // Attach error handling before any later storage await.
      final request = Future<bool>.sync(
        _requestEffect ?? _requestAndroid,
      ).onError((_, _) => false);
      if (!automatic) {
        try {
          await _attempts.write(true);
        } catch (_) {
          // An explicit retry remains available when bookkeeping is unavailable.
        }
      }
      result = await request;
      return result;
    } catch (_) {
      // Fail closed before dispatch; a dispatched error stays handled.
      result = operation.dispatched ? false : null;
      return result;
    } finally {
      _pending = null;
      operation.done.complete(result);
    }
  }

  Future<bool> _requestAndroid() async =>
      await android?.requestNotificationsPermission() ?? false;
}

final class _PermissionOperation {
  final done = Completer<bool?>();
  bool dispatched = false;
}
