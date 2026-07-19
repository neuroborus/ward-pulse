import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../dashboard/dashboard_models.dart';
import '../dashboard/dashboard_screen.dart';
import '../providers/provider_credential_store.dart';
import '../sync/watch_sync_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    required this.snapshot,
    required this.watchSyncService,
    required this.credentialStore,
    required this.onCredentialsChanged,
  });

  final DashboardSnapshot? snapshot;
  final WatchSyncService watchSyncService;
  final ProviderCredentialStore credentialStore;
  final VoidCallback onCredentialsChanged;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool? _hasCredential;
  bool _isSyncing = false;
  String? _syncResult;

  @override
  void initState() {
    super.initState();
    _loadCredentialState();
  }

  Future<void> _loadCredentialState() async {
    try {
      final value = await widget.credentialStore.readOpenAiAdminKey();
      if (mounted) {
        setState(() {
          _hasCredential = value != null;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _hasCredential = false;
        });
      }
    }
  }

  Future<void> _editCredential() async {
    final change = await showDialog<_CredentialChange>(
      context: context,
      builder:
          (context) =>
              _CredentialDialog(hasCredential: _hasCredential ?? false),
    );
    if (change == null) {
      return;
    }

    try {
      if (change.remove) {
        await widget.credentialStore.deleteOpenAiAdminKey();
      } else {
        await widget.credentialStore.writeOpenAiAdminKey(change.value!);
      }
      if (!mounted) {
        return;
      }
      setState(() {
        _hasCredential = !change.remove;
      });
      widget.onCredentialsChanged();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not update credential')),
        );
      }
    }
  }

  Future<void> _syncWatch() async {
    final snapshot = widget.snapshot;
    if (snapshot == null) {
      return;
    }

    setState(() {
      _isSyncing = true;
      _syncResult = null;
    });

    try {
      await widget.watchSyncService.sync(snapshot);
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
    final snapshot = widget.snapshot;

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
                title: const Text('OpenAI credential'),
                subtitle: const Text('Admin API key · stored on this phone'),
                trailing: switch (_hasCredential) {
                  null => const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  true => const Text('••••••••'),
                  false => const Text('Not set'),
                },
                onTap: _hasCredential == null ? null : _editCredential,
              ),
              if (snapshot != null) ...[
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
              if (kDebugMode && snapshot != null) ...[
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

class _CredentialDialog extends StatefulWidget {
  const _CredentialDialog({required this.hasCredential});

  final bool hasCredential;

  @override
  State<_CredentialDialog> createState() => _CredentialDialogState();
}

class _CredentialDialogState extends State<_CredentialDialog> {
  final _formKey = GlobalKey<FormState>();
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save() {
    if (_formKey.currentState?.validate() ?? false) {
      Navigator.of(
        context,
      ).pop(_CredentialChange.save(_controller.text.trim()));
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('OpenAI Admin API key'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'This privileged key is encrypted on this phone and sent only to OpenAI.',
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _controller,
              autofocus: true,
              obscureText: true,
              autocorrect: false,
              enableSuggestions: false,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'Admin API key',
              ),
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (_) => _save(),
              validator:
                  (value) =>
                      value == null || value.trim().isEmpty
                          ? 'Enter an Admin API key'
                          : null,
            ),
          ],
        ),
      ),
      actions: [
        if (widget.hasCredential)
          TextButton(
            onPressed: () {
              Navigator.of(context).pop(const _CredentialChange.remove());
            },
            child: const Text('Remove'),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}

final class _CredentialChange {
  const _CredentialChange.save(this.value) : remove = false;

  const _CredentialChange.remove() : value = null, remove = true;

  final String? value;
  final bool remove;
}
