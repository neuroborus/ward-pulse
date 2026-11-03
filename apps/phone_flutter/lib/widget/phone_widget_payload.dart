import '../dashboard/dashboard_models.dart';
import '../dashboard/provider_status_color.dart';
import '../providers/provider_connection.dart';
import '../settings/watch_ring_preferences.dart';
import '../sync/credit_request_runway.dart';
import '../sync/watch_credits_glance.dart';
import 'phone_widget_preferences.dart';

enum PhoneWidgetRowKind { allowance, budget }

/// Private, lossless metric data; native layout decides which details fit.
final class PhoneWidgetRow {
  const PhoneWidgetRow({
    required this.label,
    required this.remainingPercent,
    required this.accentArgb,
    this.creditsSuffix,
    this.familyLabel,
    this.poolLabel,
    this.resetsAt,
    this.kind = PhoneWidgetRowKind.allowance,
    this.spent,
    this.cap,
    this.extraUsed,
    this.extraCap,
  });

  /// Complete identity retained for old caches and descriptive payload strings.
  final String label;
  final int? remainingPercent;
  final PhoneWidgetRowKind kind;
  final Money? spent;
  final Money? cap;
  final Quantity? extraUsed;
  final Quantity? extraCap;

  /// Explicit display lines; absent when only a legacy flat label is available.
  final String? familyLabel;
  final String? poolLabel;

  /// The selected allowance's reported boundary, never an inferred budget end.
  final DateTime? resetsAt;

  /// ARGB int for the family accent bar.
  final int accentArgb;

  /// Glance-style purchased credits for this row's provider (`320 credits`).
  final String? creditsSuffix;

  /// Fixed percent column for the launcher table layout.
  String get percentText =>
      remainingPercent == null ? '' : '$remainingPercent% left';

  /// Descriptive payload line, separate from native column visibility.
  String get line {
    final credits = creditsSuffix;
    if (kind == PhoneWidgetRowKind.budget) {
      return '${spent == null ? 'Unavailable' : phoneWidgetMoneyText(spent!)} · $label';
    }
    if (credits == null) {
      return '$percentText · $label';
    }
    return '$percentText · $label · $credits';
  }
}

/// Snapshot + prefs → rows, including supported saved unknown budgets.
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
    rows: [for (final metric in metrics) _phoneWidgetRow(snapshot, metric)],
  );
}

PhoneWidgetRow _phoneWidgetRow(
  DashboardSnapshot snapshot,
  WatchRingMetric metric,
) {
  final provider = providerFromRingId(metric.id);
  final connection = connectionFromBudgetRingId(metric.id);
  final String? family;
  if (connection != null) {
    family = providerFamilyLabel(connection.provider);
  } else if (provider != null) {
    family = providerDisplayLabel(provider);
  } else {
    family = null;
  }
  // This legacy pool label already includes its family. Other pool names stay
  // whole, including spaces and separators that are part of their real label.
  final pool =
      metric.id == cursorOwnPoolId && metric.label == 'Cursor Models'
          ? 'Models'
          : metric.label;
  final allowance = _phoneWidgetAllowance(snapshot, metric.id);
  final extra = metric.id == 'allowance.claude.claude-extra-usage';
  return PhoneWidgetRow(
    label: metric.catalogTitle,
    familyLabel: family,
    poolLabel: family == null ? null : pool,
    remainingPercent: phoneWidgetRemainingPercent(metric),
    kind:
        connection == null
            ? PhoneWidgetRowKind.allowance
            : PhoneWidgetRowKind.budget,
    spent: metric.spent,
    cap: metric.limit,
    extraUsed: extra ? allowance?.used : null,
    extraCap: extra ? allowance?.limit : null,
    accentArgb: phoneWidgetAccentArgb(metric.id),
    creditsSuffix: phoneWidgetCreditsSuffix(snapshot, metric.id),
    resetsAt: allowance?.resetsAt,
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
  if (_phoneWidgetAllowance(snapshot, metricId)?.source ==
      AllowanceSource.purchased) {
    return null;
  }
  final remaining = purchasedCreditsRemainingForProvider(snapshot, provider);
  if (remaining == null || remaining <= 0) {
    return null;
  }
  return '${compactCreditCount(remaining)} credits';
}

AllowanceState? _phoneWidgetAllowance(
  DashboardSnapshot snapshot,
  String metricId,
) {
  final provider = providerFromRingId(metricId);
  if (provider == null) {
    return null;
  }
  final stem = 'allowance.$provider.';
  final allowanceId = metricId.substring(stem.length);
  for (final account in snapshot.accounts) {
    if (account.provider != provider) {
      continue;
    }
    for (final allowance in account.allowances) {
      if (allowance.id == allowanceId) {
        return allowance;
      }
    }
  }
  return null;
}

/// Family accent matching [providerFamilyColor]; neutral grey when no family is
/// named, which should not happen for a metric the product ships.
///
/// A budget row carries the connection it belongs to, so it takes that family
/// (`budget.anthropic.platform.month`) rather than a colour of its own.
int phoneWidgetAccentArgb(String metricId) {
  if (metricId == 'allowance.claude.claude-seven-day-fable') {
    return familyClaudeFableColor.toARGB32();
  }
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
  // Before the family branch, or it would never be reached: the limit name sits
  // inside a `codex` id (`WATCH_RING_DESIGN.md`, Split band).
  if (metricId.contains('codex.spark')) {
    return familyCodexSparkColor.toARGB32();
  }
  if (metricId.contains('codex') || metricId.contains('openai')) {
    return providerFamilyColor('codex').toARGB32();
  }
  return familyFallbackColor.toARGB32();
}
