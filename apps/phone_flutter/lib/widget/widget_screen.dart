import 'package:flutter/material.dart';

import '../app/catalog_outline.dart';
import '../app/pull_to_refresh_list.dart';
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
    required this.onRefresh,
    this.reportingOutcomes = const [],
  });

  final DashboardSnapshot? snapshot;
  final Iterable<ConnectionReportingOutcome> reportingOutcomes;
  final PhoneWidgetPreferences preferences;
  final Future<void> Function(PhoneWidgetPreferences value)
  onPreferencesChanged;

  /// Pull-to-refresh reload, shared with the app-bar action.
  final Future<void> Function() onRefresh;

  @override
  State<WidgetScreen> createState() => _WidgetScreenState();
}

class _WidgetScreenState extends State<WidgetScreen> {
  List<String> get _effectiveIds {
    final snapshot = widget.snapshot;
    if (!widget.preferences.usesDefaults || snapshot == null) {
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
    if (selected && !phoneWidgetMetricIsAvailable(metric)) {
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
    final reported = phoneWidgetCatalog(
      snapshot,
      reportingOutcomes: widget.reportingOutcomes,
    );
    final reportedIds = reported.map((metric) => metric.id).toSet();
    final catalog = [
      ...reported,
      for (final id in selectedIds)
        if (!reportedIds.contains(id))
          WatchRingMetric(
            id: id,
            label: 'Saved metric: $id',
            usedPercent: null,
            status: ProviderStatus.unknown,
            unavailableReason:
                'This saved metric is not currently reported. Deselect it to remove the choice.',
          ),
    ];
    // Ticked rows, not stored ids — same reason as Watchface.
    final usedSlots =
        catalog.where((metric) => selectedIds.contains(metric.id)).length;

    return PullToRefreshList(
      onRefresh: widget.onRefresh,
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
                  // Same reason as Watchface: the count explains a greyed row
                  // that the cap alone leaves looking broken.
                  '$usedSlots of $phoneWidgetSlotCount slots used · '
                  'independent of Watchface · Claude windows stay separate · '
                  'reported expenses and allowance details · exhausted pools show as 0% left',
                ),
              ),
              if (catalog.isEmpty) ...[
                const Divider(height: 1),
                const ListTile(
                  title: Text('No metrics yet'),
                  subtitle: Text(
                    'Connect a provider under Providers · plan windows and '
                    'reported expenses fill these slots.',
                  ),
                ),
              ],
              CatalogOutline(
                catalog: catalog,
                rowBuilder:
                    (metric, title) => _MetricTile(
                      metric: metric,
                      title: title,
                      selected: selectedIds.contains(metric.id),
                      atCapacity: selectedIds.length >= phoneWidgetSlotCount,
                      onChanged: (value) => _toggleMetric(metric, value),
                    ),
              ),
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
    required this.title,
    required this.selected,
    required this.atCapacity,
    required this.onChanged,
  });

  final WatchRingMetric metric;
  final String title;
  final bool selected;
  final bool atCapacity;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final available = phoneWidgetMetricIsAvailable(metric);
    final canToggle = selected || (available && !atCapacity);
    final reason = available ? null : metric.unavailableReason;
    return CheckboxListTile(
      secondary:
          reason == null
              ? const Icon(Icons.data_usage_outlined)
              : Tooltip(message: reason, child: const Icon(Icons.help_outline)),
      title: Text(title),
      subtitle: Text(phoneWidgetMetricSubtitle(metric)),
      value: selected,
      onChanged: canToggle ? (value) => onChanged(value ?? false) : null,
    );
  }
}
