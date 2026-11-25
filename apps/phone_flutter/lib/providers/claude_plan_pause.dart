import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'provider_connection.dart';
import 'provider_connection_row.dart';

/// Claude plan sign-in, token refresh and reporting run only in Debug builds.
///
/// Profile and Release builds pause the connection, with the same Debug
/// criterion as Mock data. No runtime setting reenables it.
const claudePlanPausedInBuild = !kDebugMode;

const claudePlanPauseExplanation =
    'Claude plan sign-in and monitoring are paused. '
    "Anthropic's policy restricts third-party apps from using Claude plan "
    'credentials.';

/// Muted Claude plan row whose Connect action only explains the pause.
///
/// Tap, click, keyboard activation and hover show the explanation; nothing
/// here starts sign-in or reads a saved credential.
class PausedClaudePlanRow extends StatefulWidget {
  const PausedClaudePlanRow({super.key, required this.connection});

  final ProviderConnection connection;

  @override
  State<PausedClaudePlanRow> createState() => _PausedClaudePlanRowState();
}

class _PausedClaudePlanRowState extends State<PausedClaudePlanRow> {
  final _explanation = GlobalKey<TooltipState>();

  void _explain() => _explanation.currentState?.ensureTooltipVisible();

  @override
  Widget build(BuildContext context) {
    // Muted against the primary-colored actions while keeping readable contrast.
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return ProviderConnectionRow(
      icon: Icons.account_circle_outlined,
      title: widget.connection.listTitle,
      subtitle: 'Temporarily unavailable',
      onTap: _explain,
      status: MergeSemantics(
        child: Tooltip(
          key: _explanation,
          message: claudePlanPauseExplanation,
          triggerMode: TooltipTriggerMode.manual,
          child: TextButton(
            style: TextButton.styleFrom(foregroundColor: muted),
            onPressed: _explain,
            child: const Text('Connect'),
          ),
        ),
      ),
    );
  }
}
