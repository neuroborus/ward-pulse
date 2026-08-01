import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ward_pulse_phone/dashboard/dashboard_models.dart';
import 'package:ward_pulse_phone/widget/phone_widget_payload.dart';
import 'package:ward_pulse_phone/widget/phone_widget_preferences.dart';
import 'package:ward_pulse_phone/widget/phone_widget_sync.dart';

void main() {
  final snapshot = DashboardSnapshot.fromJsonString(
    File('../../fixtures/snapshots/dashboard_today.json').readAsStringSync(),
  );

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
        const PhoneWidgetPreferences(selectedIds: ['budget.today']),
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
