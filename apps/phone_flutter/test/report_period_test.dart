import 'package:flutter_test/flutter_test.dart';
import 'package:ward_pulse_phone/sync/report_period.dart';

void main() {
  test(
    'floors one UTC capture across day, Monday, month and year boundaries',
    () {
      for (final (stamp, today, week, month) in [
        (
          '2026-07-19T23:59:59.999999Z',
          DateTime.utc(2026, 7, 19),
          DateTime.utc(2026, 7, 13),
          DateTime.utc(2026, 7),
        ),
        (
          '2026-07-20T00:00:00.000500Z',
          DateTime.utc(2026, 7, 20),
          DateTime.utc(2026, 7, 20),
          DateTime.utc(2026, 7),
        ),
        (
          '2026-08-01T00:00:00.000500Z',
          DateTime.utc(2026, 8),
          DateTime.utc(2026, 7, 27),
          DateTime.utc(2026, 8),
        ),
        (
          '2027-01-01T00:00:00.000500Z',
          DateTime.utc(2027),
          DateTime.utc(2026, 12, 28),
          DateTime.utc(2027),
        ),
        (
          '2026-06-01T00:00:00Z',
          DateTime.utc(2026, 6),
          DateTime.utc(2026, 6),
          DateTime.utc(2026, 6),
        ),
        (
          '2026-08-01T02:00:00.000500+02:00',
          DateTime.utc(2026, 8),
          DateTime.utc(2026, 7, 27),
          DateTime.utc(2026, 8),
        ),
      ]) {
        final instant = DateTime.parse(stamp);
        final bounds = ReportPeriodBounds.utc(instant);
        expect(bounds.generatedAt, instant.toUtc());
        expect(bounds.todayStartMs, today.millisecondsSinceEpoch);
        expect(bounds.weekStartMs, week.millisecondsSinceEpoch);
        expect(bounds.monthStartMs, month.millisecondsSinceEpoch);
        expect(
          bounds.requestStartMs,
          week.isBefore(month)
              ? week.millisecondsSinceEpoch
              : month.millisecondsSinceEpoch,
        );
        final cutoffMicros = bounds.endExclusiveMs * 1000;
        expect(cutoffMicros, lessThanOrEqualTo(instant.microsecondsSinceEpoch));
        expect(instant.microsecondsSinceEpoch - cutoffMicros, lessThan(1000));
      }
      final subMillisecond = ReportPeriodBounds.utc(
        DateTime.utc(2026, 6, 1, 0, 0, 0, 0, 500),
      );
      expect(
        subMillisecond.generatedAt.isAfter(subMillisecond.todayStart),
        isTrue,
      );
      expect(subMillisecond.requestStartMs, subMillisecond.endExclusiveMs);
      final beforeEpoch = ReportPeriodBounds.utc(
        DateTime.fromMicrosecondsSinceEpoch(-500, isUtc: true),
      );
      expect(beforeEpoch.endExclusiveMs, -1);
    },
  );

  test('uses the earlier of week and month starts for the fetch window', () {
    final midWeek = ReportPeriodBounds.utc(DateTime.utc(2026, 7, 19, 12));
    expect(midWeek.reportStart, midWeek.monthStart);
    expect(midWeek.todayStart, DateTime.utc(2026, 7, 19));
    expect(midWeek.weekStart, DateTime.utc(2026, 7, 13));
    expect(midWeek.monthStart, DateTime.utc(2026, 7, 1));

    final monthStartOnWeekday = ReportPeriodBounds.utc(
      DateTime.utc(2026, 8, 1, 12),
    );
    expect(monthStartOnWeekday.reportStart, monthStartOnWeekday.weekStart);
    expect(monthStartOnWeekday.weekStart, DateTime.utc(2026, 7, 27));
  });
}
