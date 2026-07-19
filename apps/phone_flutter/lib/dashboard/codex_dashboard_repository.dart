import 'package:ward_pulse_bindings/ward_pulse_bindings.dart';

import '../providers/codex_account_service.dart';
import '../sync/codex_account_client.dart';
import '../sync/provider_sync_logger.dart';
import 'dashboard_models.dart';
import 'dashboard_repository.dart';

typedef CodexReportNormalizer = String Function(String reportJson);
typedef CodexReportLoader = Future<String?> Function();
typedef DashboardSnapshotMerger = String Function(Iterable<String> snapshots);

final class CodexDashboardRepository extends DashboardRepository {
  CodexDashboardRepository({
    required CodexAccountService accountService,
    required DashboardRepository fallback,
    ProviderSyncLogger logger = const DeveloperProviderSyncLogger(),
    CodexReportNormalizer normalizeReport = normalizeCodexReportJson,
    DashboardSnapshotMerger mergeSnapshots = mergeDashboardSnapshotsJson,
    CodexReportLoader? loadReport,
  }) : _fallback = fallback,
       _loadReport = loadReport ?? accountService.fetchReport,
       _logger = logger,
       _mergeSnapshots = mergeSnapshots,
       _normalizeReport = normalizeReport;

  final DashboardRepository _fallback;
  final CodexReportLoader _loadReport;
  final ProviderSyncLogger _logger;
  final DashboardSnapshotMerger _mergeSnapshots;
  final CodexReportNormalizer _normalizeReport;

  DashboardSnapshot? _lastSuccessfulSnapshot;

  @override
  Future<DashboardSnapshot> load() async {
    final fallback = _DashboardLoadResult.capture(_fallback.load);
    final String? report;
    try {
      report = await _loadReport();
    } on CodexAccountException catch (error) {
      return _recoverFromCodexFailure(
        fallback,
        _issueFor(error),
        details: error.details,
      );
    } catch (error) {
      final details = 'Unexpected ${error.runtimeType}';
      _logger.record(ProviderSyncEvent.invalidResponse, details: details);
      return _recoverFromCodexFailure(
        fallback,
        DashboardSyncIssue.codexInvalidResponse,
        details: details,
      );
    }
    if (report == null) {
      return (await fallback).value;
    }

    final String codexJson;
    final DashboardSnapshot codexSnapshot;
    try {
      codexJson = _normalizeReport(report);
      codexSnapshot = DashboardSnapshot.fromJsonString(codexJson);
    } on WardPulseBindingsException catch (error) {
      _logger.record(ProviderSyncEvent.invalidResponse, details: error.message);
      return _recoverFromCodexFailure(
        fallback,
        DashboardSyncIssue.codexInvalidResponse,
        details: error.message,
      );
    } catch (error) {
      final details = 'Unexpected ${error.runtimeType}';
      _logger.record(ProviderSyncEvent.invalidResponse, details: details);
      return _recoverFromCodexFailure(
        fallback,
        DashboardSyncIssue.codexInvalidResponse,
        details: details,
      );
    }

    final DashboardSnapshot platformSnapshot;
    try {
      platformSnapshot = (await fallback).value;
    } on DashboardLoadException catch (error) {
      _logger.record(ProviderSyncEvent.succeeded);
      return _remember(
        codexSnapshot,
      ).withSyncIssue(error.issue, details: error.details);
    } catch (error) {
      _logger.record(ProviderSyncEvent.succeeded);
      return _remember(codexSnapshot).withSyncIssue(
        DashboardSyncIssue.dashboardUnavailable,
        details: 'Unexpected ${error.runtimeType}',
      );
    }

    if (!_hasLiveAccount(platformSnapshot)) {
      _logger.record(ProviderSyncEvent.succeeded);
      return _remember(codexSnapshot);
    }

    try {
      final merged = DashboardSnapshot.fromJsonString(
        _mergeSnapshots([platformSnapshot.toJsonString(), codexJson]),
      );
      _logger.record(ProviderSyncEvent.succeeded);
      final result = _remember(merged);
      final issue = platformSnapshot.syncIssue;
      return issue == null
          ? result
          : result.withSyncIssue(issue, details: platformSnapshot.syncDetails);
    } on WardPulseBindingsException catch (error) {
      _logger.record(ProviderSyncEvent.invalidResponse, details: error.message);
      return _remember(codexSnapshot).withSyncIssue(
        DashboardSyncIssue.dashboardUnavailable,
        details: error.message,
      );
    } catch (error) {
      final details = 'Unexpected ${error.runtimeType}';
      _logger.record(ProviderSyncEvent.invalidResponse, details: details);
      return _remember(codexSnapshot).withSyncIssue(
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

  Future<DashboardSnapshot> _cachedOrThrow(
    DashboardSyncIssue issue, {
    String? details,
  }) {
    final cached = _lastSuccessfulSnapshot;
    if (cached != null) {
      return Future.value(
        cached.withStaleStatus(syncIssue: issue, syncDetails: details),
      );
    }

    return Future.error(DashboardLoadException(issue: issue, details: details));
  }

  Future<DashboardSnapshot> _recoverFromCodexFailure(
    Future<_DashboardLoadResult> fallback,
    DashboardSyncIssue issue, {
    String? details,
  }) async {
    try {
      final snapshot = (await fallback).value;
      if (_hasLiveAccount(snapshot)) {
        return snapshot.withSyncIssue(issue, details: details);
      }
    } catch (_) {
      // The Codex failure remains the most specific actionable error.
    }
    return _cachedOrThrow(issue, details: details);
  }

  DashboardSyncIssue _issueFor(CodexAccountException error) {
    final event = switch (error.failure) {
      CodexAccountFailure.authentication =>
        ProviderSyncEvent.authenticationRequired,
      CodexAccountFailure.permissionDenied =>
        ProviderSyncEvent.permissionDenied,
      CodexAccountFailure.rateLimited => ProviderSyncEvent.rateLimited,
      CodexAccountFailure.unavailable => ProviderSyncEvent.unavailable,
      CodexAccountFailure.invalidResponse => ProviderSyncEvent.invalidResponse,
      CodexAccountFailure.cancelled => ProviderSyncEvent.unavailable,
    };
    _logger.record(event, details: error.details);
    return switch (error.failure) {
      CodexAccountFailure.authentication =>
        DashboardSyncIssue.codexAuthentication,
      CodexAccountFailure.permissionDenied =>
        DashboardSyncIssue.codexPermissionDenied,
      CodexAccountFailure.rateLimited => DashboardSyncIssue.rateLimited,
      CodexAccountFailure.unavailable => DashboardSyncIssue.codexUnavailable,
      CodexAccountFailure.invalidResponse =>
        DashboardSyncIssue.codexInvalidResponse,
      CodexAccountFailure.cancelled => DashboardSyncIssue.codexUnavailable,
    };
  }

  DashboardSnapshot _remember(DashboardSnapshot snapshot) {
    _lastSuccessfulSnapshot = snapshot;
    return snapshot;
  }
}

final class _DashboardLoadResult {
  const _DashboardLoadResult.success(this._value)
    : _error = null,
      _stackTrace = null;

  const _DashboardLoadResult.failure(this._error, this._stackTrace)
    : _value = null;

  final DashboardSnapshot? _value;
  final Object? _error;
  final StackTrace? _stackTrace;

  DashboardSnapshot get value {
    final value = _value;
    if (value != null) {
      return value;
    }
    Error.throwWithStackTrace(_error!, _stackTrace!);
  }

  static Future<_DashboardLoadResult> capture(
    Future<DashboardSnapshot> Function() load,
  ) async {
    try {
      return _DashboardLoadResult.success(await load());
    } catch (error, stackTrace) {
      return _DashboardLoadResult.failure(error, stackTrace);
    }
  }
}

bool _hasLiveAccount(DashboardSnapshot snapshot) {
  return snapshot.accounts.any((account) => account.provider != 'mock');
}
