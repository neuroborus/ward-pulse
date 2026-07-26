import 'package:flutter_test/flutter_test.dart';
import 'package:ward_pulse_phone/sync/manual_refresh_window.dart';

void main() {
  final lastSync = DateTime.utc(2026, 6, 27, 18, 42);

  test('allows refresh when the PollCadence floor has elapsed', () {
    final window = ManualRefreshWindow.fromLastSync(
      lastSyncAt: lastSync,
      now: lastSync.add(ManualRefreshWindow.floor),
    );

    expect(window.allowed, isTrue);
    expect(window.availableAt, isNull);
  });

  test('blocks refresh and reports availableAt during the floor window', () {
    final window = ManualRefreshWindow.fromLastSync(
      lastSyncAt: lastSync,
      now: lastSync.add(const Duration(minutes: 2)),
    );

    expect(window.allowed, isFalse);
    expect(window.availableAt, lastSync.add(ManualRefreshWindow.floor));
  });
}
