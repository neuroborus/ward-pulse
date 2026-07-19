import 'package:flutter/material.dart';

import '../dashboard/dashboard_models.dart';
import '../dashboard/provider_status_color.dart';

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
        color: providerStatusColor(colors, state.status),
        backgroundColor: colors.surfaceContainerHighest,
      ),
    );
  }
}
