import 'package:flutter/material.dart';

import 'dashboard_models.dart';

/// Watch-ring family accents for phone multi-provider metrics (not chrome).
const _familyCodex = Color(0xFF65D78A);
const _familyClaude = Color(0xFFE8915A);
const _familyCursor = Color(0xFF67E8D4);
const _familyOpenAi = Color(0xFF65D78A);
const familyBudgetColor = Color(0xFF8AB4F8);

Color providerStatusColor(ColorScheme colors, ProviderStatus status) {
  return switch (status) {
    // Follows olive chrome primary — not Codex/OpenAI green.
    ProviderStatus.ok => colors.primary,
    ProviderStatus.warning ||
    ProviderStatus.rateLimited ||
    ProviderStatus.stale => colors.tertiary,
    ProviderStatus.error || ProviderStatus.authRequired => colors.error,
    ProviderStatus.unknown => colors.outline,
  };
}

/// Accent for a provider family (matches `WATCH_RING_DESIGN.md`).
Color providerFamilyColor(String provider) {
  return switch (provider) {
    'openai' => _familyOpenAi,
    'codex' => _familyCodex,
    'claude' => _familyClaude,
    'cursor' => _familyCursor,
    'mock' => familyBudgetColor,
    _ => familyBudgetColor,
  };
}
