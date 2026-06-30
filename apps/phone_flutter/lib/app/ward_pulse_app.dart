import 'package:flutter/material.dart';

import '../dashboard/dashboard_models.dart';
import '../dashboard/dashboard_repository.dart';
import '../dashboard/dashboard_screen.dart';
import '../providers/providers_screen.dart';
import '../settings/settings_screen.dart';

class WardPulseApp extends StatelessWidget {
  const WardPulseApp({
    super.key,
    this.repository = const AssetDashboardRepository(),
  });

  final DashboardRepository repository;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'WardPulse',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1F7A5A),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1F7A5A),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: DashboardHost(repository: repository),
    );
  }
}

class DashboardHost extends StatefulWidget {
  const DashboardHost({super.key, required this.repository});

  final DashboardRepository repository;

  @override
  State<DashboardHost> createState() => _DashboardHostState();
}

class _DashboardHostState extends State<DashboardHost> {
  late Future<DashboardSnapshot> _snapshot = widget.repository.load();
  int _selectedIndex = 0;

  void _reload() {
    setState(() {
      _snapshot = widget.repository.load();
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
                  child: StatusPill(status: snapshot.overallStatus),
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
              ConnectionState.waiting => const _LoadingView(),
              _ when state.hasError => _ErrorView(onRetry: _reload),
              _ when snapshot != null => _SelectedSurface(
                  selectedIndex: _selectedIndex,
                  snapshot: snapshot,
                ),
              _ => _ErrorView(onRetry: _reload),
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
  });

  final int selectedIndex;
  final DashboardSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    return switch (selectedIndex) {
      0 => DashboardScreen(snapshot: snapshot),
      1 => ProvidersScreen(snapshot: snapshot),
      _ => SettingsScreen(snapshot: snapshot),
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
  const _ErrorView({required this.onRetry});

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
            Icon(Icons.error_outline, color: colors.error, size: 36),
            const SizedBox(height: 12),
            Text(
              'Dashboard unavailable',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}
