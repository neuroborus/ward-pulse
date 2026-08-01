import 'package:flutter/material.dart';

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

/// Screen-owned trailing so every catalog row keeps the same chrome.
typedef ConnectionTrailingBuilder =
    Widget Function({required List<Widget> leading, required Widget status});

/// Cursor plan row: WebView sign-in, token paste, and disconnect.
///
/// Owns its own connected/connecting state so the Providers screen does not.
class CursorPlanRow extends StatefulWidget {
  const CursorPlanRow({
    super.key,
    required this.connection,
    required this.credentialStore,
    required this.onCredentialsChanged,
    required this.buildTrailing,
    this.signIn,
  });

  final ProviderConnection connection;
  final ProviderCredentialStore credentialStore;
  final VoidCallback onCredentialsChanged;
  final ConnectionTrailingBuilder buildTrailing;

  /// Test seam; defaults to [CursorPlanSignInScreen.open].
  final CursorPlanSignIn? signIn;

  @override
  State<CursorPlanRow> createState() => _CursorPlanRowState();
}

class _CursorPlanRowState extends State<CursorPlanRow> {
  bool? _hasCursorPlan;
  bool _isConnectingCursorPlan = false;

  @override
  void initState() {
    super.initState();
    _loadCursorPlanState();
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
      final signIn = widget.signIn ?? CursorPlanSignInScreen.open;
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

  @override
  Widget build(BuildContext context) {
    final status = switch ((_hasCursorPlan, _isConnectingCursorPlan)) {
      (_, true) || (null, _) => const RowProgress(),
      (true, _) => const Text('Connected'),
      (false, _) => const Text('Not connected'),
    };
    return ProviderConnectionRow(
      icon: Icons.account_circle_outlined,
      title: widget.connection.listTitle,
      subtitle: widget.connection.listSubtitle,
      trailing: widget.buildTrailing(
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

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}

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
