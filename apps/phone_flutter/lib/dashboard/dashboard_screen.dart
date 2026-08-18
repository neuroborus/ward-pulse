import 'package:flutter/material.dart';

import '../app/pull_to_refresh_list.dart';
import '../app/surface_order.dart';
import '../charts/usage_history_chart.dart';
import '../settings/consumption_display_preferences.dart';
import 'connected_capabilities.dart';
import 'dashboard_models.dart';
import 'provider_status_color.dart';
import 'provider_status_severity.dart';
import 'status_pill.dart';

/// What the app bar summarizes: the sections a tap can scroll to, never a
/// status computed over something the screen does not show
/// (PHONE_DASHBOARD_DESIGN.md).
typedef DashboardProblems =
    ({int sections, ProviderStatus status, String? first});

DashboardProblems dashboardProblems(
  DashboardSnapshot snapshot,
  ConsumptionDisplayPreferences displayPreferences, [
  FrozenOrder? order,
]) {
  // The same [order] the screen renders with: `first` is what the app bar
  // scrolls to, and reading it off a different order would skip past a card
  // sitting higher up.
  final flagged = _providerDashboardSections(
    snapshot.accounts,
    displayPreferences,
    order,
  ).where((section) => section.flagged > 0).toList(growable: false);
  return (
    sections: flagged.length,
    status: worstProviderStatus(flagged.map((section) => section.status)),
    first: flagged.isEmpty ? null : flagged.first.provider,
  );
}

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({
    super.key,
    required this.snapshot,
    this.displayPreferences = const ConsumptionDisplayPreferences(),
    this.onOpenProviders,
    this.reveal,
    this.order,
    required this.onRefresh,
  });

  final DashboardSnapshot snapshot;
  final ConsumptionDisplayPreferences displayPreferences;
  final VoidCallback? onOpenProviders;

  /// Keeps the cards where the reader last saw them. Owned by the shell, which
  /// shares it with the app-bar problem badge; `null` ranks afresh every build.
  final FrozenOrder? order;

  /// A section to bring into view, and the tap that asked for it. The token is
  /// what makes a second tap on the same provider scroll again after the reader
  /// has wandered off.
  final ({String provider, int token})? reveal;

  /// Pull-to-refresh reload, shared with the app-bar action.
  final Future<void> Function() onRefresh;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final _sectionKeys = <String, GlobalKey>{};

  @override
  void initState() {
    super.initState();
    // Arriving from another tab builds this screen fresh, so the first request
    // lands here rather than in didUpdateWidget.
    _scheduleReveal(widget.reveal);
  }

  @override
  void didUpdateWidget(DashboardScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.reveal != oldWidget.reveal) {
      _scheduleReveal(widget.reveal);
    }
  }

  void _scheduleReveal(({String provider, int token})? reveal) {
    if (reveal == null) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_sectionKeys[reveal.provider]?.currentContext case final target?) {
        Scrollable.ensureVisible(
          target,
          duration: const Duration(milliseconds: 250),
          alignment: 0.1,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = widget.snapshot;
    final displayPreferences = widget.displayPreferences;
    final onOpenProviders = widget.onOpenProviders;
    if (snapshot.accounts.isEmpty) {
      return ConnectProviderPrompt(onOpenProviders: onOpenProviders);
    }

    final caps = ConnectedCapabilities.fromAccounts(snapshot.accounts);
    final allAllowances = snapshot.accounts
        .expand((account) => account.allowances)
        .toList(growable: false);
    final providerSections = _providerDashboardSections(
      snapshot.accounts,
      displayPreferences,
      widget.order,
    );
    final hasVisibleAllowances = providerSections.any(
      (section) => section.allowances.isNotEmpty,
    );
    final hasPurchasedAllowance = allAllowances.any(
      (allowance) => allowance.source == AllowanceSource.purchased,
    );
    final showMissingPurchased = caps.showAllowances && !hasPurchasedAllowance;
    final showPlatformSpend = true;

    return PullToRefreshList(
      onRefresh: widget.onRefresh,
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
            sectionKeys: _sectionKeys,
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
                'Connect a Codex subscription on the Providers tab to see plan limits.',
            onOpenProviders: onOpenProviders,
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
                'Connect OpenAI Platform reporting on the Providers tab to see cost and limits.',
            onOpenProviders: onOpenProviders,
          ),
        ],
      ],
    );
  }
}

class ConnectProviderPrompt extends StatelessWidget {
  const ConnectProviderPrompt({super.key, this.onOpenProviders});

  final VoidCallback? onOpenProviders;

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
              'Add an OpenAI, Anthropic, or Cursor connection on the Providers tab.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            if (onOpenProviders != null) ...[
              const SizedBox(height: 16),
              FilledButton(
                onPressed: onOpenProviders,
                child: const Text('Open Providers'),
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
    this.onOpenProviders,
  });

  final String title;
  final String explanation;
  final VoidCallback? onOpenProviders;

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
              if (onOpenProviders != null)
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Text('Open Providers'),
                ),
            ],
          ),
    );
    if (open == true) {
      onOpenProviders?.call();
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
  const AllowanceSummaryCard({super.key, required this.allowance, this.accent});

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
        allowance.remaining?.label ??
            (allowance.usedPercent != null
                ? '${allowance.usedPercentLabel} used'
                : 'Balance unavailable'),
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
                // A mark is an exception, never the norm: a column of healthy
                // checkmarks outweighs the one warning the screen was opened
                // for (PHONE_DASHBOARD_DESIGN.md).
                if (allowance.status != ProviderStatus.ok)
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

/// Spend of one period across every connection — money only.
///
/// Limits are per connection, so the total has no ceiling to measure against:
/// no bar, no percentage, and no status pill that would read `Unknown` forever.
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

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: textTheme.titleMedium),
            const SizedBox(height: 14),
            spentLabel == null
                ? const Text('No spend reported')
                : Text(spentLabel, style: textTheme.headlineSmall),
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
            // A money-only card has no full-width row left to stretch it.
            crossAxisAlignment: CrossAxisAlignment.stretch,
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
    required this.provider,
    required this.providerLabel,
    required this.status,
    required this.spent,
    required this.flagged,
    required this.allowances,
    required this.buckets,
    required this.modelBreakdown,
  });

  final String provider;
  final String providerLabel;
  final ProviderStatus status;

  /// What this family spent this month, or `null` when its accounts disagree on
  /// a currency. Carried because ordering needs it and a section spans several
  /// accounts, while spend is reported per account.
  final Money? spent;

  /// How many things this section is reporting as unhealthy: one per card that
  /// deviates, or one for an account that deviates without a card of its own —
  /// a platform connection reports spend, not meters, and its trouble would
  /// otherwise have nowhere to show.
  final int flagged;
  final List<AllowanceState> allowances;
  final List<UsageBucket> buckets;
  final List<ModelUsage> modelBreakdown;

  bool get showUsageHistory => buckets.isNotEmpty;

  bool get showModelUsage => modelBreakdown.isNotEmpty;
}

/// One plaque per provider family (plan + platform share a header).
///
/// Claude/Cursor use one `ProviderKind` for both connections; grouping by kind
/// keeps allowances, history, and model breakdown under a single accent bar.
List<_ProviderDashboardSection> _providerDashboardSections(
  List<ProviderSnapshot> accounts,
  ConsumptionDisplayPreferences displayPreferences, [
  FrozenOrder? order,
]) {
  final grouped = <String, List<ProviderSnapshot>>{};
  for (final account in accounts) {
    grouped
        .putIfAbsent(account.provider, () => <ProviderSnapshot>[])
        .add(account);
  }

  final sections = <_ProviderDashboardSection>[];
  for (final group in grouped.values) {
    final allowances = group
        .expand((account) => account.allowances)
        .where((allowance) => displayPreferences.allows(allowance.source))
        .toList(growable: false);
    final buckets = group
        .expand((account) => account.buckets)
        .toList(growable: false);
    final modelBreakdown = group
        .expand((account) => account.modelBreakdown)
        .toList(growable: false);
    if (allowances.isEmpty && buckets.isEmpty && modelBreakdown.isEmpty) {
      continue;
    }
    sections.add(
      _ProviderDashboardSection(
        provider: group.first.provider,
        providerLabel: group.first.providerLabel,
        spent: _monthSpend(group),
        // A rollup covers what this section renders — its cards and the
        // accounts behind them. Cards alone are not enough: an account can read
        // healthy while a card crossed its own threshold, and it can read
        // warning while reporting no card at all
        // (PHONE_DASHBOARD_DESIGN.md).
        status: worstProviderStatus([
          ...group.map((account) => account.status),
          ...allowances.map((allowance) => allowance.status),
        ]),
        flagged: group.fold(0, (total, account) {
          final cards =
              account.allowances
                  .where(
                    (allowance) =>
                        displayPreferences.allows(allowance.source) &&
                        allowance.status != ProviderStatus.ok,
                  )
                  .length;
          if (cards > 0) {
            return total + cards;
          }
          return total + (account.status == ProviderStatus.ok ? 0 : 1);
        }),
        allowances: allowances,
        buckets: buckets,
        modelBreakdown: modelBreakdown,
      ),
    );
  }

  sections.sort(_compareSections);
  if (order == null) {
    return sections;
  }

  // Held so a poll that only moves spend cannot slide a card out from under a
  // finger; the ranking above decides again the moment a family's state moves.
  final held = order.hold([for (final section in sections) _orderKey(section)]);
  final position = {
    for (var index = 0; index < held.length; index++) held[index]: index,
  };
  sections.sort(
    (left, right) =>
        position[_orderKey(left)]!.compareTo(position[_orderKey(right)]!),
  );
  return sections;
}

/// What a held order is held against: the family, and the state it reports.
///
/// Spend is deliberately absent — it is the number this freezing exists to
/// absorb. Status is deliberately present: a family falling into error climbs
/// the poll it happens, rather than waiting for another family to appear.
String _orderKey(_ProviderDashboardSection section) {
  return '${section.provider} ${section.status.name}';
}

/// What needs action first, then what costs most, then a stable name.
int _compareSections(
  _ProviderDashboardSection left,
  _ProviderDashboardSection right,
) {
  final statusCmp = compareByStatus(left.status, right.status);
  if (statusCmp != 0) {
    return statusCmp;
  }
  final spentCmp = compareBySpend(left.spent, right.spent);
  if (spentCmp != 0) {
    return spentCmp;
  }
  // The provider key, not the label: a copy edit must not move a card.
  return left.provider.compareTo(right.provider);
}

/// This month's spend for a whole family, or `null` when its accounts report in
/// different currencies — the core refuses to add those, and so does the order.
Money? _monthSpend(List<ProviderSnapshot> group) {
  Money? total;
  for (final account in group) {
    final spent = account.month.spent;
    if (spent == null) {
      continue;
    }
    if (total == null) {
      total = spent;
      continue;
    }
    if (total.currency != spent.currency) {
      return null;
    }
    total = Money(
      minorUnits: total.minorUnits + spent.minorUnits,
      currency: total.currency,
    );
  }
  return total;
}

class _ProviderDashboardSections extends StatelessWidget {
  const _ProviderDashboardSections({
    required this.sections,
    required this.sectionKeys,
    this.footer,
  });

  final List<_ProviderDashboardSection> sections;

  /// Owned by the screen's state so a key survives rebuilds and stays a valid
  /// scroll target between the tap and the frame that answers it.
  final Map<String, GlobalKey> sectionKeys;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (index, section) in sections.indexed) ...[
          if (index > 0) const SizedBox(height: 20),
          KeyedSubtree(
            key: sectionKeys.putIfAbsent(section.provider, GlobalKey.new),
            child: _ProviderDashboardSectionView(section: section),
          ),
        ],
        if (footer case final footer?) ...[const SizedBox(height: 12), footer],
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
    final chip = providerStatusChipColors(
      Theme.of(context).colorScheme,
      section.status,
    );
    final accent = providerFamilyColor(section.provider);
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
              child: Text(section.providerLabel, style: textTheme.titleMedium),
            ),
            // A rollup differs from a leaf in form: the card carries the glyph
            // that states a fact, the header carries how many facts are below.
            // The accent bar keeps naming the family, never the status.
            if (section.flagged > 0)
              Tooltip(
                message: section.status.label,
                triggerMode: TooltipTriggerMode.tap,
                child: Badge(
                  backgroundColor: chip.fill,
                  textColor: chip.ink,
                  label: Text('${section.flagged}'),
                ),
              ),
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
          UsageHistoryChart(buckets: section.buckets, accent: accent),
        ],
        if (section.showModelUsage) ...[
          const SizedBox(height: 12),
          _SectionHeader(title: 'Model usage'),
          const SizedBox(height: 8),
          _ModelUsagePanel(models: section.modelBreakdown, accent: accent),
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
