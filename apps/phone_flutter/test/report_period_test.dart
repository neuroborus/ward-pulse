import 'package:flutter_test/flutter_test.dart';
import 'package:ward_pulse_phone/sync/report_period.dart';

void main() {
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
