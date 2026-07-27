import 'package:flutter/material.dart';

import '../dashboard/dashboard_models.dart';
import '../settings/watch_ring_preferences.dart';

/// Wear / WFF ring slots and a compact preview of the next watch payload.
class WatchfaceScreen extends StatefulWidget {
  const WatchfaceScreen({
    super.key,
    required this.snapshot,
    required this.ringPreferences,
    required this.onRingPreferencesChanged,
  });

  final DashboardSnapshot? snapshot;
  final WatchRingPreferences ringPreferences;
  final Future<void> Function(WatchRingPreferences value)
  onRingPreferencesChanged;

  @override
  State<WatchfaceScreen> createState() => _WatchfaceScreenState();
}

class _WatchfaceScreenState extends State<WatchfaceScreen> {
  List<String> get _effectiveRingIds {
    final snapshot = widget.snapshot;
    if (snapshot == null) {
      return widget.ringPreferences.migratedIds;
    }
    return [
      for (final ring in resolveWatchRings(snapshot, widget.ringPreferences))
        ring.id,
    ];
  }

  Future<void> _toggleRing(WatchRingMetric metric, bool selected) async {
    if (!metric.isAvailable) {
      return;
    }
    final ids = [..._effectiveRingIds];
    if (selected) {
      if (ids.contains(metric.id) || ids.length >= watchRingSlotCount) {
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

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
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
                  'Pick up to $watchRingSlotCount metrics · unavailable ones '
                  'stay off the watch',
                ),
              ),
              for (final metric in watchRingCatalog(snapshot)) ...[
                const Divider(height: 1),
                _WatchRingTile(
                  metric: metric,
                  selected: selectedIds.contains(metric.id),
                  atCapacity: selectedIds.length >= watchRingSlotCount,
                  onChanged: (value) => _toggleRing(metric, value),
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
