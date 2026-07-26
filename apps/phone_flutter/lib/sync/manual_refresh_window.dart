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
