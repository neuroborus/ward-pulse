import 'package:ward_pulse_bindings/ward_pulse_bindings.dart';

import '../providers/codex_account_service.dart';
import '../sync/codex_account_client.dart';
import '../sync/provider_sync_logger.dart';
import 'dashboard_models.dart';
import 'dashboard_load.dart';
import 'dashboard_repository.dart';
import 'merging_connection_repository.dart';

/// Merges the on-device Codex subscription report into [fallback].
DashboardRepository codexDashboardRepository({
  required CodexAccountService accountService,
  required DashboardRepository fallback,
  ProviderSyncLogger logger = const DeveloperProviderSyncLogger(),
  ReportNormalizer normalizeReport = normalizeCodexReportJson,
  DashboardSnapshotMerger mergeSnapshots = mergeDashboardSnapshotsJson,
  ConnectionReportLoader? loadReport,
}) {
  return MergingConnectionRepository(
    fallback: fallback,
    logger: logger,
    loadReport: loadReport ?? accountService.fetchReport,
    normalizeReport: normalizeReport,
    mergeSnapshots: mergeSnapshots,
    mapError: (error) => _mapCodexError(error, logger),
  );
}

DashboardLoadException _mapCodexError(Object error, ProviderSyncLogger logger) {
  if (error is! CodexAccountException) {
    final details = loadFailureDetails(error);
    logger.record(ProviderSyncEvent.invalidResponse, details: details);
    return DashboardLoadException(
      issue: DashboardSyncIssue.codexInvalidResponse,
      details: details,
    );
  }
  final details = error.details ?? loadFailureDetails(error);
  logger.record(_eventFor(error.failure), details: details);
  return DashboardLoadException(
    issue: _issueFor(error.failure),
    details: details,
  );
}

ProviderSyncEvent _eventFor(CodexAccountFailure failure) {
  return switch (failure) {
    CodexAccountFailure.authentication =>
      ProviderSyncEvent.authenticationRequired,
    CodexAccountFailure.permissionDenied => ProviderSyncEvent.permissionDenied,
    CodexAccountFailure.rateLimited => ProviderSyncEvent.rateLimited,
    CodexAccountFailure.unavailable => ProviderSyncEvent.unavailable,
    CodexAccountFailure.invalidResponse => ProviderSyncEvent.invalidResponse,
    CodexAccountFailure.cancelled => ProviderSyncEvent.unavailable,
  };
}

DashboardSyncIssue _issueFor(CodexAccountFailure failure) {
  return switch (failure) {
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
