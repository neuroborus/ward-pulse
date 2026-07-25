import 'dart:async';

import 'package:flutter/material.dart';

import '../dashboard/dashboard_models.dart';
import '../dashboard/dashboard_repository.dart';
import '../dashboard/dashboard_screen.dart';
import '../providers/codex_account_service.dart';
import '../providers/provider_connection.dart';
import '../providers/provider_credential_store.dart';
import '../providers/providers_screen.dart';
import '../settings/settings_screen.dart';
import '../settings/consumption_display_preferences.dart';
import '../settings/debug_data_preferences.dart';
import '../settings/refresh_interval_preferences.dart';
import '../sync/provider_sync_scheduler.dart';
import '../sync/watch_sync_service.dart';
import 'ward_pulse_theme.dart';

class WardPulseApp extends StatelessWidget {
  const WardPulseApp({
    super.key,
    required this.repository,
    this.watchSyncService = const MethodChannelWatchSyncService(),
    this.credentialStore = const EmptyProviderCredentialStore(),
    this.codexAccountService = const EmptyCodexAccountService(),
    this.displayPreferenceStore =
        const DefaultConsumptionDisplayPreferenceStore(),
    this.refreshIntervalStore = const DefaultRefreshIntervalPreferenceStore(),
    this.syncScheduler = const DisabledProviderSyncScheduler(),
    this.debugDataAvailable = false,
    this.debugDataPreferenceStore = const DisabledDebugDataPreferenceStore(),
  });

  final DashboardRepository repository;
  final WatchSyncService watchSyncService;
  final ProviderCredentialStore credentialStore;
  final CodexAccountService codexAccountService;
  final ConsumptionDisplayPreferenceStore displayPreferenceStore;
  final RefreshIntervalPreferenceStore refreshIntervalStore;
  final ProviderSyncScheduler syncScheduler;
  final bool debugDataAvailable;
  final DebugDataPreferenceStore debugDataPreferenceStore;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'WardPulse',
      debugShowCheckedModeBanner: false,
      theme: wardPulseLightTheme,
      darkTheme: wardPulseDarkTheme,
      home: DashboardHost(
        repository: repository,
        watchSyncService: watchSyncService,
        credentialStore: credentialStore,
        codexAccountService: codexAccountService,
        displayPreferenceStore: displayPreferenceStore,
        refreshIntervalStore: refreshIntervalStore,
        syncScheduler: syncScheduler,
        debugDataAvailable: debugDataAvailable,
        debugDataPreferenceStore: debugDataPreferenceStore,
      ),
    );
  }
}

class DashboardHost extends StatefulWidget {
  const DashboardHost({
    super.key,
    required this.repository,
    required this.watchSyncService,
    required this.credentialStore,
    required this.codexAccountService,
    required this.displayPreferenceStore,
    required this.refreshIntervalStore,
    required this.syncScheduler,
    required this.debugDataAvailable,
    required this.debugDataPreferenceStore,
  });

  final DashboardRepository repository;
  final WatchSyncService watchSyncService;
  final ProviderCredentialStore credentialStore;
  final CodexAccountService codexAccountService;
  final ConsumptionDisplayPreferenceStore displayPreferenceStore;
  final RefreshIntervalPreferenceStore refreshIntervalStore;
  final ProviderSyncScheduler syncScheduler;
  final bool debugDataAvailable;
  final DebugDataPreferenceStore debugDataPreferenceStore;

  @override
  State<DashboardHost> createState() => _DashboardHostState();
}

class _DashboardHostState extends State<DashboardHost> {
  static const _settingsIndex = 2;

  /// Account ids carried by each platform connection's normalized report.
  static const _platformAccountIds = {
    'openai-local': ProviderConnections.openAiPlatform,
    'anthropic-local': ProviderConnections.anthropicPlatform,
    'cursor-team-local': ProviderConnections.cursorPlatform,
  };

  late Future<DashboardSnapshot> _snapshot = _loadSnapshot();
  DashboardSnapshot? _currentSnapshot;
  ConsumptionDisplayPreferences _displayPreferences =
      const ConsumptionDisplayPreferences();
  RefreshIntervalPreference _refreshInterval =
      const RefreshIntervalPreference();
  Map<String, String> _platformLabels = const {};
  bool _mockDataEnabled = false;
  int _selectedIndex = 0;
  StreamSubscription<void>? _syncTicks;
  var _autoSyncInFlight = false;

  @override
  void initState() {
    super.initState();
    _syncTicks = widget.syncScheduler.ticks.listen((_) {
      unawaited(_onScheduledSync());
    });
  }

  @override
  void dispose() {
    unawaited(_syncTicks?.cancel());
    unawaited(widget.syncScheduler.cancel());
    super.dispose();
  }

  Future<void> _readDisplayPreferences() async {
    try {
      final value = await widget.displayPreferenceStore.read();
      _displayPreferences = value;
    } catch (_) {
      // The default plan view remains available if local preferences fail.
    }
  }

  Future<void> _readRefreshInterval() async {
    try {
      _refreshInterval = await widget.refreshIntervalStore.read();
    } catch (_) {
      _refreshInterval = const RefreshIntervalPreference();
    }
  }

  Future<void> _readConnectionMetadata() async {
    try {
      final labels = <String, String>{};
      for (final entry in _platformAccountIds.entries) {
        final label = await widget.credentialStore.readLabel(entry.value);
        if (label != null) {
          labels[entry.key] = label;
        }
      }
      _platformLabels = labels;
    } catch (_) {
      _platformLabels = const {};
    }
  }

  Future<void> _readDebugDataPreference() async {
    if (!widget.debugDataAvailable) {
      _mockDataEnabled = false;
      return;
    }
    try {
      _mockDataEnabled =
          await widget.debugDataPreferenceStore.readMockDataEnabled();
    } catch (_) {
      _mockDataEnabled = false;
    }
  }

  Future<void> _updateDisplayPreferences(
    ConsumptionDisplayPreferences value,
  ) async {
    await widget.displayPreferenceStore.write(value);
    if (mounted) {
      setState(() {
        _displayPreferences = value;
      });
    }
    final snapshot = _currentSnapshot;
    if (snapshot != null) {
      unawaited(_syncWatch(snapshot));
    }
  }

  Future<void> _updateRefreshInterval(RefreshIntervalPreference value) async {
    await widget.refreshIntervalStore.write(value);
    if (mounted) {
      setState(() {
        _refreshInterval = value;
      });
    }
    await widget.syncScheduler.schedule(value.interval);
  }

  Future<DashboardSnapshot> _loadSnapshot() async {
    await _readDisplayPreferences();
    await _readRefreshInterval();
    await _readConnectionMetadata();
    await _readDebugDataPreference();
    // Rescheduling before the load keeps the next tick a full interval away, so
    // no connection is polled faster than its floor, and a failed load still
    // retries on the next tick.
    unawaited(widget.syncScheduler.schedule(_refreshInterval.interval));
    final snapshot = await widget.repository.load();
    _currentSnapshot = snapshot;
    unawaited(_syncWatch(snapshot));
    return snapshot;
  }

  Future<void> _onScheduledSync() async {
    if (_autoSyncInFlight || !mounted) {
      return;
    }
    _autoSyncInFlight = true;
    try {
      // Do not invalidate: load() already refetches, and clearing caches would
      // drop stale-with-issue recovery on a failed automatic tick.
      final snapshot = await widget.repository.load();
      _currentSnapshot = snapshot;
      if (mounted) {
        setState(() {
          _snapshot = Future.value(snapshot);
        });
      }
      await _syncWatch(snapshot);
    } catch (_) {
      // Automatic sync failures keep the last successful snapshot visible.
    } finally {
      _autoSyncInFlight = false;
    }
  }

  Future<void> _updateMockDataEnabled(bool value) async {
    await widget.debugDataPreferenceStore.writeMockDataEnabled(value);
    if (!mounted) {
      return;
    }
    widget.repository.invalidate();
    setState(() {
      _mockDataEnabled = value;
      _snapshot = _loadSnapshot();
    });
  }

  Future<void> _syncWatch(DashboardSnapshot snapshot) async {
    try {
      await widget.watchSyncService.sync(snapshot, _displayPreferences);
    } catch (_) {
      // Watch availability must not block the phone dashboard.
    }
  }

  void _reload() {
    setState(() {
      _snapshot = _loadSnapshot();
    });
  }

  void _openSettings() {
    setState(() {
      _selectedIndex = _settingsIndex;
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<DashboardSnapshot>(
      future: _snapshot,
      builder: (context, state) {
        final snapshot = state.data;

        return Scaffold(
          appBar: AppBar(
            title: const Text('WardPulse'),
            actions: [
              if (snapshot != null)
                Padding(
                  padding: const EdgeInsetsDirectional.only(end: 12),
                  child: StatusPill(
                    status: snapshot.overallStatus,
                    tooltip: snapshot.syncTooltip,
                  ),
                ),
              IconButton(
                tooltip: 'Refresh',
                onPressed: _reload,
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          body: SafeArea(
            child: switch (state.connectionState) {
              _ when _selectedIndex == _settingsIndex => SettingsScreen(
                key: const ValueKey('settings'),
                snapshot: snapshot,
                watchSyncService: widget.watchSyncService,
                credentialStore: widget.credentialStore,
                codexAccountService: widget.codexAccountService,
                displayPreferences: _displayPreferences,
                onDisplayPreferencesChanged: _updateDisplayPreferences,
                refreshInterval: _refreshInterval,
                onRefreshIntervalChanged: _updateRefreshInterval,
                debugDataAvailable: widget.debugDataAvailable,
                mockDataEnabled: _mockDataEnabled,
                onMockDataEnabledChanged: _updateMockDataEnabled,
                onCredentialsChanged: () {
                  unawaited(() async {
                    await _readConnectionMetadata();
                    if (!mounted) {
                      return;
                    }
                    widget.repository.invalidate();
                    _reload();
                  }());
                },
              ),
              ConnectionState.waiting => const _LoadingView(),
              _ when state.hasError => _ErrorView(
                failure: _dashboardFailure(state.error),
                onRetry: _reload,
                onOpenSettings: _openSettings,
              ),
              _ when snapshot != null => _SelectedSurface(
                selectedIndex: _selectedIndex,
                snapshot: snapshot,
                displayPreferences: _displayPreferences,
                platformLabels: _platformLabels,
                onOpenSettings: _openSettings,
              ),
              _ => _ErrorView(
                failure: const DashboardLoadException(),
                onRetry: _reload,
              ),
            },
          ),
          bottomNavigationBar: NavigationBar(
            selectedIndex: _selectedIndex,
            onDestinationSelected: (index) {
              setState(() {
                _selectedIndex = index;
              });
            },
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.dashboard_outlined),
                selectedIcon: Icon(Icons.dashboard),
                label: 'Dashboard',
              ),
              NavigationDestination(
                icon: Icon(Icons.hub_outlined),
                selectedIcon: Icon(Icons.hub),
                label: 'Providers',
              ),
              NavigationDestination(
                icon: Icon(Icons.settings_outlined),
                selectedIcon: Icon(Icons.settings),
                label: 'Settings',
              ),
            ],
          ),
        );
      },
    );
  }
}

class _SelectedSurface extends StatelessWidget {
  const _SelectedSurface({
    required this.selectedIndex,
    required this.snapshot,
    required this.displayPreferences,
    this.platformLabels = const {},
    this.onOpenSettings,
  });

  final int selectedIndex;
  final DashboardSnapshot snapshot;
  final ConsumptionDisplayPreferences displayPreferences;
  final Map<String, String> platformLabels;
  final VoidCallback? onOpenSettings;

  @override
  Widget build(BuildContext context) {
    return switch (selectedIndex) {
      0 => DashboardScreen(
        snapshot: snapshot,
        displayPreferences: displayPreferences,
        onOpenSettings: onOpenSettings,
      ),
      _ => ProvidersScreen(
        snapshot: snapshot,
        displayPreferences: displayPreferences,
        platformLabels: platformLabels,
      ),
    };
  }
}

class _LoadingView extends StatelessWidget {
  const _LoadingView();

  @override
  Widget build(BuildContext context) {
    return const Center(child: CircularProgressIndicator());
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({
    required this.failure,
    required this.onRetry,
    this.onOpenSettings,
  });

  final DashboardLoadException failure;
  final VoidCallback onRetry;
  final VoidCallback? onOpenSettings;

  @override
  Widget build(BuildContext context) {
    if (failure.issue == DashboardSyncIssue.noProviders) {
      return ConnectProviderPrompt(onOpenSettings: onOpenSettings);
    }

    final colors = Theme.of(context).colorScheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Tooltip(
              message: failure.issue.message,
              child: Icon(Icons.error_outline, color: colors.error, size: 36),
            ),
            const SizedBox(height: 12),
            Text(
              'Dashboard unavailable',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              failure.issue.message,
              textAlign: TextAlign.center,
              style: TextStyle(color: colors.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              children: [
                if (failure.details != null)
                  TextButton.icon(
                    onPressed:
                        () => _showErrorDetails(context, failure.details!),
                    icon: const Icon(Icons.info_outline),
                    label: const Text('Details'),
                  ),
                FilledButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retry'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

DashboardLoadException _dashboardFailure(Object? error) {
  return error is DashboardLoadException
      ? error
      : const DashboardLoadException();
}

void _showErrorDetails(BuildContext context, String details) {
  showDialog<void>(
    context: context,
    builder:
        (context) => AlertDialog(
          title: const Text('Error details'),
          content: SelectableText(details),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ],
        ),
  );
}
