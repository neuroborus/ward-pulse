import 'package:flutter/material.dart';

import 'connected_account_dialog.dart';
import 'credential_dialog.dart';
import 'cursor_plan_sign_in_screen.dart';
import 'cursor_session_token.dart';
import 'cursor_webview_cookies.dart';
import 'provider_connection.dart';
import 'provider_connection_row.dart';
import 'provider_credential_store.dart';
import 'connection_lifecycle.dart';

/// Opens Cursor dashboard sign-in and returns a session token, or null.
typedef CursorPlanSignIn = Future<String?> Function(BuildContext context);

/// Cursor plan row: WebView sign-in, token paste, and disconnect.
///
/// Owns its own connected/connecting state so the Providers screen does not.
class CursorPlanRow extends StatefulWidget {
  const CursorPlanRow({
    super.key,
    required this.connection,
    required this.credentialStore,
    required this.onCredentialsChanged,
    required this.buildControls,
    this.signIn,
  });

  final ProviderConnection connection;
  final ProviderCredentialStore credentialStore;
  final VoidCallback onCredentialsChanged;
  final ConnectionRowControlsBuilder buildControls;

  /// Test seam; defaults to [CursorPlanSignInScreen.open].
  final CursorPlanSignIn? signIn;

  @override
  State<CursorPlanRow> createState() => _CursorPlanRowState();
}

class _CursorPlanRowState extends State<CursorPlanRow> {
  bool? _hasAccount;
  bool _isConnecting = false;

  @override
  void initState() {
    super.initState();
    _loadState();
  }

  Future<void> _loadState() async {
    try {
      final value =
          await widget.credentialStore.readSecret(
            ProviderConnections.cursorPlan,
          ) !=
          null;
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

    await _runSignIn();
  }

  Future<void> _runSignIn() async {
    setState(() {
      _isConnecting = true;
    });
    final store = widget.credentialStore;
    final managed =
        store is ReconnectProviderCredentialStore
            ? store as ReconnectProviderCredentialStore
            : null;
    CredentialVersion? ticket;
    var saved = false;
    try {
      ticket = await managed?.beginReconnect(ProviderConnections.cursorPlan);
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
      if (managed == null) {
        await store.writeSecret(ProviderConnections.cursorPlan, normalized);
      } else if (!await managed.completeReconnect(
        ProviderConnections.cursorPlan,
        normalized,
        ticket!,
      )) {
        throw StateError('Cursor sign-in superseded.');
      }
      saved = true;
      if (!mounted) {
        return;
      }
      setState(() {
        _hasAccount = true;
      });
      widget.onCredentialsChanged();
    } catch (_) {
      if (mounted) {
        _showMessage('Could not complete Cursor sign-in');
      }
    } finally {
      if (!saved && ticket != null) {
        try {
          await managed!.cancelReconnect(
            ProviderConnections.cursorPlan,
            ticket,
          );
        } catch (_) {
          /* Pending credentials remain unavailable. */
        }
      }
      if (mounted) {
        setState(() {
          _isConnecting = false;
        });
      }
    }
  }

  Future<void> _showHelp() async {
    final paste = await showDialog<bool>(
      context: context,
      builder: (context) => const _CursorPlanHelpDialog(),
    );
    if (paste == true && mounted) {
      await _pasteToken();
    }
  }

  Future<void> _pasteToken() async {
    const id = ProviderConnections.cursorPlan;
    final change = await showDialog<CredentialChange>(
      context: context,
      builder:
          (context) => CredentialDialog(
            title: 'Cursor plan · Paste token',
            hint: cursorSessionCookieName,
            allowLabel: false,
            hasCredential: _hasAccount ?? false,
            autofocus: false,
            guidance:
                'Use a desktop browser to get the session cookie for the Cursor account you want to connect.\n\n'
                '1. In Chrome or Edge, open cursor.com/dashboard and sign in to the same account you use in Cursor.\n'
                '2. Right-click the page and choose Inspect.\n'
                '3. Open Application → Storage → Cookies, then select the Cursor site (https://cursor.com).\n'
                '4. Find WorkosCursorSessionToken. You can enter that name in the Filter box.\n'
                '5. Copy only its Value, not the cookie name or the whole Cookie header.\n'
                '6. Paste the value below and tap Save.\n\n'
                'Can’t find it? Check that you’re signed in, reload the dashboard, and select the Cursor site under Cookies.\n\n'
                'This is a private session credential. WardPulse stores it encrypted on this phone for an experimental connection to read plan usage. Do not share it.\n\n'
                'Prefer signing in here? Tap Cancel, then tap Cursor plan.',
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
        _hasAccount = !change.remove;
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
    final status = switch ((_hasAccount, _isConnecting)) {
      (_, true) || (null, _) => const RowProgress(),
      (true, _) => const Text('Connected'),
      (false, _) => const Text('Not connected'),
    };
    final controls = widget.buildControls(
      leading: [
        IconButton(
          tooltip: 'About Cursor sign-in',
          onPressed: _isConnecting ? null : _showHelp,
          icon: const Icon(Icons.help_outline),
        ),
      ],
      status: status,
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
