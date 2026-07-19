import 'package:flutter/material.dart';

import 'dashboard_models.dart';

const _successLight = Color(0xFF176B3A);
const _successDark = Color(0xFF65D78A);

Color providerStatusColor(ColorScheme colors, ProviderStatus status) {
  return switch (status) {
    ProviderStatus.ok => switch (colors.brightness) {
      Brightness.light => _successLight,
      Brightness.dark => _successDark,
    },
    ProviderStatus.warning => colors.tertiary,
    ProviderStatus.error ||
    ProviderStatus.rateLimited ||
    ProviderStatus.authRequired => colors.error,
    ProviderStatus.stale || ProviderStatus.unknown => colors.outline,
  };
}
