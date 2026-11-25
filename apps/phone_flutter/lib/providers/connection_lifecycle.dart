import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../sync/automatic_poll.dart';
import '../sync/data_mode.dart';

/// Android owns atomic lifecycle/cache transactions across Flutter engines.
abstract interface class ConnectionCachePlatform {
  Future<Object?> invoke(String method, Map<String, Object?> arguments);
}

final class MethodChannelConnectionCachePlatform
    implements ConnectionCachePlatform {
  const MethodChannelConnectionCachePlatform();
  static const channel = MethodChannel('app.wardpulse/connection_cache');
  @override
  Future<Object?> invoke(String method, Map<String, Object?> arguments) =>
      channel.invokeMethod<Object?>(method, arguments);
}

final class CredentialVersion {
  CredentialVersion(Map<String, String> values)
    : values = Map.unmodifiable({
        for (final key in [
          'generation',
          'revision',
          'epoch',
          'identity',
          'committedConnection',
          'absentRead',
          'conflict',
        ])
          if (values[key] != null) key: values[key]!,
      });

  /// Immutable, non-secret native lifecycle stamp, safe to retain after a read.
  final Map<String, String> values;
  bool get isAbsent => values.containsKey('absentRead');
  String get generation => values['generation']!;
  String get revision => values['revision']!;
  String get epoch => values['epoch']!;
  factory CredentialVersion.fromMap(Map<String, Object?> map) =>
      CredentialVersion({
        for (final key in [
          'generation',
          'revision',
          'epoch',
          'identity',
          'committedConnection',
          'absentRead',
          'conflict',
        ])
          if (map[key] is String) key: map[key]! as String,
      });
  bool sameCache(CredentialVersion other) =>
      values['absentRead'] == other.values['absentRead'] &&
      values['conflict'] == other.values['conflict'] &&
      (!isAbsent || revision == other.revision) &&
      generation == other.generation &&
      epoch == other.epoch &&
      values['identity'] == other.values['identity'];
}

/// Combines private evidence without allowing a successor to hide a conflict.
Map<String, Map<String, String>> mergeConnectionVersions(
  Iterable<Map<String, Map<String, String>>> sources,
) {
  final result = <String, Map<String, String>>{};
  for (final source in sources) {
    for (final MapEntry(:key, :value) in source.entries) {
      final previous = result[key];
      if (previous != null &&
          !CredentialVersion(previous).sameCache(CredentialVersion(value))) {
        result[key] = {...previous, 'conflict': 'true'};
      } else {
        result[key] = value;
      }
    }
  }
  return result;
}

/// Scoped to an actual connection read, never a cache probe or fallback load.
final class ConnectionReadObservation {
  ConnectionReadObservation(
    this.connection, {
    void Function(ConnectionCachePlatform)? onConfirmedAbsence,
  }) : _onConfirmedAbsence = onConfirmedAbsence;
  static final _zoneKey = Object();
  final String? connection;
  final void Function(ConnectionCachePlatform)? _onConfirmedAbsence;
  final _versions = <String, Map<String, String>>{};
  var _readFailed = false;
  var _failedReadLeaseRetired = false;
  var _unprovenAbsence = false;

  Map<String, Map<String, String>> get versions => Map.unmodifiable(_versions);
  bool get readFailed => _readFailed;
  bool get failedReadLeaseRetired => _failedReadLeaseRetired;
  bool get unprovenAbsence => _unprovenAbsence;

  Future<T> run<T>(Future<T> Function() read) =>
      runZoned(read, zoneValues: {_zoneKey: this});

  static bool hasManagedReadFailure(String connection) =>
      _forConnection(connection)?.readFailed ?? false;

  static ConnectionReadObservation? _forConnection(String connection) {
    final observer = Zone.current[_zoneKey] as ConnectionReadObservation?;
    return observer?.connection == connection ? observer : null;
  }

  static void _missing(
    ConnectionCredentialStorage storage, [
    Map<String, Object?>? state,
  ]) {
    final connection = storage.connection;
    final observer = _forConnection(connection);
    if (observer == null) return;
    if (state == null ||
        state['mode'] != 'deleted' ||
        !['generation', 'revision', 'epoch'].every(
          (key) => state[key] is String && (state[key]! as String).isNotEmpty,
        )) {
      observer._unprovenAbsence = true;
      return;
    }
    observer._versions.addAll(
      mergeConnectionVersions([
        observer._versions,
        {
          connection: {
            'absentRead': 'true',
            for (final key in ['generation', 'revision', 'epoch'])
              key: state[key]! as String,
          },
        },
      ]),
    );
    observer._onConfirmedAbsence?.call(storage.platform);
  }
}

typedef ConnectionFetchStamp =
    ({CredentialVersion version, String token, int era});

/// A connection load lacks the native evidence required for publication.
final class ConnectionFetchRetired extends StateError {
  ConnectionFetchRetired(this.connection) : super('Account fetch superseded.');

  final String connection;
}

/// Private ordering evidence for one connection load, including after release.
final class ConnectionFetchObservation {
  ConnectionFetchObservation(this.connection);
  final String? connection;
  static final _zoneKey = Object();
  CredentialVersion? _attemptedVersion;
  ConnectionFetchStamp? _stamp;
  ConnectionFetchStamp? get stamp => _stamp;
  int? _reportedAt;

  /// A rejected stamp still identifies the credential the load depended on.
  Map<String, Map<String, String>> get unstampedVersions {
    final key = connection;
    final version = _attemptedVersion;
    if (key == null || version == null || _stamp != null) return const {};
    return {key: version.values};
  }

  Future<T> run<T>(Future<T> Function() load) =>
      runZoned(load, zoneValues: {_zoneKey: this});

  static ConnectionFetchObservation? _forConnection(String connection) {
    final observer = Zone.current[_zoneKey] as ConnectionFetchObservation?;
    return observer?.connection == connection ? observer : null;
  }

  void recordReport(String report) {
    if (stamp != null) _reportedAt = _reportTime(report);
  }

  static int? _reportTime(String report) {
    try {
      final envelope = jsonDecode(report);
      if (envelope is Map && envelope['generatedAt'] is String) {
        return DateTime.tryParse(
          envelope['generatedAt'] as String,
        )?.millisecondsSinceEpoch;
      }
    } on FormatException {
      // Normalization owns report validation.
    }
    return null;
  }
}

/// Synchronous observation under a native lease; legacy stores can lack a stamp.
typedef CredentialLifecycleObserver =
    void Function(String mode, CredentialVersion? version);

typedef ConnectionRejection = ({String connection, String eventId});

/// Records only a classified failure of an owned saved credential/fetch.
abstract interface class ConnectionRejectionRecorder {
  Future<bool> rejectAuthentication(CredentialVersion expected);
}

final class VersionedCredential<T> {
  const VersionedCredential(this.value, this.version);
  final T value;
  final CredentialVersion version;
}

/// Read and fetch ownership only; secret values remain transient.
abstract interface class ConnectionCredentialAccess {
  Future<VersionedCredential<String>?> read();
  Future<bool> isCurrent(CredentialVersion expected);
  Future<void> observeLifecycle(CredentialLifecycleObserver observer);
  Future<R> serializeFetch<R>(Future<R> Function() operation);
  Future<void> admitAutomatic(CredentialVersion expected);
}

abstract interface class VersionedAccountStore<T> {
  Future<R> serializeFetch<R>(Future<R> Function() operation);
  Future<void> admitAutomatic(CredentialVersion expected);
  Future<bool> isCurrent(CredentialVersion expected);
  Future<void> observeLifecycle(CredentialLifecycleObserver observer);
  Future<VersionedCredential<T>?> readVersioned();
  Future<CredentialVersion?> refresh(T value, CredentialVersion expected);
  Future<void> deleteIfCurrent(CredentialVersion expected);
  Future<CredentialVersion> beginReconnect();
  Future<bool> completeReconnect(T value, CredentialVersion ticket);
  Future<void> cancelReconnect(CredentialVersion ticket);
}

final class _ConnectionFetchLease {
  _ConnectionFetchLease(this.ticket);

  final String ticket;
  ConnectionReadObservation? failedRead;
}

/// Secret values stay in FlutterSecureStorage; native storage receives only a digest.
final class ConnectionCredentialStorage
    implements ConnectionCredentialAccess, ConnectionRejectionRecorder {
  ConnectionCredentialStorage({
    required this.connection,
    required this.legacyKey,
    required String Function(String) principal,
    FlutterSecureStorage? storage,
    ConnectionCachePlatform? platform,
  }) : _storage = storage ?? const FlutterSecureStorage(),
       platform = platform ?? const MethodChannelConnectionCachePlatform(),
       _principal = principal;
  final String connection;
  final String legacyKey;
  final FlutterSecureStorage _storage;
  final ConnectionCachePlatform platform;
  final String Function(String) _principal;
  final _fetchZoneKey = Object();
  _ConnectionFetchLease? get _fetchLease =>
      Zone.current[_fetchZoneKey] as _ConnectionFetchLease?;
  String? get _fetchTicket => _fetchLease?.ticket;
  Future<bool> isFetchCurrent() async {
    final ticket = _fetchTicket;
    return ticket == null || await _validFetch(ticket);
  }

  Future<bool> _validFetch(String ticket, {bool forAdmission = false}) async =>
      await platform.invoke('validFetch', {
        'connection': connection,
        'fetchTicket': ticket,
        if (forAdmission) 'forAdmission': true,
      }) ==
      true;

  @override
  Future<void> admitAutomatic(CredentialVersion expected) async {
    // Cache-only work is always denied natively, even outside a poll, so it
    // reads the cache instead of reaching a transport.
    final context =
        AutomaticPollContext.current ??
        ((DataModeOperation.current?.cacheOnly ?? false)
            ? AutomaticPollContext(origin: AutomaticPollOrigin.resetWake)
            : null);
    if (context != null) await _claimAutomatic(context, expected);
    final ticket = _fetchTicket;
    final observation = ConnectionFetchObservation._forConnection(connection);
    if (ticket == null || observation == null) return;
    observation._attemptedVersion = expected;
    try {
      final result =
          await platform.invoke('stampFetch', {
                'connection': connection,
                'fetchTicket': ticket,
                'expected': expected.values,
              })
              as Map;
      observation._stamp = (
        version: expected,
        token: result['stamp'] as String,
        era: result['era'] as int,
      );
    } catch (_, stackTrace) {
      Error.throwWithStackTrace(ConnectionFetchRetired(connection), stackTrace);
    }
  }

  Future<void> _claimAutomatic(
    AutomaticPollContext context,
    CredentialVersion expected,
  ) async {
    final Map<String, Object?> result;
    try {
      final interval = await context.interval(connection);
      result = Map<String, Object?>.from(
        (await platform.invoke('claimAutomatic', {
              'connection': connection,
              'fetchTicket': _fetchTicket,
              'expected': expected.values,
              'intervalMillis': interval.inMilliseconds,
              // Cache-only work reads cadence without admitting a poll.
              if (DataModeOperation.current?.cacheOnly ?? false)
                'cacheOnly': true,
            }))!
            as Map,
      );
    } catch (_) {
      throw AutomaticPollUnavailable(connection, expected);
    }
    // Both decisions return the confirmed anchor for this connection's reset
    // wakes, including when the native clock has moved backward.
    if (result['automaticAt'] case final num at) {
      context.automaticAt[connection] = DateTime.fromMillisecondsSinceEpoch(
        at.toInt(),
        isUtc: true,
      );
    }
    if (result['admitted'] != true) {
      final skipped = AutomaticPollSkipped(
        connection,
        expected,
        DateTime.fromMillisecondsSinceEpoch(
          (result['nextEligible']! as num).toInt(),
          isUtc: true,
        ),
        cacheOrder: result['order'] as String?,
      );
      context.skipped[connection] = skipped;
      throw skipped;
    }
    context.attempted.add(connection);
    context.admittedVersions[connection] = expected;
  }

  @override
  Future<R> serializeFetch<R>(Future<R> Function() operation) async {
    final dataMode = DataModeOperation.current;
    final String ticket;
    try {
      final lease = await platform.invoke('acquireFetch', {
        'connection': connection,
        // Binds the network reservation to the operation's data mode.
        ...?dataMode?.fetchArguments,
      });
      ticket = (lease as Map)['fetchTicket'] as String;
    } catch (_, stackTrace) {
      Error.throwWithStackTrace(ConnectionFetchRetired(connection), stackTrace);
    }
    final lease = _ConnectionFetchLease(ticket);
    final observation = ConnectionFetchObservation._forConnection(connection);
    int? reportAt;
    late R value;
    var releasedCurrent = false;
    try {
      if (dataMode != null) {
        // Native may have granted this ticket before delivering its reply.
        final bool admitted;
        try {
          admitted = await _validFetch(ticket, forAdmission: true);
        } catch (_, stackTrace) {
          Error.throwWithStackTrace(
            ConnectionFetchRetired(connection),
            stackTrace,
          );
        }
        if (!admitted) throw ConnectionFetchRetired(connection);
      }
      Object? failure;
      StackTrace? failureStack;
      try {
        value = await runZoned(operation, zoneValues: {_fetchZoneKey: lease});
        if (value is String) {
          reportAt = ConnectionFetchObservation._reportTime(value);
        }
      } catch (error, stackTrace) {
        failure = error;
        failureStack = stackTrace;
      }
      var current = false;
      StackTrace? validationStack;
      try {
        current = await _validFetch(ticket);
      } catch (_, stackTrace) {
        validationStack = stackTrace;
      }
      if (failure != null) {
        // Record retirement on the owning read while preserving its error.
        final failedRead = lease.failedRead;
        if (!current) failedRead?._failedReadLeaseRetired = true;
        if (current || failedRead != null) {
          Error.throwWithStackTrace(failure, failureStack!);
        }
      }
      if (validationStack != null) {
        Error.throwWithStackTrace(
          ConnectionFetchRetired(connection),
          validationStack,
        );
      }
      if (!current) throw ConnectionFetchRetired(connection);
    } finally {
      final generatedAt = reportAt ?? observation?._reportedAt;
      try {
        releasedCurrent =
            await platform.invoke('releaseFetch', {
              'connection': connection,
              'fetchTicket': ticket,
              if (generatedAt != null) 'reportAtMillis': generatedAt,
            }) ==
            true;
      } catch (_) {
        /* Detached engines cannot publish or retain a network reservation. */
      }
      if (dataMode != null && !releasedCurrent) {
        lease.failedRead?._failedReadLeaseRetired = true;
      }
    }
    if (dataMode != null && !releasedCurrent) {
      throw ConnectionFetchRetired(connection);
    }
    return value;
  }

  String _identity(String value) =>
      sha256.convert(utf8.encode(_principal(value))).toString();
  Future<Map<String, Object?>> _begin(
    String action, [
    CredentialVersion? expected,
  ]) async {
    final dataMode = DataModeOperation.current;
    final readGeneration = action == 'read' ? dataMode?.generation : null;
    final ticket = _fetchTicket;
    final settlementLease =
        dataMode != null && ticket != null && action == 'refresh'
            ? DataModeOperation.credentialSettlementLease
            : null;
    final result = await platform.invoke('acquire', {
      'connection': connection,
      'action': action,
      if (readGeneration != null) 'generation': readGeneration,
      if (ticket != null &&
          (readGeneration != null ||
              action == 'refresh' ||
              action == 'reject' ||
              action == 'rejectDelete' ||
              (action == 'delete' && expected != null)))
        'fetchTicket': ticket,
      if (settlementLease != null) 'settlementLease': settlementLease,
      if (expected != null) 'expected': expected.values,
    });
    return Map<String, Object?>.from(result! as Map);
  }

  Future<Map<String, Object?>> _finish(
    Map<String, Object?> lease,
    String operation, [
    String? identity,
  ]) async {
    final result = await platform.invoke('finish', {
      'connection': connection,
      'lease': lease['lease'],
      'operation': operation,
      if (identity != null) 'identity': identity,
    });
    return Map<String, Object?>.from(result! as Map);
  }

  Future<void> _cleanup(Map<String, Object?> lease) async {
    final cleaned = <String>[];
    for (final key in (lease['cleanupSlots'] as List<Object?>? ?? const [])) {
      try {
        await _storage.delete(key: key! as String);
        cleaned.add(key);
      } catch (_) {
        /* Retry on the next read. */
      }
    }
    if (cleaned.isNotEmpty) {
      try {
        await platform.invoke('acknowledgeCleanup', {
          'connection': connection,
          'lease': lease['lease'],
          'cleaned': cleaned,
        });
      } catch (_) {
        /* Durable references stay queued for a later retry. */
      }
    }
  }

  Future<Map<String, Object?>> _release(Map<String, Object?> lease) async {
    late final Map<String, Object?> state;
    try {
      await _cleanup(lease);
    } finally {
      state = await _finish(lease, 'release');
    }
    return state;
  }

  @override
  Future<bool> isCurrent(CredentialVersion expected) async =>
      await isFetchCurrent() &&
      await platform.invoke('valid', {
            'connection': connection,
            'expected': expected.values,
          }) ==
          true;

  CredentialVersion? _stamp(Map<String, Object?> state) =>
      ['generation', 'revision', 'epoch'].every(
            (key) =>
                state[key] is String &&
                (state[key]! as String).trim().isNotEmpty,
          )
          ? CredentialVersion.fromMap(state)
          : null;

  @override
  Future<void> observeLifecycle(CredentialLifecycleObserver observer) async {
    final lease = await _begin('read');
    if (lease['accepted'] != true) {
      throw StateError('Credential lifecycle unavailable.');
    }
    try {
      final mode = lease['mode'];
      final stamp = _stamp(lease);
      if (lease['lease'] is! String ||
          (lease['lease']! as String).isEmpty ||
          ![
            'active',
            'pending',
            'deleted',
            'legacy',
            'migration',
          ].contains(mode) ||
          (mode != 'legacy' && stamp == null)) {
        throw StateError('Credential lifecycle unavailable.');
      }
      observer(mode! as String, stamp);
    } finally {
      await _finish(lease, 'release');
    }
  }

  @override
  Future<VersionedCredential<String>?> read() async {
    try {
      return await _read();
    } catch (_) {
      final observation = ConnectionReadObservation._forConnection(connection);
      if (observation != null) {
        observation._readFailed = true;
        _fetchLease?.failedRead = observation;
      }
      rethrow;
    }
  }

  Future<VersionedCredential<String>?> _read() async {
    final lease = await _begin('read');
    var finished = false;
    try {
      await _cleanup(lease);
      final mode = lease['mode'];
      if (mode == 'deleted' || mode == 'pending') {
        finished = true;
        final state = await _release(lease);
        ConnectionReadObservation._missing(
          this,
          mode == 'deleted' ? state : null,
        );
        return null;
      }
      final legacy = mode == 'legacy' || mode == 'migration';
      var value = await _storage.read(
        key: legacy ? legacyKey : lease['slot']! as String,
      );
      var restoring = false;
      if (!legacy && value == null && lease['backupKey'] is String) {
        value = await _storage.read(key: lease['backupKey']! as String);
        restoring = value != null;
      }
      if (value == null || value.trim().isEmpty) {
        finished = true;
        final state = await _finish(lease, 'missing');
        ConnectionReadObservation._missing(this, state);
        return null;
      }
      final String identity;
      try {
        identity = _identity(value);
      } on FormatException {
        finished = true;
        await _finish(lease, 'missing');
        ConnectionReadObservation._missing(this);
        return null;
      } on TypeError {
        finished = true;
        await _finish(lease, 'missing');
        ConnectionReadObservation._missing(this);
        return null;
      }
      if (restoring && identity != lease['identity']) {
        finished = true;
        await _finish(lease, 'confirm', identity);
        ConnectionReadObservation._missing(this);
        return null;
      }
      Map<String, Object?> state;
      if (legacy || restoring) {
        final migration = Map<String, Object?>.from(
          (await platform.invoke('prepareMigration', {
                'connection': connection,
                'lease': lease['lease'],
              }))!
              as Map,
        );
        await _storage.write(
          key: migration['writeSlot']! as String,
          value: value,
        );
        finished = true;
        state = await _finish(lease, 'activate', identity);
        // Keep the legacy backup until explicit deletion; migration never loses installed sessions.
      } else {
        finished = true;
        state = await _finish(lease, 'confirm', identity);
        if (state['mode'] != 'active') {
          ConnectionReadObservation._missing(this);
          return null;
        }
      }
      return VersionedCredential(value, CredentialVersion.fromMap(state));
    } finally {
      if (!finished) await _release(lease);
    }
  }

  Future<CredentialVersion> beginReconnect() async {
    // Materialize an installed legacy session before preserving it for cancellation.
    try {
      await read();
    } catch (_) {
      // An explicit reconnect can recover a pending/unknown prior operation.
      // Native state retains the prior reference; no failed read activates data.
    }
    final lease = await _begin('reconnect');
    final ticket = CredentialVersion.fromMap(lease);
    await _release(lease);
    return ticket;
  }

  Future<bool> completeReconnect(String value, CredentialVersion ticket) async {
    final identity = _identity(value);
    final lease = await _begin('complete', ticket);
    if (lease['accepted'] != true) return false;
    var finished = false;
    try {
      await _storage.write(key: lease['writeSlot']! as String, value: value);
      finished = true;
      await _finish(lease, 'activate', identity);
      return true;
    } finally {
      if (!finished) await _release(lease);
    }
  }

  /// Native state commits an admitted cancellation without granting a lease.
  Future<void> cancelReconnect(CredentialVersion ticket) async {
    await _begin('cancel', ticket);
  }

  Future<void> deleteLegacyPastedSecret() async {
    final lease = await _begin('read');
    final key = 'wardpulse.$connection.secret';
    try {
      await platform.invoke('queueLegacyCleanup', {
        'connection': connection,
        'lease': lease['lease'],
      });
      await _storage.delete(key: key);
      await platform.invoke('acknowledgeCleanup', {
        'connection': connection,
        'lease': lease['lease'],
        'cleaned': [key],
      });
    } finally {
      await _release(lease);
    }
  }

  /// Commits local Claude plan retirement and drains its durable cleanup queue.
  Future<void> retireClaudePlan() async {
    await _release(await _begin('retireClaudePlan'));
  }

  Future<void> write(String value) async {
    final ticket = await beginReconnect();
    try {
      if (!await completeReconnect(value, ticket))
        throw StateError('Credential change superseded.');
    } catch (_) {
      await cancelReconnect(ticket);
      rethrow;
    }
  }

  Future<CredentialVersion?> refresh(
    String value,
    CredentialVersion expected,
  ) async {
    final identity = _identity(value);
    final lease = await _begin('refresh', expected);
    if (lease['accepted'] != true) return null;
    var finished = false;
    try {
      await _storage.write(key: lease['writeSlot']! as String, value: value);
      finished = true;
      final state = await _finish(lease, 'activate', identity);
      return CredentialVersion.fromMap(state);
    } finally {
      if (!finished) await _release(lease);
    }
  }

  @override
  Future<bool> rejectAuthentication(CredentialVersion expected) =>
      recordRejection(expected);

  Future<bool> recordRejection(
    CredentialVersion expected, {
    bool removeCredential = false,
  }) async {
    final lease = await _begin(
      removeCredential ? 'rejectDelete' : 'reject',
      expected,
    );
    if (lease['accepted'] != true) return false;
    if (removeCredential) await _deleteRetired(lease);
    return true;
  }

  Future<void> delete({
    CredentialVersion? expected,
    void Function(CredentialVersion)? onRetired,
  }) async {
    final lease = await _begin('delete', expected);
    if (lease['accepted'] != true) return;
    try {
      final stamp = _stamp(lease);
      if (lease['mode'] == 'deleted' &&
          stamp != null &&
          lease['lease'] is String &&
          (lease['lease']! as String).isNotEmpty) {
        onRetired?.call(stamp);
      }
    } finally {
      await _deleteRetired(lease);
    }
  }

  Future<void> _deleteRetired(Map<String, Object?> lease) async {
    try {
      final retired = lease['retired'] as String?;
      for (final key in {
        legacyKey,
        ...?retired?.split('\n').where((key) => key.isNotEmpty),
      }) {
        await _storage.delete(key: key);
      }
    } finally {
      await _release(lease);
    }
  }
}
