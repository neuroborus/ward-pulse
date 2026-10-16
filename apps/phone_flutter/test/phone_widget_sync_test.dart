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

  test(
    'stale marker preserves every retained row and redraws Android provider',
    () async {
      final data = <String, Object?>{
        'row_count': 1,
        'empty': '0',
        'stale': '0',
        'row_0_percent': '46% left',
        'row_0_label': 'Claude plan',
        'row_0_credits': '320 credits',
        'row_0_color': 'ff91c4b1',
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
