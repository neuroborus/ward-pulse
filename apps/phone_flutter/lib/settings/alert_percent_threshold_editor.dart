import 'package:flutter/material.dart';

import 'alert_threshold_preferences.dart';

/// Compact editor for an opt-in threshold in **remaining %** language.
///
/// Persists used% via [AlertPercentThreshold] for Rust evaluation.
class AlertPercentThresholdEditor extends StatelessWidget {
  const AlertPercentThresholdEditor({
    super.key,
    this.title,
    required this.value,
    required this.onChanged,
    this.disabledReason,
  });

  /// Heading above the control; omit when the caller already labels the group.
  final String? title;
  final AlertPercentThreshold value;
  final ValueChanged<AlertPercentThreshold> onChanged;

  /// Non-null greys out the control and says why the rule cannot fire.
  final String? disabledReason;

  @override
  Widget build(BuildContext context) {
    final remaining = alertUsedToRemaining(value.at);
    final enabled = disabledReason == null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (title != null) ...[
          Text(title!, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
        ],
        InputDecorator(
          decoration: InputDecoration(
            labelText: 'Alert when',
            border: const OutlineInputBorder(),
            isDense: true,
            enabled: enabled,
            helperText: disabledReason,
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<int?>(
              isExpanded: true,
              value: remaining,
              items: [
                for (final stop in alertRemainingStops)
                  DropdownMenuItem<int?>(
                    value: stop,
                    child: Text(stop == null ? 'Off' : '$stop% left'),
                  ),
              ],
              onChanged:
                  enabled
                      ? (next) => onChanged(
                        AlertPercentThreshold(at: alertRemainingToUsed(next)),
                      )
                      : null,
            ),
          ),
        ),
      ],
    );
  }
}
