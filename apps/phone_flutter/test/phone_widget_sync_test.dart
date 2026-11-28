import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:ward_pulse_phone/dashboard/dashboard_models.dart';
import 'package:ward_pulse_phone/sync/data_mode.dart';
import 'package:ward_pulse_phone/widget/phone_widget_payload.dart';
import 'package:ward_pulse_phone/widget/phone_widget_preferences.dart';
import 'package:ward_pulse_phone/widget/phone_widget_sync.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // Mock accounts hold no metric slots, so default prefs would write nothing.
  final snapshot = _asConnection(
    DashboardSnapshot.fromJsonString(
      File('../../fixtures/snapshots/dashboard_today.json').readAsStringSync(),
    ),
  );

  for (final identity in <Map<String, Object?>>[
    {},
    {
      'row_0_family': 'Claude',
      'row_0_pool': 'plan',
      'row_0_resets_at': '2028-02-10T09:15:00.000Z',
    },
  ]) {
    final format = identity.isEmpty ? 'legacy' : 'structured';
    test('stale marker preserves $format rows and redraws Android', () async {
      final data = <String, Object?>{
        'row_count': 1,
        'empty': '0',
        'stale': '0',
        'row_0_percent': '46% left',
        'row_0_label': 'Claude plan',
        'row_0_credits': '320 credits',
        'row_0_color': 'ff91c4b1',
        ...identity,
      };
      final original = Map<String, Object?>.from(data);
      final calls = <MethodCall>[];
      _bindWidgetStorage(data, calls: calls);
      await HomeWidgetPhoneWidgetSyncService.markExistingRowsStale();
      expect(data, {...original, 'stale': '1'});
      final redraw = calls.singleWhere((call) => call.method == 'updateWidget');
      expect(
        (redraw.arguments as Map)['qualifiedAndroidName'],
        phoneWidgetQualifiedAndroidName,
      );
    });
  }

  test('upgrades a legacy cache with identity and UTC reset', () async {
    final data = <String, Object?>{
      'row_count': 1,
      'empty': '0',
      'row_0_percent': '0% left',
      'row_0_label': 'Cursor Models',
      'row_0_credits': '320 credits',
      'row_0_color': 'ff91c4b1',
    };
    final calls = <MethodCall>[];
    _bindWidgetStorage(data, calls: calls);

    await HomeWidgetPhoneWidgetSyncService.writeHomeWidgetPayload(
      PhoneWidgetPayload(
        rows: [
          PhoneWidgetRow(
            label: 'Cursor Models',
            familyLabel: 'Cursor',
            poolLabel: 'Models',
            remainingPercent: 0,
            accentArgb: 0xff91c4b1,
            creditsSuffix: '320 credits',
            resetsAt: DateTime.parse('2028-02-10T14:45:00+05:30'),
          ),
        ],
        stale: false,
      ),
    );

    expect(data['row_count'], 1);
    expect(data['empty'], '0');
    expect(data['stale'], '0');
    expect(data['row_0_percent'], '0% left');
    expect(data['row_0_label'], 'Cursor Models');
    expect(data['row_0_credits'], '320 credits');
    expect(data['row_0_color'], 'ff91c4b1');
    expect(data['row_0_family'], 'Cursor');
    expect(data['row_0_pool'], 'Models');
    expect(data['row_0_resets_at'], '2028-02-10T09:15:00.000Z');
    expect(calls.where((call) => call.method == 'updateWidget'), hasLength(1));
  });

  test('clears absent optional fields and every removed slot', () async {
    const rowFields = [
      'percent',
      'credits',
      'label',
      'family',
      'pool',
      'resets_at',
      'color',
      'kind',
      'spent_minor',
      'spent_currency',
      'cap_minor',
      'cap_currency',
      'extra_used_value',
      'extra_used_unit',
      'extra_cap_value',
      'extra_cap_unit',
    ];
    final data = <String, Object?>{
      'row_count': phoneWidgetSlotCount,
      'empty': '0',
      for (var i = 0; i < phoneWidgetSlotCount; i++)
        for (final field in rowFields) 'row_${i}_$field': 'previous',
    };
    final calls = <MethodCall>[];
    _bindWidgetStorage(data, calls: calls);

    await HomeWidgetPhoneWidgetSyncService.writeHomeWidgetPayload(
      const PhoneWidgetPayload(
        rows: [
          PhoneWidgetRow(
            label: 'Retained metric',
            remainingPercent: 46,
            accentArgb: 0xff91c4b1,
          ),
        ],
        stale: false,
      ),
    );

    expect(data['row_count'], 1);
    expect(data['row_0_label'], 'Retained metric');
    expect(data['row_0_percent'], '46% left');
    for (final field in [
      'credits',
      'family',
      'pool',
      'resets_at',
      'spent_minor',
      'spent_currency',
      'cap_minor',
      'cap_currency',
      'extra_used_value',
      'extra_used_unit',
      'extra_cap_value',
      'extra_cap_unit',
    ]) {
      expect(
        data['row_0_$field'],
        '',
        reason: 'Absent $field must be cleared.',
      );
    }
    for (var i = 1; i < phoneWidgetSlotCount; i++) {
      for (final field in rowFields) {
        expect(data['row_${i}_$field'], '', reason: 'Removed slot $i: $field');
      }
    }

    await HomeWidgetPhoneWidgetSyncService.writeHomeWidgetPayload(
      const PhoneWidgetPayload(rows: [], stale: false),
    );

    expect(data['row_count'], 0);
    expect(data['empty'], '1');
    for (final field in rowFields) {
      expect(data['row_0_$field'], '', reason: 'Cleared final row: $field');
    }
    expect(calls.where((call) => call.method == 'updateWidget'), hasLength(2));
  });

  test(
    'Money and Quantity transitions retain exact strings and clear obsolete fields',
    () async {
      final data = <String, Object?>{};
      _bindWidgetStorage(data, calls: <MethodCall>[]);
      Future<void> write(PhoneWidgetRow row) =>
          HomeWidgetPhoneWidgetSyncService.writeHomeWidgetPayload(
            PhoneWidgetPayload(rows: [row], stale: false),
          );
      await write(
        const PhoneWidgetRow(
          label: 'Expense',
          remainingPercent: 40,
          accentArgb: 0xff91c4b1,
          kind: PhoneWidgetRowKind.budget,
          spent: Money(minorUnits: -9007199254740993, currency: 'EUR'),
          cap: Money(minorUnits: 10000, currency: 'EUR'),
        ),
      );
      expect(data['row_0_kind'], 'budget');
      expect(data['row_0_spent_minor'], '-9007199254740993');
      expect(data['row_0_spent_currency'], 'EUR');
      expect(data['row_0_cap_minor'], '10000');
      await write(
        const PhoneWidgetRow(
          label: 'Uncapped',
          remainingPercent: null,
          accentArgb: 0xff91c4b1,
          kind: PhoneWidgetRowKind.budget,
          spent: Money(minorUnits: 0, currency: 'EUR'),
        ),
      );
      expect(data['row_0_spent_minor'], '0');
      expect(data['row_0_cap_minor'], '');
      expect(data['row_0_cap_currency'], '');
      expect(data['row_0_percent'], '');
      await write(
        const PhoneWidgetRow(
          label: 'Extra',
          remainingPercent: 80,
          accentArgb: 0xff91c4b1,
          extraUsed: Quantity(value: '12.500000', unit: 'Credits'),
        ),
      );
      expect(data['row_0_kind'], 'allowance');
      expect(data['row_0_extra_used_value'], '12.500000');
      expect(data['row_0_extra_used_unit'], 'Credits');
      for (final field in [
        'spent_minor',
        'spent_currency',
        'cap_minor',
        'cap_currency',
        'extra_cap_value',
        'extra_cap_unit',
      ]) {
        expect(data['row_0_$field'], '');
      }
      await write(
        const PhoneWidgetRow(
          label: 'Unavailable expense',
          remainingPercent: null,
          accentArgb: 0xff91c4b1,
          kind: PhoneWidgetRowKind.budget,
        ),
      );
      for (final field in ['percent', 'extra_used_value', 'extra_used_unit']) {
        expect(data['row_0_$field'], '');
      }
    },
  );

  for (final data in <Map<String, Object?>>[
    {},
    {'row_count': 0, 'empty': '1', 'stale': '0'},
    {'row_count': 1, 'empty': '1', 'stale': '0'},
  ]) {
    test(
      'stale marker leaves initial or cleared payload $data unchanged',
      () async {
        final stored = Map<String, Object?>.from(data);
        final calls = <MethodCall>[];
        _bindWidgetStorage(stored, calls: calls);
        await HomeWidgetPhoneWidgetSyncService.markExistingRowsStale();
        expect(stored, data);
        expect(calls.map((call) => call.method), ['markStale']);
      },
    );
  }

  for (final method in ['markStale', 'publish']) {
    test(
      'ownership before and during $method bounds subsequent effects',
      () async {
        final data = <String, Object?>{
          'row_count': 1,
          'empty': '0',
          'stale': '0',
        };
        final calls = <MethodCall>[];
        var owned = false;
        final started = Completer<void>();
        final release = Completer<void>();
        _bindWidgetStorage(
          data,
          calls: calls,
          onCall: (call) async {
            if (call.method == method) {
              started.complete();
              await release.future;
            }
          },
        );
        Future<void> write() =>
            method == 'markStale'
                ? HomeWidgetPhoneWidgetSyncService.markExistingRowsStale(
                  isCurrent: () async => owned,
                )
                : HomeWidgetPhoneWidgetSyncService.writeHomeWidgetPayload(
                  PhoneWidgetPayload(
                    rows: List.generate(
                      phoneWidgetSlotCount,
                      (i) => PhoneWidgetRow(
                        label: 'Published $i',
                        remainingPercent: i,
                        accentArgb: 0xff91c4b1,
                      ),
                    ),
                    stale: false,
                  ),
                  isCurrent: () async => owned,
                );
        await write();
        expect(calls, isEmpty);
        owned = true;
        final run = write();
        await started.future;
        owned = false;
        release.complete();
        await run;
        expect(data['stale'], method == 'markStale' ? '1' : '0');
        expect(
          data['row_count'],
          method == 'markStale' ? 1 : phoneWidgetSlotCount,
        );
        expect(data['empty'], '0');
        if (method == 'publish') {
          for (var i = 0; i < phoneWidgetSlotCount; i++) {
            expect(data['row_${i}_label'], 'Published $i');
            expect(data['row_${i}_percent'], '$i% left');
          }
        }
        expect(calls.where((call) => call.method == 'updateWidget'), isEmpty);
      },
    );
  }

  for (final failedMethod in ['markStale', 'updateWidget']) {
    test('stale marker reports a failed $failedMethod result', () async {
      final data = <String, Object?>{
        'row_count': 1,
        'empty': '0',
        'stale': '0',
      };
      final calls = <MethodCall>[];
      _bindWidgetStorage(data, calls: calls, failedMethod: failedMethod);
      await expectLater(
        HomeWidgetPhoneWidgetSyncService.markExistingRowsStale(),
        throwsStateError,
      );
      if (failedMethod == 'markStale') {
        expect(data['stale'], '0');
        expect(calls.where((call) => call.method == 'updateWidget'), isEmpty);
      } else {
        expect(data['stale'], '1');
      }
    });
  }

  test(
    'failed complete publication reports failure and suppresses redraw',
    () async {
      final calls = <MethodCall>[];
      _bindWidgetStorage({}, calls: calls, failedMethod: 'publish');
      await expectLater(
        HomeWidgetPhoneWidgetSyncService.writeHomeWidgetPayload(
          const PhoneWidgetPayload(rows: [], stale: false),
        ),
        throwsStateError,
      );
      expect(calls.map((call) => call.method), ['publish']);
    },
  );

  test('overlapping syncs keep only the newer payload', () async {
    final written = <PhoneWidgetPayload>[];
    final firstWriteStarted = Completer<void>();
    final releaseFirstWrite = Completer<void>();

    final coordinator = PhoneWidgetSyncCoordinator(
      write: (payload, {required isCurrent}) async {
        written.add(payload);
        if (written.length == 1) {
          firstWriteStarted.complete();
          await releaseFirstWrite.future;
        }
        return true;
      },
    );

    final emptyPrefs = const PhoneWidgetPreferences(selectedIds: []);
    final defaultPrefs = const PhoneWidgetPreferences();

    final first = coordinator.sync(snapshot, emptyPrefs);
    await firstWriteStarted.future;

    final second = coordinator.sync(snapshot, defaultPrefs);
    releaseFirstWrite.complete();
    await Future.wait([first, second]);

    expect(written, hasLength(2));
    expect(written.first.isEmpty, isTrue);
    expect(written.last.isEmpty, isFalse);
  });

  test(
    'superseded sync skips write when a newer request is already queued',
    () async {
      final written = <PhoneWidgetPayload>[];
      final gate = Completer<void>();

      final coordinator = PhoneWidgetSyncCoordinator(
        write: (payload, {required isCurrent}) async {
          written.add(payload);
          if (written.length == 1) {
            await gate.future;
          }
          return true;
        },
      );

      final emptyPrefs = const PhoneWidgetPreferences(selectedIds: []);
      final defaultPrefs = const PhoneWidgetPreferences();

      // Start a write, then queue two superseding requests before it finishes.
      final first = coordinator.sync(snapshot, emptyPrefs);
      await Future<void>.delayed(Duration.zero);
      final middle = coordinator.sync(
        snapshot,
        const PhoneWidgetPreferences(
          selectedIds: ['budget.anthropic.platform.today'],
        ),
      );
      final latest = coordinator.sync(snapshot, defaultPrefs);
      gate.complete();
      await Future.wait([first, middle, latest]);

      // First write may have started with empty prefs; middle is skipped; latest runs.
      expect(written.length, inInclusiveRange(1, 2));
      expect(written.last.isEmpty, isFalse);
      expect(
        written.where((payload) => payload.isEmpty),
        anyOf(isEmpty, hasLength(1)),
      );
    },
  );

  test('a queued request carries its own ownership guard', () async {
    final written = <PhoneWidgetPayload>[];
    final guards = <bool>[];
    final firstWriteStarted = Completer<void>();
    final releaseFirstWrite = Completer<void>();
    final coordinator = PhoneWidgetSyncCoordinator(
      write: (payload, {required isCurrent}) async {
        written.add(payload);
        guards.add(await isCurrent());
        if (written.length == 1) {
          firstWriteStarted.complete();
          await releaseFirstWrite.future;
        }
        return true;
      },
    );
    const emptyPrefs = PhoneWidgetPreferences(selectedIds: []);
    const defaultPrefs = PhoneWidgetPreferences();

    final first = coordinator.sync(snapshot, defaultPrefs);
    await firstWriteStarted.future;
    var owned = true;
    final retired = coordinator.sync(
      snapshot,
      emptyPrefs,
      isCurrent: () async => owned,
    );
    owned = false;
    releaseFirstWrite.complete();
    await Future.wait([first, retired]);
    expect(written, hasLength(1));

    // A newer foreground request keeps its own default guard.
    final superseded = coordinator.sync(
      snapshot,
      defaultPrefs,
      isCurrent: () async => false,
    );
    final foreground = coordinator.sync(snapshot, emptyPrefs);
    await Future.wait([superseded, foreground]);
    expect(written, hasLength(2));
    expect(written.last.isEmpty, isTrue);
    expect(guards, [true, true]);
  });

  group('publication tickets', () {
    const input = PhoneWidgetPublicationInput(
      load: 3,
      settingsRevision: 7,
      observed: 2,
    );

    Future<bool> sync() => input.run(
      () => PhoneWidgetSyncCoordinator(
        write: HomeWidgetPhoneWidgetSyncService.writeHomeWidgetPayload,
      ).sync(snapshot, const PhoneWidgetPreferences(selectedIds: [])),
    );

    test('a refused ticket publishes and redraws nothing', () async {
      final data = <String, Object?>{};
      final calls = <MethodCall>[];
      _bindWidgetStorage(data, calls: calls, replies: {'issue': null});
      expect(await sync(), isFalse);
      expect(calls.map((call) => call.method), ['issue']);
      expect(calls.single.arguments, {'load': 3, 'settingsRevision': 7});
      expect(data, isEmpty);
    });

    test('a refused ticketed commit skips its redraw', () async {
      final calls = <MethodCall>[];
      _bindWidgetStorage(
        {},
        calls: calls,
        replies: {'issue': 9, 'publish': null},
      );
      expect(await sync(), isFalse);
      expect(calls.map((call) => call.method), ['issue', 'publish']);
      expect((calls.last.arguments as Map)['ticket'], 9);
    });

    test('a committed ticket redraws the launcher', () async {
      final data = <String, Object?>{};
      final calls = <MethodCall>[];
      _bindWidgetStorage(data, calls: calls, replies: {'issue': 9});
      expect(await sync(), isTrue);
      expect(calls.map((call) => call.method), [
        'issue',
        'publish',
        'updateWidget',
      ]);
      expect(data['ticket'], 9);
      expect(data['empty'], '1');
    });

    test('a mode switch held at effect admission commits nothing', () async {
      final data = <String, Object?>{};
      final calls = <MethodCall>[];
      _bindWidgetStorage(data, calls: calls, replies: {'issue': 9});
      final modes = MemoryDataModeAuthority();
      final authority = _HeldAdmissionAuthority(modes);
      DataModeOperation capture() => DataModeOperation(
        authority: authority,
        state: modes.state,
        requestId: 'widget',
      );
      final coordinator = PhoneWidgetSyncCoordinator(
        write: HomeWidgetPhoneWidgetSyncService.writeHomeWidgetPayload,
      );
      Future<bool> publish(DataModeOperation operation) => operation.run(
        () => input.run(
          () => coordinator.sync(
            snapshot,
            const PhoneWidgetPreferences(selectedIds: []),
          ),
        ),
      );

      final retired = capture();
      final held = Completer<void>();
      authority.hold = held;
      var guards = 0;
      final refused = retired.run(
        () => input.run(
          () => coordinator.sync(
            snapshot,
            const PhoneWidgetPreferences(selectedIds: []),
            isCurrent: () async {
              guards++;
              return true;
            },
          ),
        ),
      );
      await authority.entered.future;
      // Both Dart guards passed before the real admission ran.
      expect(guards, 2);
      final switched = modes.switchTo(DataMode.mock);
      held.complete();
      expect(await refused, isFalse);
      await switched;
      expect(calls, isEmpty);
      expect(data, isEmpty);
      // The retired operation cannot publish later either.
      expect(await publish(retired), isFalse);
      expect(calls, isEmpty);

      final current = capture();
      expect(await publish(current), isTrue);
      expect(calls.map((call) => call.method), [
        'issue',
        'publish',
        'updateWidget',
      ]);
      expect((calls.first.arguments as Map)['generation'], current.generation);
      expect(data['ticket'], 9);
    });

    test(
      'a publication retired at native effect admission reports no commit',
      () async {
        final data = <String, Object?>{};
        final calls = <MethodCall>[];
        final reached = Completer<void>();
        final release = Completer<void>();
        addTearDown(() {
          if (!release.isCompleted) release.complete();
        });
        var retire = true;
        _bindWidgetStorage(
          data,
          calls: calls,
          replies: {'issue': 9},
          onCall: (call) async {
            if (call.method != 'publish' || !retire) return;
            retire = false;
            reached.complete();
            await release.future;
            // The switch closed native admission after the ticket was issued.
            throw PlatformException(code: 'widget_publication_retired');
          },
        );
        final modes = MemoryDataModeAuthority()..failWrite = true;
        final operation = await modes.begin();
        Future<bool> publish() => operation.run(
          () => input.run(
            () => PhoneWidgetSyncCoordinator(
              write: HomeWidgetPhoneWidgetSyncService.writeHomeWidgetPayload,
            ).sync(snapshot, const PhoneWidgetPreferences(selectedIds: [])),
          ),
        );

        final refused = publish();
        await reached.future;
        // The switch fails; the unchanged mode still owns the current choice.
        final switched = expectLater(
          modes.switchTo(DataMode.mock),
          throwsA(isA<DataModeWriteFailure>()),
        );
        release.complete();
        expect(await refused, isFalse);
        expect(calls.map((call) => call.method), ['issue', 'publish']);
        expect(data, isEmpty);
        await switched;
        expect(await operation.isCurrent(), isTrue);
        expect(await publish(), isTrue);
        expect(calls.map((call) => call.method).skip(2), [
          'issue',
          'publish',
          'updateWidget',
        ]);
        expect(data['ticket'], 9);
      },
    );

    test('a native storage failure still reaches the caller', () async {
      _bindWidgetStorage(
        {},
        calls: <MethodCall>[],
        replies: {'issue': 9},
        onCall: (call) async {
          if (call.method == 'publish') {
            throw PlatformException(code: 'widget_storage_unavailable');
          }
        },
      );
      await expectLater(sync(), throwsA(isA<PlatformException>()));
    });

    test(
      'a superseded request reports no success for its replacement',
      () async {
        final entered = Completer<void>();
        final release = Completer<bool>();
        addTearDown(() {
          if (!release.isCompleted) release.complete(false);
        });
        var writes = 0;
        final coordinator = PhoneWidgetSyncCoordinator(
          write: (payload, {required isCurrent}) async {
            writes++;
            // Native refuses the replacement's ticket.
            return false;
          },
        );
        const prefs = PhoneWidgetPreferences(selectedIds: []);
        final earlier = coordinator.sync(
          snapshot,
          prefs,
          isCurrent: () {
            if (!entered.isCompleted) entered.complete();
            return release.future;
          },
        );
        await entered.future;
        final replacement = coordinator.sync(snapshot, prefs);
        release.complete(true);
        expect(await earlier, isFalse);
        expect(await replacement, isFalse);
        expect(writes, 1);
      },
    );

    test('acceptance registers the load with the shared authority', () async {
      final calls = <MethodCall>[];
      final replies = <String, Object?>{'accept': true};
      _bindWidgetStorage({}, calls: calls, replies: replies);
      expect(await input.accept(snapshot), isTrue);
      expect(calls.single.arguments, {'load': 3});
      replies['accept'] = false;
      expect(await input.accept(snapshot), isFalse);
      expect(
        await PhoneWidgetPublicationInput.unavailable.accept(snapshot),
        isFalse,
      );
      expect(calls, hasLength(2));
    });

    test('a failed load marks only the publication it observed', () async {
      final calls = <MethodCall>[];
      _bindWidgetStorage(
        {'row_count': 1, 'empty': '0', 'stale': '0'},
        calls: calls,
        replies: {'markStale': null},
      );
      await input.run(HomeWidgetPhoneWidgetSyncService.markExistingRowsStale);
      expect(calls.map((call) => call.method), ['markStale']);
      expect(calls.single.arguments, {'observed': 2});
    });

    test('a load claim records its settings read', () async {
      final calls = <MethodCall>[];
      final reply = <String, Object?>{
        'load': 5,
        'settingsRevision': null,
        'observed': 4,
        'established': false,
      };
      _bindWidgetStorage({}, calls: calls, replies: {'beginLoad': reply});
      final headless = await PhoneWidgetPublicationInput.begin();
      expect(headless.load, 5);
      expect(headless.observed, 4);
      expect(headless.established, isFalse);
      // No committed rows awaited a first delivery.
      expect(headless.awaitingDelivery, isFalse);
      // A save in flight retires the read.
      expect(headless.settingsRevision, -1);
      reply['settingsRevision'] = 6;
      reply['awaitingDelivery'] = true;
      final settled = await PhoneWidgetPublicationInput.begin();
      expect(settled.settingsRevision, 6);
      expect(settled.awaitingDelivery, isTrue);
      expect(settled.withSettingsRevision(8).settingsRevision, 8);
      expect(settled.withSettingsRevision(8).awaitingDelivery, isTrue);
      expect(settled.withSettingsRevision(null).settingsRevision, -1);
    });

    test('a missing authority leaves publications unordered', () async {
      _bindWidgetStorage({}, calls: <MethodCall>[]);
      expect(
        await PhoneWidgetPublicationInput.begin(),
        same(PhoneWidgetPublicationInput.unordered),
      );
      var saved = false;
      expect(
        await PhoneWidgetPublicationInput.saveSettings(
          () async => saved = true,
        ),
        isNull,
      );
      expect(saved, isTrue);
    });

    test('a settings save is bracketed by the native authority', () async {
      final calls = <MethodCall>[];
      final replies = <String, Object?>{
        'beginSettingsWrite': 'save',
        'finishSettingsWrite': 8,
      };
      // Set while native cannot begin a save; it carries the settled revision.
      PlatformException? beginFailure;
      _bindWidgetStorage(
        {},
        calls: calls,
        replies: replies,
        onCall: (call) async {
          final failure = beginFailure;
          if (call.method == 'beginSettingsWrite' && failure != null) {
            throw failure;
          }
        },
      );
      expect(await PhoneWidgetPublicationInput.saveSettings(() async {}), 8);
      calls.clear();
      // Another save in flight leaves the revision unsettled.
      replies['finishSettingsWrite'] = null;
      expect(await PhoneWidgetPublicationInput.saveSettings(() async {}), null);
      calls.clear();
      // A failed write still reports that native began it, so the save that
      // settles replaces what it retired.
      final unsettled = StateError('disk full');
      await expectLater(
        PhoneWidgetPublicationInput.saveSettings(() async => throw unsettled),
        throwsA(
          isA<SettingsWriteFailure>()
              .having((failure) => failure.settingsRevision, 'revision', null)
              .having((failure) => failure.error, 'error', same(unsettled)),
        ),
      );
      expect(calls.map((call) => call.method), [
        'beginSettingsWrite',
        'finishSettingsWrite',
      ]);
      expect(calls.first.arguments, isNull);
      expect(calls.last.arguments, {'token': 'save'});

      // A save native could not begin never writes; native finished it, and
      // its error carries the revision it settled, if any.
      for (final settled in [10, null]) {
        calls.clear();
        beginFailure = PlatformException(
          code: 'widget_storage_unavailable',
          details: settled,
        );
        var saved = false;
        await expectLater(
          PhoneWidgetPublicationInput.saveSettings(() async => saved = true),
          throwsA(
            isA<SettingsWriteFailure>()
                .having((it) => it.settingsRevision, 'revision', settled)
                .having((it) => it.error, 'error', isA<PlatformException>()),
          ),
        );
        expect(saved, isFalse);
        expect(calls.map((call) => call.method), ['beginSettingsWrite']);
      }
      beginFailure = null;

      // A failed write native settled anyway surfaces that revision with the
      // write's own error.
      replies['finishSettingsWrite'] = 9;
      final error = StateError('disk full');
      await expectLater(
        PhoneWidgetPublicationInput.saveSettings(() async => throw error),
        throwsA(
          isA<SettingsWriteFailure>()
              .having((failure) => failure.settingsRevision, 'revision', 9)
              .having((failure) => failure.error, 'error', same(error)),
        ),
      );

      // A launcher-only save asks native to leave the watch item answerable.
      calls.clear();
      await PhoneWidgetPublicationInput.saveSettings(() async {}, watch: false);
      expect(calls.first.arguments, {'watch': false});
    });

    test('the coordinator writes under the newest caller claim', () async {
      final claims = <int?>[];
      final release = Completer<void>();
      final coordinator = PhoneWidgetSyncCoordinator(
        write: (payload, {required isCurrent}) async {
          claims.add(PhoneWidgetPublicationInput.current?.load);
          if (claims.length == 1) await release.future;
          return true;
        },
      );
      const prefs = PhoneWidgetPreferences();
      final first = input.run(() => coordinator.sync(snapshot, prefs));
      await Future<void>.delayed(Duration.zero);
      const olderInput = PhoneWidgetPublicationInput(load: 4);
      const newerInput = PhoneWidgetPublicationInput(load: 5);
      final older = olderInput.run(() => coordinator.sync(snapshot, prefs));
      final newer = newerInput.run(() => coordinator.sync(snapshot, prefs));
      release.complete();
      await Future.wait([first, older, newer]);
      expect(claims, [3, 5]);
    });
  });

  test(
    'a failed write reaches the caller without poisoning the queue',
    () async {
      var attempts = 0;
      final coordinator = PhoneWidgetSyncCoordinator(
        write: (payload, {required isCurrent}) async {
          attempts++;
          if (attempts == 1) {
            throw StateError('platform unavailable');
          }
          return true;
        },
      );

      await expectLater(
        coordinator.sync(snapshot, const PhoneWidgetPreferences()),
        throwsStateError,
      );

      // The next caller must still get a write, not the previous failure.
      await coordinator.sync(snapshot, const PhoneWidgetPreferences());
      expect(attempts, 2);
    },
  );
}

/// Holds the next effect admission, then asks the real authority.
final class _HeldAdmissionAuthority implements DataModeAuthority {
  _HeldAdmissionAuthority(this._inner);

  final MemoryDataModeAuthority _inner;
  final entered = Completer<void>();
  Completer<void>? hold;

  @override
  Future<DataModeState> read() => _inner.read();

  @override
  Future<DataModeOperation> begin({
    bool cacheOnly = false,
    bool waitForSwitch = false,
  }) => _inner.begin(cacheOnly: cacheOnly, waitForSwitch: waitForSwitch);

  @override
  Future<bool> isCurrent(int generation) => _inner.isCurrent(generation);

  @override
  Future<String?> enter(int generation, {bool settlement = false}) async {
    final held = hold;
    hold = null;
    if (held != null) {
      entered.complete();
      await held.future;
    }
    return _inner.enter(generation, settlement: settlement);
  }

  @override
  Future<void> exit(String lease, {bool unresolved = false}) =>
      _inner.exit(lease, unresolved: unresolved);

  @override
  Future<DataModeSwitch> switchTo(DataMode mode) => _inner.switchTo(mode);
}

void _bindWidgetStorage(
  Map<String, Object?> data, {
  required List<MethodCall> calls,
  String? failedMethod,
  Future<void> Function(MethodCall call)? onCall,
  Map<String, Object?> replies = const {},
}) {
  const channel = MethodChannel('home_widget');
  const publication = MethodChannel('app.wardpulse/widget_publication');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  Future<Object?> handle(MethodCall call) async {
    calls.add(call);
    await onCall?.call(call);
    if (call.method == failedMethod) {
      return false;
    }
    if (replies.containsKey(call.method)) {
      return replies[call.method];
    }
    switch (call.method) {
      case 'publish':
        data.addAll(Map<String, Object?>.from(call.arguments as Map));
        return true;
      case 'markStale':
        if ((data['row_count'] as int? ?? 0) <= 0 || data['empty'] == '1') {
          return null;
        }
        data['stale'] = '1';
        return true;
      case 'updateWidget':
        return true;
      default:
        throw MissingPluginException();
    }
  }

  messenger.setMockMethodCallHandler(channel, handle);
  messenger.setMockMethodCallHandler(publication, handle);
  addTearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
    messenger.setMockMethodCallHandler(publication, null);
  });
}

/// Mock fixture as a real connection: mock accounts hold no metric slots.
DashboardSnapshot _asConnection(DashboardSnapshot snapshot) {
  final account =
      Map<String, Object?>.from(snapshot.primaryAccount!.toJson())
        ..['accountId'] = 'anthropic-platform'
        ..['provider'] = 'claude'
        ..['connection'] = 'anthropic.platform';
  return DashboardSnapshot.fromJson({
    ...snapshot.toJson(),
    'accounts': [account],
  });
}
