import 'dart:convert';

import 'package:ward_pulse_bindings/ward_pulse_bindings.dart';

import '../providers/provider_connection.dart';
import '../providers/provider_credential_store.dart';
import '../sync/provider_reporting.dart';
import '../sync/provider_reporting_clients.dart';
import '../sync/provider_sync_logger.dart';
import '../sync/report_period.dart';
import 'dashboard_load.dart';
import 'dashboard_repository.dart';
import 'merging_connection_repository.dart';

/// Chains every credential-backed connection in front of [openAiAndCodex].
///
/// Each link merges its own provider report and falls back to the links behind
/// it, so one unconfigured or failing connection never hides the others.
DashboardRepository buildLiveProviderStack({
  required ProviderCredentialStore credentialStore,
  required DashboardRepository openAiAndCodex,
  ProviderSyncLogger logger = const DeveloperProviderSyncLogger(),
  DateTime Function()? clock,
}) {
  final now = clock ?? DateTime.now;
  final anthropicClient = AnthropicReportingClient();
  final claudeClient = ClaudeUsageClient();
  final cursorPlanClient = CursorPlanClient();
  final cursorPlatformClient = CursorPlatformClient(clock: now);

  DashboardRepository connect({
    required DashboardRepository fallback,
    required ReportNormalizer normalizeReport,
    required ConnectionReportLoader loadReport,
  }) {
    return MergingConnectionRepository(
      fallback: fallback,
      logger: logger,
      mapError: (error) => mapReportingError(error, logger),
      normalizeReport: normalizeReport,
      loadReport: loadReport,
    );
  }

  /// Plan reports arrive as one object that only needs report envelope fields.
  ConnectionReportLoader planReport({
    required ProviderConnectionId connection,
    required String accountId,
    required Future<String> Function(String token) fetch,
  }) {
    return () async {
      final token = await readConnectionSecret(
        store: credentialStore,
        id: connection,
        logger: logger,
      );
      if (token == null) {
        return null;
      }
      return jsonEncode({
        ...decodeReportObject(await fetch(token)),
        'accountId': accountId,
        'generatedAt': now().toUtc().toIso8601String(),
      });
    };
  }

  final anthropic = connect(
    fallback: openAiAndCodex,
    normalizeReport: normalizeAnthropicReportJson,
    loadReport: () async {
      final key = await readConnectionSecret(
        store: credentialStore,
        id: ProviderConnections.anthropicPlatform,
        logger: logger,
      );
      if (key == null) {
        return null;
      }
      final period = ReportPeriodBounds.utc(now());
      final reports = await anthropicClient.fetchDailyReports(
        adminApiKey: key,
        start: period.reportStart,
        end: period.generatedAt,
      );
      return jsonEncode({
        'accountId': 'anthropic-local',
        'generatedAt': period.generatedAt.toIso8601String(),
        'todayStart': period.todayStart.toIso8601String(),
        'weekStart': period.weekStart.toIso8601String(),
        'monthStart': period.monthStart.toIso8601String(),
        'usagePages': reports.usage,
        'costPages': reports.costs,
      });
    },
  );

  final claude = connect(
    fallback: anthropic,
    normalizeReport: normalizeClaudeReportJson,
    loadReport: planReport(
      connection: ProviderConnections.claudePlan,
      accountId: 'claude-local',
      fetch: (token) => claudeClient.fetchUsage(oauthToken: token),
    ),
  );

  final cursorTeam = connect(
    fallback: claude,
    normalizeReport: normalizeCursorPlatformReportJson,
    loadReport: () async {
      final key = await readConnectionSecret(
        store: credentialStore,
        id: ProviderConnections.cursorPlatform,
        logger: logger,
      );
      if (key == null) {
        return null;
      }
      final reports = await cursorPlatformClient.fetchReports(adminApiKey: key);
      return jsonEncode({
        'accountId': 'cursor-team-local',
        'generatedAt': now().toUtc().toIso8601String(),
        'dailyUsagePages': reports.dailyUsage,
        'spendPages': reports.spend,
      });
    },
  );

  return connect(
    fallback: cursorTeam,
    normalizeReport: normalizeCursorPlanReportJson,
    loadReport: planReport(
      connection: ProviderConnections.cursorPlan,
      accountId: 'cursor-local',
      fetch: (token) => cursorPlanClient.fetchUsageSummary(sessionToken: token),
    ),
  );
}
