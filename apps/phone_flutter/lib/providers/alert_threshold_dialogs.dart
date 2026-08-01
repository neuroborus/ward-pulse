import 'package:flutter/material.dart';

import '../settings/alert_percent_threshold_editor.dart';
import '../settings/alert_threshold_preferences.dart';

/// Edits the plan and purchased rules of one connection.
///
/// Pops the edited thresholds, or null when dismissed.
class ConnectionAlertsDialog extends StatefulWidget {
  const ConnectionAlertsDialog({
    super.key,
    required this.connectionTitle,
    required this.thresholds,
  });

  final String connectionTitle;
  final ConnectionAlertThresholds thresholds;

  @override
  State<ConnectionAlertsDialog> createState() => _ConnectionAlertsDialogState();
}

class _ConnectionAlertsDialogState extends State<ConnectionAlertsDialog> {
  late var _draft = widget.thresholds;

  @override
  Widget build(BuildContext context) {
    return _ThresholdsDialog(
      title: 'Alerts · ${widget.connectionTitle}',
      intro:
          'Opt-in · fire when remaining capacity reaches the chosen % left. '
          'Off until you pick a value.',
      onSave: () => Navigator.of(context).pop(_draft),
      editors: [
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
              (purchased) => setState(
                () => _draft = _draft.copyWith(purchased: purchased),
              ),
        ),
      ],
    );
  }
}

/// Edits the global today/week/month budget rules.
///
/// Pops the whole updated preferences, or null when dismissed.
class PlatformBudgetAlertsDialog extends StatefulWidget {
  const PlatformBudgetAlertsDialog({super.key, required this.thresholds});

  final AlertThresholdPreferences thresholds;

  @override
  State<PlatformBudgetAlertsDialog> createState() =>
      _PlatformBudgetAlertsDialogState();
}

class _PlatformBudgetAlertsDialogState
    extends State<PlatformBudgetAlertsDialog> {
  late var _draft = widget.thresholds;

  @override
  Widget build(BuildContext context) {
    return _ThresholdsDialog(
      title: 'Alerts · OpenAI Platform',
      intro:
          'Opt-in budget alerts · fire when remaining budget reaches the '
          'chosen % left.',
      onSave: () => Navigator.of(context).pop(_draft),
      editors: [
        AlertPercentThresholdEditor(
          title: 'Today',
          value: _draft.today,
          onChanged:
              (today) => setState(() => _draft = _draft.copyWith(today: today)),
        ),
        AlertPercentThresholdEditor(
          title: 'Week',
          value: _draft.week,
          onChanged:
              (week) => setState(() => _draft = _draft.copyWith(week: week)),
        ),
        AlertPercentThresholdEditor(
          title: 'Month',
          value: _draft.month,
          onChanged:
              (month) => setState(() => _draft = _draft.copyWith(month: month)),
        ),
      ],
    );
  }
}

/// Shell both threshold dialogs share: intro copy, spaced editors, Cancel/Save.
class _ThresholdsDialog extends StatelessWidget {
  const _ThresholdsDialog({
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
