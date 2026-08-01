import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../sync/claude_account_client.dart';
import 'claude_account_service.dart';
import 'connected_account_dialog.dart';
import 'cursor_plan_row.dart';
import 'provider_connection.dart';
import 'provider_credential_store.dart';
import 'provider_connection_row.dart';

/// Claude subscription row: Claude Code OAuth sign-in, reconnect, disconnect.
///
/// Owns its own connected/connecting state so the Providers screen does not.
class ClaudeAccountRow extends StatefulWidget {
  const ClaudeAccountRow({
    super.key,
    required this.connection,
    required this.accountService,
    required this.credentialStore,
    required this.onCredentialsChanged,
    required this.onPastedSecretCleared,
    required this.buildTrailing,
  });

  final ProviderConnection connection;
  final ClaudeAccountService accountService;
  final ProviderCredentialStore credentialStore;
  final VoidCallback onCredentialsChanged;

  /// OAuth supersedes a pasted token; lets the screen drop its cached flag.
  final VoidCallback onPastedSecretCleared;
  final ConnectionTrailingBuilder buildTrailing;

  @override
  State<ClaudeAccountRow> createState() => _ClaudeAccountRowState();
}

class _ClaudeAccountRowState extends State<ClaudeAccountRow> {
  bool? _hasAccount;
  bool _isConnecting = false;

  @override
  void initState() {
    super.initState();
    _loadState();
  }

  Future<void> _loadState() async {
    try {
      final value = await widget.accountService.isConnected();
      if (mounted) {
        setState(() {
          _hasAccount = value;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _hasAccount = false;
        });
      }
    }
  }

  Future<void> _editAccount() async {
    if (_hasAccount == true) {
      final action = await showDialog<AccountAction>(
        context: context,
        builder:
            (context) => const ConnectedAccountDialog(
              title: 'Claude account',
              message:
                  'WardPulse reads Claude subscription windows directly on '
                  'this phone using Claude Code OAuth.',
            ),
      );
      if (action == AccountAction.disconnect) {
        try {
          await widget.accountService.disconnect();
        } on ClaudeAccountException catch (error) {
          if (mounted) {
            _showMessage(error.details ?? 'Could not disconnect Claude');
          }
          return;
        } catch (_) {
          if (mounted) {
            _showMessage('Could not disconnect Claude');
          }
          return;
        }
        if (mounted) {
          setState(() {
            _hasAccount = false;
          });
          widget.onCredentialsChanged();
        }
        return;
      }
      if (action != AccountAction.reconnect) {
        return;
      }
    }

    setState(() {
      _isConnecting = true;
    });
    try {
      final attempt = await widget.accountService.startLogin();
      if (!mounted) {
        attempt.cancel();
        return;
      }
      final connected = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (context) => _ClaudeLoginDialog(attempt: attempt),
      );
      if (connected == true && mounted) {
        // Drop any pre-OAuth pasted access token for this connection.
        try {
          await widget.credentialStore.deleteSecret(
            ProviderConnections.claudePlan,
          );
        } catch (_) {
          // Session is already saved; orphaned paste is non-fatal.
        }
        if (!mounted) {
          return;
        }
        setState(() {
          _hasAccount = true;
        });
        widget.onPastedSecretCleared();
        widget.onCredentialsChanged();
      }
    } on ClaudeAccountException catch (error) {
      if (mounted && error.failure != ClaudeAccountFailure.cancelled) {
        _showMessage(error.details ?? 'Could not start Claude sign-in');
      }
    } catch (_) {
      if (mounted) {
        _showMessage('Could not start Claude sign-in');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isConnecting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ProviderConnectionRow(
      icon: Icons.account_circle_outlined,
      title: widget.connection.listTitle,
      subtitle: widget.connection.listSubtitle,
      trailing: widget.buildTrailing(
        status: switch ((_hasAccount, _isConnecting)) {
          (_, true) || (null, _) => const RowProgress(),
          (true, _) => const Text('Connected'),
          (false, _) => const Text('Not connected'),
        },
      ),
      onTap: _hasAccount == null || _isConnecting ? null : _editAccount,
    );
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}

class _ClaudeLoginDialog extends StatefulWidget {
  const _ClaudeLoginDialog({required this.attempt});

  final ClaudeLoginAttempt attempt;

  @override
  State<_ClaudeLoginDialog> createState() => _ClaudeLoginDialogState();
}

class _ClaudeLoginDialogState extends State<_ClaudeLoginDialog> {
  final _codeController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  String? _browserError;
  String? _submitError;
  bool _submitting = false;
  bool _completed = false;

  @override
  void dispose() {
    _codeController.dispose();
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
        widget.attempt.authorization.authorizationUri,
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

  Future<void> _submit() async {
    if (_submitting || !(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    setState(() {
      _submitting = true;
      _submitError = null;
    });
    try {
      await widget.attempt.completeWithCode(_codeController.text);
      _completed = true;
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } on ClaudeAccountException catch (error) {
      if (mounted && error.failure != ClaudeAccountFailure.cancelled) {
        setState(() {
          _submitError = error.details ?? 'Claude sign-in failed';
          _submitting = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _submitError = 'Claude sign-in failed';
          _submitting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Connect Claude'),
      scrollable: true,
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Open the secure Claude sign-in page, approve access, then paste '
              'the authorization code from the callback page (CODE#STATE).',
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _codeController,
              enabled: !_submitting,
              autocorrect: false,
              enableSuggestions: false,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'Authorization code',
                hintText: 'CODE#STATE',
              ),
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (_) => _submit(),
              validator: (value) {
                return value == null || value.trim().isEmpty
                    ? 'Paste the authorization code'
                    : null;
              },
            ),
            const SizedBox(height: 12),
            if (_submitting) const LinearProgressIndicator(),
            if (_submitError != null)
              Text(
                _submitError!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            if (_browserError != null) ...[
              const SizedBox(height: 8),
              Text(
                _browserError!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed:
              _submitting ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed: _submitting ? null : _openBrowser,
          icon: const Icon(Icons.open_in_browser),
          label: const Text('Open browser'),
        ),
        FilledButton(
          onPressed: _submitting ? null : _submit,
          child: const Text('Continue'),
        ),
      ],
    );
  }
}
