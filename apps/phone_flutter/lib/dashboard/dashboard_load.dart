import 'package:ward_pulse_bindings/ward_pulse_bindings.dart';

import '../providers/provider_connection.dart';
import '../providers/provider_credential_store.dart';
import '../sync/provider_reporting.dart';
import '../sync/provider_sync_logger.dart';
import 'dashboard_models.dart';
import 'dashboard_repository.dart';

/// Fallback load outcome captured once so every branch can reuse or rethrow it.
final class CapturedDashboardLoad {
  const CapturedDashboardLoad.success(this._value)
    : _error = null,
      _stackTrace = null;

  const CapturedDashboardLoad.failure(this._error, this._stackTrace)
    : _value = null;

  static Future<CapturedDashboardLoad> capture(
    Future<DashboardSnapshot> Function() load,
  ) async {
    try {
      return CapturedDashboardLoad.success(await load());
    } catch (error, stackTrace) {
      return CapturedDashboardLoad.failure(error, stackTrace);
    }
  }

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
}

/// Whether a snapshot carries a real provider account rather than mock data.
bool hasLiveAccount(DashboardSnapshot snapshot) {
  return snapshot.accounts.any((account) => account.provider != 'mock');
}

/// Load failure details safe to log: never raw provider payloads.
String loadFailureDetails(Object error) {
  if (error is WardPulseBindingsException) {
    return error.message;
  }
  final message = error.toString().trim();
  if (message.isEmpty) {
    return 'Unexpected ${error.runtimeType}';
  }
  // Prefer the exception message (e.g. ArgumentError) while staying short.
  final clipped =
      message.length > 240 ? '${message.substring(0, 240)}…' : message;
  return clipped;
}

/// Maps a reporting or normalize failure into a dashboard load issue.
///
/// [DashboardLoadException] values already mapped by the loader pass through.
DashboardLoadException mapReportingError(
  Object error,
  ProviderSyncLogger logger,
) {
  if (error is DashboardLoadException) {
    return error;
  }
  if (error is ProviderReportingException) {
    logger.record(reportingSyncEvent(error.failure), details: error.details);
    return DashboardLoadException(
      issue: reportingIssue(error.failure),
      details: error.details,
    );
  }
  final details = loadFailureDetails(error);
  logger.record(ProviderSyncEvent.invalidResponse, details: details);
  return DashboardLoadException(
    issue: DashboardSyncIssue.invalidResponse,
    details: details,
  );
}

/// Reads a connection secret, or maps secure-storage failures for the UI.
Future<String?> readConnectionSecret({
  required ProviderCredentialStore store,
  required ProviderConnectionId id,
  required ProviderSyncLogger logger,
}) async {
  try {
    return await store.readSecret(id);
  } catch (_) {
    logger.record(ProviderSyncEvent.unavailable);
    throw const DashboardLoadException(
      issue: DashboardSyncIssue.credentialUnavailable,
    );
  }
}
