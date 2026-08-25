import 'package:flutter/material.dart';

import '../settings/alert_percent_threshold_editor.dart';
import '../settings/alert_threshold_preferences.dart';
import 'provider_connection.dart';

/// Edits the alert rules of one connection.
///
/// Which rules apply depends on what the connection reports: a subscription
/// plan exposes usage windows, an organization key exposes spend. Pops the
/// edited thresholds, or null when dismissed.
class ConnectionAlertsDialog extends StatefulWidget {
  const ConnectionAlertsDialog({
    super.key,
    required this.connectionTitle,
    required this.kind,
    required this.thresholds,
  });

  final String connectionTitle;
  final ConnectionKind kind;
  final ConnectionAlertThresholds thresholds;

  @override
  State<ConnectionAlertsDialog> createState() => _ConnectionAlertsDialogState();
}

class _ConnectionAlertsDialogState extends State<ConnectionAlertsDialog> {
  late var _draft = widget.thresholds;

  @override
  Widget build(BuildContext context) {
    final isPlan = widget.kind == ConnectionKind.plan;
    return _ConnectionDialog(
      title: 'Alerts · ${widget.connectionTitle}',
      intro:
          isPlan
              ? 'Opt-in · fire when remaining capacity reaches the chosen % '
                  'left. Off until you pick a value.'
              : 'Opt-in · fire when this connection’s remaining budget reaches '
                  'the chosen % left. Other providers do not count.',
      onSave: () => Navigator.of(context).pop(_draft),
      editors: isPlan ? _planEditors() : _budgetEditors(),
    );
  }

  List<Widget> _planEditors() {
    return [
      AlertPercentThresholdEditor(
        title: 'Plan',
        value: _draft.plan,
        onChanged:
            (plan) => setState(() => _draft = _draft.copyWith(plan: plan)),
      ),
      AlertPercentThresholdEditor(
        title: 'Purchased',
        value: _draft.purchased,
        onChanged:
            (purchased) =>
                setState(() => _draft = _draft.copyWith(purchased: purchased)),
      ),
    ];
  }

  List<Widget> _budgetEditors() {
    return [
      for (final period in _BudgetPeriod.values)
        AlertPercentThresholdEditor(
          title: period.label,
          value: period.thresholdOf(_draft),
          // The limit comes first: without it there is no percentage to alert on.
          disabledReason:
              period.limitOf(_draft.budget) == null
                  ? 'Set this period’s limit under Budget limits'
                  : null,
          onChanged:
              (value) =>
                  setState(() => _draft = period.withThreshold(_draft, value)),
        ),
    ];
  }
}

/// Edits the [ConnectionBudget] of one connection.
///
/// Pops the edited budget, or null when dismissed.
class ConnectionBudgetDialog extends StatefulWidget {
  const ConnectionBudgetDialog({
    super.key,
    required this.connectionTitle,
    required this.budget,
  });

  final String connectionTitle;
  final ConnectionBudget budget;

  @override
  State<ConnectionBudgetDialog> createState() => _ConnectionBudgetDialogState();
}

class _ConnectionBudgetDialogState extends State<ConnectionBudgetDialog> {
  late var _draft = widget.budget;
  late final _limits = {
    for (final period in _BudgetPeriod.values)
      period: TextEditingController(text: _amountText(period.limitOf(_draft))),
  };

  @override
  void dispose() {
    for (final controller in _limits.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _ConnectionDialog(
      title: 'Budget · ${widget.connectionTitle}',
      intro:
          'Your own ceiling on this connection’s spend — providers report the '
          'spend, never the limit. Empty means no limit.',
      onSave: () => Navigator.of(context).pop(_draft),
      editors: [
        for (final period in _BudgetPeriod.values)
          TextField(
            controller: _limits[period],
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: period.label,
              border: const OutlineInputBorder(),
              isDense: true,
            ),
            // No setState: the controllers own the text this build reads.
            onChanged:
                (text) => _draft = period.withLimit(_draft, _minorUnits(text)),
          ),
      ],
    );
  }
}

/// Budget periods in the order the dialog shows them.
enum _BudgetPeriod {
  today('Today'),
  week('Week'),
  month('Month');

  const _BudgetPeriod(this.label);

  final String label;

  AlertPercentThreshold thresholdOf(ConnectionAlertThresholds rules) =>
      switch (this) {
        _BudgetPeriod.today => rules.today,
        _BudgetPeriod.week => rules.week,
        _BudgetPeriod.month => rules.month,
      };

  int? limitOf(ConnectionBudget budget) => switch (this) {
    _BudgetPeriod.today => budget.today,
    _BudgetPeriod.week => budget.week,
    _BudgetPeriod.month => budget.month,
  };

  ConnectionAlertThresholds withThreshold(
    ConnectionAlertThresholds rules,
    AlertPercentThreshold value,
  ) => switch (this) {
    _BudgetPeriod.today => rules.copyWith(today: value),
    _BudgetPeriod.week => rules.copyWith(week: value),
    _BudgetPeriod.month => rules.copyWith(month: value),
  };

  ConnectionBudget withLimit(ConnectionBudget budget, int? minorUnits) =>
      switch (this) {
        _BudgetPeriod.today => ConnectionBudget(
          today: minorUnits,
          week: budget.week,
          month: budget.month,
        ),
        _BudgetPeriod.week => ConnectionBudget(
          today: budget.today,
          week: minorUnits,
          month: budget.month,
        ),
        _BudgetPeriod.month => ConnectionBudget(
          today: budget.today,
          week: budget.week,
          month: minorUnits,
        ),
      };
}

/// Minor units are the storage unit; the field takes major units.
String _amountText(int? minorUnits) =>
    minorUnits == null ? '' : (minorUnits / 100).toStringAsFixed(2);

int? _minorUnits(String text) {
  final value = double.tryParse(text.trim().replaceAll(',', '.'));
  if (value == null || value <= 0) {
    return null;
  }
  return (value * 100).round();
}

/// Shell both dialogs use: intro copy, spaced editors, Cancel/Save.
class _ConnectionDialog extends StatelessWidget {
  const _ConnectionDialog({
    required this.title,
    required this.intro,
    required this.editors,
    required this.onSave,
  });

  final String title;
  final String intro;
  final List<Widget> editors;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: Text(title),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              intro,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            for (final editor in editors) ...[
              const SizedBox(height: 16),
              editor,
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: onSave, child: const Text('Save')),
      ],
    );
  }
}
