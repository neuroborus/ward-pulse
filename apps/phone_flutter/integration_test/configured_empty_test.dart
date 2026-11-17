import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:ward_pulse_phone/app/ward_pulse_app.dart';
import 'package:ward_pulse_phone/dashboard/dashboard_models.dart';
import 'package:ward_pulse_phone/dashboard/dashboard_repository.dart';
import 'package:ward_pulse_phone/dashboard/dashboard_screen.dart';
import 'package:ward_pulse_phone/settings/alert_threshold_preferences.dart';
import 'package:ward_pulse_phone/sync/watch_sync_service.dart';
import 'package:ward_pulse_phone/widget/phone_widget_navigation.dart';

const _settings = AlertThresholdPreferences(
  connections: {
    'openai.plan': ConnectionAlertThresholds(plan: AlertPercentThreshold(at: 80)),
    'openai.platform': ConnectionAlertThresholds(
      budget: ConnectionBudget(today: 2500),
    ),
  },
);

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'configured empty app renders native idle with real Rust settings',
    (tester) async {
      final source = DashboardSnapshot.empty(
        generatedAt: DateTime.utc(2026, 11, 6, 12),
      );
      final rules = _Rules();
      final publication = Completer<MethodCall>();
      final calls = <MethodCall>[];
      const channel = MethodChannel('app.wardpulse/watch_sync');
      final messenger = binding.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        if (!publication.isCompleted) publication.complete(call);
        return null;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

      try {
        await tester.pumpWidget(
          WardPulseApp(
            repository: _Repository(source),
            alertThresholdStore: rules,
            watchSyncService: const _IsolatedWatch(),
            phoneWidgetNavigationService: _NoNavigation(),
            scheduleHeadlessSync: (_) async {},
          ),
        );
        final call = (await tester.runAsync(() => publication.future))!;
        await tester.pumpAndSettle(
          const Duration(milliseconds: 100),
          EnginePhase.sendSemanticsUpdate,
          const Duration(seconds: 10),
        );
        final screen = tester.widget<DashboardScreen>(
          find.byType(DashboardScreen),
        );
        final emitted = jsonDecode(call.arguments as String);
        binding.reportData = {
          'scope':
              'configured-empty integration target / real Rust and watch serializer',
          'input': source.toJson(),
          'settings': _settings.toJson(),
          'result': screen.snapshot.toJson(),
          'emitted': emitted,
          'completed': false,
        };
        expect(calls, hasLength(1));
        expect(call.method, 'syncWatchSummary');
        expect(rules.reads, greaterThan(0));
        expect(rules.writes, 0);
        expect([
          screen.snapshot.overallStatus.name,
          screen.snapshot.watchSummary.status.name,
          emitted['overallStatus'],
        ], ['ok', 'ok', 'ok']);
        expect(screen.snapshot.toJson(), source.toJson());
        expect(screen.snapshot.alertConditions, isEmpty);
        expect(screen.configuredBudgetPeriods['openai.platform'], {'today'});
        expect(find.byType(ConnectProviderPrompt), findsOneWidget);
        expect(find.text('Connect a provider'), findsOneWidget);
        expect(find.byType(Badge), findsNothing);
        expect(emitted['generatedAt'], source.generatedAt.toIso8601String());
        for (final key in ['providers', 'allowances', 'rings', 'alerts']) {
          expect(emitted[key], isEmpty, reason: key);
        }
        expect(emitted['creditsGlance'], isNull);
        expect(emitted['isStale'], isFalse);
        // Stock Android integration capture retains the original native frame
        // in reportData. The SDK restores its temporary image surface at teardown.
        await binding.convertFlutterSurfaceToImage();
        await tester.pump();
        final frame = await binding.takeScreenshot('configured-empty-idle');
        expect(frame, isNotEmpty);
      } finally {
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle(
          const Duration(milliseconds: 100),
          EnginePhase.sendSemanticsUpdate,
          const Duration(seconds: 10),
        );
      }
      binding.reportData!['completed'] = true;
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );
}

final class _Repository extends DashboardRepository {
  const _Repository(this.snapshot);
  final DashboardSnapshot snapshot;
  @override
  Future<DashboardSnapshot> load() async => snapshot;
}

final class _Rules implements AlertThresholdPreferenceStore {
  int reads = 0;
  int writes = 0;
  AlertThresholdPreferences value = _settings;
  @override
  Future<AlertThresholdPreferences> read() async {
    reads++;
    return value;
  }

  @override
  Future<void> write(AlertThresholdPreferences next) async {
    writes++;
    value = next;
  }
}

// Keep the real sender, intercepting only its publication above. Do not drain
// refresh requests belonging to the ordinary app or publish to paired devices.
final class _IsolatedWatch extends MethodChannelWatchSyncService {
  const _IsolatedWatch();
  @override
  void bindWatchRefreshListener(void Function() onRefresh) {}
  @override
  void unbindWatchRefreshListener() {}
}

final class _NoNavigation implements PhoneWidgetNavigationService {
  @override
  void bind(void Function() openDashboard) {}
  @override
  void unbind() {}
}
