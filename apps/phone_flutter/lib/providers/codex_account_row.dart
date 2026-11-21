import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../sync/codex_account_client.dart';
import 'codex_account_service.dart';
import 'connected_account_dialog.dart';
import 'connection_lifecycle.dart';
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
    required this.buildControls,
    this.onInitialRead,
  });

  final ProviderConnection connection;
  final CodexAccountService accountService;
  final VoidCallback onCredentialsChanged;
  final ConnectionRowControlsBuilder buildControls;

  /// Registers the initial local read with the containing reveal layout.
  final VoidCallback Function()? onInitialRead;

  @override
  State<CodexAccountRow> createState() => _CodexAccountRowState();
}

class _CodexAccountRowState extends State<CodexAccountRow>
    with PlanConnectionState<CodexAccountRow> {
  VoidCallback? _finishInitialRead;

  @override
  void initState() {
    super.initState();
    _finishInitialRead = widget.onInitialRead?.call();
    _loadState();
  }

  @override
  Object ownerOf(CodexAccountRow widget) => widget.accountService;

  @override
  Future<bool> readConnected() => widget.accountService.isConnected();

  @override
  Future<void> observeConnection(CredentialLifecycleObserver observer) =>
      widget.accountService.observeLifecycle(observer);

  @override
  void credentialsChanged() => widget.onCredentialsChanged();

  Future<void> _loadState() async {
    try {
      await loadConnectionState();
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
    final owner = widget.accountService;
    if (hasAccount == true) {
      final action = await showDialog<AccountAction>(
        context: context,
        builder:
            (context) => const ConnectedAccountDialog(
              title: 'Codex plan',
              message:
                  'WardPulse reads Codex plan limits and token activity '
                  'directly on this phone.',
            ),
      );
      if (action == AccountAction.disconnect) {
        await disconnectConnection(
          owner: owner,
          remove: (onRetired) => owner.disconnect(onRetired: onRetired),
        );
        return;
      }
      if (action != AccountAction.reconnect) {
        return;
      }
    }

    if (!mounted || !identical(owner, widget.accountService)) return;
    final revision = beginConnectionOperation();
    setState(() {
      connecting = true;
    });
    try {
      final attempt = await owner.startLogin();
      if (!ownsConnectionOperation(revision, owner)) {
        attempt.cancel();
        return;
      }
      final connected = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (context) => _CodexLoginDialog(attempt: attempt),
      );
      if (connected == true && ownsConnectionOperation(revision, owner)) {
        setState(() {
          hasAccount = true;
        });
        widget.onCredentialsChanged();
      }
    } on CodexAccountException catch (error) {
      if (ownsConnectionOperation(revision, owner) &&
          error.failure != CodexAccountFailure.cancelled) {
        _showMessage(error.details ?? 'Could not start Codex sign-in');
      }
    } catch (_) {
      if (ownsConnectionOperation(revision, owner)) {
        _showMessage('Could not start Codex sign-in');
      }
    } finally {
      if (ownsConnectionOperation(revision, owner)) {
        setState(() {
          connecting = false;
          if (hasAccount == null) connectionUnavailable = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final controls = widget.buildControls(status: connectionStatus());
    return ProviderConnectionRow(
      icon: Icons.account_circle_outlined,
      title: widget.connection.listTitle,
      subtitle: widget.connection.listSubtitle,
      status: controls.status,
      actions: controls.actions,
      onTap:
          (hasAccount == null && !connectionUnavailable) ||
                  connecting ||
                  disconnecting
              ? null
              : _editAccount,
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
      title: const Text('Connect Codex plan'),
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
