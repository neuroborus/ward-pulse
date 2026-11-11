import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../sync/claude_account_client.dart';
import 'claude_account_service.dart';
import 'connected_account_dialog.dart';
import 'provider_connection.dart';
import 'provider_connection_row.dart';
import 'provider_credential_store.dart';

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
    required this.buildControls,
    this.onInitialRead,
  });

  final ProviderConnection connection;
  final ClaudeAccountService accountService;
  final ProviderCredentialStore credentialStore;
  final VoidCallback onCredentialsChanged;

  /// OAuth supersedes a pasted token; lets the screen drop its cached flag.
  final VoidCallback onPastedSecretCleared;
  final ConnectionRowControlsBuilder buildControls;

  /// Registers the initial local read with the containing reveal layout.
  final VoidCallback Function()? onInitialRead;

  @override
  State<ClaudeAccountRow> createState() => _ClaudeAccountRowState();
}

class _ClaudeAccountRowState extends State<ClaudeAccountRow> {
  bool? _hasAccount;
  VoidCallback? _finishInitialRead;
  bool _isConnecting = false;

  @override
  void initState() {
    super.initState();
    _finishInitialRead = widget.onInitialRead?.call();
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
    } finally {
      _finishInitialRead?.call();
      _finishInitialRead = null;
    }
  }

  @override
  void dispose() {
    _finishInitialRead?.call();
    _finishInitialRead = null;
    super.dispose();
  }

  Future<void> _editAccount() async {
    if (_hasAccount == true) {
      final action = await showDialog<AccountAction>(
        context: context,
        builder:
            (context) => const ConnectedAccountDialog(
              title: 'Claude plan',
              message:
                  'WardPulse reads Claude plan windows directly on '
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
        builder:
            (context) => _ClaudeLoginDialog(
              attempt: attempt,
              startLogin: widget.accountService.startLogin,
            ),
      );
      if (connected == true && mounted) {
        // Drop any pre-OAuth pasted access token for this connection.
        try {
          final store = widget.credentialStore;
          if (store is LegacyProviderCredentialCleanup) {
            await (store as LegacyProviderCredentialCleanup).deleteLegacySecret(
              ProviderConnections.claudePlan,
            );
          } else {
            await store.deleteSecret(ProviderConnections.claudePlan);
          }
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
    final controls = widget.buildControls(
      status: switch ((_hasAccount, _isConnecting)) {
        (_, true) || (null, _) => const RowProgress(),
        (true, _) => const Text('Connected'),
        (false, _) => const Text('Not connected'),
      },
    );
    return ProviderConnectionRow(
      icon: Icons.account_circle_outlined,
      title: widget.connection.listTitle,
      subtitle: widget.connection.listSubtitle,
      status: controls.status,
      actions: controls.actions,
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
  const _ClaudeLoginDialog({required this.attempt, required this.startLogin});

  final ClaudeLoginAttempt attempt;

  /// Begins the fresh authorization that replaces a failed attempt.
  final Future<ClaudeLoginAttempt> Function() startLogin;

  @override
  State<_ClaudeLoginDialog> createState() => _ClaudeLoginDialogState();
}

class _ClaudeLoginDialogState extends State<_ClaudeLoginDialog> {
  final _codeController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  late ClaudeLoginAttempt _attempt;
  String? _browserError;
  String? _error;
  bool _submitting = false;

  /// The current attempt has ended without connecting; only Restart continues.
  bool _failed = false;
  bool _restarting = false;
  bool _completed = false;

  @override
  void initState() {
    super.initState();
    _attempt = widget.attempt;
  }

  @override
  void dispose() {
    _codeController.dispose();
    if (!_completed) {
      _attempt.cancel();
    }
    super.dispose();
  }

  Future<void> _openBrowser() async {
    final attempt = _attempt;
    if (_browserError != null) {
      setState(() {
        _browserError = null;
      });
    }
    try {
      final opened = await launchUrl(
        attempt.authorization.authorizationUri,
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
    // A failed, restarting or replaced attempt no longer owns the feedback.
    if (mounted && identical(attempt, _attempt) && !_failed && !_restarting) {
      setState(() {
        _browserError = 'Could not open the browser';
      });
    }
  }

  Future<void> _submit() async {
    if (_submitting ||
        _failed ||
        !(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await _attempt.completeWithCode(_codeController.text);
      _completed = true;
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } on ClaudeAccountException catch (error) {
      _fail(error.details ?? 'Claude sign-in failed');
    } catch (_) {
      _fail('Claude sign-in failed');
    }
  }

  /// Replaces the spent attempt; its authorization code is never reused.
  Future<void> _restart() async {
    if (_restarting) {
      return;
    }
    setState(() {
      _restarting = true;
      _error = null;
      _browserError = null;
    });
    try {
      final attempt = await widget.startLogin();
      if (!mounted) {
        attempt.cancel();
        return;
      }
      _codeController.clear();
      setState(() {
        _attempt = attempt;
        _failed = false;
        _restarting = false;
      });
    } on ClaudeAccountException catch (error) {
      _fail(error.details ?? 'Could not start Claude sign-in');
    } catch (_) {
      _fail('Could not start Claude sign-in');
    }
  }

  void _fail(String message) {
    if (mounted) {
      setState(() {
        _error = message;
        _failed = true;
        _submitting = false;
        _restarting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Connect Claude plan'),
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
              enabled: !_submitting && !_failed,
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
            if (_submitting || _restarting) const LinearProgressIndicator(),
            if (_error != null)
              Text(
                _error!,
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
        if (_failed)
          FilledButton(
            onPressed: _restarting ? null : _restart,
            child: const Text('Restart sign-in'),
          )
        else ...[
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
      ],
    );
  }
}
