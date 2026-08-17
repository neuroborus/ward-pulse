import 'package:flutter_test/flutter_test.dart';
import 'package:ward_pulse_phone/dashboard/dashboard_models.dart';
import 'package:ward_pulse_phone/dashboard/plan_recoveries.dart';
import 'package:ward_pulse_phone/sync/recovery_watchlist.dart';

void main() {
  test('a phone that has never looked remembers nothing', () async {
    // Not an error state: the first poll is what fills the list, and until then
    // there is no past for an edge to be measured against.
    expect(await const DisabledRecoveryWatchlistStore().read(), isEmpty);
  });

  test('what was written comes back, in order', () async {
    final store = _MemoryRecoveryWatchlistStore();
    const keys = [
      (accountId: 'claude-local', allowanceId: 'claude-weekly'),
      (accountId: 'claude-local', allowanceId: 'claude-session'),
    ];

    await store.write(keys);

    expect(await store.read(), keys);
  });

  test('demo data is remembered as nothing at all', () async {
    final store = _MemoryRecoveryWatchlistStore();
    await store.write(const [
      (accountId: 'claude-local', allowanceId: 'claude-weekly'),
    ]);

    // Demo windows are invented. Left in the list, they would make the first
    // live poll after leaving demo mode look like a recovery.
    // The snapshot is never read: demo mode short-circuits before the core is
    // asked anything.
    await rememberExhaustedWindows(
      DashboardSnapshot.empty(generatedAt: DateTime.utc(2026, 8, 17)),
      store,
      mockData: true,
    );

    expect(await store.read(), isEmpty);
  });

  test('a later look replaces the list rather than adding to it', () async {
    final store = _MemoryRecoveryWatchlistStore();
    await store.write(const [
      (accountId: 'claude-local', allowanceId: 'claude-weekly'),
    ]);

    // The weekly window refilled and the session one ran out: what is spent now
    // is the whole answer, not a running tally.
    await store.write(const [
      (accountId: 'claude-local', allowanceId: 'claude-session'),
    ]);

    expect(await store.read(), const [
      (accountId: 'claude-local', allowanceId: 'claude-session'),
    ]);
  });
}

class _MemoryRecoveryWatchlistStore implements RecoveryWatchlistStore {
  List<WindowKey> _keys = const [];

  @override
  Future<List<WindowKey>> read() async => _keys;

  @override
  Future<void> write(List<WindowKey> keys) async => _keys = keys;
}
