/// Phone-side mirror of `ward_pulse_providers::poll`.
///
/// Rust owns the per-connection floors and their documented sources. The phone
/// needs the global slider bounds and the Cursor Admin API freshness note: the
/// lower bound is the strictest hard floor across connections, so a single
/// global cadence never polls any connection faster than that connection allows.
abstract final class PollCadence {
  static const minRefreshMinutes = 5;
  static const maxRefreshMinutes = 60;
  static const defaultRefreshMinutes = 15;

  /// Android WorkManager periodic minimum (`PeriodicWorkRequest`).
  ///
  /// In-process timer honors the slider down to [minRefreshMinutes]; headless
  /// sync after process death uses [headlessInterval].
  static const headlessMinRefreshMinutes = 15;

  /// Segmented Settings slider: 5–15 by 1, 15–30 by 5, 30–60 by 10.
  static final refreshIntervalStops = List<int>.unmodifiable([
    for (var minutes = minRefreshMinutes; minutes <= 15; minutes++) minutes,
    for (var minutes = 20; minutes <= 30; minutes += 5) minutes,
    for (var minutes = 40; minutes <= maxRefreshMinutes; minutes += 10) minutes,
  ]);

  /// Non-clamping freshness guidance for the Cursor Team Admin API row only.
  static const cursorFreshnessNote =
      'Cursor aggregates usage about once an hour, so refreshed values may lag.';

  /// Clamps into the slider range and snaps onto a segmented stop.
  static int clampMinutes(int minutes) =>
      _nearestStop(minutes.clamp(minRefreshMinutes, maxRefreshMinutes));

  /// Headless / WorkManager cadence: never below the Android 15-minute floor.
  static Duration headlessInterval(Duration preferred) {
    final minutes = preferred.inMinutes;
    final clamped =
        minutes < headlessMinRefreshMinutes
            ? headlessMinRefreshMinutes
            : clampMinutes(minutes);
    return Duration(minutes: clamped);
  }

  static int refreshIntervalStopIndex(int minutes) =>
      refreshIntervalStops.indexOf(clampMinutes(minutes));

  static int _nearestStop(int minutes) {
    var best = refreshIntervalStops.first;
    var bestDistance = (minutes - best).abs();
    for (final stop in refreshIntervalStops.skip(1)) {
      final distance = (minutes - stop).abs();
      // Prefer the later stop on a midpoint (e.g. 35 → 40).
      if (distance < bestDistance ||
          (distance == bestDistance && stop > best)) {
        best = stop;
        bestDistance = distance;
      }
    }
    return best;
  }
}
