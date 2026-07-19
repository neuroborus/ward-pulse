import 'package:flutter/material.dart';

import '../dashboard/dashboard_models.dart';

class BudgetProgressBar extends StatelessWidget {
  const BudgetProgressBar({super.key, required this.state});

  final BudgetState state;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final value = state.usedFraction;

    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: LinearProgressIndicator(
        minHeight: 8,
        value: value ?? 0,
        color: _barColor(colors, state.status),
        backgroundColor: colors.surfaceContainerHighest,
      ),
    );
  }
}

Color _barColor(ColorScheme colors, ProviderStatus status) {
  return switch (status) {
    ProviderStatus.ok => colors.primary,
    ProviderStatus.warning => colors.tertiary,
    ProviderStatus.error ||
    ProviderStatus.rateLimited ||
    ProviderStatus.authRequired => colors.error,
    ProviderStatus.stale || ProviderStatus.unknown => colors.outline,
  };
}
