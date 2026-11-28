import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../providers/connection_lifecycle.dart';
import '../sync/data_mode.dart';

/// Whether WardPulse may say a plan window is usable again.
///
/// One independent recovery switch for all connections. Threshold notification
/// delivery has its own preference; neither control changes recovery tracking.
abstract interface class RecoveryNotificationPreferenceStore {
  Future<bool> read();

  Future<void> write(bool enabled);
}

final class SecureRecoveryNotificationPreferenceStore
    implements RecoveryNotificationPreferenceStore {
  /// A save through [platform] is ordered for [RecoveryDeliveryAdmission] in
  /// every engine of this process; without it, a save is unordered.
  SecureRecoveryNotificationPreferenceStore({
    FlutterSecureStorage? storage,
    ConnectionCachePlatform? platform,
  }) : _storage = storage ?? const FlutterSecureStorage(),
       _platform = platform;

  static const _key = 'wardpulse.recovery.notify';

  final FlutterSecureStorage _storage;
  final ConnectionCachePlatform? _platform;

  @override
  Future<bool> read() async =>
      recoveryNotificationsFrom(await _storage.read(key: _key));

  @override
  Future<void> write(bool enabled) async {
    final platform = _platform;
    if (platform == null) {
      return _storage.write(key: _key, value: enabled.toString());
    }
    final token = await platform.invoke('beginRecoveryPreferenceWrite', {});
    try {
      await _storage.write(key: _key, value: enabled.toString());
    } finally {
      await platform.invoke('finishRecoveryPreferenceWrite', {'token': token});
    }
  }
}

/// A settled recovery switch revision the current delivery admission proves.
///
/// Native provenance checks run in its zone carry it, so the saved choice, the
/// Live mode admission and the report's provenance are checked in one native
/// step.
final class RecoveryPreferenceRevision {
  RecoveryPreferenceRevision._(this.value, this.generation);

  static final _zoneKey = Object();

  static RecoveryPreferenceRevision? get current =>
      Zone.current[_zoneKey] as RecoveryPreferenceRevision?;

  final int value;

  /// The posting operation's mode generation, or `null` for unscoped work.
  final int? generation;
  var _proven = false;

  /// Records that a native provenance check carried this revision.
  void markProven() => _proven = true;
}

/// Resolves a recovery post against the saved switch and an observation proof
/// together, for an isolate that does not own the switch.
final class RecoveryDeliveryAdmission {
  const RecoveryDeliveryAdmission({
    required this.preferences,
    required this.platform,
  });

  final RecoveryNotificationPreferenceStore preferences;
  final ConnectionCachePlatform platform;

  /// `true` posts, `false` mutes, and `null` leaves the window for a later
  /// look because [isCurrent], the choice or the mode changed before
  /// admission. A switch that has closed admission refuses the post even while
  /// the batch lease keeps the outgoing generation open.
  Future<bool?> admit(Future<bool> Function() isCurrent) async {
    final Object? settled;
    try {
      settled = await platform.invoke('readRecoveryPreferenceRevision', {});
    } on MissingPluginException {
      // No native engine orders saves on this host.
      if (!await _enabled()) return false;
      return await isCurrent() ? true : null;
    }
    // A save in flight decides; a later look reads its outcome.
    if (settled is! int) return null;
    // Read after the revision, so a save finishing later retires it.
    if (!await _enabled()) return false;
    final generation = DataModeOperation.current?.generation;
    final revision = RecoveryPreferenceRevision._(settled, generation);
    final current = await runZoned(
      isCurrent,
      zoneValues: {RecoveryPreferenceRevision._zoneKey: revision},
    );
    if (!current) return null;
    if (revision._proven) return true;
    // A proof with no native step still orders the choice before the post.
    final unchanged = await platform.invoke('recoveryDeliveryCurrent', {
      'revision': settled,
      if (generation != null) 'generation': generation,
    });
    return unchanged == true ? true : null;
  }

  Future<bool> _enabled() async {
    try {
      return await preferences.read();
    } catch (_) {
      // Unreadable storage mutes delivery, as at every other read.
      return false;
    }
  }
}

/// Reads on and remembers nothing, for hosts with no storage: tests, and builds
/// where a recovery has nowhere to arrive anyway.
final class DefaultRecoveryNotificationPreferenceStore
    implements RecoveryNotificationPreferenceStore {
  const DefaultRecoveryNotificationPreferenceStore();

  @override
  Future<bool> read() async => true;

  @override
  Future<void> write(bool enabled) async {}
}

/// Reads the stored switch, defaulting to on.
///
/// Preserves the existing stored-value parsing. Secure storage errors propagate
/// to callers, which mute delivery without persisting a fallback. Android still
/// gates posts behind its own permission.
bool recoveryNotificationsFrom(String? stored) => stored != 'false';
