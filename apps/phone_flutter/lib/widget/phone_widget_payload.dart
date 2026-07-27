import '../dashboard/dashboard_models.dart';
import '../dashboard/provider_status_color.dart';
import 'phone_widget_preferences.dart';

/// One rendered home-widget row (remaining language).
final class PhoneWidgetRow {
  const PhoneWidgetRow({
    required this.label,
    required this.remainingPercent,
    required this.accentArgb,
  });

  final String label;
  final int remainingPercent;

  /// ARGB int for the family accent bar.
  final int accentArgb;

  String get line => '$remainingPercent% left · $label';
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
          label: metric.label,
          remainingPercent: metric.remainingPercent!.round(),
          accentArgb: phoneWidgetAccentArgb(metric.id),
        ),
    ],
  );
}

/// Family accent matching [providerFamilyColor] / budget blue.
int phoneWidgetAccentArgb(String metricId) {
  if (metricId.startsWith('budget.')) {
    return familyBudgetColor.toARGB32();
  }
  if (metricId.contains('claude')) {
    return providerFamilyColor('claude').toARGB32();
  }
  if (metricId.contains('cursor')) {
    return providerFamilyColor('cursor').toARGB32();
  }
  if (metricId.contains('codex') || metricId.contains('openai')) {
    return providerFamilyColor('codex').toARGB32();
  }
  return familyBudgetColor.toARGB32();
}
