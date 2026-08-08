import 'package:flutter/material.dart';

import '../settings/alert_threshold_preferences.dart';
import 'alert_threshold_dialogs.dart';
import 'claude_account_row.dart';
import 'claude_account_service.dart';
import 'codex_account_row.dart';
import 'codex_account_service.dart';
import 'credential_dialog.dart';
import 'cursor_plan_row.dart';
import 'provider_connection.dart';
import 'provider_connection_row.dart';
import 'provider_credential_store.dart';

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

  /// Connections authorized by a pasted secret, in catalog order.
  static final _secretConnections = providerConnectionCatalog()
      .where((connection) => connection.secretHint != null)
      .map((connection) => connection.id)
      .toList(growable: false);

  @override
  void initState() {
    super.initState();
    _loadCredentialState();
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
            kind: connection.id.kind,
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

  Future<void> _editConnectionBudget(ProviderConnection connection) async {
    final saved = await showDialog<ConnectionBudget>(
      context: context,
      builder:
          (context) => ConnectionBudgetDialog(
            connectionTitle: connection.listTitle,
            budget: widget.alertThresholds.forConnection(connection.id).budget,
          ),
    );
    if (saved == null || !mounted) {
      return;
    }
    await _saveAlertThresholds(
      (current) => current.withConnection(
        connection.id,
        current.forConnection(connection.id).copyWith(budget: saved),
      ),
    );
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

  /// Binds [_statusTrailing] to one connection so extracted rows can reuse it.
  ConnectionTrailingBuilder _trailingBuilderFor(ProviderConnection connection) {
    return ({List<Widget> leading = const [], required Widget status}) =>
        _statusTrailing(
          connection: connection,
          leading: leading,
          status: status,
        );
  }

  Widget _statusTrailing({
    required ProviderConnection connection,
    required Widget status,
    List<Widget> leading = const [],
  }) {
    final settings = widget.alertThresholds.forConnection(connection.id);
    // Only a connection that reports spend can be held to a limit.
    final offersBudget = connection.id.kind == ConnectionKind.platform;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ...leading,
        if (offersBudget)
          IconButton(
            tooltip: 'Budget limits',
            onPressed: () => _editConnectionBudget(connection),
            icon: Icon(
              settings.budget.isEmpty ? Icons.savings_outlined : Icons.savings,
            ),
          ),
        IconButton(
          tooltip: 'Alert thresholds',
          onPressed: () => _editConnectionAlerts(connection),
          icon: Icon(
            settings.hasAlertRules
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
      return CodexAccountRow(
        connection: connection,
        accountService: widget.codexAccountService,
        onCredentialsChanged: widget.onCredentialsChanged,
        buildTrailing: _trailingBuilderFor(connection),
      );
    }
    if (connection.id == ProviderConnections.claudePlan) {
      return ClaudeAccountRow(
        connection: connection,
        accountService: widget.claudeAccountService,
        credentialStore: widget.credentialStore,
        onCredentialsChanged: widget.onCredentialsChanged,
        onPastedSecretCleared:
            () => setState(() {
              _hasSecret[ProviderConnections.claudePlan.storageKey] = false;
            }),
        buildTrailing: _trailingBuilderFor(connection),
      );
    }
    if (connection.id == ProviderConnections.cursorPlan) {
      return CursorPlanRow(
        connection: connection,
        credentialStore: widget.credentialStore,
        onCredentialsChanged: widget.onCredentialsChanged,
        signIn: widget.cursorPlanSignIn,
        buildTrailing: _trailingBuilderFor(connection),
      );
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
          null => const RowProgress(),
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

/// Compact preview of what the next watch payload would carry as rings.
