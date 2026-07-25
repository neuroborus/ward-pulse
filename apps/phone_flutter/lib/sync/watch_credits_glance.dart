import '../dashboard/dashboard_models.dart';
import '../settings/consumption_display_preferences.dart';

/// Compact remaining purchased credits for the watch-face strip.
final class WatchCreditsGlance {
  const WatchCreditsGlance({
    required this.text,
    required this.label,
    this.provider,
  });

  /// Glance string at most 12 characters (e.g. `500`, `1.2K`).
  final String text;
  final String label;
  final String? provider;

  Map<String, Object?> toJson() => {
    'text': text,
    'label': label,
    'provider': provider,
  };
}

/// Remaining purchased credits when Settings shows purchased usage.
WatchCreditsGlance? resolveWatchCreditsGlance(
  DashboardSnapshot snapshot,
  ConsumptionDisplayPreferences displayPreferences,
) {
  if (!displayPreferences.purchased) {
    return null;
  }

  String? unit;
  final providers = <String>{};
  double total = 0;
  var sawFinite = false;

  for (final account in snapshot.accounts) {
    for (final allowance in account.allowances) {
      if (allowance.source != AllowanceSource.purchased) {
        continue;
      }
      if (allowance.unlimited) {
        return const WatchCreditsGlance(
          text: '∞',
          label: 'Credits left',
          provider: null,
        );
      }
      final remaining = allowance.remaining;
      if (remaining == null) {
        continue;
      }
      final value = double.tryParse(remaining.value);
      if (value == null || !value.isFinite || value < 0) {
        continue;
      }
      if (unit != null && unit != remaining.unit) {
        // Mixed units — keep the first unit's running total only.
        continue;
      }
      unit = remaining.unit;
      total += value;
      sawFinite = true;
      providers.add(account.provider);
    }
  }

  if (!sawFinite || total <= 0) {
    return null;
  }

  return WatchCreditsGlance(
    text: _glanceText(total),
    label: 'Credits left',
    provider: providers.length == 1 ? providers.single : null,
  );
}

/// Schema `creditsGlance.text` maxLength is 12.
String _glanceText(double value) {
  final text = compactCreditCount(value);
  if (text.length <= 12) {
    return text;
  }
  return '>999T';
}

/// Compact credit count for glanceable Wear surfaces (no `TOK` suffix).
String compactCreditCount(double value) {
  final absolute = value.abs();
  final sign = value < 0 ? '-' : '';
  if (absolute < 1000) {
    final places = absolute.truncateToDouble() == absolute ? 0 : 1;
    return '$sign${absolute.toStringAsFixed(places)}';
  }

  var amount = absolute / 1000;
  var unit = 0;
  const suffixes = ['K', 'M', 'B', 'T'];
  while (unit < suffixes.length - 1 && _roundOneDecimal(amount) >= 1000) {
    amount /= 1000;
    unit += 1;
  }
  return '$sign${_formatOneDecimal(amount)}${suffixes[unit]}';
}

double _roundOneDecimal(double value) => (value * 10).round() / 10;

String _formatOneDecimal(double value) {
  final rounded = _roundOneDecimal(value);
  return rounded == rounded.roundToDouble()
      ? rounded.toInt().toString()
      : rounded.toStringAsFixed(1);
}
