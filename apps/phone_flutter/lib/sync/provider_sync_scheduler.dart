import 'dart:async';

/// Schedules automatic provider sync ticks at the chosen refresh interval.
///
/// The phone owns cadence; each tick reloads the dashboard and re-sends the
/// watch summary.
abstract interface class ProviderSyncScheduler {
  /// Emits when a sync should run.
  Stream<void> get ticks;

  Future<void> schedule(Duration interval);

  Future<void> cancel();
}

/// No-op scheduler for hosts that sync only on demand, including widget tests.
final class DisabledProviderSyncScheduler implements ProviderSyncScheduler {
  const DisabledProviderSyncScheduler();

  @override
  Stream<void> get ticks => const Stream.empty();

  @override
  Future<void> schedule(Duration interval) async {}

  @override
  Future<void> cancel() async {}
}

/// Ticks on an in-process timer while the app isolate is alive.
///
/// Honors the full 5–60 minute slider. After process death, headless
/// WorkManager sync uses at least 15 minutes (`HeadlessProviderSync`).
final class TimerProviderSyncScheduler implements ProviderSyncScheduler {
  final _ticks = StreamController<void>.broadcast();
  Timer? _timer;

  @override
  Stream<void> get ticks => _ticks.stream;

  @override
  Future<void> schedule(Duration interval) async {
    _timer?.cancel();
    if (interval <= Duration.zero) {
      return;
    }
    _timer = Timer.periodic(interval, (_) => _ticks.add(null));
  }

  @override
  Future<void> cancel() async {
    _timer?.cancel();
    _timer = null;
  }
}
