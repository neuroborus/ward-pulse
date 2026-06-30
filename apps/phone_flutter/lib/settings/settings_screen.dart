import 'package:flutter/material.dart';

import '../dashboard/dashboard_models.dart';
import '../dashboard/dashboard_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key, required this.snapshot});

  final DashboardSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final account = snapshot.primaryAccount;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        Card(
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.key_outlined),
                title: const Text('Credentials'),
                subtitle: Text(account?.providerLabel ?? 'No provider'),
                trailing: const Text('Not set'),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.sync_outlined),
                title: const Text('Sync'),
                subtitle: Text(formatUtc(snapshot.generatedAt)),
                trailing: StatusPill(status: snapshot.overallStatus),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.watch_outlined),
                title: const Text('Watch summary'),
                subtitle: Text(
                  'Today ${snapshot.todayTotal.usedPercentLabel}',
                ),
                trailing: StatusPill(status: snapshot.watchSummary.status),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
