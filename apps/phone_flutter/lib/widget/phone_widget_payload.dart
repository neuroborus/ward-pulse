import '../dashboard/dashboard_models.dart';
import '../dashboard/provider_status_color.dart';
import '../settings/watch_ring_preferences.dart';
import '../sync/credit_request_runway.dart';
import '../sync/watch_credits_glance.dart';
import 'phone_widget_preferences.dart';

/// One rendered home-widget row (remaining language).
final class PhoneWidgetRow {
  const PhoneWidgetRow({
    required this.label,
    required this.remainingPercent,
    required this.accentArgb,
    this.creditsSuffix,
  });

  final String label;
  final int remainingPercent;

  /// ARGB int for the family accent bar.
  final int accentArgb;

  /// Glance-style purchased credits for this row's provider (`320 credits`).
  final String? creditsSuffix;

  /// Fixed percent column for the launcher table layout.
  String get percentText => '$remainingPercent% left';

  /// Widget-tab / tests line: `% left` · label · optional credits (matches columns).
  String get line {
    final credits = creditsSuffix;
    if (credits == null) {
      return '$percentText · $label';
    }
    return '$percentText · $label · $credits';
  }
}

/// Snapshot + prefs → home-widget rows (unavailable already omitted).
final class PhoneWidgetPayload {
  const PhoneWidgetPayload({required this.rows, required this.stale});

  final List<PhoneWidgetRow> rows;
  final bool stale;

  bool get isEmpty => rows.isEmpty;
}

/// Builds the launcher payload. Tightest-first; exhausted plan pools stay as 0%.
PhoneWidgetPayload buildPhoneWidgetPayload(
  DashboardSnapshot snapshot,
  PhoneWidgetPreferences preferences, {
  int maxSlots = phoneWidgetSlotCount,
}) {
  final metrics = orderPhoneWidgetMetrics(
    resolvePhoneWidgetMetrics(snapshot, preferences),
    maxSlots: maxSlots,
  );
  return PhoneWidgetPayload(
    stale: snapshot.overallStatus == ProviderStatus.stale,
    rows: [
      for (final metric in metrics)
        PhoneWidgetRow(
          label: metric.catalogTitle,
          remainingPercent: metric.remainingPercent!.round(),
          accentArgb: phoneWidgetAccentArgb(metric.id),
          creditsSuffix: phoneWidgetCreditsSuffix(snapshot, metric.id),
        ),
    ],
  );
}

/// Per-provider purchased credits suffix for a **plan** metric row, or null.
///
/// Matches Wear Glance / face strips: append finite purchased `credits` on plan
/// windows only. Purchased-meter rows (Extra usage, on-demand) already *are* the
/// credit pool — do not repeat. Budgets and missing/unlimited balances omit.
String? phoneWidgetCreditsSuffix(DashboardSnapshot snapshot, String metricId) {
  final provider = providerFromRingId(metricId);
  if (provider == null) {
    return null;
  }
  if (_isPurchasedMeterMetric(snapshot, provider, metricId)) {
    return null;
  }
  final remaining = purchasedCreditsRemainingForProvider(snapshot, provider);
  if (remaining == null || remaining <= 0) {
    return null;
  }
  return '${compactCreditCount(remaining)} credits';
}

bool _isPurchasedMeterMetric(
  DashboardSnapshot snapshot,
  String provider,
  String metricId,
) {
  const prefix = 'allowance.';
  final stem = '$prefix$provider.';
  if (!metricId.startsWith(stem)) {
    return false;
  }
  final allowanceId = metricId.substring(stem.length);
  for (final account in snapshot.accounts) {
    if (account.provider != provider) {
      continue;
    }
    for (final allowance in account.allowances) {
      if (allowance.id == allowanceId) {
        return allowance.source == AllowanceSource.purchased;
      }
    }
  }
  return false;
}

/// Family accent matching [providerFamilyColor]; neutral grey when no family is
/// named, which should not happen for a metric the product ships.
///
/// A budget row carries the connection it belongs to, so it takes that family
/// (`budget.anthropic.platform.month`) rather than a colour of its own.
int phoneWidgetAccentArgb(String metricId) {
  if (metricId.contains('claude') || metricId.contains('anthropic')) {
    return providerFamilyColor('claude').toARGB32();
  }
  // Before the family branch, or it would never be reached: the pool name sits
  // inside a `cursor` id (`WATCH_RING_DESIGN.md`, Split band).
  if (metricId.contains('cursor-plan-models')) {
    return familyCursorOwnColor.toARGB32();
  }
  if (metricId.contains('cursor')) {
    return providerFamilyColor('cursor').toARGB32();
  }
  if (metricId.contains('codex') || metricId.contains('openai')) {
    return providerFamilyColor('codex').toARGB32();
  }
  return familyFallbackColor.toARGB32();
}
