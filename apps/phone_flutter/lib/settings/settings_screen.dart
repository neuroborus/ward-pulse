import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app/pull_to_refresh_list.dart';
import '../dashboard/dashboard_models.dart';
import '../dashboard/status_pill.dart';
import '../providers/claude_plan_pause.dart';
import '../sync/poll_cadence.dart';
import '../widget/phone_widget_preferences.dart';
import 'refresh_interval_preferences.dart';
import 'watch_ring_preferences.dart';

const _independentProductDisclaimer =
    'WardPulse is an independent usage monitor. It is not affiliated with, '
    'endorsed by, or sponsored by OpenAI, Anthropic, Cursor, Google, or any '
    'other provider. Product names are trademarks of their respective owners.';

const _helpUrl = 'https://neuroborus.github.io/ward-pulse/';
const _privacyPolicyUrl =
    'https://neuroborus.github.io/ward-pulse/product/privacy-policy/';

/// Systemic phone settings: poll cadence, notifications, Demo mode,
/// diagnostics, help, privacy policy, legal, and debug toggles.
/// Not connections, credentials, Watchface/Widget layout, or alert thresholds
/// (those live on Providers).
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    required this.snapshot,
    required this.refreshInterval,
    required this.onRefreshIntervalChanged,
    required this.ringPreferences,
    required this.widgetPreferences,
    this.claudePlanPaused = claudePlanPausedInBuild,
    required this.onSyncWatch,
    required this.onResumeWatch,
    required this.recoveryNotificationsEnabled,
    required this.onRecoveryNotificationsChanged,
    required this.alertNotificationsEnabled,
    required this.onAlertNotificationsChanged,
    required this.androidNotificationsEnabled,
    required this.onOpenNotificationSettings,
    required this.debugDataAvailable,
    this.dataModeReady = true,
    this.demoDataEnabled = false,
    this.onDemoDataEnabledChanged,
    required this.mockDataEnabled,
    required this.onMockDataEnabledChanged,
    this.accountStorageUnresolved = false,
    required this.onRefresh,
  });

  final DashboardSnapshot? snapshot;

  /// Whether a plan window coming back may interrupt the reader.
  final bool recoveryNotificationsEnabled;
  final bool alertNotificationsEnabled;
  final Future<bool> Function(bool enabled) onAlertNotificationsChanged;
  final bool? androidNotificationsEnabled;
  final Future<bool?> Function() onOpenNotificationSettings;

  /// Turning it on is also where Android is asked for the permission: only the
  /// foreground can ask, and the poll that posts runs without an Activity.
  /// Answers whether posting is allowed now, which the switch alone cannot say.
  final Future<bool> Function(bool enabled) onRecoveryNotificationsChanged;
  final RefreshIntervalPreference refreshInterval;
  final Future<void> Function(RefreshIntervalPreference value)
  onRefreshIntervalChanged;
  final WatchRingPreferences? ringPreferences;
  final PhoneWidgetPreferences? widgetPreferences;

  /// The capability policy of the shown data, for the watch preview and sync.
  final bool claudePlanPaused;
  final Future<void> Function() onSyncWatch;

  /// Resumes pending or owed native watch publication without sending a
  /// summary, for an explicit sync that saved ring choices block.
  final Future<void> Function() onResumeWatch;
  final bool debugDataAvailable;

  /// Whether the saved data mode is known, so either switch may change it.
  final bool dataModeReady;

  /// Product Demo mode, offered in every build; Mock data is Debug-only.
  /// Turning either on replaces the other.
  final bool demoDataEnabled;
  final Future<void> Function(bool value)? onDemoDataEnabledChanged;
  final bool mockDataEnabled;
  final bool accountStorageUnresolved;
  final Future<void> Function(bool value) onMockDataEnabledChanged;

  /// Pull-to-refresh reload, shared with the app-bar action.
  final Future<void> Function() onRefresh;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _settingNotification = false;
  bool _settingDataMode = false;
  bool _openingNotificationSettings = false;
  bool _isSyncing = false;
  String? _syncResult;
  int? _dragRefreshMinutes;

  String? _capacityReason(
    DashboardSnapshot snapshot,
    WatchRingPreferences preferences,
  ) {
    final paused = widget.claudePlanPaused;
    return watchRingCapacityReason(
      watchRingSelectionIds(snapshot, preferences, claudePlanPaused: paused),
      claudePlanPaused: paused,
    );
  }

  Future<void> _syncWatch() async {
    final snapshot = widget.snapshot;
    final preferences = widget.ringPreferences;
    if (snapshot == null) {
      return;
    }
    if (preferences != null && _capacityReason(snapshot, preferences) != null) {
      setState(() {
        _syncResult = watchRingPayloadSubtitle(
          snapshot,
          preferences,
          claudePlanPaused: widget.claudePlanPaused,
        );
      });
      // No replacement can be built, but an owed or pending one still resumes.
      await widget.onResumeWatch();
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

  Future<void> _openNotificationSettings() async {
    if (_openingNotificationSettings) return;
    setState(() => _openingNotificationSettings = true);
    var opened = false;
    try {
      opened = await widget.onOpenNotificationSettings() == true;
    } catch (_) {
      // Navigation failures share retryable feedback below.
    } finally {
      if (mounted) setState(() => _openingNotificationSettings = false);
    }
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not open Android notification settings'),
        ),
      );
    }
  }

  Future<void> _setNotification(
    bool value,
    Future<bool> Function(bool) save,
  ) async {
    setState(() => _settingNotification = true);
    try {
      final granted = await save(value);
      if (value && !granted && mounted) {
        // The reader said yes and Android said no; leaving the switch on
        // without a word would promise an interruption that cannot arrive.
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Android is blocking WardPulse notifications'),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not update notification setting'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _settingNotification = false);
    }
  }

  Future<void> _setDataMode(
    Future<void> Function(bool value) change,
    bool value,
    String failure,
  ) async {
    if (_settingDataMode) return;
    setState(() => _settingDataMode = true);
    try {
      await change(value);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(failure)));
      }
    } finally {
      if (mounted) setState(() => _settingDataMode = false);
    }
  }

  Future<void> _setDemoDataEnabled(bool value) async {
    await _setDataMode(
      widget.onDemoDataEnabledChanged!,
      value,
      'Could not update Demo mode',
    );
  }

  Future<void> _setMockDataEnabled(bool value) async {
    await _setDataMode(
      widget.onMockDataEnabledChanged,
      value,
      'Could not update mock data setting',
    );
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

  Future<void> _openInBrowser(String url) async {
    bool opened;
    try {
      opened = await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {
      opened = false;
    }
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open the browser')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = widget.snapshot;
    final ringPreferences = widget.ringPreferences;
    final widgetPreferences = widget.widgetPreferences;
    final colors = Theme.of(context).colorScheme;
    final shownRefreshMinutes = PollCadence.clampMinutes(
      _dragRefreshMinutes ?? widget.refreshInterval.minutes,
    );
    final backgroundRefreshMinutes =
        PollCadence.headlessInterval(
          Duration(minutes: shownRefreshMinutes),
        ).inMinutes;
    final refreshStopIndex = PollCadence.refreshIntervalStopIndex(
      shownRefreshMinutes,
    );

    return PullToRefreshList(
      onRefresh: widget.onRefresh,
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
                    'about every $backgroundRefreshMinutes minutes '
                    'in the background (Android may delay updates) · some providers publish '
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
        const _SettingsSectionHeader(title: 'Notifications'),
        if (widget.androidNotificationsEnabled == false)
          Card(
            color: colors.errorContainer,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.warning_amber_rounded,
                        color: colors.onErrorContainer,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Notifications are blocked',
                              style: Theme.of(context).textTheme.titleSmall
                                  ?.copyWith(color: colors.onErrorContainer),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Allow notifications for WardPulse in Android settings.',
                              style: TextStyle(color: colors.onErrorContainer),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  TextButton(
                    onPressed:
                        _openingNotificationSettings
                            ? null
                            : _openNotificationSettings,
                    style: TextButton.styleFrom(
                      foregroundColor: colors.onErrorContainer,
                    ),
                    child: const Text('Enable notifications'),
                  ),
                ],
              ),
            ),
          ),
        Card(
          child: SwitchListTile(
            secondary: const Icon(Icons.notifications_outlined),
            title: const Text('Alert notifications'),
            subtitle: const Text(
              'Your configured usage and budget thresholds · rules stay on Providers',
            ),
            value: widget.alertNotificationsEnabled,
            onChanged:
                _settingNotification
                    ? null
                    : (value) => _setNotification(
                      value,
                      widget.onAlertNotificationsChanged,
                    ),
          ),
        ),
        Card(
          child: SwitchListTile(
            secondary: const Icon(Icons.notifications_active_outlined),
            title: const Text('Plan recovery'),
            subtitle: const Text(
              'Tells you when a plan window you had run out of is usable again',
            ),
            value: widget.recoveryNotificationsEnabled,
            onChanged:
                _settingNotification
                    ? null
                    : (value) => _setNotification(
                      value,
                      widget.onRecoveryNotificationsChanged,
                    ),
          ),
        ),
        const SizedBox(height: 16),
        if (widget.accountStorageUnresolved) ...[
          const ListTile(
            leading: Icon(Icons.warning_amber_outlined),
            title: Text('Could not save an updated account session'),
            subtitle: Text(
              'Check the connection under Providers before using live data.',
            ),
          ),
          const SizedBox(height: 16),
        ],
        if (widget.onDemoDataEnabledChanged != null) ...[
          const _SettingsSectionHeader(title: 'Demo'),
          Card(
            child: SwitchListTile(
              secondary: const Icon(Icons.preview_outlined),
              title: const Text('Demo mode'),
              subtitle: const Text(
                'Sample readings on Dashboard, widget and watch · no provider '
                'refresh or notifications; your connections stay saved',
              ),
              value: widget.demoDataEnabled,
              onChanged:
                  widget.dataModeReady && !_settingDataMode
                      ? _setDemoDataEnabled
                      : null,
            ),
          ),
          const SizedBox(height: 16),
        ],
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
              onChanged:
                  widget.dataModeReady && !_settingDataMode
                      ? _setMockDataEnabled
                      : null,
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
                    ringPreferences == null
                        ? 'Unavailable'
                        : watchRingPayloadSubtitle(
                          snapshot,
                          ringPreferences,
                          claudePlanPaused: widget.claudePlanPaused,
                        ),
                  ),
                  trailing:
                      ringPreferences == null
                          ? null
                          : StatusPill(
                            status: snapshot.watchSummary.status,
                            tooltip: snapshot.syncTooltip,
                          ),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.widgets_outlined),
                  title: const Text('Widget summary'),
                  subtitle: Text(
                    widgetPreferences == null
                        ? 'Unavailable'
                        : phoneWidgetPayloadSubtitle(
                          snapshot,
                          widgetPreferences,
                        ),
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
          const SizedBox(height: 16),
        ],
        Card(
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.help_outline),
                title: const Text('Help'),
                subtitle: const Text('Open the user guide in your browser'),
                trailing: const Icon(Icons.open_in_new),
                onTap: () => _openInBrowser(_helpUrl),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.privacy_tip_outlined),
                title: const Text('Privacy Policy'),
                subtitle: const Text('Open the privacy policy in your browser'),
                trailing: const Icon(Icons.open_in_new),
                onTap: () => _openInBrowser(_privacyPolicyUrl),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        const _SettingsSectionHeader(title: 'Legal'),
        const Card(
          child: ListTile(
            leading: Icon(Icons.info_outline),
            title: Text('Independent product'),
            subtitle: Text(_independentProductDisclaimer),
          ),
        ),
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
