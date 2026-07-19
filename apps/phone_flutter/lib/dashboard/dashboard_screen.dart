import 'package:flutter/material.dart';

import '../charts/budget_progress_bar.dart';
import '../charts/usage_history_chart.dart';
import '../settings/consumption_display_preferences.dart';
import 'dashboard_models.dart';
import 'provider_status_color.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({
    super.key,
    required this.snapshot,
    this.displayPreferences = const ConsumptionDisplayPreferences(),
  });

  final DashboardSnapshot snapshot;
  final ConsumptionDisplayPreferences displayPreferences;

  @override
  Widget build(BuildContext context) {
    final primaryAccount = snapshot.primaryAccount;
    final hasMultipleAccounts = snapshot.accounts.length > 1;
    final allowances = snapshot.accounts
        .expand((account) => account.allowances)
        .where((allowance) => displayPreferences.allows(allowance.source))
        .toList(growable: false);
    final hasAllowanceData = snapshot.accounts.any(
      (account) => account.allowances.isNotEmpty,
    );
    final historyAccount = _firstAccountWith(
      snapshot.accounts,
      (account) => account.buckets.isNotEmpty,
    );
    final modelAccount = _firstAccountWith(
      snapshot.accounts,
      (account) => account.modelBreakdown.isNotEmpty,
    );

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        _SyncHeader(snapshot: snapshot),
        const SizedBox(height: 16),
        if (!hasAllowanceData)
          _BudgetCards(snapshot: snapshot)
        else if (allowances.isEmpty)
          const EmptyAllowanceCard()
        else
          _AllowanceCards(allowances: allowances),
        const SizedBox(height: 16),
        UsageHistoryChart(
          title:
              hasMultipleAccounts && historyAccount != null
                  ? '${historyAccount.providerLabel} usage history'
                  : 'Usage history',
          buckets:
              historyAccount?.buckets ??
              primaryAccount?.buckets ??
              const <UsageBucket>[],
        ),
        const SizedBox(height: 16),
        _SectionHeader(
          title:
              hasMultipleAccounts && modelAccount != null
                  ? '${modelAccount.providerLabel} model usage'
                  : 'Model usage',
          trailing: snapshot.accountCountLabel,
        ),
        const SizedBox(height: 8),
        _ModelUsagePanel(
          models:
              modelAccount?.modelBreakdown ??
              primaryAccount?.modelBreakdown ??
              const <ModelUsage>[],
        ),
        const SizedBox(height: 16),
        _SectionHeader(title: 'Alerts'),
        const SizedBox(height: 8),
        _AlertsPanel(alerts: snapshot.alerts),
      ],
    );
  }
}

class EmptyAllowanceCard extends StatelessWidget {
  const EmptyAllowanceCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: const Padding(
        padding: EdgeInsets.all(16),
        child: Text('The provider did not report the selected usage source.'),
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
      AllowanceSource.purchased => allowance.remaining?.label ?? 'Unknown',
    };
    final detail = switch (allowance.source) {
      AllowanceSource.plan when allowance.resetsAt != null =>
        'Resets ${formatUtc(allowance.resetsAt!)}',
      AllowanceSource.plan => 'Reset time unavailable',
      AllowanceSource.purchased when allowance.unlimited => 'No balance limit',
      AllowanceSource.purchased => 'Available balance',
    };

    return Card(
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
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

    return Card(
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
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
            const SizedBox(height: 14),
            Text(
              state.spent?.label ?? 'Unknown',
              style: textTheme.headlineSmall,
            ),
            const SizedBox(height: 4),
            Text('Limit ${state.limit?.label ?? 'Unknown'}'),
            const SizedBox(height: 14),
            BudgetProgressBar(state: state),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(child: Text('${state.usedPercentLabel} used')),
                Text('Left ${state.remaining?.label ?? 'Unknown'}'),
              ],
            ),
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
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
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
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
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
            Text(model.cost?.label ?? 'Unknown'),
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
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
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
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
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
