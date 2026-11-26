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

  test('a report dated after the clock anchors only owned attempts', () {
    final now = lastSync.add(const Duration(minutes: 1));
    final rolledBack = now.add(const Duration(hours: 1));
    final attempt = now.subtract(const Duration(minutes: 10));

    expect(
      ManualRefreshWindow.anchorAt(reportAt: rolledBack, now: now),
      ManualRefreshWindow.open,
    );
    expect(
      ManualRefreshWindow.anchorAt(
        reportAt: rolledBack,
        attempts: [null, attempt],
        now: now,
      ),
      attempt,
    );
    expect(
      ManualRefreshWindow.anchorAt(
        reportAt: lastSync,
        attempts: [attempt],
        now: now,
      ),
      lastSync,
    );
    expect(
      ManualRefreshWindow.fromLastSync(
        lastSyncAt: ManualRefreshWindow.open,
        now: now,
      ).allowed,
      isTrue,
    );
  });
}
