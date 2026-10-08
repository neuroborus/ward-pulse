import 'package:flutter/material.dart';

import '../settings/metric_catalog_groups.dart';
import '../settings/watch_ring_preferences.dart';

/// Lays a metric catalog out as an outline: a heading per kind of connection, a
/// sub-heading per connection, and the caller's row under it.
///
/// Both pickers use it so they cannot drift apart — the Watchface tab kept a
/// flat list for a while after the Widget tab grew headings, and that gap is
/// what this widget exists to close. The rows differ (their slot budgets do),
/// so the caller builds them; everything above a row is the same on both.
class CatalogOutline extends StatelessWidget {
  const CatalogOutline({
    super.key,
    required this.catalog,
    required this.rowBuilder,
  });

  final List<WatchRingMetric> catalog;

  /// Builds one row; [title] is the metric's name under its heading.
  final Widget Function(WatchRingMetric metric, String title) rowBuilder;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final group in groupMetricCatalog(catalog)) ...[
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text(
              group.title,
              style: theme.textTheme.titleSmall?.copyWith(
                color: theme.colorScheme.primary,
              ),
            ),
          ),
          for (final connection in group.connections) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Text(
                connection.title,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            for (final metric in connection.metrics)
              rowBuilder(metric, metricRowTitle(metric)),
          ],
        ],
      ],
    );
  }
}
