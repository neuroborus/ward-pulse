import 'package:flutter/foundation.dart';
import 'package:ward_pulse_bindings/ward_pulse_bindings.dart';

import '../sync/provider_sync_logger.dart';
import '../sync/provider_reporting.dart';
import '../sync/automatic_poll.dart';
import '../sync/claude_account_client.dart' show ClaudeAccountException;
import '../sync/codex_account_client.dart' show CodexAccountException;
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
      bool hasTypedCause,
      ConnectionCacheRecord? cached,
      ConnectionCacheRecord? remembered,
      String? failedCacheOrder,
      AutomaticPollSkipped? skipped,
    });

const _connectionChanged = 'Connection changed during refresh.';
const _ConnectionResult _noConnectionResult = (
  snapshot: null,
  failure: null,
  hasTypedCause: false,
  cached: null,
  remembered: null,
  failedCacheOrder: null,
  skipped: null,
);

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

  ConnectionCacheRecord? _lastSuccessfulConnectionSnapshot;
  DashboardLoadException? _lastFailure;
  CredentialVersion? _lastFailureVersion;
  ConnectionCachePlatform? _absencePlatform;
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
    final readObservation = ConnectionReadObservation(
      _cache?.connection ?? id?.storageKey,
      onConfirmedAbsence: (platform) {
        if (_cache == null && revision == _cacheRevision) {
          _absencePlatform = platform;
        }
      },
    );
    final fetchObservation = ConnectionFetchObservation(_cache?.connection);
    var provenance = <String, Map<String, String>>{};
    // A positive read stays private provenance until this connection returns
    // its own result, so a retired read cannot vanish from the aggregate.
    var positiveRead = const <String, Map<String, String>>{};
    var ownOutcomes = const <ConnectionReportingOutcome>[];
    var selectionOrdering = const <String, SnapshotOrdering>{};
    Map<String, Map<String, String>> captureProvenance(
      CapturedDashboardLoad other, {
      bool includeOutcomes = false,
    }) => mergeConnectionVersions([
      provenance,
      positiveRead,
      fetchObservation.unstampedVersions,
      other.connectionVersions,
      readObservation.versions,
      if (includeOutcomes)
        for (final outcome in [...ownOutcomes, ...other.reportingOutcomes])
          if (outcome.credentialVersion case final version?)
            {outcome.connection.storageKey: version.values},
    ]);

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
        return _loadOwned(
          revision,
          () => fetchObservation.run(() => readObservation.run(_loadReport!)),
          null,
          fetchObservation,
          readObservation: readObservation,
        );
      }
      // Fetch ownership is acquired before this read. The storage transaction
      // ends inside read(), before any provider request begins.
      final VersionedCredential<String>? read;
      final String? secret;
      try {
        read = access == null ? null : await readObservation.run(access.read);
        secret =
            access == null
                ? await readObservation.run(() => store.readSecret(id))
                : read?.value;
      } catch (_, stackTrace) {
        final failure = DashboardLoadException.withOutcomes(
          issue: DashboardSyncIssue.credentialUnavailable,
          reportingOutcomes: [
            ConnectionReportingOutcome(
              connection: id,
              category: ReportingOutcomeCategory.localReadFailure,
              source: ReportingOutcomeSource.local,
              freshness: ReportingOutcomeFreshness.current,
              provisionalReadFailure: !readObservation.readFailed,
            ),
          ],
        );
        if (readObservation.readFailed) {
          Error.throwWithStackTrace(
            _unverifiedFailure(failure, id.storageKey),
            stackTrace,
          );
        }
        return _failed(failure, null);
      }
      if (secret == null) {
        if (readObservation.unprovenAbsence)
          throw ConnectionFetchRetired(id.storageKey);
        if (revision == _cacheRevision) {
          _lastSuccessfulConnectionSnapshot = null;
          _lastFailure = null;
          _lastFailureVersion = null;
        }
        _logger.record(ProviderSyncEvent.skippedNoCredential);
        return _noConnectionResult;
      }
      final version = read?.version;
      if (version != null) positiveRead = {id.storageKey: version.values};
      if (!await _current(id, revision, version, access))
        return _noConnectionResult;
      return _loadOwned(
        revision,
        () async {
          if (!await _current(id, revision, version, access)) return null;
          if (version != null) await access!.admitAutomatic(version);
          forward(
            ConnectionReportingUpdate(
              connection: id,
              credentialVersion: version,
            ),
          );
          try {
            return await loadCredentialReport!(secret!);
          } on ProviderReportingException catch (error) {
            if (error.failure == ProviderReportingFailure.authentication &&
                version != null) {
              if (access case final ConnectionRejectionRecorder recorder) {
                if (!await _current(id, revision, version, access) ||
                    !await recorder.rejectAuthentication(version)) {
                  throw StateError('Connection changed during refresh.');
                }
              }
            }
            rethrow;
          }
        },
        version,
        fetchObservation,
      );
    }

    DashboardLoadException? confirmedFailure;
    try {
      // Release fetch ownership as soon as this connection finishes. An
      // unrelated held fallback must not queue the next saved-key check.
      final own =
          access == null
              ? await run()
              : await fetchObservation.run(() => access.serializeFetch(run));
      var remembered = own.remembered;
      final skipped = own.skipped;
      var failure = skipped == null ? own.failure : null;
      // A pre-fetch failure can only describe the cache selection it observed.
      final fixedFailureSelection = failure != null && own.snapshot != null;
      final cache = _cache;
      final stamp = fetchObservation.stamp;
      DashboardSnapshot? failedAttempt;
      // A completed OAuth rejection retires its credential and cache epoch.
      // The historical rejection survives that retirement.
      if (failure != null &&
          failure.issue != DashboardSyncIssue.codexAuthentication &&
          failure.issue != DashboardSyncIssue.claudeAuthentication &&
          cache != null &&
          stamp != null) {
        failure = failure.withConnectionVersions(
          mergeConnectionVersions([
            failure.connectionVersions,
            {cache.connection: stamp.version.values},
          ]),
          snapshotOrdering: {
            ...failure.snapshotOrdering,
            cache.connection: SnapshotOrdering(attemptEra: stamp.era),
          },
        );
        failedAttempt = DashboardSnapshot.empty().withConnectionVersions(
          failure.connectionVersions,
          snapshotOrdering: failure.snapshotOrdering,
        );
      }
      final cached = own.cached;
      var selected = own.snapshot ?? failedAttempt;
      final cachedVersion =
          cached?.snapshot.connectionVersions[cache?.connection];
      if (failure != null &&
          cached != null &&
          (failedAttempt == null ||
              (cachedVersion != null &&
                  stamp!.version.sameCache(
                    CredentialVersion(cachedVersion),
                  )))) {
        selected =
            cache == null
                ? cached.snapshot
                : _withSelection(
                  cached,
                  cache.connection,
                  attemptEra:
                      failedAttempt
                          ?.snapshotOrdering[cache.connection]
                          ?.attemptEra,
                );
      }
      selectionOrdering = selected?.snapshotOrdering ?? const {};
      if (own.snapshot != null || failure != null || own.skipped != null)
        positiveRead = const {};
      // An unselected cache row cannot qualify the current attempt.
      provenance = mergeConnectionVersions([
        selected?.connectionVersions ?? const {},
        failure?.connectionVersions ?? const {},
        readObservation.versions,
        fetchObservation.unstampedVersions,
        if (own.skipped case final skipped?)
          {skipped.connection: skipped.version.values},
      ]);
      final facts =
          own.skipped != null
              ? const <ConnectionReportingOutcome>[]
              : failure?.reportingOutcomes ??
                  own.snapshot?.reportingOutcomes ??
                  const <ConnectionReportingOutcome>[];
      ownOutcomes = facts;
      // A fixed pre-admission selection is only surfaced by the final
      // aggregate, which carries its selection proof.
      var feedbackCurrent = false;
      if (!fixedFailureSelection) {
        try {
          feedbackCurrent =
              failure != null
                  ? await isFailureCurrent(
                    failure.withConnectionVersions(provenance),
                  )
                  : own.snapshot == null ||
                      await isSnapshotCurrent(own.snapshot!);
        } catch (_) {
          // Omit early feedback and let final selection validate the attempt.
        }
      }
      if (feedbackCurrent && revision == _cacheRevision) {
        for (final outcome in facts) {
          forward(
            ConnectionReportingUpdate(
              connection: outcome.connection,
              credentialVersion: outcome.credentialVersion,
              outcome: outcome,
              attemptEra:
                  selectionOrdering[outcome.connection.storageKey]?.attemptEra,
            ),
          );
        }
      }
      final capturedFallback = await fallback;
      provenance = captureProvenance(capturedFallback);
      final connectionKey = cache?.connection;
      final initialOrder = selectionOrdering[connectionKey];
      if (initialOrder != null && !fixedFailureSelection) {
        final (refreshed, replacement) = await _refreshSelection(
          selected!,
          revision,
          allowPayloadReadFailure: failure != null || skipped != null,
          fallbackCacheOrder: own.failedCacheOrder,
          failure: failure,
          hasTypedCause: own.hasTypedCause,
          fallbackFailure: capturedFallback.loadException,
        );
        selected = refreshed;
        selectionOrdering = refreshed.snapshotOrdering;
        remembered = replacement ?? remembered;
      }
      for (var canReselect = true; ; canReselect = false) {
        final order = selectionOrdering[connectionKey];
        final attemptCurrent =
            initialOrder?.attemptEra == null || order?.attemptEra != null;
        final currentFailure = attemptCurrent ? failure : null;
        final skippedFailure = attemptCurrent ? own.failure : null;
        final hasPayload =
            selected != null &&
            (initialOrder != null || fixedFailureSelection
                ? order?.payload != null
                : own.snapshot != null || cached != null);
        ProviderSyncEvent? selectionEvent;
        final DashboardSnapshot? result;
        if (currentFailure != null) {
          result = _recover(
            capturedFallback,
            currentFailure,
            hasPayload ? selected : null,
            onCached: () {
              selectionEvent = ProviderSyncEvent.usingCachedSnapshot;
            },
          );
        } else if (hasPayload) {
          final succeeded =
              own.snapshot != null &&
              skipped == null &&
              failure == null &&
              (stamp == null || order?.attemptEra != null);
          result = _finishSuccess(
            _decorateSkip(selected, skipped, skippedFailure),
            capturedFallback,
            onSuccess:
                succeeded
                    ? () {
                      selectionEvent = ProviderSyncEvent.succeeded;
                    }
                    : null,
          );
        } else {
          final other = capturedFallback.value;
          result =
              order?.emptyCacheOrder == null
                  ? other
                  : _decorateSkip(
                    other,
                    skipped,
                    skippedFailure,
                    stalePayload: false,
                  );
        }
        final candidate =
            result ??
            DashboardSnapshot.empty().withReportingOutcomes(
              _combineOutcomes(
                capturedFallback.reportingOutcomes,
                currentFailure!.reportingOutcomes,
              ),
            );
        final versions = mergeConnectionVersions([
          candidate.connectionVersions,
          if (result == null)
            captureProvenance(capturedFallback, includeOutcomes: true)
          else
            provenance,
        ]);
        // Keep ordering evidence even when a connection contributed no account
        // to the aggregate or the aggregate is only used to guard publication.
        final ordering = {
          ...capturedFallback.snapshotOrdering,
          ...candidate.snapshotOrdering,
          ...selectionOrdering,
        };
        final attributed =
            mapEquals(ordering, candidate.snapshotOrdering) &&
                    _sameConnectionVersions(
                      candidate.connectionVersions,
                      versions,
                    )
                ? candidate
                : candidate.withConnectionVersions(
                  versions,
                  snapshotOrdering: ordering,
                );
        DashboardLoadException rejectSelection() => _superseded(
          attributed,
          failure: currentFailure,
          unverifiedConnection:
              (initialOrder != null
                  ? connectionKey
                  : ordering.keys.firstOrNull ??
                      connectionKey ??
                      versions.keys.firstOrNull) ??
              id?.storageKey ??
              '',
        );
        final bool selectionCurrent;
        try {
          selectionCurrent = await isSnapshotCurrent(attributed);
        } catch (_) {
          // Retire the proof before any reader can retry this validation.
          throw rejectSelection();
        }
        if (selectionCurrent && revision == _cacheRevision) {
          // A live payload whose write failed can only seed recovery once
          // the ordered selection has been validated.
          if (remembered != null) {
            _lastSuccessfulConnectionSnapshot = remembered.withCacheObservation(
              order?.cacheObservation,
            );
          }
          // Only a qualified attempt can supply feedback to a later skip.
          if (!fixedFailureSelection && attemptCurrent) {
            if (currentFailure != null) {
              _lastFailure = currentFailure;
              final owner = cache?.connection ?? id?.storageKey;
              _lastFailureVersion =
                  AutomaticPollContext.current?.admittedVersions[owner] ??
                  stamp?.version ??
                  (cachedVersion == null
                      ? null
                      : CredentialVersion(cachedVersion));
              for (final outcome in facts) {
                if (outcome.connection.storageKey == owner &&
                    outcome.credentialVersion != null)
                  _lastFailureVersion = outcome.credentialVersion;
              }
            }
            if (own.snapshot != null && skipped == null) {
              _lastFailure = null;
              _lastFailureVersion = null;
            }
          }
          if (result == null) {
            var resultFailure = currentFailure!;
            if (!listEquals(
              resultFailure.reportingOutcomes,
              attributed.reportingOutcomes,
            )) {
              resultFailure = DashboardLoadException.withOutcomes(
                issue: resultFailure.issue,
                details: resultFailure.details,
                syncRejection: resultFailure.syncRejection,
                reportingOutcomes: attributed.reportingOutcomes,
              );
            }
            if (!_sameConnectionVersions(
                  resultFailure.connectionVersions,
                  versions,
                ) ||
                !mapEquals(resultFailure.snapshotOrdering, ordering)) {
              resultFailure = resultFailure.withConnectionVersions(
                versions,
                snapshotOrdering: ordering,
              );
            }
            confirmedFailure = resultFailure;
            break;
          }
          if (hasPayload && skipped != null) {
            AutomaticPollContext.current?.retainedAccountIds[skipped
                .connection] = {
              for (final account in selected.accounts) account.accountId,
            };
          }
          if (selectionEvent case final event?) _logger.record(event);
          return attributed;
        }
        if (!canReselect ||
            revision != _cacheRevision ||
            initialOrder == null ||
            fixedFailureSelection) {
          // Keep the original order for a selection that cannot be replaced.
          throw rejectSelection();
        }
        final (refreshed, replacement) = await _refreshSelection(
          selected!,
          revision,
          allowPayloadReadFailure: currentFailure != null || skipped != null,
          failure: currentFailure,
          hasTypedCause: own.hasTypedCause,
          fallbackFailure: capturedFallback.loadException,
        );
        if (identical(refreshed, selected)) throw rejectSelection();
        selected = refreshed;
        selectionOrdering = refreshed.snapshotOrdering;
        remembered = replacement ?? remembered;
      }
    } on DashboardLoadException catch (error, stackTrace) {
      final capturedFallback = await fallback;
      final versions = mergeConnectionVersions([
        error.connectionVersions,
        for (final outcome in error.reportingOutcomes)
          if (outcome.credentialVersion case final version?)
            {outcome.connection.storageKey: version.values},
        captureProvenance(capturedFallback, includeOutcomes: true),
      ]);
      final ordering = {
        ...capturedFallback.snapshotOrdering,
        ...selectionOrdering,
        ...error.snapshotOrdering,
      };
      final alreadyRetired = error.snapshotOrdering.values.any(
        (order) => order.selectionUnverified,
      );
      if (!alreadyRetired) {
        final failure =
            mapEquals(ordering, error.snapshotOrdering) &&
                    _sameConnectionVersions(error.connectionVersions, versions)
                ? error
                : error.withConnectionVersions(
                  versions,
                  snapshotOrdering: ordering,
                );
        var current = false;
        try {
          current = await isFailureCurrent(failure);
        } catch (_) {
          // Unavailable validation rejects this selection as well.
        }
        if (current && revision == _cacheRevision) {
          Error.throwWithStackTrace(failure, stackTrace);
        }
        // Reject later validation even for a load without connection evidence.
        final key =
            error.snapshotOrdering.keys.firstOrNull ??
            ordering.keys.firstOrNull ??
            _cache?.connection ??
            versions.keys.firstOrNull ??
            id?.storageKey ??
            '';
        ordering[key] = _unverifiedSelection(ordering[key]);
      }
      Error.throwWithStackTrace(
        _retiredFailure(
          versions,
          ordering,
          primary: error,
          sibling: capturedFallback,
        ),
        stackTrace,
      );
    } catch (error) {
      // Ownership loss and detachment must never become bad-key evidence.
      final capturedFallback = await fallback;
      final retired = error is ConnectionFetchRetired ? error.connection : null;
      final ordering = {
        ...capturedFallback.snapshotOrdering,
        ...selectionOrdering,
      };
      if (retired != null) {
        // A current credential cannot requalify a retired fetch.
        ordering[retired] = _unverifiedSelection(ordering[retired]);
      }
      final versions = mergeConnectionVersions([
        captureProvenance(capturedFallback, includeOutcomes: true),
        if (retired != null && fetchObservation.stamp != null)
          {retired: fetchObservation.stamp!.version.values},
      ]);
      if (retired != null) {
        throw _retiredFailure(versions, ordering, sibling: capturedFallback);
      }
      throw DashboardLoadException(
        details: _connectionChanged,
        connectionVersions: versions,
        snapshotOrdering: ordering,
      );
    } finally {
      observing = false;
    }
    throw confirmedFailure;
  }

  Future<bool> _current(
    ProviderConnectionId id,
    int revision,
    CredentialVersion? version,
    ConnectionCredentialAccess? access,
  ) async {
    try {
      return revision == _cacheRevision &&
          (access is! ConnectionCredentialStorage ||
              await access.isFetchCurrent()) &&
          (version == null ||
              access == null ||
              await access.isCurrent(version)) &&
          revision == _cacheRevision;
    } catch (_, stackTrace) {
      Error.throwWithStackTrace(
        ConnectionFetchRetired(id.storageKey),
        stackTrace,
      );
    }
  }

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
    final event = version?.values['committedConnection'];
    final rejection =
        failure.issue == DashboardSyncIssue.authentication && event != null
            ? (connection: connection!.storageKey, eventId: event)
            : failure.syncRejection;
    final localRejection = failure.reportingOutcomes.any(
      (outcome) =>
          connection == ProviderConnections.anthropicPlatform &&
          outcome.connection == connection &&
          outcome.source == ReportingOutcomeSource.local &&
          outcome.category == ReportingOutcomeCategory.authenticationRejected,
    );
    if (localRejection && failure.issue == DashboardSyncIssue.authentication) {
      return DashboardLoadException.withOutcomes(
        issue: failure.issue,
        details: failure.details,
        syncRejection: rejection,
        connectionVersions: failure.connectionVersions,
        reportingOutcomes: [
          ConnectionReportingOutcome(
            connection: connection!,
            category: ReportingOutcomeCategory.authenticationRejected,
            source: ReportingOutcomeSource.local,
            freshness: ReportingOutcomeFreshness.current,
            credentialVersion: version,
          ),
        ],
      );
    }
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
      syncRejection: rejection,
      connectionVersions: failure.connectionVersions,
      reportingOutcomes: [_outcome(category, version)],
    );
  }

  Future<_ConnectionResult> _loadOwned(
    int revision,
    ConnectionReportLoader loadReport,
    CredentialVersion? version,
    ConnectionFetchObservation fetchObservation, {
    ConnectionReadObservation? readObservation,
  }) async {
    final cache = _cache;
    final CapturedConnectionCache? captured;
    try {
      captured = cache == null ? null : await cache.capture(expected: version);
    } catch (error, stackTrace) {
      _logger.record(
        ProviderSyncEvent.unavailable,
        details: 'Connection storage unavailable.',
      );
      // A failed credential/cache observation cannot qualify setup feedback.
      final key = cache!.connection;
      final failure =
          error is DashboardLoadException
              ? error
              : DashboardLoadException.withOutcomes(
                issue: DashboardSyncIssue.credentialUnavailable,
                details: 'Connection storage unavailable.',
                reportingOutcomes: [
                  if (ProviderConnectionId.fromStorageKey(key) case final id?)
                    ConnectionReportingOutcome(
                      connection: id,
                      category: ReportingOutcomeCategory.localReadFailure,
                      source: ReportingOutcomeSource.local,
                    ),
                ],
              );
      Error.throwWithStackTrace(_unverifiedFailure(failure, key), stackTrace);
    }
    var cached = _lastSuccessfulConnectionSnapshot;
    if (_cache != null) {
      final stamp = cached?.snapshot.connectionVersions[_cache.connection];
      if (captured?.version == null ||
          stamp == null ||
          !captured!.version!.sameCache(CredentialVersion(stamp))) {
        cached = null;
      }
      if ((_lastFailureVersion == null ||
              captured?.version?.sameCache(_lastFailureVersion!) != true) &&
          revision == _cacheRevision) {
        _lastFailure = null;
        _lastFailureVersion = null;
      }
      final disk = captured?.record;
      if (disk != null && _preferPairedRecord(disk, cached)) cached = disk;
      if (revision == _cacheRevision)
        _lastSuccessfulConnectionSnapshot = cached;
    }
    // Only a capture of the failed attempt's cache epoch can qualify an
    // accountless result if the paired selection read fails.
    _ConnectionResult failed(DashboardLoadException failure, {Object? cause}) {
      final stamp = fetchObservation.stamp;
      return _failed(
        failure,
        cached?.withCacheObservation(captured?.observation),
        // An error mapper supplies a dashboard issue even for generic errors.
        hasTypedCause:
            cause is DashboardLoadException ||
            cause is ProviderReportingException ||
            cause is CodexAccountException ||
            cause is ClaudeAccountException ||
            cause is WardPulseBindingsException,
        failedCacheOrder:
            stamp != null && captured?.version?.sameCache(stamp.version) == true
                ? captured?.order
                : null,
      );
    }

    _ConnectionResult failedBeforeStamp(
      DashboardLoadException failure,
      String key,
      CredentialVersion expected,
    ) {
      final sameCapture =
          _cache?.connection == key &&
          captured?.version?.sameCache(expected) == true;
      // The initial selection already compared RAM with this exact pair.
      final retained = sameCapture ? cached : null;
      final order = sameCapture ? captured?.order : null;
      final snapshot =
          retained != null
              ? _withSelection(
                retained,
                key,
                pairedCacheOrder: order,
                selectionUnverified: order == null,
              )
              : DashboardSnapshot.empty().withConnectionVersions(
                {key: expected.values},
                snapshotOrdering: {
                  key: SnapshotOrdering(
                    emptyCacheOrder: order,
                    selectionUnverified: order == null,
                  ),
                },
              );
      return (
        snapshot: snapshot,
        failure: failure.withConnectionVersions(
          mergeConnectionVersions([
            failure.connectionVersions,
            {key: expected.values},
          ]),
        ),
        hasTypedCause: true,
        cached: null,
        remembered: null,
        failedCacheOrder: null,
        skipped: null,
      );
    }

    final String? report;
    try {
      report = await loadReport();
    } on AutomaticPollSkipped catch (skipped) {
      // OAuth/Cursor may have queued after the earlier cache capture. Read again
      // under the credential version actually denied by the native owner.
      CapturedConnectionCache? current;
      try {
        current = await _cache?.capture(
          expected: skipped.version,
          forSelection: true,
        );
      } catch (_) {
        if (skipped.cacheOrder == null) rethrow;
      }
      final versions = {skipped.connection: skipped.version.values};
      // Plan loaders release their lease before the paired read. An empty
      // selection must carry the order seen at denial across that gap.
      final emptyCacheOrder =
          _cache == null ? null : skipped.cacheOrder ?? current?.order;
      if (current != null &&
          current.version?.sameCache(skipped.version) != true) {
        throw DashboardLoadException(
          details: _connectionChanged,
          connectionVersions: versions,
        );
      }
      var retained = _lastSuccessfulConnectionSnapshot;
      final stamp = retained?.snapshot.connectionVersions[skipped.connection];
      if (stamp == null ||
          !skipped.version.sameCache(CredentialVersion(stamp))) {
        retained = null;
      }
      final disk = current?.record;
      if (disk != null && _preferPairedRecord(disk, retained)) {
        retained = disk;
      }
      final failure =
          _lastFailureVersion?.sameCache(skipped.version) == true
              ? _lastFailure
              : null;
      final failureEra =
          failure?.snapshotOrdering[skipped.connection]?.attemptEra;
      final minimumEra = current?.minimumEra;
      // Qualify the old outcome separately when only metadata is available.
      bool? failureCurrent;
      try {
        failureCurrent =
            failureEra == null ||
            (current == null
                ? await isFailureCurrent(failure!)
                : minimumEra == null || failureEra >= minimumEra);
      } catch (_) {
        // Omit unverified feedback and let the aggregate validate the skip.
      }
      if (failureCurrent == false && revision == _cacheRevision) {
        _lastFailure = null;
        _lastFailureVersion = null;
      }
      final retainFailure = failureCurrent == true;
      final attemptEra = retainFailure ? failureEra : null;
      final DashboardSnapshot? snapshot;
      if (retained != null) {
        snapshot = _withSelection(
          retained,
          skipped.connection,
          attemptEra: attemptEra,
          cacheObservation: current?.observation,
        );
      } else if (emptyCacheOrder != null) {
        snapshot = DashboardSnapshot.empty().withConnectionVersions(
          versions,
          snapshotOrdering: {
            skipped.connection: SnapshotOrdering(
              attemptEra: attemptEra,
              emptyCacheOrder: emptyCacheOrder,
            ),
          },
        );
      } else {
        snapshot = null;
      }
      return (
        snapshot: snapshot,
        failure: retainFailure ? failure : null,
        hasTypedCause: false,
        cached: null,
        remembered: null,
        failedCacheOrder: null,
        skipped: skipped,
      );
    } on AutomaticPollUnavailable catch (error) {
      return failedBeforeStamp(
        DashboardLoadException.withOutcomes(
          issue: DashboardSyncIssue.credentialUnavailable,
          reportingOutcomes: [
            ConnectionReportingOutcome(
              connection:
                  ProviderConnectionId.fromStorageKey(error.connection)!,
              category: ReportingOutcomeCategory.localReadFailure,
              source: ReportingOutcomeSource.local,
              freshness: ReportingOutcomeFreshness.current,
              credentialVersion: error.version,
            ),
          ],
        ),
        error.connection,
        error.version,
      );
    } on ConnectionFetchRetired {
      rethrow;
    } catch (error, stackTrace) {
      final failure = _attribute(_mapError(error), version);
      // Cacheless loaders with a credential store can recheck a failed read
      // before publishing fallback data, provided they still own the fetch.
      if (readObservation
          case ConnectionReadObservation(
            connection: final key?,
            readFailed: true,
            failedReadLeaseRetired: final retiredLease,
          )
          when retiredLease ||
              (fetchObservation.stamp == null &&
                  (cache != null || credentialStore == null))) {
        Error.throwWithStackTrace(_unverifiedFailure(failure, key), stackTrace);
      }
      final key = _cache?.connection;
      final attempted = fetchObservation.unstampedVersions[key];
      return key != null && attempted != null
          ? failedBeforeStamp(failure, key, CredentialVersion(attempted))
          : failed(failure, cause: error);
    }
    if (report == null) {
      // The cache probe cannot qualify the actual credential read.
      if (readObservation case ConnectionReadObservation(
        connection: final key?,
        unprovenAbsence: true,
      )) {
        throw ConnectionFetchRetired(key);
      }
      if (revision == _cacheRevision && captured?.version != null)
        await _cache!.clear(captured!.version);
      if (revision == _cacheRevision) _lastSuccessfulConnectionSnapshot = null;
      return _noConnectionResult;
    }

    // Reporting loads still own the lease here. Plan loaders report their
    // sample on release and carry the same stamp into this selection.
    if (version != null) fetchObservation.recordReport(report);
    final String normalized;
    try {
      normalized = _normalizeReport(report);
    } catch (error) {
      return failed(_attribute(_mapError(error), version), cause: error);
    }

    DashboardSnapshot connectionSnapshot;
    try {
      connectionSnapshot =
          _cache?.parse(normalized) ??
          DashboardSnapshot.fromJsonString(normalized);
    } catch (error) {
      return failed(_attribute(_mapError(error), version), cause: error);
    }
    ConnectionCacheRecord remembered;
    var currentAttempt = true;
    if (_cache != null) {
      final fetchStamp = fetchObservation.stamp;
      final cacheVersion = version ?? fetchStamp?.version ?? captured?.version;
      DashboardLoadException rejectedSelection(
        CredentialVersion expected, {
        bool unverified = false,
      }) => _superseded(
        DashboardSnapshot.empty().withConnectionVersions(
          {_cache.connection: (fetchStamp?.version ?? expected).values},
          snapshotOrdering: {
            _cache.connection: SnapshotOrdering(
              attemptEra: fetchStamp?.era,
              selectionUnverified: unverified,
            ),
          },
        ),
      );

      _ConnectionResult discardSelection() {
        // A stamped fetch must remain in the aggregate's publication guard.
        if (fetchStamp != null) throw rejectedSelection(fetchStamp.version);
        return _noConnectionResult;
      }

      Future<bool> isCacheCurrent(CredentialVersion expected) async {
        try {
          return await _cache.valid(expected);
        } catch (_) {
          if (fetchStamp == null) rethrow;
          throw rejectedSelection(expected, unverified: true);
        }
      }

      if (cacheVersion == null || !await isCacheCurrent(cacheVersion)) {
        if (revision == _cacheRevision)
          _lastSuccessfulConnectionSnapshot = null;
        return discardSelection();
      }
      if (!_cache.owns(connectionSnapshot))
        return failed(
          _attribute(
            _mapError(StateError('Invalid connection snapshot.')),
            version,
          ),
        );
      connectionSnapshot = _cache.stamp(connectionSnapshot, cacheVersion);
      if (fetchStamp != null && !fetchStamp.version.sameCache(cacheVersion)) {
        throw rejectedSelection(cacheVersion, unverified: true);
      }
      final live = ConnectionCacheRecord(
        connectionSnapshot,
        era: fetchStamp?.era,
      );
      final sameCapturedCache =
          captured?.version?.sameCache(cacheVersion) == true;
      final previous =
          !sameCapturedCache ||
                  (live.era != null && cached?.isEligible(0) == false)
              ? null
              : cached;
      final alreadyOlder = previous != null && previous.supersedes(live);
      final write =
          revision == _cacheRevision && !alreadyOlder
              ? await _cache.storeOrdered(
                connectionSnapshot,
                cacheVersion,
                fetchStamp: fetchStamp,
              )
              : null;
      if (!await isCacheCurrent(cacheVersion)) return discardSelection();
      // A different owner can advance the floor even when its write fails.
      // Refresh it after the write decision, including on the skipped path.
      final CapturedConnectionCache latest;
      try {
        latest = await _cache.capture(
          expected: cacheVersion,
          forSelection: true,
        );
      } catch (_) {
        throw rejectedSelection(cacheVersion, unverified: true);
      }
      if (latest.version?.sameCache(cacheVersion) != true)
        return discardSelection();
      final minimumEra = [
        if (sameCapturedCache) captured?.minimumEra,
        write?.minimumEra,
        latest.minimumEra,
      ].whereType<int>().fold<int?>(
        null,
        (floor, era) => floor == null || era > floor ? era : floor,
      );
      ConnectionCacheRecord? winner;
      for (final record in [previous, latest.record]) {
        if (record != null &&
            (record.rowId == null || record.rowId == latest.record?.rowId) &&
            record.isEligible(minimumEra) &&
            _preferPairedRecord(record, winner)) {
          winner = record;
        }
      }
      // Break ties only when the same cache proves a paired row changed.
      final newRow = _isPairedReplacement(
        winner?.rowId,
        sameCapturedCache ? captured?.observation : null,
      );
      if (write?.status != SnapshotWriteStatus.superseded &&
          write?.status != SnapshotWriteStatus.stored &&
          live.isEligible(minimumEra) &&
          (winner == null ||
              (newRow ? live.isNewerThan(winner) : !winner.supersedes(live)))) {
        winner = live;
      }
      if (winner == null)
        throw _superseded(_withSelection(live, _cache.connection));
      remembered = winner;
      currentAttempt =
          write?.status != SnapshotWriteStatus.superseded &&
          live.isEligible(minimumEra);
      connectionSnapshot = _withSelection(
        remembered,
        _cache.connection,
        attemptEra: currentAttempt ? live.era : null,
        cacheObservation: latest.observation,
      );
    } else {
      remembered = ConnectionCacheRecord(connectionSnapshot);
    }
    if (currentAttempt && connection != null && loadCredentialReport != null) {
      final outcome = _outcome(ReportingOutcomeCategory.success, version);
      connectionSnapshot = connectionSnapshot.withReportingOutcomes([outcome]);
    }
    return (
      snapshot: connectionSnapshot,
      failure: null,
      hasTypedCause: false,
      cached: null,
      remembered: remembered,
      failedCacheOrder: null,
      skipped: null,
    );
  }

  bool _preferPairedRecord(
    ConnectionCacheRecord paired,
    ConnectionCacheRecord? retained,
  ) =>
      retained == null ||
      (retained.rowId != null && paired.rowId != retained.rowId) ||
      paired.isNewerThan(retained) ||
      (_isPairedReplacement(paired.rowId, retained.cacheObservation) &&
          !retained.isNewerThan(paired));

  bool _isPairedReplacement(
    String? rowId,
    SnapshotCacheObservation? previous,
  ) => rowId != null && previous != null && rowId != previous.rowId;

  DashboardSnapshot _withSelection(
    ConnectionCacheRecord record,
    String connection, {
    int? attemptEra,
    String? pairedCacheOrder,
    SnapshotCacheObservation? cacheObservation,
    bool selectionUnverified = false,
  }) => record.snapshot.withConnectionVersions(
    record.snapshot.connectionVersions,
    snapshotOrdering: {
      connection: SnapshotOrdering(
        payload: (
          era: record.selectionEra,
          generatedAtMicros: record.snapshot.generatedAt.microsecondsSinceEpoch,
        ),
        confirmedRowId: record.rowId,
        cacheObservation:
            record.confirmed
                ? null
                : cacheObservation ?? record.cacheObservation,
        attemptEra: attemptEra,
        emptyCacheOrder: pairedCacheOrder,
        selectionUnverified: selectionUnverified,
      ),
    },
  );

  Future<(DashboardSnapshot, ConnectionCacheRecord?)> _refreshSelection(
    DashboardSnapshot selected,
    int revision, {
    required bool allowPayloadReadFailure,
    String? fallbackCacheOrder,
    DashboardLoadException? failure,
    required bool hasTypedCause,
    DashboardLoadException? fallbackFailure,
  }) async {
    final cache = _cache!;
    final key = cache.connection;
    final order = selected.snapshotOrdering[key]!;
    final version = CredentialVersion(selected.connectionVersions[key]!);
    DashboardLoadException rejectSelection(
      DashboardSnapshot snapshot,
      DashboardLoadException? primary,
    ) {
      // An ordinary fallback failure does not explain why selection retired.
      final fallbackRetired =
          fallbackFailure?.snapshotOrdering.values.any(
            (order) => order.selectionUnverified,
          ) ??
          false;
      return _superseded(
        snapshot,
        failure: primary ?? (fallbackRetired ? fallbackFailure : null),
        unverifiedConnection: key,
      );
    }

    // A sibling can outlive the original selection. The metadata gate can
    // still qualify a stale fallback or an empty selection after a read error.
    final CapturedConnectionCache latest;
    try {
      latest = await cache.capture(expected: version, forSelection: true);
    } catch (_) {
      if (allowPayloadReadFailure) {
        if (order.payload != null || order.emptyCacheOrder != null) {
          return (selected, null);
        }
        final observed = selected.withConnectionVersions(
          selected.connectionVersions,
          snapshotOrdering: {
            key: SnapshotOrdering(
              attemptEra: order.attemptEra,
              emptyCacheOrder: fallbackCacheOrder,
            ),
          },
        );
        if (fallbackCacheOrder != null) return (observed, null);
        // The attempt era alone cannot qualify publication. Keep the
        // independently typed cause for diagnostics.
        throw rejectSelection(observed, hasTypedCause ? failure : null);
      }
      throw rejectSelection(selected, failure);
    }
    if (latest.version?.sameCache(version) != true) {
      throw _superseded(selected);
    }
    if (revision != _cacheRevision) {
      throw rejectSelection(selected, failure);
    }
    final minimumEra = latest.minimumEra;
    bool eligible(int era) => minimumEra == null || era >= minimumEra;
    final payload = order.payload;
    final attemptEra = order.attemptEra;
    final attemptCurrent = attemptEra == null || eligible(attemptEra);
    final payloadCurrent =
        payload != null &&
        eligible(payload.era) &&
        (order.confirmedRowId == null ||
            order.confirmedRowId == latest.record?.rowId);
    final emptyCacheCurrent =
        order.emptyCacheOrder != null && order.emptyCacheOrder == latest.order;

    ConnectionCacheRecord? winner;
    for (final record in [_lastSuccessfulConnectionSnapshot, latest.record]) {
      final recordedVersion = record?.snapshot.connectionVersions[key];
      if (record == null ||
          recordedVersion == null ||
          !version.sameCache(CredentialVersion(recordedVersion)) ||
          (record.rowId != null && record.rowId != latest.record?.rowId) ||
          !record.isEligible(minimumEra)) {
        continue;
      }
      if (_preferPairedRecord(record, winner)) winner = record;
    }
    // An unstamped RAM candidate keeps the legacy timestamp comparison even
    // when the confirmed legacy row has a different selection-era encoding.
    final sameEra =
        winner != null &&
        payload != null &&
        (winner.selectionEra == payload.era ||
            (winner.era == null && payload.era == -1));
    final newConfirmedRow = _isPairedReplacement(
      winner?.rowId,
      order.cacheObservation,
    );
    final winnerTime = winner?.snapshot.generatedAt.microsecondsSinceEpoch;
    final winsByTimestamp =
        winnerTime != null &&
        payload != null &&
        (winnerTime > payload.generatedAtMicros ||
            (newConfirmedRow && winnerTime == payload.generatedAtMicros));
    if (winner != null &&
        (payload == null ||
            !payloadCurrent ||
            (sameEra ? winsByTimestamp : winner.selectionEra > payload.era))) {
      final replacement = _withSelection(
        winner,
        key,
        attemptEra: attemptCurrent ? attemptEra : null,
        cacheObservation: latest.observation,
      );
      return (
        attemptCurrent
            ? replacement.withReportingOutcomes(selected.reportingOutcomes)
            : replacement,
        winner,
      );
    }
    if ((payload != null && !payloadCurrent) ||
        (order.emptyCacheOrder != null && !emptyCacheCurrent) ||
        (!attemptCurrent && payload == null && !emptyCacheCurrent)) {
      throw _superseded(selected);
    }
    final observedCacheOrder = latest.order;
    if (payload == null &&
        order.emptyCacheOrder == null &&
        observedCacheOrder != null) {
      // A confirmed row may arrive after an accountless failure's reread.
      final observed = selected.withConnectionVersions(
        selected.connectionVersions,
        snapshotOrdering: {
          key: SnapshotOrdering(
            attemptEra: attemptEra,
            emptyCacheOrder: observedCacheOrder,
          ),
        },
      );
      return (observed, null);
    }
    final cacheObservation =
        payload != null && order.confirmedRowId == null
            ? latest.observation ?? order.cacheObservation
            : null;
    if (attemptCurrent && cacheObservation == order.cacheObservation) {
      return (selected, null);
    }
    final refreshed =
        attemptCurrent ? selected : selected.withReportingOutcomes(const []);
    return (
      refreshed.withConnectionVersions(
        refreshed.connectionVersions,
        snapshotOrdering: {
          key: SnapshotOrdering(
            payload: payload,
            confirmedRowId: order.confirmedRowId,
            cacheObservation: cacheObservation,
            attemptEra: attemptCurrent ? attemptEra : null,
            emptyCacheOrder: order.emptyCacheOrder,
          ),
        },
      ),
      null,
    );
  }

  DashboardSnapshot _decorateSkip(
    DashboardSnapshot snapshot,
    AutomaticPollSkipped? skipped,
    DashboardLoadException? failure, {
    bool stalePayload = true,
  }) {
    if (skipped == null || failure == null) return snapshot;
    final withOutcomes = snapshot.withReportingOutcomes(
      _combineOutcomes(snapshot.reportingOutcomes, [
        for (final outcome in failure.reportingOutcomes)
          if (outcome.failed &&
              outcome.connection.storageKey == skipped.connection)
            stalePayload
                ? ConnectionReportingOutcome(
                  connection: outcome.connection,
                  category: outcome.category,
                  source: ReportingOutcomeSource.cache,
                  freshness: ReportingOutcomeFreshness.stale,
                  credentialVersion: outcome.credentialVersion,
                  provisionalReadFailure: outcome.provisionalReadFailure,
                )
                : outcome,
      ]),
    );
    return stalePayload
        ? withOutcomes.withStaleStatus(
          syncIssue: failure.issue,
          syncDetails: failure.details,
          syncRejection: failure.syncRejection,
        )
        : withOutcomes;
  }

  DashboardSnapshot _finishSuccess(
    DashboardSnapshot connectionSnapshot,
    CapturedDashboardLoad capturedFallback, {
    VoidCallback? onSuccess,
  }) {
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
      if (error.snapshotOrdering.values.any(
        (order) => order.selectionUnverified,
      )) {
        rethrow;
      }
      onSuccess?.call();
      if (error.issue == DashboardSyncIssue.noProviders) {
        return connectionSnapshot;
      }
      return connectionSnapshot.withSyncIssue(
        error.issue,
        details: error.details,
        rejection: error.syncRejection,
      );
    } catch (error) {
      onSuccess?.call();
      return connectionSnapshot.withSyncIssue(
        DashboardSyncIssue.dashboardUnavailable,
        details: loadFailureDetails(error),
      );
    }

    if (!hasLiveAccount(other)) {
      onSuccess?.call();
      return connectionSnapshot;
    }

    try {
      final merged = DashboardSnapshot.fromJsonString(
            _mergeSnapshots([
              other.toJsonString(),
              connectionSnapshot.toJsonString(),
            ]),
          )
          .withConnectionVersions(
            {
              ...other.connectionVersions,
              ...connectionSnapshot.connectionVersions,
            },
            snapshotOrdering: {
              ...other.snapshotOrdering,
              ...connectionSnapshot.snapshotOrdering,
            },
          )
          .withReportingOutcomes(
            _combineOutcomes(
              other.reportingOutcomes,
              connectionSnapshot.reportingOutcomes,
            ),
          );
      final issue = other.syncIssue;
      final retainedIssue = connectionSnapshot.syncIssue;
      onSuccess?.call();
      return issue == null && retainedIssue == null
          ? merged
          : merged.withSyncIssue(
            issue ?? retainedIssue!,
            details:
                issue == null
                    ? connectionSnapshot.syncDetails
                    : other.syncDetails,
            rejection:
                issue == null
                    ? connectionSnapshot.syncRejection
                    : other.syncRejection,
          );
    } catch (error) {
      final details = loadFailureDetails(error);
      _logger.record(ProviderSyncEvent.invalidResponse, details: details);
      return other
          .withReportingOutcomes(connectionSnapshot.reportingOutcomes)
          .withSyncIssue(
            DashboardSyncIssue.dashboardUnavailable,
            details: details,
          );
    }
  }

  DashboardLoadException _superseded(
    DashboardSnapshot snapshot, {
    DashboardLoadException? failure,
    String? unverifiedConnection,
  }) => (failure ?? const DashboardLoadException(details: _connectionChanged))
      .withConnectionVersions(
        snapshot.connectionVersions,
        snapshotOrdering:
            unverifiedConnection == null
                ? snapshot.snapshotOrdering
                : {
                  ...snapshot.snapshotOrdering,
                  unverifiedConnection: _unverifiedSelection(
                    snapshot.snapshotOrdering[unverifiedConnection],
                  ),
                },
      );

  SnapshotOrdering _unverifiedSelection(SnapshotOrdering? order) =>
      SnapshotOrdering(
        payload: order?.payload,
        confirmedRowId: order?.confirmedRowId,
        cacheObservation: order?.cacheObservation,
        attemptEra: order?.attemptEra,
        emptyCacheOrder: order?.emptyCacheOrder,
        selectionUnverified: true,
      );

  DashboardLoadException _unverifiedFailure(
    DashboardLoadException failure,
    String connection,
  ) {
    final ordering = {
      ...failure.snapshotOrdering,
      connection: _unverifiedSelection(failure.snapshotOrdering[connection]),
    };
    final id = ProviderConnectionId.fromStorageKey(connection);
    // These throws follow a failed storage read. Keep that evidence even for
    // plan loaders whose sync issue also represents a provider outage.
    if (id == null ||
        failure.reportingOutcomes.any(
          (outcome) =>
              outcome.connection == id &&
              outcome.category == ReportingOutcomeCategory.localReadFailure,
        )) {
      return failure.withConnectionVersions(
        failure.connectionVersions,
        snapshotOrdering: ordering,
      );
    }
    return DashboardLoadException.withOutcomes(
      issue: failure.issue,
      details: failure.details,
      syncRejection: failure.syncRejection,
      reportingOutcomes: _combineOutcomes(failure.reportingOutcomes, [
        ConnectionReportingOutcome(
          connection: id,
          category: ReportingOutcomeCategory.localReadFailure,
          source: ReportingOutcomeSource.local,
        ),
      ]),
      connectionVersions: failure.connectionVersions,
      snapshotOrdering: ordering,
    );
  }

  DashboardLoadException _retiredFailure(
    Map<String, Map<String, String>> versions,
    Map<String, SnapshotOrdering> ordering, {
    DashboardLoadException? primary,
    required CapturedDashboardLoad sibling,
  }) {
    // A retired selection can carry diagnostics, but cannot qualify an
    // unversioned reader error that lacks a managed storage observation.
    final storageOutcomes = sibling.reportingOutcomes.where(
      (outcome) =>
          outcome.category == ReportingOutcomeCategory.localReadFailure &&
          !outcome.provisionalReadFailure,
    );
    final siblingFailure = sibling.loadException;
    final siblingSnapshot = sibling.snapshot;
    final siblingIssue = siblingFailure?.issue ?? siblingSnapshot?.syncIssue;
    // The plan loaders also use their unavailable issues for local read errors.
    final storageIssue = switch (siblingIssue) {
      DashboardSyncIssue.credentialUnavailable
          when _hasRetainedCredentialIssue(sibling.reportingOutcomes) =>
        siblingIssue,
      DashboardSyncIssue.codexUnavailable
          when storageOutcomes.any(
            (outcome) => outcome.connection == ProviderConnections.codexPlan,
          ) =>
        siblingIssue,
      DashboardSyncIssue.claudeUnavailable
          when storageOutcomes.any(
            (outcome) => outcome.connection == ProviderConnections.claudePlan,
          ) =>
        siblingIssue,
      _ => null,
    };
    final cause = switch (primary) {
      null ||
      DashboardLoadException(issue: DashboardSyncIssue.noProviders) ||
      DashboardLoadException(
        issue: DashboardSyncIssue.dashboardUnavailable,
        details: _connectionChanged,
        syncRejection: null,
      ) ||
      DashboardLoadException(
        issue: DashboardSyncIssue.dashboardUnavailable,
        details: null,
        syncRejection: null,
        reportingOutcomes: [],
      ) => null,
      DashboardLoadException(
        issue: DashboardSyncIssue.credentialUnavailable,
        :final reportingOutcomes,
      )
          when !_hasRetainedCredentialIssue(reportingOutcomes) =>
        null,
      _ => primary,
    };
    return DashboardLoadException.withOutcomes(
      issue:
          cause?.issue ??
          storageIssue ??
          DashboardSyncIssue.dashboardUnavailable,
      details:
          cause != null
              ? cause.details
              : storageIssue != null
              ? siblingFailure?.details ?? siblingSnapshot?.syncDetails
              : _connectionChanged,
      syncRejection: cause?.syncRejection,
      reportingOutcomes: _combineOutcomes(
        storageOutcomes,
        primary?.reportingOutcomes.where(
              (outcome) => !outcome.provisionalReadFailure,
            ) ??
            const [],
      ),
      connectionVersions: versions,
      snapshotOrdering: ordering,
    );
  }

  bool _hasRetainedCredentialIssue(List<ConnectionReportingOutcome> outcomes) =>
      !outcomes.any((outcome) => outcome.provisionalReadFailure) ||
      outcomes.any(
        (outcome) =>
            outcome.category == ReportingOutcomeCategory.localReadFailure &&
            !outcome.provisionalReadFailure,
      );

  bool _hasLocalStorageDiagnostic(DashboardLoadException failure) =>
      failure.issue == DashboardSyncIssue.credentialUnavailable ||
      failure.reportingOutcomes.any(
        (outcome) =>
            outcome.category == ReportingOutcomeCategory.localReadFailure,
      );

  bool _isUnverifiedStorageFailure(DashboardLoadException failure) =>
      _hasLocalStorageDiagnostic(failure) &&
      failure.snapshotOrdering.values.any((order) => order.selectionUnverified);

  bool _isUnversionedReadFailure(ConnectionReportingOutcome outcome) =>
      outcome.category == ReportingOutcomeCategory.localReadFailure &&
      outcome.credentialVersion == null;

  @override
  Future<bool> isSnapshotCurrent(DashboardSnapshot snapshot) async {
    final cache = _cache;
    if (snapshot.snapshotOrdering.values.any(
      (order) => order.selectionUnverified,
    )) {
      return false;
    }
    final hasUnversionedReadFailure = snapshot.reportingOutcomes.any(
      _isUnversionedReadFailure,
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
            outcome.connection == id && _isUnversionedReadFailure(outcome),
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
    // A fallback carrying deletion evidence can make the final native check.
    final checkCredentialsFirst =
        cache == null &&
        access != null &&
        snapshot.connectionVersions.values.any(
          (version) => version.containsKey('absentRead'),
        );
    if (!checkCredentialsFirst &&
        !await _fallback.isSnapshotCurrent(snapshot)) {
      return false;
    }
    if (cache != null) return cache.validSnapshot(snapshot);
    final carried = snapshot.connectionVersions[id?.storageKey];
    if (access != null) {
      for (final version in [
        if (carried != null && !CredentialVersion(carried).isAbsent)
          CredentialVersion(carried),
        for (final outcome in snapshot.reportingOutcomes)
          if (outcome.connection == id) outcome.credentialVersion,
      ]) {
        if (version != null && !await access.isCurrent(version)) return false;
      }
    }
    if (checkCredentialsFirst && !await _fallback.isSnapshotCurrent(snapshot)) {
      return false;
    }
    if (carried?.containsKey('absentRead') != true) return true;
    final platform = _absencePlatform;
    if (platform == null) return false;
    return validateSnapshotSelection(
      snapshot,
      platform,
      allowUnstampedAccounts: true,
    );
  }

  @override
  Future<void> clearPersistentSnapshots() async {
    final revision = ++_cacheRevision;
    await _cache?.clear();
    if (revision == _cacheRevision) _lastSuccessfulConnectionSnapshot = null;
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
    ConnectionCacheRecord? cached, {
    bool hasTypedCause = false,
    String? failedCacheOrder,
  }) => (
    snapshot: null,
    failure: failure,
    hasTypedCause: hasTypedCause,
    cached: cached,
    remembered: null,
    failedCacheOrder: failedCacheOrder,
    skipped: null,
  );

  DashboardSnapshot? _recover(
    CapturedDashboardLoad capturedFallback,
    DashboardLoadException failure,
    DashboardSnapshot? cached, {
    required VoidCallback onCached,
  }) {
    final siblingFailure = capturedFallback.loadException;
    if (siblingFailure != null && _isUnverifiedStorageFailure(siblingFailure)) {
      // The sibling retires the aggregate without replacing the primary issue.
      throw failure.withConnectionVersions(
        failure.connectionVersions,
        snapshotOrdering: siblingFailure.snapshotOrdering,
      );
    }
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
    other = other?.withReportingOutcomes(outcomes);
    final hasFallback = other != null && hasLiveAccount(other);
    if (cached == null) {
      if (hasFallback) {
        return other.withSyncIssue(
          failure.issue,
          details: failure.details,
          rejection: failure.syncRejection,
        );
      }
      return null;
    }

    final stale = cached
        .withReportingOutcomes(outcomes)
        .withStaleStatus(
          syncIssue: failure.issue,
          syncDetails: failure.details,
          syncRejection: failure.syncRejection,
        );
    if (hasFallback) {
      try {
        final merged = DashboardSnapshot.fromJsonString(
              _mergeSnapshots([other.toJsonString(), stale.toJsonString()]),
            )
            .withConnectionVersions(
              {...other.connectionVersions, ...stale.connectionVersions},
              snapshotOrdering: {
                ...other.snapshotOrdering,
                ...stale.snapshotOrdering,
              },
            )
            .withReportingOutcomes(outcomes);
        onCached();
        return merged.withSyncIssue(
          failure.issue,
          details: failure.details,
          rejection: failure.syncRejection,
        );
      } catch (error) {
        _logger.record(
          ProviderSyncEvent.invalidResponse,
          details: loadFailureDetails(error),
        );
        return other.withSyncIssue(
          failure.issue,
          details: failure.details,
          rejection: failure.syncRejection,
        );
      }
    }
    onCached();
    return stale;
  }
}

bool _sameConnectionVersions(
  Map<String, Map<String, String>> first,
  Map<String, Map<String, String>> second,
) =>
    first.length == second.length &&
    first.entries.every((entry) => mapEquals(entry.value, second[entry.key]));

List<ConnectionReportingOutcome> _combineOutcomes(
  Iterable<ConnectionReportingOutcome> first,
  Iterable<ConnectionReportingOutcome> second,
) => {
  for (final outcome in [...first, ...second]) outcome.connection: outcome,
}.values.toList(growable: false);
