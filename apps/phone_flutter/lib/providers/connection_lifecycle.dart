import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

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
        for (final key in ['generation', 'revision', 'epoch', 'identity'])
          if (values[key] != null) key: values[key]!,
      });

  /// Immutable, non-secret native lifecycle stamp, safe to retain after a read.
  final Map<String, String> values;
  String get generation => values['generation']!;
  String get revision => values['revision']!;
  String get epoch => values['epoch']!;
  factory CredentialVersion.fromMap(Map<String, Object?> map) =>
      CredentialVersion({
        for (final key in ['generation', 'revision', 'epoch', 'identity'])
          if (map[key] is String) key: map[key]! as String,
      });
  bool sameCache(CredentialVersion other) =>
      generation == other.generation &&
      epoch == other.epoch &&
      values['identity'] == other.values['identity'];
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
  Future<R> serializeFetch<R>(Future<R> Function() operation);
}

abstract interface class VersionedAccountStore<T> {
  Future<R> serializeFetch<R>(Future<R> Function() operation);
  Future<bool> isCurrent(CredentialVersion expected);
  Future<VersionedCredential<T>?> readVersioned();
  Future<CredentialVersion?> refresh(T value, CredentialVersion expected);
  Future<void> deleteIfCurrent(CredentialVersion expected);
  Future<CredentialVersion> beginReconnect();
  Future<bool> completeReconnect(T value, CredentialVersion ticket);
  Future<void> cancelReconnect(CredentialVersion ticket);
}

/// Secret values stay in FlutterSecureStorage; native storage receives only a digest.
final class ConnectionCredentialStorage implements ConnectionCredentialAccess {
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
  String? get _fetchTicket => Zone.current[_fetchZoneKey] as String?;
  Future<bool> isFetchCurrent() async =>
      _fetchTicket == null ||
      await platform.invoke('validFetch', {
            'connection': connection,
            'fetchTicket': _fetchTicket,
          }) ==
          true;
  @override
  Future<R> serializeFetch<R>(Future<R> Function() operation) async {
    final lease = Map<String, Object?>.from(
      (await platform.invoke('acquireFetch', {'connection': connection}))!
          as Map,
    );
    final ticket = lease['fetchTicket']! as String;
    try {
      late R value;
      Object? failure;
      StackTrace? failureStack;
      try {
        value = await runZoned(operation, zoneValues: {_fetchZoneKey: ticket});
      } catch (error, stackTrace) {
        failure = error;
        failureStack = stackTrace;
      }
      if (await platform.invoke('validFetch', {
            'connection': connection,
            'fetchTicket': ticket,
          }) !=
          true) {
        throw StateError('Account fetch superseded.');
      }
      if (failure != null) Error.throwWithStackTrace(failure, failureStack!);
      return value;
    } finally {
      try {
        await platform.invoke('releaseFetch', {
          'connection': connection,
          'fetchTicket': ticket,
        });
      } catch (_) {
        /* Detached engines cannot publish or retain a network reservation. */
      }
    }
  }

  String _identity(String value) =>
      sha256.convert(utf8.encode(_principal(value))).toString();
  Future<Map<String, Object?>> _begin(
    String action, [
    CredentialVersion? expected,
  ]) async {
    final result = await platform.invoke('acquire', {
      'connection': connection,
      'action': action,
      if (_fetchTicket != null &&
          (action == 'refresh' || (action == 'delete' && expected != null)))
        'fetchTicket': _fetchTicket,
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

  Future<void> _release(Map<String, Object?> lease) async {
    try {
      await _cleanup(lease);
    } finally {
      await _finish(lease, 'release');
    }
  }

  @override
  Future<bool> isCurrent(CredentialVersion expected) async =>
      await isFetchCurrent() &&
      await platform.invoke('valid', {
            'connection': connection,
            'expected': expected.values,
          }) ==
          true;

  @override
  Future<VersionedCredential<String>?> read() async {
    final lease = await _begin('read');
    var finished = false;
    try {
      await _cleanup(lease);
      final mode = lease['mode'];
      if (mode == 'deleted' || mode == 'pending') return null;
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
        await _finish(lease, 'missing');
        return null;
      }
      final String identity;
      try {
        identity = _identity(value);
      } on FormatException {
        finished = true;
        await _finish(lease, 'missing');
        return null;
      } on TypeError {
        finished = true;
        await _finish(lease, 'missing');
        return null;
      }
      if (restoring && identity != lease['identity']) {
        finished = true;
        await _finish(lease, 'confirm', identity);
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
        if (state['mode'] != 'active') return null;
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

  Future<void> cancelReconnect(CredentialVersion ticket) async {
    final lease = await _begin('cancel', ticket);
    if (lease['accepted'] == true) await _finish(lease, 'cancel');
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

  Future<void> delete([CredentialVersion? expected]) async {
    final lease = await _begin('delete', expected);
    if (lease['accepted'] != true) return;
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
