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

  test('clamps a requested interval into the slider range', () {
    expect(PollCadence.clampMinutes(1), PollCadence.minRefreshMinutes);
    expect(PollCadence.clampMinutes(30), 30);
    expect(PollCadence.clampMinutes(600), PollCadence.maxRefreshMinutes);
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
