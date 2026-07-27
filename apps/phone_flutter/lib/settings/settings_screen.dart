import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../dashboard/dashboard_models.dart';
import '../dashboard/dashboard_screen.dart';
import '../sync/poll_cadence.dart';
import 'alert_percent_threshold_editor.dart';
import 'alert_threshold_preferences.dart';
import 'consumption_display_preferences.dart';
import 'refresh_interval_preferences.dart';
import 'watch_ring_preferences.dart';

/// Systemic phone settings: dashboard surfaces, poll cadence, diagnostics, and debug
/// toggles. Watch ring slots stay here until the Watchface tab (Phase 14). Not
/// connections or credentials.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    required this.snapshot,
    required this.displayPreferences,
    required this.onDisplayPreferencesChanged,
    required this.refreshInterval,
    required this.onRefreshIntervalChanged,
    required this.ringPreferences,
    required this.onRingPreferencesChanged,
    required this.alertThresholds,
    required this.onAlertThresholdsChanged,
    required this.onSyncWatch,
    required this.debugDataAvailable,
    required this.mockDataEnabled,
    required this.onMockDataEnabledChanged,
  });

  final DashboardSnapshot? snapshot;
  final ConsumptionDisplayPreferences displayPreferences;
  final Future<void> Function(ConsumptionDisplayPreferences value)
  onDisplayPreferencesChanged;
  final RefreshIntervalPreference refreshInterval;
  final Future<void> Function(RefreshIntervalPreference value)
  onRefreshIntervalChanged;
  final WatchRingPreferences ringPreferences;
  final Future<void> Function(WatchRingPreferences value)
  onRingPreferencesChanged;
  final AlertThresholdPreferences alertThresholds;
  final Future<void> Function(
    AlertThresholdPreferences Function(AlertThresholdPreferences current)
    update,
  )
  onAlertThresholdsChanged;
  final Future<void> Function() onSyncWatch;
  final bool debugDataAvailable;
  final bool mockDataEnabled;
  final Future<void> Function(bool value) onMockDataEnabledChanged;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _isSyncing = false;
  String? _syncResult;
  int? _dragRefreshMinutes;

  Future<void> _syncWatch() async {
    if (widget.snapshot == null) {
      return;
    }

    setState(() {
      _isSyncing = true;
      _syncResult = null;
    });

    try {
      await widget.onSyncWatch();
      if (mounted) {
        setState(() {
          _syncResult = 'Watch summary queued';
        });
      }
    } on PlatformException catch (error) {
      if (mounted) {
        setState(() {
          _syncResult =
              error.message?.trim().isNotEmpty == true
                  ? error.message!
                  : 'Watch sync unavailable';
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _syncResult = 'Watch sync unavailable';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSyncing = false;
        });
      }
    }
  }

  Future<void> _setDisplayPreferences(
    ConsumptionDisplayPreferences value,
  ) async {
    if (!value.hasVisibleSurface) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Keep at least one dashboard surface visible'),
        ),
      );
      return;
    }

    try {
      await widget.onDisplayPreferencesChanged(value);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not update display settings')),
        );
      }
    }
  }

  Future<void> _setMockDataEnabled(bool value) async {
    try {
      await widget.onMockDataEnabledChanged(value);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not update mock data setting')),
        );
      }
    }
  }

  Future<void> _setRefreshInterval(int minutes) async {
    final preference = RefreshIntervalPreference(
      minutes: PollCadence.clampMinutes(minutes),
    );
    try {
      await widget.onRefreshIntervalChanged(preference);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not update refresh interval')),
        );
      }
    }
  }

  Future<void> _setAlertThresholds(
    AlertThresholdPreferences Function(AlertThresholdPreferences current)
    update,
  ) async {
    try {
      await widget.onAlertThresholdsChanged(update);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not update alert thresholds')),
        );
      }
    }
  }

  Future<void> _toggleRing(WatchRingMetric metric, bool selected) async {
    if (!metric.isAvailable) {
      return;
    }
    final snapshot = widget.snapshot;
    final ids = [
      if (snapshot != null)
        for (final ring in resolveWatchRings(snapshot, widget.ringPreferences))
          ring.id
      else
        ...widget.ringPreferences.migratedIds,
    ];
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
          const SnackBar(content: Text('Could not update watch display')),
        );
      }
    }
  }

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

  @override
  Widget build(BuildContext context) {
    final snapshot = widget.snapshot;
    final shownRefreshMinutes = PollCadence.clampMinutes(
      _dragRefreshMinutes ?? widget.refreshInterval.minutes,
    );
    final refreshStopIndex = PollCadence.refreshIntervalStopIndex(
      shownRefreshMinutes,
    );

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        const _SettingsSectionHeader(title: 'Display'),
        Card(
          child: Column(
            children: [
              SwitchListTile(
                secondary: const Icon(Icons.speed_outlined),
                title: const Text('Plan usage'),
                subtitle: const Text('Subscription rate limits'),
                value: widget.displayPreferences.plan,
                onChanged:
                    (value) => _setDisplayPreferences(
                      widget.displayPreferences.copyWith(plan: value),
                    ),
              ),
              const Divider(height: 1),
              SwitchListTile(
                secondary: const Icon(Icons.toll_outlined),
                title: const Text('Purchased usage'),
                subtitle: const Text(
                  'Purchased tokens or credits, when the provider reports them',
                ),
                value: widget.displayPreferences.purchased,
                onChanged:
                    (value) => _setDisplayPreferences(
                      widget.displayPreferences.copyWith(purchased: value),
                    ),
              ),
              const Divider(height: 1),
              SwitchListTile(
                secondary: const Icon(Icons.payments_outlined),
                title: const Text('Platform spend'),
                subtitle: const Text(
                  'Monetary budgets for today, week, and month when reported',
                ),
                value: widget.displayPreferences.platform,
                onChanged:
                    (value) => _setDisplayPreferences(
                      widget.displayPreferences.copyWith(platform: value),
                    ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        const _SettingsSectionHeader(title: 'Refresh'),
        Card(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.schedule_outlined),
                  title: const Text('Refresh interval'),
                  subtitle: Text(
                    'Every $shownRefreshMinutes minutes while WardPulse is open · '
                    'at least every ${PollCadence.headlessMinRefreshMinutes} minutes '
                    'in the background (Android limit) · some providers publish '
                    'new data less often',
                  ),
                ),
                Slider(
                  min: 0,
                  max: (PollCadence.refreshIntervalStops.length - 1).toDouble(),
                  divisions: PollCadence.refreshIntervalStops.length - 1,
                  label: '$shownRefreshMinutes min',
                  semanticFormatterCallback: (value) {
                    final minutes =
                        PollCadence.refreshIntervalStops[value.round()];
                    return '$minutes minutes';
                  },
                  value: refreshStopIndex.toDouble(),
                  onChanged: (value) {
                    setState(() {
                      _dragRefreshMinutes =
                          PollCadence.refreshIntervalStops[value.round()];
                    });
                  },
                  onChangeEnd: (value) async {
                    final minutes =
                        PollCadence.refreshIntervalStops[value.round()];
                    await _setRefreshInterval(minutes);
                    // Keep a newer drag in place if one started while saving.
                    if (mounted && _dragRefreshMinutes == minutes) {
                      setState(() {
                        _dragRefreshMinutes = null;
                      });
                    }
                  },
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        const _SettingsSectionHeader(title: 'Alerts'),
        Card(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Global budgets · off until you set a percent',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 12),
                AlertPercentThresholdEditor(
                  title: 'Today',
                  value: widget.alertThresholds.today,
                  onChanged:
                      (today) => _setAlertThresholds(
                        (current) => current.copyWith(today: today),
                      ),
                ),
                const SizedBox(height: 16),
                AlertPercentThresholdEditor(
                  title: 'Week',
                  value: widget.alertThresholds.week,
                  onChanged:
                      (week) => _setAlertThresholds(
                        (current) => current.copyWith(week: week),
                      ),
                ),
                const SizedBox(height: 16),
                AlertPercentThresholdEditor(
                  title: 'Month',
                  value: widget.alertThresholds.month,
                  onChanged:
                      (month) => _setAlertThresholds(
                        (current) => current.copyWith(month: month),
                      ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        const _SettingsSectionHeader(title: 'Watch'),
        Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const ListTile(
                leading: Icon(Icons.watch_outlined),
                title: Text('Watch display'),
                subtitle: Text(
                  'Temporary until the Watchface tab · pick up to '
                  '$watchRingSlotCount metrics · unavailable ones stay off the watch',
                ),
              ),
              for (final metric in watchRingCatalog(widget.snapshot)) ...[
                const Divider(height: 1),
                _WatchRingTile(
                  metric: metric,
                  selected: _effectiveRingIds.contains(metric.id),
                  atCapacity: _effectiveRingIds.length >= watchRingSlotCount,
                  onChanged: (value) => _toggleRing(metric, value),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),
        if (widget.debugDataAvailable) ...[
          const _SettingsSectionHeader(title: 'Debug'),
          Card(
            child: SwitchListTile(
              secondary: const Icon(Icons.science_outlined),
              title: const Text('Mock data'),
              subtitle: const Text(
                'Debug only · full multi-provider demo; refresh draws a new scenario',
              ),
              value: widget.mockDataEnabled,
              onChanged: _setMockDataEnabled,
            ),
          ),
          const SizedBox(height: 16),
        ],
        if (snapshot != null) ...[
          const _SettingsSectionHeader(title: 'Diagnostics'),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.sync_outlined),
                  title: const Text('Sync'),
                  subtitle: Tooltip(
                    message: formatUtc(snapshot.generatedAt),
                    child: Text(formatLocal(snapshot.generatedAt)),
                  ),
                  trailing: StatusPill(
                    status: snapshot.overallStatus,
                    tooltip: snapshot.syncTooltip,
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.watch_outlined),
                  title: const Text('Watch summary'),
                  subtitle: Text(
                    _watchSummarySubtitle(snapshot, widget.ringPreferences),
                  ),
                  trailing: StatusPill(
                    status: snapshot.watchSummary.status,
                    tooltip: snapshot.syncTooltip,
                  ),
                ),
                if (kDebugMode) ...[
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.send_to_mobile_outlined),
                    title: const Text('Send to watch'),
                    subtitle: Text(_syncResult ?? 'Development only'),
                    trailing:
                        _isSyncing
                            ? const SizedBox.square(
                              dimension: 24,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                            : FilledButton.tonal(
                              onPressed: _syncWatch,
                              child: const Text('Sync'),
                            ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _SettingsSectionHeader extends StatelessWidget {
  const _SettingsSectionHeader({required this.title});

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
      title: Text(metric.settingsTitle),
      subtitle: Text(metric.settingsSubtitle),
      value: selected,
      onChanged: canToggle ? (value) => onChanged(value ?? false) : null,
    );
  }
}

String _watchSummarySubtitle(
  DashboardSnapshot snapshot,
  WatchRingPreferences ringPreferences,
) {
  final rings = orderWatchRingsForSurface(
    resolveWatchRings(snapshot, ringPreferences),
    snapshot: snapshot,
  );
  if (rings.isEmpty) {
    return 'No rings selected';
  }
  if (rings.length == 1) {
    final ring = rings.single;
    return '${ring.label} ${ring.remainingPercent!.round()}% left';
  }
  return '${rings.length} rings · ${rings.map((ring) => ring.label).join(', ')}';
}
