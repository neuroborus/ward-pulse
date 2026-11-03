import 'package:flutter/material.dart';

import '../app/catalog_outline.dart';
import '../app/pull_to_refresh_list.dart';
import '../dashboard/dashboard_models.dart';
import '../settings/watch_ring_preferences.dart';

/// Wear / WFF ring slots and a compact preview of the next watch payload.
class WatchfaceScreen extends StatefulWidget {
  const WatchfaceScreen({
    super.key,
    required this.snapshot,
    required this.ringPreferences,
    required this.onRingPreferencesChanged,
    required this.onRefresh,
    this.reportingOutcomes = const [],
  });

  final DashboardSnapshot? snapshot;
  final Iterable<ConnectionReportingOutcome> reportingOutcomes;
  final WatchRingPreferences ringPreferences;
  final Future<void> Function(WatchRingPreferences value)
  onRingPreferencesChanged;

  /// Pull-to-refresh reload, shared with the app-bar action.
  final Future<void> Function() onRefresh;

  @override
  State<WatchfaceScreen> createState() => _WatchfaceScreenState();
}

class _WatchfaceScreenState extends State<WatchfaceScreen> {
  /// Saved/catalogue choices, including missing data that must remain removable.
  List<String> get _effectiveRingIds =>
      watchRingSelectionIds(widget.snapshot, widget.ringPreferences);

  Future<void> _toggleRing(WatchRingMetric metric, bool selected) async {
    final ids = [..._effectiveRingIds];
    if (selected) {
      if (!metric.isAvailable ||
          ids.contains(metric.id) ||
          watchRingCapacityReason([...ids, metric.id]) != null) {
        return;
      }
      ids.add(metric.id);
    } else {
      ids.remove(metric.id);
    }
    try {
      await widget.onRingPreferencesChanged(
        WatchRingPreferences(selectedIds: ids),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not update ring slots')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = widget.snapshot;
    final selectedIds = _effectiveRingIds;
    final reported = watchRingCatalog(
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
    final capacityReason = watchRingCapacityReason(selectedIds);
    final usedSlots = watchRingSlotCost(selectedIds);

    return PullToRefreshList(
      onRefresh: widget.onRefresh,
      children: [
        const _SectionHeader(title: 'Ring slots'),
        Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ListTile(
                leading: const Icon(Icons.watch_outlined),
                title: const Text('Wear & watch face'),
                subtitle: Text(
                  // The count, not the cap: a full stack greys every unpicked
                  // row, and without it that reads as a fault rather than a
                  // slot to free.
                  '$usedSlots of $watchRingSlotCount slots used · '
                  'unavailable ones stay off the watch',
                ),
              ),
              if (capacityReason != null) ...[
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.tune),
                  title: const Text('Correct ring choices'),
                  subtitle: Text(
                    '$capacityReason\nWatch updates are paused until your choices fit. '
                    'The last watch summary is kept; phone and widget updates continue.',
                  ),
                ),
              ],
              if (reported.isEmpty) ...[
                const Divider(height: 1),
                const ListTile(
                  title: Text('No metrics yet'),
                  subtitle: Text(
                    'Connect a provider under Providers · plan windows and '
                    'budget limits fill these slots.',
                  ),
                ),
              ],
              CatalogOutline(
                catalog: catalog,
                rowBuilder:
                    (metric, title) => _WatchRingTile(
                      metric: metric,
                      title: title,
                      selected: selectedIds.contains(metric.id),
                      capacityReason: watchRingCapacityReason([
                        ...selectedIds,
                        metric.id,
                      ]),
                      onChanged: (value) => _toggleRing(metric, value),
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
              title: const Text('Next watch payload'),
              subtitle: Text(
                watchRingPayloadSubtitle(snapshot, widget.ringPreferences),
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

class _WatchRingTile extends StatelessWidget {
  const _WatchRingTile({
    required this.metric,
    required this.title,
    required this.selected,
    required this.capacityReason,
    required this.onChanged,
  });

  final WatchRingMetric metric;
  final String title;
  final bool selected;
  final String? capacityReason;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final canToggle =
        selected || (metric.isAvailable && capacityReason == null);
    final reason =
        metric.unavailableReason ?? (selected ? null : capacityReason);
    return CheckboxListTile(
      secondary:
          reason == null
              ? const Icon(Icons.data_usage_outlined)
              : Tooltip(message: reason, child: const Icon(Icons.help_outline)),
      title: Text(title),
      subtitle: Text(
        metric.isAvailable && !selected && capacityReason != null
            ? '${metric.catalogSubtitle}\n$capacityReason'
            : metric.catalogSubtitle,
      ),
      value: selected,
      onChanged: canToggle ? (value) => onChanged(value ?? false) : null,
    );
  }
}
