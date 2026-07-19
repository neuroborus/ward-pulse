import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../dashboard/dashboard_models.dart';
import '../dashboard/dashboard_screen.dart';
import '../sync/watch_sync_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    required this.snapshot,
    required this.watchSyncService,
  });

  final DashboardSnapshot snapshot;
  final WatchSyncService watchSyncService;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _isSyncing = false;
  String? _syncResult;

  Future<void> _syncWatch() async {
    setState(() {
      _isSyncing = true;
      _syncResult = null;
    });

    try {
      await widget.watchSyncService.sync(widget.snapshot);
      if (mounted) {
        setState(() {
          _syncResult = 'Watch summary queued';
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

  @override
  Widget build(BuildContext context) {
    final account = widget.snapshot.primaryAccount;

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
                subtitle: Text(formatUtc(widget.snapshot.generatedAt)),
                trailing: StatusPill(status: widget.snapshot.overallStatus),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.watch_outlined),
                title: const Text('Watch summary'),
                subtitle: Text(
                  'Today ${widget.snapshot.todayTotal.usedPercentLabel}',
                ),
                trailing: StatusPill(
                  status: widget.snapshot.watchSummary.status,
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
    );
  }
}
