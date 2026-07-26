import 'package:ward_pulse_bindings/ward_pulse_bindings.dart';

import '../providers/claude_account_service.dart';
import '../sync/claude_account_client.dart';
import '../sync/provider_sync_logger.dart';
import 'dashboard_models.dart';
import 'dashboard_load.dart';
import 'dashboard_repository.dart';
import 'merging_connection_repository.dart';

/// Merges the on-device Claude subscription report into [fallback].
DashboardRepository claudeDashboardRepository({
  required ClaudeAccountService accountService,
  required DashboardRepository fallback,
  ProviderSyncLogger logger = const DeveloperProviderSyncLogger(),
  ReportNormalizer normalizeReport = normalizeClaudeReportJson,
  DashboardSnapshotMerger mergeSnapshots = mergeDashboardSnapshotsJson,
  ConnectionReportLoader? loadReport,
}) {
  return MergingConnectionRepository(
    fallback: fallback,
    logger: logger,
    loadReport: loadReport ?? accountService.fetchReport,
    normalizeReport: normalizeReport,
    mergeSnapshots: mergeSnapshots,
    mapError: (error) => _mapClaudeError(error, logger),
  );
}

DashboardLoadException _mapClaudeError(Object error, ProviderSyncLogger logger) {
  if (error is! ClaudeAccountException) {
    final details = loadFailureDetails(error);
    logger.record(ProviderSyncEvent.invalidResponse, details: details);
    return DashboardLoadException(
      issue: DashboardSyncIssue.claudeInvalidResponse,
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

ProviderSyncEvent _eventFor(ClaudeAccountFailure failure) {
  return switch (failure) {
    ClaudeAccountFailure.authentication =>
      ProviderSyncEvent.authenticationRequired,
    ClaudeAccountFailure.permissionDenied => ProviderSyncEvent.permissionDenied,
    ClaudeAccountFailure.rateLimited => ProviderSyncEvent.rateLimited,
    ClaudeAccountFailure.unavailable => ProviderSyncEvent.unavailable,
    ClaudeAccountFailure.invalidResponse => ProviderSyncEvent.invalidResponse,
    ClaudeAccountFailure.cancelled => ProviderSyncEvent.unavailable,
  };
}

DashboardSyncIssue _issueFor(ClaudeAccountFailure failure) {
  return switch (failure) {
    ClaudeAccountFailure.authentication =>
      DashboardSyncIssue.claudeAuthentication,
    ClaudeAccountFailure.permissionDenied =>
      DashboardSyncIssue.claudePermissionDenied,
    ClaudeAccountFailure.rateLimited => DashboardSyncIssue.rateLimited,
    ClaudeAccountFailure.unavailable => DashboardSyncIssue.claudeUnavailable,
    ClaudeAccountFailure.invalidResponse =>
      DashboardSyncIssue.claudeInvalidResponse,
    ClaudeAccountFailure.cancelled => DashboardSyncIssue.claudeUnavailable,
  };
}
