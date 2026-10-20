import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ward_pulse_phone/app/ward_pulse_app.dart';
import 'package:ward_pulse_phone/app/ward_pulse_theme.dart';
import 'package:ward_pulse_phone/dashboard/dashboard_models.dart';
import 'package:ward_pulse_phone/dashboard/dashboard_load.dart';
import 'package:ward_pulse_phone/providers/connection_lifecycle.dart';
import 'package:ward_pulse_phone/sync/provider_reporting.dart';
import 'package:ward_pulse_phone/dashboard/plan_recoveries.dart';
import 'package:ward_pulse_phone/dashboard/provider_status_color.dart';
import 'package:ward_pulse_phone/dashboard/dashboard_repository.dart';
import 'package:ward_pulse_phone/dashboard/merging_connection_repository.dart';
import 'package:ward_pulse_phone/providers/provider_connection.dart';
import 'package:ward_pulse_phone/providers/provider_connection_row.dart';
import 'package:ward_pulse_phone/providers/provider_credential_store.dart';
import 'package:ward_pulse_phone/settings/alert_threshold_preferences.dart';
import 'package:ward_pulse_phone/settings/watch_ring_preferences.dart';
import 'package:ward_pulse_phone/settings/debug_data_preferences.dart';
import 'package:ward_pulse_phone/settings/refresh_interval_preferences.dart';
import 'package:ward_pulse_phone/widget/phone_widget_preferences.dart';
import 'package:ward_pulse_phone/sync/poll_cadence.dart';
import 'package:ward_pulse_phone/sync/provider_sync_scheduler.dart';
import 'package:ward_pulse_phone/sync/provider_sync_logger.dart';
import 'package:ward_pulse_phone/settings/recovery_notification_preferences.dart';
import 'package:ward_pulse_phone/sync/recovery_notifications.dart';
import 'package:ward_pulse_phone/sync/recovery_watchlist.dart';
import 'package:ward_pulse_phone/sync/watch_sync_service.dart';

void main() {
  for (final brightness in Brightness.values) {
    testWidgets(
      'app bar keeps the WardPulse mark and title in ${brightness.name}',
      (tester) async {
        tester.platformDispatcher.platformBrightnessTestValue = brightness;
        addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);

        await tester.pumpWidget(
          WardPulseApp(repository: const NoProvidersDashboardRepository()),
        );
        await tester.pumpAndSettle();

        final appBar = find.byType(AppBar);
        final leading = tester.widget<AppBar>(appBar).leading;
        expect(leading, isA<Center>());
        final mark = (leading! as Center).child;
        expect(mark, isA<Image>());
        final image = mark! as Image;
        final asset = image.image as AssetImage;

        expect(asset.assetName, 'assets/brand/wardpulse.png');
        expect(image.width, 32);
        expect(image.height, 32);
        expect(image.excludeFromSemantics, isTrue);
        expect(
          find.descendant(of: appBar, matching: find.text('WardPulse')),
          findsOneWidget,
        );
        expect(Theme.of(tester.element(appBar)).brightness, brightness);
      },
    );
  }

  testWidgets('full navigation labels fit at 360dp and retain 411dp layout', (
    tester,
  ) async {
    // Ahem's square glyphs cannot represent the phone's width boundary.
    await tester.runAsync(() async {
      final flutter = await Isolate.resolvePackageUri(
        Uri.parse('package:flutter/material.dart'),
      );
      final loader = FontLoader('Roboto');
      for (final weight in ['Regular', 'Medium']) {
        loader.addFont(
          File.fromUri(
            flutter!.resolve(
              '../../../bin/cache/artifacts/material_fonts/Roboto-$weight.ttf',
            ),
          ).readAsBytes().then((bytes) => ByteData.sublistView(bytes)),
        );
      }
      await loader.load();
    });
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(411, 800);
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    const labels = [
      'Dashboard',
      'Watchface',
      'Widget',
      'Providers',
      'Settings',
    ];
    List<({Rect glyphs, double baseline, Rect icon, Rect indicator})> measure() {
      final bar = find.byType(NavigationBar);
      final barRect = tester.getRect(bar);
      expect(barRect.size, Size(tester.view.physicalSize.width, 80));
      final destinations = find.byType(NavigationDestination);
      expect(destinations, findsNWidgets(labels.length));
      final measurements =
          <({Rect glyphs, double baseline, Rect icon, Rect indicator})>[];
      for (var index = 0; index < labels.length; index++) {
        final label = labels[index];
        final destination = destinations.at(index);
        final destinationRect = tester.getRect(destination);
        expect(
          destinationRect.width,
          closeTo(barRect.width / labels.length, 0.001),
        );
        final text = find.descendant(of: destination, matching: find.text(label));
        final paragraph = tester.renderObject<RenderParagraph>(text);
        final origin = paragraph.localToGlobal(Offset.zero);
        final paragraphRect = origin & paragraph.size;
        final boxes = paragraph.getBoxesForSelection(
          TextSelection(baseOffset: 0, extentOffset: label.length),
        );
        expect(boxes, hasLength(1), reason: label);
        expect(paragraph.didExceedMaxLines, isFalse, reason: label);
        expect(paragraph.textScaler.scale(10), closeTo(13, 0.001));
        final glyphs = boxes.single.toRect().shift(origin);
        for (var offset = 0; offset < label.length; offset++) {
          final characterBoxes = paragraph.getBoxesForSelection(
            TextSelection(baseOffset: offset, extentOffset: offset + 1),
          );
          expect(characterBoxes, hasLength(1), reason: '$label[$offset]');
          final character = characterBoxes.single.toRect().shift(origin);
          expect(character.top, closeTo(glyphs.top, 0.001), reason: label);
          expect(character.bottom, closeTo(glyphs.bottom, 0.001), reason: label);
          for (final bounds in [paragraphRect, destinationRect]) {
            expect(
              bounds.inflate(0.001).contains(character.topLeft),
              isTrue,
              reason: '$label[$offset] starts outside $bounds',
            );
            expect(
              bounds.inflate(0.001).contains(character.bottomRight),
              isTrue,
              reason: '$label[$offset] ends outside $bounds',
            );
          }
        }
        final relativeOrigin = Offset(destinationRect.center.dx, barRect.top);
        final measurement = (
          glyphs: glyphs.shift(-relativeOrigin),
          baseline:
              origin.dy +
              paragraph.getDistanceToBaseline(TextBaseline.alphabetic)! -
              barRect.top,
          icon: tester
              .getRect(
                find.descendant(of: destination, matching: find.byType(Icon)),
              )
              .shift(-relativeOrigin),
          indicator: tester
              .getRect(
                find.descendant(
                  of: destination,
                  matching: find.byType(NavigationIndicator),
                ),
              )
              .shift(-relativeOrigin),
        );
        if (measurements.isNotEmpty) {
          expect(
            measurement.baseline,
            closeTo(measurements.first.baseline, 0.001),
            reason: label,
          );
          expect(
            measurement.icon,
            rectMoreOrLessEquals(measurements.first.icon, epsilon: 0.001),
            reason: label,
          );
          expect(
            measurement.indicator,
            rectMoreOrLessEquals(measurements.first.indicator, epsilon: 0.001),
            reason: label,
          );
          expect(
            measurement.glyphs.height,
            closeTo(measurements.first.glyphs.height, 0.001),
            reason: label,
          );
        }
        measurements.add(measurement);
      }
      return measurements;
    }

    const app = WardPulseApp(repository: NoProvidersDashboardRepository());
    await tester.pumpWidget(app);
    await tester.pumpAndSettle();
    final destinations =
        tester.widget<NavigationBar>(find.byType(NavigationBar)).destinations;
    final ordinary = measure();

    // A stock Material bar is the reference for ordinary-width typography
    // and for icon/indicator geometry at both widths.
    await tester.pumpWidget(
      MaterialApp(
        theme: wardPulseLightTheme,
        home: Scaffold(
          bottomNavigationBar: NavigationBar(destinations: destinations),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final reference = measure();
    expect(ordinary, reference);

    await tester.pumpWidget(app);
    await tester.pumpAndSettle();
    tester.view.physicalSize = const Size(360, 800);
    await tester.pumpAndSettle();
    final narrow = measure();
    for (var index = 0; index < labels.length; index++) {
      expect(
        narrow[index].icon,
        rectMoreOrLessEquals(reference[index].icon, epsilon: 0.001),
      );
      expect(
        narrow[index].indicator,
        rectMoreOrLessEquals(reference[index].indicator, epsilon: 0.001),
      );
      expect(
        narrow[index].glyphs.width,
        lessThan(reference[index].glyphs.width),
      );
    }

    // A measurably larger common candidate must fail at least one label;
    // this guards against replacing measured fitting with a small fixed size.
    var largerWouldWrap = false;
    for (final label in labels) {
      final paragraph = tester.renderObject<RenderParagraph>(
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text(label),
        ),
      );
      final style = paragraph.text.style!;
      final painter = TextPainter(
        text: TextSpan(
          text: label,
          style: style.copyWith(fontSize: style.fontSize! + 0.02),
        ),
        textDirection: paragraph.textDirection,
        textScaler: paragraph.textScaler,
        locale: paragraph.locale,
      )..layout();
      largerWouldWrap |= painter.width > paragraph.constraints.maxWidth;
      painter.dispose();
    }
    expect(largerWouldWrap, isTrue);

    // Settle the other long label's selected style without duplicating the
    // existing tests of what each destination opens.
    await tester.tap(find.text('Watchface'));
    await tester.pumpAndSettle();
    expect(measure(), narrow);
    tester.view.physicalSize = const Size(411, 800);
    await tester.pumpAndSettle();
    expect(measure(), reference);
    expect(tester.takeException(), isNull);
  });

  testWidgets('renders mock history and opens Providers catalog', (
    tester,
  ) async {
    final fixture =
        File(
          '../../fixtures/snapshots/dashboard_today.json',
        ).readAsStringSync();
    final snapshot = DashboardSnapshot.fromJsonString(fixture);

    await tester.pumpWidget(
      WardPulseApp(repository: ValueDashboardRepository(snapshot)),
    );
    await tester.pumpAndSettle();

    expect(find.text('WardPulse'), findsOneWidget);

    final dashboard = find.byType(Scrollable).first;
    await tester.scrollUntilVisible(
      find.text('Usage history'),
      300,
      scrollable: dashboard,
    );
    expect(find.text('Usage history'), findsOneWidget);
    expect(find.text('4 buckets'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('mock-fast'),
      300,
      scrollable: dashboard,
    );
    expect(find.text('mock-fast'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('No alerts'),
      300,
      scrollable: dashboard,
    );
    expect(find.text('No alerts'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('Platform spend'),
      300,
      scrollable: dashboard,
    );
    expect(find.text('Today'), findsWidgets);

    await tester.tap(find.text('Providers'));
    await tester.pumpAndSettle();

    // Which family sits where is the tab's own business
    // (providers_screen_test.dart); this test only asks that the catalog
    // opened, so it scrolls to the row instead of assuming a position.
    await tester.scrollUntilVisible(
      find.text('Codex plan'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Codex plan'), findsOneWidget);
    expect(find.text('Not connected'), findsWidgets);
  });

  testWidgets('syncs an empty watch summary when no providers are connected', (
    tester,
  ) async {
    final watchSyncService = _FakeWatchSyncService();

    await tester.pumpWidget(
      WardPulseApp(
        repository: const NoProvidersDashboardRepository(),
        watchSyncService: watchSyncService,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Connect a provider'), findsOneWidget);
    expect(watchSyncService.syncedSnapshots, hasLength(1));
    expect(watchSyncService.syncedSnapshots.single.accounts, isEmpty);
  });

  testWidgets('Wear refresh reloads when the phone has no providers', (
    tester,
  ) async {
    final watchSyncService = _FakeWatchSyncService();
    var loads = 0;
    final repository = _CountingDashboardRepository(() {
      loads += 1;
      return DashboardSnapshot.empty(
        generatedAt: DateTime.utc(
          2026,
          7,
          26,
          12,
        ).subtract(Duration(minutes: loads == 1 ? 10 : 0)),
      );
    });

    await tester.pumpWidget(
      WardPulseApp(repository: repository, watchSyncService: watchSyncService),
    );
    await tester.pumpAndSettle();
    expect(loads, 1);
    expect(watchSyncService.syncedSnapshots, hasLength(1));

    watchSyncService.refreshHandler!();
    await tester.pumpAndSettle();

    expect(loads, 2);
    expect(watchSyncService.syncedSnapshots.length, greaterThanOrEqualTo(2));
  });

  testWidgets(
    'Wear refresh failure retains the warm live connection as stale',
    (tester) async {
      final snapshot = _asConnection(
        DashboardSnapshot.fromJsonString(
          File(
            '../../fixtures/snapshots/dashboard_today.json',
          ).readAsStringSync(),
        ),
      );
      var failReport = false;
      final repository = MergingConnectionRepository(
        fallback: const NoProvidersDashboardRepository(),
        loadReport: () async {
          if (failReport) {
            throw StateError('Network unavailable');
          }
          return 'report';
        },
        normalizeReport: (_) => snapshot.toJsonString(),
        mapError: (_) => const DashboardLoadException(),
        logger: const NullProviderSyncLogger(),
      );
      final watch = _FakeWatchSyncService();
      await tester.pumpWidget(
        WardPulseApp(repository: repository, watchSyncService: watch),
      );
      await tester.pumpAndSettle();
      expect(
        watch.syncedSnapshots.last.accounts.single.accountId,
        'anthropic-platform',
      );

      failReport = true;
      watch.refreshHandler!();
      await tester.pumpAndSettle();

      final retained = watch.syncedSnapshots.last;
      expect(retained.overallStatus, ProviderStatus.stale);
      expect(retained.syncIssue, DashboardSyncIssue.dashboardUnavailable);
      expect(retained.generatedAt, snapshot.generatedAt);
      expect(retained.accounts.single.accountId, 'anthropic-platform');
      expect(retained.accounts.single.status, ProviderStatus.stale);
      expect(
        retained.accounts.single.today.toJson(),
        snapshot.accounts.single.today.toJson(),
      );
      expect(find.text('Usage dashboard'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('queues a development watch sync', (tester) async {
    final snapshot = DashboardSnapshot.fromJsonString(
      File('../../fixtures/snapshots/dashboard_today.json').readAsStringSync(),
    );
    final watchSyncService = _FakeWatchSyncService();

    await tester.pumpWidget(
      WardPulseApp(
        repository: ValueDashboardRepository(snapshot),
        watchSyncService: watchSyncService,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    expect(watchSyncService.syncedSnapshots, [snapshot]);

    await tester.scrollUntilVisible(
      find.text('Send to watch'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -160));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Sync'));
    await tester.pumpAndSettle();

    expect(watchSyncService.syncedSnapshots, [snapshot, snapshot]);
    expect(find.text('Watch summary queued'), findsOneWidget);
  });

  testWidgets('Settings shows systemic sections without Watch display', (
    tester,
  ) async {
    final snapshot = DashboardSnapshot.fromJsonString(
      File('../../fixtures/snapshots/dashboard_today.json').readAsStringSync(),
    );

    await tester.pumpWidget(
      WardPulseApp(repository: ValueDashboardRepository(snapshot)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();

    expect(find.text('Display'), findsNothing);
    expect(find.text('Alerts'), findsNothing);
    expect(find.text('Refresh'), findsOneWidget);
    expect(find.text('Watch display'), findsNothing);
    expect(
      find.textContaining('Temporary until the Watchface tab'),
      findsNothing,
    );
    await tester.scrollUntilVisible(
      find.text('Diagnostics'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Diagnostics'), findsOneWidget);
    expect(find.text('Sync'), findsWidgets);
    expect(find.text('Watch summary'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Help'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.widgetWithText(ListTile, 'Help'), findsOneWidget);
  });

  testWidgets('Settings keeps Help and Legal without snapshot or debug', (
    tester,
  ) async {
    await tester.pumpWidget(
      WardPulseApp(
        repository: const _FailingDashboardRepository(
          DashboardSyncIssue.dashboardUnavailable,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();

    expect(find.text('Debug'), findsNothing);
    expect(find.text('Diagnostics'), findsNothing);
    await tester.scrollUntilVisible(
      find.text('Help'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.widgetWithText(ListTile, 'Help'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Legal'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Legal'), findsOneWidget);
    expect(
      find.text(
        'WardPulse is an independent usage monitor. It is not affiliated with, '
        'endorsed by, or sponsored by OpenAI, Anthropic, Cursor, Google, or any '
        'other provider. Product names are trademarks of their respective owners.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('Settings Help opens the public guide in an external browser', (
    tester,
  ) async {
    const channel = MethodChannel('plugins.flutter.io/url_launcher');
    final messenger = tester.binding.defaultBinaryMessenger;
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return true;
    });

    await tester.pumpWidget(
      WardPulseApp(repository: const NoProvidersDashboardRepository()),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Help'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Help'));
    await tester.pumpAndSettle();

    expect(calls, hasLength(1));
    expect(calls.single.method, 'launch');
    expect(
      calls.single.arguments,
      allOf(
        containsPair('url', 'https://neuroborus.github.io/ward-pulse/'),
        containsPair('useWebView', false),
        containsPair('useSafariVC', false),
        containsPair('universalLinksOnly', false),
        containsPair('headers', isEmpty),
      ),
    );
    expect(find.byType(SnackBar), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final throwsException in [false, true]) {
    for (final disposeBeforeCompletion in [false, true]) {
      testWidgets(
        'Settings Help handles '
        '${throwsException ? 'a platform exception' : 'a false launch result'}'
        '${disposeBeforeCompletion ? ' after disposal' : ''}',
        (tester) async {
          const channel = MethodChannel('plugins.flutter.io/url_launcher');
          final messenger = tester.binding.defaultBinaryMessenger;
          addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
          final completion = Completer<bool>();
          final calls = <MethodCall>[];
          messenger.setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            return completion.future;
          });

          await tester.pumpWidget(
            WardPulseApp(repository: const NoProvidersDashboardRepository()),
          );
          await tester.pumpAndSettle();
          await tester.tap(find.text('Settings'));
          await tester.pumpAndSettle();
          await tester.scrollUntilVisible(
            find.text('Help'),
            300,
            scrollable: find.byType(Scrollable).first,
          );
          await tester.tap(find.text('Help'));
          await tester.pump();
          expect(calls, hasLength(1));
          expect(calls.single.method, 'launch');
          expect(find.byType(SnackBar), findsNothing);

          if (disposeBeforeCompletion) {
            await tester.pumpWidget(const SizedBox.shrink());
          }
          if (throwsException) {
            completion.completeError(PlatformException(code: 'launch_failed'));
          } else {
            completion.complete(false);
          }
          await tester.pumpAndSettle();

          expect(tester.takeException(), isNull);
          expect(
            find.text('Could not open the browser'),
            disposeBeforeCompletion ? findsNothing : findsOneWidget,
          );
        },
      );
    }
  }

  testWidgets('slot cards say where metrics come from when there are none', (
    tester,
  ) async {
    await tester.pumpWidget(
      WardPulseApp(repository: const NoProvidersDashboardRepository()),
    );
    await tester.pumpAndSettle();

    for (final tab in ['Watchface', 'Widget']) {
      await tester.tap(find.text(tab));
      await tester.pumpAndSettle();
      // A bare header card would read as a broken screen.
      expect(find.text('No metrics yet'), findsOneWidget, reason: tab);
      expect(find.byType(CheckboxListTile), findsNothing, reason: tab);
    }
  });

  for (final trigger in ['refresh', 'scheduled']) {
    testWidgets(
      '$trigger rechecks revision after delayed ownership validation',
      (tester) async {
        final live = DashboardSnapshot.fromJsonString(
          File(
            '../../fixtures/snapshots/dashboard_today.json',
          ).readAsStringSync(),
        );
        final repository = _PublicationRepository(live);
        final watch = _FakeWatchSyncService();
        final scheduler = _ManualProviderSyncScheduler();
        addTearDown(scheduler.dispose);
        await tester.pumpWidget(
          WardPulseApp(
            repository: repository,
            watchSyncService: watch,
            syncScheduler: scheduler,
          ),
        );
        await tester.pumpAndSettle();
        repository.delayNextValidation = true;
        if (trigger == 'refresh') {
          await tester.tap(find.byTooltip('Refresh'));
        } else {
          scheduler.tick();
        }
        await tester.pump();
        await tester.pump();
        expect(repository.validationStarted, isTrue);
        repository.snapshot = DashboardSnapshot.empty();
        await tester.tap(find.byTooltip('Refresh'));
        await tester.pumpAndSettle();
        expect(watch.syncedSnapshots.last.accounts, isEmpty);
        repository.validation.complete(true);
        await tester.pumpAndSettle();
        expect(watch.syncedSnapshots.last.accounts, isEmpty);
        expect(find.text('Connect a provider'), findsWidgets);
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets('delayed alert write cannot reinstate a removed account', (
    tester,
  ) async {
    final live = DashboardSnapshot.fromJsonString(
      File('../../fixtures/snapshots/dashboard_today.json').readAsStringSync(),
    );
    final repository = _PublicationRepository(live);
    final scheduler = _ManualProviderSyncScheduler();
    addTearDown(scheduler.dispose);
    final store = _DelayedAlertThresholdStore();
    final watch = _FakeWatchSyncService();
    await tester.pumpWidget(
      WardPulseApp(
        repository: repository,
        syncScheduler: scheduler,
        watchSyncService: watch,
        alertThresholdStore: store,
        applyAlertSettings: (current, _) => current,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Providers'));
    await tester.pumpAndSettle();
    final button = find.descendant(
      of: find.ancestor(
        of: find.text('Platform reporting'),
        matching: find.byType(ProviderConnectionRow),
      ),
      matching: find.byWidgetPredicate(
        (widget) => widget is IconButton && widget.tooltip == 'Budget limits',
      ),
    );
    await tester.scrollUntilVisible(
      button,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(button.hitTestable(), findsOneWidget);
    await tester.tap(button);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '25');
    await tester.tap(find.text('Save'));
    await tester.pump();
    expect(store.started, isTrue);
    repository.snapshot = DashboardSnapshot.empty();
    scheduler.tick();
    await tester.pump();
    await tester.pump();
    store.release.complete();
    await tester.pumpAndSettle();
    expect(watch.syncedSnapshots.last.accounts, isEmpty);
    await tester.tap(find.text('Dashboard'));
    await tester.pumpAndSettle();
    expect(find.text('Connect a provider'), findsWidgets);
    expect(
      store.value
          .forConnection(ProviderConnections.openAiPlatform)
          .budget
          .today,
      2500,
    );
  });

  testWidgets('a reload keeps the dashboard on screen', (tester) async {
    final snapshot = DashboardSnapshot.fromJsonString(
      File('../../fixtures/snapshots/dashboard_today.json').readAsStringSync(),
    );

    await tester.pumpWidget(
      WardPulseApp(repository: ValueDashboardRepository(snapshot)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Usage dashboard'), findsOneWidget);

    // The refresh used to blank the tab and draw it again, which read as a
    // flicker over the numbers the reader was looking at.
    await tester.tap(find.byTooltip('Refresh'));
    await tester.pump();
    expect(find.text('Usage dashboard'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);

    await tester.pumpAndSettle();
    expect(find.text('Usage dashboard'), findsOneWidget);
  });

  testWidgets('slot count follows the rows, not a stored selection', (
    tester,
  ) async {
    final store =
        _MemoryWatchRingStore()
          ..value = const WatchRingPreferences(
            selectedIds: [
              'allowance.codex.plan',
              'budget.anthropic.platform.today',
              'budget.anthropic.platform.week',
            ],
          );

    await tester.pumpWidget(
      WardPulseApp(
        repository: const _FailingDashboardRepository(
          DashboardSyncIssue.providerUnavailable,
        ),
        watchRingPreferenceStore: store,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Watchface'));
    await tester.pumpAndSettle();

    // A failed load leaves no rows to tick, so counting the stored ids would
    // claim three slots the screen does not show.
    expect(find.text('No metrics yet'), findsOneWidget);
    expect(find.textContaining('0 of 3 slots used'), findsOneWidget);
  });

  testWidgets('Watchface tab owns ring slots and payload preview', (
    tester,
  ) async {
    final snapshot = _asConnection(
      DashboardSnapshot.fromJsonString(
        File(
          '../../fixtures/snapshots/dashboard_today.json',
        ).readAsStringSync(),
      ),
    );
    final store = _MemoryWatchRingStore();

    await tester.pumpWidget(
      WardPulseApp(
        repository: ValueDashboardRepository(snapshot),
        watchRingPreferenceStore: store,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Watchface'));
    await tester.pumpAndSettle();

    expect(find.text('Ring slots'), findsOneWidget);
    expect(find.text('Wear & watch face'), findsOneWidget);
    expect(find.text('Next watch payload'), findsOneWidget);
    // Budget rings are per connection, and the connection is a heading now.
    expect(find.text('Anthropic'), findsWidgets);

    await tester.scrollUntilVisible(
      find.text('Anthropic'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    // Defaults select available metrics; toggling Today off persists an explicit list.
    final todayTile =
        find.widgetWithText(CheckboxListTile, 'Today').hitTestable().first;
    // A full stack greys every unpicked row; the count is what tells that
    // apart from a fault, so it has to follow the selection.
    expect(find.textContaining('3 of 3 slots used'), findsOneWidget);
    await tester.tap(todayTile);
    await tester.pumpAndSettle();

    expect(store.value.selectedIds, isNotNull);
    expect(find.textContaining('2 of 3 slots used'), findsOneWidget);
  });

  testWidgets('a metric with nothing to show stays listed and refuses a tap', (
    tester,
  ) async {
    final source = DashboardSnapshot.fromJsonString(
      File('../../fixtures/snapshots/dashboard_today.json').readAsStringSync(),
    );
    final account =
        Map<String, Object?>.from(source.primaryAccount!.toJson())
          ..['accountId'] = 'anthropic-platform'
          ..['provider'] = 'claude'
          ..['connection'] = 'anthropic.platform'
          // No limit set for the month, so the ring has no percentage to draw.
          ..['month'] = {
            'period': 'month',
            'spent': {'minorUnits': 2500, 'currency': 'USD'},
            'limit': null,
            'remaining': null,
            'usedPercent': null,
            'projectedTotal': null,
            'status': 'ok',
          };
    final snapshot = DashboardSnapshot.fromJson({
      ...source.toJson(),
      'accounts': [account],
    });

    await tester.pumpWidget(
      WardPulseApp(
        repository: ValueDashboardRepository(snapshot),
        watchRingPreferenceStore: _MemoryWatchRingStore(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Watchface'));
    await tester.pumpAndSettle();

    final month = find.widgetWithText(CheckboxListTile, 'Month');
    await tester.scrollUntilVisible(
      month,
      200,
      scrollable: find.byType(Scrollable).first,
    );

    // Still under its connection, saying why it cannot be picked, and the box
    // refuses the tap — sunk rather than hidden.
    expect(month, findsOneWidget);
    expect(
      find.descendant(
        of: month,
        matching: find.byTooltip(
          'Set this period’s limit under Providers · Budget limits.',
        ),
      ),
      findsOneWidget,
    );
    expect(tester.widget<CheckboxListTile>(month).onChanged, isNull);
  });

  testWidgets('Widget tab owns metrics independently of Watchface', (
    tester,
  ) async {
    final snapshot = _asConnection(
      DashboardSnapshot.fromJsonString(
        File(
          '../../fixtures/snapshots/dashboard_today.json',
        ).readAsStringSync(),
      ),
    );
    final store = _MemoryPhoneWidgetStore();

    await tester.pumpWidget(
      WardPulseApp(
        repository: ValueDashboardRepository(snapshot),
        phoneWidgetPreferenceStore: store,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Widget'));
    await tester.pumpAndSettle();

    expect(find.text('Widget metrics'), findsOneWidget);
    expect(find.text('Home screen widget'), findsOneWidget);
    // The picker is an outline now, so the preview sits below its headings.
    await tester.scrollUntilVisible(
      find.text('Next widget payload'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Next widget payload'), findsOneWidget);
    expect(find.textContaining('independent of Watchface'), findsOneWidget);
    // Its own copy of the count, on a screen with six slots instead of three.
    expect(find.textContaining('of 6 slots used'), findsOneWidget);

    // The connection is a heading here now, so its rows carry only the period.
    expect(find.text('Anthropic'), findsWidgets);
    final todayTile =
        find.widgetWithText(CheckboxListTile, 'Today').hitTestable().first;
    await tester.tap(todayTile);
    await tester.pumpAndSettle();

    expect(store.value.selectedIds, isNotNull);
  });

  testWidgets('Providers Platform row saves a budget limit and its alert', (
    tester,
  ) async {
    final snapshot = DashboardSnapshot.fromJsonString(
      File('../../fixtures/snapshots/dashboard_today.json').readAsStringSync(),
    );
    final store = _MemoryAlertThresholdStore();
    // A connection rule the budget dialog must not clobber on save.
    store.value = store.value.withConnection(
      ProviderConnections.codexPlan,
      const ConnectionAlertThresholds(plan: AlertPercentThreshold(at: 90)),
    );

    await tester.pumpWidget(
      WardPulseApp(
        repository: ValueDashboardRepository(snapshot),
        alertThresholdStore: store,
        // Widget tests do not load libward_pulse_ffi.so; prefs UI only.
        applyAlertSettings: (current, _) => current,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Providers'));
    await tester.pumpAndSettle();

    Finder platformButton(String tooltip) => find.descendant(
      of: find.ancestor(
        of: find.text('Platform reporting'),
        matching: find.byType(ProviderConnectionRow),
      ),
      matching: find.byWidgetPredicate(
        (widget) => widget is IconButton && widget.tooltip == tooltip,
      ),
    );

    // The limit comes first: a percentage is meaningless without one.
    await tester.scrollUntilVisible(
      platformButton('Budget limits'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(platformButton('Budget limits').hitTestable(), findsOneWidget);
    await tester.tap(platformButton('Budget limits'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Budget · Platform reporting'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, '25');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    await tester.tap(platformButton('Alert thresholds'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Alerts · Platform reporting'), findsOneWidget);
    expect(find.text('Today'), findsOneWidget);
    expect(find.text('Week'), findsOneWidget);
    expect(find.text('Month'), findsOneWidget);

    await tester.tap(find.text('Off').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('20% left').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(
      store.value.forConnection(ProviderConnections.openAiPlatform).today.at,
      80,
    );
    expect(
      store.value
          .forConnection(ProviderConnections.openAiPlatform)
          .budget
          .today,
      2500,
    );
    expect(
      store.value.forConnection(ProviderConnections.codexPlan).plan.at,
      90,
    );
  });

  testWidgets('Providers plan row can save connection alert thresholds', (
    tester,
  ) async {
    final snapshot = DashboardSnapshot.fromJsonString(
      File('../../fixtures/snapshots/dashboard_today.json').readAsStringSync(),
    );
    final store = _MemoryAlertThresholdStore();

    await tester.pumpWidget(
      WardPulseApp(
        repository: ValueDashboardRepository(snapshot),
        alertThresholdStore: store,
        applyAlertSettings: (current, _) => current,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Providers'));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('Codex plan'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(
      find.descendant(
        of: find.widgetWithText(ProviderConnectionRow, 'Codex plan'),
        matching: find.byTooltip('Alert thresholds'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Alerts ·'), findsOneWidget);
    // A plan connection offers window rules, not spend budgets.
    expect(find.text('Plan'), findsOneWidget);
    expect(find.text('Purchased'), findsOneWidget);
    expect(find.text('Today'), findsNothing);
    await tester.tap(find.text('Off').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('30% left').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(
      store.value.forConnection(ProviderConnections.codexPlan).plan.at,
      70,
    );
  });

  testWidgets('watch sync failure does not block the dashboard', (
    tester,
  ) async {
    final snapshot = DashboardSnapshot.fromJsonString(
      File('../../fixtures/snapshots/dashboard_today.json').readAsStringSync(),
    );

    await tester.pumpWidget(
      WardPulseApp(
        repository: ValueDashboardRepository(snapshot),
        watchSyncService: const _FailingWatchSyncService(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('WardPulse'), findsOneWidget);
    expect(find.text('Dashboard unavailable'), findsNothing);
    // Nothing deviates, so the app bar says nothing at all
    // (PHONE_DASHBOARD_DESIGN.md).
    expect(find.byType(Badge), findsNothing);
  });

  testWidgets('labels previous dashboard data as stale', (tester) async {
    final snapshot = DashboardSnapshot.fromJsonString(
      File('../../fixtures/snapshots/dashboard_today.json').readAsStringSync(),
    ).withStaleStatus(syncIssue: DashboardSyncIssue.authentication);

    await tester.pumpWidget(
      WardPulseApp(repository: ValueDashboardRepository(snapshot)),
    );
    await tester.pumpAndSettle();

    // Staleness is an account state, so no card carries a glyph for it: the
    // family answers with a count and the app bar with a way in — never the
    // same mark twice down the screen (PHONE_DASHBOARD_DESIGN.md).
    expect(find.byIcon(Icons.schedule), findsNothing);
    expect(find.byTooltip('Stale'), findsWidgets);
    expect(find.byTooltip('Go to stale'), findsOneWidget);
    expect(
      find.textContaining('Showing previous data · Updated'),
      findsOneWidget,
    );
    expect(
      find.text(DashboardSyncIssue.authentication.message),
      findsOneWidget,
    );
    expect(
      find.byTooltip(DashboardSyncIssue.authentication.message),
      findsWidgets,
    );
    final appBarMark = find.byTooltip('Go to stale');
    expect(
      tester
          .widget<Badge>(
            find.descendant(of: appBarMark, matching: find.byType(Badge)),
          )
          .backgroundColor,
      providerStatusChipColors(
        Theme.of(tester.element(appBarMark)).colorScheme,
        ProviderStatus.stale,
      ).fill,
    );
  });

  testWidgets('the app-bar mark opens the Dashboard at the first problem', (
    tester,
  ) async {
    final snapshot =
        DashboardSnapshot.fromJsonString(
          File(
            '../../fixtures/snapshots/dashboard_today.json',
          ).readAsStringSync(),
        ).withStaleStatus();

    await tester.pumpWidget(
      WardPulseApp(repository: ValueDashboardRepository(snapshot)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    expect(find.text('Refresh interval'), findsOneWidget);

    // A rollup earns its place by leading somewhere, so it works from any tab.
    await tester.tap(find.byTooltip('Go to stale'));
    await tester.pumpAndSettle();

    // Settings is gone and the flagged section is the thing on screen — the
    // dashboard title has scrolled off above it, which is the point.
    expect(find.text('Refresh interval'), findsNothing);
    expect(find.byTooltip('Stale'), findsWidgets);
    expect(find.text('Usage dashboard'), findsNothing);

    // The request is spent: coming back later is an ordinary visit, not a
    // repeat of a tap the reader made once.
    await tester.tap(find.text('Providers'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dashboard'));
    await tester.pumpAndSettle();
    expect(find.text('Usage dashboard'), findsOneWidget);
  });

  testWidgets(
    'saved-key check survives tab disposal and a failed Label write',
    (tester) async {
      final store = _MemoryCredentialStore()..failLabelWrite = true;
      final writeRelease = Completer<void>();
      store.pendingWrite = writeRelease.future;
      final response = Completer<String>();
      var requests = 0;
      final repository = _reportingRepository(store, (_) {
        requests++;
        return response.future;
      });
      await tester.pumpWidget(
        WardPulseApp(repository: repository, credentialStore: store),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Providers'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Organization reporting'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).first, 'synthetic-key');
      await tester.enterText(
        find.byType(TextFormField).last,
        'Synthetic label',
      );
      await tester.tap(find.text('Save'));
      await tester.pump();
      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();
      expect(requests, 0);
      writeRelease.complete();
      await tester.pumpAndSettle();
      expect(requests, 1);
      expect(find.text('Key saved. Could not update label.'), findsOneWidget);
      response.completeError(
        const ProviderReportingException(
          ProviderReportingFailure.authentication,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Providers'));
      await tester.pumpAndSettle();
      expect(find.text('Key rejected'), findsOneWidget);
      expect(
        find.textContaining('Anthropic · Organization reporting'),
        findsWidgets,
      );
      expect(find.text('synthetic-key'), findsNothing);
      expect(requests, 1);
    },
  );

  testWidgets(
    'manual and automatic refresh do not duplicate an active saved-key check',
    (tester) async {
      final store = _MemoryCredentialStore();
      final response = Completer<String>();
      final scheduler = _ManualProviderSyncScheduler();
      addTearDown(scheduler.dispose);
      var requests = 0;
      final repository = _reportingRepository(store, (_) {
        requests++;
        return response.future;
      });
      await tester.pumpWidget(
        WardPulseApp(
          repository: repository,
          credentialStore: store,
          syncScheduler: scheduler,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Providers'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Organization reporting'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).first, 'synthetic-key');
      await tester.tap(find.text('Save'));
      await tester.pump();
      await tester.pump();
      expect(requests, 1);
      expect(find.text('Checking…'), findsOneWidget);
      expect(
        tester
            .widget<IconButton>(find.widgetWithIcon(IconButton, Icons.refresh))
            .onPressed,
        isNull,
      );
      final row = tester.widget<ProviderConnectionRow>(
        find.widgetWithText(ProviderConnectionRow, 'Organization reporting'),
      );
      expect(row.onTap, isNull);
      scheduler.tick();
      await tester.pump();
      expect(requests, 1);
      response.complete(DashboardSnapshot.empty().toJsonString());
      await tester.pumpAndSettle();
      expect(find.text('Connected'), findsOneWidget);
      expect(requests, 1);
    },
  );

  for (final previousSuccess in [false, true]) {
    testWidgets(
      'scheduled all-failed retries replace ${previousSuccess ? 'a later' : 'the initial'} Dashboard failure',
      (tester) async {
        final store = _MemoryCredentialStore();
        await store.writeSecret(
          ProviderConnections.anthropicPlatform,
          'synthetic-key',
        );
        final scheduler = _ManualProviderSyncScheduler();
        addTearDown(scheduler.dispose);
        ProviderReportingFailure? failure =
            previousSuccess ? null : ProviderReportingFailure.authentication;
        var requests = 0;
        final repository = _reportingRepository(store, (_) async {
          requests++;
          if (failure != null) throw ProviderReportingException(failure);
          return DashboardSnapshot.empty().toJsonString();
        });
        await tester.pumpWidget(
          WardPulseApp(
            repository: repository,
            credentialStore: store,
            syncScheduler: scheduler,
          ),
        );
        await tester.pumpAndSettle();
        if (previousSuccess) {
          repository.invalidate();
          failure = ProviderReportingFailure.authentication;
          await tester.tap(find.byTooltip('Refresh'));
          await tester.pumpAndSettle();
        }
        expect(
          find.textContaining(
            'Anthropic · Organization reporting: Key rejected',
          ),
          findsOneWidget,
        );
        await tester.tap(find.text('Providers'));
        await tester.pumpAndSettle();
        expect(find.text('Key rejected'), findsOneWidget);
        failure = ProviderReportingFailure.permissionDenied;
        scheduler.tick();
        await tester.pumpAndSettle();
        expect(find.text('Access denied'), findsOneWidget);
        await tester.tap(find.text('Dashboard'));
        await tester.pumpAndSettle();
        expect(
          find.textContaining(
            'Anthropic · Organization reporting: Access denied',
          ),
          findsOneWidget,
        );
        expect(find.textContaining('Key rejected'), findsNothing);
        expect(requests, previousSuccess ? 3 : 2);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('Remove retires Dashboard data even when local cleanup fails', (
    tester,
  ) async {
    final store = _MemoryCredentialStore()..failDeleteAfterRetirement = true;
    await store.writeSecret(
      ProviderConnections.anthropicPlatform,
      'synthetic-key',
    );
    await store.writeLabel(
      ProviderConnections.anthropicPlatform,
      'Synthetic label',
    );
    final json =
        DashboardSnapshot.fromJsonString(
          File(
            '../../fixtures/snapshots/dashboard_today.json',
          ).readAsStringSync(),
        ).toJson();
    final account = (json['accounts'] as List).single as Map;
    account['provider'] = 'claude';
    account['connection'] = ProviderConnections.anthropicPlatform.storageKey;
    final live = DashboardSnapshot.fromJson(json);
    var requests = 0;
    final repository = _reportingRepository(store, (_) async {
      requests++;
      return live.toJsonString();
    });
    final watch = _FakeWatchSyncService();
    await tester.pumpWidget(
      WardPulseApp(
        repository: repository,
        credentialStore: store,
        watchSyncService: watch,
      ),
    );
    await tester.pumpAndSettle();
    expect(watch.syncedSnapshots.last.accounts, isNotEmpty);
    await tester.tap(find.text('Providers'));
    await tester.pumpAndSettle();
    expect(find.text('Connected'), findsOneWidget);
    await tester.tap(find.text('Synthetic label'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();
    expect(
      find.text('Connection removed. Could not finish local cleanup.'),
      findsOneWidget,
    );
    expect(find.text('Connected'), findsNothing);
    expect(
      await store.readSecret(ProviderConnections.anthropicPlatform),
      isNull,
    );
    expect(watch.syncedSnapshots.last.accounts, isEmpty);
    await tester.tap(find.text('Dashboard'));
    await tester.pumpAndSettle();
    expect(find.text('Connect a provider'), findsOneWidget);
    expect(requests, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('open Providers follows automatic and manual reporting results', (
    tester,
  ) async {
    final store = _MemoryCredentialStore();
    await store.writeSecret(
      ProviderConnections.anthropicPlatform,
      'synthetic-key',
    );
    final scheduler = _ManualProviderSyncScheduler();
    addTearDown(scheduler.dispose);
    ProviderReportingFailure? failure;
    var requests = 0;
    final repository = _reportingRepository(store, (_) async {
      requests++;
      if (failure != null) throw ProviderReportingException(failure);
      return DashboardSnapshot.empty().toJsonString();
    });
    await tester.pumpWidget(
      WardPulseApp(
        repository: repository,
        credentialStore: store,
        syncScheduler: scheduler,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Providers'));
    await tester.pumpAndSettle();
    expect(find.text('Connected'), findsOneWidget);
    failure = ProviderReportingFailure.permissionDenied;
    scheduler.tick();
    await tester.pumpAndSettle();
    expect(find.text('Access denied'), findsOneWidget);
    failure = ProviderReportingFailure.unavailable;
    await tester.tap(find.byTooltip('Refresh'));
    await tester.pumpAndSettle();
    expect(find.text('Could not check'), findsOneWidget);
    expect(find.text('Key rejected'), findsNothing);
    expect(requests, 3);
  });

  testWidgets(
    'refresh retires externally removed outcomes and keeps current sibling feedback',
    (tester) async {
      final store = _MemoryCredentialStore();
      const rejected = ProviderConnections.anthropicPlatform;
      const sibling = ProviderConnections.cursorPlatform;
      await store.writeSecret(rejected, 'synthetic-rejected');
      await store.writeSecret(sibling, 'synthetic-sibling');
      final live = _PublicationRepository(
        DashboardSnapshot.fromJsonString(
          File(
            '../../fixtures/snapshots/dashboard_today.json',
          ).readAsStringSync(),
        ),
      );
      final scheduler = _ManualProviderSyncScheduler();
      addTearDown(scheduler.dispose);
      var rejectedRequests = 0;
      var siblingRequests = 0;
      final repository = _reportingRepository(
        store,
        (_) async {
          rejectedRequests++;
          throw const ProviderReportingException(
            ProviderReportingFailure.authentication,
          );
        },
        fallback: _reportingRepository(
          store,
          (_) async {
            siblingRequests++;
            throw const ProviderReportingException(
              ProviderReportingFailure.permissionDenied,
            );
          },
          connection: sibling,
          fallback: live,
        ),
      );
      await tester.pumpWidget(
        WardPulseApp(
          repository: repository,
          credentialStore: store,
          syncScheduler: scheduler,
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Anthropic · Organization reporting: Key rejected'),
        findsOneWidget,
      );
      expect(find.text('Edit key'), findsNWidgets(2));

      // Another lifecycle owner removes the key without the app's callback.
      await store.deleteSecret(rejected);
      scheduler.tick();
      await tester.pumpAndSettle();
      expect(find.textContaining('Key rejected'), findsNothing);
      expect(
        find.textContaining('Cursor · Team Admin API: Access denied'),
        findsOneWidget,
      );
      expect(find.text('Edit key'), findsOneWidget);
      expect(find.text('Connect a provider'), findsNothing);
      expect(rejectedRequests, 1);
      expect(siblingRequests, 2);
      await tester.tap(find.text('Providers'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Organization reporting'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(
        find.descendant(
          of: find.widgetWithText(
            ProviderConnectionRow,
            'Organization reporting',
          ),
          matching: find.text('Not connected'),
        ),
        findsOneWidget,
      );

      await store.deleteSecret(sibling);
      live.snapshot = DashboardSnapshot.empty();
      await tester.tap(find.text('Dashboard'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Refresh'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Key rejected'), findsNothing);
      expect(find.textContaining('Access denied'), findsNothing);
      expect(find.text('Edit key'), findsNothing);
      expect(find.text('Connect a provider'), findsOneWidget);
      expect(rejectedRequests, 1);
      expect(siblingRequests, 2);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('failed key storage never checks or blames the provider', (
    tester,
  ) async {
    final store = _MemoryCredentialStore()..failKeyWrite = true;
    var requests = 0;
    final repository = _reportingRepository(store, (_) async {
      requests++;
      return DashboardSnapshot.empty().toJsonString();
    });
    await tester.pumpWidget(
      WardPulseApp(repository: repository, credentialStore: store),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Providers'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Organization reporting'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).first, 'synthetic-key');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Could not update credential'), findsOneWidget);
    expect(find.text('Key rejected'), findsNothing);
    expect(
      await store.readSecret(ProviderConnections.anthropicPlatform),
      isNull,
    );
    expect(requests, 0);
  });

  testWidgets(
    'initial all-failed feedback repairs the exact row despite labels and ordering',
    (tester) async {
      final store = _MemoryCredentialStore();
      const ids = [
        ProviderConnections.cursorPlatform,
        ProviderConnections.openAiPlatform,
        ProviderConnections.anthropicPlatform,
      ];
      for (final id in ids) {
        await store.writeSecret(id, 'synthetic-key');
        await store.writeLabel(id, 'Shared label');
      }
      final outcomes = [
        for (final id in ids)
          ConnectionReportingOutcome(
            connection: id,
            category: ReportingOutcomeCategory.authenticationRejected,
            source: ReportingOutcomeSource.live,
            credentialVersion: store.version(id),
            freshness: ReportingOutcomeFreshness.current,
          ),
      ];
      await tester.pumpWidget(
        WardPulseApp(
          repository: _OutcomeFailureRepository(outcomes),
          credentialStore: store,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Connect a provider'), findsNothing);
      for (final outcome in outcomes) {
        expect(
          find.textContaining('${outcome.connectionLabel}: Key rejected'),
          findsOneWidget,
        );
      }
      await tester.ensureVisible(find.text('Edit key').at(1));
      await tester.tap(find.text('Edit key').at(1));
      await tester.pumpAndSettle();
      expect(
        find.widgetWithText(AlertDialog, 'Anthropic · Organization reporting'),
        findsOneWidget,
      );
      expect(
        tester
            .widget<TextFormField>(find.byType(TextFormField).first)
            .controller!
            .text,
        isEmpty,
      );
      expect(find.text('Remove'), findsOneWidget);
    },
  );

  testWidgets('stores and masks an OpenAI Admin API key', (tester) async {
    final snapshot = DashboardSnapshot.fromJsonString(
      File('../../fixtures/snapshots/dashboard_today.json').readAsStringSync(),
    );
    final credentialStore = _MemoryCredentialStore();

    await tester.pumpWidget(
      WardPulseApp(
        repository: ValueDashboardRepository(snapshot),
        credentialStore: credentialStore,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Providers'));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('Platform reporting'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('Not connected'), findsWidgets);
    await tester.tap(find.text('Platform reporting'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextFormField).first,
      'secret-admin-key',
    );
    expect(
      tester.widget<TextField>(find.byType(TextField).first).obscureText,
      isTrue,
    );
    await tester.tap(find.byTooltip('Show value'));
    await tester.pump();
    expect(
      tester.widget<TextField>(find.byType(TextField).first).obscureText,
      isFalse,
    );
    expect(find.byTooltip('Hide value'), findsOneWidget);
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(credentialStore.openAiSecret, 'secret-admin-key');
    await tester.scrollUntilVisible(
      find.text('Not verified'),
      -300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Not verified'), findsOneWidget);
    expect(find.text('secret-admin-key'), findsNothing);
  });

  testWidgets('saves an optional OpenAI Platform label', (tester) async {
    final snapshot = DashboardSnapshot.fromJsonString(
      File('../../fixtures/snapshots/dashboard_today.json').readAsStringSync(),
    );
    final credentialStore = _MemoryCredentialStore();

    await tester.pumpWidget(
      WardPulseApp(
        repository: ValueDashboardRepository(snapshot),
        credentialStore: credentialStore,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Providers'));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('OpenAI'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('OpenAI'), findsOneWidget);
    expect(find.text('Codex plan'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('Platform reporting'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Platform reporting'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextFormField).at(0),
      'secret-admin-key',
    );
    await tester.enterText(find.byType(TextFormField).at(1), 'Work org key');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(credentialStore.openAiSecret, 'secret-admin-key');
    expect(credentialStore.openAiLabel, 'Work org key');
    await tester.scrollUntilVisible(
      find.text('Work org key'),
      -300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Work org key'), findsOneWidget);
    expect(find.text('Platform reporting'), findsNothing);

    final providersList = find.descendant(
      of: find.byType(ListView),
      matching: find.byType(Scrollable),
    );
    await tester.scrollUntilVisible(
      find.text('Anthropic'),
      300,
      scrollable: providersList,
    );
    expect(find.text('Anthropic'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('Cursor'),
      300,
      scrollable: providersList,
    );
    expect(find.text('Cursor'), findsOneWidget);
    expect(find.text('Not connected'), findsWidgets);

    await tester.scrollUntilVisible(
      find.text('Work org key'),
      300,
      scrollable: providersList,
    );
    await tester.ensureVisible(
      find.widgetWithText(ProviderConnectionRow, 'Work org key'),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Work org key'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();

    expect(credentialStore.openAiSecret, isNull);
    expect(credentialStore.openAiLabel, isNull);
    await tester.scrollUntilVisible(
      find.text('Platform reporting'),
      300,
      scrollable: providersList,
    );
    await tester.pumpAndSettle();
    expect(find.text('Platform reporting'), findsOneWidget);
  });

  testWidgets('keeps Providers catalog available after a load failure', (
    tester,
  ) async {
    final credentialStore = _MemoryCredentialStore('invalid-admin-key');
    final scheduler = _ManualProviderSyncScheduler();
    addTearDown(scheduler.dispose);

    await tester.pumpWidget(
      WardPulseApp(
        repository: const _FailingDashboardRepository(
          DashboardSyncIssue.authentication,
          'Usage · HTTP 401 · invalid_api_key',
        ),
        credentialStore: credentialStore,
        syncScheduler: scheduler,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Dashboard unavailable'), findsOneWidget);
    expect(scheduler.scheduledInterval, isNotNull);
    expect(
      find.text(DashboardSyncIssue.authentication.message),
      findsOneWidget,
    );
    expect(
      find.byTooltip(DashboardSyncIssue.authentication.message),
      findsOneWidget,
    );
    expect(find.text('Details'), findsOneWidget);
    await tester.tap(find.text('Details'));
    await tester.pumpAndSettle();
    expect(find.text('Error details'), findsOneWidget);
    expect(find.text('Usage · HTTP 401 · invalid_api_key'), findsOneWidget);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Providers'));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('Platform reporting'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('Platform reporting'), findsOneWidget);
    expect(find.text('Not verified'), findsOneWidget);
    await tester.tap(find.text('Platform reporting'));
    await tester.pumpAndSettle();
    expect(find.text('Remove'), findsOneWidget);
  });

  testWidgets(
    'shows plan and purchased surfaces without Settings display toggles',
    (tester) async {
      final json =
          jsonDecode(
                File(
                  '../../fixtures/snapshots/dashboard_today.json',
                ).readAsStringSync(),
              )
              as Map<String, dynamic>;
      final account = (json['accounts'] as List).first as Map<String, dynamic>;
      account['provider'] = 'codex';
      account['allowances'] = [
        {
          'id': 'plan',
          'source': 'plan',
          'label': 'Weekly plan',
          'usedPercent': 84.0,
          'used': null,
          'limit': null,
          'remaining': null,
          'windowMinutes': 10080,
          'resetsAt': '2026-07-26T09:55:37Z',
          'status': 'warning',
        },
        {
          'id': 'purchased',
          'source': 'purchased',
          'label': 'Purchased credits',
          'usedPercent': null,
          'used': null,
          'limit': null,
          'remaining': {'value': '12.5', 'unit': 'credits'},
          'windowMinutes': null,
          'resetsAt': null,
          'status': 'ok',
        },
      ];

      await tester.pumpWidget(
        WardPulseApp(
          repository: ValueDashboardRepository(
            DashboardSnapshot.fromJson(json),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Weekly plan'), findsOneWidget);
      expect(find.text('Purchased credits'), findsOneWidget);

      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();
      expect(find.text('Display'), findsNothing);
      expect(find.text('Platform spend'), findsNothing);
      expect(find.text('Purchased usage'), findsNothing);
    },
  );

  testWidgets('persists the global refresh interval slider', (tester) async {
    final snapshot = DashboardSnapshot.fromJsonString(
      File('../../fixtures/snapshots/dashboard_today.json').readAsStringSync(),
    );
    final preferences = _MemoryRefreshIntervalPreferenceStore();

    await tester.pumpWidget(
      WardPulseApp(
        repository: ValueDashboardRepository(snapshot),
        refreshIntervalStore: preferences,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining(
        'Every ${PollCadence.defaultRefreshMinutes} minutes while WardPulse is open',
      ),
      findsOneWidget,
    );
    expect(
      find.textContaining(
        'about every 15 minutes in the background (Android may delay updates)',
      ),
      findsOneWidget,
    );

    final slider = find.byType(Slider);
    await tester.ensureVisible(slider);
    await tester.pumpAndSettle();
    // Advance one segmented stop past the default (15 → 20).
    final sliderWidget = tester.widget<Slider>(slider);
    final nextIndex = (sliderWidget.value + 1).clamp(
      sliderWidget.min,
      sliderWidget.max,
    );
    sliderWidget.onChanged!(nextIndex);
    await tester.pump();
    sliderWidget.onChangeEnd!(nextIndex);
    await tester.pumpAndSettle();

    expect(preferences.value.minutes, 20);
    expect(
      PollCadence.refreshIntervalStops,
      contains(preferences.value.minutes),
    );
    expect(
      find.textContaining('about every 20 minutes in the background'),
      findsOneWidget,
    );

    final sixtyIndex = PollCadence.refreshIntervalStopIndex(60).toDouble();
    tester.widget<Slider>(slider).onChanged!(sixtyIndex);
    await tester.pump();
    expect(preferences.value.minutes, 20);
    expect(
      find.textContaining('Every 60 minutes while WardPulse is open'),
      findsOneWidget,
    );
    expect(
      find.textContaining('about every 60 minutes in the background'),
      findsOneWidget,
    );
    tester.widget<Slider>(slider).onChangeEnd!(sixtyIndex);
    await tester.pumpAndSettle();
    expect(preferences.value.minutes, 60);
    expect(
      find.textContaining('about every 60 minutes in the background'),
      findsOneWidget,
    );

    final fiveIndex = PollCadence.refreshIntervalStopIndex(5).toDouble();
    tester.widget<Slider>(slider).onChanged!(fiveIndex);
    await tester.pump();
    expect(preferences.value.minutes, 60);
    expect(
      find.textContaining('Every 5 minutes while WardPulse is open'),
      findsOneWidget,
    );
    expect(
      find.textContaining('about every 15 minutes in the background'),
      findsOneWidget,
    );
    tester.widget<Slider>(slider).onChangeEnd!(fiveIndex);
    await tester.pumpAndSettle();
    expect(preferences.value.minutes, 5);
    expect(
      find.textContaining('about every 15 minutes in the background'),
      findsOneWidget,
    );
  });

  testWidgets('resyncs providers and the watch on a scheduled tick', (
    tester,
  ) async {
    final snapshot = DashboardSnapshot.fromJsonString(
      File('../../fixtures/snapshots/dashboard_today.json').readAsStringSync(),
    );
    final watchSyncService = _FakeWatchSyncService();
    final scheduler = _ManualProviderSyncScheduler();
    addTearDown(scheduler.dispose);

    await tester.pumpWidget(
      WardPulseApp(
        repository: ValueDashboardRepository(snapshot),
        watchSyncService: watchSyncService,
        syncScheduler: scheduler,
      ),
    );
    await tester.pumpAndSettle();

    expect(
      scheduler.scheduledInterval,
      const Duration(minutes: PollCadence.defaultRefreshMinutes),
    );
    expect(watchSyncService.syncedSnapshots, hasLength(1));

    scheduler.tick();
    await tester.pumpAndSettle();

    expect(watchSyncService.syncedSnapshots, hasLength(2));
  });

  testWidgets('shows Cursor freshness guidance on connection rows', (
    tester,
  ) async {
    final snapshot = DashboardSnapshot.fromJsonString(
      File('../../fixtures/snapshots/dashboard_today.json').readAsStringSync(),
    );

    await tester.pumpWidget(
      WardPulseApp(repository: ValueDashboardRepository(snapshot)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Providers'));
    await tester.pumpAndSettle();

    final settingsScrollable = find.descendant(
      of: find.byType(ListView),
      matching: find.byType(Scrollable),
    );
    await tester.scrollUntilVisible(
      find.text('Team Admin API'),
      300,
      scrollable: settingsScrollable,
    );

    final planTile = find.ancestor(
      of: find.text('Cursor plan'),
      matching: find.byType(ProviderConnectionRow),
    );
    final adminTile = find.ancestor(
      of: find.text('Team Admin API'),
      matching: find.byType(ProviderConnectionRow),
    );
    expect(
      find.descendant(
        of: planTile,
        matching: find.textContaining(PollCadence.cursorFreshnessNote),
      ),
      findsNothing,
    );
    expect(
      find.descendant(
        of: adminTile,
        matching: find.textContaining(PollCadence.cursorFreshnessNote),
      ),
      findsOneWidget,
    );
  });

  testWidgets('enables mock data only from the debug setting', (tester) async {
    final liveFixture = DashboardSnapshot.fromJsonString(
      File('../../fixtures/snapshots/dashboard_today.json').readAsStringSync(),
    );
    final liveJson = liveFixture.toJson();
    (liveJson['accounts'] as List).first['provider'] = 'openai';
    final live = DashboardSnapshot.fromJson(liveJson);
    final mockJson = liveFixture.toJson();
    final accounts = mockJson['accounts'] as List<dynamic>;
    accounts.first
      ..['provider'] = 'codex'
      ..['accountId'] = 'codex-demo';
    accounts.add({
      ...Map<String, dynamic>.from(accounts.first as Map),
      'provider': 'cursor',
      'accountId': 'cursor-demo',
    });
    final mock = DashboardSnapshot.fromJson(mockJson);
    final preferences = _MemoryDebugDataPreferenceStore();

    await tester.pumpWidget(
      WardPulseApp(
        repository: DebugDashboardRepository(
          live: ValueDashboardRepository(live),
          mock: ValueDashboardRepository(mock),
          preferences: preferences,
        ),
        debugDataAvailable: true,
        debugDataPreferenceStore: preferences,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();

    final toggle = find.widgetWithText(SwitchListTile, 'Mock data');
    await tester.scrollUntilVisible(
      toggle,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(tester.widget<SwitchListTile>(toggle).value, isFalse);

    await tester.tap(toggle);
    await tester.pumpAndSettle();

    expect(preferences.value, isTrue);
    await tester.tap(find.text('Providers'));
    await tester.pumpAndSettle();
    // Which family sits where is the tab's own business
    // (providers_screen_test.dart); this test only asks that the catalog
    // opened, so it scrolls to the row instead of assuming a position.
    await tester.scrollUntilVisible(
      find.text('Codex plan'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Codex plan'), findsOneWidget);
  });

  testWidgets(
    'demo data leaves nothing for a recovery to be measured against',
    (tester) async {
      final source = DashboardSnapshot.fromJsonString(
        File(
          '../../fixtures/snapshots/dashboard_today.json',
        ).readAsStringSync(),
      );
      final preferences = _MemoryDebugDataPreferenceStore();
      await preferences.writeMockDataEnabled(true);
      final watchlist =
          _MemoryRecoveryWatchlistStore()
            ..keys = const [(accountId: 'codex-demo', allowanceId: 'weekly')];

      await tester.pumpWidget(
        WardPulseApp(
          repository: DebugDashboardRepository(
            live: ValueDashboardRepository(source),
            mock: ValueDashboardRepository(source),
            preferences: preferences,
          ),
          debugDataAvailable: true,
          debugDataPreferenceStore: preferences,
          recoveryWatchlistStore: watchlist,
        ),
      );
      await tester.pumpAndSettle();

      // Invented windows must not survive the demo: kept, they would make the
      // first live poll afterwards look like a recovery.
      expect(watchlist.keys, isEmpty);
    },
  );

  testWidgets('the recovery switch is on, and says when Android blocks it', (
    tester,
  ) async {
    final store = _MemoryRecoveryNotificationStore();
    final notifier = _BlockedRecoveryNotifier();

    await tester.pumpWidget(
      WardPulseApp(
        repository: ValueDashboardRepository(
          DashboardSnapshot.empty(generatedAt: DateTime.utc(2026, 8, 17)),
        ),
        recoveryNotificationStore: store,
        recoveryNotifier: notifier,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();

    final toggle = find.widgetWithText(SwitchListTile, 'Plan recovery');
    await tester.scrollUntilVisible(
      toggle,
      300,
      scrollable: find.byType(Scrollable).first,
    );

    // On without being asked: interrupting is the point of the feature.
    expect(tester.widget<SwitchListTile>(toggle).value, isTrue);

    // Off and on again, so the ask runs with Android refusing it.
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(store.enabled, isFalse);
    await tester.tap(toggle);
    await tester.pumpAndSettle();

    expect(store.enabled, isTrue);
    expect(notifier.asked, 1);
    // The reader said yes and Android said no; leaving the switch on without a
    // word would promise an interruption that cannot arrive.
    expect(
      find.text('Android is blocking WardPulse notifications'),
      findsOneWidget,
    );
  });

  testWidgets('hides mock data outside debug builds', (tester) async {
    await tester.pumpWidget(
      WardPulseApp(
        repository: ValueDashboardRepository(
          DashboardSnapshot.fromJsonString(
            File(
              '../../fixtures/snapshots/dashboard_today.json',
            ).readAsStringSync(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();

    expect(find.text('Mock data'), findsNothing);
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

class _MemoryRecoveryNotificationStore
    implements RecoveryNotificationPreferenceStore {
  bool enabled = true;

  @override
  Future<bool> read() async => enabled;

  @override
  Future<void> write(bool value) async => enabled = value;
}

/// Android refusing the permission, which the switch alone cannot detect.
class _BlockedRecoveryNotifier implements RecoveryNotifier {
  var asked = 0;

  @override
  Future<void> notify(PlanRecovery recovery) async {}

  @override
  Future<bool> requestPermission() async {
    asked++;
    return false;
  }
}

class _MemoryRecoveryWatchlistStore implements RecoveryWatchlistStore {
  List<WindowKey> keys = const [];

  @override
  Future<List<WindowKey>> read() async => keys;

  @override
  Future<void> write(List<WindowKey> value) async => keys = value;
}

class _FakeWatchSyncService implements WatchSyncService {
  final syncedSnapshots = <DashboardSnapshot>[];
  void Function()? refreshHandler;

  @override
  Future<void> sync(
    DashboardSnapshot snapshot,
    WatchRingPreferences ringPreferences, {
    DateTime? manualRefreshAnchorAt,
    bool mockDataMode = false,
  }) async {
    syncedSnapshots.add(snapshot);
  }

  @override
  void bindWatchRefreshListener(void Function() onRefresh) {
    refreshHandler = onRefresh;
  }

  @override
  void unbindWatchRefreshListener() {
    refreshHandler = null;
  }
}

class _FailingWatchSyncService implements WatchSyncService {
  const _FailingWatchSyncService();

  @override
  Future<void> sync(
    DashboardSnapshot snapshot,
    WatchRingPreferences ringPreferences, {
    DateTime? manualRefreshAnchorAt,
    bool mockDataMode = false,
  }) {
    return Future.error(StateError('Watch unavailable'));
  }

  @override
  void bindWatchRefreshListener(void Function() onRefresh) {}

  @override
  void unbindWatchRefreshListener() {}
}

final class _FailingDashboardRepository extends DashboardRepository {
  const _FailingDashboardRepository(this.issue, [this.details]);

  final DashboardSyncIssue issue;
  final String? details;

  @override
  Future<DashboardSnapshot> load() {
    return Future.error(DashboardLoadException(issue: issue, details: details));
  }
}

final class _CountingDashboardRepository extends DashboardRepository {
  _CountingDashboardRepository(this._load);

  final DashboardSnapshot Function() _load;

  @override
  Future<DashboardSnapshot> load() async => _load();
}

class _MemoryPhoneWidgetStore implements PhoneWidgetPreferenceStore {
  PhoneWidgetPreferences value = const PhoneWidgetPreferences();

  @override
  Future<PhoneWidgetPreferences> read() async => value;

  @override
  Future<void> write(PhoneWidgetPreferences next) async {
    value = next;
  }
}

class _MemoryWatchRingStore implements WatchRingPreferenceStore {
  WatchRingPreferences value = const WatchRingPreferences();

  @override
  Future<WatchRingPreferences> read() async => value;

  @override
  Future<void> write(WatchRingPreferences next) async {
    value = next;
  }
}

class _MemoryAlertThresholdStore implements AlertThresholdPreferenceStore {
  AlertThresholdPreferences value = const AlertThresholdPreferences();

  @override
  Future<AlertThresholdPreferences> read() async => value;

  @override
  Future<void> write(AlertThresholdPreferences next) async {
    value = next;
  }
}

class _MemoryCredentialStore
    implements ProviderCredentialStore, VersionedProviderCredentialStore {
  final _generations = <ProviderConnectionId, int>{};
  Future<void>? pendingWrite;
  bool failLabelWrite = false;
  bool failKeyWrite = false;
  bool failDeleteAfterRetirement = false;
  CredentialVersion version(ProviderConnectionId id) => CredentialVersion({
    'generation': '${_generations[id] ?? 0}',
    'revision': 'revision',
    'epoch': 'epoch',
    'identity': id.storageKey,
  });
  @override
  ConnectionCredentialAccess credentialAccess(ProviderConnectionId id) =>
      _MemoryCredentialAccess(this, id);
  _MemoryCredentialStore([String? openAiAdminKey]) {
    if (openAiAdminKey != null) {
      _secrets[ProviderConnections.openAiPlatform] = openAiAdminKey;
    }
  }

  final _secrets = <ProviderConnectionId, String>{};
  final _labels = <ProviderConnectionId, String>{};

  String? get openAiSecret => _secrets[ProviderConnections.openAiPlatform];

  String? get openAiLabel => _labels[ProviderConnections.openAiPlatform];

  @override
  Future<String?> readSecret(ProviderConnectionId id) async => _secrets[id];

  @override
  Future<void> writeSecret(ProviderConnectionId id, String value) async {
    await pendingWrite;
    if (failKeyWrite) throw StateError('Synthetic write failure');
    _generations[id] = (_generations[id] ?? 0) + 1;
    _secrets[id] = value;
  }

  @override
  Future<void> deleteSecret(ProviderConnectionId id) async {
    _generations[id] = (_generations[id] ?? 0) + 1;
    _secrets.remove(id);
    if (failDeleteAfterRetirement)
      throw StateError('Synthetic cleanup failure');
    _labels.remove(id);
  }

  @override
  Future<String?> readLabel(ProviderConnectionId id) async => _labels[id];

  @override
  Future<void> writeLabel(ProviderConnectionId id, String? value) async {
    if (failLabelWrite) throw StateError('Synthetic label failure');
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      _labels.remove(id);
      return;
    }
    _labels[id] = trimmed;
  }
}

class _MemoryDebugDataPreferenceStore implements DebugDataPreferenceStore {
  bool value = false;

  @override
  Future<bool> readMockDataEnabled() async => value;

  @override
  Future<void> writeMockDataEnabled(bool value) async {
    this.value = value;
  }
}

class _MemoryRefreshIntervalPreferenceStore
    implements RefreshIntervalPreferenceStore {
  RefreshIntervalPreference value = const RefreshIntervalPreference();

  @override
  Future<RefreshIntervalPreference> read() async => value;

  @override
  Future<void> write(RefreshIntervalPreference value) async {
    this.value = value;
  }
}

class _ManualProviderSyncScheduler implements ProviderSyncScheduler {
  final _ticks = StreamController<void>.broadcast();

  Duration? scheduledInterval;

  @override
  Stream<void> get ticks => _ticks.stream;

  @override
  Future<void> schedule(Duration interval) async {
    scheduledInterval = interval;
  }

  @override
  Future<void> cancel() async {}

  void tick() => _ticks.add(null);

  Future<void> dispose() => _ticks.close();
}

class _PublicationRepository extends DashboardRepository {
  _PublicationRepository(this.snapshot);
  DashboardSnapshot snapshot;
  bool delayNextValidation = false;
  bool validationStarted = false;
  final validation = Completer<bool>();
  @override
  Future<DashboardSnapshot> load() async => snapshot;
  @override
  Future<bool> isSnapshotCurrent(DashboardSnapshot snapshot) async {
    if (delayNextValidation) {
      delayNextValidation = false;
      validationStarted = true;
      return validation.future;
    }
    return true;
  }
}

class _DelayedAlertThresholdStore implements AlertThresholdPreferenceStore {
  final release = Completer<void>();
  bool started = false;
  AlertThresholdPreferences value = const AlertThresholdPreferences();
  @override
  Future<AlertThresholdPreferences> read() async => value;
  @override
  Future<void> write(AlertThresholdPreferences next) async {
    started = true;
    await release.future;
    value = next;
  }
}

MergingConnectionRepository _reportingRepository(
  _MemoryCredentialStore store,
  Future<String> Function(String) fetch, {
  ProviderConnectionId connection = ProviderConnections.anthropicPlatform,
  DashboardRepository fallback = const NoProvidersDashboardRepository(),
}) => MergingConnectionRepository(
  connection: connection,
  credentialStore: store,
  loadCredentialReport: fetch,
  normalizeReport: (value) => value,
  fallback: fallback,
  logger: const NullProviderSyncLogger(),
  mapError: (error) => mapReportingError(error, const NullProviderSyncLogger()),
);

final class _MemoryCredentialAccess implements ConnectionCredentialAccess {
  const _MemoryCredentialAccess(this.store, this.id);
  final _MemoryCredentialStore store;
  final ProviderConnectionId id;
  @override
  Future<VersionedCredential<String>?> read() async {
    final value = await store.readSecret(id);
    return value == null ? null : VersionedCredential(value, store.version(id));
  }

  @override
  Future<bool> isCurrent(CredentialVersion expected) async =>
      await store.readSecret(id) != null &&
      expected.sameCache(store.version(id));
  @override
  Future<R> serializeFetch<R>(Future<R> Function() operation) => operation();
}

final class _OutcomeFailureRepository extends DashboardRepository {
  const _OutcomeFailureRepository(this.outcomes);
  final List<ConnectionReportingOutcome> outcomes;
  @override
  Future<DashboardSnapshot> load() async =>
      throw DashboardLoadException.withOutcomes(
        issue: DashboardSyncIssue.authentication,
        reportingOutcomes: outcomes,
      );
}
