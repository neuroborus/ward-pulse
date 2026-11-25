import 'dart:convert';

import '../providers/connection_lifecycle.dart';
import '../providers/provider_connection.dart';
import '../sync/data_mode.dart';
import 'dashboard_models.dart';

final class CapturedConnectionCache {
  const CapturedConnectionCache(
    this.version,
    this.record, {
    this.minimumEra,
    this.order,
  });
  final CredentialVersion? version;
  final ConnectionCacheRecord? record;
  final int? minimumEra;
  final String? order;

  DashboardSnapshot? get snapshot => record?.snapshot;
  SnapshotCacheObservation? get observation {
    final cacheOrder = order;
    return cacheOrder == null
        ? null
        : (order: cacheOrder, rowId: record?.rowId);
  }
}

final class ConnectionCacheRecord {
  const ConnectionCacheRecord(
    this.snapshot, {
    this.era,
    this.confirmed = false,
    this.rowId,
    this.cacheObservation,
  });
  final DashboardSnapshot snapshot;
  final int? era;
  final bool confirmed;
  final String? rowId;
  final SnapshotCacheObservation? cacheObservation;

  ConnectionCacheRecord withCacheObservation(
    SnapshotCacheObservation? observation,
  ) =>
      confirmed || observation == null || observation == cacheObservation
          ? this
          : ConnectionCacheRecord(
            snapshot,
            era: era,
            cacheObservation: observation,
          );

  // Only a confirmed legacy payload belongs to the initial era.
  int get selectionEra => era ?? (confirmed ? 0 : -1);

  bool isEligible(int? minimumEra) =>
      minimumEra == null || selectionEra >= minimumEra;

  bool isNewerThan(ConnectionCacheRecord other) {
    final comparison =
        era == null && other.era == null
            ? 0
            : selectionEra.compareTo(other.selectionEra);
    return comparison > 0 ||
        (comparison == 0 &&
            snapshot.generatedAt.isAfter(other.snapshot.generatedAt));
  }

  bool supersedes(ConnectionCacheRecord candidate) =>
      (era != null && candidate.era == null) || isNewerThan(candidate);
}

enum SnapshotWriteStatus { stored, older, storageFailure, superseded }

typedef SnapshotWriteResult = ({SnapshotWriteStatus status, int? minimumEra});

/// Validates the complete selection through the shared native lifecycle gate.
Future<bool> validateSnapshotSelection(
  DashboardSnapshot snapshot,
  ConnectionCachePlatform platform, {
  bool allowUnstampedAccounts = false,
}) async {
  final versions = {...snapshot.connectionVersions};
  for (final outcome in snapshot.reportingOutcomes) {
    final previous = versions[outcome.connection.storageKey];
    if (previous?.containsKey('absentRead') == true &&
        outcome.category == ReportingOutcomeCategory.success)
      return false;
    final version = outcome.credentialVersion;
    if (version == null) continue;
    if (version.isAbsent) return false;
    if (previous != null && !version.sameCache(CredentialVersion(previous)))
      return false;
    versions[outcome.connection.storageKey] = version.values;
  }
  for (final account in snapshot.accounts) {
    final values = versions[account.connection];
    if (values != null && CredentialVersion(values).isAbsent) return false;
    // Cacheless reports can carry a credential version without a history owner.
    if (allowUnstampedAccounts && account.historyOwner == null) continue;
    final owner =
        values == null || account.connection == null
            ? null
            : HistoryOwner.fromVersion(
              account.connection!,
              CredentialVersion(values),
            );
    if (account.historyOwner != owner) return false;
  }
  final attemptEras = <String, int>{};
  final payloadOrders = <String, Map<String, Object>>{};
  final cacheOrders = <String, String>{};
  for (final MapEntry(:key, :value) in snapshot.snapshotOrdering.entries) {
    if (value.selectionUnverified) return false;
    if (value.attemptEra case final era?) attemptEras[key] = era;
    if (value.payload case final payload?) {
      payloadOrders[key] = {
        'era': payload.era,
        'generatedAt': payload.generatedAtMicros,
        if (value.confirmedRowId case final id?) 'rowId': id,
      };
    }
    if ((value.emptyCacheOrder ?? value.cacheObservation?.order)
        case final order?) {
      cacheOrders[key] = order;
    }
  }
  return await platform.invoke('validAll', {
        'versions': versions,
        if (attemptEras.isNotEmpty) 'attemptClockEras': attemptEras,
        if (payloadOrders.isNotEmpty) 'payloadOrders': payloadOrders,
        if (cacheOrders.isNotEmpty) 'emptyCacheOrders': cacheOrders,
      }) ==
      true;
}

/// Only canonical normalized data for the owning connection is persisted.
final class ConnectionSnapshotCache {
  static const _cursorMonetaryBasis = 'cursor-extra-paid-calendar-v1';
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
    if (DataModeOperation.current case final operation?)
      'generation': operation.generation,
    ...values,
  });
  Future<bool> valid(CredentialVersion version) async =>
      await _invoke('valid', version) == true;
  Future<bool> validSnapshot(DashboardSnapshot snapshot) =>
      validateSnapshotSelection(snapshot, _platform);

  bool owns(DashboardSnapshot snapshot) => snapshot.accounts.every(
    (account) =>
        account.connection == connection && account.provider == _provider,
  );
  String get _provider =>
      ProviderConnectionId.fromStorageKey(connection)?.legacyProvider ?? '';
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
  ) {
    if (version.isAbsent)
      throw const FormatException('Invalid connection history owner.');
    final owner = HistoryOwner.fromVersion(connection, version);
    if (!owns(snapshot) ||
        snapshot.accounts.any(
          (account) =>
              account.historyOwner != null && account.historyOwner != owner,
        ))
      throw const FormatException('Invalid connection history owner.');
    return snapshot
        .withAccounts([
          for (final account in snapshot.accounts)
            ProviderSnapshot.fromJson({
              ...account.toJson(),
              if (owner != null) 'historyOwner': owner.toJson(),
            }),
        ])
        .withConnectionVersions({connection: version.values});
  }

  Future<CapturedConnectionCache> capture({
    CredentialVersion? expected,
    bool forSelection = false,
  }) async {
    final version = expected ?? await _readCredentialVersion();
    if (version == null) return const CapturedConnectionCache(null, null);
    String? encoded;
    int? minimumEra;
    int? era;
    String? order;
    String? rowId;
    bool? nativeValid;
    var legacyTimestamp = true;
    try {
      final reply = await _invoke('readSnapshot', version, {
        'ordered': true,
        if (forSelection) 'forSelection': true,
      });
      if (reply is Map) {
        nativeValid = reply['valid'] == true;
        encoded = reply['snapshot'] as String?;
        minimumEra = reply['minimumEra'] as int?;
        era = reply['era'] as int?;
        order = reply['order'] as String?;
        rowId = reply['rowId'] as String?;
        legacyTimestamp = reply['legacyTimestamp'] == true;
      } else {
        encoded = reply as String?;
      }
    } catch (_) {
      // A successful refresh needs a current ordering floor.
      if (forSelection) rethrow;
      return CapturedConnectionCache(version, null);
    }
    if (nativeValid == false ||
        (encoded == null && nativeValid == null && !await valid(version))) {
      return CapturedConnectionCache(
        expected == null ? await _readCredentialVersion() : null,
        null,
      );
    }
    CapturedConnectionCache result([ConnectionCacheRecord? record]) =>
        CapturedConnectionCache(
          version,
          record,
          minimumEra: minimumEra,
          order: order,
        );
    if (encoded == null) return result();
    try {
      String normalized = encoded;
      if (connection == 'cursor.platform') {
        final Object? wrapper;
        try {
          wrapper = jsonDecode(encoded);
        } catch (_) {
          // Unmarked old bytes are a basis miss, including unreadable old payloads.
          return result();
        }
        if (wrapper is! Map ||
            wrapper['monetaryBasis'] != _cursorMonetaryBasis) {
          return result();
        }
        normalized = jsonEncode(wrapper['snapshot']);
      }
      final snapshot = parse(normalized);
      if (!owns(snapshot))
        throw const FormatException('Invalid connection cache.');
      if (!forSelection && legacyTimestamp) {
        try {
          await _invoke('upgradeSnapshotTimestamp', version, {
            'snapshot': encoded,
            'generatedAt': snapshot.generatedAt.microsecondsSinceEpoch,
          });
        } catch (_) {
          /* Ordering metadata upgrades are best effort payload I/O. */
        }
      }
      return result(
        ConnectionCacheRecord(
          stamp(snapshot, version),
          era: era,
          confirmed: true,
          rowId: rowId,
        ),
      );
    } catch (_) {
      // Purging advances the epoch. A reporting load must keep the version of
      // the credential it actually read; a fresh write can replace this corrupt
      // payload without retiring that in-flight read.
      if (expected != null) return result();
      try {
        await clear(version);
      } catch (_) {
        /* A corrupt payload remains a cache miss if its purge fails. */
      }
      return CapturedConnectionCache(await _readCredentialVersion(), null);
    }
  }

  Future<bool> store(
    DashboardSnapshot snapshot,
    CredentialVersion version,
  ) async =>
      (await storeOrdered(snapshot, version)).status ==
      SnapshotWriteStatus.stored;

  Future<SnapshotWriteResult> storeOrdered(
    DashboardSnapshot snapshot,
    CredentialVersion version, {
    ConnectionFetchStamp? fetchStamp,
  }) async {
    if (!owns(snapshot))
      throw const FormatException('Invalid connection snapshot.');
    snapshot = stamp(snapshot, version);
    try {
      final reply = await _invoke('writeSnapshot', version, {
        'ordered': true,
        if (fetchStamp != null) 'stamp': fetchStamp.token,
        'snapshot':
            connection == 'cursor.platform'
                ? jsonEncode({
                  'monetaryBasis': _cursorMonetaryBasis,
                  'snapshot': snapshot.toJson(),
                })
                : snapshot.toJsonString(),
        'generatedAt': snapshot.generatedAt.microsecondsSinceEpoch,
      });
      if (reply is Map) {
        return (
          status: SnapshotWriteStatus.values.byName(reply['status'] as String),
          minimumEra: reply['minimumEra'] as int?,
        );
      }
      return (
        status:
            reply == true
                ? SnapshotWriteStatus.stored
                : SnapshotWriteStatus.older,
        minimumEra: null,
      );
    } catch (_) {
      /* A live response remains usable when payload persistence fails. */
      return (status: SnapshotWriteStatus.storageFailure, minimumEra: null);
    }
  }

  Future<void> clear([CredentialVersion? expected]) async {
    await _invoke('clearSnapshot', expected);
  }
}
