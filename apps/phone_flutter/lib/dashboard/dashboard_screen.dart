import 'package:flutter/material.dart';

import '../charts/budget_progress_bar.dart';
import '../charts/usage_history_chart.dart';
import '../settings/consumption_display_preferences.dart';
import 'connected_capabilities.dart';
import 'dashboard_models.dart';
import 'provider_status_color.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({
    super.key,
    required this.snapshot,
    this.displayPreferences = const ConsumptionDisplayPreferences(),
    this.onOpenSettings,
  });

  final DashboardSnapshot snapshot;
  final ConsumptionDisplayPreferences displayPreferences;
  final VoidCallback? onOpenSettings;

  @override
  Widget build(BuildContext context) {
    if (snapshot.accounts.isEmpty) {
      return ConnectProviderPrompt(onOpenSettings: onOpenSettings);
    }

    final caps = ConnectedCapabilities.fromAccounts(snapshot.accounts);
    final hasMultipleAccounts = snapshot.accounts.length > 1;
    final allAllowances = snapshot.accounts
        .expand((account) => account.allowances)
        .toList(growable: false);
    final allowances = allAllowances
        .where((allowance) => displayPreferences.allows(allowance.source))
        .toList(growable: false);
    final historyAccount = _firstAccountWith(
      snapshot.accounts,
      (account) => account.buckets.isNotEmpty,
    );
    final modelAccount = _firstAccountWith(
      snapshot.accounts,
      (account) => account.modelBreakdown.isNotEmpty,
    );
    final hasPurchasedAllowance = allAllowances.any(
      (allowance) => allowance.source == AllowanceSource.purchased,
    );
    final showMissingPurchased =
        caps.showAllowances &&
        displayPreferences.purchased &&
        !hasPurchasedAllowance;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        _SyncHeader(snapshot: snapshot),
        const SizedBox(height: 16),
        if (caps.showAllowances) ...[
          if (allowances.isEmpty)
            EmptyAllowanceCard(
              availableSources:
                  allAllowances.map((allowance) => allowance.source).toSet(),
              purchasedSelectedWithoutData: showMissingPurchased,
            )
          else ...[
            _AllowanceCards(allowances: allowances),
            if (showMissingPurchased) ...[
              const SizedBox(height: 12),
              const MissingPurchasedUsageCard(),
            ],
          ],
          const SizedBox(height: 16),
        ] else if (caps.showPlanGap) ...[
          _CapabilityGapRow(
            title: 'Plan usage',
            explanation:
                'Connect a Codex subscription in Settings to see plan limits.',
            onOpenSettings: onOpenSettings,
          ),
          const SizedBox(height: 16),
        ],
        if (caps.showBudgets) ...[
          _BudgetCards(snapshot: snapshot),
          const SizedBox(height: 16),
        ] else if (caps.showSpendGap) ...[
          _CapabilityGapRow(
            title: 'Spend',
            explanation:
                'Connect OpenAI Platform reporting in Settings to see cost and limits.',
            onOpenSettings: onOpenSettings,
          ),
          const SizedBox(height: 16),
        ],
        if (caps.showUsageHistory) ...[
          UsageHistoryChart(
            title:
                hasMultipleAccounts && historyAccount != null
                    ? '${historyAccount.providerLabel} usage history'
                    : 'Usage history',
            buckets: historyAccount?.buckets ?? const <UsageBucket>[],
          ),
          const SizedBox(height: 16),
        ],
        if (caps.showModelUsage) ...[
          _SectionHeader(
            title:
                hasMultipleAccounts && modelAccount != null
                    ? '${modelAccount.providerLabel} model usage'
                    : 'Model usage',
            trailing: snapshot.accountCountLabel,
          ),
          const SizedBox(height: 8),
          _ModelUsagePanel(
            models: modelAccount?.modelBreakdown ?? const <ModelUsage>[],
          ),
          const SizedBox(height: 16),
        ],
        _SectionHeader(title: 'Alerts'),
        const SizedBox(height: 8),
        _AlertsPanel(alerts: snapshot.alerts),
      ],
    );
  }
}

class ConnectProviderPrompt extends StatelessWidget {
  const ConnectProviderPrompt({super.key, this.onOpenSettings});

  final VoidCallback? onOpenSettings;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Connect a provider',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'Add a Codex subscription or OpenAI Platform key in Settings.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            if (onOpenSettings != null) ...[
              const SizedBox(height: 16),
              FilledButton(
                onPressed: onOpenSettings,
                child: const Text('Open Settings'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _CapabilityGapRow extends StatelessWidget {
  const _CapabilityGapRow({
    required this.title,
    required this.explanation,
    this.onOpenSettings,
  });

  final String title;
  final String explanation;
  final VoidCallback? onOpenSettings;

  Future<void> _showHelp(BuildContext context) async {
    final open = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: Text(title),
            content: Text(explanation),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Close'),
              ),
              if (onOpenSettings != null)
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Text('Open Settings'),
                ),
            ],
          ),
    );
    if (open == true) {
      onOpenSettings?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        title: Text(title),
        trailing: IconButton(
          tooltip: 'Why is this hidden?',
          onPressed: () => _showHelp(context),
          icon: const Icon(Icons.help_outline),
        ),
      ),
    );
  }
}

class EmptyAllowanceCard extends StatelessWidget {
  const EmptyAllowanceCard({
    super.key,
    this.availableSources = const {},
    this.purchasedSelectedWithoutData = false,
  });

  final Set<AllowanceSource> availableSources;
  final bool purchasedSelectedWithoutData;

  @override
  Widget build(BuildContext context) {
    final hasPlan = availableSources.contains(AllowanceSource.plan);
    final hasPurchased = availableSources.contains(AllowanceSource.purchased);
    final message = switch ((
      hasPlan,
      hasPurchased,
      purchasedSelectedWithoutData,
    )) {
      (_, _, true) when !hasPlan =>
        'No purchased credits were reported for the connected account.',
      (true, false, _) =>
        'Plan usage is available. Enable Plan usage in Settings to show it.',
      (false, true, _) =>
        'Purchased usage is available. Enable Purchased usage in Settings to show it.',
      (true, true, _) =>
        'Plan and purchased usage are available. Enable them in Settings to show them.',
      _ => 'The provider did not report the selected usage source.',
    };

    return Card(
      child: Padding(padding: const EdgeInsets.all(16), child: Text(message)),
    );
  }
}

class MissingPurchasedUsageCard extends StatelessWidget {
  const MissingPurchasedUsageCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: const Padding(
        padding: EdgeInsets.all(16),
        child: Text(
          'Purchased usage: none reported. This account has no purchased credits right now.',
        ),
      ),
    );
  }
}

class AllowanceSummaryCard extends StatelessWidget {
  const AllowanceSummaryCard({super.key, required this.allowance});

  final AllowanceState allowance;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final progress = allowance.usedFraction;
    final headline = switch (allowance.source) {
      AllowanceSource.plan => '${allowance.usedPercentLabel} used',
      AllowanceSource.purchased when allowance.unlimited => 'Unlimited',
      AllowanceSource.purchased =>
        allowance.remaining?.label ?? 'Balance unavailable',
    };
    final detail = switch (allowance.source) {
      AllowanceSource.plan when allowance.resetsAt != null =>
        'Resets ${formatUtc(allowance.resetsAt!)}',
      AllowanceSource.plan => 'Reset time unavailable',
      AllowanceSource.purchased when allowance.unlimited => 'No balance limit',
      AllowanceSource.purchased => 'Available balance',
    };

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(allowance.label, style: textTheme.titleMedium),
                ),
                StatusPill(status: allowance.status),
              ],
            ),
            const SizedBox(height: 14),
            Text(headline, style: textTheme.headlineSmall),
            if (progress != null) ...[
              const SizedBox(height: 14),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(minHeight: 8, value: progress),
              ),
            ],
            const SizedBox(height: 10),
            Text(detail),
          ],
        ),
      ),
    );
  }
}

class StatusPill extends StatelessWidget {
  const StatusPill({super.key, required this.status, this.tooltip});

  final ProviderStatus status;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Tooltip(
      message: tooltip ?? status.description,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            _statusIcon(status),
            color: providerStatusColor(colors, status),
            size: 18,
          ),
          const SizedBox(width: 6),
          Text(status.label),
        ],
      ),
    );
  }
}

class BudgetSummaryCard extends StatelessWidget {
  const BudgetSummaryCard({
    super.key,
    required this.title,
    required this.state,
  });

  final String title;
  final BudgetState state;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final spentLabel = state.spent?.label;
    final limit = state.limit;
    final remaining = state.remaining;
    final usedPercentLabel =
        state.usedPercent == null ? null : state.usedPercentLabel;
    final progress = state.usedFraction;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(title, style: textTheme.titleMedium)),
                StatusPill(status: state.status),
              ],
            ),
            if (spentLabel != null) ...[
              const SizedBox(height: 14),
              Text(spentLabel, style: textTheme.headlineSmall),
            ],
            if (limit != null) ...[
              const SizedBox(height: 4),
              Text('Limit ${limit.label}'),
            ],
            if (progress != null) ...[
              const SizedBox(height: 14),
              BudgetProgressBar(state: state),
            ],
            if (usedPercentLabel != null || remaining != null) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  if (usedPercentLabel != null)
                    Expanded(child: Text('$usedPercentLabel used')),
                  if (remaining != null)
                    Flexible(
                      child: Text(
                        'Left ${remaining.label}',
                        textAlign: TextAlign.end,
                      ),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SyncHeader extends StatelessWidget {
  const _SyncHeader({required this.snapshot});

  final DashboardSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final updatedAt = formatUtc(snapshot.generatedAt);
    final syncIssue = snapshot.syncIssue;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Usage dashboard', style: textTheme.headlineSmall),
        const SizedBox(height: 4),
        Text(
          snapshot.overallStatus == ProviderStatus.stale
              ? 'Showing previous data · Updated $updatedAt'
              : 'Updated $updatedAt',
        ),
        if (syncIssue != null) ...[
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Tooltip(
                message: snapshot.syncTooltip ?? syncIssue.message,
                child: Icon(Icons.error_outline, color: colors.error, size: 18),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  syncIssue.message,
                  style: TextStyle(color: colors.error),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _BudgetCards extends StatelessWidget {
  const _BudgetCards({required this.snapshot});

  final DashboardSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final cards = [
      BudgetSummaryCard(title: 'Today', state: snapshot.todayTotal),
      BudgetSummaryCard(title: 'Week', state: snapshot.weekTotal),
      BudgetSummaryCard(title: 'Month', state: snapshot.monthTotal),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 760) {
          return Column(
            children: [
              for (final card in cards) ...[
                card,
                if (card != cards.last) const SizedBox(height: 12),
              ],
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final card in cards) ...[
              Expanded(child: card),
              if (card != cards.last) const SizedBox(width: 12),
            ],
          ],
        );
      },
    );
  }
}

class _AllowanceCards extends StatelessWidget {
  const _AllowanceCards({required this.allowances});

  final List<AllowanceState> allowances;

  @override
  Widget build(BuildContext context) {
    final cards = [
      for (final allowance in allowances)
        AllowanceSummaryCard(allowance: allowance),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 760) {
          return Column(
            children: [
              for (final card in cards) ...[
                card,
                if (card != cards.last) const SizedBox(height: 12),
              ],
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final card in cards) ...[
              Expanded(child: card),
              if (card != cards.last) const SizedBox(width: 12),
            ],
          ],
        );
      },
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, this.trailing});

  final String title;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(title, style: Theme.of(context).textTheme.titleMedium),
        ),
        if (trailing != null) Text(trailing!),
      ],
    );
  }
}

class _ModelUsagePanel extends StatelessWidget {
  const _ModelUsagePanel({required this.models});

  final List<ModelUsage> models;

  @override
  Widget build(BuildContext context) {
    if (models.isEmpty) {
      return Card(
        child: const Padding(
          padding: EdgeInsets.all(16),
          child: Text('No model data'),
        ),
      );
    }

    final maxRequests = models.fold<int>(
      0,
      (current, model) =>
          model.requests != null && model.requests! > current
              ? model.requests!
              : current,
    );

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            for (final model in models) ...[
              _ModelUsageRow(model: model, maxRequests: maxRequests),
              if (model != models.last) const Divider(height: 24),
            ],
          ],
        ),
      ),
    );
  }
}

class _ModelUsageRow extends StatelessWidget {
  const _ModelUsageRow({required this.model, required this.maxRequests});

  final ModelUsage model;
  final int maxRequests;

  @override
  Widget build(BuildContext context) {
    final value =
        maxRequests == 0 || model.requests == null
            ? 0.0
            : model.requests! / maxRequests;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                model.model,
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
            if (model.cost != null) Text(model.cost!.label),
          ],
        ),
        const SizedBox(height: 10),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(minHeight: 8, value: value),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 16,
          runSpacing: 4,
          children: [
            Text('${formatCount(model.requests)} requests'),
            Text('${formatCount(model.totalTokens)} tokens'),
          ],
        ),
      ],
    );
  }
}

class _AlertsPanel extends StatelessWidget {
  const _AlertsPanel({required this.alerts});

  final List<AlertSummary> alerts;

  @override
  Widget build(BuildContext context) {
    if (alerts.isEmpty) {
      return const _EmptyAlertsCard();
    }

    return Card(
      child: Column(
        children: [
          for (final alert in alerts)
            ListTile(
              leading: const Icon(Icons.warning_amber),
              title: Text(alert.message),
              subtitle: Text(alert.severity),
            ),
        ],
      ),
    );
  }
}

class _EmptyAlertsCard extends StatelessWidget {
  const _EmptyAlertsCard();

  @override
  Widget build(BuildContext context) {
    return Card(
      child: const Padding(
        padding: EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(Icons.check_circle_outline),
            SizedBox(width: 12),
            Text('No alerts'),
          ],
        ),
      ),
    );
  }
}

ProviderSnapshot? _firstAccountWith(
  List<ProviderSnapshot> accounts,
  bool Function(ProviderSnapshot account) matches,
) {
  for (final account in accounts) {
    if (matches(account)) {
      return account;
    }
  }
  return null;
}

IconData _statusIcon(ProviderStatus status) {
  return switch (status) {
    ProviderStatus.ok => Icons.check_circle,
    ProviderStatus.warning => Icons.warning_amber,
    ProviderStatus.error => Icons.error,
    ProviderStatus.rateLimited => Icons.speed,
    ProviderStatus.authRequired => Icons.key,
    ProviderStatus.stale => Icons.schedule,
    ProviderStatus.unknown => Icons.help_outline,
  };
}
