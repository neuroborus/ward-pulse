import 'package:flutter/material.dart';

import '../charts/usage_history_chart.dart';
import '../dashboard/dashboard_models.dart';
import '../dashboard/dashboard_screen.dart';
import '../settings/consumption_display_preferences.dart';

class ProviderDetailScreen extends StatelessWidget {
  const ProviderDetailScreen({
    super.key,
    required this.account,
    this.displayPreferences = const ConsumptionDisplayPreferences(),
    this.syncTooltip,
  });

  final ProviderSnapshot account;
  final ConsumptionDisplayPreferences displayPreferences;
  final String? syncTooltip;

  @override
  Widget build(BuildContext context) {
    final allowances = account.allowances
        .where((allowance) => displayPreferences.allows(allowance.source))
        .toList(growable: false);

    return Scaffold(
      appBar: AppBar(title: Text(account.providerLabel)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            Card(
              margin: EdgeInsets.zero,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              child: ListTile(
                leading: const Icon(Icons.account_circle_outlined),
                title: Text(account.accountId),
                subtitle: Text(
                  account.lastSuccessfulSyncAt == null
                      ? 'No sync'
                      : 'Synced ${formatUtc(account.lastSuccessfulSyncAt!)}',
                ),
                trailing: StatusPill(
                  status: account.status,
                  tooltip: syncTooltip,
                ),
              ),
            ),
            const SizedBox(height: 16),
            if (account.allowances.isEmpty) ...[
              BudgetSummaryCard(title: 'Today', state: account.today),
              const SizedBox(height: 12),
              BudgetSummaryCard(title: 'Week', state: account.week),
              const SizedBox(height: 12),
              BudgetSummaryCard(title: 'Month', state: account.month),
            ] else if (allowances.isEmpty)
              const EmptyAllowanceCard()
            else
              for (final allowance in allowances) ...[
                AllowanceSummaryCard(allowance: allowance),
                if (allowance != allowances.last) const SizedBox(height: 12),
              ],
            const SizedBox(height: 16),
            UsageHistoryChart(buckets: account.buckets),
            const SizedBox(height: 16),
            Text('Models', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            for (final model in account.modelBreakdown)
              Card(
                margin: const EdgeInsets.only(bottom: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                child: ListTile(
                  leading: const Icon(Icons.memory),
                  title: Text(model.model),
                  subtitle: Text('${formatCount(model.requests)} requests'),
                  trailing: Text(model.cost?.label ?? 'Unknown'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
