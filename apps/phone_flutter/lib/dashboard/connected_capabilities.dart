import 'dashboard_models.dart';

/// Phone-side capability aggregate derived from connected provider accounts.
///
/// OpenAI and Codex stay kind-based (separate `ProviderKind` values). Claude and
/// Cursor share one kind across plan/platform, so those rows inspect snapshot
/// fields instead of enabling the union of both connection types.
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
        case 'claude':
        case 'cursor':
          if (_hasSpend(account)) {
            showBudgets = true;
          }
          if (account.allowances.isNotEmpty || account.credits.isNotEmpty) {
            showAllowances = true;
          }
          if (account.buckets.isNotEmpty) {
            showUsageHistory = true;
          }
          if (account.modelBreakdown.isNotEmpty) {
            showModelUsage = true;
          }
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

bool _hasSpend(ProviderSnapshot account) {
  return account.today.spent != null ||
      account.week.spent != null ||
      account.month.spent != null;
}
