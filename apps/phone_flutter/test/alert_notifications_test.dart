import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:ward_pulse_phone/dashboard/dashboard_models.dart';
import 'package:ward_pulse_phone/settings/alert_notification_preferences.dart';
import 'package:ward_pulse_phone/settings/recovery_notification_preferences.dart';
import 'package:ward_pulse_phone/sync/alert_notifications.dart';

import 'connection_cache_test_support.dart';

const _key = AlertConditionKey(
  provider: 'claude',
  accountId: 'private-account-a',
  connection: 'anthropic.plan',
  target: AllowanceAlertTarget(source: AllowanceSource.plan, id: 'window-a'),
);
const _other = AlertConditionKey(
  provider: 'claude',
  accountId: 'private-account-a',
  connection: 'anthropic.plan',
  target: BudgetAlertTarget(period: AlertBudgetPeriod.today),
);
const _crossed = AlertCondition.crossed(
  key: _key,
  alert: AlertSummary(severity: 'warning', message: 'Raw error/spend copy'),
);
const _clear = AlertCondition.clear(key: _key);
const _unknown = AlertCondition.unknown(key: _key);

DashboardSnapshot _snapshot(
  List<AlertCondition> conditions,
) => DashboardSnapshot.fromJson({
  ...DashboardSnapshot.empty(generatedAt: DateTime.utc(2026, 11, 2)).toJson(),
  'alertConditions': conditions.map((condition) => condition.toJson()).toList(),
});

void main() {
  test(
    'secure choices and per-condition consumed markers survive new adapters',
    () async {
      final storage = FakeSecureStorage();
      final preference = SecureAlertNotificationPreferenceStore(
        storage: storage,
      );
      final recovery = SecureRecoveryNotificationPreferenceStore(
        storage: storage,
      );
      expect(await preference.read(), isTrue);
      await recovery.write(false);
      await preference.write(false);
      expect(
        await SecureAlertNotificationPreferenceStore(storage: storage).read(),
        isFalse,
      );
      await preference.write(true);
      expect(await recovery.read(), isFalse);
      final markers = SecureAlertConditionStore(storage: storage);
      await markers.write(_key, true);
      await markers.write(_other, true);
      final restarted = SecureAlertConditionStore(storage: storage);
      expect(await restarted.read(_key), isTrue);
      await restarted.write(_key, false);
      expect(await markers.read(_key), isFalse);
      expect(await markers.read(_other), isTrue);
      expect(storage.values.keys.join(), isNot(contains(_key.accountId)));
      final saved = Map.of(storage.values);
      storage.failRead = true;
      await expectLater(preference.read(), throwsStateError);
      expect(storage.values, saved);
    },
  );

  test(
    'unchanged crossings suppress callbacks; only positive clear rearms',
    () async {
      final store = _Conditions();
      final notifier = _Notifier();
      final preferences = _Preferences();
      AlertNotificationDelivery delivery() => AlertNotificationDelivery(
        preferences: preferences,
        conditions: store,
        notifier: notifier,
      );
      await delivery().sync(_snapshot([_clear]));
      await delivery().sync(_snapshot([_crossed]));
      await delivery().sync(_snapshot([_crossed, _unknown]));
      await delivery().sync(
        _snapshot([]),
      ); // Disabled/missing observations retain history.
      await delivery().sync(
        _snapshot([
          const AlertCondition.crossed(
            key: _key,
            alert: AlertSummary(severity: 'warning', message: 'Renamed window'),
          ),
        ]),
      ); // Rule/label edits retain the same structural identity.
      expect(notifier.posts, [_key]);
      await delivery().sync(_snapshot([_clear]));
      await delivery().sync(_snapshot([_crossed]));
      expect(notifier.posts, [_key, _key]);
      expect(notifier.titles, everyElement('Claude · Plan window'));
      expect(notifier.titles.join(), isNot(contains(_key.accountId)));
      expect(notifier.titles.join(), isNot(contains(_crossed.alert!.message)));
      expect(
        alertNotificationTag(_key),
        alertNotificationTag(AlertConditionKey.fromJson(_key.toJson())),
      );
      expect(alertNotificationTag(_key), isNot(alertNotificationTag(_other)));
      expect(alertNotificationBody, 'Reached your alert threshold.');
      expect(
        alertNotificationTag(_key),
        'wardpulse.alert.6734e09933085fe53344ed7272cadde9adb0682d3fd8d9c19b039d3e7cd85a5c',
      );
    },
  );

  test(
    'provider status and displayed errors alone never create posts',
    () async {
      final store = _Conditions();
      final notifier = _Notifier();
      await AlertNotificationDelivery(
        preferences: _Preferences(),
        conditions: store,
        notifier: notifier,
      ).sync(
        DashboardSnapshot.fromJson({
          ...DashboardSnapshot.empty().toJson(),
          'overallStatus': 'error',
          'alerts': [
            {'severity': 'error', 'message': 'Provider unavailable'},
          ],
        }),
      );
      expect(store.reads, 0);
      expect(store.writes, 0);
      expect(notifier.posts, isEmpty);
    },
  );

  test('window copy prefers the exact connection over a legacy sibling', () {
    final empty = DashboardSnapshot.empty();
    ProviderSnapshot account(String? connection, String label) =>
        ProviderSnapshot(
          accountId: _key.accountId,
          provider: _key.provider,
          connection: connection,
          status: ProviderStatus.ok,
          today: empty.todayTotal,
          week: empty.weekTotal,
          month: empty.monthTotal,
          credits: const [],
          buckets: const [],
          modelBreakdown: const [],
          lastSuccessfulSyncAt: null,
          allowances: [
            AllowanceState(
              id: 'window-a',
              source: AllowanceSource.plan,
              label: label,
              usedPercent: 80,
              used: null,
              limit: null,
              remaining: null,
              windowMinutes: null,
              resetsAt: null,
              status: ProviderStatus.warning,
            ),
          ],
        );
    final exact = account('other-connection', 'Weekly plan');
    final legacy = account(null, 'Legacy window');
    final snapshot = DashboardSnapshot.fromJson({
      ...empty.toJson(),
      'accounts': [exact.toJson(), legacy.toJson()],
    });
    final exactKey = AlertConditionKey(
      provider: _key.provider,
      accountId: _key.accountId,
      connection: 'other-connection',
      target: _key.target,
    );
    expect(alertNotificationTitle(snapshot, exactKey), 'Claude · Weekly plan');
    expect(alertNotificationTitle(snapshot, _key), 'Claude · Legacy window');
  });

  for (final mode in ['muted', 'denied', 'preference failure']) {
    test('$mode consumes a crossing without later backlog', () async {
      final preferences =
          _Preferences()
            ..enabled = mode != 'muted'
            ..failRead = mode == 'preference failure';
      final notifier = _Notifier()..allowed = mode != 'denied';
      final delivery = AlertNotificationDelivery(
        preferences: preferences,
        conditions: _Conditions(),
        notifier: notifier,
      );
      await delivery.sync(_snapshot([_crossed]));
      expect(notifier.posts, isEmpty);
      preferences
        ..enabled = true
        ..failRead = false;
      notifier.allowed = true;
      await delivery.sync(_snapshot([_crossed]));
      expect(notifier.posts, isEmpty);
      await delivery.sync(_snapshot([_clear]));
      await delivery.sync(_snapshot([_crossed]));
      expect(notifier.posts, [_key]);
      expect(notifier.asked, 0);
    });
  }

  for (final failRead in [true, false]) {
    test(
      'failed ${failRead ? 'read' : 'claim'} isolates one condition and can retry',
      () async {
        final store = _Conditions();
        (failRead ? store.failReads : store.failWrites).add(_key);
        final notifier = _Notifier();
        final delivery = AlertNotificationDelivery(
          preferences: _Preferences(),
          conditions: store,
          notifier: notifier,
        );
        const second = AlertCondition.crossed(
          key: _other,
          alert: AlertSummary(severity: 'warning', message: 'Same copy'),
        );
        await delivery.sync(_snapshot([_crossed, second]));
        expect(notifier.posts, [_other]);
        store.failReads.clear();
        store.failWrites.clear();
        await delivery.sync(_snapshot([_crossed, second]));
        expect(notifier.posts, [_other, _key]);
      },
    );
  }

  test('a plugin failure after claim is not retried until clear', () async {
    final notifier = _Notifier()..failPost = true;
    final delivery = AlertNotificationDelivery(
      preferences: _Preferences(),
      conditions: _Conditions(),
      notifier: notifier,
    );
    await delivery.sync(_snapshot([_crossed]));
    notifier.failPost = false;
    await delivery.sync(_snapshot([_crossed]));
    expect(notifier.posts, isEmpty);
    await delivery.sync(_snapshot([_clear]));
    await delivery.sync(_snapshot([_crossed]));
    expect(notifier.posts, [_key]);
  });

  test('mock data never reads or changes production markers', () async {
    final store = _Conditions()..values[_key] = true;
    final notifier = _Notifier();
    final delivery = AlertNotificationDelivery(
      preferences: _Preferences(),
      conditions: store,
      notifier: notifier,
    );
    await delivery.sync(_snapshot([_clear]), mockData: true);
    await delivery.sync(_snapshot([_crossed]), mockData: true);
    expect(store.reads, 0);
    expect(store.writes, 0);
    expect(store.values, {_key: true});
    expect(notifier.posts, isEmpty);
  });

  test(
    'retired rules or ownership after a read cannot consume the crossing',
    () async {
      var current = true;
      final store = _Conditions()..afterRead = () => current = false;
      final notifier = _Notifier();
      await AlertNotificationDelivery(
        preferences: _Preferences(),
        conditions: store,
        notifier: notifier,
      ).sync(_snapshot([_crossed]), isCurrent: () async => current);
      expect(store.values, isEmpty);
      expect(notifier.posts, isEmpty);
    },
  );

  test(
    'ownership and delivery choice are checked again after bookkeeping',
    () async {
      for (final retire in [false, true]) {
        var current = true;
        final preferences = _Preferences();
        final store =
            _Conditions()
              ..beforeWrite = (_, _) async {
                if (retire) {
                  current = false;
                } else {
                  preferences.enabled = false;
                }
              };
        final notifier = _Notifier();
        await AlertNotificationDelivery(
          preferences: preferences,
          conditions: store,
          notifier: notifier,
        ).sync(_snapshot([_crossed]), isCurrent: () async => current);
        expect(store.values[_key], isTrue);
        expect(notifier.posts, isEmpty);
      }
    },
  );

  test('separate service instances serialize within one isolate', () async {
    final entered = Completer<void>();
    final release = Completer<void>();
    final store =
        _Conditions()
          ..beforeWrite = (_, _) async {
            if (!entered.isCompleted) entered.complete();
            await release.future;
          };
    final notifier = _Notifier();
    AlertNotificationDelivery delivery() => AlertNotificationDelivery(
      preferences: _Preferences(),
      conditions: store,
      notifier: notifier,
    );
    final first = delivery().sync(_snapshot([_crossed]));
    await entered.future;
    final second = delivery().sync(_snapshot([_crossed]));
    release.complete();
    await Future.wait([first, second]);
    expect(notifier.posts, [_key]);
  });
  test(
    'accepted identity is checked after the final preference await',
    () async {
      var accepted = true;
      final preferences =
          _Preferences()
            ..beforeRead = () async {
              accepted = false;
            };
      final notifier = _Notifier();
      await AlertNotificationDelivery(
        preferences: preferences,
        conditions: _Conditions(),
        notifier: notifier,
      ).sync(_snapshot([_crossed]), isAccepted: () => accepted);
      expect(notifier.posts, isEmpty);
    },
  );
}

class _Preferences implements AlertNotificationPreferenceStore {
  bool enabled = true;
  bool failRead = false;
  Future<void> Function()? beforeRead;
  @override
  Future<bool> read() async {
    await beforeRead?.call();
    if (failRead) throw StateError('Preference unavailable.');
    return enabled;
  }

  @override
  Future<void> write(bool value) async => enabled = value;
}

class _Conditions implements AlertConditionStore {
  final values = <AlertConditionKey, bool>{};
  final failReads = <AlertConditionKey>{};
  final failWrites = <AlertConditionKey>{};
  void Function()? afterRead;
  Future<void> Function(AlertConditionKey, bool)? beforeWrite;
  var reads = 0;
  var writes = 0;
  @override
  Future<bool> read(AlertConditionKey key) async {
    reads++;
    if (failReads.contains(key)) throw StateError('Read unavailable.');
    afterRead?.call();
    return values[key] ?? false;
  }

  @override
  Future<void> write(AlertConditionKey key, bool consumed) async {
    writes++;
    await beforeWrite?.call(key, consumed);
    if (failWrites.contains(key)) throw StateError('Write unavailable.');
    if (consumed) {
      values[key] = true;
    } else {
      values.remove(key);
    }
  }
}

class _Notifier implements AlertNotifier {
  bool allowed = true;
  bool failPost = false;
  int asked = 0;
  final posts = <AlertConditionKey>[];
  final titles = <String>[];
  @override
  Future<bool> canPost() async => allowed;
  @override
  Future<bool> requestPermission() async {
    asked++;
    return allowed;
  }

  @override
  Future<void> notify(AlertConditionKey key, {required String title}) async {
    if (failPost) throw StateError('Plugin unavailable.');
    posts.add(key);
    titles.add(title);
  }
}
