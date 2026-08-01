import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../dashboard/dashboard_models.dart';
import '../dashboard/dashboard_screen.dart';
import '../sync/poll_cadence.dart';
import 'refresh_interval_preferences.dart';
import 'watch_ring_preferences.dart';

/// Systemic phone settings: poll cadence, diagnostics, and debug toggles.
/// Not connections, credentials, Watchface/Widget layout, or alert thresholds
/// (those live on Providers).
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    required this.snapshot,
    required this.refreshInterval,
    required this.onRefreshIntervalChanged,
    required this.ringPreferences,
    required this.onSyncWatch,
    required this.debugDataAvailable,
    required this.mockDataEnabled,
    required this.onMockDataEnabledChanged,
  });

  final DashboardSnapshot? snapshot;
  final RefreshIntervalPreference refreshInterval;
  final Future<void> Function(RefreshIntervalPreference value)
  onRefreshIntervalChanged;
  final WatchRingPreferences ringPreferences;
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
                    watchRingPayloadSubtitle(snapshot, widget.ringPreferences),
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
