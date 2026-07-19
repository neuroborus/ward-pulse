import 'package:flutter/material.dart';

import '../dashboard/dashboard_models.dart';

class UsageHistoryChart extends StatelessWidget {
  const UsageHistoryChart({super.key, required this.buckets});

  final List<UsageBucket> buckets;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final totalCost = _totalCost(buckets);
    final showDates = _spansMultipleUtcDays(buckets);

    return Card(
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Usage history',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                Text(_bucketCountLabel(buckets.length)),
              ],
            ),
            const SizedBox(height: 14),
            if (buckets.isEmpty)
              const Text('No usage history')
            else ...[
              SizedBox(
                height: 112,
                width: double.infinity,
                child: CustomPaint(
                  painter: _UsageHistoryPainter(
                    values: buckets
                        .map((bucket) => bucket.cost?.minorUnits ?? 0)
                        .toList(growable: false),
                    color: colors.primary,
                    baselineColor: colors.outlineVariant,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: Text(_rangeLabel(buckets.first.startAt, showDates)),
                  ),
                  Text(totalCost?.label ?? 'Unknown'),
                  Expanded(
                    child: Text(
                      _rangeLabel(buckets.last.endAt, showDates),
                      textAlign: TextAlign.end,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _UsageHistoryPainter extends CustomPainter {
  const _UsageHistoryPainter({
    required this.values,
    required this.color,
    required this.baselineColor,
  });

  final List<int> values;
  final Color color;
  final Color baselineColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) {
      return;
    }

    final baselinePaint =
        Paint()
          ..color = baselineColor
          ..strokeWidth = 1;
    final barPaint = Paint()..color = color;
    final maxValue = values.fold<int>(
      0,
      (current, value) => value > current ? value : current,
    );
    final barGap = values.length > 1 ? 8.0 : 0.0;
    final availableWidth =
        (size.width - barGap * (values.length - 1))
            .clamp(0.0, size.width)
            .toDouble();
    final barWidth = availableWidth / values.length;
    final radius = Radius.circular(barWidth < 6 ? 2 : 4);

    canvas.drawLine(
      Offset(0, size.height),
      Offset(size.width, size.height),
      baselinePaint,
    );

    if (barWidth <= 0) {
      return;
    }

    for (var index = 0; index < values.length; index += 1) {
      final fraction = maxValue == 0 ? 0.0 : values[index] / maxValue;
      final height =
          (size.height * fraction).clamp(2.0, size.height).toDouble();
      final left = index * (barWidth + barGap);
      final rect = Rect.fromLTWH(left, size.height - height, barWidth, height);

      canvas.drawRRect(RRect.fromRectAndRadius(rect, radius), barPaint);
    }
  }

  @override
  bool shouldRepaint(_UsageHistoryPainter oldDelegate) {
    return oldDelegate.values != values ||
        oldDelegate.color != color ||
        oldDelegate.baselineColor != baselineColor;
  }
}

String _bucketCountLabel(int count) {
  return count == 1 ? '1 bucket' : '$count buckets';
}

Money? _totalCost(List<UsageBucket> buckets) {
  if (buckets.isEmpty) {
    return null;
  }

  final currency = buckets.first.cost?.currency;
  if (currency == null ||
      buckets.any((bucket) => bucket.cost?.currency != currency)) {
    return null;
  }

  return Money(
    minorUnits: buckets.fold(
      0,
      (total, bucket) => total + bucket.cost!.minorUnits,
    ),
    currency: currency,
  );
}

bool _spansMultipleUtcDays(List<UsageBucket> buckets) {
  if (buckets.isEmpty) {
    return false;
  }

  final start = buckets.first.startAt.toUtc();
  final end = buckets.last.endAt.toUtc();
  return start.year != end.year ||
      start.month != end.month ||
      start.day != end.day;
}

String _rangeLabel(DateTime value, bool showDate) {
  final utc = value.toUtc();
  if (showDate) {
    final month = utc.month.toString().padLeft(2, '0');
    final day = utc.day.toString().padLeft(2, '0');
    return '${utc.year}-$month-$day';
  }

  final hour = utc.hour.toString().padLeft(2, '0');
  final minute = utc.minute.toString().padLeft(2, '0');

  return '$hour:$minute';
}
