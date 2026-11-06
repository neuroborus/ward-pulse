import 'dart:async';

import '../providers/connection_lifecycle.dart';
import '../settings/refresh_interval_preferences.dart';
import 'poll_cadence.dart';

enum AutomaticPollOrigin { periodic, resetWake }

/// One load's provenance; the durable admission decision belongs to Android.
final class AutomaticPollContext {
  AutomaticPollContext({
    this.origin = AutomaticPollOrigin.periodic,
    Future<Duration> Function()? readInterval,
  }) : _readInterval = readInterval ?? _savedInterval;

  static final _key = Object();
  static AutomaticPollContext? get current =>
      Zone.current[_key] as AutomaticPollContext?;
  static const _resetInterval = Duration(
    minutes: PollCadence.minRefreshMinutes,
  );
  final AutomaticPollOrigin origin;
  final Future<Duration> Function() _readInterval;
  final skipped = <String, AutomaticPollSkipped>{};
  final attempted = <String>{};
  final admittedVersions = <String, CredentialVersion>{};
  final retainedAccountIds = <String, Set<String>>{};

  /// Native start anchors by connection: the start this load recorded, or the
  /// durable one that denied it.
  final automaticAt = <String, DateTime>{};
  bool get whollySkipped => skipped.isNotEmpty && attempted.isEmpty;

  static Future<Duration> _savedInterval() async =>
      (await SecureRefreshIntervalPreferenceStore().read()).interval;

  Future<Duration> interval(String connection) async => _floored(
    connection,
    origin == AutomaticPollOrigin.resetWake
        ? _resetInterval
        : await _readInterval(),
  );

  /// The earliest a reset wake can start [connection], whatever started this
  /// load, or `null` when this load saw no native anchor for it.
  DateTime? resetEligibleAt(String connection) =>
      automaticAt[connection]?.add(_floored(connection, _resetInterval));

  static Duration _floored(String connection, Duration preferred) {
    final floor = Duration(
      seconds: connection == 'anthropic.platform' ? 60 : 300,
    );
    return preferred < floor ? floor : preferred;
  }

  Future<T> run<T>(Future<T> Function() load) =>
      runZoned(load, zoneValues: {_key: this});

  bool observes(String connection) => !skipped.containsKey(connection);
}

/// A denied automatic start is neither a provider response nor a failure.
final class AutomaticPollSkipped implements Exception {
  const AutomaticPollSkipped(this.connection, this.version, this.nextEligible);
  final String connection;
  final CredentialVersion version;
  final DateTime nextEligible;
}

final class AutomaticPollUnavailable implements Exception {
  const AutomaticPollUnavailable(this.connection, this.version);
  final String connection;
  final CredentialVersion version;
}
