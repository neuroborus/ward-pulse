import 'package:flutter/material.dart';

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
    this.statusBelow = false,
    this.supportingText,
  });

  static const _compactWidth = 360.0;

  final IconData icon;
  final String title;
  final String subtitle;
  final Widget status;
  final List<Widget> actions;
  final VoidCallback? onTap;
  final bool statusBelow;
  final String? supportingText;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < _compactWidth;
        final stackedActions = (compact || statusBelow) && actions.length > 1;
        final trailing = [
          if (!stackedActions) ...actions,
          if (!compact && !statusBelow) status,
        ];
        return ListTile(
          leading: Icon(icon),
          title: Text(title),
          subtitle:
              compact || statusBelow
                  ? Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(subtitle),
                      const SizedBox(height: 4),
                      status,
                      if (supportingText?.isNotEmpty == true) ...[
                        const SizedBox(height: 4),
                        Text(supportingText!),
                      ],
                      if (stackedActions)
                        Wrap(
                          children: [
                            for (final action in actions)
                              ConstrainedBox(
                                constraints: const BoxConstraints(
                                  minWidth: kMinInteractiveDimension,
                                  minHeight: kMinInteractiveDimension,
                                ),
                                child: action,
                              ),
                          ],
                        ),
                    ],
                  )
                  : Text(subtitle),
          isThreeLine: compact || statusBelow || subtitle.contains('\n'),
          trailing:
              trailing.isEmpty
                  ? null
                  : Row(mainAxisSize: MainAxisSize.min, children: trailing),
          onTap: onTap,
        );
      },
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
