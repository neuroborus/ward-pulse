import 'package:ward_pulse_bindings/ward_pulse_bindings.dart';

import '../sync/provider_sync_logger.dart';
import '../providers/connection_lifecycle.dart';
import 'connection_snapshot_cache.dart';
import 'dashboard_models.dart';
import 'dashboard_load.dart';
import 'dashboard_repository.dart';

typedef ReportNormalizer = String Function(String reportJson);
typedef DashboardSnapshotMerger = String Function(Iterable<String> snapshots);
typedef ConnectionReportLoader = Future<String?> Function();

/// Fetches one connection report, normalizes it, and merges with the fallback.
///
/// Missing credentials pass through to the fallback. Fetch and normalization
/// failures are mapped by `mapError`, which also records the sync event, and
/// retain this connection's previous data alongside fresh fallback accounts.
final class MergingConnectionRepository extends DashboardRepository {
  MergingConnectionRepository({
    required DashboardRepository fallback,
    required ConnectionReportLoader loadReport,
    required ReportNormalizer normalizeReport,
    required DashboardLoadException Function(Object error) mapError,
    ConnectionSnapshotCache? cache,
    ProviderSyncLogger logger = const DeveloperProviderSyncLogger(),
    DashboardSnapshotMerger mergeSnapshots = mergeDashboardSnapshotsJson,
  }) : _cache = cache,
       _fallback = fallback,
       _loadReport = loadReport,
       _normalizeReport = normalizeReport,
       _mapError = mapError,
       _logger = logger,
       _mergeSnapshots = mergeSnapshots;

  final ConnectionSnapshotCache? _cache;
  final DashboardRepository _fallback;
  final ConnectionReportLoader _loadReport;
  final ReportNormalizer _normalizeReport;
  final DashboardLoadException Function(Object error) _mapError;
  final ProviderSyncLogger _logger;
  final DashboardSnapshotMerger _mergeSnapshots;

  DashboardSnapshot? _lastSuccessfulConnectionSnapshot;
  var _cacheRevision = 0;

  @override
  Future<DashboardSnapshot> load() async {
    final revision = ++_cacheRevision;
    final fallback = CapturedDashboardLoad.capture(_fallback.load);
    final CapturedConnectionCache? captured;
    try {
      captured = _cache == null ? null : await _cache.capture();
    } catch (_) {
      _logger.record(
        ProviderSyncEvent.unavailable,
        details: 'Connection storage unavailable.',
      );
      if (revision == _cacheRevision) _lastSuccessfulConnectionSnapshot = null;
      return _recover(
        fallback,
        const DashboardLoadException(
          issue: DashboardSyncIssue.credentialUnavailable,
          details: 'Connection storage unavailable.',
        ),
        revision,
        null,
      );
    }
    var cached = _lastSuccessfulConnectionSnapshot;
    if (_cache != null) {
      final stamp = cached?.connectionVersions[_cache.connection];
      if (captured?.version == null ||
          stamp == null ||
          !captured!.version!.sameCache(CredentialVersion(stamp)))
        cached = null;
      final disk = captured?.snapshot;
      if (disk != null &&
          (cached == null || disk.generatedAt.isAfter(cached.generatedAt)))
        cached = disk;
      if (revision == _cacheRevision)
        _lastSuccessfulConnectionSnapshot = cached;
    }
    final String? report;
    try {
      report = await _loadReport();
    } catch (error) {
      return _recover(fallback, _mapError(error), revision, cached);
    }
    if (report == null) {
      if (revision == _cacheRevision) {
        _lastSuccessfulConnectionSnapshot = null;
      }
      if (revision == _cacheRevision && captured?.version != null)
        await _cache!.clear(captured!.version);
      return _publish((await fallback).value);
    }

    final String normalized;
    try {
      normalized = _normalizeReport(report);
    } catch (error) {
      return _recover(
        fallback,
        _mapError(StateError('Normalize failed: ${loadFailureDetails(error)}')),
        revision,
        cached,
      );
    }

    DashboardSnapshot connectionSnapshot;
    try {
      connectionSnapshot =
          _cache?.parse(normalized) ??
          DashboardSnapshot.fromJsonString(normalized);
    } catch (error) {
      return _recover(
        fallback,
        _mapError(
          StateError('Dashboard parse failed: ${loadFailureDetails(error)}'),
        ),
        revision,
        cached,
      );
    }
    var remembered = connectionSnapshot;
    if (_cache != null) {
      final version = captured?.version;
      if (version == null || !await _cache.valid(version)) {
        if (revision == _cacheRevision)
          _lastSuccessfulConnectionSnapshot = null;
        return _publish((await fallback).value);
      }
      if (!_cache.owns(connectionSnapshot))
        return _recover(
          fallback,
          _mapError(StateError('Invalid connection snapshot.')),
          revision,
          cached,
        );
      connectionSnapshot = _cache.stamp(connectionSnapshot, version);
      remembered = connectionSnapshot;
      if (revision == _cacheRevision) {
        final alreadyOlder =
            cached != null &&
            cached.generatedAt.isAfter(connectionSnapshot.generatedAt);
        if (alreadyOlder || !await _cache.store(connectionSnapshot, version)) {
          try {
            final newer = await _cache.capture();
            final disk = newer.snapshot;
            if (newer.version != null &&
                newer.version!.sameCache(version) &&
                disk != null &&
                disk.generatedAt.isAfter(remembered.generatedAt))
              remembered = disk;
          } catch (_) {
            /* Payload persistence remains best effort for a live response. */
          }
        }
      }
      if (cached != null && cached.generatedAt.isAfter(remembered.generatedAt))
        remembered = cached;
      if (!await _cache.valid(version)) return _publish((await fallback).value);
    }
    // An older successful response must not move reader-visible data backwards.
    if (remembered.generatedAt.isAfter(connectionSnapshot.generatedAt))
      connectionSnapshot = remembered;
    // A credential change or newer load may supersede this in-flight request.
    if (revision == _cacheRevision) {
      _lastSuccessfulConnectionSnapshot = remembered;
    }

    final DashboardSnapshot other;
    try {
      other = (await fallback).value;
    } on DashboardLoadException catch (error) {
      _logger.record(ProviderSyncEvent.succeeded);
      if (error.issue == DashboardSyncIssue.noProviders) {
        return _publish(connectionSnapshot);
      }
      return _publish(
        connectionSnapshot.withSyncIssue(error.issue, details: error.details),
      );
    } catch (error) {
      _logger.record(ProviderSyncEvent.succeeded);
      return _publish(
        connectionSnapshot.withSyncIssue(
          DashboardSyncIssue.dashboardUnavailable,
          details: loadFailureDetails(error),
        ),
      );
    }

    if (!hasLiveAccount(other)) {
      _logger.record(ProviderSyncEvent.succeeded);
      return _publish(connectionSnapshot);
    }

    try {
      final merged = DashboardSnapshot.fromJsonString(
        _mergeSnapshots([
          other.toJsonString(),
          connectionSnapshot.toJsonString(),
        ]),
      ).withConnectionVersions({
        ...other.connectionVersions,
        ...connectionSnapshot.connectionVersions,
      });
      _logger.record(ProviderSyncEvent.succeeded);
      final issue = other.syncIssue;
      return _publish(
        issue == null
            ? merged
            : merged.withSyncIssue(issue, details: other.syncDetails),
      );
    } catch (error) {
      final details = loadFailureDetails(error);
      _logger.record(ProviderSyncEvent.invalidResponse, details: details);
      return _publish(
        connectionSnapshot.withSyncIssue(
          DashboardSyncIssue.dashboardUnavailable,
          details: details,
        ),
      );
    }
  }

  Future<DashboardSnapshot> _publish(DashboardSnapshot snapshot) async {
    if (!await isSnapshotCurrent(snapshot))
      throw const DashboardLoadException(
        issue: DashboardSyncIssue.dashboardUnavailable,
        details: 'Connection changed during refresh.',
      );
    return snapshot;
  }

  @override
  Future<bool> isSnapshotCurrent(DashboardSnapshot snapshot) async {
    final cache = _cache;
    return cache == null
        ? _fallback.isSnapshotCurrent(snapshot)
        : cache.validSnapshot(snapshot);
  }

  @override
  Future<void> clearPersistentSnapshots() async {
    _cacheRevision++;
    _lastSuccessfulConnectionSnapshot = null;
    await _cache?.clear();
    await _fallback.clearPersistentSnapshots();
  }

  @override
  void invalidate() {
    _cacheRevision++;
    _lastSuccessfulConnectionSnapshot = null;
    _fallback.invalidate();
  }

  Future<DashboardSnapshot> _recover(
    Future<CapturedDashboardLoad> fallback,
    DashboardLoadException failure,
    int revision,
    DashboardSnapshot? capturedCache,
  ) async {
    DashboardSnapshot? other;
    try {
      other = (await fallback).value;
    } catch (_) {
      // Prefer the connection-specific issue when nothing else is live.
    }
    var cached = revision == _cacheRevision ? capturedCache : null;
    final ownVersion = cached?.connectionVersions[_cache?.connection];
    if (_cache != null &&
        (ownVersion == null ||
            !await _cache.valid(CredentialVersion(ownVersion)))) {
      cached = null;
      if (revision == _cacheRevision) _lastSuccessfulConnectionSnapshot = null;
    }
    final hasFallback = other != null && hasLiveAccount(other);
    if (cached == null) {
      if (hasFallback) {
        return _publish(
          other.withSyncIssue(failure.issue, details: failure.details),
        );
      }
      throw failure;
    }

    final stale = cached.withStaleStatus(
      syncIssue: failure.issue,
      syncDetails: failure.details,
    );
    if (hasFallback) {
      try {
        final merged = DashboardSnapshot.fromJsonString(
          _mergeSnapshots([other.toJsonString(), stale.toJsonString()]),
        ).withConnectionVersions({
          ...other.connectionVersions,
          ...stale.connectionVersions,
        });
        _logger.record(ProviderSyncEvent.usingCachedSnapshot);
        return _publish(
          merged.withSyncIssue(failure.issue, details: failure.details),
        );
      } catch (error) {
        _logger.record(
          ProviderSyncEvent.invalidResponse,
          details: loadFailureDetails(error),
        );
        return _publish(
          other.withSyncIssue(failure.issue, details: failure.details),
        );
      }
    }
    _logger.record(ProviderSyncEvent.usingCachedSnapshot);
    return _publish(stale);
  }
}
