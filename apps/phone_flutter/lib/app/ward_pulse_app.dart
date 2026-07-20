import 'dart:async';

import 'package:flutter/material.dart';

import '../dashboard/dashboard_models.dart';
import '../dashboard/dashboard_repository.dart';
import '../dashboard/dashboard_screen.dart';
import '../providers/codex_account_service.dart';
import '../providers/provider_credential_store.dart';
import '../providers/providers_screen.dart';
import '../settings/settings_screen.dart';
import '../settings/consumption_display_preferences.dart';
import '../settings/debug_data_preferences.dart';
import '../sync/watch_sync_service.dart';

final ColorScheme _lightColorScheme = ColorScheme.fromSeed(
  seedColor: const Color(0xFF67E8D4),
  dynamicSchemeVariant: DynamicSchemeVariant.fidelity,
  primary: const Color(0xFF006B60),
  onPrimary: Colors.white,
  tertiary: const Color(0xFF715D00),
  onTertiary: Colors.white,
  tertiaryContainer: const Color(0xFFFFE16B),
  onTertiaryContainer: const Color(0xFF221B00),
);

final ColorScheme _darkColorScheme = ColorScheme.fromSeed(
  seedColor: const Color(0xFF67E8D4),
  brightness: Brightness.dark,
  dynamicSchemeVariant: DynamicSchemeVariant.fidelity,
  primary: const Color(0xFF67E8D4),
  onPrimary: const Color(0xFF002F2A),
  primaryContainer: const Color(0xFF155B45),
  onPrimaryContainer: const Color(0xFFF4FBF8),
  tertiary: const Color(0xFFE6C349),
  onTertiary: const Color(0xFF3C2F00),
  tertiaryContainer: const Color(0xFF574500),
  onTertiaryContainer: const Color(0xFFFFE17A),
);

class WardPulseApp extends StatelessWidget {
  const WardPulseApp({
    super.key,
    required this.repository,
    this.watchSyncService = const MethodChannelWatchSyncService(),
    this.credentialStore = const EmptyProviderCredentialStore(),
    this.codexAccountService = const EmptyCodexAccountService(),
    this.displayPreferenceStore =
        const DefaultConsumptionDisplayPreferenceStore(),
    this.debugDataAvailable = false,
    this.debugDataPreferenceStore = const DisabledDebugDataPreferenceStore(),
  });

  final DashboardRepository repository;
  final WatchSyncService watchSyncService;
  final ProviderCredentialStore credentialStore;
  final CodexAccountService codexAccountService;
  final ConsumptionDisplayPreferenceStore displayPreferenceStore;
  final bool debugDataAvailable;
  final DebugDataPreferenceStore debugDataPreferenceStore;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'WardPulse',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorScheme: _lightColorScheme, useMaterial3: true),
      darkTheme: ThemeData(colorScheme: _darkColorScheme, useMaterial3: true),
      home: DashboardHost(
        repository: repository,
        watchSyncService: watchSyncService,
        credentialStore: credentialStore,
        codexAccountService: codexAccountService,
        displayPreferenceStore: displayPreferenceStore,
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
    required this.debugDataAvailable,
    required this.debugDataPreferenceStore,
  });

  final DashboardRepository repository;
  final WatchSyncService watchSyncService;
  final ProviderCredentialStore credentialStore;
  final CodexAccountService codexAccountService;
  final ConsumptionDisplayPreferenceStore displayPreferenceStore;
  final bool debugDataAvailable;
  final DebugDataPreferenceStore debugDataPreferenceStore;

  @override
  State<DashboardHost> createState() => _DashboardHostState();
}

class _DashboardHostState extends State<DashboardHost> {
  late Future<DashboardSnapshot> _snapshot = _loadSnapshot();
  DashboardSnapshot? _currentSnapshot;
  ConsumptionDisplayPreferences _displayPreferences =
      const ConsumptionDisplayPreferences();
  bool _mockDataEnabled = false;
  int _selectedIndex = 0;

  Future<void> _readDisplayPreferences() async {
    try {
      final value = await widget.displayPreferenceStore.read();
      _displayPreferences = value;
    } catch (_) {
      // The default plan view remains available if local preferences fail.
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

  Future<DashboardSnapshot> _loadSnapshot() async {
    await _readDisplayPreferences();
    await _readDebugDataPreference();
    final snapshot = await widget.repository.load();
    _currentSnapshot = snapshot;
    unawaited(_syncWatch(snapshot));
    return snapshot;
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
              _ when _selectedIndex == 2 => SettingsScreen(
                snapshot: snapshot,
                watchSyncService: widget.watchSyncService,
                credentialStore: widget.credentialStore,
                codexAccountService: widget.codexAccountService,
                displayPreferences: _displayPreferences,
                onDisplayPreferencesChanged: _updateDisplayPreferences,
                debugDataAvailable: widget.debugDataAvailable,
                mockDataEnabled: _mockDataEnabled,
                onMockDataEnabledChanged: _updateMockDataEnabled,
                onCredentialsChanged: () {
                  widget.repository.invalidate();
                  _reload();
                },
              ),
              ConnectionState.waiting => const _LoadingView(),
              _ when state.hasError => _ErrorView(
                failure: _dashboardFailure(state.error),
                onRetry: _reload,
              ),
              _ when snapshot != null => _SelectedSurface(
                selectedIndex: _selectedIndex,
                snapshot: snapshot,
                displayPreferences: _displayPreferences,
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
  });

  final int selectedIndex;
  final DashboardSnapshot snapshot;
  final ConsumptionDisplayPreferences displayPreferences;

  @override
  Widget build(BuildContext context) {
    return switch (selectedIndex) {
      0 => DashboardScreen(
        snapshot: snapshot,
        displayPreferences: displayPreferences,
      ),
      _ => ProvidersScreen(
        snapshot: snapshot,
        displayPreferences: displayPreferences,
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
  const _ErrorView({required this.failure, required this.onRetry});

  final DashboardLoadException failure;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
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
