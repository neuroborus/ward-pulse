import 'package:flutter/material.dart';

/// Shared Settings row for a plan or platform connection.
class ProviderConnectionRow extends StatelessWidget {
  const ProviderConnectionRow({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.trailing,
    this.onTap,
    this.enabled = true,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Widget trailing;
  final VoidCallback? onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return ListTile(
      enabled: enabled,
      leading: Icon(icon, color: enabled ? null : colors.outline),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: trailing,
      onTap: enabled ? onTap : null,
    );
  }
}
