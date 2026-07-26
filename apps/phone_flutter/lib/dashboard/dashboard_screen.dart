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
    final allAllowances = snapshot.accounts
        .expand((account) => account.allowances)
        .toList(growable: false);
    final providerSections = _providerDashboardSections(
      snapshot.accounts,
      displayPreferences,
    );
    final hasVisibleAllowances = providerSections.any(
      (section) => section.allowances.isNotEmpty,
    );
    final hasPurchasedAllowance = allAllowances.any(
      (allowance) => allowance.source == AllowanceSource.purchased,
    );
    final showMissingPurchased =
        caps.showAllowances &&
        displayPreferences.purchased &&
        !hasPurchasedAllowance;
    final showPlatformSpend = displayPreferences.platform;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        _SyncHeader(snapshot: snapshot),
        const SizedBox(height: 16),
        if (caps.showAllowances && !hasVisibleAllowances) ...[
          EmptyAllowanceCard(
            availableSources:
                allAllowances.map((allowance) => allowance.source).toSet(),
            purchasedSelectedWithoutData: showMissingPurchased,
          ),
          const SizedBox(height: 16),
        ],
        if (providerSections.isNotEmpty) ...[
          _ProviderDashboardSections(
            sections: providerSections,
            footer:
                showMissingPurchased && hasVisibleAllowances
                    ? const MissingPurchasedUsageCard()
                    : null,
          ),
          const SizedBox(height: 16),
        ],
        if (caps.showPlanGap) ...[
          _CapabilityGapRow(
            title: 'Plan usage',
            explanation:
                'Connect a Codex subscription in Settings to see plan limits.',
            onOpenSettings: onOpenSettings,
          ),
          const SizedBox(height: 16),
        ],
        _SectionHeader(title: 'Alerts'),
        const SizedBox(height: 8),
        _AlertsPanel(alerts: snapshot.alerts),
        // Platform spend sits below primary plan/token surfaces — $0 + Unknown
        // is easy to misread as "Codex is empty" when shown near the top.
        if (showPlatformSpend && caps.showBudgets) ...[
          const SizedBox(height: 16),
          _SectionHeader(title: 'Platform spend'),
          const SizedBox(height: 8),
          _BudgetCards(snapshot: snapshot),
        ] else if (showPlatformSpend && caps.showSpendGap) ...[
          const SizedBox(height: 16),
          _CapabilityGapRow(
            title: 'Spend',
            explanation:
                'Connect OpenAI Platform reporting in Settings to see cost and limits.',
            onOpenSettings: onOpenSettings,
          ),
        ],
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
              'Add an OpenAI, Anthropic, or Cursor connection in Settings.',
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
  const AllowanceSummaryCard({
    super.key,
    required this.allowance,
    this.accent,
  });

  final AllowanceState allowance;

  /// Provider family tint for the progress fill; defaults to theme primary.
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colors = Theme.of(context).colorScheme;
    // Plan bars follow Wear/WFF: fill = remaining capacity (full bar = unused).
    final progress = switch (allowance.source) {
      AllowanceSource.plan => allowance.remainingFraction,
      AllowanceSource.purchased => allowance.usedFraction,
    };
    final headline = switch (allowance.source) {
      AllowanceSource.plan => '${allowance.remainingPercentLabel} left',
      AllowanceSource.purchased when allowance.unlimited => 'Unlimited',
      AllowanceSource.purchased =>
        allowance.remaining?.label ?? 'Balance unavailable',
    };
    final detail = switch (allowance.source) {
      AllowanceSource.plan when allowance.resetsAt != null =>
        'Resets ${formatLocal(allowance.resetsAt!)}',
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
                child: LinearProgressIndicator(
                  minHeight: 8,
                  value: progress,
                  color: accent ?? colors.primary,
                  backgroundColor: colors.surfaceContainerHighest,
                ),
              ),
            ],
            const SizedBox(height: 10),
            if (allowance.resetsAt != null)
              Tooltip(
                message: formatUtc(allowance.resetsAt!),
                child: Text(detail),
              )
            else
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
    final message = tooltip ?? status.description;

    return Tooltip(
      message: message,
      // Tap works on phone; hover still works on desktop/emulator with pointer.
      triggerMode: TooltipTriggerMode.tap,
      showDuration: const Duration(seconds: 6),
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
                StatusPill(
                  status: state.status,
                  tooltip: state.statusExplanation,
                ),
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
    final updatedAt = formatLocal(snapshot.generatedAt);
    final syncIssue = snapshot.syncIssue;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Usage dashboard', style: textTheme.headlineSmall),
        const SizedBox(height: 4),
        Tooltip(
          message: formatUtc(snapshot.generatedAt),
          child: Text(
            snapshot.overallStatus == ProviderStatus.stale
                ? 'Showing previous data · Updated $updatedAt'
                : 'Updated $updatedAt',
          ),
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

class _ProviderDashboardSection {
  const _ProviderDashboardSection({
    required this.account,
    required this.allowances,
  });

  final ProviderSnapshot account;
  final List<AllowanceState> allowances;

  bool get showUsageHistory => account.buckets.isNotEmpty;

  bool get showModelUsage => account.modelBreakdown.isNotEmpty;
}

/// Per-account dashboard groups in snapshot order (not cross-provider sums).
///
/// Each provider plaque owns its allowances, usage history, and model breakdown.
List<_ProviderDashboardSection> _providerDashboardSections(
  List<ProviderSnapshot> accounts,
  ConsumptionDisplayPreferences displayPreferences,
) {
  final sections = <_ProviderDashboardSection>[];
  for (final account in accounts) {
    final allowances =
        account.allowances
            .where((allowance) => displayPreferences.allows(allowance.source))
            .toList(growable: false);
    final section = _ProviderDashboardSection(
      account: account,
      allowances: allowances,
    );
    if (allowances.isEmpty &&
        !section.showUsageHistory &&
        !section.showModelUsage) {
      continue;
    }
    sections.add(section);
  }
  return sections;
}

class _ProviderDashboardSections extends StatelessWidget {
  const _ProviderDashboardSections({required this.sections, this.footer});

  final List<_ProviderDashboardSection> sections;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (index, section) in sections.indexed) ...[
          if (index > 0) const SizedBox(height: 20),
          _ProviderDashboardSectionView(section: section),
        ],
        if (footer case final footer?) ...[
          const SizedBox(height: 12),
          footer,
        ],
      ],
    );
  }
}

class _ProviderDashboardSectionView extends StatelessWidget {
  const _ProviderDashboardSectionView({required this.section});

  final _ProviderDashboardSection section;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final accent = providerFamilyColor(section.account.provider);
    final cards = [
      for (final allowance in section.allowances)
        AllowanceSummaryCard(allowance: allowance, accent: accent),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Container(
              width: 3,
              height: 22,
              decoration: BoxDecoration(
                color: accent,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                section.account.providerLabel,
                style: textTheme.titleMedium,
              ),
            ),
            StatusPill(status: section.account.status),
          ],
        ),
        if (cards.isNotEmpty) ...[
          const SizedBox(height: 12),
          LayoutBuilder(
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
          ),
        ],
        if (section.showUsageHistory) ...[
          const SizedBox(height: 12),
          UsageHistoryChart(
            buckets: section.account.buckets,
            accent: accent,
          ),
        ],
        if (section.showModelUsage) ...[
          const SizedBox(height: 12),
          _SectionHeader(title: 'Model usage'),
          const SizedBox(height: 8),
          _ModelUsagePanel(
            models: section.account.modelBreakdown,
            accent: accent,
          ),
        ],
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(title, style: Theme.of(context).textTheme.titleMedium);
  }
}

class _ModelUsagePanel extends StatelessWidget {
  const _ModelUsagePanel({required this.models, this.accent});

  final List<ModelUsage> models;
  final Color? accent;

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
              _ModelUsageRow(
                model: model,
                maxRequests: maxRequests,
                accent: accent,
              ),
              if (model != models.last) const Divider(height: 24),
            ],
          ],
        ),
      ),
    );
  }
}

class _ModelUsageRow extends StatelessWidget {
  const _ModelUsageRow({
    required this.model,
    required this.maxRequests,
    this.accent,
  });

  final ModelUsage model;
  final int maxRequests;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
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
          child: LinearProgressIndicator(
            minHeight: 8,
            value: value,
            color: accent ?? colors.primary,
            backgroundColor: colors.surfaceContainerHighest,
          ),
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
