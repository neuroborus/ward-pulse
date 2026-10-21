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
