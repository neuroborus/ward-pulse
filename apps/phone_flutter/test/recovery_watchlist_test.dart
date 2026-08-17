import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ward_pulse_phone/dashboard/dashboard_models.dart';
import 'package:ward_pulse_phone/dashboard/plan_recoveries.dart';
import 'package:ward_pulse_phone/sync/recovery_notifications.dart';
import 'package:ward_pulse_phone/settings/consumption_display_preferences.dart';
import 'package:ward_pulse_phone/settings/watch_ring_preferences.dart';
import 'package:ward_pulse_phone/sync/poll_cadence.dart';
import 'package:ward_pulse_phone/sync/recovery_wake.dart';
import 'package:ward_pulse_phone/sync/watch_sync_service.dart';
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
      const DisabledRecoveryWakeScheduler(),
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
      const DisabledRecoveryWakeScheduler(),
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
    final wake = _RecordingWake();

    await syncPlanRecoveries(
      DashboardSnapshot.empty(generatedAt: DateTime.utc(2026, 8, 17)),
      store,
      notifier,
      wake,
      readRecoveries:
          (_, exhausted) => [
            for (final key in exhausted)
              (
                accountId: key.accountId,
                provider: 'claude',
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
    final wake = _RecordingWake();

    await syncPlanRecoveries(
      DashboardSnapshot.empty(generatedAt: DateTime.utc(2026, 8, 17)),
      store,
      notifier,
      wake,
      readRecoveries:
          (_, exhausted) => [
            for (final key in exhausted)
              (
                accountId: key.accountId,
                provider: 'claude',
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

  test('the wake is booked for the soonest window still spent', () async {
    final source = DashboardSnapshot.fromJsonString(
      File('../../fixtures/snapshots/dashboard_today.json').readAsStringSync(),
    );
    final snapshot = _withAllowances(source, {
      'weekly': DateTime.utc(2026, 8, 18, 9),
      'session': DateTime.utc(2026, 8, 17, 14),
    });
    final store = _MemoryRecoveryWatchlistStore();
    final wake = _RecordingWake();

    await syncPlanRecoveries(
      snapshot,
      store,
      const SilentRecoveryNotifier(),
      wake,
      readRecoveries: (_, _) => const [],
      readWindows:
          (_) => const [
            (accountId: 'claude-local', allowanceId: 'weekly'),
            (accountId: 'claude-local', allowanceId: 'session'),
          ],
      // Pinned, or the wall clock decides the answer: both instants have to be
      // ahead for "the soonest" to mean anything.
      now: () => DateTime.utc(2026, 8, 17, 12),
    );

    // Two windows are spent; one wake is enough, because the poll it starts
    // looks at both. The earlier instant is the one worth booking.
    expect(wake.booked, [DateTime.utc(2026, 8, 17, 14)]);
    expect(wake.cancelled, 0);
  });

  test('a window whose reset moves gets the wake booked again', () async {
    final source = DashboardSnapshot.fromJsonString(
      File('../../fixtures/snapshots/dashboard_today.json').readAsStringSync(),
    );
    final store = _MemoryRecoveryWatchlistStore();
    final wake = _RecordingWake();
    const spent = [(accountId: 'claude-local', allowanceId: 'weekly')];

    // Pinned: these instants are only "ahead" until the day they are not, and
    // a test that rots with the calendar is a test nobody trusts.
    final rightNow = DateTime.utc(2026, 8, 17, 12);
    Future<void> pollWithReset(DateTime resetsAt) => syncPlanRecoveries(
      _withAllowances(source, {'weekly': resetsAt}),
      store,
      const SilentRecoveryNotifier(),
      wake,
      readRecoveries: (_, _) => const [],
      readWindows: (_) => spent,
      now: () => rightNow,
    );

    await pollWithReset(DateTime.utc(2026, 8, 18, 9));
    await pollWithReset(DateTime.utc(2026, 8, 18, 15));

    // The provider moved the window; the booking follows it. On the platform
    // side this is what `ExistingWorkPolicy.replace` is for — the default would
    // keep the first instant and the reader would be woken too early.
    expect(wake.booked, [
      DateTime.utc(2026, 8, 18, 9),
      DateTime.utc(2026, 8, 18, 15),
    ]);
  });

  test('a wake never lands sooner than the poll floor', () async {
    final source = DashboardSnapshot.fromJsonString(
      File('../../fixtures/snapshots/dashboard_today.json').readAsStringSync(),
    );
    final wake = _RecordingWake();
    final rightNow = DateTime.utc(2026, 8, 17, 12);

    await syncPlanRecoveries(
      // The window rolls in a minute, well inside the floor.
      _withAllowances(source, {
        'weekly': rightNow.add(const Duration(minutes: 1)),
      }),
      _MemoryRecoveryWatchlistStore(),
      const SilentRecoveryNotifier(),
      wake,
      readRecoveries: (_, _) => const [],
      readWindows:
          (_) => const [(accountId: 'claude-local', allowanceId: 'weekly')],
      now: () => rightNow,
    );

    // Waking on the instant would put two polls a minute apart, and the floor
    // is the strictest a connection allows — a recovery is not an exemption.
    expect(wake.booked, [
      rightNow.add(const Duration(minutes: PollCadence.minRefreshMinutes)),
    ]);
  });

  test('a reset the provider has not caught up to books nothing', () async {
    final source = DashboardSnapshot.fromJsonString(
      File('../../fixtures/snapshots/dashboard_today.json').readAsStringSync(),
    );
    final wake = _RecordingWake();
    final rightNow = DateTime.utc(2026, 8, 17, 12);

    await syncPlanRecoveries(
      // The window says it rolled an hour ago and still reads spent, which is
      // what a provider aggregating hourly looks like.
      _withAllowances(source, {
        'weekly': rightNow.subtract(const Duration(hours: 1)),
      }),
      _MemoryRecoveryWatchlistStore(),
      const SilentRecoveryNotifier(),
      wake,
      readRecoveries: (_, _) => const [],
      readWindows:
          (_) => const [(accountId: 'claude-local', allowanceId: 'weekly')],
      now: () => rightNow,
    );

    // Booking here would wake, see the same thing, and book again — a
    // five-minute loop for as long as the provider lags. The cadence covers it.
    expect(wake.booked, isEmpty);
    expect(wake.cancelled, 1);
  });

  test('a reset the provider has not caught up to books nothing', () async {
    final source = DashboardSnapshot.fromJsonString(
      File('../../fixtures/snapshots/dashboard_today.json').readAsStringSync(),
    );
    final wake = _RecordingWake();
    final rightNow = DateTime.utc(2026, 8, 17, 12);

    await syncPlanRecoveries(
      // The window says it rolled an hour ago and still reads spent, which is
      // what a provider aggregating hourly looks like.
      _withAllowances(source, {
        'weekly': rightNow.subtract(const Duration(hours: 1)),
      }),
      _MemoryRecoveryWatchlistStore(),
      const SilentRecoveryNotifier(),
      wake,
      readRecoveries: (_, _) => const [],
      readWindows:
          (_) => const [(accountId: 'claude-local', allowanceId: 'weekly')],
      now: () => rightNow,
    );

    // Booking here would wake, see the same thing, and book again — a
    // five-minute loop for as long as the provider lags. The cadence covers it.
    expect(wake.booked, isEmpty);
    expect(wake.cancelled, 1);
  });

  test('the switch silences the telling, not the watching', () async {
    final source = DashboardSnapshot.fromJsonString(
      File('../../fixtures/snapshots/dashboard_today.json').readAsStringSync(),
    );
    final store = _MemoryRecoveryWatchlistStore();
    await store.write(const [
      (accountId: 'claude-local', allowanceId: 'weekly'),
    ]);
    final notifier = _RecordingRecoveryNotifier();
    final wake = _RecordingWake();
    final rightNow = DateTime.utc(2026, 8, 17, 12);
    final resetsAt = rightNow.add(const Duration(hours: 3));

    await syncPlanRecoveries(
      _withAllowances(source, {'weekly': resetsAt}),
      store,
      notifier,
      wake,
      notifications: false,
      readRecoveries:
          (_, _) => const [
            (
              accountId: 'claude-local',
              provider: 'claude',
              allowanceId: 'weekly',
              label: 'Weekly plan',
              resetsAt: null,
            ),
          ],
      readWindows:
          (_) => const [(accountId: 'claude-local', allowanceId: 'weekly')],
      now: () => rightNow,
    );

    // Nothing is said, and everything else carries on: the list moves and the
    // wake is booked, so turning the switch back on picks up where it was.
    expect(notifier.reported, isEmpty);
    expect(await store.read(), hasLength(1));
    expect(wake.booked, [resetsAt]);
  });

  test('nothing spent takes the wake off the books', () async {
    final store = _MemoryRecoveryWatchlistStore();
    final wake = _RecordingWake();

    await syncPlanRecoveries(
      DashboardSnapshot.empty(generatedAt: DateTime.utc(2026, 8, 17)),
      store,
      const SilentRecoveryNotifier(),
      wake,
      readRecoveries: (_, _) => const [],
      readWindows: (_) => const [],
    );

    expect(wake.booked, isEmpty);
    expect(wake.cancelled, 1);
  });

  test('a reported recovery adds nothing to alerts, phone or watch', () async {
    final source = DashboardSnapshot.fromJsonString(
      File('../../fixtures/snapshots/dashboard_today.json').readAsStringSync(),
    );
    final snapshot = _withAllowances(source, {
      'weekly': DateTime.utc(2026, 8, 18, 9),
    });
    final store = _MemoryRecoveryWatchlistStore();
    await store.write(const [
      (accountId: 'claude-local', allowanceId: 'weekly'),
    ]);
    final notifier = _RecordingRecoveryNotifier();

    await syncPlanRecoveries(
      snapshot,
      store,
      notifier,
      _RecordingWake(),
      readRecoveries:
          (_, _) => const [
            (
              accountId: 'claude-local',
              provider: 'claude',
              allowanceId: 'weekly',
              label: 'Weekly plan',
              resetsAt: null,
            ),
          ],
      readWindows: (_) => const [],
    );

    // A recovery is an edge, not a condition: it is told once and leaves no
    // standing state behind. An alert would be listed on the Dashboard and
    // counted on the watch, and this one is neither.
    expect(notifier.reported, hasLength(1));
    expect(snapshot.alerts, isEmpty);
    expect(
      WatchDashboardSummaryPayload.fromSnapshot(
        snapshot,
        const ConsumptionDisplayPreferences(),
        const WatchRingPreferences(),
      ).encode(),
      contains('"alerts":[]'),
    );
  });

  test('with nothing remembered the core is not even asked', () async {
    final store = _MemoryRecoveryWatchlistStore();
    final notifier = _RecordingRecoveryNotifier();
    final wake = _RecordingWake();
    var asked = false;

    await syncPlanRecoveries(
      DashboardSnapshot.empty(generatedAt: DateTime.utc(2026, 8, 17)),
      store,
      notifier,
      wake,
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

  @override
  Future<bool> requestPermission() async => true;
}

class _RecordingWake implements RecoveryWakeScheduler {
  final booked = <DateTime>[];
  var cancelled = 0;

  @override
  Future<void> scheduleAt(DateTime resetsAt) async => booked.add(resetsAt);

  @override
  Future<void> cancel() async => cancelled++;
}

/// The golden snapshot with one account whose windows reset at [resets].
DashboardSnapshot _withAllowances(
  DashboardSnapshot source,
  Map<String, DateTime> resets,
) {
  return DashboardSnapshot.fromJson({
    ...source.toJson(),
    'accounts': [
      {
        ...source.primaryAccount!.toJson(),
        'accountId': 'claude-local',
        'provider': 'claude',
        'allowances': [
          for (final entry in resets.entries)
            {
              'id': entry.key,
              'source': 'plan',
              'label': entry.key,
              'usedPercent': 100.0,
              'used': null,
              'limit': null,
              'remaining': null,
              'windowMinutes': null,
              'resetsAt': entry.value.toIso8601String(),
              'status': 'warning',
            },
        ],
        'buckets': <Object>[],
        'modelBreakdown': <Object>[],
      },
    ],
  });
}
