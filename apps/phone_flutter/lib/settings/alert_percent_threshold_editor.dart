import 'package:flutter/material.dart';

import 'alert_threshold_preferences.dart';

/// Compact editor for an opt-in warn/critical percent pair.
class AlertPercentThresholdEditor extends StatelessWidget {
  const AlertPercentThresholdEditor({
    super.key,
    required this.title,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final AlertPercentThreshold value;
  final ValueChanged<AlertPercentThreshold> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        _PercentStopDropdown(
          label: 'Warn at',
          value: value.warnAt,
          onChanged:
              (warnAt) => onChanged(
                AlertPercentThreshold(
                  warnAt: warnAt,
                  criticalAt: value.criticalAt,
                ).normalized,
              ),
        ),
        const SizedBox(height: 8),
        _PercentStopDropdown(
          label: 'Critical at',
          value: value.criticalAt,
          onChanged:
              (criticalAt) => onChanged(
                AlertPercentThreshold(
                  warnAt: value.warnAt,
                  criticalAt: criticalAt,
                ).normalized,
              ),
        ),
      ],
    );
  }
}

class _PercentStopDropdown extends StatelessWidget {
  const _PercentStopDropdown({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final int? value;
  final ValueChanged<int?> onChanged;

  @override
  Widget build(BuildContext context) {
    return InputDecorator(
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        isDense: true,
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<int?>(
          isExpanded: true,
          value: alertThresholdStops.contains(value) ? value : null,
          items: [
            for (final stop in alertThresholdStops)
              DropdownMenuItem<int?>(
                value: stop,
                child: Text(stop == null ? 'Off' : '$stop%'),
              ),
          ],
          onChanged: onChanged,
        ),
      ),
    );
  }
}
