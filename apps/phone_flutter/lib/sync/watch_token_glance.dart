import '../dashboard/dashboard_models.dart';

/// Compact token activity for the watch-face SHORT_TEXT slot.
final class WatchTokenGlance {
  const WatchTokenGlance({
    required this.text,
    required this.label,
    this.provider,
  });

  /// Glance string at most 12 characters (e.g. `1.4B TOK`).
  final String text;
  final String label;
  final String? provider;

  Map<String, Object?> toJson() => {
    'text': text,
    'label': label,
    'provider': provider,
  };
}

/// Today's token total from provider buckets, when any account reports them.
WatchTokenGlance? resolveWatchTokenGlance(DashboardSnapshot snapshot) {
  final day = _utcDate(snapshot.generatedAt);
  final totals = <String, int>{};

  for (final account in snapshot.accounts) {
    if (account.provider == 'mock') {
      continue;
    }
    var dayTokens = 0;
    var sawBucket = false;
    for (final bucket in account.buckets) {
      final tokens = bucket.totalTokens;
      if (tokens == null || tokens < 0) {
        continue;
      }
      if (_utcDate(bucket.startAt) != day) {
        continue;
      }
      dayTokens += tokens;
      sawBucket = true;
    }
    // Ignore an all-zero day — "0 TOK" is noise on the watch face.
    if (sawBucket && dayTokens > 0) {
      totals[account.provider] = (totals[account.provider] ?? 0) + dayTokens;
    }
  }

  if (totals.isEmpty) {
    return null;
  }

  if (totals.length == 1) {
    final entry = totals.entries.single;
    return WatchTokenGlance(
      text: _glanceText(entry.value),
      label: 'Today tokens',
      provider: entry.key,
    );
  }

  final sum = totals.values.fold<int>(0, (left, right) => left + right);
  if (sum <= 0) {
    return null;
  }
  return WatchTokenGlance(
    text: _glanceText(sum),
    label: 'Today tokens',
  );
}

/// Compact count for glanceable Wear surfaces.
String compactTokenCount(int value) {
  final absolute = value.abs();
  final sign = value < 0 ? '-' : '';
  if (absolute < 1000) {
    return '$sign$absolute';
  }

  // Carry 999.95K → 1M (never emit 1000K / 1000M / …).
  var amount = absolute / 1000;
  var unit = 0;
  const suffixes = ['K', 'M', 'B', 'T'];
  while (unit < suffixes.length - 1 && _roundOneDecimal(amount) >= 1000) {
    amount /= 1000;
    unit += 1;
  }
  return '$sign${_formatOneDecimal(amount)}${suffixes[unit]}';
}

/// Schema `tokenGlance.text` maxLength is 12 (e.g. `999.9B TOK`).
String _glanceText(int tokens) {
  final text = '${compactTokenCount(tokens)} TOK';
  if (text.length <= 12) {
    return text;
  }
  // Pathological totals only — keep the watch contract valid.
  return '>999T TOK';
}

double _roundOneDecimal(double value) => (value * 10).round() / 10;

String _formatOneDecimal(double value) {
  final rounded = _roundOneDecimal(value);
  return rounded == rounded.roundToDouble()
      ? rounded.toInt().toString()
      : rounded.toStringAsFixed(1);
}

DateTime _utcDate(DateTime value) {
  final utc = value.toUtc();
  return DateTime.utc(utc.year, utc.month, utc.day);
}
