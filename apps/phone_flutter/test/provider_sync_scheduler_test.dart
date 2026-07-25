import 'package:flutter_test/flutter_test.dart';
import 'package:ward_pulse_phone/sync/provider_sync_scheduler.dart';

void main() {
  test('ticks repeatedly on the scheduled interval', () async {
    final scheduler = TimerProviderSyncScheduler();
    addTearDown(scheduler.cancel);

    final ticks = scheduler.ticks.take(2).toList();
    await scheduler.schedule(const Duration(milliseconds: 10));

    expect(await ticks, hasLength(2));
  });

  test('stops ticking once cancelled', () async {
    final scheduler = TimerProviderSyncScheduler();
    addTearDown(scheduler.cancel);

    var ticks = 0;
    scheduler.ticks.listen((_) => ticks++);
    await scheduler.schedule(const Duration(milliseconds: 10));
    await scheduler.cancel();
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(ticks, isZero);
  });

  test('does nothing while sync is disabled', () async {
    const scheduler = DisabledProviderSyncScheduler();

    await scheduler.schedule(const Duration(minutes: 5));

    await expectLater(scheduler.ticks.isEmpty, completion(isTrue));
  });
}
