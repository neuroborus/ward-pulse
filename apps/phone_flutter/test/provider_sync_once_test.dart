import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ward_pulse_phone/dashboard/dashboard_models.dart';
import 'package:ward_pulse_phone/dashboard/dashboard_repository.dart';
import 'package:ward_pulse_phone/settings/watch_ring_preferences.dart';
import 'package:ward_pulse_phone/sync/headless_provider_sync.dart';
import 'package:ward_pulse_phone/sync/provider_sync_once.dart';
import 'package:ward_pulse_phone/sync/watch_sync_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'headless validates ownership immediately before each surface',
    () async {
      final attempts = <String>[];
      var current = true;
      await providerSyncOnce(
        load:
            () async => ProviderSyncWork(
              isCurrent: () async => current,
              syncWatch: () async {
                attempts.add('watch');
                current = false;
              },
              syncWidget: () async {
                attempts.add('widget');
              },
              syncRecoveries: () async {
                attempts.add('recovery');
              },
            ),
      );
      expect(attempts, ['watch']);
    },
  );
  test(
    'retired headless snapshot cannot reach any surface or recovery',
    () async {
      final attempts = <String>[];
      await providerSyncOnce(
        load:
            () async => ProviderSyncWork(
              isCurrent: () async => false,
              syncWatch: () async {
                attempts.add('watch');
              },
              syncWidget: () async {
                attempts.add('widget');
              },
              syncRecoveries: () async {
                attempts.add('recovery');
              },
            ),
      );
      expect(attempts, isEmpty);
    },
  );

  test('missing watch plugin does not skip widget or recovery work', () async {
    final attempts = <String>[];
    final failures = <_RecordedFailure>[];
    final snapshot = DashboardSnapshot.empty(
      generatedAt: DateTime.utc(2026, 10, 4),
    );

    await providerSyncOnce(
      load:
          () async => ProviderSyncWork(
            syncWatch: () async {
              attempts.add('watch');
              // No mock handler: this is the real headless failure mode that used
              // to stop the tick at the activity-owned channel.
              await const MethodChannelWatchSyncService().sync(
                snapshot,
                const WatchRingPreferences(),
              );
            },
            syncWidget: () async {
              attempts.add('widget');
            },
            syncRecoveries: () async {
              attempts.add('recovery');
            },
          ),
      logFailure: (step, error, stackTrace) {
        failures.add((step: step, error: error, stackTrace: stackTrace));
      },
    );

    expect(attempts, ['watch', 'widget', 'recovery']);
    expect(failures, hasLength(1));
    expect(failures.single.step, 'watch');
    expect(failures.single.error, isA<MissingPluginException>());
    expect(failures.single.stackTrace.toString(), isNotEmpty);
  });

  for (final failedStep in ['watch', 'widget']) {
    test(
      '$failedStep failure leaves every step attempted exactly once',
      () async {
        final attempts = {'watch': 0, 'widget': 0, 'recovery': 0};
        final failures = <_RecordedFailure>[];

        Future<void> attempt(String step) async {
          attempts[step] = attempts[step]! + 1;
          if (step == failedStep) {
            throw StateError('$step unavailable');
          }
        }

        await providerSyncOnce(
          load:
              () async => ProviderSyncWork(
                syncWatch: () => attempt('watch'),
                syncWidget: () => attempt('widget'),
                syncRecoveries: () => attempt('recovery'),
              ),
          logFailure: (step, error, stackTrace) {
            failures.add((step: step, error: error, stackTrace: stackTrace));
          },
        );

        expect(attempts, {'watch': 1, 'widget': 1, 'recovery': 1});
        expect(failures, hasLength(1));
        expect(failures.single.step, failedStep);
        expect(failures.single.error, isA<StateError>());
        expect(failures.single.stackTrace.toString(), isNotEmpty);
      },
    );
  }

  test('setup failure is logged while the recognized task succeeds', () async {
    final failures = <_RecordedFailure>[];

    final succeeded = await runHeadlessProviderTask(
      HeadlessProviderSync.taskName,
      sync:
          () => providerSyncOnce(
            load: () async => throw StateError('credentials unavailable'),
            markWidgetStale: () async {},
            logFailure: (step, error, stackTrace) {
              failures.add((step: step, error: error, stackTrace: stackTrace));
            },
          ),
    );

    expect(succeeded, isTrue);
    expect(failures, hasLength(1));
    expect(failures.single.step, 'setup');
    expect(failures.single.error, isA<StateError>());
    expect(failures.single.stackTrace.toString(), isNotEmpty);
  });

  test(
    'provider load failure marks retained widget rows stale and redraws',
    () async {
      final data = <String, Object?>{
        'row_count': 1,
        'empty': '0',
        'stale': '0',
        'row_0_percent': '46% left',
        'row_0_label': 'Claude plan',
      };
      final original = Map<String, Object?>.from(data);
      var redraws = 0;
      const channel = MethodChannel('home_widget');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, (call) async {
        final args = Map<String, Object?>.from(call.arguments as Map);
        switch (call.method) {
          case 'getWidgetData':
            return data[args['id']] ?? args['defaultValue'];
          case 'saveWidgetData':
            data[args['id']! as String] = args['data'];
            return true;
          case 'updateWidget':
            redraws += 1;
            return true;
          default:
            throw MissingPluginException();
        }
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      final failures = <String>[];
      final succeeded = await runHeadlessProviderTask(
        HeadlessProviderSync.taskName,
        sync:
            () => providerSyncOnce(
              load: () async => throw const DashboardLoadException(),
              logFailure: (step, _, _) => failures.add(step),
            ),
      );

      expect(succeeded, isTrue);
      expect(failures, ['setup']);
      expect(data, {...original, 'stale': '1'});
      expect(redraws, 1);
    },
  );

  test(
    'stale widget delivery failure is logged independently from setup',
    () async {
      final failures = <String>[];
      final succeeded = await runHeadlessProviderTask(
        HeadlessProviderSync.taskName,
        sync:
            () => providerSyncOnce(
              load: () async => throw const DashboardLoadException(),
              markWidgetStale:
                  () async => throw StateError('Widget unavailable'),
              logFailure: (step, _, _) => failures.add(step),
            ),
      );
      expect(succeeded, isTrue);
      expect(failures, ['setup', 'widget']);
    },
  );
}

typedef _RecordedFailure = ({String step, Object error, StackTrace stackTrace});
