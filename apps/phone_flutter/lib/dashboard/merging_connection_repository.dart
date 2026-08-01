import 'package:ward_pulse_bindings/ward_pulse_bindings.dart';

import '../sync/provider_sync_logger.dart';
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
/// keep other providers visible when the fallback still has live accounts.
final class MergingConnectionRepository extends DashboardRepository {
  MergingConnectionRepository({
    required DashboardRepository fallback,
    required ConnectionReportLoader loadReport,
    required ReportNormalizer normalizeReport,
    required DashboardLoadException Function(Object error) mapError,
    ProviderSyncLogger logger = const DeveloperProviderSyncLogger(),
    DashboardSnapshotMerger mergeSnapshots = mergeDashboardSnapshotsJson,
  }) : _fallback = fallback,
       _loadReport = loadReport,
       _normalizeReport = normalizeReport,
       _mapError = mapError,
       _logger = logger,
       _mergeSnapshots = mergeSnapshots;

  final DashboardRepository _fallback;
  final ConnectionReportLoader _loadReport;
  final ReportNormalizer _normalizeReport;
  final DashboardLoadException Function(Object error) _mapError;
  final ProviderSyncLogger _logger;
  final DashboardSnapshotMerger _mergeSnapshots;

  DashboardSnapshot? _lastSuccessfulSnapshot;

  @override
  Future<DashboardSnapshot> load() async {
    final fallback = CapturedDashboardLoad.capture(_fallback.load);
    final String? report;
    try {
      report = await _loadReport();
    } catch (error) {
      return _recover(fallback, _mapError(error));
    }
    if (report == null) {
      return (await fallback).value;
    }

    final String normalized;
    try {
      normalized = _normalizeReport(report);
    } catch (error) {
      return _recover(
        fallback,
        _mapError(StateError('Normalize failed: ${loadFailureDetails(error)}')),
      );
    }

    final DashboardSnapshot connectionSnapshot;
    try {
      connectionSnapshot = DashboardSnapshot.fromJsonString(normalized);
    } catch (error) {
      return _recover(
        fallback,
        _mapError(
          StateError('Dashboard parse failed: ${loadFailureDetails(error)}'),
        ),
      );
    }

    final DashboardSnapshot other;
    try {
      other = (await fallback).value;
    } on DashboardLoadException catch (error) {
      _logger.record(ProviderSyncEvent.succeeded);
      if (error.issue == DashboardSyncIssue.noProviders) {
        return _remember(connectionSnapshot);
      }
      return _remember(
        connectionSnapshot,
      ).withSyncIssue(error.issue, details: error.details);
    } catch (error) {
      _logger.record(ProviderSyncEvent.succeeded);
      return _remember(connectionSnapshot).withSyncIssue(
        DashboardSyncIssue.dashboardUnavailable,
        details: loadFailureDetails(error),
      );
    }

    if (!hasLiveAccount(other)) {
      _logger.record(ProviderSyncEvent.succeeded);
      return _remember(connectionSnapshot);
    }

    try {
      final merged = DashboardSnapshot.fromJsonString(
        _mergeSnapshots([other.toJsonString(), normalized]),
      );
      _logger.record(ProviderSyncEvent.succeeded);
      final remembered = _remember(merged);
      final issue = other.syncIssue;
      return issue == null
          ? remembered
          : remembered.withSyncIssue(issue, details: other.syncDetails);
    } catch (error) {
      final details = loadFailureDetails(error);
      _logger.record(ProviderSyncEvent.invalidResponse, details: details);
      return _remember(connectionSnapshot).withSyncIssue(
        DashboardSyncIssue.dashboardUnavailable,
        details: details,
      );
    }
  }

  @override
  void invalidate() {
    _lastSuccessfulSnapshot = null;
    _fallback.invalidate();
  }

  Future<DashboardSnapshot> _recover(
    Future<CapturedDashboardLoad> fallback,
    DashboardLoadException failure,
  ) async {
    try {
      final snapshot = (await fallback).value;
      if (hasLiveAccount(snapshot)) {
        return snapshot.withSyncIssue(failure.issue, details: failure.details);
      }
    } catch (_) {
      // Prefer the connection-specific issue when nothing else is live.
    }
    final cached = _lastSuccessfulSnapshot;
    if (cached != null) {
      _logger.record(ProviderSyncEvent.usingCachedSnapshot);
      return cached.withStaleStatus(
        syncIssue: failure.issue,
        syncDetails: failure.details,
      );
    }
    throw failure;
  }

  DashboardSnapshot _remember(DashboardSnapshot snapshot) {
    _lastSuccessfulSnapshot = snapshot;
    return snapshot;
  }
}
