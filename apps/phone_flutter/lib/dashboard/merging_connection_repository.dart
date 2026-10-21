import 'package:ward_pulse_bindings/ward_pulse_bindings.dart';

import '../sync/provider_sync_logger.dart';
import '../providers/connection_lifecycle.dart';
import '../providers/provider_connection.dart';
import '../providers/provider_credential_store.dart';
import 'connection_snapshot_cache.dart';
import 'dashboard_models.dart';
import 'dashboard_load.dart';
import 'dashboard_repository.dart';

typedef ReportNormalizer = String Function(String reportJson);
typedef DashboardSnapshotMerger = String Function(Iterable<String> snapshots);
typedef ConnectionReportLoader = Future<String?> Function();
typedef _ConnectionResult =
    ({
      DashboardSnapshot? snapshot,
      DashboardLoadException? failure,
      DashboardSnapshot? cached,
    });

/// Fetches one connection report, normalizes it, and merges with the fallback.
///
/// Missing credentials pass through to the fallback. Fetch and normalization
/// failures are mapped by `mapError`, which also records the sync event, and
/// retain this connection's previous data alongside fresh fallback accounts.
final class MergingConnectionRepository extends DashboardRepository {
  MergingConnectionRepository({
    required DashboardRepository fallback,
    ConnectionReportLoader? loadReport,
    this.connection,
    this.credentialStore,
    this.loadCredentialReport,
    required ReportNormalizer normalizeReport,
    required DashboardLoadException Function(Object error) mapError,
    ConnectionSnapshotCache? cache,
    ProviderSyncLogger logger = const DeveloperProviderSyncLogger(),
    DashboardSnapshotMerger mergeSnapshots = mergeDashboardSnapshotsJson,
  }) : assert(
         loadReport != null ||
             (connection != null &&
                 credentialStore != null &&
                 loadCredentialReport != null),
       ),
       assert(loadReport == null || loadCredentialReport == null),
       _cache = cache,
       _fallback = fallback,
       _loadReport = loadReport,
       _normalizeReport = normalizeReport,
       _mapError = mapError,
       _logger = logger,
       _mergeSnapshots = mergeSnapshots;

  final ConnectionSnapshotCache? _cache;
  final DashboardRepository _fallback;
  final ConnectionReportLoader? _loadReport;
  final ProviderConnectionId? connection;
  final ProviderCredentialStore? credentialStore;
  final Future<String> Function(String credential)? loadCredentialReport;
  final ReportNormalizer _normalizeReport;
  final DashboardLoadException Function(Object error) _mapError;
  final ProviderSyncLogger _logger;
  final DashboardSnapshotMerger _mergeSnapshots;

  DashboardSnapshot? _lastSuccessfulConnectionSnapshot;
  var _cacheRevision = 0;

  @override
  Future<DashboardSnapshot> load() => _load(null);

  @override
  Future<DashboardSnapshot> loadObserved(ReportingObserver observer) =>
      _load(observer);

  Future<DashboardSnapshot> _load(ReportingObserver? observer) async {
    final revision = ++_cacheRevision;
    var observing = true;
    void forward(ConnectionReportingUpdate update) {
      if (observing && revision == _cacheRevision) {
        try {
          observer?.call(update);
        } catch (_) {
          // Presentation must not change reporting classification or ownership.
        }
      }
    }

    final fallback = CapturedDashboardLoad.capture(
      () => _fallback.loadObserved(forward),
    );
    final store = credentialStore;
    final id = connection;
    // Legacy session loaders retain their read/fetch flow. Their store still
    // owns local-read outcomes at the publication boundary.
    final access =
        loadCredentialReport != null &&
                store is VersionedProviderCredentialStore &&
                id != null
            ? (store as VersionedProviderCredentialStore).credentialAccess(id)
            : null;
    Future<_ConnectionResult> run() async {
      if (store == null || id == null || loadCredentialReport == null) {
        return _loadOwned(revision, _loadReport!, null);
      }
      // Fetch ownership is acquired before this read. The storage transaction
      // ends inside read(), before any provider request begins.
      final VersionedCredential<String>? read;
      final String? secret;
      try {
        read = await access?.read();
        secret = access == null ? await store.readSecret(id) : read?.value;
      } catch (_) {
        return _failed(
          DashboardLoadException.withOutcomes(
            issue: DashboardSyncIssue.credentialUnavailable,
            reportingOutcomes: [
              ConnectionReportingOutcome(
                connection: id,
                category: ReportingOutcomeCategory.localReadFailure,
                source: ReportingOutcomeSource.local,
                freshness: ReportingOutcomeFreshness.current,
              ),
            ],
          ),
          null,
        );
      }
      if (secret == null) {
        if (revision == _cacheRevision)
          _lastSuccessfulConnectionSnapshot = null;
        _logger.record(ProviderSyncEvent.skippedNoCredential);
        return (snapshot: null, failure: null, cached: null);
      }
      final version = read?.version;
      if (!await _current(revision, version, access))
        return (snapshot: null, failure: null, cached: null);
      forward(
        ConnectionReportingUpdate(connection: id, credentialVersion: version),
      );
      return _loadOwned(
        revision,
        () async =>
            await _current(revision, version, access)
                ? loadCredentialReport!(secret!)
                : null,
        version,
      );
    }

    try {
      // Release fetch ownership as soon as this connection finishes. An
      // unrelated held fallback must not queue the next saved-key check.
      final own =
          access == null ? await run() : await access.serializeFetch(run);
      final facts =
          own.snapshot?.reportingOutcomes ??
          own.failure?.reportingOutcomes ??
          const <ConnectionReportingOutcome>[];
      final current =
          own.failure != null
              ? await isFailureCurrent(own.failure!)
              : own.snapshot == null || await isSnapshotCurrent(own.snapshot!);
      if (current && revision == _cacheRevision) {
        for (final outcome in facts) {
          forward(
            ConnectionReportingUpdate(
              connection: outcome.connection,
              credentialVersion: outcome.credentialVersion,
              outcome: outcome,
            ),
          );
        }
      }
      final DashboardSnapshot result;
      if (own.failure != null) {
        result = await _recover(fallback, own.failure!, revision, own.cached);
      } else if (own.snapshot != null) {
        result = await _finishSuccess(own.snapshot!, fallback);
      } else {
        result = (await fallback).value;
      }
      if (!await isSnapshotCurrent(result) || revision != _cacheRevision) {
        throw const DashboardLoadException(
          details: 'Connection changed during refresh.',
        );
      }
      return result;
    } on DashboardLoadException catch (error) {
      if (!await isFailureCurrent(error) || revision != _cacheRevision) {
        throw const DashboardLoadException(
          details: 'Connection changed during refresh.',
        );
      }
      rethrow;
    } catch (_) {
      // Ownership loss and detachment must never become bad-key evidence.
      throw const DashboardLoadException(
        details: 'Connection changed during refresh.',
      );
    } finally {
      observing = false;
    }
  }

  Future<bool> _current(
    int revision,
    CredentialVersion? version,
    ConnectionCredentialAccess? access,
  ) async =>
      revision == _cacheRevision &&
      (access is! ConnectionCredentialStorage ||
          await access.isFetchCurrent()) &&
      (version == null || access == null || await access.isCurrent(version)) &&
      revision == _cacheRevision;

  ConnectionReportingOutcome _outcome(
    ReportingOutcomeCategory category,
    CredentialVersion? version,
  ) => ConnectionReportingOutcome(
    connection: connection!,
    category: category,
    source: ReportingOutcomeSource.live,
    freshness: ReportingOutcomeFreshness.current,
    credentialVersion: version,
  );

  DashboardLoadException _attribute(
    DashboardLoadException failure,
    CredentialVersion? version,
  ) {
    if (connection == null || loadCredentialReport == null) return failure;
    final category = switch (failure.issue) {
      DashboardSyncIssue.authentication =>
        ReportingOutcomeCategory.authenticationRejected,
      DashboardSyncIssue.permissionDenied =>
        ReportingOutcomeCategory.accessDenied,
      DashboardSyncIssue.rateLimited => ReportingOutcomeCategory.rateLimited,
      DashboardSyncIssue.credentialUnavailable =>
        ReportingOutcomeCategory.localReadFailure,
      DashboardSyncIssue.invalidResponse =>
        ReportingOutcomeCategory.malformedResponse,
      _ => ReportingOutcomeCategory.transientFailure,
    };
    return DashboardLoadException.withOutcomes(
      issue: failure.issue,
      details: failure.details,
      reportingOutcomes: [_outcome(category, version)],
    );
  }

  Future<_ConnectionResult> _loadOwned(
    int revision,
    ConnectionReportLoader loadReport,
    CredentialVersion? version,
  ) async {
    final CapturedConnectionCache? captured;
    try {
      captured =
          _cache == null ? null : await _cache.capture(expected: version);
    } catch (_) {
      _logger.record(
        ProviderSyncEvent.unavailable,
        details: 'Connection storage unavailable.',
      );
      if (revision == _cacheRevision) _lastSuccessfulConnectionSnapshot = null;
      return _failed(
        _attribute(
          const DashboardLoadException(
            issue: DashboardSyncIssue.credentialUnavailable,
            details: 'Connection storage unavailable.',
          ),
          version,
        ),
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
      report = await loadReport();
    } catch (error) {
      return _failed(_attribute(_mapError(error), version), cached);
    }
    if (report == null) {
      if (revision == _cacheRevision) {
        _lastSuccessfulConnectionSnapshot = null;
      }
      if (revision == _cacheRevision && captured?.version != null)
        await _cache!.clear(captured!.version);
      return (snapshot: null, failure: null, cached: null);
    }

    final String normalized;
    try {
      normalized = _normalizeReport(report);
    } catch (error) {
      return _failed(_attribute(_mapError(error), version), cached);
    }

    DashboardSnapshot connectionSnapshot;
    try {
      connectionSnapshot =
          _cache?.parse(normalized) ??
          DashboardSnapshot.fromJsonString(normalized);
    } catch (error) {
      return _failed(_attribute(_mapError(error), version), cached);
    }
    var remembered = connectionSnapshot;
    if (_cache != null) {
      final cacheVersion = version ?? captured?.version;
      if (cacheVersion == null || !await _cache.valid(cacheVersion)) {
        if (revision == _cacheRevision)
          _lastSuccessfulConnectionSnapshot = null;
        return (snapshot: null, failure: null, cached: null);
      }
      if (!_cache.owns(connectionSnapshot))
        return _failed(
          _attribute(
            _mapError(StateError('Invalid connection snapshot.')),
            version,
          ),
          cached,
        );
      connectionSnapshot = _cache.stamp(connectionSnapshot, cacheVersion);
      remembered = connectionSnapshot;
      if (revision == _cacheRevision) {
        final alreadyOlder =
            cached != null &&
            cached.generatedAt.isAfter(connectionSnapshot.generatedAt);
        if (alreadyOlder ||
            !await _cache.store(connectionSnapshot, cacheVersion)) {
          try {
            final newer = await _cache.capture(expected: version);
            final disk = newer.snapshot;
            if (newer.version != null &&
                newer.version!.sameCache(cacheVersion) &&
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
      if (!await _cache.valid(cacheVersion))
        return (snapshot: null, failure: null, cached: null);
    }
    // An older successful response must not move reader-visible data backwards.
    if (remembered.generatedAt.isAfter(connectionSnapshot.generatedAt))
      connectionSnapshot = remembered;
    // A credential change or newer load may supersede this in-flight request.
    if (revision == _cacheRevision) {
      _lastSuccessfulConnectionSnapshot = remembered;
    }

    if (connection != null && loadCredentialReport != null) {
      final outcome = _outcome(ReportingOutcomeCategory.success, version);
      connectionSnapshot = connectionSnapshot.withReportingOutcomes([outcome]);
    }
    return (snapshot: connectionSnapshot, failure: null, cached: null);
  }

  Future<DashboardSnapshot> _finishSuccess(
    DashboardSnapshot connectionSnapshot,
    Future<CapturedDashboardLoad> fallback,
  ) async {
    final capturedFallback = await fallback;
    connectionSnapshot = connectionSnapshot.withReportingOutcomes(
      _combineOutcomes(
        capturedFallback.reportingOutcomes,
        connectionSnapshot.reportingOutcomes,
      ),
    );
    final DashboardSnapshot other;
    try {
      other = capturedFallback.value;
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
          )
          .withConnectionVersions({
            ...other.connectionVersions,
            ...connectionSnapshot.connectionVersions,
          })
          .withReportingOutcomes(
            _combineOutcomes(
              other.reportingOutcomes,
              connectionSnapshot.reportingOutcomes,
            ),
          );
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
        other
            .withReportingOutcomes(connectionSnapshot.reportingOutcomes)
            .withSyncIssue(
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
    final hasUnversionedReadFailure = snapshot.reportingOutcomes.any(
      (outcome) =>
          outcome.category == ReportingOutcomeCategory.localReadFailure &&
          outcome.credentialVersion == null,
    );
    if (cache != null && !hasUnversionedReadFailure) {
      return cache.validSnapshot(snapshot);
    }
    final store = credentialStore;
    final id = connection;
    final access =
        store is VersionedProviderCredentialStore && id != null
            ? (store as VersionedProviderCredentialStore).credentialAccess(id)
            : null;
    if (store != null && id != null) {
      for (final outcome in snapshot.reportingOutcomes.where(
        (outcome) =>
            outcome.connection == id &&
            outcome.category == ReportingOutcomeCategory.localReadFailure &&
            outcome.credentialVersion == null,
      )) {
        // A failed read has no stamp. Confirm that local condition before the
        // final atomic gate, without another provider request.
        try {
          if (access == null) {
            await store.readSecret(outcome.connection);
          } else {
            await access.read();
          }
          return false;
        } catch (_) {
          // The current storage capability still cannot read this connection.
        }
      }
    }
    if (!await _fallback.isSnapshotCurrent(snapshot)) return false;
    // All potentially blocking probes in the chain have finished. Nothing may
    // await storage after this validation of the complete stamped provenance.
    if (cache != null) return cache.validSnapshot(snapshot);
    if (access != null) {
      for (final outcome in snapshot.reportingOutcomes.where(
        (outcome) => outcome.connection == id,
      )) {
        final version = outcome.credentialVersion;
        if (version != null && !await access.isCurrent(version)) return false;
      }
    }
    return true;
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
    // Stamped memory is revalidated on load, including credential and epoch
    // changes. Retire requests without losing unrelated RAM-only recovery.
    if (_cache == null) _lastSuccessfulConnectionSnapshot = null;
    _fallback.invalidate();
  }

  _ConnectionResult _failed(
    DashboardLoadException failure,
    DashboardSnapshot? capturedCache,
  ) => (snapshot: null, failure: failure, cached: capturedCache);

  Future<DashboardSnapshot> _recover(
    Future<CapturedDashboardLoad> fallback,
    DashboardLoadException failure,
    int revision,
    DashboardSnapshot? capturedCache,
  ) async {
    final capturedFallback = await fallback;
    final outcomes = _combineOutcomes(
      capturedFallback.reportingOutcomes,
      failure.reportingOutcomes,
    );
    DashboardSnapshot? other;
    try {
      other = capturedFallback.value;
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
    other = other?.withReportingOutcomes(outcomes);
    final hasFallback = other != null && hasLiveAccount(other);
    if (cached == null) {
      if (hasFallback) {
        return _publish(
          other.withSyncIssue(failure.issue, details: failure.details),
        );
      }
      if (outcomes.isEmpty) throw failure;
      throw DashboardLoadException.withOutcomes(
        issue: failure.issue,
        details: failure.details,
        reportingOutcomes: outcomes,
      );
    }

    final stale = cached
        .withReportingOutcomes(outcomes)
        .withStaleStatus(
          syncIssue: failure.issue,
          syncDetails: failure.details,
        );
    if (hasFallback) {
      try {
        final merged = DashboardSnapshot.fromJsonString(
              _mergeSnapshots([other.toJsonString(), stale.toJsonString()]),
            )
            .withConnectionVersions({
              ...other.connectionVersions,
              ...stale.connectionVersions,
            })
            .withReportingOutcomes(outcomes);
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

List<ConnectionReportingOutcome> _combineOutcomes(
  Iterable<ConnectionReportingOutcome> first,
  Iterable<ConnectionReportingOutcome> second,
) => {
  for (final outcome in [...first, ...second]) outcome.connection: outcome,
}.values.toList(growable: false);
