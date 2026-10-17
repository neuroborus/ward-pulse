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
              .widget<ListTile>(find.widgetWithText(ListTile, 'Team Admin API'))
              .onTap,
          isNull,
        );
        expect(
          tester
              .widget<ListTile>(
                find.widgetWithText(ListTile, 'Organization reporting'),
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
      await tester.scrollUntilVisible(
        find.text('Platform reporting'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(
        _inRow('Platform reporting', find.text('Could not read saved key')),
        findsOneWidget,
      );
      await tester.tap(find.text('Platform reporting'));
      await tester.pumpAndSettle();
      expect(find.text('Remove'), findsOneWidget);
    });
  });

  for (final width in [359.0, 361.0]) {
    testWidgets('reporting copy and controls fit ${width}dp at enlarged text', (
      tester,
    ) async {
      _setTestSurface(tester, Size(width, 900));
      var actions = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MediaQuery(
              data: const MediaQueryData(textScaler: TextScaler.linear(1.7)),
              child: SingleChildScrollView(
                child: SizedBox(
                  width: width,
                  child: ProviderConnectionRow(
                    icon: Icons.key_outlined,
                    title: 'Organization reporting',
                    subtitle: 'API key with reporting access',
                    status: const Text('Access denied'),
                    statusBelow: true,
                    supportingText:
                        "Check this key's permissions and your account's reporting access.",
                    actions: [
                      IconButton(
                        tooltip: 'Budget limits',
                        onPressed: () => actions++,
                        icon: const Icon(Icons.savings),
                      ),
                      IconButton(
                        tooltip: 'Alert thresholds',
                        onPressed: () => actions++,
                        icon: const Icon(Icons.notifications),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      for (final tooltip in ['Budget limits', 'Alert thresholds']) {
        await tester.ensureVisible(find.byTooltip(tooltip));
        await tester.tap(find.byTooltip(tooltip));
      }
      expect(actions, 2);
      final row = tester.getRect(find.byType(ListTile));
      final copy = tester.getRect(
        find.textContaining("Check this key's permissions"),
      );
      expect(copy.right, lessThanOrEqualTo(row.right));
      expect(copy.bottom, lessThanOrEqualTo(row.bottom));
    });
  }

  group('connection row layout', () {
    testWidgets('stacks two actions without splitting words at 320dp', (
      tester,
    ) async {
      await _pumpProvidersAtSize(tester, const Size(320, 640));

      for (final title in const ['Organization reporting', 'Team Admin API']) {
        await tester.scrollUntilVisible(
          find.text(title),
          300,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();

        final row = find.widgetWithText(ListTile, title);
        final titleText = _inRow(title, find.text(title));
        final subtitleText = _inRow(
          title,
          find.textContaining('reporting access'),
        );
        final status = _inRow(title, find.text('Not connected'));
        final budget = _inRow(title, find.byTooltip('Budget limits'));
        final alerts = _inRow(title, find.byTooltip('Alert thresholds'));

        expect(row, findsOneWidget);
        expect(budget, findsOneWidget);
        expect(alerts, findsOneWidget);
        _expectWordsStayIntact(tester, titleText, title);

        final rowRect = tester.getRect(row);
        final subtitleRect = tester.getRect(subtitleText);
        final statusRect = tester.getRect(status);
        final budgetRect = tester.getRect(budget);
        final alertsRect = tester.getRect(alerts);
        expect(statusRect.left, closeTo(subtitleRect.left, 0.1));
        expect(statusRect.top, greaterThan(subtitleRect.bottom));
        expect(budgetRect.top, greaterThanOrEqualTo(statusRect.bottom));
        expect(alertsRect.center.dy, closeTo(budgetRect.center.dy, 0.1));
        expect(alertsRect.left, greaterThanOrEqualTo(budgetRect.right));

        for (final action in [budget, alerts]) {
          final size = tester.getSize(action);
          final rect = tester.getRect(action);
          expect(size.width, greaterThanOrEqualTo(48));
          expect(size.height, greaterThanOrEqualTo(48));
          expect(rect.left, greaterThanOrEqualTo(rowRect.left));
          expect(rect.right, lessThanOrEqualTo(rowRect.right));
          expect(rect.bottom, lessThanOrEqualTo(rowRect.bottom));
        }
      }
    });

    testWidgets('keeps one compact action in the trailing slot', (
      tester,
    ) async {
      await _pumpProvidersAtSize(tester, const Size(320, 640));

      const title = 'Claude subscription';
      await tester.scrollUntilVisible(
        find.text(title),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();

      final row = find.widgetWithText(ListTile, title);
      final tile = tester.widget<ListTile>(row);
      final status = _inRow(title, find.text('Not connected'));
      final alerts = _inRow(title, find.byTooltip('Alert thresholds'));

      expect(tile.trailing, isA<Row>());
      expect((tile.trailing! as Row).children, hasLength(1));
      expect(
        tester.getRect(alerts).left,
        greaterThan(tester.getRect(status).right),
      );
    });

    testWidgets('keeps reporting status outside the controls at 411dp', (
      tester,
    ) async {
      await _pumpProvidersAtSize(tester, const Size(411, 640));

      const title = 'Organization reporting';
      final row = find.widgetWithText(ListTile, title);
      final status = _inRow(title, find.text('Not connected'));
      final budget = _inRow(title, find.byTooltip('Budget limits'));
      final alerts = _inRow(title, find.byTooltip('Alert thresholds'));
      final tile = tester.widget<ListTile>(row);

      expect(row, findsOneWidget);
      expect(budget, findsOneWidget);
      expect(alerts, findsOneWidget);
      expect(tile.subtitle, isA<Column>());
      expect(tile.trailing, isNull);

      final statusRect = tester.getRect(status);
      final budgetRect = tester.getRect(budget);
      final alertsRect = tester.getRect(alerts);
      expect(alertsRect.left, greaterThanOrEqualTo(budgetRect.right));
      expect(budgetRect.top, greaterThanOrEqualTo(statusRect.bottom));
      expect(budgetRect.center.dy, closeTo(alertsRect.center.dy, 0.1));
      expect(statusRect.right, lessThanOrEqualTo(tester.getRect(row).right));
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

      final row = find.widgetWithText(ListTile, 'Organization reporting');
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
    await tester.pumpAndSettle();

    expect(find.text('Cursor plan'), findsOneWidget);
    expect(find.text('Experimental · dashboard sign-in'), findsOneWidget);
    expect(find.text('Not connected'), findsWidgets);

    await tester.tap(find.byTooltip('About Cursor sign-in'));
    await tester.pumpAndSettle();

    expect(find.text('Cursor sign-in'), findsOneWidget);
    expect(find.text('Advanced paste'), findsOneWidget);
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

  testWidgets('budget limits are offered to platform connections only', (
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
  });

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
  of: find.widgetWithText(ListTile, title),
  matching: matching,
);

void _expectWordsStayIntact(WidgetTester tester, Finder text, String contents) {
  final paragraph = tester.renderObject<RenderParagraph>(text);
  for (final word in RegExp(r'\S+').allMatches(contents)) {
    final boxes = paragraph.getBoxesForSelection(
      TextSelection(baseOffset: word.start, extentOffset: word.end),
    );
    expect(
      boxes,
      hasLength(1),
      reason: '"${word.group(0)}" must not split across lines in "$contents"',
    );
  }
}

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
