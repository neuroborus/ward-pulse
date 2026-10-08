import 'package:ward_pulse_bindings/ward_pulse_bindings.dart';

import '../settings/alert_threshold_preferences.dart';
import 'dashboard_models.dart';

/// Applies [settings] to [snapshot] (Rust core in production).
typedef ApplyAlertSettings =
    DashboardSnapshot Function(
      DashboardSnapshot snapshot,
      AlertThresholdPreferences settings,
    );

/// Applies phone alert prefs through the Rust core.
///
/// When no rules are enabled, clears leftover alerts without calling FFI
/// (default-off path for first-run hosts and widget tests).
DashboardSnapshot applyUserAlertSettings(
  DashboardSnapshot snapshot,
  AlertThresholdPreferences settings,
) {
  if (!settings.hasEnabledRules) {
    if (snapshot.alerts.isEmpty) {
      return snapshot;
    }
    return DashboardSnapshot(
      generatedAt: snapshot.generatedAt,
      overallStatus: snapshot.overallStatus,
      accounts: snapshot.accounts,
      todayTotal: snapshot.todayTotal,
      weekTotal: snapshot.weekTotal,
      monthTotal: snapshot.monthTotal,
      alerts: const [],
      watchSummary: snapshot.watchSummary,
      syncIssue: snapshot.syncIssue,
      syncDetails: snapshot.syncDetails,
    );
  }

  final applied = DashboardSnapshot.fromJsonString(
    applyAlertSettingsJson(snapshot.toJsonString(), settings.encode()),
  );
  // Phone-only sync metadata is not part of the Rust snapshot contract.
  if (snapshot.syncIssue == null && snapshot.syncDetails == null) {
    return applied;
  }
  return DashboardSnapshot(
    generatedAt: applied.generatedAt,
    overallStatus: applied.overallStatus,
    accounts: applied.accounts,
    todayTotal: applied.todayTotal,
    weekTotal: applied.weekTotal,
    monthTotal: applied.monthTotal,
    alerts: applied.alerts,
    watchSummary: applied.watchSummary,
    syncIssue: snapshot.syncIssue,
    syncDetails: snapshot.syncDetails,
  );
}
