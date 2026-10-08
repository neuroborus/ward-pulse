import 'package:flutter/material.dart';

import 'dashboard_models.dart';
import 'provider_status_color.dart';

/// One provider status as a glyph, with the word behind a tap.
///
/// Chrome shared by the Dashboard cards and the Settings diagnostics rows, so
/// it lives beside the status colour and severity rules rather than inside the
/// screen that happened to need it first.
class StatusPill extends StatelessWidget {
  const StatusPill({super.key, required this.status, this.tooltip});

  final ProviderStatus status;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    // Short word (OK / Warning) by default; sync callers may override.
    final message = tooltip ?? status.label;

    return Tooltip(
      message: message,
      // Tap works on phone; hover still works on desktop/emulator with pointer.
      triggerMode: TooltipTriggerMode.tap,
      showDuration: const Duration(seconds: 6),
      child: Padding(
        // Keep chrome compact while giving the icon a usable tap target.
        padding: const EdgeInsets.all(6),
        child: Icon(
          _statusIcon(status),
          color: providerStatusColor(colors, status),
          size: 18,
          semanticLabel: message,
        ),
      ),
    );
  }
}

IconData _statusIcon(ProviderStatus status) {
  return switch (status) {
    ProviderStatus.ok => Icons.check_circle,
    ProviderStatus.warning => Icons.warning_amber,
    ProviderStatus.error => Icons.error,
    ProviderStatus.rateLimited => Icons.speed,
    ProviderStatus.authRequired => Icons.key,
    ProviderStatus.stale => Icons.schedule,
    ProviderStatus.unknown => Icons.help_outline,
  };
}
