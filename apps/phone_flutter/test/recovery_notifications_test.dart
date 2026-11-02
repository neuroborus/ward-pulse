import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ward_pulse_phone/settings/notification_permission_preferences.dart';
import 'package:ward_pulse_phone/sync/alert_notifications.dart';
import 'package:ward_pulse_phone/sync/notification_coordinator.dart';
import 'package:ward_pulse_phone/sync/recovery_notifications.dart';

import 'connection_cache_test_support.dart';

void main() {
  testWidgets(
    'passive Android status and settings bypass readiness and attempts',
    (tester) async {
      final previousPlatform = FlutterLocalNotificationsPlatform.instance;
      AndroidFlutterLocalNotificationsPlugin.registerWith();
      const channel = MethodChannel(
        'dexterous.com/flutter/local_notifications',
      );
      final messenger = tester.binding.defaultBinaryMessenger;
      addTearDown(() {
        messenger.setMockMethodCallHandler(channel, null);
        FlutterLocalNotificationsPlatform.instance = previousPlatform;
      });
      final calls = <String>[];
      bool? response;
      var fail = false;
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call.method);
        if (fail) throw PlatformException(code: 'unavailable');
        return response;
      });
      final storage = FakeSecureStorage()..failRead = true;
      var writes = 0;
      storage.beforeWrite = (_) async {
        writes++;
      };
      var initializations = 0;
      final coordinator = PhoneNotificationCoordinator(
        attempts: SecureNotificationPermissionAttemptStore(storage: storage),
        initialize: () async {
          initializations++;
        },
      );
      for (final value in [false, true, null]) {
        response = value;
        expect(await coordinator.readAndroidNotificationStatus(), value);
        expect(await coordinator.openAndroidNotificationSettings(), value);
      }
      fail = true;
      await expectLater(
        coordinator.readAndroidNotificationStatus(),
        throwsA(isA<PlatformException>()),
      );
      await expectLater(
        coordinator.openAndroidNotificationSettings(),
        throwsA(isA<PlatformException>()),
      );
      fail = false;
      response = true;
      expect(await coordinator.openAndroidNotificationSettings(), isTrue);
      expect(calls, [
        for (var i = 0; i < 4; i++) ...[
          'areNotificationsEnabled',
          'openAppNotificationSettings',
        ],
        'openAppNotificationSettings',
      ]);
      expect(initializations, 0);
      expect(writes, 0);
      expect(storage.values, isEmpty);
      expect(storage.deleted, isEmpty);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  testWidgets(
    'readiness registers both channels once without posting or requesting',
    (tester) async {
      final previousPlatform = FlutterLocalNotificationsPlatform.instance;
      AndroidFlutterLocalNotificationsPlugin.registerWith();
      const channel = MethodChannel(
        'dexterous.com/flutter/local_notifications',
      );
      final messenger = tester.binding.defaultBinaryMessenger;
      addTearDown(() {
        messenger.setMockMethodCallHandler(channel, null);
        FlutterLocalNotificationsPlatform.instance = previousPlatform;
      });
      final calls = <MethodCall>[];
      final initialized = Completer<void>();
      final release = Completer<void>();
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        if (call.method == 'initialize') {
          initialized.complete();
          await release.future;
          return true;
        }
        if (call.method == 'areNotificationsEnabled') return false;
        return null;
      });
      final storage = FakeSecureStorage();
      final coordinator = PhoneNotificationCoordinator(
        attempts: SecureNotificationPermissionAttemptStore(storage: storage),
      );
      final ready = coordinator.ensureReady();
      await initialized.future;
      final canPost = LocalAlertNotifier(coordinator: coordinator).canPost();
      release.complete();
      await ready;
      expect(await canPost, isFalse);
      await coordinator.ensureReady();
      expect(calls.map((call) => call.method), [
        'initialize',
        'createNotificationChannel',
        'createNotificationChannel',
        'areNotificationsEnabled',
      ]);
      final channels =
          calls
              .where((call) => call.method == 'createNotificationChannel')
              .map((call) => call.arguments as Map)
              .toList();
      expect(
        channels.map(
          (value) => [
            value['id'],
            value['name'],
            value['description'],
            value['importance'],
          ],
        ),
        [
          [
            'wardpulse.alerts',
            'Alert notifications',
            'Your configured usage and budget thresholds.',
            3,
          ],
          [
            'wardpulse.plan_recovery',
            'Plan recovery',
            'A plan window you had run out of is usable again.',
            4,
          ],
        ],
      );
      expect(
        storage.values,
        isEmpty,
      ); // Readiness never consumes a foreground attempt.
      await LocalRecoveryNotifier(coordinator: coordinator).notify((
        accountId: 'account',
        provider: 'claude',
        allowanceId: 'weekly',
        label: 'Weekly plan',
        resetsAt: null,
      ));
      expect(calls.last.method, 'show');
      expect(calls.where((call) => call.method == 'initialize'), hasLength(1));
      expect(
        calls.where((call) => call.method == 'createNotificationChannel'),
        hasLength(2),
      );
      expect(
        calls.any(
          (call) =>
              call.method == 'requestNotificationsPermission' ||
              call.method.startsWith('delete'),
        ),
        isFalse,
      );
      expect(storage.values, isEmpty);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  int idOf(String accountId, String allowanceId) => recoveryNotificationId((
    accountId: accountId,
    provider: 'claude',
    allowanceId: allowanceId,
    label: 'Weekly plan',
    resetsAt: null,
  ));

  test('a window keeps its id, so a second telling replaces the first', () {
    // The reporting order risks a repeat on purpose, and that is only harmless
    // while the id stays the same one — run after run, not just call after
    // call, which is why it is not a `hashCode`.
    expect(idOf('claude-local', 'weekly'), 2077179748);
  });

  test('what it says is the family and the window, and nothing else', () {
    const recovery = (
      accountId: 'claude-local',
      provider: 'claude',
      allowanceId: 'claude-weekly',
      label: 'Weekly plan',
      resetsAt: null,
    );

    final title = recoveryNotificationTitle(recovery);

    expect(title, 'Claude · Weekly plan');
    // The rule from SECURITY_MODEL.md, read off the text a locked screen shows.
    expect(title, isNot(contains(recovery.accountId)));
    expect(title, isNot(contains(recovery.allowanceId)));
    expect(recoveryNotificationBody, 'Usable again.');
  });

  test('two windows of one account do not share an id', () {
    expect(idOf('claude-local', 'weekly'), isNot(idOf('claude-local', 'five')));
  });

  test('one window name under two accounts does not collide', () {
    expect(
      idOf('claude-local', 'weekly'),
      isNot(idOf('codex-local', 'weekly')),
    );
  });
}
