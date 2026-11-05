import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../app/pull_to_refresh_list.dart';
import '../app/surface_order.dart';
import '../dashboard/dashboard_models.dart';
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
    this.onSaveReportingCredential,
    this.reportingUpdates = const {},
    this.isSnapshotCurrent,
    this.savingConnections = const {},
    this.mockDataEnabled = false,
    this.editConnection,
    this.revealConnection,
    this.onConnectionRevealed,
    this.onEditConnectionOpened,
    this.statuses = const {},
    this.snapshot,
    this.alertContextRevision = 0,
    required this.onRefresh,
  });

  final ProviderCredentialStore credentialStore;
  final Future<void> Function(ProviderConnectionId, CredentialChange)?
  onSaveReportingCredential;
  final Map<ProviderConnectionId, ConnectionReportingUpdate> reportingUpdates;

  /// The repository's complete publication gate, including native atomic proof.
  final Future<bool> Function(DashboardSnapshot)? isSnapshotCurrent;
  final bool mockDataEnabled;
  final Set<ProviderConnectionId> savingConnections;
  final ProviderConnectionId? editConnection;
  final ({ProviderConnectionId connection, int token})? revealConnection;
  final void Function(int token)? onConnectionRevealed;
  final VoidCallback? onEditConnectionOpened;
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

  /// What each family is reporting, worst account first. Only the order reads
  /// it: a tab for managing connections leads with the one asking to be
  /// managed. Empty until a snapshot lands.
  final Map<ProviderFamily, ProviderStatus> statuses;

  /// Usable, owned repository data; family status and watch selection cannot
  /// supply the connection's complete normalized Plan catalogue.
  final DashboardSnapshot? snapshot;
  final int alertContextRevision;

  /// Pull-to-refresh reload, shared with the app-bar action.
  final Future<void> Function() onRefresh;

  @override
  State<ProvidersScreen> createState() => _ProvidersScreenState();
}

class _ProvidersScreenState extends State<ProvidersScreen> {
  final Map<String, bool> _hasSecret = {};
  final _rowKeys = <ProviderConnectionId, GlobalKey>{};
  final _rowFocus = <ProviderConnectionId, FocusNode>{};
  final _initialRowReads = <Object>{};
  ({ProviderConnectionId connection, int token})? _pendingReveal;
  var _revealGeneration = 0;
  var _layoutRevision = 0;
  var _credentialsReady = false;
  var _revealQueued = false;
  int? _runningReveal;
  var _discoveryFromStart = true;

  @override
  void dispose() {
    ++_revealGeneration;
    _pendingReveal = null;
    _initialRowReads.clear();
    for (final node in _rowFocus.values) {
      node.dispose();
    }
    super.dispose();
  }

  void _scheduleReveal() {
    ++_revealGeneration;
    _pendingReveal = widget.revealConnection;
    _discoveryFromStart = true;
    _queueReveal();
  }

  // Rows register only their existing initial local read. Disposal retires the
  // same owner as completion, so a late result cannot wake a newer row instance.
  VoidCallback _registerInitialRowRead() {
    final owner = Object();
    _initialRowReads.add(owner);
    ++_layoutRevision;
    _queueReveal();
    return () {
      if (!mounted || !_initialRowReads.remove(owner)) return;
      ++_layoutRevision;
      _queueReveal();
    };
  }

  void _queueReveal() {
    if (!mounted || _pendingReveal == null || _revealQueued) return;
    _revealQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _revealQueued = false;
      if (mounted) _settleReveal();
    });
    WidgetsBinding.instance.scheduleFrame();
  }

  Future<void> _revealLayout() {
    WidgetsBinding.instance.scheduleFrame();
    return WidgetsBinding.instance.endOfFrame;
  }

  Future<void> _settleReveal() async {
    final request = _pendingReveal;
    final generation = _revealGeneration;
    if (request == null || _runningReveal == generation) return;
    bool owned() =>
        mounted &&
        generation == _revealGeneration &&
        _pendingReveal == request &&
        widget.revealConnection == request;
    _runningReveal = generation;
    final startedRevision = _layoutRevision;
    try {
      // Screen publication can reorder families. Discover in that published
      // order before waiting for row-local reads, never for unbuilt rows.
      if (!_credentialsReady) return;
      var target = _rowKeys[request.connection]?.currentContext;
      while (owned() && target == null) {
        final controller = PrimaryScrollController.maybeOf(context);
        if (controller == null || controller.positions.length != 1) return;
        final position = controller.position;
        final offset =
            _discoveryFromStart
                ? position.minScrollExtent
                : (position.pixels + position.viewportDimension)
                    .clamp(position.minScrollExtent, position.maxScrollExtent)
                    .toDouble();
        if (!_discoveryFromStart && offset <= position.pixels) return;
        _discoveryFromStart = false;
        position.jumpTo(offset);
        await _revealLayout();
        if (!owned() ||
            !_credentialsReady ||
            startedRevision != _layoutRevision)
          return;
        target = _rowKeys[request.connection]?.currentContext;
      }
      if (!owned() || target == null || _initialRowReads.isNotEmpty) return;
      final revision = _layoutRevision;
      bool settled() =>
          owned() &&
          _credentialsReady &&
          revision == _layoutRevision &&
          _initialRowReads.isEmpty &&
          identical(target, _rowKeys[request.connection]?.currentContext);
      await Scrollable.ensureVisible(
        target,
        alignment: 0,
        duration: const Duration(milliseconds: 250),
      );
      await _revealLayout();
      if (!settled()) return;
      final row = target.findRenderObject();
      if (row is! RenderBox || !row.attached) return;
      final abstractViewport = RenderAbstractViewport.of(row);
      if (abstractViewport is! RenderBox) return;
      final viewport = abstractViewport as RenderBox;
      final position = Scrollable.of(target).position;
      Rect bounds() =>
          row.localToGlobal(Offset.zero, ancestor: viewport) & row.size;
      final before = bounds();
      final height = viewport.size.height;
      final oversized = before.height > height;
      final delta =
          oversized || before.top < 0
              ? before.top
              : before.bottom > height
              ? before.bottom - height
              : 0.0;
      if (delta.abs() > 0.5) {
        position.jumpTo(
          (position.pixels + delta)
              .clamp(position.minScrollExtent, position.maxScrollExtent)
              .toDouble(),
        );
      }
      await _revealLayout();
      if (!settled() || !row.attached || !viewport.attached) return;
      final after = bounds();
      if (oversized
          ? after.top.abs() > 0.5
          : after.top < -0.5 || after.bottom > viewport.size.height + 0.5) {
        return;
      }
      _pendingReveal = null;
      _rowFocus[request.connection]?.requestFocus();
      widget.onConnectionRevealed?.call(request.token);
    } finally {
      if (_runningReveal == generation) _runningReveal = null;
      // Only a real read/layout publication resumes unfinished work.
      if (owned() && startedRevision != _layoutRevision) _queueReveal();
    }
  }

  final Map<String, String?> _labels = {};
  final _readFailures = <String>{};
  final _currentUpdates = <ProviderConnectionId, ConnectionReportingUpdate>{};
  var _readRevision = 0;
  ProviderConnectionId? _openingConnection;
  final _saving = <ProviderConnectionId>{};
  ProviderConnectionId? _alertConnection;
  ValueNotifier<List<AllowanceState>>? _alertWindows;

  /// Connections authorized by a pasted secret, in catalog order.
  static final _secretConnections = providerConnectionCatalog()
      .where((connection) => connection.secretHint != null)
      .map((connection) => connection.id)
      .toList(growable: false);

  @override
  void initState() {
    super.initState();
    _loadCredentialState();
    _scheduleReveal();
  }

  @override
  void didUpdateWidget(ProvidersScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_alertConnection case final connection?) {
      final windows = _alertWindows;
      final catalogue = _planWindows(connection);
      // The modal is a separate route; notify after the host's build completes.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && identical(windows, _alertWindows)) {
          windows?.value = catalogue;
        }
      });
    }
    if (!identical(oldWidget.reportingUpdates, widget.reportingUpdates) ||
        oldWidget.credentialStore != widget.credentialStore) {
      _currentUpdates.removeWhere(
        (id, update) => !identical(widget.reportingUpdates[id], update),
      );
      _loadCredentialState();
    }
    if (oldWidget.revealConnection != widget.revealConnection) {
      _scheduleReveal();
    } else if (_pendingReveal != null) {
      _discoveryFromStart = true;
      ++_layoutRevision;
      _queueReveal();
    }
    if (oldWidget.editConnection != widget.editConnection) {
      _openingConnection = null;
      _scheduleEditor();
    }
  }

  Future<void> _loadCredentialState() async {
    final revision = ++_readRevision;
    _credentialsReady = false;
    ++_layoutRevision;
    final secrets = <String, bool>{};
    final labels = <String, String?>{};
    final failures = <String>{};
    final updates = <ProviderConnectionId, ConnectionReportingUpdate>{};
    for (final id in _secretConnections) {
      final store = widget.credentialStore;
      final access =
          store is VersionedProviderCredentialStore
              ? (store as VersionedProviderCredentialStore).credentialAccess(id)
              : null;
      try {
        // Keep only presence and nonsecret proof; never put a saved value in UI state.
        secrets[id.storageKey] =
            access == null
                ? await store.readSecret(id) != null
                : await access.read() != null;
        final update = widget.reportingUpdates[id];
        final version = update?.credentialVersion;
        if (update != null &&
            secrets[id.storageKey]! &&
            version != null &&
            access != null &&
            await access.isCurrent(version)) {
          updates[id] = update;
        }
      } catch (_) {
        failures.add(id.storageKey);
        secrets[id.storageKey] = false;
      }
      try {
        labels[id.storageKey] = await store.readLabel(id);
      } catch (_) {
        labels[id.storageKey] = _labels[id.storageKey];
      }
    }
    Future<bool> current(Iterable<ConnectionReportingUpdate> candidates) async {
      final proof = DashboardSnapshot.empty()
          .withConnectionVersions({
            for (final update in candidates)
              update.connection.storageKey: update.credentialVersion!.values,
          })
          .withReportingOutcomes([
            for (final update in candidates)
              if (update.outcome != null) update.outcome!,
          ]);
      try {
        return await widget.isSnapshotCurrent?.call(proof) == true;
      } catch (_) {
        return false;
      }
    }

    while (updates.isNotEmpty && !await current(updates.values)) {
      final obsolete = <ProviderConnectionId>[];
      for (final entry in updates.entries) {
        if (!await current([entry.value])) obsolete.add(entry.key);
      }
      if (obsolete.isEmpty) {
        // Individual checks cannot replace the complete publication gate.
        if (!await current(updates.values)) updates.clear();
        break;
      }
      for (final id in obsolete) updates.remove(id);
      // Removing a retired connection must preserve current sibling feedback,
      // including progress. Revalidate the retained set after every probe.
    }
    if (!mounted || revision != _readRevision) return;
    setState(() {
      _credentialsReady = true;
      // A newer catalogue publication replaces an unfinished traversal: its
      // target may now be behind the previous offset. Row-local completion
      // alone never restarts the bounded start-to-end search.
      _discoveryFromStart = true;
      ++_layoutRevision;
      _hasSecret
        ..clear()
        ..addAll(secrets);
      _labels
        ..clear()
        ..addAll(labels);
      _readFailures
        ..clear()
        ..addAll(failures);
      _currentUpdates
        ..clear()
        ..addAll(updates);
    });
    _queueReveal();
    _scheduleEditor();
  }

  void _scheduleEditor() {
    final id = widget.editConnection;
    if (id == null ||
        _openingConnection == id ||
        !_hasSecret.containsKey(id.storageKey))
      return;
    _openingConnection = id;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      widget.onEditConnectionOpened?.call();
      final connection = providerConnectionCatalog(
        platformLabels: _labels,
      ).firstWhere((entry) => entry.id == id);
      _editSecret(
        id,
        allowLabel: true,
        title: '${providerFamilyLabel(id.provider)} · ${connection.title}',
        hint: connection.secretHint!,
      );
    });
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
            hasCredential:
                (_hasSecret[key] ?? false) || _readFailures.contains(key),
            initialLabel: _labels[key],
            guidance:
                id == ProviderConnections.anthropicPlatform
                    ? '$anthropicReportingKeyGuidance '
                        'The key is encrypted on this phone and sent only to Anthropic.'
                    : null,
            valueValidator:
                id == ProviderConnections.anthropicPlatform
                    ? validateAnthropicReportingKey
                    : null,
          ),
    );
    if (change == null) {
      return;
    }

    final save = widget.onSaveReportingCredential;
    if (save != null) {
      if (mounted) setState(() => _saving.add(id));
      await save(id, change);
      if (mounted) {
        setState(() => _saving.remove(id));
        await _loadCredentialState();
      }
      return;
    }
    try {
      if (change.remove) {
        await widget.credentialStore.deleteSecret(id);
        widget.onCredentialsChanged();
      } else if (change.updateLabelOnly) {
        await widget.credentialStore.writeLabel(id, change.label);
      } else {
        await widget.credentialStore.writeSecret(id, change.value!);
        widget.onCredentialsChanged();
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
      await _loadCredentialState();
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
    final revision = widget.alertContextRevision;
    final store = widget.credentialStore;
    final snapshot = widget.snapshot;
    final thresholds = widget.alertThresholds.forConnection(connection.id);
    final windows = ValueNotifier(_planWindows(connection.id));
    _alertConnection = connection.id;
    _alertWindows = windows;
    ConnectionAlertThresholds? saved;
    try {
      saved = await showDialog<ConnectionAlertThresholds>(
        context: context,
        builder:
            (context) => ValueListenableBuilder<List<AllowanceState>>(
              valueListenable: windows,
              builder:
                  (_, catalogue, _) => ConnectionAlertsDialog(
                    connectionTitle: connection.sourceTitle,
                    connection: connection.id,
                    thresholds: thresholds,
                    planWindows: catalogue,
                  ),
            ),
      );
    } finally {
      _alertConnection = null;
      _alertWindows = null;
      windows.dispose();
    }
    if (saved == null || !mounted) {
      return;
    }
    final result = saved;
    if (snapshot != null && widget.isSnapshotCurrent != null) {
      try {
        if (!await widget.isSnapshotCurrent!(snapshot)) {
          if (mounted)
            _showMessage('Connection changed. Reopen alert thresholds.');
          return;
        }
      } catch (_) {
        if (mounted) _showMessage('Could not update alert thresholds');
        return;
      }
    }
    if (!mounted) return;
    await _saveAlertThresholds((current) {
      if (!mounted ||
          revision != widget.alertContextRevision ||
          !identical(store, widget.credentialStore)) {
        throw StateError('Connection changed during alert editing');
      }
      return current.withConnection(connection.id, result);
    });
  }

  List<AllowanceState> _planWindows(ProviderConnectionId connection) => [
    for (final account in widget.snapshot?.accounts ?? <ProviderSnapshot>[])
      if (_connectionKey(account) == connection.storageKey)
        for (final allowance in account.allowances)
          if (allowance.source == AllowanceSource.plan) allowance,
  ];

  // Match core alerts::connection_key: fallback only when identity is absent.
  String? _connectionKey(ProviderSnapshot account) =>
      account.connection ??
      switch (account.provider) {
        'codex' => ProviderConnections.codexPlan.storageKey,
        'openai' => ProviderConnections.openAiPlatform.storageKey,
        'claude' => ProviderConnections.claudePlan.storageKey,
        'cursor' => ProviderConnections.cursorPlan.storageKey,
        _ => null,
      };

  Future<void> _editConnectionBudget(ProviderConnection connection) async {
    final saved = await showDialog<ConnectionBudget>(
      context: context,
      builder:
          (context) => ConnectionBudgetDialog(
            connectionTitle: connection.sourceTitle,
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

  /// Binds [_rowControls] to one connection so extracted rows can reuse it.
  ConnectionRowControlsBuilder _controlsBuilderFor(
    ProviderConnection connection,
  ) {
    return ({List<Widget> leading = const [], required Widget status}) =>
        _rowControls(connection: connection, leading: leading, status: status);
  }

  ConnectionRowControls _rowControls({
    required ProviderConnection connection,
    required Widget status,
    List<Widget> leading = const [],
  }) {
    final settings = widget.alertThresholds.forConnection(connection.id);
    // Only a connection that reports spend can be held to a limit.
    final offersBudget = connection.id.kind == ConnectionKind.platform;

    return (
      actions: [
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
      ],
      status: status,
    );
  }

  Widget _connectionRow(ProviderConnection connection) {
    if (connection.id == ProviderConnections.codexPlan) {
      return CodexAccountRow(
        onInitialRead: _registerInitialRowRead,
        connection: connection,
        accountService: widget.codexAccountService,
        onCredentialsChanged: widget.onCredentialsChanged,
        buildControls: _controlsBuilderFor(connection),
      );
    }
    if (connection.id == ProviderConnections.claudePlan) {
      return ClaudeAccountRow(
        onInitialRead: _registerInitialRowRead,
        connection: connection,
        accountService: widget.claudeAccountService,
        credentialStore: widget.credentialStore,
        onCredentialsChanged: widget.onCredentialsChanged,
        onPastedSecretCleared:
            () => setState(() {
              _hasSecret[ProviderConnections.claudePlan.storageKey] = false;
            }),
        buildControls: _controlsBuilderFor(connection),
      );
    }
    if (connection.id == ProviderConnections.cursorPlan) {
      return CursorPlanRow(
        onInitialRead: _registerInitialRowRead,
        connection: connection,
        credentialStore: widget.credentialStore,
        onCredentialsChanged: widget.onCredentialsChanged,
        signIn: widget.cursorPlanSignIn,
        buildControls: _controlsBuilderFor(connection),
      );
    }

    final hint = connection.secretHint;
    if (hint == null) {
      return const SizedBox.shrink();
    }

    final hasSecret = _hasSecret[connection.id.storageKey];
    final update = _currentUpdates[connection.id];
    final outcome = update?.outcome;
    final readFailed = _readFailures.contains(connection.id.storageKey);
    final checking = update?.checking == true;
    final status =
        readFailed
            ? 'Could not read saved key'
            : hasSecret == true && widget.mockDataEnabled
            ? 'Not verified'
            : checking
            ? 'Checking…'
            : hasSecret != true
            ? 'Not connected'
            : outcome != null &&
                outcome.freshness == ReportingOutcomeFreshness.current &&
                (outcome.source == ReportingOutcomeSource.live ||
                    (outcome.connection ==
                            ProviderConnections.anthropicPlatform &&
                        outcome.source == ReportingOutcomeSource.local &&
                        outcome.category ==
                            ReportingOutcomeCategory.authenticationRejected))
            ? outcome.label
            : 'Not verified';
    final supporting =
        readFailed
            ? 'Edit or remove the saved key to try again.'
            : hasSecret == true && widget.mockDataEnabled
            ? 'Key not checked while Mock data is on.'
            : outcome?.failed == true
            ? '${outcome!.connectionLabel}\n${outcome.supportingCopy}'
            : null;
    final controls = _rowControls(
      connection: connection,
      status:
          hasSecret == null
              ? const RowProgress()
              : checking && !widget.mockDataEnabled
              ? const Wrap(
                spacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [RowProgress(), Text('Checking…')],
              )
              : Text(status),
    );
    return ProviderConnectionRow(
      icon:
          connection.id.kind == ConnectionKind.plan
              ? Icons.account_circle_outlined
              : Icons.key_outlined,
      title: connection.listTitle,
      subtitle:
          connection.displayName == null
              ? connection.listSubtitle
              : '${providerFamilyLabel(connection.id.provider)} · ${connection.title}\n${connection.listSubtitle}',
      supportingText: supporting,
      status: controls.status,
      actions: controls.actions,
      onTap:
          hasSecret == null ||
                  checking ||
                  _saving.contains(connection.id) ||
                  widget.savingConnections.contains(connection.id)
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

  /// Families in the order this tab declares: the ones asking for attention
  /// first, the ones with no credential last, ties broken by a stable name.
  ///
  /// Rows inside a card keep their plan-then-platform layout — that pairing is
  /// how the card reads, not an order to sort.
  int _compareFamilies(ProviderFamily left, ProviderFamily right) {
    final connectedCmp = (_isConnected(right) ? 1 : 0).compareTo(
      _isConnected(left) ? 1 : 0,
    );
    if (connectedCmp != 0) {
      return connectedCmp;
    }
    final statusCmp = compareByStatus(_statusOf(left), _statusOf(right));
    if (statusCmp != 0) {
      return statusCmp;
    }
    // The enum name, not the label: renaming OpenAI must not move its card.
    return left.name.compareTo(right.name);
  }

  /// Reporting accounts, or a stored secret no poll has used yet.
  ///
  /// A subscription signed in through its account service never reaches
  /// [_hasSecret] — only pasted secrets do — but it does reach the snapshot,
  /// and a family with accounts in the snapshot is a family that is connected.
  bool _isConnected(ProviderFamily family) {
    return widget.statuses.containsKey(family) ||
        _hasSecret.entries.any(
          (entry) =>
              entry.value &&
              ProviderConnectionId.fromStorageKey(entry.key)?.provider ==
                  family,
        );
  }

  ProviderStatus _statusOf(ProviderFamily family) {
    return widget.statuses[family] ?? ProviderStatus.unknown;
  }

  @override
  Widget build(BuildContext context) {
    final catalog = providerConnectionCatalog(platformLabels: _labels);
    final families = ProviderFamily.values.toList()..sort(_compareFamilies);

    return PullToRefreshList(
      onRefresh: widget.onRefresh,
      children: [
        for (final provider in families) ...[
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
                  Focus(
                    key: _rowKeys.putIfAbsent(connection.id, GlobalKey.new),
                    focusNode: _rowFocus.putIfAbsent(
                      connection.id,
                      FocusNode.new,
                    ),
                    child: _connectionRow(connection),
                  ),
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
