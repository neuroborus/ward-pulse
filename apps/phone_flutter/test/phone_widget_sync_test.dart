import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:ward_pulse_phone/dashboard/dashboard_models.dart';
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
        expect(calls.where((call) => call.method != 'getWidgetData'), isEmpty);
      },
    );
  }

  for (final failedMethod in ['saveWidgetData', 'updateWidget']) {
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
      if (failedMethod == 'saveWidgetData') {
        expect(data['stale'], '0');
        expect(calls.where((call) => call.method == 'updateWidget'), isEmpty);
      } else {
        expect(data['stale'], '1');
      }
    });
  }

  test('overlapping syncs keep only the newer payload', () async {
    final written = <PhoneWidgetPayload>[];
    final firstWriteStarted = Completer<void>();
    final releaseFirstWrite = Completer<void>();

    final coordinator = PhoneWidgetSyncCoordinator(
      write: (payload) async {
        written.add(payload);
        if (written.length == 1) {
          firstWriteStarted.complete();
          await releaseFirstWrite.future;
        }
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
        write: (payload) async {
          written.add(payload);
          if (written.length == 1) {
            await gate.future;
          }
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

  test(
    'a failed write reaches the caller without poisoning the queue',
    () async {
      var attempts = 0;
      final coordinator = PhoneWidgetSyncCoordinator(
        write: (payload) async {
          attempts++;
          if (attempts == 1) {
            throw StateError('platform unavailable');
          }
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

void _bindWidgetStorage(
  Map<String, Object?> data, {
  required List<MethodCall> calls,
  String? failedMethod,
}) {
  const channel = MethodChannel('home_widget');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(channel, (call) async {
    calls.add(call);
    final args = Map<String, Object?>.from(call.arguments as Map);
    if (call.method == failedMethod) {
      return false;
    }
    switch (call.method) {
      case 'getWidgetData':
        return data[args['id']] ?? args['defaultValue'];
      case 'saveWidgetData':
        data[args['id']! as String] = args['data'];
        return true;
      case 'updateWidget':
        return true;
      default:
        throw MissingPluginException();
    }
  });
  addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
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
