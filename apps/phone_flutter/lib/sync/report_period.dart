/// Calendar bounds shared by platform reporting envelopes and fetch windows.
final class ReportPeriodBounds {
  const ReportPeriodBounds({
    required this.generatedAt,
    required this.todayStart,
    required this.weekStart,
    required this.monthStart,
  });

  factory ReportPeriodBounds.utc(DateTime now) {
    final generatedAt = now.toUtc();
    final todayStart = DateTime.utc(
      generatedAt.year,
      generatedAt.month,
      generatedAt.day,
    );
    final weekStart = todayStart.subtract(
      Duration(days: todayStart.weekday - 1),
    );
    final monthStart = DateTime.utc(generatedAt.year, generatedAt.month);
    return ReportPeriodBounds(
      generatedAt: generatedAt,
      todayStart: todayStart,
      weekStart: weekStart,
      monthStart: monthStart,
    );
  }

  final DateTime generatedAt;
  final DateTime todayStart;
  final DateTime weekStart;
  final DateTime monthStart;

  /// Monetary coverage ends at the captured instant floored to epoch milliseconds.
  int get endExclusiveMs {
    final micros = generatedAt.microsecondsSinceEpoch;
    return micros ~/ 1000 - (micros < 0 && micros.remainder(1000) != 0 ? 1 : 0);
  }

  int get todayStartMs => todayStart.millisecondsSinceEpoch;
  int get weekStartMs => weekStart.millisecondsSinceEpoch;
  int get monthStartMs => monthStart.millisecondsSinceEpoch;
  int get requestStartMs => reportStart.millisecondsSinceEpoch;

  /// Earliest bound needed so week and month cards both have source data.
  DateTime get reportStart =>
      weekStart.isBefore(monthStart) ? weekStart : monthStart;
}
