import 'package:flutter_test/flutter_test.dart';
import 'package:ward_pulse_phone/dashboard/dashboard_models.dart';
import 'package:ward_pulse_phone/dashboard/plan_recoveries.dart';
import 'package:ward_pulse_phone/sync/recovery_notifications.dart';
import 'package:ward_pulse_phone/sync/recovery_watchlist.dart';

void main() {
  test('a phone that has never looked remembers nothing', () async {
    // Not an error state: the first poll is what fills the list, and until then
    // there is no past for an edge to be measured against.
    expect(await const DisabledRecoveryWatchlistStore().read(), isEmpty);
  });

  test('demo data is remembered as nothing at all', () async {
    final store = _MemoryRecoveryWatchlistStore();
    await store.write(const [
      (accountId: 'claude-local', allowanceId: 'claude-weekly'),
    ]);

    // Demo windows are invented: left in the list, they would make the first
    // live poll after leaving demo mode look like a recovery. The snapshot
    // below is never read, because demo mode short-circuits before the core is
    // asked anything.
    await syncPlanRecoveries(
      DashboardSnapshot.empty(generatedAt: DateTime.utc(2026, 8, 17)),
      store,
      const SilentRecoveryNotifier(),
      mockData: true,
    );

    expect(await store.read(), isEmpty);
  });

  test('a later look replaces the list rather than adding to it', () async {
    final store = _MemoryRecoveryWatchlistStore();
    await store.write(const [
      (accountId: 'claude-local', allowanceId: 'claude-weekly'),
    ]);

    // The weekly window refilled and the session one ran out. What is spent now
    // is the whole answer, not a running tally.
    await syncPlanRecoveries(
      DashboardSnapshot.empty(generatedAt: DateTime.utc(2026, 8, 17)),
      store,
      const SilentRecoveryNotifier(),
      readRecoveries: (_, _) => const [],
      readWindows:
          (_) => const [
            (accountId: 'claude-local', allowanceId: 'claude-session'),
          ],
    );

    expect(await store.read(), const [
      (accountId: 'claude-local', allowanceId: 'claude-session'),
    ]);
  });

  test('a window that came back is reported, then forgotten', () async {
    final store = _MemoryRecoveryWatchlistStore();
    await store.write(const [
      (accountId: 'claude-local', allowanceId: 'claude-weekly'),
    ]);
    final notifier = _RecordingRecoveryNotifier();

    await syncPlanRecoveries(
      DashboardSnapshot.empty(generatedAt: DateTime.utc(2026, 8, 17)),
      store,
      notifier,
      readRecoveries:
          (_, exhausted) => [
            for (final key in exhausted)
              (
                accountId: key.accountId,
                allowanceId: key.allowanceId,
                label: 'Weekly plan',
                resetsAt: DateTime.utc(2026, 8, 18),
              ),
          ],
      readWindows: (_) => const [],
    );

    expect(notifier.reported.single.label, 'Weekly plan');
    // Reported first, remembered second: an empty snapshot leaves nothing spent.
    expect(await store.read(), isEmpty);
  });

  test('a notifier that refuses one window does not stop the rest', () async {
    final store = _MemoryRecoveryWatchlistStore();
    await store.write(const [
      (accountId: 'claude-local', allowanceId: 'claude-weekly'),
      (accountId: 'claude-local', allowanceId: 'claude-session'),
    ]);
    final notifier = _RecordingRecoveryNotifier(refuse: 'claude-weekly');

    await syncPlanRecoveries(
      DashboardSnapshot.empty(generatedAt: DateTime.utc(2026, 8, 17)),
      store,
      notifier,
      readRecoveries:
          (_, exhausted) => [
            for (final key in exhausted)
              (
                accountId: key.accountId,
                allowanceId: key.allowanceId,
                label: key.allowanceId,
                resetsAt: null,
              ),
          ],
      readWindows: (_) => const [],
    );

    // The second window is still told, and the list still moves on — otherwise
    // a stuck list would go on missing every window exhausted after it.
    expect(notifier.reported.single.allowanceId, 'claude-session');
    expect(await store.read(), isEmpty);
  });

  test('with nothing remembered the core is not even asked', () async {
    final store = _MemoryRecoveryWatchlistStore();
    final notifier = _RecordingRecoveryNotifier();
    var asked = false;

    await syncPlanRecoveries(
      DashboardSnapshot.empty(generatedAt: DateTime.utc(2026, 8, 17)),
      store,
      notifier,
      readRecoveries: (_, _) {
        asked = true;
        return const [];
      },
      readWindows: (_) => const [],
    );

    // No past, no edge — and no snapshot serialized across the FFI boundary to
    // be told so, which is most polls.
    expect(asked, isFalse);
    expect(notifier.reported, isEmpty);
  });
}

class _MemoryRecoveryWatchlistStore implements RecoveryWatchlistStore {
  List<WindowKey> _keys = const [];

  @override
  Future<List<WindowKey>> read() async => _keys;

  @override
  Future<void> write(List<WindowKey> keys) async => _keys = keys;
}

class _RecordingRecoveryNotifier implements RecoveryNotifier {
  _RecordingRecoveryNotifier({this.refuse});

  /// Allowance id this notifier throws on, standing in for a platform that
  /// refuses to post — a revoked permission, say.
  final String? refuse;

  final reported = <PlanRecovery>[];

  @override
  Future<void> notify(PlanRecovery recovery) async {
    if (recovery.allowanceId == refuse) {
      throw StateError('nowhere to post ${recovery.allowanceId}');
    }
    reported.add(recovery);
  }
}
