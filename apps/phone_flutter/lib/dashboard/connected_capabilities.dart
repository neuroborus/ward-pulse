import 'dashboard_models.dart';

/// Phone-side capability aggregate derived from connected provider accounts.
///
/// Mirrors the `CAPABILITIES` constants in the Rust `ward-pulse-providers` crate
/// for implemented providers, so UI layout decisions stay off the FFI boundary.
final class ConnectedCapabilities {
  const ConnectedCapabilities({
    required this.showBudgets,
    required this.showAllowances,
    required this.showUsageHistory,
    required this.showModelUsage,
    required this.isMock,
  });

  factory ConnectedCapabilities.fromAccounts(List<ProviderSnapshot> accounts) {
    var showBudgets = false;
    var showAllowances = false;
    var showUsageHistory = false;
    var showModelUsage = false;
    var isMock = false;

    for (final account in accounts) {
      switch (account.provider) {
        case 'openai':
          showBudgets = true;
          showUsageHistory = true;
          showModelUsage = true;
        case 'codex':
          showAllowances = true;
          showUsageHistory = true;
        case 'mock':
          isMock = true;
          showBudgets = true;
          showUsageHistory = true;
          showModelUsage = true;
          if (account.allowances.isNotEmpty) {
            showAllowances = true;
          }
        default:
          break;
      }
    }

    return ConnectedCapabilities(
      showBudgets: showBudgets,
      showAllowances: showAllowances,
      showUsageHistory: showUsageHistory,
      showModelUsage: showModelUsage,
      isMock: isMock,
    );
  }

  final bool showBudgets;
  final bool showAllowances;
  final bool showUsageHistory;
  final bool showModelUsage;
  final bool isMock;

  bool get showPlanGap => !isMock && !showAllowances;
  bool get showSpendGap => !isMock && !showBudgets;
}
