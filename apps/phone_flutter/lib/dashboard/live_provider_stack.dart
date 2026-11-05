import 'dart:convert';

import 'package:ward_pulse_bindings/ward_pulse_bindings.dart';

import '../providers/claude_account_service.dart';
import '../providers/connection_lifecycle.dart';
import '../providers/provider_connection.dart';
import '../providers/provider_credential_store.dart';
import '../sync/provider_reporting.dart';
import '../sync/provider_reporting_clients.dart';
import '../sync/provider_sync_logger.dart';
import '../sync/report_period.dart';
import 'claude_dashboard_repository.dart';
import 'dashboard_load.dart';
import 'dashboard_models.dart';
import 'dashboard_repository.dart';
import 'merging_connection_repository.dart';
import 'connection_snapshot_cache.dart';

/// Chains every credential-backed connection in front of [openAiAndCodex].
///
/// Each link merges its own provider report and falls back to the links behind
/// it, so one unconfigured or failing connection never hides the others.
DashboardRepository buildLiveProviderStack({
  required ProviderCredentialStore credentialStore,
  required ClaudeAccountService claudeAccountService,
  required DashboardRepository openAiAndCodex,
  Map<String, ConnectionSnapshotCache> caches = const {},
  ProviderSyncLogger logger = const DeveloperProviderSyncLogger(),
  DateTime Function()? clock,
  AnthropicReportingClient? anthropicReportingClient,
  CursorPlatformClient? cursorReportingClient,
  CursorPlanClient? cursorSessionClient,
  ReportNormalizer normalizeAnthropicReport = normalizeAnthropicReportJson,
  ReportNormalizer normalizeCursorPlatformReport =
      normalizeCursorPlatformReportJson,
  DashboardSnapshotMerger mergeSnapshots = mergeDashboardSnapshotsJson,
}) {
  final now = clock ?? DateTime.now;
  final anthropicClient =
      anthropicReportingClient ?? AnthropicReportingClient();
  final cursorPlanClient = cursorSessionClient ?? CursorPlanClient();
  final cursorPlatformClient = cursorReportingClient ?? CursorPlatformClient();

  DashboardRepository connect({
    required String connection,
    required DashboardRepository fallback,
    required ReportNormalizer normalizeReport,
    ConnectionReportLoader? loadReport,
    Future<String> Function(String credential)? loadCredentialReport,
  }) {
    return MergingConnectionRepository(
      cache: caches[connection],
      connection: ProviderConnectionId.fromStorageKey(connection),
      credentialStore: credentialStore,
      loadCredentialReport: loadCredentialReport,
      mergeSnapshots: mergeSnapshots,
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
      final store = credentialStore;
      final access =
          store is VersionedProviderCredentialStore
              ? (store as VersionedProviderCredentialStore).credentialAccess(
                connection,
              )
              : null;
      Future<String?> load() async {
        VersionedCredential<String>? credential;
        final token = await readConnectionSecret(
          store: store,
          id: connection,
          logger: logger,
          readSecret:
              access == null
                  ? null
                  : () async {
                    credential = await access.read();
                    return credential?.value;
                  },
        );
        final captured = credential;
        if (token == null) return null;
        try {
          final report = await fetch(token);
          if (captured != null && !await access!.isCurrent(captured.version))
            throw StateError('Connection changed during refresh.');
          return jsonEncode({
            ...decodeReportObject(report),
            'accountId': accountId,
            'generatedAt': now().toUtc().toIso8601String(),
          });
        } on ProviderReportingException catch (error) {
          if (error.failure == ProviderReportingFailure.authentication &&
              captured != null) {
            if (access case final ConnectionRejectionRecorder recorder) {
              if (!await recorder.rejectAuthentication(captured.version))
                throw StateError('Connection changed during refresh.');
              final event = captured.version.values['committedConnection'];
              throw DashboardLoadException(
                issue: DashboardSyncIssue.authentication,
                syncRejection:
                    event == null
                        ? null
                        : (connection: connection.storageKey, eventId: event),
              );
            }
          }
          rethrow;
        }
      }

      return access == null ? load() : access.serializeFetch(load);
    };
  }

  final anthropic = connect(
    connection: ProviderConnections.anthropicPlatform.storageKey,
    fallback: openAiAndCodex,
    normalizeReport: normalizeAnthropicReport,
    loadCredentialReport: (key) async {
      final period = ReportPeriodBounds.utc(now());
      final reports = await anthropicClient.fetchDailyReports(
        apiKey: key,
        start: period.reportStart,
        end: period.generatedAt,
      );
      return jsonEncode({
        'accountId': 'anthropic-local',
        'generatedAt': period.generatedAt.toIso8601String(),
        'capturedEndMicros': period.generatedAt.microsecondsSinceEpoch,
        'todayStart': period.todayStart.toIso8601String(),
        'weekStart': period.weekStart.toIso8601String(),
        'monthStart': period.monthStart.toIso8601String(),
        'usagePages': reports.usage,
        'costPages': reports.costs,
      });
    },
  );

  final claude = claudeDashboardRepository(
    accountService: claudeAccountService,
    mergeSnapshots: mergeSnapshots,
    cache: caches[ProviderConnections.claudePlan.storageKey],
    fallback: anthropic,
    logger: logger,
  );

  final cursorTeam = connect(
    connection: ProviderConnections.cursorPlatform.storageKey,
    fallback: claude,
    normalizeReport: normalizeCursorPlatformReport,
    loadCredentialReport: (key) async {
      final period = ReportPeriodBounds.utc(now());
      final reports = await cursorPlatformClient.fetchReports(
        adminApiKey: key,
        period: period,
      );
      return jsonEncode({
        'accountId': 'cursor-team-local',
        'generatedAt': period.generatedAt.toIso8601String(),
        'requestStartMs': period.requestStartMs,
        'endExclusiveMs': period.endExclusiveMs,
        'todayStartMs': period.todayStartMs,
        'weekStartMs': period.weekStartMs,
        'monthStartMs': period.monthStartMs,
        'dailyUsagePages': reports.dailyUsage,
        'usageEventPages': reports.usageEvents,
      });
    },
  );

  return connect(
    connection: ProviderConnections.cursorPlan.storageKey,
    fallback: cursorTeam,
    normalizeReport: normalizeCursorPlanReportJson,
    loadReport: planReport(
      connection: ProviderConnections.cursorPlan,
      accountId: 'cursor-local',
      fetch: (token) => cursorPlanClient.fetchUsageSummary(sessionToken: token),
    ),
  );
}
