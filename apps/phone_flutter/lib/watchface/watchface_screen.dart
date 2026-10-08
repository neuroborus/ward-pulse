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
  });

  final DashboardSnapshot? snapshot;
  final WatchRingPreferences ringPreferences;
  final Future<void> Function(WatchRingPreferences value)
  onRingPreferencesChanged;

  /// Pull-to-refresh reload, shared with the app-bar action.
  final Future<void> Function() onRefresh;

  @override
  State<WatchfaceScreen> createState() => _WatchfaceScreenState();
}

class _WatchfaceScreenState extends State<WatchfaceScreen> {
  /// Catalog ids, never resolved ones: a pair is one row here, and a checkbox
  /// that looked for its pools would never find itself.
  List<String> get _effectiveRingIds =>
      watchRingSelectionIds(widget.snapshot, widget.ringPreferences);

  Future<void> _toggleRing(WatchRingMetric metric, bool selected) async {
    if (!metric.isAvailable) {
      return;
    }
    final ids = [..._effectiveRingIds];
    if (selected) {
      if (ids.contains(metric.id) ||
          watchRingSlotCost([...ids, metric.id]) > watchRingSlotCount) {
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
    final catalog = watchRingCatalog(snapshot);
    // Ticked rows, not stored ids: without a snapshot the card has no rows at
    // all, and the stored selection would claim slots nothing on screen shows.
    // Counted by band, so both Cursor pools together cost one.
    final usedSlots = watchRingSlotCost([
      for (final metric in catalog)
        if (selectedIds.contains(metric.id)) metric.id,
    ]);

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
              if (catalog.isEmpty) ...[
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
                      atCapacity:
                          watchRingSlotCost([...selectedIds, metric.id]) >
                          watchRingSlotCount,
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
    final canToggle = metric.isAvailable && (selected || !atCapacity);
    final reason = metric.unavailableReason;
    return CheckboxListTile(
      secondary:
          reason == null
              ? const Icon(Icons.data_usage_outlined)
              : Tooltip(message: reason, child: const Icon(Icons.help_outline)),
      title: Text(title),
      subtitle: Text(metric.catalogSubtitle),
      value: selected,
      onChanged: canToggle ? (value) => onChanged(value ?? false) : null,
    );
  }
}
