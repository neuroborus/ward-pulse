import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ward_pulse_phone/sync/poll_cadence.dart';

/// Rust owns the cadence, so these tests read the constants from its source.
void main() {
  final rust =
      File('../../core/ward-pulse-providers/src/poll.rs').readAsStringSync();

  test('mirrors the Rust slider bounds', () {
    expect(
      PollCadence.minRefreshMinutes,
      _rustMinutes(rust, 'GLOBAL_REFRESH_MIN'),
    );
    expect(
      PollCadence.maxRefreshMinutes,
      _rustMinutes(rust, 'GLOBAL_REFRESH_MAX'),
    );
    expect(
      PollCadence.defaultRefreshMinutes,
      inInclusiveRange(
        PollCadence.minRefreshMinutes,
        PollCadence.maxRefreshMinutes,
      ),
    );
  });

  test('mirrors the Rust Cursor freshness note', () {
    expect(PollCadence.cursorFreshnessNote, _rustFreshnessNote(rust));
  });

  test('exposes segmented refresh stops', () {
    expect(
      PollCadence.refreshIntervalStops.first,
      PollCadence.minRefreshMinutes,
    );
    expect(
      PollCadence.refreshIntervalStops.last,
      PollCadence.maxRefreshMinutes,
    );
    expect(
      PollCadence.refreshIntervalStops,
      contains(PollCadence.defaultRefreshMinutes),
    );
    expect(PollCadence.refreshIntervalStops, [
      5,
      6,
      7,
      8,
      9,
      10,
      11,
      12,
      13,
      14,
      15,
      20,
      25,
      30,
      40,
      50,
      60,
    ]);
  });

  test('clamps and snaps a requested interval onto a slider stop', () {
    expect(PollCadence.clampMinutes(1), PollCadence.minRefreshMinutes);
    expect(PollCadence.clampMinutes(30), 30);
    expect(PollCadence.clampMinutes(600), PollCadence.maxRefreshMinutes);
    expect(PollCadence.clampMinutes(17), 15);
    expect(PollCadence.clampMinutes(18), 20);
    expect(PollCadence.clampMinutes(33), 30);
    expect(PollCadence.clampMinutes(35), 40);
    expect(PollCadence.clampMinutes(36), 40);
  });

  test('headless interval respects the Android 15-minute WorkManager floor', () {
    expect(PollCadence.headlessMinRefreshMinutes, 15);
    expect(
      PollCadence.headlessInterval(const Duration(minutes: 5)),
      const Duration(minutes: 15),
    );
    expect(
      PollCadence.headlessInterval(const Duration(minutes: 14)),
      const Duration(minutes: 15),
    );
    expect(
      PollCadence.headlessInterval(const Duration(minutes: 15)),
      const Duration(minutes: 15),
    );
    expect(
      PollCadence.headlessInterval(const Duration(minutes: 20)),
      const Duration(minutes: 20),
    );
    expect(
      PollCadence.headlessInterval(const Duration(minutes: 60)),
      const Duration(minutes: 60),
    );
  });
}

int _rustMinutes(String source, String constant) {
  final match = RegExp(
    '$constant: Duration = Duration::from_secs\\((\\d+) \\* 60\\);',
  ).firstMatch(source);
  expect(match, isNotNull, reason: 'whole-minute $constant not found in Rust');
  return int.parse(match!.group(1)!);
}

String _rustFreshnessNote(String source) {
  final match = RegExp(
    r'CURSOR_USAGE_FRESHNESS_NOTE: &str =\s*"([^"]*)";',
  ).firstMatch(source);
  expect(match, isNotNull, reason: 'freshness note not found in Rust');
  return match!.group(1)!;
}
