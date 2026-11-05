import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ward_pulse_phone/app/ward_pulse_theme.dart';
import 'package:ward_pulse_phone/dashboard/dashboard_models.dart';
import 'package:ward_pulse_phone/providers/claude_account_service.dart';
import 'package:ward_pulse_phone/providers/alert_threshold_dialogs.dart';
import 'package:ward_pulse_phone/providers/codex_account_service.dart';
import 'package:ward_pulse_phone/providers/credential_dialog.dart';
import 'package:ward_pulse_phone/providers/provider_connection.dart';
import 'package:ward_pulse_phone/providers/connection_lifecycle.dart';
import 'package:ward_pulse_phone/providers/provider_connection_row.dart';
import 'package:ward_pulse_phone/providers/providers_screen.dart';
import 'package:ward_pulse_phone/providers/provider_credential_store.dart';
import 'package:ward_pulse_phone/settings/alert_percent_threshold_editor.dart';
import 'package:ward_pulse_phone/settings/alert_threshold_preferences.dart';

void main() {
  group('owned connection reveal', () {
    const id = ProviderConnections.openAiPlatform;
    const request = (connection: id, token: 1);
    const statuses = {
      ProviderFamily.openai: ProviderStatus.ok,
      ProviderFamily.anthropic: ProviderStatus.ok,
      ProviderFamily.cursor: ProviderStatus.ok,
    };

    Widget screen({
      required _MemoryCredentialStore store,
      required void Function(int) revealed,
      ({ProviderConnectionId connection, int token})? reveal = request,
      Map<ProviderConnectionId, ConnectionReportingUpdate> updates = const {},
      Map<ProviderFamily, ProviderStatus> order = statuses,
      CodexAccountService codex = const EmptyCodexAccountService(),
      Key? key,
    }) => MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('Providers')),
        bottomNavigationBar: NavigationBar(
          destinations: const [
            NavigationDestination(icon: Icon(Icons.home), label: 'Dashboard'),
            NavigationDestination(icon: Icon(Icons.hub), label: 'Providers'),
          ],
        ),
        body: ProvidersScreen(
          key: key,
          credentialStore: store,
          codexAccountService: codex,
          claudeAccountService: const EmptyClaudeAccountService(),
          onCredentialsChanged: () => fail('Unexpected credential change'),
          alertThresholds: const AlertThresholdPreferences(),
          onAlertThresholdsChanged: (_) async => fail('Unexpected save'),
          onRefresh: _noRefresh,
          statuses: order,
          reportingUpdates: updates,
          isSnapshotCurrent:
              (snapshot) async => snapshot.connectionVersions.entries.every(
                (entry) => CredentialVersion(entry.value).sameCache(
                  store.version(
                    ProviderConnectionId.fromStorageKey(entry.key)!,
                  ),
                ),
              ),
          revealConnection: reveal,
          onConnectionRevealed: revealed,
        ),
      ),
    );

    ConnectionReportingUpdate failure(_MemoryCredentialStore store) =>
        ConnectionReportingUpdate(
          connection: id,
          credentialVersion: store.version(id),
          outcome: ConnectionReportingOutcome(
            connection: id,
            credentialVersion: store.version(id),
            category: ReportingOutcomeCategory.transientFailure,
            source: ReportingOutcomeSource.live,
            freshness: ReportingOutcomeFreshness.current,
          ),
        );

    for (final scale in [1.0, 1.6]) {
      testWidgets('late reporting layout settles the complete row at $scale', (
        tester,
      ) async {
        _setTestSurface(tester, const Size(390, 844));
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        final store = _MemoryCredentialStore();
        await store.writeSecret(id, 'synthetic-key');
        final release = Completer<void>();
        addTearDown(() {
          if (!release.isCompleted) release.complete();
        });
        store.beforeReadLabel = (connection) async {
          if (connection == id) await release.future;
        };
        final acknowledgements = <int>[];
        final update = failure(store);
        await tester.pumpWidget(
          screen(
            store: store,
            revealed: acknowledgements.add,
            updates: {id: update},
          ),
        );
        await _pumpPendingReveal(tester);
        expect(acknowledgements, isEmpty);
        release.complete();
        await tester.pumpAndSettle();
        expect(acknowledgements, [1]);
        _expectCompleteReveal(tester, 'Platform reporting', update.outcome!);

        // A finished token must not turn an ordinary later publication into
        // another navigation request after the reader scrolls elsewhere.
        final list = find.descendant(
          of: find.byType(ProvidersScreen),
          matching: find.byType(Scrollable),
        );
        final position = tester.state<ScrollableState>(list).position;
        final startingPixels = position.pixels;
        final minScrollExtent = position.minScrollExtent;
        final viewportDimension = position.viewportDimension;
        expect(startingPixels.isFinite, isTrue);
        expect(minScrollExtent.isFinite, isTrue);
        expect(viewportDimension.isFinite, isTrue);
        expect(startingPixels, greaterThan(minScrollExtent));
        expect(viewportDimension, greaterThan(kDragSlopDefault));
        await tester.drag(
          list,
          Offset(0, startingPixels - minScrollExtent + viewportDimension),
        );
        await tester.pumpAndSettle();
        expect(position.pixels, lessThan(startingPixels));
        expect(position.pixels, position.minScrollExtent);
        await tester.pumpWidget(
          screen(
            store: store,
            revealed: acknowledgements.add,
            updates: {
              id: ConnectionReportingUpdate(
                connection: id,
                credentialVersion: store.version(id),
                outcome: ConnectionReportingOutcome(
                  connection: id,
                  credentialVersion: store.version(id),
                  category: ReportingOutcomeCategory.success,
                  source: ReportingOutcomeSource.live,
                  freshness: ReportingOutcomeFreshness.current,
                ),
              ),
            },
          ),
        );
        await tester.pumpAndSettle();
        expect(position.pixels, position.minScrollExtent);
        expect(acknowledgements, [1]);
      });
    }

    testWidgets('only the latest request owns delayed publication', (
      tester,
    ) async {
      _setTestSurface(tester, const Size(390, 844));
      final store = _MemoryCredentialStore();
      final release = Completer<void>();
      addTearDown(() {
        if (!release.isCompleted) release.complete();
      });
      store.beforeReadLabel = (connection) async {
        if (connection == id) await release.future;
      };
      final acknowledgements = <int>[];
      await tester.pumpWidget(
        screen(store: store, revealed: acknowledgements.add),
      );
      await _pumpPendingReveal(tester);
      await tester.pumpWidget(
        screen(
          store: store,
          revealed: acknowledgements.add,
          reveal: (connection: ProviderConnections.anthropicPlatform, token: 2),
        ),
      );
      await _pumpPendingReveal(tester);
      expect(acknowledgements, isEmpty);
      release.complete();
      await tester.pumpAndSettle();
      expect(acknowledgements, [2]);
      _expectCompleteReveal(tester, 'Organization reporting');
    });

    for (final dispose in [false, true]) {
      testWidgets(
        'delayed publication cannot complete ${dispose ? 'disposed' : 'canceled'} reveal',
        (tester) async {
          _setTestSurface(tester, const Size(390, 844));
          final store = _MemoryCredentialStore();
          final release = Completer<void>();
          addTearDown(() {
            if (!release.isCompleted) release.complete();
          });
          store.beforeReadLabel = (connection) async {
            if (connection == id) await release.future;
          };
          final acknowledgements = <int>[];
          await tester.pumpWidget(
            screen(store: store, revealed: acknowledgements.add),
          );
          await _pumpPendingReveal(tester);
          await tester.pumpWidget(
            dispose
                ? const SizedBox()
                : screen(
                  store: store,
                  revealed: acknowledgements.add,
                  reveal: null,
                ),
          );
          release.complete();
          await tester.pumpAndSettle();
          expect(acknowledgements, isEmpty);
          final focused = FocusManager.instance.primaryFocus?.context;
          if (focused != null) {
            expect(
              find.descendant(
                of: find.byElementPredicate(
                  (element) => identical(element, focused),
                ),
                matching: find.widgetWithText(
                  ProviderConnectionRow,
                  'Platform reporting',
                ),
              ),
              findsNothing,
            );
          }
          expect(tester.takeException(), isNull);
        },
      );
    }

    testWidgets('superseding an unfinished animation retires its completion', (
      tester,
    ) async {
      _setTestSurface(tester, const Size(390, 844));
      final store = _MemoryCredentialStore();
      final acknowledgements = <int>[];
      await tester.pumpWidget(
        screen(store: store, revealed: acknowledgements.add, reveal: null),
      );
      await tester.pumpAndSettle();
      await tester.pumpWidget(
        screen(
          store: store,
          revealed: acknowledgements.add,
          reveal: (connection: ProviderConnections.anthropicPlatform, token: 1),
        ),
      );
      final list = find.descendant(
        of: find.byType(ProvidersScreen),
        matching: find.byType(Scrollable),
      );
      expect(
        tester.state<ScrollableState>(list).position.isScrollingNotifier.value,
        isTrue,
      );
      expect(acknowledgements, isEmpty);
      await tester.pumpWidget(
        screen(
          store: store,
          revealed: acknowledgements.add,
          reveal: (connection: ProviderConnections.codexPlan, token: 2),
        ),
      );
      await tester.pumpAndSettle();
      expect(acknowledgements, [2]);
      _expectCompleteReveal(tester, 'Codex plan');
    });

    testWidgets(
      'an older credential read cannot resume the completed revision',
      (tester) async {
        _setTestSurface(tester, const Size(390, 844));
        final oldStore = _MemoryCredentialStore();
        final release = Completer<void>();
        addTearDown(() {
          if (!release.isCompleted) release.complete();
        });
        oldStore.beforeReadLabel = (connection) async {
          if (connection == id) await release.future;
        };
        final acknowledgements = <int>[];
        await tester.pumpWidget(
          screen(store: oldStore, revealed: acknowledgements.add),
        );
        await _pumpPendingReveal(tester);
        expect(acknowledgements, isEmpty);
        await tester.pumpWidget(
          screen(
            store: _MemoryCredentialStore(),
            revealed: acknowledgements.add,
          ),
        );
        await tester.pumpAndSettle();
        expect(acknowledgements, [1]);
        _expectCompleteReveal(tester, 'Platform reporting');
        final list = find.descendant(
          of: find.byType(ProvidersScreen),
          matching: find.byType(Scrollable),
        );
        final position = tester.state<ScrollableState>(list).position;
        final startingPixels = position.pixels;
        final minScrollExtent = position.minScrollExtent;
        final viewportDimension = position.viewportDimension;
        expect(startingPixels.isFinite, isTrue);
        expect(minScrollExtent.isFinite, isTrue);
        expect(viewportDimension.isFinite, isTrue);
        expect(startingPixels, greaterThan(minScrollExtent));
        expect(viewportDimension, greaterThan(kDragSlopDefault));
        await tester.drag(
          list,
          Offset(0, startingPixels - minScrollExtent + viewportDimension),
        );
        await tester.pumpAndSettle();
        expect(position.pixels, lessThan(startingPixels));
        expect(position.pixels, position.minScrollExtent);
        release.complete();
        await tester.pumpAndSettle();
        expect(acknowledgements, [1]);
        expect(position.pixels, position.minScrollExtent);
      },
    );

    testWidgets('new credential publication retires the old family traversal', (
      tester,
    ) async {
      _setTestSurface(tester, const Size(390, 844));
      final store = _MemoryCredentialStore();
      final local = _DelayedCodexAccountService();
      addTearDown(() {
        if (!local.read.isCompleted) local.read.complete(false);
      });
      final acknowledgements = <int>[];
      await tester.pumpWidget(
        screen(
          store: store,
          revealed: acknowledgements.add,
          order: const {},
          codex: local,
        ),
      );
      await _pumpPendingReveal(tester);
      expect(local.reads, greaterThan(0));
      expect(
        find.widgetWithText(ProviderConnectionRow, 'Platform reporting'),
        findsOneWidget,
      );
      expect(acknowledgements, isEmpty);
      // The target was discovered near the end while its sibling initial read
      // remained pending. This publication moves OpenAI ahead of that offset.
      await store.writeSecret(id, 'synthetic-key');
      await tester.pumpWidget(
        screen(
          store: store,
          revealed: acknowledgements.add,
          order: const {},
          codex: local,
          updates: {id: failure(store)},
        ),
      );
      await _pumpPendingReveal(tester);
      local.read.complete(false);
      await tester.pumpAndSettle();
      expect(acknowledgements, [1]);
      _expectCompleteReveal(tester, 'Platform reporting');
      expect(
        tester.getTopLeft(find.text('OpenAI')).dy,
        lessThan(tester.getTopLeft(find.text('Anthropic')).dy),
      );
    });

    testWidgets('lazy target waits for its row-local failure publication', (
      tester,
    ) async {
      _setTestSurface(tester, const Size(390, 844));
      final local = _DelayedCodexAccountService();
      addTearDown(() {
        if (!local.read.isCompleted) local.read.complete(false);
      });
      final acknowledgements = <int>[];
      await tester.pumpWidget(
        screen(
          store: _MemoryCredentialStore(),
          revealed: acknowledgements.add,
          codex: local,
          reveal: (connection: ProviderConnections.codexPlan, token: 1),
        ),
      );
      await _pumpPendingReveal(tester);
      expect(local.reads, 1);
      expect(acknowledgements, isEmpty);
      local.read.completeError(StateError('Synthetic local read failure'));
      await tester.pumpAndSettle();
      expect(acknowledgements, [1]);
      _expectCompleteReveal(tester, 'Codex plan');
      expect(local.reads, 1);
    });

    testWidgets('retired row read cannot block or focus a replacement', (
      tester,
    ) async {
      _setTestSurface(tester, const Size(390, 844));
      final store = _MemoryCredentialStore();
      final local = _DelayedCodexAccountService();
      addTearDown(() {
        if (!local.read.isCompleted) local.read.complete(false);
      });
      final acknowledgements = <int>[];
      await tester.pumpWidget(
        screen(
          key: const ValueKey('old'),
          store: store,
          revealed: acknowledgements.add,
          codex: local,
          reveal: (connection: ProviderConnections.codexPlan, token: 1),
        ),
      );
      await _pumpPendingReveal(tester);
      expect(local.reads, 1);
      expect(acknowledgements, isEmpty);
      await tester.pumpWidget(
        screen(
          key: const ValueKey('replacement'),
          store: store,
          revealed: acknowledgements.add,
          reveal: (connection: ProviderConnections.anthropicPlatform, token: 2),
        ),
      );
      await tester.pumpAndSettle();
      expect(acknowledgements, [2]);
      local.read.complete(true);
      await tester.pumpAndSettle();
      expect(acknowledgements, [2]);
      _expectCompleteReveal(tester, 'Organization reporting');
    });

    testWidgets(
      'oversized row completes and its remaining recovery copy scrolls normally',
      (tester) async {
        _setTestSurface(tester, const Size(390, 844));
        tester.platformDispatcher.textScaleFactorTestValue = 3;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        final store = _MemoryCredentialStore();
        await store.writeSecret(id, 'synthetic-key');
        final update = failure(store);
        final acknowledgements = <int>[];
        await tester.pumpWidget(
          screen(
            store: store,
            revealed: acknowledgements.add,
            updates: {id: update},
          ),
        );
        await tester.pumpAndSettle();
        expect(acknowledgements, [1]);
        final row = find.widgetWithText(
          ProviderConnectionRow,
          'Platform reporting',
        );
        final viewport = tester.getRect(
          find.descendant(
            of: find.byType(ProvidersScreen),
            matching: find.byType(Viewport),
          ),
        );
        expect(tester.getSize(row).height, greaterThan(viewport.height));
        expect(tester.getTopLeft(row).dy, closeTo(viewport.top, 0.5));
        _expectRevealFocus(row);
        await tester.drag(
          find.descendant(
            of: find.byType(ProvidersScreen),
            matching: find.byType(Scrollable),
          ),
          const Offset(0, -1400),
        );
        await tester.pumpAndSettle();
        final copy = find.text(
          '${update.outcome!.connectionLabel}\n${update.outcome!.supportingCopy}',
        );
        final remaining = tester.getRect(copy);
        expect(remaining.bottom, lessThanOrEqualTo(viewport.bottom + 0.5));
        expect(remaining.overlaps(viewport), isTrue);
        expect(tester.getTopLeft(row).dy, lessThan(viewport.top));
        expect(acknowledgements, [1]);
      },
    );
  });

  testWidgets(
    'Plan catalogue uses owning connection and only absent-ID fallback',
    (tester) async {
      final snapshot = _windowSnapshot([
        _windowAccount('cursor', 'cursor.plan', ['Models', 'Other Models']),
        _windowAccount('cursor', 'cursor.platform', ['Sibling only']),
        _windowAccount('cursor', 'unrecognized', ['Unknown owner']),
        _windowAccount('codex', null, ['Legacy dynamic']),
        _windowAccount('claude', null, ['Legacy weekly']),
        _windowAccount('openai', null, ['Legacy reporting']),
      ]);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ProvidersScreen(
              onRefresh: _noRefresh,
              credentialStore: const EmptyProviderCredentialStore(),
              codexAccountService: const EmptyCodexAccountService(),
              claudeAccountService: const EmptyClaudeAccountService(),
              onCredentialsChanged: () {},
              alertThresholds: const AlertThresholdPreferences(),
              onAlertThresholdsChanged: (_) async => fail('Unexpected save'),
              snapshot: snapshot,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      for (final (row, labels) in [
        ('Claude plan', ['Legacy weekly']),
        ('Cursor plan', ['Models', 'Other Models']),
        ('Codex plan', ['Legacy dynamic']),
      ]) {
        await _openRowAlerts(tester, row);
        final dialog = tester.widget<ConnectionAlertsDialog>(
          find.byType(ConnectionAlertsDialog),
        );
        expect(dialog.planWindows.map((value) => value.label), labels);
        expect(
          dialog.planWindows.every((value) => value.usedPercent == null),
          isTrue,
        );
        expect(find.text('Sibling only'), findsNothing);
        expect(find.text('Unknown owner'), findsNothing);
        expect(find.text('Legacy reporting'), findsNothing);
        for (final label in labels) {
          expect(find.text(label), findsOneWidget);
        }
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
      }
    },
  );

  testWidgets('catalogue refresh keeps drafts and rejects retired owners', (
    tester,
  ) async {
    final credentials = _MemoryCredentialStore();
    var preferences = const AlertThresholdPreferences().withConnection(
      ProviderConnections.cursorPlan,
      const ConnectionAlertThresholds(
        planWindows: {'saved': AlertPercentThreshold()},
      ),
    );
    DashboardSnapshot? snapshot;
    var revision = 0;
    var saves = 0;
    late StateSetter refresh;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              refresh = setState;
              return ProvidersScreen(
                onRefresh: _noRefresh,
                credentialStore: credentials,
                codexAccountService: const EmptyCodexAccountService(),
                claudeAccountService: const EmptyClaudeAccountService(),
                onCredentialsChanged: () {},
                alertThresholds: preferences,
                onAlertThresholdsChanged: (edit) async {
                  final next = edit(preferences);
                  refresh(() => preferences = next);
                  saves++;
                },
                snapshot: snapshot,
                alertContextRevision: revision,
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await _openRowAlerts(tester, 'Cursor plan');
    expect(find.text('Plan'), findsOneWidget);
    expect(find.text('Purchased'), findsOneWidget);
    await _chooseAlert(tester, 'Plan', '20% left');
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(saves, 0);
    refresh(() {
      snapshot = _windowSnapshot([
        _windowAccount('cursor', 'cursor.plan', ['Initial'], ids: ['saved']),
      ]);
    });
    await tester.pumpAndSettle();
    await _openRowAlerts(tester, 'Cursor plan');
    await _chooseAlert(tester, 'Initial', 'Custom % left');
    final field = find.byType(TextFormField);
    await tester.ensureVisible(field);
    await tester.enterText(field, '17x');
    refresh(() => snapshot = null);
    await tester.pumpAndSettle();
    expect(find.textContaining('Unavailable window'), findsOneWidget);
    expect(tester.widget<TextFormField>(field).controller!.text, '17x');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(saves, 0);
    refresh(() {
      snapshot = _windowSnapshot([
        _windowAccount(
          'cursor',
          'cursor.plan',
          ['New pool', 'Renamed'],
          ids: ['new', 'saved'],
        ),
      ]);
    });
    await tester.pumpAndSettle();
    expect(find.text('Renamed'), findsOneWidget);
    expect(find.text('New pool'), findsOneWidget);
    expect(tester.widget<TextFormField>(field).controller!.text, '17x');
    await tester.enterText(field, '17');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(saves, 1);
    expect(
      preferences
          .forConnection(ProviderConnections.cursorPlan)
          .planWindows['saved']!
          .at,
      83,
    );

    // A draft from the prior credential/surface owner cannot save on retirement.
    await _openRowAlerts(tester, 'Cursor plan');
    refresh(() {
      revision++;
      snapshot = null;
    });
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(saves, 1);
    ScaffoldMessenger.of(
      tester.element(find.byType(ProvidersScreen)),
    ).hideCurrentSnackBar();
    await tester.pumpAndSettle();
    await _openRowAlerts(tester, 'Cursor plan');
    expect(find.text('Plan'), findsOneWidget);
    expect(find.text('Purchased'), findsOneWidget);
    expect(find.text('Plan window · saved'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  group('reporting proof', () {
    Future<void> show(
      WidgetTester tester,
      _MemoryCredentialStore store,
      Map<ProviderConnectionId, ConnectionReportingUpdate> updates, {
      VoidCallback? changed,
      bool mock = false,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ProvidersScreen(
              credentialStore: store,
              codexAccountService: const EmptyCodexAccountService(),
              claudeAccountService: const EmptyClaudeAccountService(),
              onCredentialsChanged: changed ?? () {},
              reportingUpdates: updates,
              isSnapshotCurrent:
                  (snapshot) async => snapshot.connectionVersions.entries.every(
                    (entry) => CredentialVersion(entry.value).sameCache(
                      store.version(
                        ProviderConnectionId.fromStorageKey(entry.key)!,
                      ),
                    ),
                  ),
              mockDataEnabled: mock,
              alertThresholds: const AlertThresholdPreferences(),
              onAlertThresholdsChanged: (_) async {},
              onRefresh: _noRefresh,
              cursorPlanSignIn: (_) async => null,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    ConnectionReportingUpdate proof(
      _MemoryCredentialStore store,
      ProviderConnectionId id,
      ReportingOutcomeCategory category,
    ) => ConnectionReportingUpdate(
      connection: id,
      credentialVersion: store.version(id),
      outcome: ConnectionReportingOutcome(
        connection: id,
        credentialVersion: store.version(id),
        category: category,
        source: ReportingOutcomeSource.live,
        freshness: ReportingOutcomeFreshness.current,
      ),
    );

    testWidgets(
      'storage and Mock cannot verify; current proof is retired by replacement',
      (tester) async {
        final store = _MemoryCredentialStore();
        const id = ProviderConnections.cursorPlatform;
        await store.writeSecret(id, 'synthetic-A');
        await show(tester, store, {});
        expect(
          _inRow('Team Admin API', find.text('Not verified')),
          findsOneWidget,
        );
        final update = proof(store, id, ReportingOutcomeCategory.success);
        await show(tester, store, {id: update});
        expect(
          _inRow('Team Admin API', find.text('Connected')),
          findsOneWidget,
        );
        await show(tester, store, {id: update}, mock: true);
        expect(
          _inRow('Team Admin API', find.text('Not verified')),
          findsOneWidget,
        );
        expect(
          find.text('Key not checked while Mock data is on.'),
          findsOneWidget,
        );
        await store.writeSecret(id, 'synthetic-B');
        await show(tester, store, {id: update});
        expect(
          _inRow('Team Admin API', find.text('Not verified')),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'Anthropic local rejection is visible but cannot establish Connected',
      (tester) async {
        final store = _MemoryCredentialStore();
        const id = ProviderConnections.anthropicPlatform;
        await store.writeSecret(id, 'sk-ant-admin01-synthetic');
        ConnectionReportingUpdate local(
          ReportingOutcomeCategory category,
          ReportingOutcomeFreshness freshness,
        ) => ConnectionReportingUpdate(
          connection: id,
          credentialVersion: store.version(id),
          outcome: ConnectionReportingOutcome(
            connection: id,
            credentialVersion: store.version(id),
            category: category,
            source: ReportingOutcomeSource.local,
            freshness: freshness,
          ),
        );
        await show(tester, store, {
          id: local(
            ReportingOutcomeCategory.authenticationRejected,
            ReportingOutcomeFreshness.current,
          ),
        });
        expect(
          _inRow('Organization reporting', find.text('Key rejected')),
          findsOneWidget,
        );
        expect(
          find.textContaining(anthropicReportingKeyGuidance),
          findsOneWidget,
        );
        expect(
          _inRow('Organization reporting', find.text('Connected')),
          findsNothing,
        );
        await tester.tap(find.text('Organization reporting'));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.widgetWithText(TextFormField, 'Value (leave blank to keep)'),
          'sk-ant-admin01-replacement',
        );
        await tester.tap(find.text('Save'));
        await tester.pumpAndSettle();
        expect(find.text('Replace this Console Admin key.'), findsOneWidget);
        expect(
          find.descendant(
            of: find.byType(CredentialDialog),
            matching: find.textContaining(anthropicReportingKeyGuidance),
          ),
          findsOneWidget,
        );
        expect(await store.readSecret(id), 'sk-ant-admin01-synthetic');
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
        await show(tester, store, {
          id: local(
            ReportingOutcomeCategory.success,
            ReportingOutcomeFreshness.current,
          ),
        });
        expect(
          _inRow('Organization reporting', find.text('Not verified')),
          findsOneWidget,
        );
        await show(tester, store, {
          id: local(
            ReportingOutcomeCategory.authenticationRejected,
            ReportingOutcomeFreshness.stale,
          ),
        });
        expect(
          _inRow('Organization reporting', find.text('Not verified')),
          findsOneWidget,
        );
        await show(tester, store, {
          id: proof(store, id, ReportingOutcomeCategory.success),
        });
        expect(
          _inRow('Organization reporting', find.text('Connected')),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('label-only save and Cancel preserve proof and do not poll', (
      tester,
    ) async {
      final store = _MemoryCredentialStore();
      const id = ProviderConnections.cursorPlatform;
      await store.writeSecret(id, 'synthetic-key');
      var polls = 0;
      await show(tester, store, {
        id: proof(store, id, ReportingOutcomeCategory.success),
      }, changed: () => polls++);
      await tester.tap(find.text('Team Admin API'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextFormField>(find.byType(TextFormField).first)
            .controller!
            .text,
        isEmpty,
      );
      await tester.enterText(
        find.byType(TextFormField).last,
        'Synthetic label',
      );
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(polls, 0);
      expect(_inRow('Synthetic label', find.text('Connected')), findsOneWidget);
      await tester.tap(find.text('Synthetic label'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextFormField).first,
        'unsaved-replacement',
      );
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(await store.readSecret(id), 'synthetic-key');
      expect(polls, 0);
      expect(_inRow('Synthetic label', find.text('Connected')), findsOneWidget);
    });

    testWidgets(
      'a fresh failure replaces success, with distinct permission and retry results',
      (tester) async {
        final store = _MemoryCredentialStore();
        const id = ProviderConnections.cursorPlatform;
        await store.writeSecret(id, 'synthetic-key');
        for (final category in ReportingOutcomeCategory.values) {
          await show(tester, store, {id: proof(store, id, category)});
          final outcome = proof(store, id, category).outcome!;
          expect(
            _inRow('Team Admin API', find.text(outcome.label)),
            findsOneWidget,
          );
          if (outcome.failed) {
            expect(
              _inRow(
                'Team Admin API',
                find.textContaining(outcome.connectionLabel),
              ),
              findsWidgets,
            );
            expect(
              _inRow('Team Admin API', find.text('Connected')),
              findsNothing,
            );
          }
        }
      },
    );

    for (final category in <ReportingOutcomeCategory?>[
      ReportingOutcomeCategory.accessDenied,
      null,
    ]) {
      testWidgets('later label reads preserve the current sibling: $category', (
        tester,
      ) async {
        _setTestSurface(tester, const Size(800, 2000));
        final store = _MemoryCredentialStore();
        const first = ProviderConnections.openAiPlatform;
        const later = ProviderConnections.cursorPlatform;
        await store.writeSecret(first, 'synthetic-first');
        await store.writeSecret(later, 'synthetic-later');
        final held = Completer<void>();
        final started = Completer<void>();
        store.beforeReadLabel = (id) async {
          if (id == later) {
            started.complete();
            await held.future;
          }
        };
        final validated = <DashboardSnapshot>[];
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ProvidersScreen(
                credentialStore: store,
                codexAccountService: const EmptyCodexAccountService(),
                claudeAccountService: const EmptyClaudeAccountService(),
                onCredentialsChanged: () {},
                reportingUpdates: {
                  first: proof(store, first, ReportingOutcomeCategory.success),
                  later:
                      category == null
                          ? ConnectionReportingUpdate(
                            connection: later,
                            credentialVersion: store.version(later),
                          )
                          : proof(store, later, category),
                },
                isSnapshotCurrent: (snapshot) async {
                  validated.add(snapshot);
                  return snapshot.connectionVersions.entries.every(
                    (entry) => CredentialVersion(entry.value).sameCache(
                      store.version(
                        ProviderConnectionId.fromStorageKey(entry.key)!,
                      ),
                    ),
                  );
                },
                alertThresholds: const AlertThresholdPreferences(),
                onAlertThresholdsChanged: (_) async {},
                onRefresh: _noRefresh,
                cursorPlanSignIn: (_) async => null,
              ),
            ),
          ),
        );
        await tester.pump();
        expect(started.isCompleted, isTrue);
        await store.writeSecret(first, 'synthetic-replacement');
        held.complete();
        await tester.pump();
        expect(
          validated.first.connectionVersions.keys,
          unorderedEquals([first.storageKey, later.storageKey]),
        );
        expect(
          validated.last.connectionVersions.keys,
          unorderedEquals([later.storageKey]),
        );
        expect(
          _inRow('Platform reporting', find.text('Connected')),
          findsNothing,
        );
        expect(
          _inRow('Platform reporting', find.text('Not verified')),
          findsOneWidget,
        );
        expect(
          _inRow(
            'Team Admin API',
            find.text(category == null ? 'Checking…' : 'Access denied'),
          ),
          findsOneWidget,
        );
        expect(
          tester
              .widget<ProviderConnectionRow>(
                find.widgetWithText(ProviderConnectionRow, 'Team Admin API'),
              )
              .onTap,
          category == null ? isNull : isNotNull,
        );
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      });
    }

    testWidgets('one unreadable key does not disconnect siblings', (
      tester,
    ) async {
      final store = _MemoryCredentialStore();
      await store.writeSecret(
        ProviderConnections.cursorPlatform,
        'synthetic-key',
      );
      store.unreadable = ProviderConnections.openAiPlatform;
      await show(tester, store, {
        ProviderConnections.cursorPlatform: proof(
          store,
          ProviderConnections.cursorPlatform,
          ReportingOutcomeCategory.success,
        ),
      });
      expect(_inRow('Team Admin API', find.text('Connected')), findsOneWidget);
      final primary = find.ancestor(
        of: _inRow('Platform reporting', find.text('Platform reporting')),
        matching: find.byType(InkWell),
      );
      final scrollable = find.byType(Scrollable).first;
      await tester.scrollUntilVisible(primary, 300, scrollable: scrollable);
      await tester.pumpAndSettle();
      expect(
        _inRow('Platform reporting', find.text('Could not read saved key')),
        findsOneWidget,
      );
      final primaryRect = tester.getRect(primary);
      final viewportRect = tester.getRect(scrollable);
      expect(viewportRect.intersect(primaryRect), primaryRect);
      expect(primary.hitTestable(), findsOneWidget);
      await tester.tap(primary);
      await tester.pumpAndSettle();
      final editor = find.widgetWithText(
        AlertDialog,
        'OpenAI · Platform reporting',
      );
      expect(editor, findsOneWidget);
      expect(
        find.descendant(of: editor, matching: find.text('Remove')),
        findsOneWidget,
      );
    });
  });

  group('connection row layout', () {
    testWidgets('all active rows keep actions right and status below at 360dp', (
      tester,
    ) async {
      final store = _MemoryCredentialStore();
      await store.writeLabel(
        ProviderConnections.openAiPlatform,
        'Synthetic reporting connection',
      );
      await _pumpProvidersAtSize(tester, const Size(360, 640), store: store);
      for (final title in const [
        'Claude plan',
        'Organization reporting',
        'Cursor plan',
        'Team Admin API',
        'Codex plan',
        'Synthetic reporting connection',
      ]) {
        final row = find.widgetWithText(ProviderConnectionRow, title);
        await tester.scrollUntilVisible(
          row,
          300,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        final primary = find.ancestor(
          of: _inRow(title, find.text(title)),
          matching: find.byType(InkWell),
        );
        final status = _inRow(title, find.text('Not connected'));
        final alerts = _inRow(title, find.byTooltip('Alert thresholds'));
        final budget = _inRow(title, find.byTooltip('Budget limits'));
        final help = _inRow(title, find.byTooltip('About Cursor plan sign-in'));
        final isPlan = title.endsWith(' plan');
        expect(budget, isPlan ? findsNothing : findsOneWidget);
        expect(help, title == 'Cursor plan' ? findsOneWidget : findsNothing);
        final targets = [
          primary,
          if (!isPlan) budget,
          if (title == 'Cursor plan') help,
          alerts,
        ];
        final rowRect = tester.getRect(row);
        final primaryRect = tester.getRect(primary);
        final titleText = _inRow(title, find.text(title));
        final titleRect = tester.getRect(titleText);
        final paragraph = tester.renderObject<RenderParagraph>(titleText);
        final selection = TextSelection(
          baseOffset: 0,
          extentOffset: title.length,
        );
        final titleBoxes = paragraph.getBoxesForSelection(selection);
        final localSelectionRects = [
          for (final box in titleBoxes) box.toRect(),
        ];
        final globalSelectionRects = [
          for (final rect in localSelectionRects)
            MatrixUtils.transformRect(paragraph.getTransformTo(null), rect),
        ];
        final paragraphRect = Offset.zero & paragraph.size;
        final statusRect = tester.getRect(status);
        final layoutContext =
            'catalogTitle=$title; '
            'selection=${selection.baseOffset}..${selection.extentOffset}; '
            'localSelectionLTRB=${[
              for (final rect in localSelectionRects) [rect.left, rect.top, rect.right, rect.bottom],
            ]}; '
            'globalSelectionLTRB=${[
              for (final rect in globalSelectionRects) [rect.left, rect.top, rect.right, rect.bottom],
            ]}; '
            'paragraphLocalLTRB=${[paragraphRect.left, paragraphRect.top, paragraphRect.right, paragraphRect.bottom]}; '
            'paragraphGlobalLTRB=${[titleRect.left, titleRect.top, titleRect.right, titleRect.bottom]}; '
            'primaryGlobalLTRB=${[primaryRect.left, primaryRect.top, primaryRect.right, primaryRect.bottom]}; '
            'constraints=${paragraph.constraints}; '
            'style=${paragraph.text.style}; '
            'textAlign=${paragraph.textAlign}; '
            'textDirection=${paragraph.textDirection}; '
            'textWidthBasis=${paragraph.textWidthBasis}; '
            'softWrap=${paragraph.softWrap}; maxLines=${paragraph.maxLines}; '
            'overflow=${paragraph.overflow}; '
            'textScaler=${paragraph.textScaler}; '
            'textScaleAt1=${paragraph.textScaler.scale(1)}; '
            'dpr=${tester.view.devicePixelRatio}; '
            'titleToPrimaryLTRB=${[titleRect.left - primaryRect.left, titleRect.top - primaryRect.top, primaryRect.right - titleRect.right, primaryRect.bottom - titleRect.bottom]}; '
            'primaryToRowLTRB=${[primaryRect.left - rowRect.left, primaryRect.top - rowRect.top, rowRect.right - primaryRect.right, rowRect.bottom - primaryRect.bottom]}; '
            'statusGap=${statusRect.top - primaryRect.bottom}';
        expect(
          titleRect.left,
          greaterThanOrEqualTo(primaryRect.left),
          reason: layoutContext,
        );
        expect(
          titleRect.right,
          lessThanOrEqualTo(primaryRect.right),
          reason: layoutContext,
        );
        expect(
          titleRect.top,
          greaterThanOrEqualTo(primaryRect.top),
          reason: layoutContext,
        );
        expect(
          titleRect.bottom,
          lessThanOrEqualTo(primaryRect.bottom),
          reason: layoutContext,
        );
        expect(paragraph.didExceedMaxLines, isFalse, reason: layoutContext);
        expect(titleBoxes, isNotEmpty, reason: layoutContext);
        if (title == 'Synthetic reporting connection') {
          expect(titleBoxes.length, greaterThan(1), reason: layoutContext);
        }
        // Full selection containment proves ownership and nonintrusion into
        // adjacent targets, not glyph ink-fit or absence of clipping. Actual
        // device glyph and readability acceptance remains mandatory.
        for (final rect in globalSelectionRects) {
          expect(
            rect.left,
            greaterThanOrEqualTo(primaryRect.left),
            reason: layoutContext,
          );
          expect(
            rect.right,
            lessThanOrEqualTo(primaryRect.right),
            reason: layoutContext,
          );
          expect(
            rect.top,
            greaterThanOrEqualTo(primaryRect.top),
            reason: layoutContext,
          );
          expect(
            rect.bottom,
            lessThanOrEqualTo(primaryRect.bottom),
            reason: layoutContext,
          );
        }
        for (var index = 0; index < targets.length; index++) {
          final rect = tester.getRect(targets[index]);
          expect(rect.width, greaterThanOrEqualTo(48), reason: layoutContext);
          expect(rect.height, greaterThanOrEqualTo(48), reason: layoutContext);
          expect(
            rect.left,
            greaterThanOrEqualTo(rowRect.left),
            reason: layoutContext,
          );
          expect(
            rect.right,
            lessThanOrEqualTo(rowRect.right),
            reason: layoutContext,
          );
          expect(
            rect.top,
            greaterThanOrEqualTo(rowRect.top),
            reason: layoutContext,
          );
          expect(
            rect.bottom,
            lessThanOrEqualTo(rowRect.bottom),
            reason: layoutContext,
          );
          expect(
            statusRect.top,
            greaterThanOrEqualTo(rect.bottom),
            reason: layoutContext,
          );
          if (index > 0) {
            final previous = tester.getRect(targets[index - 1]);
            expect(
              rect.left,
              greaterThanOrEqualTo(previous.right),
              reason: layoutContext,
            );
            expect(
              rect.top,
              closeTo(primaryRect.top, 0.1),
              reason: layoutContext,
            );
          }
        }
        expect(
          tester.getRect(alerts).right,
          closeTo(rowRect.right - 16, 0.1),
          reason: layoutContext,
        );
        expect(
          statusRect.left,
          closeTo(tester.getRect(find.text(title)).left, 0.1),
          reason: layoutContext,
        );
        expect(
          statusRect.right,
          lessThanOrEqualTo(rowRect.right - 16),
          reason: layoutContext,
        );
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('enlarged text keeps errors readable and targets independent', (
      tester,
    ) async {
      _setTestSurface(tester, const Size(411, 900));
      final semantics = tester.ensureSemantics();
      try {
        var primaryTaps = 0;
        var budgetTaps = 0;
        var alertTaps = 0;
        const title = 'A long saved reporting label';
        const purpose = 'Cursor · Team Admin API';
        const error =
            "Check this key's permissions and your account's reporting access.";
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: MediaQuery(
                data: const MediaQueryData(textScaler: TextScaler.linear(1.7)),
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Card(
                      child: ProviderConnectionRow(
                        icon: Icons.key_outlined,
                        title: title,
                        subtitle: purpose,
                        status: const Text('Access denied'),
                        supportingText: error,
                        onTap: () => primaryTaps++,
                        actions: [
                          IconButton(
                            tooltip: 'Budget limits',
                            onPressed: () => budgetTaps++,
                            icon: const Icon(Icons.savings),
                          ),
                          IconButton(
                            tooltip: 'Alert thresholds',
                            onPressed: () => alertTaps++,
                            icon: const Icon(Icons.notifications),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final primary = find.ancestor(
          of: find.text(title),
          matching: find.byType(InkWell),
        );
        final budget = find.byTooltip('Budget limits');
        final alerts = find.byTooltip('Alert thresholds');
        final nodes = [
          tester.getSemantics(primary),
          tester.getSemantics(budget),
          tester.getSemantics(alerts),
        ];
        expect(nodes.map((node) => node.id).toSet(), hasLength(3));
        for (final node in nodes) {
          expect(
            node.getSemanticsData().hasAction(SemanticsAction.tap),
            isTrue,
          );
          expect(node.getSemanticsData().flagsCollection.isButton, isTrue);
        }
        expect(nodes[0].getSemanticsData().label, contains(title));
        expect(nodes[0].getSemanticsData().label, contains(purpose));
        expect(nodes[1].getSemanticsData().tooltip, 'Budget limits');
        expect(nodes[2].getSemanticsData().tooltip, 'Alert thresholds');
        final rowRect = tester.getRect(find.byType(ProviderConnectionRow));
        final statusRect = tester.getRect(find.text('Access denied'));
        final errorRect = tester.getRect(find.text(error));
        final titleRect = tester.getRect(find.text(title));
        final primaryRect = tester.getRect(primary);
        expect(titleRect.height, greaterThan(30));
        expect(titleRect.right, lessThanOrEqualTo(primaryRect.right));
        expect(
          primaryRect.right,
          lessThanOrEqualTo(tester.getRect(budget).left),
        );
        expect(
          tester.getRect(budget).right,
          lessThanOrEqualTo(tester.getRect(alerts).left),
        );
        for (final target in [primary, budget, alerts]) {
          final rect = tester.getRect(target);
          expect(rect.width, greaterThanOrEqualTo(48));
          expect(rect.height, greaterThanOrEqualTo(48));
          expect(statusRect.top, greaterThanOrEqualTo(rect.bottom));
        }
        expect(errorRect.top, greaterThan(statusRect.bottom));
        expect(errorRect.right, lessThanOrEqualTo(rowRect.right));
        expect(errorRect.bottom, lessThanOrEqualTo(rowRect.bottom));
        await tester.tap(budget);
        expect([primaryTaps, budgetTaps, alertTaps], [0, 1, 0]);
        await tester.tap(alerts);
        expect([primaryTaps, budgetTaps, alertTaps], [0, 1, 1]);
        await tester.tap(primary);
        expect([primaryTaps, budgetTaps, alertTaps], [1, 1, 1]);
        expect(tester.takeException(), isNull);
      } finally {
        semantics.dispose();
      }
    });

    testWidgets('compact row grows for a long status', (tester) async {
      _setTestSurface(tester, const Size(320, 640));
      const longStatus =
          'Waiting for account authorization before usage can refresh';

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: ProviderConnectionRow(
                    icon: Icons.key_outlined,
                    title: 'Team Admin API',
                    subtitle: 'Team key with reporting access',
                    status: const Text(longStatus),
                    actions: [
                      IconButton(
                        tooltip: 'Budget limits',
                        onPressed: () {},
                        icon: const Icon(Icons.savings_outlined),
                      ),
                      IconButton(
                        tooltip: 'Alert thresholds',
                        onPressed: () {},
                        icon: const Icon(Icons.notifications_none_outlined),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );

      final row = find.widgetWithText(ProviderConnectionRow, 'Team Admin API');
      final status = find.text(longStatus);
      final rowRect = tester.getRect(row);
      final statusRect = tester.getRect(status);
      expect(statusRect.height, greaterThan(40));
      expect(rowRect.height, greaterThan(88));
      expect(statusRect.bottom, lessThan(rowRect.bottom));
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('Cursor plan row shows Not connected and help Advanced paste', (
    tester,
  ) async {
    final store = _MemoryCredentialStore();
    var credentialsChanged = 0;
    var signInCalls = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ProvidersScreen(
            onRefresh: _noRefresh,
            credentialStore: store,
            codexAccountService: const EmptyCodexAccountService(),
            claudeAccountService: const EmptyClaudeAccountService(),
            onCredentialsChanged: () => credentialsChanged++,
            alertThresholds: const AlertThresholdPreferences(),
            onAlertThresholdsChanged: (_) async {},
            cursorPlanSignIn: (_) async {
              signInCalls++;
              return null;
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('Cursor plan'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    expect(find.text('Cursor plan'), findsOneWidget);
    expect(find.text('Experimental · dashboard sign-in'), findsOneWidget);
    expect(find.text('Not connected'), findsWidgets);

    await tester.tap(find.byTooltip('About Cursor plan sign-in'));
    await tester.pumpAndSettle();

    expect(find.text('Cursor plan sign-in'), findsOneWidget);
    expect(find.text('Advanced paste'), findsOneWidget);
    expect(signInCalls, 0);
    expect(credentialsChanged, 0);
    await tester.tap(find.text('Advanced paste'));
    await tester.pumpAndSettle();

    expect(find.text('Cursor plan · Paste token'), findsOneWidget);
    const pasted =
        'user_01TEST::eyJhbGciOiJSUzI1NiJ9.payload.signature_padding==';
    final value = find.byType(TextFormField).first;
    await tester.ensureVisible(value);
    await tester.pumpAndSettle();
    await tester.tap(value);
    await tester.enterText(value, ' ${Uri.encodeComponent(pasted)} ');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(await store.readSecret(ProviderConnections.cursorPlan), pasted);
    expect(credentialsChanged, 1);
    expect(find.text('Connected'), findsWidgets);
  });

  testWidgets('Cursor plan Sign in uses injected port and marks Connected', (
    tester,
  ) async {
    final store = _ReconnectMemoryCredentialStore();
    await store.writeSecret(
      ProviderConnections.cursorPlatform,
      'team-sentinel',
    );
    var credentialsChanged = 0;
    var signInCalls = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ProvidersScreen(
            onRefresh: _noRefresh,
            credentialStore: store,
            codexAccountService: const EmptyCodexAccountService(),
            claudeAccountService: const EmptyClaudeAccountService(),
            onCredentialsChanged: () => credentialsChanged++,
            alertThresholds: const AlertThresholdPreferences(),
            onAlertThresholdsChanged: (_) async {},
            cursorPlanSignIn: (_) async {
              signInCalls++;
              return ' user_01WEB%3A%3AeyJhbGciOiJSUzI1NiJ9.payload.signature_padding%3D%3D ';
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('Cursor plan'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cursor plan'));
    await tester.pumpAndSettle();

    expect(signInCalls, 1);
    expect(
      await store.readSecret(ProviderConnections.cursorPlan),
      'user_01WEB::eyJhbGciOiJSUzI1NiJ9.payload.signature_padding==',
    );
    expect(find.text('Connected'), findsWidgets);
    expect(credentialsChanged, 1);
    expect(store.reconnectCalls, ['begin:cursor.plan', 'complete:cursor.plan']);
    expect(
      await store.readSecret(ProviderConnections.cursorPlatform),
      'team-sentinel',
    );
  });

  for (final installed in [false, true]) {
    testWidgets(
      'Cursor cancellation preserves saved state (installed: $installed)',
      (tester) async {
        final store = _ReconnectMemoryCredentialStore();
        if (installed) {
          await store.writeSecret(
            ProviderConnections.cursorPlan,
            'saved-session',
          );
        }
        var changes = 0;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ProvidersScreen(
                onRefresh: _noRefresh,
                credentialStore: store,
                codexAccountService: const EmptyCodexAccountService(),
                claudeAccountService: const EmptyClaudeAccountService(),
                onCredentialsChanged: () => changes++,
                alertThresholds: const AlertThresholdPreferences(),
                onAlertThresholdsChanged: (_) async {},
                cursorPlanSignIn: (_) async => null,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.text('Cursor plan'),
          300,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.tap(find.text('Cursor plan'));
        await tester.pumpAndSettle();
        if (installed) {
          await tester.tap(find.text('Sign in again'));
          await tester.pumpAndSettle();
        }
        expect(
          await store.readSecret(ProviderConnections.cursorPlan),
          installed ? 'saved-session' : null,
        );
        expect(store.reconnectCalls, [
          'begin:cursor.plan',
          'cancel:cursor.plan',
        ]);
        expect(changes, 0);
      },
    );
  }

  testWidgets(
    'reporting controls and primary tap open only their own dialogs',
    (tester) async {
      final store = _MemoryCredentialStore();
      await store.writeSecret(
        ProviderConnections.cursorPlatform,
        'synthetic-key',
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ProvidersScreen(
              onRefresh: _noRefresh,
              credentialStore: store,
              codexAccountService: const EmptyCodexAccountService(),
              claudeAccountService: const EmptyClaudeAccountService(),
              onCredentialsChanged:
                  () => fail('Unexpected credential mutation'),
              alertThresholds: const AlertThresholdPreferences(),
              onAlertThresholdsChanged:
                  (_) async => fail('Unexpected settings save'),
              cursorPlanSignIn: (_) async => null,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.text('Team Admin API'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();

      expect(
        _inRow('Cursor plan', find.byTooltip('Budget limits')),
        findsNothing,
      );
      expect(
        _inRow('Cursor plan', find.byTooltip('Alert thresholds')),
        findsOneWidget,
      );
      expect(
        _inRow('Team Admin API', find.byTooltip('Budget limits')),
        findsOneWidget,
      );
      for (final (tooltip, dialog) in const [
        ('Budget limits', 'Budget · Cursor · Team Admin API'),
        ('Alert thresholds', 'Alerts · Cursor · Team Admin API'),
      ]) {
        final action = _inRow('Team Admin API', find.byTooltip(tooltip));
        await tester.ensureVisible(action);
        await tester.tap(action);
        await tester.pumpAndSettle();
        expect(find.text(dialog), findsOneWidget);
        expect(find.byType(AlertDialog), findsOneWidget);
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
      }
      await tester.tap(find.text('Team Admin API'));
      await tester.pumpAndSettle();
      expect(find.text('Cursor · Team Admin API'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(
        await store.readSecret(ProviderConnections.cursorPlatform),
        'synthetic-key',
      );
    },
  );

  testWidgets('colliding aliases keep canonical editors and save targets', (
    tester,
  ) async {
    const alias = 'Shared reporting key';
    const sources = [
      (
        ProviderConnections.openAiPlatform,
        'OpenAI · Platform reporting',
        1000,
        80,
      ),
      (
        ProviderConnections.anthropicPlatform,
        'Anthropic · Organization reporting',
        2000,
        70,
      ),
    ];
    final store = _MemoryCredentialStore();
    for (final (id, _, _, _) in sources) {
      await store.writeSecret(id, 'synthetic-key');
      await store.writeLabel(id, alias);
    }
    var preferences = AlertThresholdPreferences(
      connections: {
        for (final (id, _, limit, at) in sources)
          id.storageKey: ConnectionAlertThresholds(
            today: AlertPercentThreshold(at: at),
            budget: ConnectionBudget(today: limit),
          ),
      },
    );
    var saves = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder:
                (context, setState) => ProvidersScreen(
                  onRefresh: _noRefresh,
                  credentialStore: store,
                  codexAccountService: const EmptyCodexAccountService(),
                  claudeAccountService: const EmptyClaudeAccountService(),
                  onCredentialsChanged:
                      () => fail('Unexpected credential mutation'),
                  alertThresholds: preferences,
                  onAlertThresholdsChanged: (edit) async {
                    setState(() => preferences = edit(preferences));
                    saves++;
                  },
                  cursorPlanSignIn: (_) async => null,
                ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    for (final (id, title, limit, at) in sources) {
      Future<void> open(String tooltip, String heading) async {
        tester
            .state<ScrollableState>(find.byType(Scrollable).first)
            .position
            .jumpTo(0);
        await tester.pumpAndSettle();
        final row = find.byWidgetPredicate(
          (widget) =>
              widget is ProviderConnectionRow &&
              widget.title == alias &&
              widget.subtitle.startsWith('$title\n'),
        );
        final action = find.descendant(
          of: row,
          matching: find.byTooltip(tooltip),
        );
        await tester.scrollUntilVisible(
          action,
          300,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        await tester.tap(action);
        await tester.pumpAndSettle();
        expect(find.text('$heading · $title'), findsOneWidget);
        expect(find.text('$heading · $alias'), findsNothing);
      }

      final beforeBudget = preferences;
      final beforeSaves = saves;
      for (final action in ['Cancel', 'Save']) {
        await open('Budget limits', 'Budget');
        final dialog = tester.widget<ConnectionBudgetDialog>(
          find.byType(ConnectionBudgetDialog),
        );
        expect(
          dialog.budget.toJson(),
          beforeBudget.forConnection(id).budget.toJson(),
        );
        final field =
            find
                .descendant(
                  of: find.byType(ConnectionBudgetDialog),
                  matching: find.byType(TextFormField),
                )
                .first;
        expect(
          tester.widget<TextFormField>(field).controller!.text,
          '${limit ~/ 100}.00',
        );
        await tester.enterText(field, '99.00');
        await tester.tap(find.text(action));
        await tester.pumpAndSettle();
        final expected =
            action == 'Cancel'
                ? beforeBudget
                : beforeBudget.withConnection(
                  id,
                  beforeBudget
                      .forConnection(id)
                      .copyWith(budget: const ConnectionBudget(today: 9900)),
                );
        expect(preferences.toJson(), expected.toJson());
        expect(saves, beforeSaves + (action == 'Save' ? 1 : 0));
      }

      final beforeAlerts = preferences;
      for (final action in ['Cancel', 'Save']) {
        await open('Alert thresholds', 'Alerts');
        final dialog = tester.widget<ConnectionAlertsDialog>(
          find.byType(ConnectionAlertsDialog),
        );
        expect(dialog.connection, id);
        expect(
          dialog.thresholds.toJson(),
          beforeAlerts.forConnection(id).toJson(),
        );
        expect(
          tester
              .widget<AlertPercentThresholdEditor>(
                find.widgetWithText(AlertPercentThresholdEditor, 'Today'),
              )
              .value
              .at,
          at,
        );
        await _chooseAlert(tester, 'Today', 'Off');
        await tester.tap(find.text(action));
        await tester.pumpAndSettle();
        final expected =
            action == 'Cancel'
                ? beforeAlerts
                : beforeAlerts.withConnection(
                  id,
                  beforeAlerts
                      .forConnection(id)
                      .copyWith(today: const AlertPercentThreshold()),
                );
        expect(preferences.toJson(), expected.toJson());
        expect(saves, beforeSaves + (action == 'Save' ? 2 : 1));
      }
      expect(await store.readSecret(id), 'synthetic-key');
      expect(await store.readLabel(id), alias);
    }
  });

  testWidgets('missing budget limits disable alerts with readable guidance', (
    tester,
  ) async {
    // Use the phone font so line wrapping reflects the actual dialog widths.
    await tester.runAsync(() async {
      final flutterRoot = Directory(Platform.environment['FLUTTER_ROOT']!).uri;
      final loader = FontLoader('Roboto');
      for (final weight in ['Regular', 'Medium']) {
        loader.addFont(
          File.fromUri(
            flutterRoot.resolve(
              'bin/cache/artifacts/material_fonts/Roboto-$weight.ttf',
            ),
          ).readAsBytes().then((bytes) => ByteData.sublistView(bytes)),
        );
      }
      await loader.load();
    });
    _setTestSurface(tester, const Size(411, 640));
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    final initial = const AlertThresholdPreferences()
        .withConnection(
          ProviderConnections.cursorPlatform,
          const ConnectionAlertThresholds(
            today: AlertPercentThreshold(at: 70),
            week: AlertPercentThreshold(at: 90),
            month: AlertPercentThreshold(at: 80),
            budget: ConnectionBudget(month: 2000),
          ),
        )
        .withConnection(
          ProviderConnections.openAiPlatform,
          const ConnectionAlertThresholds(
            today: AlertPercentThreshold(at: 50),
            budget: ConnectionBudget(today: 4000),
          ),
        );
    AlertThresholdPreferences? saved;
    var saves = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: wardPulseDarkTheme,
        home: Scaffold(
          body: ProvidersScreen(
            onRefresh: _noRefresh,
            credentialStore: _MemoryCredentialStore(),
            codexAccountService: const EmptyCodexAccountService(),
            claudeAccountService: const EmptyClaudeAccountService(),
            onCredentialsChanged: () => fail('Unexpected credential mutation'),
            alertThresholds: initial,
            onAlertThresholdsChanged: (edit) async {
              saved = edit(initial);
              saves++;
            },
            cursorPlanSignIn: (_) async => null,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    Future<void> openAlerts() async {
      final action = _inRow(
        'Team Admin API',
        find.byTooltip('Alert thresholds'),
      );
      await tester.scrollUntilVisible(
        action,
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(action);
      await tester.pumpAndSettle();
      expect(find.text('Alerts · Cursor · Team Admin API'), findsOneWidget);
    }

    final dialog = find.byType(AlertDialog);
    final scrollable = find.descendant(
      of: dialog,
      matching: find.byType(Scrollable),
    );
    Finder editor(String period) =>
        find.widgetWithText(AlertPercentThresholdEditor, period);
    Finder dropdown(String period) => find.descendant(
      of: editor(period),
      matching: find.byType(DropdownButton<int?>),
    );
    Future<List<({int lines, double lineHeight})>> inspectGuidance() async {
      const reason = 'Set this period’s limit under Budget limits';
      final periods =
          tester
              .widgetList<DropdownButton<int?>>(
                find.descendant(
                  of: dialog,
                  matching: find.byType(DropdownButton<int?>),
                ),
              )
              .toList();
      expect(periods, hasLength(3));
      expect(periods[0].onChanged, isNull, reason: 'Today has no limit');
      expect(periods[1].onChanged, isNull, reason: 'Week has no limit');
      expect(periods[2].onChanged, isNotNull, reason: 'Month has a limit');
      expect(periods.map((period) => period.value), [30, 10, 20]);
      expect(scrollable, findsOneWidget);
      final measurements = <({int lines, double lineHeight})>[];
      for (final period in const ['Today', 'Week']) {
        final control = editor(period);
        await tester.ensureVisible(control);
        await tester.pumpAndSettle();
        final helper = find.descendant(
          of: control,
          matching: find.text(reason),
        );
        final paragraph = tester.renderObject<RenderParagraph>(helper);
        final origin = paragraph.localToGlobal(Offset.zero);
        final paragraphRect = origin & paragraph.size;
        final boxes = paragraph.getBoxesForSelection(
          TextSelection(baseOffset: 0, extentOffset: reason.length),
        );
        expect(boxes, isNotEmpty, reason: period);
        expect(paragraph.didExceedMaxLines, isFalse, reason: period);
        expect(paragraph.textScaler.scale(10), closeTo(13, 0.001));
        expect(
          tester.getRect(dropdown(period)).bottom,
          lessThanOrEqualTo(paragraphRect.top),
          reason: '$period guidance must not overlap its dropdown',
        );
        // Every visible character, including the final "Budget limits", must
        // survive layout and fit inside the editor and the scrolled viewport.
        final containmentBounds = [
          paragraphRect,
          tester.getRect(control),
          tester.getRect(scrollable),
          tester.getRect(dialog),
        ];
        for (var offset = 0; offset < reason.length; offset++) {
          if (reason[offset] == ' ') continue;
          final glyphs = paragraph.getBoxesForSelection(
            TextSelection(baseOffset: offset, extentOffset: offset + 1),
          );
          expect(glyphs, hasLength(1), reason: '$period[$offset]');
          final glyph = glyphs.single.toRect().shift(origin);
          expect(glyph.width, greaterThan(0), reason: '$period[$offset]');
          expect(glyph.height, greaterThan(0), reason: '$period[$offset]');
          for (final bounds in containmentBounds) {
            expect(
              bounds.inflate(0.001).contains(glyph.topLeft),
              isTrue,
              reason: '$period[$offset] starts outside $bounds',
            );
            expect(
              bounds.inflate(0.001).contains(glyph.bottomRight),
              isTrue,
              reason: '$period[$offset] ends outside $bounds',
            );
          }
        }
        measurements.add((
          lines: boxes.length,
          lineHeight: boxes.first.bottom - boxes.first.top,
        ));
      }
      expect(
        tester.getRect(editor('Today')).bottom,
        lessThanOrEqualTo(tester.getRect(editor('Week')).top),
      );
      expect(
        tester.getRect(editor('Week')).bottom,
        lessThanOrEqualTo(tester.getRect(editor('Month')).top),
      );
      for (final button in [
        find.widgetWithText(TextButton, 'Cancel'),
        find.widgetWithText(FilledButton, 'Save'),
      ]) {
        expect(button.hitTestable(), findsOneWidget);
        final bounds = tester.getRect(button);
        expect(tester.getRect(dialog).intersect(bounds), bounds);
        expect(
          tester.getRect(scrollable).bottom,
          lessThanOrEqualTo(bounds.top),
        );
      }
      return measurements;
    }

    Future<void> changeMonth() async {
      await tester.ensureVisible(editor('Month'));
      await tester.pumpAndSettle();
      expect(dropdown('Month').hitTestable(), findsOneWidget);
      await tester.tap(dropdown('Month'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('30% left').last);
      await tester.pumpAndSettle();
      expect(tester.widget<DropdownButton<int?>>(dropdown('Month')).value, 30);
    }

    await openAlerts();
    final ordinary = await inspectGuidance();
    await changeMonth();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(saved, isNull);
    expect(saves, 0);

    tester.view.physicalSize = const Size(360, 640);
    await tester.pumpAndSettle();
    await openAlerts();
    final narrow = await inspectGuidance();
    for (var index = 0; index < narrow.length; index++) {
      expect(narrow[index].lines, greaterThan(1));
      expect(narrow[index].lines, greaterThanOrEqualTo(ordinary[index].lines));
      expect(
        narrow[index].lineHeight,
        closeTo(ordinary[index].lineHeight, 0.001),
      );
    }
    await changeMonth();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(dialog, findsNothing);
    expect(saves, 1);
    expect(
      saved!.toJson(),
      initial
          .withConnection(
            ProviderConnections.cursorPlatform,
            initial
                .forConnection(ProviderConnections.cursorPlatform)
                .copyWith(month: const AlertPercentThreshold(at: 70)),
          )
          .toJson(),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('a recovery is not something a connection configures', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ProvidersScreen(
            onRefresh: _noRefresh,
            credentialStore: _MemoryCredentialStore(),
            codexAccountService: const EmptyCodexAccountService(),
            claudeAccountService: const EmptyClaudeAccountService(),
            onCredentialsChanged: () {},
            alertThresholds: const AlertThresholdPreferences(),
            onAlertThresholdsChanged: (_) async {},
            cursorPlanSignIn: (_) async => null,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // The switch lives in Settings, alone, because a recovery has no threshold
    // to set: it either happened or it did not. A per-connection rule here
    // would be a threshold pretending to be one.
    expect(
      find.textContaining(RegExp('recovery', caseSensitive: false)),
      findsNothing,
    );
  });

  group('the declared card order', () {
    Future<List<String>> shown(
      WidgetTester tester, {
      ProviderCredentialStore? store,
      Map<ProviderFamily, ProviderStatus> statuses = const {},
    }) async {
      _setTestSurface(tester, const Size(800, 1600));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ProvidersScreen(
              onRefresh: _noRefresh,
              credentialStore: store ?? _MemoryCredentialStore(),
              codexAccountService: const EmptyCodexAccountService(),
              claudeAccountService: const EmptyClaudeAccountService(),
              onCredentialsChanged: () {},
              alertThresholds: const AlertThresholdPreferences(),
              onAlertThresholdsChanged: (_) async {},
              cursorPlanSignIn: (_) async => null,
              statuses: statuses,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      return ['OpenAI', 'Anthropic', 'Cursor']..sort(
        (left, right) => tester
            .getTopLeft(find.text(left))
            .dy
            .compareTo(tester.getTopLeft(find.text(right)).dy),
      );
    }

    testWidgets('without a snapshot the families keep a stable name order', (
      tester,
    ) async {
      // Nothing reported yet and nothing connected: the tab still has to open
      // the same way every time.
      expect(await shown(tester), ['Anthropic', 'Cursor', 'OpenAI']);
    });

    testWidgets('the family asking for attention comes first', (tester) async {
      expect(
        await shown(
          tester,
          statuses: const {
            ProviderFamily.cursor: ProviderStatus.authRequired,
            ProviderFamily.openai: ProviderStatus.ok,
            ProviderFamily.anthropic: ProviderStatus.ok,
          },
        ),
        ['Cursor', 'Anthropic', 'OpenAI'],
      );
    });

    testWidgets('a subscription signed in without a pasted secret counts', (
      tester,
    ) async {
      // Nothing was pasted for OpenAI, but Codex is reporting, so the family is
      // connected and outranks the two that report nothing at all.
      expect(
        await shown(
          tester,
          statuses: const {ProviderFamily.openai: ProviderStatus.ok},
        ),
        ['OpenAI', 'Anthropic', 'Cursor'],
      );
    });

    testWidgets('a family with no credential sinks but stays on the tab', (
      tester,
    ) async {
      final store = _MemoryCredentialStore();
      await store.writeSecret(ProviderConnections.cursorPlatform, 'secret');

      // Cursor has a secret and is healthy; the other two report nothing and
      // hold nothing, so they follow it — still listed, because this tab is
      // where one connects them.
      expect(
        await shown(
          tester,
          store: store,
          statuses: const {ProviderFamily.cursor: ProviderStatus.ok},
        ),
        ['Cursor', 'Anthropic', 'OpenAI'],
      );
    });
  });
}

// Drain the bounded catalogue discovery and the existing 250 ms animation.
// Loading indicators intentionally remain active until the controlled read ends.
Future<void> _pumpPendingReveal(WidgetTester tester) async {
  for (var frame = 0; frame < 4; frame++) {
    await tester.pump();
  }
  await tester.pump(const Duration(milliseconds: 250));
  await tester.pump();
}

void _expectRevealFocus(Finder row) {
  final focused = FocusManager.instance.primaryFocus!.context!;
  expect(
    find.descendant(
      of: find.byElementPredicate((element) => identical(element, focused)),
      matching: row,
    ),
    findsOneWidget,
  );
}

void _expectCompleteReveal(
  WidgetTester tester,
  String title, [
  ConnectionReportingOutcome? outcome,
]) {
  final row = find.widgetWithText(ProviderConnectionRow, title);
  final viewport = tester.getRect(
    find.descendant(
      of: find.byType(ProvidersScreen),
      matching: find.byType(Viewport),
    ),
  );
  expect(
    viewport.bottom,
    lessThanOrEqualTo(tester.getTopLeft(find.byType(NavigationBar)).dy),
  );
  for (final element in [
    ...row.evaluate(),
    ...find.descendant(of: row, matching: find.byType(Text)).evaluate(),
    ...find.descendant(of: row, matching: find.byType(IconButton)).evaluate(),
  ]) {
    final rect = tester.getRect(
      find.byElementPredicate((candidate) => identical(candidate, element)),
    );
    expect(
      viewport.inflate(0.5).contains(rect.topLeft),
      isTrue,
      reason: '$rect outside $viewport',
    );
    expect(
      viewport.inflate(0.5).contains(rect.bottomRight),
      isTrue,
      reason: '$rect outside $viewport',
    );
  }
  if (outcome != null) {
    expect(_inRow(title, find.text(outcome.label)), findsOneWidget);
    expect(
      _inRow(
        title,
        find.text('${outcome.connectionLabel}\n${outcome.supportingCopy}'),
      ),
      findsOneWidget,
    );
    expect(_inRow(title, find.byTooltip('Budget limits')), findsOneWidget);
    expect(_inRow(title, find.byTooltip('Alert thresholds')), findsOneWidget);
  }
  _expectRevealFocus(row);
}

class _DelayedCodexAccountService implements CodexAccountService {
  final read = Completer<bool>();
  var reads = 0;
  @override
  Future<bool> isConnected() {
    reads++;
    return read.future;
  }

  @override
  Future<CodexLoginAttempt> startLogin() async =>
      throw StateError('Unexpected login');
  @override
  Future<String?> fetchReport() async =>
      throw StateError('Unexpected provider request');
  @override
  Future<void> disconnect() async => throw StateError('Unexpected disconnect');
}

/// Scopes a finder to the catalog row titled [title].
Finder _inRow(String title, Finder matching) => find.descendant(
  of: find.widgetWithText(ProviderConnectionRow, title),
  matching: matching,
);

DashboardSnapshot _windowSnapshot(List<ProviderSnapshot> accounts) =>
    DashboardSnapshot.fromJson({
      ...DashboardSnapshot.empty(generatedAt: DateTime.utc(2026)).toJson(),
      'accounts': [for (final account in accounts) account.toJson()],
    });

ProviderSnapshot _windowAccount(
  String provider,
  String? connection,
  List<String> labels, {
  List<String>? ids,
}) => ProviderSnapshot(
  accountId: '$provider-${connection ?? 'legacy'}',
  provider: provider,
  connection: connection,
  status: ProviderStatus.ok,
  today: const BudgetState.unknownPeriod('today'),
  week: const BudgetState.unknownPeriod('week'),
  month: const BudgetState.unknownPeriod('month'),
  credits: const [],
  allowances: [
    for (var i = 0; i < labels.length; i++)
      AllowanceState(
        id: ids?[i] ?? 'window-$i',
        source: AllowanceSource.plan,
        label: labels[i],
        usedPercent: null,
        used: null,
        limit: null,
        remaining: null,
        windowMinutes: null,
        resetsAt: null,
        status: ProviderStatus.ok,
      ),
  ],
  buckets: const [],
  modelBreakdown: const [],
  lastSuccessfulSyncAt: null,
);

Future<void> _openRowAlerts(WidgetTester tester, String row) async {
  tester
      .state<ScrollableState>(find.byType(Scrollable).first)
      .position
      .jumpTo(0);
  await tester.pumpAndSettle();
  final action = _inRow(row, find.byTooltip('Alert thresholds'));
  await tester.scrollUntilVisible(
    action,
    300,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
  await tester.tap(action);
  await tester.pumpAndSettle();
}

Future<void> _chooseAlert(
  WidgetTester tester,
  String title,
  String choice,
) async {
  final dropdown = find.descendant(
    of: find.widgetWithText(AlertPercentThresholdEditor, title),
    matching: find.byType(DropdownButton<int?>),
  );
  await tester.ensureVisible(dropdown);
  await tester.pumpAndSettle();
  await tester.tap(dropdown);
  await tester.pumpAndSettle();
  await tester.ensureVisible(find.text(choice).last);
  await tester.tap(find.text(choice).last);
  await tester.pumpAndSettle();
}

Future<void> _pumpProvidersAtSize(
  WidgetTester tester,
  Size size, {
  _MemoryCredentialStore? store,
}) async {
  _setTestSurface(tester, size);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: ProvidersScreen(
          onRefresh: _noRefresh,
          credentialStore: store ?? _MemoryCredentialStore(),
          codexAccountService: const EmptyCodexAccountService(),
          claudeAccountService: const EmptyClaudeAccountService(),
          onCredentialsChanged: () {},
          alertThresholds: const AlertThresholdPreferences(),
          onAlertThresholdsChanged: (_) async {},
          cursorPlanSignIn: (_) async => null,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void _setTestSurface(WidgetTester tester, Size size) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}

class _MemoryCredentialStore
    implements ProviderCredentialStore, VersionedProviderCredentialStore {
  final _generations = <ProviderConnectionId, int>{};
  ProviderConnectionId? unreadable;
  Future<void> Function(ProviderConnectionId)? beforeReadLabel;
  CredentialVersion version(ProviderConnectionId id) => CredentialVersion({
    'generation': '${_generations[id] ?? 0}',
    'revision': 'revision',
    'epoch': 'epoch',
    'identity': id.storageKey,
  });
  @override
  ConnectionCredentialAccess credentialAccess(ProviderConnectionId id) =>
      _MemoryCredentialAccess(this, id);
  final _secrets = <ProviderConnectionId, String>{};
  final _labels = <ProviderConnectionId, String>{};

  @override
  Future<String?> readSecret(ProviderConnectionId id) async {
    if (unreadable == id) throw StateError('Synthetic storage failure');
    return _secrets[id];
  }

  @override
  Future<void> writeSecret(ProviderConnectionId id, String value) async {
    _generations[id] = (_generations[id] ?? 0) + 1;
    _secrets[id] = value;
  }

  @override
  Future<void> deleteSecret(ProviderConnectionId id) async {
    _generations[id] = (_generations[id] ?? 0) + 1;
    _secrets.remove(id);
    _labels.remove(id);
  }

  @override
  Future<String?> readLabel(ProviderConnectionId id) async {
    await beforeReadLabel?.call(id);
    return _labels[id];
  }

  @override
  Future<void> writeLabel(ProviderConnectionId id, String? value) async {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      _labels.remove(id);
      return;
    }
    _labels[id] = trimmed;
  }
}

/// These tests drive the screen, not the reload behind the pull.
Future<void> _noRefresh() async {}

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

/// Records the row's lifecycle protocol; native lifecycle tests own persistence.
class _ReconnectMemoryCredentialStore extends _MemoryCredentialStore
    implements ReconnectProviderCredentialStore {
  final reconnectCalls = <String>[];

  @override
  Future<CredentialVersion> beginReconnect(ProviderConnectionId id) async {
    reconnectCalls.add('begin:${id.storageKey}');
    return version(id);
  }

  @override
  Future<bool> completeReconnect(
    ProviderConnectionId id,
    String value,
    CredentialVersion ticket,
  ) async {
    reconnectCalls.add('complete:${id.storageKey}');
    await writeSecret(id, value);
    return true;
  }

  @override
  Future<void> cancelReconnect(
    ProviderConnectionId id,
    CredentialVersion ticket,
  ) async {
    reconnectCalls.add('cancel:${id.storageKey}');
  }
}
