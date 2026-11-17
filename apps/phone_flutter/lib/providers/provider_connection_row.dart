import 'package:flutter/material.dart';

import 'connection_lifecycle.dart';

/// Connection status and screen-owned action widgets for a catalog row.
typedef ConnectionRowControls = ({List<Widget> actions, Widget status});

/// Builds the controls shared by ordinary and extracted connection rows.
typedef ConnectionRowControlsBuilder =
    ConnectionRowControls Function({
      List<Widget> leading,
      required Widget status,
    });

/// Shared connection-catalog row for a plan or platform connection.
class ProviderConnectionRow extends StatelessWidget {
  const ProviderConnectionRow({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.status,
    this.actions = const [],
    this.onTap,
    this.supportingText,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Widget status;
  final List<Widget> actions;
  final VoidCallback? onTap;
  final String? supportingText;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: DefaultTextStyle(
        style: theme.textTheme.bodyMedium!.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: MergeSemantics(
                    child: Semantics(
                      button: true,
                      enabled: onTap != null,
                      child: InkWell(
                        onTap: onTap,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(
                            minWidth: kMinInteractiveDimension,
                            minHeight: kMinInteractiveDimension,
                          ),
                          child: Padding(
                            padding: const EdgeInsets.only(
                              top: 4,
                              right: 8,
                              bottom: 4,
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(
                                  icon,
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        title,
                                        style: theme.textTheme.bodyLarge,
                                      ),
                                      Text(subtitle),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                for (final action in actions)
                  SizedBox.square(
                    dimension: kMinInteractiveDimension,
                    child: action,
                  ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(left: 40, top: 4, bottom: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  status,
                  if (supportingText?.isNotEmpty == true) ...[
                    const SizedBox(height: 4),
                    Text(supportingText!),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Spinner sized for a catalog row status.
class RowProgress extends StatelessWidget {
  const RowProgress();

  @override
  Widget build(BuildContext context) {
    return const SizedBox.square(
      dimension: 20,
      child: CircularProgressIndicator(strokeWidth: 2),
    );
  }
}

/// Shared plan-row settlement; only a held native lease can confirm retirement.
mixin PlanConnectionState<T extends StatefulWidget> on State<T> {
  bool? hasAccount;
  bool connecting = false;
  bool disconnecting = false;
  bool connectionUnavailable = false;
  int _connectionRevision = 0;
  CredentialVersion? _retirement;
  String? _cleanupFeedback;
  bool _reloadFailed = false;

  Object ownerOf(T widget);
  Future<bool> readConnected();
  Future<void> observeConnection(CredentialLifecycleObserver observer);
  void credentialsChanged();

  bool ownsConnectionOperation(int revision, Object owner) =>
      mounted &&
      revision == _connectionRevision &&
      identical(owner, ownerOf(widget));

  int beginConnectionOperation() {
    _connectionRevision++;
    connecting = false;
    disconnecting = false;
    connectionUnavailable = false;
    _retirement = null;
    _cleanupFeedback = null;
    _reloadFailed = false;
    return _connectionRevision;
  }

  @override
  void didUpdateWidget(covariant T oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(ownerOf(oldWidget), ownerOf(widget))) {
      beginConnectionOperation();
      loadConnectionState();
    }
  }

  Future<void> loadConnectionState() async {
    final revision = ++_connectionRevision;
    final owner = ownerOf(widget);
    try {
      final connected = await readConnected();
      if (ownsConnectionOperation(revision, owner)) {
        setState(() {
          hasAccount = connected;
          connectionUnavailable = false;
          disconnecting = false;
        });
      }
    } catch (_) {
      if (ownsConnectionOperation(revision, owner)) _unavailable();
    }
  }

  void _unavailable() => setState(() {
    hasAccount = null;
    connectionUnavailable = true;
    disconnecting = false;
  });

  void _feedback(String message) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(message)));

  Future<void> disconnectConnection({
    required Object owner,
    required Future<void> Function(void Function(CredentialVersion)) remove,
    Future<String?> Function()? cleanup,
  }) async {
    if (!mounted || !identical(owner, ownerOf(widget))) return;
    beginConnectionOperation();
    final revision = _connectionRevision;
    setState(() => disconnecting = true);
    var completed = false;
    String? cleanupFeedback;
    try {
      await remove((stamp) {
        if (!ownsConnectionOperation(revision, owner) || _retirement != null) {
          return;
        }
        _retirement = stamp;
        setState(() {
          hasAccount = false;
          connectionUnavailable = false;
          disconnecting = false;
        });
        try {
          credentialsChanged();
        } catch (_) {
          _reloadFailed = true;
        }
      });
      if (ownsConnectionOperation(revision, owner)) {
        cleanupFeedback = await cleanup?.call();
      }
      completed = true;
    } catch (_) {
      cleanupFeedback = 'Disconnected, but local cleanup remains';
    }
    if (!ownsConnectionOperation(revision, owner)) return;
    _cleanupFeedback = cleanupFeedback;
    await _settleRemoval(
      revision,
      owner,
      completed: completed,
      reportFailure: true,
    );
  }

  Future<void> _settleRemoval(
    int revision,
    Object owner, {
    bool completed = false,
    bool reportFailure = false,
  }) async {
    try {
      await observeConnection((mode, stamp) {
        if (!ownsConnectionOperation(revision, owner)) return;
        final receipt = _retirement;
        final matching =
            mode == 'deleted' &&
            receipt != null &&
            stamp != null &&
            receipt.generation == stamp.generation &&
            receipt.revision == stamp.revision &&
            receipt.epoch == stamp.epoch;
        final legacy =
            mode == 'deleted' && stamp == null && receipt == null && completed;
        if (mode == 'pending' ||
            mode == 'migration' ||
            mode == 'legacy' ||
            (mode == 'deleted' && receipt == null && !legacy)) {
          _unavailable();
          return;
        }
        setState(() {
          hasAccount = mode == 'active';
          connectionUnavailable = false;
          disconnecting = false;
        });
        if (legacy) {
          try {
            credentialsChanged();
          } catch (_) {
            _reloadFailed = true;
          }
        }
        if (matching || legacy) {
          if (_cleanupFeedback case final message?) _feedback(message);
          if (_reloadFailed) _feedback('Disconnected, but could not reload usage');
        } else if (receipt == null && reportFailure) {
          _feedback('Could not disconnect. Check again or reconnect');
        }
      });
    } catch (_) {
      if (ownsConnectionOperation(revision, owner)) _unavailable();
    }
  }

  Widget connectionStatus() {
    if (connectionUnavailable) return unavailableStatus;
    return switch ((hasAccount, connecting || disconnecting)) {
      (_, true) || (null, _) => const RowProgress(),
      (true, _) => const Text('Connected'),
      (false, _) => const Text('Not connected'),
    };
  }

  Widget get unavailableStatus => TextButton(
    onPressed: () => _settleRemoval(++_connectionRevision, ownerOf(widget)),
    child: const Text('Unavailable · Retry check'),
  );
}
