import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../settings/alert_threshold_preferences.dart';
import '../sync/claude_account_client.dart';
import '../sync/codex_account_client.dart';
import 'alert_threshold_dialogs.dart';
import 'claude_account_service.dart';
import 'codex_account_service.dart';
import 'connected_account_dialog.dart';
import 'credential_dialog.dart';
import 'cursor_plan_sign_in_screen.dart';
import 'cursor_session_token.dart';
import 'cursor_webview_cookies.dart';
import 'provider_connection.dart';
import 'provider_connection_row.dart';
import 'provider_credential_store.dart';

/// Opens Cursor dashboard sign-in and returns a session token, or null.
typedef CursorPlanSignIn = Future<String?> Function(BuildContext context);

/// Connection hub: plan/platform catalog, credentials, and auth flows.
class ProvidersScreen extends StatefulWidget {
  const ProvidersScreen({
    super.key,
    required this.credentialStore,
    required this.codexAccountService,
    required this.claudeAccountService,
    required this.onCredentialsChanged,
    required this.alertThresholds,
    required this.onAlertThresholdsChanged,
    this.cursorPlanSignIn,
  });

  final ProviderCredentialStore credentialStore;
  final CodexAccountService codexAccountService;
  final ClaudeAccountService claudeAccountService;
  final VoidCallback onCredentialsChanged;
  final AlertThresholdPreferences alertThresholds;
  final Future<void> Function(
    AlertThresholdPreferences Function(AlertThresholdPreferences current)
    update,
  )
  onAlertThresholdsChanged;

  /// Test seam; defaults to [CursorPlanSignInScreen.open].
  final CursorPlanSignIn? cursorPlanSignIn;

  @override
  State<ProvidersScreen> createState() => _ProvidersScreenState();
}

class _ProvidersScreenState extends State<ProvidersScreen> {
  final Map<String, bool> _hasSecret = {};
  final Map<String, String?> _labels = {};
  bool? _hasCodexAccount;
  bool? _hasClaudeAccount;
  bool? _hasCursorPlan;
  bool _isConnectingCodex = false;
  bool _isConnectingClaude = false;
  bool _isConnectingCursorPlan = false;

  /// Connections authorized by a pasted secret, in catalog order.
  static final _secretConnections = providerConnectionCatalog()
      .where((connection) => connection.secretHint != null)
      .map((connection) => connection.id)
      .toList(growable: false);

  @override
  void initState() {
    super.initState();
    _loadCredentialState();
    _loadCodexAccountState();
    _loadClaudeAccountState();
    _loadCursorPlanState();
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

  Future<void> _loadClaudeAccountState() async {
    try {
      final value = await widget.claudeAccountService.isConnected();
      if (mounted) {
        setState(() {
          _hasClaudeAccount = value;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _hasClaudeAccount = false;
        });
      }
    }
  }

  Future<void> _loadCursorPlanState() async {
    try {
      final value =
          await widget.credentialStore.readSecret(
            ProviderConnections.cursorPlan,
          ) !=
          null;
      if (mounted) {
        setState(() {
          _hasCursorPlan = value;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _hasCursorPlan = false;
        });
      }
    }
  }

  Future<void> _loadCredentialState() async {
    try {
      final secrets = <String, bool>{};
      final labels = <String, String?>{};
      for (final id in _secretConnections) {
        secrets[id.storageKey] =
            await widget.credentialStore.readSecret(id) != null;
        labels[id.storageKey] = await widget.credentialStore.readLabel(id);
      }
      if (mounted) {
        setState(() {
          _hasSecret
            ..clear()
            ..addAll(secrets);
          _labels
            ..clear()
            ..addAll(labels);
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          for (final id in _secretConnections) {
            _hasSecret[id.storageKey] = false;
            _labels[id.storageKey] = null;
          }
        });
      }
    }
  }

  Future<void> _editSecret(
    ProviderConnectionId id, {
    required bool allowLabel,
    required String title,
    required String hint,
  }) async {
    final key = id.storageKey;
    final change = await showDialog<CredentialChange>(
      context: context,
      builder:
          (context) => CredentialDialog(
            title: title,
            hint: hint,
            allowLabel: allowLabel,
            hasCredential: _hasSecret[key] ?? false,
            initialLabel: _labels[key],
          ),
    );
    if (change == null) {
      return;
    }

    try {
      if (change.remove) {
        await widget.credentialStore.deleteSecret(id);
      } else if (change.updateLabelOnly) {
        await widget.credentialStore.writeLabel(id, change.label);
      } else {
        await widget.credentialStore.writeSecret(id, change.value!);
        if (allowLabel) {
          await widget.credentialStore.writeLabel(id, change.label);
        }
      }
      if (!mounted) {
        return;
      }
      setState(() {
        _hasSecret[key] = !change.remove;
        _labels[key] = change.remove ? null : change.label;
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
      if (action != AccountAction.reconnect) {
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

  Future<void> _editClaudeAccount() async {
    if (_hasClaudeAccount == true) {
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
          await widget.claudeAccountService.disconnect();
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
            _hasClaudeAccount = false;
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
      _isConnectingClaude = true;
    });
    try {
      final attempt = await widget.claudeAccountService.startLogin();
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
          _hasClaudeAccount = true;
          _hasSecret[ProviderConnections.claudePlan.storageKey] = false;
        });
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
          _isConnectingClaude = false;
        });
      }
    }
  }

  Future<void> _editCursorPlanAccount() async {
    if (_hasCursorPlan == true) {
      final action = await showDialog<AccountAction>(
        context: context,
        builder:
            (context) => const ConnectedAccountDialog(
              title: 'Cursor plan',
              message:
                  'WardPulse reads personal plan usage from the Cursor '
                  'dashboard session stored on this phone.',
              confirmLabel: 'Sign in again',
            ),
      );
      if (action == AccountAction.disconnect) {
        try {
          await widget.credentialStore.deleteSecret(
            ProviderConnections.cursorPlan,
          );
          final wiped = await wipeCursorWebViewSession();
          if (!wiped && mounted) {
            _showMessage(
              'Disconnected, but could not clear the in-app Cursor session',
            );
          }
        } catch (_) {
          if (mounted) {
            _showMessage('Could not disconnect Cursor plan');
          }
          return;
        }
        if (mounted) {
          setState(() {
            _hasCursorPlan = false;
          });
          widget.onCredentialsChanged();
        }
        return;
      }
      if (action != AccountAction.reconnect) {
        return;
      }
    }

    await _runCursorPlanSignIn();
  }

  Future<void> _runCursorPlanSignIn() async {
    setState(() {
      _isConnectingCursorPlan = true;
    });
    try {
      final signIn = widget.cursorPlanSignIn ?? CursorPlanSignInScreen.open;
      final token = await signIn(context);
      if (!mounted) {
        return;
      }
      final normalized =
          token == null ? null : normalizeCursorSessionToken(token);
      if (normalized == null) {
        return;
      }
      await widget.credentialStore.writeSecret(
        ProviderConnections.cursorPlan,
        normalized,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _hasCursorPlan = true;
      });
      widget.onCredentialsChanged();
    } catch (_) {
      if (mounted) {
        _showMessage('Could not complete Cursor sign-in');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isConnectingCursorPlan = false;
        });
      }
    }
  }

  Future<void> _showCursorPlanHelp() async {
    final paste = await showDialog<bool>(
      context: context,
      builder: (context) => const _CursorPlanHelpDialog(),
    );
    if (paste == true && mounted) {
      await _pasteCursorPlanToken();
    }
  }

  Future<void> _pasteCursorPlanToken() async {
    const id = ProviderConnections.cursorPlan;
    final change = await showDialog<CredentialChange>(
      context: context,
      builder:
          (context) => CredentialDialog(
            title: 'Cursor plan · Paste token',
            hint: cursorSessionCookieName,
            allowLabel: false,
            hasCredential: _hasCursorPlan ?? false,
          ),
    );
    if (change == null) {
      return;
    }
    try {
      if (change.remove) {
        await widget.credentialStore.deleteSecret(id);
        final wiped = await wipeCursorWebViewSession();
        if (!wiped && mounted) {
          _showMessage(
            'Removed, but could not clear the in-app Cursor session',
          );
        }
      } else if (change.value != null) {
        final token = normalizeCursorSessionToken(change.value!);
        if (token == null) {
          if (mounted) {
            _showMessage('That does not look like a Cursor session token');
          }
          return;
        }
        await widget.credentialStore.writeSecret(id, token);
      } else {
        return;
      }
      if (!mounted) {
        return;
      }
      setState(() {
        _hasCursorPlan = !change.remove;
      });
      widget.onCredentialsChanged();
    } catch (_) {
      if (mounted) {
        _showMessage('Could not update Cursor plan token');
      }
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _editConnectionAlerts(ProviderConnection connection) async {
    final saved = await showDialog<ConnectionAlertThresholds>(
      context: context,
      builder:
          (context) => ConnectionAlertsDialog(
            connectionTitle: connection.listTitle,
            thresholds: widget.alertThresholds.forConnection(connection.id),
          ),
    );
    if (saved == null || !mounted) {
      return;
    }
    await _saveAlertThresholds(
      (current) => current.withConnection(connection.id, saved),
    );
  }

  Future<void> _editPlatformBudgetAlerts() async {
    final saved = await showDialog<AlertThresholdPreferences>(
      context: context,
      builder:
          (context) =>
              PlatformBudgetAlertsDialog(thresholds: widget.alertThresholds),
    );
    if (saved == null || !mounted) {
      return;
    }
    // The dialog edits a copy of the whole preferences, so connection rules
    // ride along untouched and `current` would add nothing.
    await _saveAlertThresholds((_) => saved);
  }

  Future<void> _saveAlertThresholds(
    AlertThresholdPreferences Function(AlertThresholdPreferences current) edit,
  ) async {
    try {
      await widget.onAlertThresholdsChanged(edit);
    } catch (_) {
      if (mounted) {
        _showMessage('Could not update alert thresholds');
      }
    }
  }

  Widget _statusTrailing({
    required ProviderConnection connection,
    required Widget status,
    List<Widget> leading = const [],
  }) {
    final isPlan = connection.id.kind == ConnectionKind.plan;
    final isOpenAiPlatform =
        connection.id == ProviderConnections.openAiPlatform;
    final alertsEnabled =
        isPlan
            ? widget.alertThresholds.forConnection(connection.id).isEnabled
            : isOpenAiPlatform
            ? widget.alertThresholds.hasEnabledBudgetRules
            : false;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ...leading,
        if (isPlan || isOpenAiPlatform)
          IconButton(
            tooltip: 'Alert thresholds',
            onPressed:
                isOpenAiPlatform
                    ? _editPlatformBudgetAlerts
                    : () => _editConnectionAlerts(connection),
            icon: Icon(
              alertsEnabled
                  ? Icons.notifications_active_outlined
                  : Icons.notifications_none_outlined,
            ),
          ),
        status,
      ],
    );
  }

  Widget _connectionRow(ProviderConnection connection) {
    if (connection.id == ProviderConnections.codexPlan) {
      return _codexAccountRow(connection);
    }
    if (connection.id == ProviderConnections.claudePlan) {
      return _claudeAccountRow(connection);
    }
    if (connection.id == ProviderConnections.cursorPlan) {
      return _cursorPlanRow(connection);
    }

    final hint = connection.secretHint;
    if (hint == null) {
      return const SizedBox.shrink();
    }

    final hasSecret = _hasSecret[connection.id.storageKey];
    return ProviderConnectionRow(
      icon:
          connection.id.kind == ConnectionKind.plan
              ? Icons.account_circle_outlined
              : Icons.key_outlined,
      title: connection.listTitle,
      subtitle: connection.listSubtitle,
      trailing: _statusTrailing(
        connection: connection,
        status: switch (hasSecret) {
          null => const _RowProgress(),
          // Match OAuth row copy: connection state, not "field empty/filled".
          true => const Text('Connected'),
          false => const Text('Not connected'),
        },
      ),
      onTap:
          hasSecret == null
              ? null
              : () => _editSecret(
                connection.id,
                allowLabel: connection.id.kind == ConnectionKind.platform,
                title:
                    '${providerFamilyLabel(connection.id.provider)} · '
                    '${connection.title}',
                hint: hint,
              ),
    );
  }

  Widget _codexAccountRow(ProviderConnection connection) {
    return ProviderConnectionRow(
      icon: Icons.account_circle_outlined,
      title: connection.listTitle,
      subtitle: connection.listSubtitle,
      trailing: _statusTrailing(
        connection: connection,
        status: switch ((_hasCodexAccount, _isConnectingCodex)) {
          (_, true) || (null, _) => const _RowProgress(),
          (true, _) => const Text('Connected'),
          (false, _) => const Text('Not connected'),
        },
      ),
      onTap:
          _hasCodexAccount == null || _isConnectingCodex
              ? null
              : _editCodexAccount,
    );
  }

  Widget _claudeAccountRow(ProviderConnection connection) {
    return ProviderConnectionRow(
      icon: Icons.account_circle_outlined,
      title: connection.listTitle,
      subtitle: connection.listSubtitle,
      trailing: _statusTrailing(
        connection: connection,
        status: switch ((_hasClaudeAccount, _isConnectingClaude)) {
          (_, true) || (null, _) => const _RowProgress(),
          (true, _) => const Text('Connected'),
          (false, _) => const Text('Not connected'),
        },
      ),
      onTap:
          _hasClaudeAccount == null || _isConnectingClaude
              ? null
              : _editClaudeAccount,
    );
  }

  Widget _cursorPlanRow(ProviderConnection connection) {
    final status = switch ((_hasCursorPlan, _isConnectingCursorPlan)) {
      (_, true) || (null, _) => const _RowProgress(),
      (true, _) => const Text('Connected'),
      (false, _) => const Text('Not connected'),
    };
    return ProviderConnectionRow(
      icon: Icons.account_circle_outlined,
      title: connection.listTitle,
      subtitle: connection.listSubtitle,
      trailing: _statusTrailing(
        connection: connection,
        leading: [
          IconButton(
            tooltip: 'About Cursor sign-in',
            onPressed: _isConnectingCursorPlan ? null : _showCursorPlanHelp,
            icon: const Icon(Icons.help_outline),
          ),
        ],
        status: status,
      ),
      onTap:
          _hasCursorPlan == null || _isConnectingCursorPlan
              ? null
              : _editCursorPlanAccount,
    );
  }

  @override
  Widget build(BuildContext context) {
    final catalog = providerConnectionCatalog(platformLabels: _labels);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        for (final provider in ProviderFamily.values) ...[
          Card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _ProviderSectionHeader(title: providerFamilyLabel(provider)),
                for (final connection in catalog.where(
                  (entry) => entry.id.provider == provider,
                )) ...[
                  if (connection.id.kind == ConnectionKind.platform)
                    const Divider(height: 1),
                  _connectionRow(connection),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],
      ],
    );
  }
}

class _RowProgress extends StatelessWidget {
  const _RowProgress();

  @override
  Widget build(BuildContext context) {
    return const SizedBox.square(
      dimension: 20,
      child: CircularProgressIndicator(strokeWidth: 2),
    );
  }
}

class _ProviderSectionHeader extends StatelessWidget {
  const _ProviderSectionHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
      child: Text(title, style: Theme.of(context).textTheme.titleMedium),
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
          onPressed: _openBrowser,
          icon: const Icon(Icons.open_in_browser),
          label: const Text('Open browser'),
        ),
      ],
    );
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

/// Compact preview of what the next watch payload would carry as rings.
class _CursorPlanHelpDialog extends StatelessWidget {
  const _CursorPlanHelpDialog();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Cursor sign-in'),
      content: const SingleChildScrollView(
        child: Text(
          'Tap the Cursor plan row to open Cursor’s dashboard in the app and '
          'sign in with your Cursor account.\n\n'
          'WardPulse keeps the dashboard session on this phone only and uses it '
          'to read plan usage. This is an experimental compatibility login, not '
          'a published Cursor API.\n\n'
          'If you already have a WorkosCursorSessionToken, use Advanced paste.',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Advanced paste'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('OK'),
        ),
      ],
    );
  }
}
