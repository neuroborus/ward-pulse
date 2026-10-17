import 'dart:convert';

import 'package:ward_pulse_bindings/ward_pulse_bindings.dart';

import '../providers/provider_connection.dart';
import '../providers/provider_credential_store.dart';
import '../sync/openai_reporting_client.dart';
import '../sync/provider_sync_logger.dart';
import '../sync/report_period.dart';
import 'dashboard_load.dart';
import 'dashboard_repository.dart';
import 'merging_connection_repository.dart';
import 'connection_snapshot_cache.dart';

/// Loads OpenAI Platform Admin reporting and merges it into [fallback].
DashboardRepository openAiDashboardRepository({
  required ProviderCredentialStore credentialStore,
  OpenAiReportingClient? client,
  DashboardRepository? fallback,
  ConnectionSnapshotCache? cache,
  ProviderSyncLogger logger = const DeveloperProviderSyncLogger(),
  ReportNormalizer normalizeReport = normalizeOpenAiReportJson,
  DashboardSnapshotMerger mergeSnapshots = mergeDashboardSnapshotsJson,
  DateTime Function()? clock,
}) {
  final reporting = client ?? OpenAiReportingClient();
  final now = clock ?? DateTime.now;

  return MergingConnectionRepository(
    cache: cache,
    connection: ProviderConnections.openAiPlatform,
    credentialStore: credentialStore,
    mergeSnapshots: mergeSnapshots,
    fallback: fallback ?? const NoProvidersDashboardRepository(),
    logger: logger,
    normalizeReport: normalizeReport,
    mapError: (error) => mapReportingError(error, logger),
    loadCredentialReport: (adminApiKey) async {
      final period = ReportPeriodBounds.utc(now());
      final reports = await reporting.fetchDailyReports(
        adminApiKey: adminApiKey,
        start: period.reportStart,
        end: period.generatedAt,
      );
      return jsonEncode({
        'accountId': 'openai-local',
        'generatedAt': period.generatedAt.toIso8601String(),
        'todayStart': period.todayStart.millisecondsSinceEpoch ~/ 1000,
        'weekStart': period.weekStart.millisecondsSinceEpoch ~/ 1000,
        'monthStart': period.monthStart.millisecondsSinceEpoch ~/ 1000,
        'usagePages': reports.usage,
        'costPages': reports.costs,
      });
    },
  );
}
