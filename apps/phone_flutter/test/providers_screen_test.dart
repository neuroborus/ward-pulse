import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ward_pulse_phone/dashboard/dashboard_models.dart';
import 'package:ward_pulse_phone/providers/claude_account_service.dart';
import 'package:ward_pulse_phone/providers/codex_account_service.dart';
import 'package:ward_pulse_phone/providers/provider_connection.dart';
import 'package:ward_pulse_phone/providers/connection_lifecycle.dart';
import 'package:ward_pulse_phone/providers/provider_connection_row.dart';
import 'package:ward_pulse_phone/providers/providers_screen.dart';
import 'package:ward_pulse_phone/providers/provider_credential_store.dart';
import 'package:ward_pulse_phone/settings/alert_threshold_preferences.dart';

void main() {
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
        const id = ProviderConnections.anthropicPlatform;
        await store.writeSecret(id, 'synthetic-A');
        await show(tester, store, {});
        expect(
          _inRow('Organization reporting', find.text('Not verified')),
          findsOneWidget,
        );
        final update = proof(store, id, ReportingOutcomeCategory.success);
        await show(tester, store, {id: update});
        expect(
          _inRow('Organization reporting', find.text('Connected')),
          findsOneWidget,
        );
        await show(tester, store, {id: update}, mock: true);
        expect(
          _inRow('Organization reporting', find.text('Not verified')),
          findsOneWidget,
        );
        expect(
          find.text('Key not checked while Mock data is on.'),
          findsOneWidget,
        );
        await store.writeSecret(id, 'synthetic-B');
        await show(tester, store, {id: update});
        expect(
          _inRow('Organization reporting', find.text('Not verified')),
          findsOneWidget,
        );
      },
    );

    testWidgets('label-only save and Cancel preserve proof and do not poll', (
      tester,
    ) async {
      final store = _MemoryCredentialStore();
      const id = ProviderConnections.anthropicPlatform;
      await store.writeSecret(id, 'synthetic-key');
      var polls = 0;
      await show(tester, store, {
        id: proof(store, id, ReportingOutcomeCategory.success),
      }, changed: () => polls++);
      await tester.tap(find.text('Organization reporting'));
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
        const id = ProviderConnections.anthropicPlatform;
        await store.writeSecret(id, 'synthetic-key');
        for (final category in ReportingOutcomeCategory.values) {
          await show(tester, store, {id: proof(store, id, category)});
          final outcome = proof(store, id, category).outcome!;
          expect(
            _inRow('Organization reporting', find.text(outcome.label)),
            findsOneWidget,
          );
          if (outcome.failed) {
            expect(
              _inRow(
                'Organization reporting',
                find.textContaining(outcome.connectionLabel),
              ),
              findsWidgets,
            );
            expect(
              _inRow('Organization reporting', find.text('Connected')),
              findsNothing,
            );
          }
        }
      },
    );

    testWidgets(
      'later label reads retire only obsolete proof and keep siblings',
      (tester) async {
        _setTestSurface(tester, const Size(800, 2000));
        final store = _MemoryCredentialStore();
        const first = ProviderConnections.openAiPlatform;
        const later = ProviderConnections.anthropicPlatform;
        const checking = ProviderConnections.cursorPlatform;
        await store.writeSecret(first, 'synthetic-first');
        await store.writeSecret(later, 'synthetic-later');
        await store.writeSecret(checking, 'synthetic-checking');
        final held = Completer<void>();
        final started = Completer<void>();
        store.beforeReadLabel = (id) async {
          if (id == checking) {
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
                  later: proof(
                    store,
                    later,
                    ReportingOutcomeCategory.accessDenied,
                  ),
                  checking: ConnectionReportingUpdate(
                    connection: checking,
                    credentialVersion: store.version(checking),
                  ),
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
          unorderedEquals([
            first.storageKey,
            later.storageKey,
            checking.storageKey,
          ]),
        );
        expect(
          validated.last.connectionVersions.keys,
          unorderedEquals([later.storageKey, checking.storageKey]),
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
          _inRow('Organization reporting', find.text('Access denied')),
          findsOneWidget,
        );
        expect(
          _inRow('Team Admin API', find.text('Checking…')),
          findsOneWidget,
        );
        expect(
          tester
              .widget<ProviderConnectionRow>(
                find.widgetWithText(ProviderConnectionRow, 'Team Admin API'),
              )
              .onTap,
          isNull,
        );
        expect(
          tester
              .widget<ProviderConnectionRow>(
                find.widgetWithText(
                  ProviderConnectionRow,
                  'Organization reporting',
                ),
              )
              .onTap,
          isNotNull,
        );
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      },
    );

    testWidgets('one unreadable key does not disconnect siblings', (
      tester,
    ) async {
      final store = _MemoryCredentialStore();
      await store.writeSecret(
        ProviderConnections.anthropicPlatform,
        'synthetic-key',
      );
      store.unreadable = ProviderConnections.openAiPlatform;
      await show(tester, store, {
        ProviderConnections.anthropicPlatform: proof(
          store,
          ProviderConnections.anthropicPlatform,
          ReportingOutcomeCategory.success,
        ),
      });
      expect(
        _inRow('Organization reporting', find.text('Connected')),
        findsOneWidget,
      );
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
    testWidgets('all six rows keep actions right and status below at 360dp', (
      tester,
    ) async {
      await _pumpProvidersAtSize(tester, const Size(360, 640));
      for (final title in const [
        'Claude plan',
        'Organization reporting',
        'Cursor plan',
        'Team Admin API',
        'Codex plan',
        'Platform reporting',
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
        expect(titleRect.left, greaterThanOrEqualTo(primaryRect.left));
        expect(titleRect.right, lessThanOrEqualTo(primaryRect.right));
        expect(titleRect.top, greaterThanOrEqualTo(primaryRect.top));
        expect(titleRect.bottom, lessThanOrEqualTo(primaryRect.bottom));
        expect(paragraph.didExceedMaxLines, isFalse);
        final titleBoxes = paragraph.getBoxesForSelection(
          TextSelection(baseOffset: 0, extentOffset: title.length),
        );
        expect(titleBoxes, isNotEmpty);
        if (title == 'Organization reporting') {
          expect(titleBoxes.length, greaterThan(1));
        }
        // Selection geometry can reach 181.75dp for a 181.5dp paragraph.
        // Round both right edges outward to physical pixels only here;
        // widget and container bounds remain strict.
        final devicePixelRatio = tester.view.devicePixelRatio;
        final paragraphWidthInPixels =
            (paragraph.size.width * devicePixelRatio).ceil();
        for (final box in titleBoxes) {
          expect(box.left, greaterThanOrEqualTo(0));
          expect(
            (box.right * devicePixelRatio).ceil(),
            lessThanOrEqualTo(paragraphWidthInPixels),
          );
        }
        final statusRect = tester.getRect(status);
        for (var index = 0; index < targets.length; index++) {
          final rect = tester.getRect(targets[index]);
          expect(rect.width, greaterThanOrEqualTo(48));
          expect(rect.height, greaterThanOrEqualTo(48));
          expect(rect.left, greaterThanOrEqualTo(rowRect.left));
          expect(rect.right, lessThanOrEqualTo(rowRect.right));
          expect(statusRect.top, greaterThanOrEqualTo(rect.bottom));
          if (index > 0) {
            final previous = tester.getRect(targets[index - 1]);
            expect(rect.left, greaterThanOrEqualTo(previous.right));
            expect(rect.top, closeTo(primaryRect.top, 0.1));
          }
        }
        expect(tester.getRect(alerts).right, closeTo(rowRect.right - 16, 0.1));
        expect(
          statusRect.left,
          closeTo(tester.getRect(find.text(title)).left, 0.1),
        );
        expect(statusRect.right, lessThanOrEqualTo(rowRect.right - 16));
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
        const purpose = 'Anthropic · Organization reporting';
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
                    title: 'Organization reporting',
                    subtitle: 'Admin API key · stored on this phone',
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

      final row = find.widgetWithText(
        ProviderConnectionRow,
        'Organization reporting',
      );
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
    await tester.enterText(value, pasted);
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(await store.readSecret(ProviderConnections.cursorPlan), pasted);
    expect(credentialsChanged, 1);
    expect(find.text('Connected'), findsWidgets);
  });

  testWidgets('Cursor plan Sign in uses injected port and marks Connected', (
    tester,
  ) async {
    final store = _MemoryCredentialStore();
    var signInCalls = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ProvidersScreen(
            onRefresh: _noRefresh,
            credentialStore: store,
            codexAccountService: const EmptyCodexAccountService(),
            claudeAccountService: const EmptyClaudeAccountService(),
            onCredentialsChanged: () {},
            alertThresholds: const AlertThresholdPreferences(),
            onAlertThresholdsChanged: (_) async {},
            cursorPlanSignIn: (_) async {
              signInCalls++;
              return 'user_01WEB::eyJhbGciOiJSUzI1NiJ9.payload.signature_padding==';
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
  });

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
        ('Budget limits', 'Budget · Team Admin API'),
        ('Alert thresholds', 'Alerts · Team Admin API'),
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

  testWidgets('a budget period without a limit cannot be alerted on', (
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
            alertThresholds: const AlertThresholdPreferences().withConnection(
              ProviderConnections.cursorPlatform,
              const ConnectionAlertThresholds(
                budget: ConnectionBudget(today: 2000),
              ),
            ),
            onAlertThresholdsChanged: (_) async {},
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
    await tester.tap(
      _inRow('Team Admin API', find.byTooltip('Alert thresholds')),
    );
    await tester.pumpAndSettle();

    final periods =
        tester
            .widgetList<DropdownButton<int?>>(find.byType(DropdownButton<int?>))
            .toList();
    expect(periods, hasLength(3));
    expect(periods[0].onChanged, isNotNull, reason: 'Today has a limit');
    expect(periods[1].onChanged, isNull);
    expect(periods[2].onChanged, isNull);
    expect(
      find.text('Set this period’s limit under Budget limits'),
      findsNWidgets(2),
    );
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

/// Scopes a finder to the catalog row titled [title].
Finder _inRow(String title, Finder matching) => find.descendant(
  of: find.widgetWithText(ProviderConnectionRow, title),
  matching: matching,
);

Future<void> _pumpProvidersAtSize(WidgetTester tester, Size size) async {
  _setTestSurface(tester, size);
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
