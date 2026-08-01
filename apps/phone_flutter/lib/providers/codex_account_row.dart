import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../sync/codex_account_client.dart';
import 'codex_account_service.dart';
import 'connected_account_dialog.dart';
import 'cursor_plan_row.dart';
import 'provider_connection.dart';
import 'provider_connection_row.dart';

/// Codex subscription row: OAuth sign-in, reconnect, and disconnect.
///
/// Owns its own connected/connecting state so the Providers screen does not.
class CodexAccountRow extends StatefulWidget {
  const CodexAccountRow({
    super.key,
    required this.connection,
    required this.accountService,
    required this.onCredentialsChanged,
    required this.buildTrailing,
  });

  final ProviderConnection connection;
  final CodexAccountService accountService;
  final VoidCallback onCredentialsChanged;
  final ConnectionTrailingBuilder buildTrailing;

  @override
  State<CodexAccountRow> createState() => _CodexAccountRowState();
}

class _CodexAccountRowState extends State<CodexAccountRow> {
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
              title: 'Codex account',
              message:
                  'WardPulse reads subscription limits and token activity '
                  'directly on this phone.',
            ),
      );
      if (action == AccountAction.disconnect) {
        try {
          await widget.accountService.disconnect();
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
        builder: (context) => _CodexLoginDialog(attempt: attempt),
      );
      if (connected == true && mounted) {
        setState(() {
          _hasAccount = true;
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
          onPressed: _openBrowser,
          icon: const Icon(Icons.open_in_browser),
          label: const Text('Open browser'),
        ),
      ],
    );
  }
}
