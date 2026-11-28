import 'poll_cadence.dart';

/// Phone-owned window for Wear Glance manual refresh.
///
/// Anchored to the PollCadence hard floor ([PollCadence.minRefreshMinutes]), not
/// the Settings auto-poll slider.
final class ManualRefreshWindow {
  const ManualRefreshWindow({required this.allowed, this.availableAt});

  final bool allowed;
  final DateTime? availableAt;

  static const floor = Duration(minutes: PollCadence.minRefreshMinutes);

  /// Advertised when no report or attempt anchors the window: refresh is open.
  static final open = DateTime.utc(1970);

  /// The anchor Wear advertises: the latest of [reportAt] and the cadence
  /// [attempts] the publisher owns, or [open] without one. A report dated
  /// after [now] predates a clock rollback, so its time proves no attempt;
  /// a publisher that sees the clock cross it later passes `null` instead.
  /// Display keeps the report's own time.
  static DateTime anchorAt({
    DateTime? reportAt,
    Iterable<DateTime?> attempts = const [],
    DateTime? now,
  }) {
    final clock = (now ?? DateTime.now()).toUtc();
    DateTime? anchor;
    for (final at in [
      if (reportAt != null && !reportAt.isAfter(clock)) reportAt,
      ...attempts,
    ]) {
      if (at != null && (anchor == null || at.isAfter(anchor))) anchor = at;
    }
    return anchor ?? open;
  }

  factory ManualRefreshWindow.fromLastSync({
    required DateTime lastSyncAt,
    DateTime? now,
  }) {
    final clock = (now ?? DateTime.now()).toUtc();
    final availableAt = lastSyncAt.toUtc().add(floor);
    if (!clock.isBefore(availableAt)) {
      return const ManualRefreshWindow(allowed: true);
    }
    return ManualRefreshWindow(allowed: false, availableAt: availableAt);
  }
}
