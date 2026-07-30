import 'package:flutter/material.dart';

import '../dashboard/dashboard_models.dart';
import '../settings/watch_ring_preferences.dart';
import 'phone_widget_preferences.dart';

/// Phone home-widget metric slots and a compact preview of the next widget payload.
class WidgetScreen extends StatefulWidget {
  const WidgetScreen({
    super.key,
    required this.snapshot,
    required this.preferences,
    required this.onPreferencesChanged,
  });

  final DashboardSnapshot? snapshot;
  final PhoneWidgetPreferences preferences;
  final Future<void> Function(PhoneWidgetPreferences value)
  onPreferencesChanged;

  @override
  State<WidgetScreen> createState() => _WidgetScreenState();
}

class _WidgetScreenState extends State<WidgetScreen> {
  List<String> get _effectiveIds {
    final snapshot = widget.snapshot;
    if (snapshot == null) {
      return widget.preferences.migratedIds;
    }
    return [
      for (final metric in resolvePhoneWidgetMetrics(
        snapshot,
        widget.preferences,
      ))
        metric.id,
    ];
  }

  Future<void> _toggleMetric(WatchRingMetric metric, bool selected) async {
    if (!metric.isAvailable) {
      return;
    }
    final ids = [..._effectiveIds];
    if (selected) {
      if (ids.contains(metric.id) || ids.length >= phoneWidgetSlotCount) {
        return;
      }
      ids.add(metric.id);
    } else {
      ids.remove(metric.id);
    }
    try {
      await widget.onPreferencesChanged(
        PhoneWidgetPreferences(selectedIds: ids),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not update widget metrics')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = widget.snapshot;
    final selectedIds = _effectiveIds;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        const _SectionHeader(title: 'Widget metrics'),
        Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ListTile(
                leading: const Icon(Icons.widgets_outlined),
                title: const Text('Home screen widget'),
                subtitle: Text(
                  'Pick up to $phoneWidgetSlotCount metrics · independent of '
                  'Watchface · Claude windows stay separate · credits append '
                  'like Glance · exhausted pools show as 0% left',
                ),
              ),
              for (final metric in phoneWidgetCatalog(snapshot)) ...[
                const Divider(height: 1),
                _MetricTile(
                  metric: metric,
                  selected: selectedIds.contains(metric.id),
                  atCapacity: selectedIds.length >= phoneWidgetSlotCount,
                  onChanged: (value) => _toggleMetric(metric, value),
                ),
              ],
            ],
          ),
        ),
        if (snapshot != null) ...[
          const SizedBox(height: 16),
          const _SectionHeader(title: 'Preview'),
          Card(
            child: ListTile(
              leading: const Icon(Icons.preview_outlined),
              title: const Text('Next widget payload'),
              subtitle: Text(
                phoneWidgetPayloadSubtitle(snapshot, widget.preferences),
              ),
            ),
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
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(title, style: Theme.of(context).textTheme.titleMedium),
    );
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({
    required this.metric,
    required this.selected,
    required this.atCapacity,
    required this.onChanged,
  });

  final WatchRingMetric metric;
  final bool selected;
  final bool atCapacity;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final canToggle = metric.isAvailable && (selected || !atCapacity);
    final reason = metric.unavailableReason;
    return CheckboxListTile(
      secondary:
          reason == null
              ? const Icon(Icons.data_usage_outlined)
              : Tooltip(message: reason, child: const Icon(Icons.help_outline)),
      title: Text(metric.catalogTitle),
      subtitle: Text(metric.catalogSubtitle),
      value: selected,
      onChanged: canToggle ? (value) => onChanged(value ?? false) : null,
    );
  }
}
