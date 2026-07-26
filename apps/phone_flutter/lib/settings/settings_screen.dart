import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../dashboard/dashboard_models.dart';
import '../dashboard/dashboard_screen.dart';
import '../providers/codex_account_service.dart';
import '../providers/provider_connection.dart';
import '../providers/provider_connection_row.dart';
import '../providers/provider_credential_store.dart';
import '../sync/codex_account_client.dart';
import '../sync/poll_cadence.dart';
import '../sync/watch_sync_service.dart';
import 'consumption_display_preferences.dart';
import 'refresh_interval_preferences.dart';
import 'watch_ring_preferences.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    required this.snapshot,
    required this.watchSyncService,
    required this.credentialStore,
    required this.codexAccountService,
    required this.displayPreferences,
    required this.onDisplayPreferencesChanged,
    required this.refreshInterval,
    required this.onRefreshIntervalChanged,
    required this.ringPreferences,
    required this.onRingPreferencesChanged,
    required this.debugDataAvailable,
    required this.mockDataEnabled,
    required this.onMockDataEnabledChanged,
    required this.onCredentialsChanged,
  });

  final DashboardSnapshot? snapshot;
  final WatchSyncService watchSyncService;
  final ProviderCredentialStore credentialStore;
  final CodexAccountService codexAccountService;
  final ConsumptionDisplayPreferences displayPreferences;
  final Future<void> Function(ConsumptionDisplayPreferences value)
  onDisplayPreferencesChanged;
  final RefreshIntervalPreference refreshInterval;
  final Future<void> Function(RefreshIntervalPreference value)
  onRefreshIntervalChanged;
  final WatchRingPreferences ringPreferences;
  final Future<void> Function(WatchRingPreferences value)
  onRingPreferencesChanged;
  final bool debugDataAvailable;
  final bool mockDataEnabled;
  final Future<void> Function(bool value) onMockDataEnabledChanged;
  final VoidCallback onCredentialsChanged;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final Map<String, bool> _hasSecret = {};
  final Map<String, String?> _labels = {};
  bool? _hasCodexAccount;
  bool _isConnectingCodex = false;
  bool _isSyncing = false;
  String? _syncResult;
  double? _dragRefreshMinutes;

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
    final change = await showDialog<_CredentialChange>(
      context: context,
      builder:
          (context) => _CredentialDialog(
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
      await widget.watchSyncService.sync(
        snapshot,
        widget.displayPreferences,
        widget.ringPreferences,
      );
      if (mounted) {
        setState(() {
          _syncResult = 'Watch summary queued';
        });
      }
    } on PlatformException catch (error) {
      if (mounted) {
        setState(() {
          _syncResult =
              error.message?.trim().isNotEmpty == true
                  ? error.message!
                  : 'Watch sync unavailable';
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
    if (!value.hasVisibleSurface) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Keep at least one dashboard surface visible'),
        ),
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

  Future<void> _setMockDataEnabled(bool value) async {
    try {
      await widget.onMockDataEnabledChanged(value);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not update mock data setting')),
        );
      }
    }
  }

  Future<void> _setRefreshInterval(double minutes) async {
    final preference = RefreshIntervalPreference(minutes: minutes.round());
    try {
      await widget.onRefreshIntervalChanged(preference);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not update refresh interval')),
        );
      }
    }
  }

  Future<void> _toggleRing(WatchRingMetric metric, bool selected) async {
    if (!metric.isAvailable) {
      return;
    }
    final snapshot = widget.snapshot;
    final ids = [
      if (snapshot != null)
        for (final ring in resolveWatchRings(snapshot, widget.ringPreferences))
          ring.id
      else
        ...widget.ringPreferences.clampedIds,
    ];
    if (selected) {
      if (ids.contains(metric.id) || ids.length >= watchRingSlotCount) {
        return;
      }
      ids.add(metric.id);
    } else {
      ids.remove(metric.id);
    }
    try {
      await widget.onRingPreferencesChanged(
        WatchRingPreferences(selectedIds: ids),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not update watch display')),
        );
      }
    }
  }

  List<String> get _effectiveRingIds {
    final snapshot = widget.snapshot;
    if (snapshot == null) {
      return widget.ringPreferences.clampedIds;
    }
    return [
      for (final ring in resolveWatchRings(snapshot, widget.ringPreferences))
        ring.id,
    ];
  }

  Widget _connectionRow(ProviderConnection connection) {
    final hint = connection.secretHint;
    if (hint == null) {
      return _codexAccountRow(connection);
    }

    final hasSecret = _hasSecret[connection.id.storageKey];
    return ProviderConnectionRow(
      icon:
          connection.id.kind == ConnectionKind.plan
              ? Icons.account_circle_outlined
              : Icons.key_outlined,
      title: connection.listTitle,
      subtitle: connection.listSubtitle,
      trailing: switch (hasSecret) {
        null => const _RowProgress(),
        // Match Codex OAuth row copy: connection state, not "field empty/filled".
        true => const Text('Connected'),
        false => const Text('Not connected'),
      },
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
      trailing: switch ((_hasCodexAccount, _isConnectingCodex)) {
        (_, true) || (null, _) => const _RowProgress(),
        (true, _) => const Text('Connected'),
        (false, _) => const Text('Not connected'),
      },
      onTap:
          _hasCodexAccount == null || _isConnectingCodex
              ? null
              : _editCodexAccount,
    );
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = widget.snapshot;
    final catalog = providerConnectionCatalog(platformLabels: _labels);
    final shownRefreshMinutes =
        _dragRefreshMinutes?.round() ?? widget.refreshInterval.minutes;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        Card(
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
                subtitle: const Text(
                  'Purchased tokens or credits, when the provider reports them',
                ),
                value: widget.displayPreferences.purchased,
                onChanged:
                    (value) => _setDisplayPreferences(
                      widget.displayPreferences.copyWith(purchased: value),
                    ),
              ),
              const Divider(height: 1),
              SwitchListTile(
                secondary: const Icon(Icons.payments_outlined),
                title: const Text('Platform spend'),
                subtitle: const Text(
                  'Monetary budgets for today, week, and month when reported',
                ),
                value: widget.displayPreferences.platform,
                onChanged:
                    (value) => _setDisplayPreferences(
                      widget.displayPreferences.copyWith(platform: value),
                    ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.schedule_outlined),
                  title: const Text('Refresh interval'),
                  subtitle: Text(
                    'Every $shownRefreshMinutes minutes · some providers '
                    'publish new data less often',
                  ),
                ),
                Slider(
                  min: PollCadence.minRefreshMinutes.toDouble(),
                  max: PollCadence.maxRefreshMinutes.toDouble(),
                  divisions:
                      PollCadence.maxRefreshMinutes -
                      PollCadence.minRefreshMinutes,
                  label: '$shownRefreshMinutes min',
                  semanticFormatterCallback:
                      (value) => '${value.round()} minutes',
                  value: shownRefreshMinutes.toDouble(),
                  onChanged: (value) {
                    setState(() {
                      _dragRefreshMinutes = value;
                    });
                  },
                  onChangeEnd: (value) async {
                    await _setRefreshInterval(value);
                    // Keep a newer drag in place if one started while saving.
                    if (mounted && _dragRefreshMinutes == value) {
                      setState(() {
                        _dragRefreshMinutes = null;
                      });
                    }
                  },
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const ListTile(
                leading: Icon(Icons.watch_outlined),
                title: Text('Watch display'),
                subtitle: Text(
                  'Pick up to $watchRingSlotCount metrics for the watch at '
                  'once · unavailable ones stay off the watch',
                ),
              ),
              for (final metric in watchRingCatalog(widget.snapshot)) ...[
                const Divider(height: 1),
                _WatchRingTile(
                  metric: metric,
                  selected: _effectiveRingIds.contains(metric.id),
                  atCapacity: _effectiveRingIds.length >= watchRingSlotCount,
                  onChanged: (value) => _toggleRing(metric, value),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),
        if (widget.debugDataAvailable) ...[
          Card(
            child: SwitchListTile(
              secondary: const Icon(Icons.science_outlined),
              title: const Text('Mock data'),
              subtitle: const Text('Debug builds only'),
              value: widget.mockDataEnabled,
              onChanged: _setMockDataEnabled,
            ),
          ),
          const SizedBox(height: 16),
        ],
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
        if (snapshot != null)
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.sync_outlined),
                  title: const Text('Sync'),
                  subtitle: Tooltip(
                    message: formatUtc(snapshot.generatedAt),
                    child: Text(formatLocal(snapshot.generatedAt)),
                  ),
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
                    _watchSummarySubtitle(snapshot, widget.ringPreferences),
                  ),
                  trailing: StatusPill(
                    status: snapshot.watchSummary.status,
                    tooltip: snapshot.syncTooltip,
                  ),
                ),
                if (kDebugMode) ...[
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

class _WatchRingTile extends StatelessWidget {
  const _WatchRingTile({
    required this.metric,
    required this.selected,
    required this.atCapacity,
    required this.onChanged,
  });

  final WatchRingMetric metric;
  final bool selected;
  final bool atCapacity;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final canToggle = metric.isAvailable && (selected || !atCapacity);
    final reason = metric.unavailableReason;
    return CheckboxListTile(
      secondary:
          reason == null
              ? const Icon(Icons.data_usage_outlined)
              : Tooltip(message: reason, child: const Icon(Icons.help_outline)),
      title: Text(metric.label),
      subtitle: Text(
        reason ??
            '${metric.remainingPercent!.round()}% left · ${metric.status.label}',
      ),
      value: selected,
      onChanged: canToggle ? (value) => onChanged(value ?? false) : null,
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
          onPressed: _openBrowser,
          icon: const Icon(Icons.open_in_browser),
          label: const Text('Open browser'),
        ),
      ],
    );
  }
}

class _CredentialDialog extends StatefulWidget {
  const _CredentialDialog({
    required this.hasCredential,
    required this.title,
    required this.hint,
    required this.allowLabel,
    this.initialLabel,
  });

  final bool hasCredential;
  final String title;
  final String hint;
  final bool allowLabel;
  final String? initialLabel;

  @override
  State<_CredentialDialog> createState() => _CredentialDialogState();
}

class _CredentialDialogState extends State<_CredentialDialog> {
  final _formKey = GlobalKey<FormState>();
  final _controller = TextEditingController();
  late final TextEditingController _labelController;
  bool _obscureKey = true;

  @override
  void initState() {
    super.initState();
    _labelController = TextEditingController(text: widget.initialLabel ?? '');
  }

  @override
  void dispose() {
    _controller.dispose();
    _labelController.dispose();
    super.dispose();
  }

  void _save() {
    final key = _controller.text.trim();
    final label = _labelController.text.trim();
    final resolvedLabel = label.isEmpty ? null : label;
    if (key.isEmpty) {
      if (!widget.hasCredential) {
        _formKey.currentState?.validate();
        return;
      }
      if (widget.allowLabel) {
        Navigator.of(context).pop(_CredentialChange.labelOnly(resolvedLabel));
      } else {
        // Leave blank to keep the stored token; dismiss without a mutation.
        Navigator.of(context).pop();
      }
      return;
    }
    if (_formKey.currentState?.validate() ?? false) {
      Navigator.of(context).pop(
        _CredentialChange.save(
          key,
          label: widget.allowLabel ? resolvedLabel : null,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.allowLabel
                  ? 'This key is encrypted on this phone and sent only to the provider.'
                  : 'This token is encrypted on this phone. Experimental compatibility connection.',
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
                labelText:
                    widget.hasCredential
                        ? 'Value (leave blank to keep)'
                        : 'Value',
                hintText: widget.hint,
                suffixIcon: IconButton(
                  tooltip: _obscureKey ? 'Show value' : 'Hide value',
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
              textInputAction:
                  widget.allowLabel
                      ? TextInputAction.next
                      : TextInputAction.done,
              onFieldSubmitted: widget.allowLabel ? null : (_) => _save(),
              validator: (value) {
                if (widget.hasCredential) {
                  return null;
                }
                return value == null || value.trim().isEmpty
                    ? 'Enter a value'
                    : null;
              },
            ),
            if (widget.allowLabel) ...[
              const SizedBox(height: 12),
              TextFormField(
                controller: _labelController,
                autocorrect: false,
                enableSuggestions: false,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: 'Label (optional)',
                  hintText: 'Work org key',
                ),
                textInputAction: TextInputAction.done,
                onFieldSubmitted: (_) => _save(),
              ),
            ],
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

/// Compact preview of what the next watch payload would carry as rings.
String _watchSummarySubtitle(
  DashboardSnapshot snapshot,
  WatchRingPreferences ringPreferences,
) {
  final rings = orderWatchRingsForSurface(
    resolveWatchRings(snapshot, ringPreferences),
  );
  if (rings.isEmpty) {
    return 'No rings selected';
  }
  if (rings.length == 1) {
    final ring = rings.single;
    return '${ring.label} ${ring.remainingPercent!.round()}% left';
  }
  return '${rings.length} rings · ${rings.map((ring) => ring.label).join(', ')}';
}

final class _CredentialChange {
  const _CredentialChange.save(this.value, {this.label})
    : remove = false,
      updateLabelOnly = false;

  const _CredentialChange.labelOnly(this.label)
    : value = null,
      remove = false,
      updateLabelOnly = true;

  const _CredentialChange.remove()
    : value = null,
      label = null,
      remove = true,
      updateLabelOnly = false;

  final String? value;
  final String? label;
  final bool remove;
  final bool updateLabelOnly;
}

enum _CodexAccountAction { reconnect, disconnect }
