import '../dashboard/dashboard_models.dart';
import 'selected_data_freshness.dart';

/// Compact remaining purchased credits for the watch-face strip.
final class WatchCreditsGlance {
  const WatchCreditsGlance({
    required this.text,
    required this.label,
    this.provider,
    this.contributors = const [],
  });

  /// Glance string at most 12 characters (e.g. `500`, `1.2K`).
  final String text;
  final String label;
  final String? provider;
  final List<SurfaceDataContributor> contributors;

  Map<String, Object?> toJson() => {
    'text': text,
    'label': label,
    'provider': provider,
  };
}

/// Remaining purchased credits for the watch-face strip.
WatchCreditsGlance? resolveWatchCreditsGlance(DashboardSnapshot snapshot) {
  String? unit;
  final providers = <String>{};
  final contributors = <SurfaceDataContributor>[];
  double total = 0;
  var sawFinite = false;

  for (final account in snapshot.accounts) {
    for (final allowance in account.allowances) {
      if (allowance.source != AllowanceSource.purchased) {
        continue;
      }
      if (allowance.unlimited) {
        return WatchCreditsGlance(
          text: '∞',
          label: 'Credits left',
          provider: null,
          contributors: [(account: account, status: allowance.status)],
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
      contributors.add((account: account, status: allowance.status));
      sawFinite = true;
      providers.add(account.provider);
    }
  }

  if (!sawFinite || total <= 0) {
    return null;
  }

  return WatchCreditsGlance(
    text: _glanceText(total),
    contributors: contributors,
    label: 'Credits left',
    provider: providers.length == 1 ? providers.single : null,
  );
}

/// Mirrors Wear's first eligible purchased allowance for a rendered ring.
/// Unlike the widget sum, this channel also displays zero and unparsed values.
SurfaceDataContributor? watchRingCreditContributor(
  DashboardSnapshot snapshot,
  String provider,
) {
  for (final account in snapshot.accounts) {
    if (account.provider != provider) continue;
    for (final allowance in account.allowances) {
      if (allowance.source == AllowanceSource.purchased &&
          !allowance.unlimited &&
          allowance.remaining?.unit == 'credits') {
        return (account: account, status: allowance.status);
      }
    }
  }
  return null;
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
