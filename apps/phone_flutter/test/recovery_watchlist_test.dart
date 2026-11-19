import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ward_pulse_phone/dashboard/dashboard_models.dart';
import 'package:ward_pulse_phone/dashboard/plan_recoveries.dart';
import 'package:ward_pulse_phone/sync/recovery_notifications.dart';
import 'package:ward_pulse_phone/settings/watch_ring_preferences.dart';
import 'package:ward_pulse_phone/sync/poll_cadence.dart';
import 'package:ward_pulse_phone/sync/recovery_wake.dart';
import 'package:ward_pulse_phone/sync/watch_sync_service.dart';
import 'package:ward_pulse_phone/sync/recovery_watchlist.dart';
import 'package:ward_pulse_phone/sync/automatic_poll.dart';
import 'package:ward_pulse_phone/providers/connection_lifecycle.dart';

import 'connection_cache_test_support.dart' show FakeSecureStorage;

void main() {
  test(
    'reconciliation persists context only in observed partitions before reload',
    () async {
      final storage = FakeSecureStorage();
      final store = SecureRecoveryWatchlistStore(storage: storage);
      final at = DateTime.utc(2026, 11, 6);
      final version = CredentialVersion({
        'generation': '1',
        'revision': '1',
        'epoch': '0',
        'identity': 'owner-a',
        'committedConnection': 'accepted-a',
      });
      final owner = HistoryOwner.fromVersion('anthropic.plan', version)!;
      final key = (accountId: 'a', allowanceId: 'session', historyOwner: owner);
      const protectedKey = (
        accountId: 'b',
        allowanceId: 'weekly',
        historyOwner: HistoryOwner(connection: 'cursor.plan', identity: 'owner-b'),
      );
      const requirements = RecoveryRequirements(
        allowanceIds: ['session', 'weekly'],
        complete: false,
      );
      const protectedRequirements = RecoveryRequirements(
        allowanceIds: ['weekly'],
        complete: true,
      );
      await store.writeObserved(
        [key, protectedKey],
        {owner, protectedKey.historyOwner},
        resets: {key: at.add(const Duration(minutes: 10))},
        requirements: {protectedKey: protectedRequirements},
      );
      final source = DashboardSnapshot.fromJsonString(
        File(
          '../../fixtures/snapshots/dashboard_today.json',
        ).readAsStringSync(),
      );
      final snapshot = DashboardSnapshot.fromJson({
        ...source.toJson(),
        'accounts': [
          {
            ...source.accounts.first.toJson(),
            'accountId': 'a',
            'connection': owner.connection,
            'historyOwner': owner.toJson(),
          },
        ],
      }).withConnectionVersions({owner.connection: version.values});
      var calls = 0;
      await syncPlanRecoveries(
        snapshot,
        store,
        const SilentRecoveryNotifier(),
        _RecordingWake(),
        notifications: false,
        now: () => at,
        readWindows: (_) => [],
        reconcile: (observed, pending) {
          calls++;
          expect(pending.single.key, key);
          expect(observed.accounts.single.accountId, 'a');
          return (
            pending: [
              PendingRecovery(key, requirements: requirements),
              const PendingRecovery(protectedKey),
            ],
            recoveries: <PlanRecovery>[],
          );
        },
        rethrowFailures: true,
      );
      final restarted = SecureRecoveryWatchlistStore(storage: storage);
      final result = await restarted.readPendingOwners({
        owner,
        protectedKey.historyOwner,
      });
      expect(calls, 1);
      expect(result.pending.first.requirements!.toJson(), requirements.toJson());
      expect(
        result.pending.last.requirements!.toJson(),
        protectedRequirements.toJson(),
      );
      expect(result.resets[key], at.add(const Duration(minutes: 10)));
      final skipped =
          AutomaticPollContext()
            ..skipped[owner.connection] = AutomaticPollSkipped(
              owner.connection,
              version,
              at.add(const Duration(minutes: 20)),
            );
      await syncPlanRecoveries(
        snapshot,
        restarted,
        const SilentRecoveryNotifier(),
        _RecordingWake(),
        poll: skipped,
        now: () => at,
        readWindows: (_) => throw StateError('wholly skipped raw read'),
        reconcile: (_, _) => throw StateError('wholly skipped reconciliation'),
        rethrowFailures: true,
      );
      final unchanged = await restarted.readPendingOwners({owner});
      expect(
        unchanged.pending.single.requirements!.toJson(),
        requirements.toJson(),
      );
    },
  );

  test(
    'partial skips preserve remembered windows and denied reset rebooks its exact eligibility',
    () async {
      final at = DateTime.utc(2026, 11, 6);
      final source = _withAllowances(
        DashboardSnapshot.fromJsonString(
          File(
            '../../fixtures/snapshots/dashboard_today.json',
          ).readAsStringSync(),
        ),
        {'remembered-window': at.subtract(const Duration(minutes: 1))},
      );
      final account = source.accounts.first;
      final connection = account.connection ?? 'openai.plan';
      final key = (
        accountId: account.accountId,
        historyOwner: null,
        allowanceId: 'remembered-window',
      );
      const freshKey = (
        accountId: 'fresh-account',
        historyOwner: null,
        allowanceId: 'fresh-window',
      );
      final mixed = DashboardSnapshot.fromJson({
        ...source.toJson(),
        'accounts': [
          ...source.accounts.map((account) => account.toJson()),
          {
            ...account.toJson(),
            'accountId': freshKey.accountId,
            'connection': 'openai.platform',
            'provider': 'openai',
          },
        ],
      });
      final store = _MemoryRecoveryWatchlistStore();
      await store.write([key, freshKey]);
      final notifier = _RecordingRecoveryNotifier(), wake = _RecordingWake();
      final poll = AutomaticPollContext(
        origin: AutomaticPollOrigin.resetWake,
        readInterval: () async => const Duration(minutes: 60),
      );
      poll.skipped[connection] = AutomaticPollSkipped(
        connection,
        CredentialVersion({}),
        at.add(const Duration(minutes: 1)),
      );
      poll.retainedAccountIds[connection] = {account.accountId};
      poll.attempted.add('openai.platform');
      await syncPlanRecoveries(
        mixed,
        store,
        notifier,
        wake,
        poll: poll,
        now: () => at,
        readWindows: (_) => [],
        readRecoveries: (_, keys) {
          expect(keys, [freshKey]);
          return [
            (
              accountId: freshKey.accountId,
              historyOwner: null,
              provider: 'openai',
              allowanceId: freshKey.allowanceId,
              label: 'Fresh window',
              resetsAt: null,
            ),
          ];
        },
      );
      expect(await store.read(), [key]);
      expect(notifier.reported.single.accountId, freshKey.accountId);
      expect(wake.booked, [at.add(const Duration(minutes: 1))]);
      poll.attempted.clear();
      await syncPlanRecoveries(
        source,
        store,
        notifier,
        wake,
        poll: poll,
        now: () => at,
        readWindows:
            (_) => throw StateError('Skipped data supplies no evidence'),
        readRecoveries:
            (_, _) => throw StateError('Skipped data supplies no recovery'),
        rethrowFailures: true,
      );
      expect(await store.read(), [key]);
      expect(wake.cancelled, 0);
      expect(notifier.reported, hasLength(1));
      final bookings = wake.booked.length;
      await syncPlanRecoveries(
        source,
        store,
        notifier,
        wake,
        poll: poll,
        isCurrent: () async => false,
        rethrowFailures: true,
      );
      expect(await store.read(), [key]);
      expect(wake.booked, hasLength(bookings));
      final futureReset = at.add(const Duration(hours: 1));
      final future = _withAllowances(source, {
        'remembered-window': futureReset,
      });
      await syncPlanRecoveries(
        future,
        store,
        notifier,
        wake,
        poll: poll,
        now: () => at,
        readWindows:
            (_) => throw StateError('Skipped data supplies no evidence'),
        readRecoveries:
            (_, _) => throw StateError('Skipped data supplies no recovery'),
        rethrowFailures: true,
      );
      expect(wake.booked.last, futureReset);
    },
  );
  test(
    'reset wakes keep per-connection eligibility through denied and partial loads',
    () async {
      final start = DateTime.utc(2026, 11, 6);
      DateTime at(int minutes) => start.add(Duration(minutes: minutes));
      final source = DashboardSnapshot.fromJsonString(
        File(
          '../../fixtures/snapshots/dashboard_today.json',
        ).readAsStringSync(),
      );
      const a = 'anthropic.plan', b = 'anthropic.platform';
      const aKey = (
        accountId: 'account-a',
        allowanceId: 'window-a',
        historyOwner: null,
      );
      const bKey = (
        accountId: 'account-b',
        allowanceId: 'window-b',
        historyOwner: null,
      );
      Map<String, dynamic> account(
        WindowKey key,
        String connection, [
        DateTime? resetsAt,
      ]) => {
        ..._withAllowances(source, {
          if (resetsAt != null) key.allowanceId: resetsAt,
        }).accounts.single.toJson(),
        'accountId': key.accountId,
        'connection': connection,
      };
      DashboardSnapshot snapshot(List<Map<String, dynamic>> accounts) =>
          DashboardSnapshot.fromJson({
            ...source.toJson(),
            'accounts': accounts,
          });
      AutomaticPollContext hourly() => AutomaticPollContext(
        readInterval: () async => const Duration(minutes: 60),
      );
      // A started at 00:00; its periodic denial names the hourly due time.
      AutomaticPollContext deniedA() =>
          hourly()
            ..skipped[a] = AutomaticPollSkipped(
              a,
              CredentialVersion({}),
              at(60),
            )
            ..retainedAccountIds[a] = {aKey.accountId}
            ..automaticAt[a] = at(0);
      final retainedA = account(aKey, a, at(10));
      final store = _MemoryRecoveryWatchlistStore();
      final notifier = _RecordingRecoveryNotifier(), wake = _RecordingWake();
      await syncPlanRecoveries(
        snapshot([retainedA]),
        store,
        notifier,
        wake,
        poll:
            hourly()
              ..attempted.add(a)
              ..automaticAt[a] = at(0),
        now: () => at(0),
        readRecoveries: (_, _) => const [],
        readWindows: (_) => [aKey],
      );
      expect(wake.booked, [at(10)]);
      // Denied startup or periodic work makes no attempt for A, so neither it
      // nor a repeat may move A's wake to a floor counted from itself.
      for (final instant in [at(9), at(9).add(const Duration(seconds: 30))]) {
        await syncPlanRecoveries(
          snapshot([retainedA]),
          store,
          notifier,
          wake,
          poll: deniedA(),
          now: () => instant,
          readWindows:
              (_) => throw StateError('Skipped data supplies no evidence'),
          readRecoveries:
              (_, _) => throw StateError('Skipped data supplies no recovery'),
          rethrowFailures: true,
        );
      }
      expect(wake.booked, [at(10), at(10), at(10)]);
      expect(wake.cancelled, 0);
      expect(await store.read(), [aKey]);
      // B starts at 00:09 and its earlier spent window refilled: B's genuine
      // recovery is told and forgotten while A keeps its history and 00:10.
      await store.write([aKey, bKey]);
      await syncPlanRecoveries(
        snapshot([retainedA, account(bKey, b)]),
        store,
        notifier,
        wake,
        poll:
            deniedA()
              ..attempted.add(b)
              ..automaticAt[b] = at(9),
        now: () => at(9),
        readWindows: (_) => const [],
        readRecoveries: (_, keys) {
          expect(keys, [bKey]);
          return [
            (
              accountId: bKey.accountId,
              historyOwner: null,
              provider: 'claude',
              allowanceId: bKey.allowanceId,
              label: 'Window B',
              resetsAt: null,
            ),
          ];
        },
      );
      expect(notifier.reported.single.accountId, bKey.accountId);
      expect(await store.read(), [aKey]);
      expect(wake.booked.last, at(10));
      // B's own near reset still waits for B's floor; A's start lends it none.
      final fresh = _MemoryRecoveryWatchlistStore();
      await syncPlanRecoveries(
        snapshot([account(aKey, a), account(bKey, b, at(11))]),
        fresh,
        notifier,
        wake,
        poll:
            deniedA()
              ..attempted.add(b)
              ..automaticAt[b] = at(9),
        now: () => at(9),
        readRecoveries: (_, _) => const [],
        readWindows: (_) => [bKey],
      );
      expect(await fresh.read(), [bKey]);
      expect(wake.booked.last, at(14));
      // B starts at 00:12, so its own floor is 00:17.
      Future<void> partial(
        AutomaticPollContext poll,
        DateTime instant,
        Map<String, dynamic> cachedA, [
        DateTime? resetB,
      ]) async {
        await store.write([aKey]);
        await syncPlanRecoveries(
          snapshot([cachedA, account(bKey, b, resetB)]),
          store,
          notifier,
          wake,
          poll:
              poll
                ..attempted.add(b)
                ..automaticAt[b] = at(12),
          now: () => instant,
          readRecoveries: (_, _) => const [],
          readWindows: (_) => [if (resetB != null) bKey],
          rethrowFailures: true,
        );
      }

      // Android delayed A's 00:10 wake and nothing has served it, so neither
      // fresh B without a reset nor B's 00:30 reset may cancel or replace it.
      var cancels = wake.cancelled;
      await partial(deniedA(), at(12), retainedA);
      expect(wake.booked.last, at(12));
      await partial(deniedA(), at(12), retainedA, at(30));
      expect(wake.booked.last, at(12));
      expect(await store.read(), [bKey, aKey]);
      expect(wake.cancelled, cancels);
      // A start after the reset served it even though it failed, and so did a
      // manual success that left A's anchor alone: the old reset is no retry.
      final served = {
        ...retainedA,
        'lastSuccessfulSyncAt': at(11).toIso8601String(),
      };
      for (final (poll, cachedA) in [
        (deniedA()..automaticAt[a] = at(12), retainedA),
        (deniedA(), served),
      ]) {
        await partial(poll, at(14), cachedA, at(15));
        expect(wake.booked.last, at(17));
        final booked = wake.booked.length;
        await partial(poll, at(14), cachedA);
        expect(wake.booked, hasLength(booked));
        expect(wake.cancelled, ++cancels);
      }
      // A current A poll that still reads the past reset is provider lag.
      final booked = wake.booked.length;
      await store.write([aKey]);
      await syncPlanRecoveries(
        snapshot([retainedA]),
        store,
        notifier,
        wake,
        poll:
            hourly()
              ..attempted.add(a)
              ..automaticAt[a] = at(12),
        now: () => at(12),
        readRecoveries: (_, _) => const [],
        readWindows: (_) => [aKey],
      );
      expect(wake.booked, hasLength(booked));
      expect(wake.cancelled, ++cancels);
    },
  );
  for (final (name, startMinutes, successMinutes) in [
    (
      'own native start cancels a served qualified wake and retains history',
      12,
      0,
    ),
    ('own success cancels a served qualified wake and retains history', 0, 11),
  ]) {
    test(name, () async {
      final start = DateTime.utc(2026, 11, 6);
      final reset = start.add(const Duration(minutes: 10));
      const a = HistoryOwner(connection: 'anthropic.plan', identity: 'owner-a');
      const b = HistoryOwner(
        connection: 'anthropic.platform',
        identity: 'owner-b',
      );
      final versions = {
        for (final owner in [a, b])
          owner.connection: CredentialVersion({
            'generation': '1',
            'revision': '1',
            'epoch': '0',
            'identity': owner.identity,
            'committedConnection': 'accepted-${owner.identity}',
          }),
      };
      const key = (
        accountId: 'account-a',
        historyOwner: a,
        allowanceId: 'window-a',
      );
      final source = DashboardSnapshot.fromJsonString(
        File(
          '../../fixtures/snapshots/dashboard_today.json',
        ).readAsStringSync(),
      );
      final retainedA = {
        ..._withAllowances(source, {
          'window-a': reset,
        }).accounts.single.toJson(),
        'accountId': key.accountId,
        'connection': a.connection,
        'historyOwner': a.toJson(),
        'lastSuccessfulSyncAt': start.toIso8601String(),
      };
      final secure = FakeSecureStorage();
      final store = SecureRecoveryWatchlistStore(storage: secure);
      final notifier = _RecordingRecoveryNotifier(), wake = _RecordingWake();
      await syncPlanRecoveries(
        DashboardSnapshot.fromJson({
          ...source.toJson(),
          'accounts': [retainedA],
        }).withConnectionVersions({
          a.connection: versions[a.connection]!.values,
        }),
        store,
        notifier,
        wake,
        poll:
            AutomaticPollContext()
              ..attempted.add(a.connection)
              ..admittedVersions[a.connection] = versions[a.connection]!
              ..automaticAt[a.connection] = start,
        now: () => start,
        rethrowFailures: true,
      );
      final initialBookings = List<DateTime>.of(wake.booked);
      final initialHistory = await store.readOwners({a});
      await syncPlanRecoveries(
        DashboardSnapshot.fromJson({
          ...source.toJson(),
          'accounts': [
            {
              ...retainedA,
              'lastSuccessfulSyncAt':
                  start
                      .add(Duration(minutes: successMinutes))
                      .toIso8601String(),
            },
            {
              ..._withAllowances(source, {}).accounts.single.toJson(),
              'accountId': 'account-b',
              'connection': b.connection,
              'historyOwner': b.toJson(),
              'lastSuccessfulSyncAt':
                  start.add(const Duration(minutes: 14)).toIso8601String(),
            },
          ],
        }).withConnectionVersions({
          for (final entry in versions.entries) entry.key: entry.value.values,
        }),
        store,
        notifier,
        wake,
        poll:
            AutomaticPollContext()
              ..skipped[a.connection] = AutomaticPollSkipped(
                a.connection,
                versions[a.connection]!,
                start.add(Duration(minutes: startMinutes + 60)),
              )
              ..retainedAccountIds[a.connection] = {key.accountId}
              ..automaticAt[a.connection] = start.add(
                Duration(minutes: startMinutes),
              )
              ..attempted.add(b.connection)
              ..admittedVersions[b.connection] = versions[b.connection]!
              ..automaticAt[b.connection] = start.add(
                const Duration(minutes: 12),
              ),
        now: () => start.add(const Duration(minutes: 14)),
        rethrowFailures: true,
      );
      final cancellations = wake.cancelled;
      final bookings = List<DateTime>.of(wake.booked);
      final notifications = List<PlanRecovery>.of(notifier.reported);
      final persistedKeys = await store.read();
      final persistedHistory = await store.readOwners({a, b});
      final restarted = SecureRecoveryWatchlistStore(storage: secure);
      final restartedKeys = await restarted.read();
      final restartedHistory = await restarted.readOwners({a, b});

      expect(initialBookings, [reset]);
      expect(initialHistory.keys, [key]);
      expect(initialHistory.resets, {key: reset});
      expect(
        cancellations,
        1,
        reason: 'The obsolete reset wake must be cancelled',
      );
      expect(bookings, initialBookings);
      expect(notifications, isEmpty);
      expect(persistedKeys, [key]);
      expect(persistedHistory.keys, [key]);
      expect(persistedHistory.resets, {key: reset});
      expect(restartedKeys, [key]);
      expect(restartedHistory.keys, [key]);
      expect(restartedHistory.resets, {key: reset});
    });
  }
  test('a phone that has never looked remembers nothing', () async {
    // Not an error state: the first poll is what fills the list, and until then
    // there is no past for an edge to be measured against.
    expect(await const DisabledRecoveryWatchlistStore().read(), isEmpty);
  });

  test('demo data is remembered as nothing at all', () async {
    final store = _MemoryRecoveryWatchlistStore();
    await store.write(const [
      (
        accountId: 'claude-local',
        allowanceId: 'claude-weekly',
        historyOwner: null,
      ),
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
      (
        accountId: 'claude-local',
        allowanceId: 'claude-weekly',
        historyOwner: null,
      ),
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
            (
              accountId: 'claude-local',
              allowanceId: 'claude-session',
              historyOwner: null,
            ),
          ],
    );

    expect(await store.read(), const [
      (
        accountId: 'claude-local',
        allowanceId: 'claude-session',
        historyOwner: null,
      ),
    ]);
  });

  test('a window that came back is reported, then forgotten', () async {
    final store = _MemoryRecoveryWatchlistStore();
    await store.write(const [
      (
        accountId: 'claude-local',
        allowanceId: 'claude-weekly',
        historyOwner: null,
      ),
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
                historyOwner: null,
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
      (
        accountId: 'claude-local',
        allowanceId: 'claude-weekly',
        historyOwner: null,
      ),
      (
        accountId: 'claude-local',
        allowanceId: 'claude-session',
        historyOwner: null,
      ),
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
                historyOwner: null,
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
            (
              accountId: 'claude-local',
              allowanceId: 'weekly',
              historyOwner: null,
            ),
            (
              accountId: 'claude-local',
              allowanceId: 'session',
              historyOwner: null,
            ),
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
    const spent = [
      (accountId: 'claude-local', allowanceId: 'weekly', historyOwner: null),
    ];

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
          (_) => const [
            (
              accountId: 'claude-local',
              allowanceId: 'weekly',
              historyOwner: null,
            ),
          ],
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
          (_) => const [
            (
              accountId: 'claude-local',
              allowanceId: 'weekly',
              historyOwner: null,
            ),
          ],
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
          (_) => const [
            (
              accountId: 'claude-local',
              allowanceId: 'weekly',
              historyOwner: null,
            ),
          ],
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
      (accountId: 'claude-local', allowanceId: 'weekly', historyOwner: null),
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
              historyOwner: null,
              provider: 'claude',
              allowanceId: 'weekly',
              label: 'Weekly plan',
              resetsAt: null,
            ),
          ],
      readWindows:
          (_) => const [
            (
              accountId: 'claude-local',
              allowanceId: 'weekly',
              historyOwner: null,
            ),
          ],
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
      (accountId: 'claude-local', allowanceId: 'weekly', historyOwner: null),
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
              historyOwner: null,
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
