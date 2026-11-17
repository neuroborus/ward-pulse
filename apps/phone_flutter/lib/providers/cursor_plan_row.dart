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
    this.onInitialRead,
    this.signIn,
  });

  final ProviderConnection connection;
  final ProviderCredentialStore credentialStore;
  final VoidCallback onCredentialsChanged;
  final ConnectionRowControlsBuilder buildControls;

  /// Registers the initial local read with the containing reveal layout.
  final VoidCallback Function()? onInitialRead;

  /// Test seam; defaults to [CursorPlanSignInScreen.open].
  final CursorPlanSignIn? signIn;

  @override
  State<CursorPlanRow> createState() => _CursorPlanRowState();
}

class _CursorPlanRowState extends State<CursorPlanRow>
    with PlanConnectionState<CursorPlanRow> {
  VoidCallback? _finishInitialRead;

  @override
  void initState() {
    super.initState();
    _finishInitialRead = widget.onInitialRead?.call();
    _loadState();
  }

  @override
  Object ownerOf(CursorPlanRow widget) => widget.credentialStore;

  @override
  Future<bool> readConnected() async =>
      await widget.credentialStore.readSecret(ProviderConnections.cursorPlan) !=
      null;

  @override
  Future<void> observeConnection(CredentialLifecycleObserver observer) async {
    final store = widget.credentialStore;
    final access =
        store is VersionedProviderCredentialStore
            ? (store as VersionedProviderCredentialStore).credentialAccess(
              ProviderConnections.cursorPlan,
            )
            : null;
    if (access != null) {
      await access.observeLifecycle(observer);
    } else {
      observer(await readConnected() ? 'active' : 'deleted', null);
    }
  }

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
    final owner = widget.credentialStore;
    if (hasAccount == true) {
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
        await disconnectConnection(
          owner: owner,
          remove:
              (onRetired) => owner.deleteSecret(
                ProviderConnections.cursorPlan,
                onRetired: onRetired,
              ),
          cleanup: () async {
            try {
              if (await wipeCursorWebViewSession()) return null;
            } catch (_) {
              // Cookie cleanup is separate from saved credential removal.
            }
            return 'Disconnected, but could not clear the in-app Cursor session';
          },
        );
        return;
      }
      if (action != AccountAction.reconnect) {
        return;
      }
    }

    if (!mounted || !identical(owner, widget.credentialStore)) return;
    await _runSignIn();
  }

  Future<void> _runSignIn() async {
    if (connecting) return;
    final revision = beginConnectionOperation();
    setState(() {
      connecting = true;
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
      if (!ownsConnectionOperation(revision, store)) return;
      final signIn = widget.signIn ?? CursorPlanSignInScreen.open;
      final token = await signIn(context);
      if (!ownsConnectionOperation(revision, store)) {
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
      if (!ownsConnectionOperation(revision, store)) {
        return;
      }
      setState(() {
        hasAccount = true;
      });
      widget.onCredentialsChanged();
    } catch (_) {
      if (ownsConnectionOperation(revision, store)) {
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
      if (ownsConnectionOperation(revision, store)) {
        setState(() {
          connecting = false;
          if (hasAccount == null) connectionUnavailable = true;
        });
      }
    }
  }

  Future<void> _showHelp() async {
    if (!mounted || connecting || disconnecting) return;
    final paste = await showDialog<bool>(
      context: context,
      builder: (context) => const _CursorPlanHelpDialog(),
    );
    if (paste == true && mounted) {
      await _pasteToken();
    }
  }

  Future<void> _pasteToken() async {
    if (!mounted || connecting || disconnecting) return;
    const id = ProviderConnections.cursorPlan;
    final store = widget.credentialStore;
    final change = await showDialog<CredentialChange>(
      context: context,
      builder:
          (context) => CredentialDialog(
            title: 'Cursor plan · Paste token',
            hint: cursorSessionCookieName,
            allowLabel: false,
            hasCredential: hasAccount ?? false,
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
    if (change == null ||
        !mounted ||
        connecting ||
        disconnecting ||
        !identical(store, widget.credentialStore)) {
      return;
    }
    final token =
        change.value == null ? null : normalizeCursorSessionToken(change.value!);
    if (!change.remove && token == null) {
      if (change.value != null) {
        _showMessage('That does not look like a Cursor session token');
      }
      return;
    }
    final revision = beginConnectionOperation();
    setState(() => connecting = true);
    try {
      if (change.remove) {
        await store.deleteSecret(id);
        final wiped = await wipeCursorWebViewSession();
        if (!wiped && ownsConnectionOperation(revision, store)) {
          _showMessage(
            'Removed, but could not clear the in-app Cursor session',
          );
        }
      } else {
        await store.writeSecret(id, token!);
      }
      if (!ownsConnectionOperation(revision, store)) {
        return;
      }
      setState(() {
        hasAccount = !change.remove;
      });
      widget.onCredentialsChanged();
    } catch (_) {
      if (ownsConnectionOperation(revision, store)) {
        _showMessage('Could not update Cursor plan token');
      }
    } finally {
      if (ownsConnectionOperation(revision, store)) {
        setState(() {
          connecting = false;
          if (hasAccount == null) connectionUnavailable = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = connectionStatus();
    final controls = widget.buildControls(
      leading: [
        IconButton(
          tooltip: 'About Cursor plan sign-in',
          onPressed: connecting || disconnecting ? null : _showHelp,
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

class _CursorPlanHelpDialog extends StatelessWidget {
  const _CursorPlanHelpDialog();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Cursor plan sign-in'),
      content: const SingleChildScrollView(
        child: Text(
          'Tap the Cursor plan row to open Cursor’s dashboard in the app and '
          'sign in with your Cursor account.\n\n'
          'WardPulse stores the session encrypted on this phone and sends it '
          'only to Cursor to read plan usage. This experimental dashboard '
          'connection may stop working if Cursor changes sign-in or reporting.\n\n'
          'Google authorization requires a supported browser and is blocked '
          'here. Use email for the same account when offered, or Cancel and '
          'reopen. Retry starts a fresh in-app session; cancelling a replacement '
          'keeps the saved connection.\n\n'
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
