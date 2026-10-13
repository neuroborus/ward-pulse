import 'dart:convert';

import '../providers/connection_lifecycle.dart';
import 'dashboard_models.dart';

final class CapturedConnectionCache {
  const CapturedConnectionCache(this.version, this.snapshot);
  final CredentialVersion? version;
  final DashboardSnapshot? snapshot;
}

/// Only canonical normalized data for the owning connection is persisted.
final class ConnectionSnapshotCache {
  ConnectionSnapshotCache({
    required this.connection,
    required Future<CredentialVersion?> Function() readCredentialVersion,
    ConnectionCachePlatform? platform,
  }) : _readCredentialVersion = readCredentialVersion,
       _platform = platform ?? const MethodChannelConnectionCachePlatform();
  final String connection;
  final Future<CredentialVersion?> Function() _readCredentialVersion;
  final ConnectionCachePlatform _platform;

  Future<Object?> _invoke(
    String method,
    CredentialVersion? expected, [
    Map<String, Object?> values = const {},
  ]) => _platform.invoke(method, {
    'connection': connection,
    if (expected != null) 'expected': expected.values,
    ...values,
  });
  Future<bool> valid(CredentialVersion version) async =>
      await _invoke('valid', version) == true;
  Future<bool> validSnapshot(DashboardSnapshot snapshot) async =>
      await _platform.invoke('validAll', {
        'versions': snapshot.connectionVersions,
      }) ==
      true;
  bool owns(DashboardSnapshot snapshot) =>
      snapshot.accounts.isNotEmpty &&
      snapshot.accounts.every(
        (account) =>
            account.connection == connection && account.provider == _provider,
      );
  String get _provider => switch (connection) {
    'openai.plan' => 'codex',
    'openai.platform' => 'openai',
    'anthropic.plan' || 'anthropic.platform' => 'claude',
    'cursor.plan' || 'cursor.platform' => 'cursor',
    _ => '',
  };
  DashboardSnapshot parse(String encoded) {
    final json = jsonDecode(encoded);
    _validate(json);
    final snapshot = DashboardSnapshot.fromJson(
      Map<String, dynamic>.from(json as Map),
    );
    if (!owns(snapshot))
      throw const FormatException('Invalid connection cache.');
    return snapshot;
  }

  static void _validate(Object? value, [String? section]) {
    if (value is List) {
      for (final item in value) {
        _validate(item, section);
      }
    }
    if (value is! Map) return;
    for (final entry in value.entries) {
      final key = entry.key;
      final item = entry.value;
      if ((key == 'status' || key == 'overallStatus') &&
          !ProviderStatus.values.any((status) => status.name == item)) {
        throw const FormatException('Invalid cached status.');
      }
      if (key == 'severity' &&
          !const {'info', 'warning', 'error'}.contains(item))
        throw const FormatException('Invalid cached severity.');
      if (key == 'currency' &&
          (item is! String || !RegExp(r'^[A-Z]{3}$').hasMatch(item)))
        throw const FormatException('Invalid cached currency.');
      if (key == 'minorUnits' &&
          (item is! num || !item.isFinite || item != item.truncateToDouble()))
        throw const FormatException('Invalid cached money.');
      if (key == 'windowMinutes' && item != null && (item is! num || item < 1))
        throw const FormatException('Invalid cached window.');
      if (key == 'source' &&
          !(section == 'credits'
                  ? const {'provider', 'promo', 'manual', 'unknown'}
                  : const {'plan', 'purchased'})
              .contains(item))
        throw const FormatException('Invalid cached source.');
      if (key is String &&
          key.endsWith('Percent') &&
          item != null &&
          (item is! num || !item.isFinite || item < 0)) {
        throw const FormatException('Invalid cached percentage.');
      }
      if (const {
            'windowMinutes',
            'inputTokens',
            'outputTokens',
            'cachedTokens',
            'totalTokens',
            'requests',
          }.contains(key) &&
          item != null &&
          (item is! num ||
              !item.isFinite ||
              item < 0 ||
              item != item.truncateToDouble())) {
        throw const FormatException('Invalid cached count.');
      }
      _validate(item, key is String ? key : section);
    }
  }

  DashboardSnapshot stamp(
    DashboardSnapshot snapshot,
    CredentialVersion version,
  ) => snapshot.withConnectionVersions({connection: version.values});

  Future<CapturedConnectionCache> capture() async {
    var version = await _readCredentialVersion();
    if (version == null) return const CapturedConnectionCache(null, null);
    String? encoded;
    try {
      encoded = await _invoke('readSnapshot', version) as String?;
    } catch (_) {
      return CapturedConnectionCache(version, null);
    }
    if (encoded == null) {
      if (!await valid(version)) version = await _readCredentialVersion();
      return CapturedConnectionCache(version, null);
    }
    try {
      final snapshot = parse(encoded);
      if (!owns(snapshot))
        throw const FormatException('Invalid connection cache.');
      try {
        await _invoke('upgradeSnapshotTimestamp', version, {
          'snapshot': encoded,
          'generatedAt': snapshot.generatedAt.microsecondsSinceEpoch,
        });
      } catch (_) {
        /* Ordering metadata upgrades are best effort payload I/O. */
      }
      return CapturedConnectionCache(version, stamp(snapshot, version));
    } catch (_) {
      try {
        await clear(version);
      } catch (_) {
        /* A corrupt payload remains a cache miss if its purge fails. */
      }
      version = await _readCredentialVersion();
      return CapturedConnectionCache(version, null);
    }
  }

  Future<bool> store(
    DashboardSnapshot snapshot,
    CredentialVersion version,
  ) async {
    if (!owns(snapshot))
      throw const FormatException('Invalid connection snapshot.');
    try {
      return await _invoke('writeSnapshot', version, {
            'snapshot': snapshot.toJsonString(),
            'generatedAt': snapshot.generatedAt.microsecondsSinceEpoch,
          }) ==
          true;
    } catch (_) {
      return false;
      /* A live response remains usable when payload persistence fails. */
    }
  }

  Future<void> clear([CredentialVersion? expected]) async {
    await _invoke('clearSnapshot', expected);
  }
}
