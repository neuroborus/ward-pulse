import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../dashboard/dashboard_models.dart';
import '../dashboard/dashboard_screen.dart';
import '../providers/codex_account_service.dart';
import '../providers/provider_credential_store.dart';
import '../sync/codex_account_client.dart';
import '../sync/watch_sync_service.dart';
import 'consumption_display_preferences.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    required this.snapshot,
    required this.watchSyncService,
    required this.credentialStore,
    required this.codexAccountService,
    required this.displayPreferences,
    required this.onDisplayPreferencesChanged,
    required this.onCredentialsChanged,
  });

  final DashboardSnapshot? snapshot;
  final WatchSyncService watchSyncService;
  final ProviderCredentialStore credentialStore;
  final CodexAccountService codexAccountService;
  final ConsumptionDisplayPreferences displayPreferences;
  final Future<void> Function(ConsumptionDisplayPreferences value)
  onDisplayPreferencesChanged;
  final VoidCallback onCredentialsChanged;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool? _hasCredential;
  bool? _hasCodexAccount;
  bool _isConnectingCodex = false;
  bool _isSyncing = false;
  String? _syncResult;

  @override
  void initState() {
    super.initState();
    _loadCredentialState();
    _loadCodexAccountState();
  }

  Future<void> _loadCodexAccountState() async {
    try {
      final value = await widget.codexAccountService.isConnected();
      if (mounted) {
        setState(() {
          _hasCodexAccount = value;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _hasCodexAccount = false;
        });
      }
    }
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

  Future<void> _editCodexAccount() async {
    if (_hasCodexAccount == true) {
      final action = await showDialog<_CodexAccountAction>(
        context: context,
        builder: (context) => const _ConnectedCodexAccountDialog(),
      );
      if (action == _CodexAccountAction.disconnect) {
        try {
          await widget.codexAccountService.disconnect();
        } on CodexAccountException catch (error) {
          if (mounted) {
            _showMessage(error.details ?? 'Could not disconnect Codex');
          }
          return;
        } catch (_) {
          if (mounted) {
            _showMessage('Could not disconnect Codex');
          }
          return;
        }
        if (mounted) {
          setState(() {
            _hasCodexAccount = false;
          });
          widget.onCredentialsChanged();
        }
        return;
      }
      if (action != _CodexAccountAction.reconnect) {
        return;
      }
    }

    setState(() {
      _isConnectingCodex = true;
    });
    try {
      final attempt = await widget.codexAccountService.startLogin();
      if (!mounted) {
        attempt.cancel();
        return;
      }
      final connected = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (context) => _CodexLoginDialog(attempt: attempt),
      );
      if (connected == true && mounted) {
        setState(() {
          _hasCodexAccount = true;
        });
        widget.onCredentialsChanged();
      }
    } on CodexAccountException catch (error) {
      if (mounted && error.failure != CodexAccountFailure.cancelled) {
        _showMessage(error.details ?? 'Could not start Codex sign-in');
      }
    } catch (_) {
      if (mounted) {
        _showMessage('Could not start Codex sign-in');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isConnectingCodex = false;
        });
      }
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
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
      await widget.watchSyncService.sync(snapshot, widget.displayPreferences);
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

  Future<void> _setDisplayPreferences(
    ConsumptionDisplayPreferences value,
  ) async {
    if (!value.plan && !value.purchased) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Keep at least one usage source visible')),
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
                subtitle: const Text('Purchased tokens or credits'),
                value: widget.displayPreferences.purchased,
                onChanged:
                    (value) => _setDisplayPreferences(
                      widget.displayPreferences.copyWith(purchased: value),
                    ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Card(
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.account_circle_outlined),
                title: const Text('Codex account'),
                subtitle: const Text(
                  'Experimental · plan limits and token activity',
                ),
                trailing: switch ((_hasCodexAccount, _isConnectingCodex)) {
                  (_, true) => const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  (null, _) => const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  (true, _) => const Text('Connected'),
                  (false, _) => const Text('Not connected'),
                },
                onTap:
                    _hasCodexAccount == null || _isConnectingCodex
                        ? null
                        : _editCodexAccount,
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.key_outlined),
                title: const Text('OpenAI Platform credential'),
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
                    'Today ${snapshot.todayTotal.usedPercentLabel}',
                  ),
                  trailing: StatusPill(
                    status: snapshot.watchSummary.status,
                    tooltip: snapshot.syncTooltip,
                  ),
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

class _ConnectedCodexAccountDialog extends StatelessWidget {
  const _ConnectedCodexAccountDialog();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Codex account'),
      content: const Text(
        'WardPulse reads subscription limits and token activity directly on this phone.',
      ),
      actions: [
        TextButton(
          onPressed:
              () => Navigator.of(context).pop(_CodexAccountAction.disconnect),
          child: const Text('Disconnect'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed:
              () => Navigator.of(context).pop(_CodexAccountAction.reconnect),
          child: const Text('Reconnect'),
        ),
      ],
    );
  }
}

class _CodexLoginDialog extends StatefulWidget {
  const _CodexLoginDialog({required this.attempt});

  final CodexLoginAttempt attempt;

  @override
  State<_CodexLoginDialog> createState() => _CodexLoginDialogState();
}

class _CodexLoginDialogState extends State<_CodexLoginDialog> {
  String? _error;
  String? _browserError;
  bool _completed = false;

  @override
  void initState() {
    super.initState();
    _waitForLogin();
  }

  Future<void> _waitForLogin() async {
    try {
      await widget.attempt.completion;
      _completed = true;
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } on CodexAccountException catch (error) {
      if (mounted && error.failure != CodexAccountFailure.cancelled) {
        setState(() {
          _error = error.details ?? 'Codex sign-in failed';
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'Codex sign-in failed';
        });
      }
    }
  }

  @override
  void dispose() {
    if (!_completed) {
      widget.attempt.cancel();
    }
    super.dispose();
  }

  Future<void> _openBrowser() async {
    if (_browserError != null) {
      setState(() {
        _browserError = null;
      });
    }
    try {
      final opened = await launchUrl(
        widget.attempt.deviceCode.verificationUri,
        mode: LaunchMode.externalApplication,
      );
      if (opened || !mounted) {
        return;
      }
    } catch (_) {
      if (!mounted) {
        return;
      }
    }
    if (mounted) {
      setState(() {
        _browserError = 'Could not open the browser';
      });
    }
  }

  Future<void> _copyCode() async {
    await Clipboard.setData(
      ClipboardData(text: widget.attempt.deviceCode.userCode),
    );
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Code copied')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Connect Codex'),
      scrollable: true,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Open the secure OpenAI sign-in page, then enter this one-time code:',
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: SelectableText(
                  widget.attempt.deviceCode.userCode,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
              ),
              IconButton(
                tooltip: 'Copy code',
                onPressed: _copyCode,
                icon: const Icon(Icons.copy_outlined),
              ),
            ],
          ),
          SelectableText(
            widget.attempt.deviceCode.verificationUri.toString(),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          if (_error == null)
            const LinearProgressIndicator()
          else
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          if (_browserError != null) ...[
            const SizedBox(height: 12),
            Text(
              _browserError!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed: _error == null ? _openBrowser : null,
          icon: const Icon(Icons.open_in_browser),
          label: const Text('Open browser'),
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
  bool _obscureKey = true;

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
              obscureText: _obscureKey,
              autocorrect: false,
              enableSuggestions: false,
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                labelText: 'Admin API key',
                suffixIcon: IconButton(
                  tooltip: _obscureKey ? 'Show API key' : 'Hide API key',
                  onPressed: () {
                    setState(() {
                      _obscureKey = !_obscureKey;
                    });
                  },
                  icon: Icon(
                    _obscureKey
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                  ),
                ),
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

enum _CodexAccountAction { reconnect, disconnect }
