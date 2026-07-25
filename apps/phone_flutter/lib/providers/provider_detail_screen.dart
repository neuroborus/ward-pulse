import 'package:flutter/material.dart';

import '../charts/usage_history_chart.dart';
import '../dashboard/dashboard_models.dart';
import '../dashboard/dashboard_screen.dart';
import '../dashboard/provider_status_color.dart';
import '../settings/consumption_display_preferences.dart';

class ProviderDetailScreen extends StatelessWidget {
  const ProviderDetailScreen({
    super.key,
    required this.account,
    this.displayPreferences = const ConsumptionDisplayPreferences(),
    this.syncTooltip,
    this.platformLabel,
  });

  final ProviderSnapshot account;
  final ConsumptionDisplayPreferences displayPreferences;
  final String? syncTooltip;
  final String? platformLabel;

  @override
  Widget build(BuildContext context) {
    final allowances = account.allowances
        .where((allowance) => displayPreferences.allows(allowance.source))
        .toList(growable: false);
    final title = account.displayTitle(platformLabel: platformLabel);
    final accent = providerFamilyColor(account.provider);

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            Card(
              child: ListTile(
                leading: const Icon(Icons.account_circle_outlined),
                title: Text(title),
                subtitle: switch (account.lastSuccessfulSyncAt) {
                  null => Text(account.accountId),
                  final syncedAt => Tooltip(
                    message: formatUtc(syncedAt),
                    child: Text(
                      '${account.accountId} · Synced ${formatLocal(syncedAt)}',
                    ),
                  ),
                },
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
                AllowanceSummaryCard(allowance: allowance, accent: accent),
                if (allowance != allowances.last) const SizedBox(height: 12),
              ],
            const SizedBox(height: 16),
            UsageHistoryChart(buckets: account.buckets, accent: accent),
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
                  trailing: model.cost == null ? null : Text(model.cost!.label),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
