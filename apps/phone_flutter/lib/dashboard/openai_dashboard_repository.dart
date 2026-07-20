import 'dart:convert';

import 'package:ward_pulse_bindings/ward_pulse_bindings.dart';

import '../providers/provider_credential_store.dart';
import '../sync/openai_reporting_client.dart';
import '../sync/provider_sync_logger.dart';
import 'dashboard_models.dart';
import 'dashboard_repository.dart';

typedef OpenAiReportNormalizer = String Function(String reportJson);

final class OpenAiDashboardRepository extends DashboardRepository {
  OpenAiDashboardRepository({
    required ProviderCredentialStore credentialStore,
    OpenAiReportingClient? client,
    DashboardRepository? fallback,
    ProviderSyncLogger logger = const DeveloperProviderSyncLogger(),
    OpenAiReportNormalizer normalizeReport = normalizeOpenAiReportJson,
    DateTime Function()? clock,
  }) : _credentialStore = credentialStore,
       _client = client ?? OpenAiReportingClient(),
       _fallback = fallback,
       _logger = logger,
       _normalizeReport = normalizeReport,
       _clock = clock ?? DateTime.now;

  final ProviderCredentialStore _credentialStore;
  final OpenAiReportingClient _client;
  final DashboardRepository? _fallback;
  final ProviderSyncLogger _logger;
  final OpenAiReportNormalizer _normalizeReport;
  final DateTime Function() _clock;

  DashboardSnapshot? _lastSuccessfulSnapshot;

  @override
  Future<DashboardSnapshot> load() async {
    final String? adminApiKey;
    try {
      adminApiKey = await _credentialStore.readOpenAiAdminKey();
    } catch (_) {
      _logger.record(ProviderSyncEvent.unavailable);
      return _cachedOrThrow(DashboardSyncIssue.credentialUnavailable);
    }

    if (adminApiKey == null) {
      _logger.record(ProviderSyncEvent.skippedNoCredential);
      final fallback = _fallback;
      if (fallback != null) {
        return fallback.load();
      }
      throw const DashboardLoadException(issue: DashboardSyncIssue.noProviders);
    }

    try {
      final now = _clock().toUtc();
      final todayStart = DateTime.utc(now.year, now.month, now.day);
      final weekStart = todayStart.subtract(
        Duration(days: todayStart.weekday - 1),
      );
      final monthStart = DateTime.utc(now.year, now.month);
      final reportStart =
          weekStart.isBefore(monthStart) ? weekStart : monthStart;
      final reports = await _client.fetchDailyReports(
        adminApiKey: adminApiKey,
        start: reportStart,
        end: now,
      );
      final reportJson = jsonEncode({
        'accountId': 'openai-local',
        'generatedAt': now.toIso8601String(),
        'todayStart': todayStart.millisecondsSinceEpoch ~/ 1000,
        'weekStart': weekStart.millisecondsSinceEpoch ~/ 1000,
        'monthStart': monthStart.millisecondsSinceEpoch ~/ 1000,
        'usagePages': reports.usage,
        'costPages': reports.costs,
      });
      final snapshot = DashboardSnapshot.fromJsonString(
        _normalizeReport(reportJson),
      );
      _lastSuccessfulSnapshot = snapshot;
      _logger.record(ProviderSyncEvent.succeeded);
      return snapshot;
    } on OpenAiReportingException catch (error) {
      final event = switch (error.failure) {
        OpenAiReportingFailure.authentication =>
          ProviderSyncEvent.authenticationRequired,
        OpenAiReportingFailure.permissionDenied =>
          ProviderSyncEvent.permissionDenied,
        OpenAiReportingFailure.rateLimited => ProviderSyncEvent.rateLimited,
        OpenAiReportingFailure.unavailable => ProviderSyncEvent.unavailable,
        OpenAiReportingFailure.invalidResponse =>
          ProviderSyncEvent.invalidResponse,
      };
      _logger.record(event, details: error.details);
      return _cachedOrThrow(switch (error.failure) {
        OpenAiReportingFailure.authentication =>
          DashboardSyncIssue.authentication,
        OpenAiReportingFailure.permissionDenied =>
          DashboardSyncIssue.permissionDenied,
        OpenAiReportingFailure.rateLimited => DashboardSyncIssue.rateLimited,
        OpenAiReportingFailure.unavailable =>
          DashboardSyncIssue.providerUnavailable,
        OpenAiReportingFailure.invalidResponse =>
          DashboardSyncIssue.invalidResponse,
      }, details: error.details);
    } on WardPulseBindingsException catch (error) {
      _logger.record(ProviderSyncEvent.invalidResponse, details: error.message);
      return _cachedOrThrow(
        DashboardSyncIssue.invalidResponse,
        details: error.message,
      );
    } catch (error) {
      final details = 'Unexpected ${error.runtimeType}';
      _logger.record(ProviderSyncEvent.invalidResponse, details: details);
      return _cachedOrThrow(
        DashboardSyncIssue.invalidResponse,
        details: details,
      );
    }
  }

  @override
  void invalidate() {
    _lastSuccessfulSnapshot = null;
    _fallback?.invalidate();
  }

  Future<DashboardSnapshot> _cachedOrThrow(
    DashboardSyncIssue issue, {
    String? details,
  }) {
    final cached = _lastSuccessfulSnapshot;
    if (cached != null) {
      _logger.record(ProviderSyncEvent.usingCachedSnapshot);
      return Future.value(
        cached.withStaleStatus(syncIssue: issue, syncDetails: details),
      );
    }

    return Future.error(DashboardLoadException(issue: issue, details: details));
  }
}
