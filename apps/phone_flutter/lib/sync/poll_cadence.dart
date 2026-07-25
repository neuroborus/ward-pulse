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

  /// Non-clamping freshness guidance for the Cursor Team Admin API row only.
  static const cursorFreshnessNote =
      'Cursor aggregates usage about once an hour, so refreshed values may lag.';

  static int clampMinutes(int minutes) =>
      minutes.clamp(minRefreshMinutes, maxRefreshMinutes);
}
