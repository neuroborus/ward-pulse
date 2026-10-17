import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ward_pulse_phone/app/surface_order.dart';
import 'package:ward_pulse_phone/app/ward_pulse_theme.dart';
import 'package:ward_pulse_phone/charts/usage_history_chart.dart';
import 'package:ward_pulse_phone/dashboard/dashboard_models.dart';
import 'package:ward_pulse_phone/dashboard/dashboard_screen.dart';
import 'package:ward_pulse_phone/dashboard/status_pill.dart';
import 'package:ward_pulse_phone/providers/provider_connection.dart';

void main() {
  testWidgets(
    'empty configured feedback names every failure and repairs the exact connection',
    (tester) async {
      const outcomes = [
        ConnectionReportingOutcome(
          connection: ProviderConnections.openAiPlatform,
          category: ReportingOutcomeCategory.authenticationRejected,
          source: ReportingOutcomeSource.live,
        ),
        ConnectionReportingOutcome(
          connection: ProviderConnections.anthropicPlatform,
          category: ReportingOutcomeCategory.accessDenied,
          source: ReportingOutcomeSource.live,
        ),
        ConnectionReportingOutcome(
          connection: ProviderConnections.cursorPlatform,
          category: ReportingOutcomeCategory.transientFailure,
          source: ReportingOutcomeSource.live,
        ),
      ];
      ProviderConnectionId? repaired;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MediaQuery(
              data: const MediaQueryData(textScaler: TextScaler.linear(1.7)),
              child: DashboardScreen(
                snapshot: DashboardSnapshot.empty().withReportingOutcomes(
                  outcomes,
                ),
                onRefresh: () async {},
                onEditReportingKey: (id) => repaired = id,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Connect a provider'), findsNothing);
      for (final outcome in outcomes) {
        final text = find.textContaining(
          '${outcome.connectionLabel}: ${outcome.label}',
        );
        await tester.scrollUntilVisible(
          text,
          200,
          scrollable: find.byType(Scrollable).first,
        );
        expect(text, findsOneWidget);
      }
      expect(find.text('Edit key'), findsNWidgets(2));
      await tester.ensureVisible(find.text('Edit key').at(1));
      await tester.tap(find.text('Edit key').at(1));
      expect(repaired, ProviderConnections.anthropicPlatform);
      expect(tester.takeException(), isNull);
    },
  );

  test('shows a balance in full, grouped, to at most one decimal place', () {
    // The Dashboard does not compact: `62.5K` is what a glance shows
    // (`PHONE_DASHBOARD_DESIGN.md`, Balances).
    expect(
      const Quantity(value: '62479.294375', unit: 'credits').label,
      '62,479.3 credits',
    );
    expect(
      const Quantity(value: '500.0000000000', unit: 'credits').label,
      '500 credits',
    );
    expect(
      const Quantity(value: '12.50', unit: 'credits').label,
      '12.5 credits',
    );
    expect(formatQuantityValue('62479.294375'), '62,479.3');
    expect(formatQuantityValue('1000'), '1,000');
    expect(formatQuantityValue('320'), '320');
    expect(formatQuantityValue('0'), '0');
    expect(formatQuantityValue('12.50'), '12.5');
    expect(formatQuantityValue('12.5'), '12.5');
    expect(formatQuantityValue('100'), '100');
    // A balance that rounds away its own decimal loses it rather than
    // carrying a `.0`.
    expect(formatQuantityValue('0.04'), '0');
    expect(formatQuantityValue('999.96'), '1,000');
    // Text that is not a number keeps itself, and keeps it ungrouped.
    expect(formatQuantityValue('n/a.'), 'n/a.');
    expect(formatQuantityValue('unknown'), 'unknown');
    // A whole balance is separated, never reshaped: every digit of a value no
    // double could hold survives.
    expect(
      formatQuantityValue('123456789012345678901'),
      '123,456,789,012,345,678,901',
    );
  });

  test('a balance and a count are grouped by one rule', () {
    // The card above the Usage history reads a balance, the card below reads a
    // count; one screen, one way of writing a long number
    // (`PHONE_DASHBOARD_DESIGN.md`, Balances, grouping correction 2026-10-11).
    expect(formatCount(19213690951), '19,213,690,951');
    expect(formatCount(0), '0');
    expect(formatCount(7), '7');
    expect(formatCount(100), '100');
    expect(formatCount(1000), '1,000');
    expect(formatCount(999999), '999,999');
    expect(formatCount(1000000), '1,000,000');
    expect(formatCount(null), 'Unknown');
    // The sign is carried, not counted: grouping a negative once wrote a
    // separator straight after the minus.
    expect(formatCount(-1234), '-1,234');
    expect(formatCount(-123456), '-123,456');
    expect(formatQuantityValue('-1234.56'), '-1,234.6');
    // The two formatters agree on the same digits.
    expect(formatCount(62479), formatQuantityValue('62479'));
  });

  test('the app bar counts sections, not the problems inside them', () {
    final source = DashboardSnapshot.fromJsonString(
      File('../../fixtures/snapshots/dashboard_today.json').readAsStringSync(),
    );
    Map<String, dynamic> account(String provider, List<String> statuses) {
      return source.primaryAccount!.toJson()
        ..['accountId'] = '$provider-local'
        ..['provider'] = provider
        ..['status'] = 'ok'
        ..['allowances'] = [
          for (final (index, status) in statuses.indexed)
            {
              'id': '$provider-$index',
              'source': 'plan',
              'label': '$provider $index',
              'usedPercent': 50.0,
              'used': null,
              'limit': null,
              'remaining': null,
              'unlimited': false,
              'windowMinutes': null,
              'resetsAt': null,
              'status': status,
            },
        ]
        ..['buckets'] = <Object>[]
        ..['modelBreakdown'] = <Object>[];
    }

    final snapshot = DashboardSnapshot.fromJson(
      source.toJson()
        ..['accounts'] = [
          account('cursor', ['warning', 'rateLimited']),
          account('claude', ['ok']),
          account('codex', ['error']),
        ],
    );

    final problems = dashboardProblems(snapshot);

    // Three unhealthy cards live in two families, and a tap can only take the
    // reader to a family (PHONE_DASHBOARD_DESIGN.md).
    expect(problems.sections, 2);
    // The worst family, not the one that happened to arrive first: Codex is in
    // error while Cursor is only rate limited.
    expect(problems.first, 'openai');
    expect(problems.status, ProviderStatus.error);
  });

  testWidgets('aggregate spend card shows money and nothing to measure it', (
    tester,
  ) async {
    final state = BudgetState.fromJson({
      'period': 'today',
      'spent': {'minorUnits': 1240, 'currency': 'USD'},
      'limit': null,
      'remaining': null,
      'usedPercent': null,
      'projectedTotal': null,
      'status': 'unknown',
    });

    await tester.pumpWidget(
      MaterialApp(
        theme: wardPulseLightTheme,
        home: Scaffold(body: BudgetSummaryCard(title: 'Today', state: state)),
      ),
    );

    expect(find.text('USD 12.40'), findsOneWidget);
    // Limits are per connection, so the total has no ceiling: a bar or a pill
    // here could only say Unknown, next to a sum that is exactly known.
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(find.byType(StatusPill), findsNothing);
  });

  testWidgets('shows allowances from every connected provider', (tester) async {
    final source = DashboardSnapshot.fromJsonString(
      File('../../fixtures/snapshots/dashboard_today.json').readAsStringSync(),
    );
    final openAi =
        source.primaryAccount!.toJson()
          ..['accountId'] = 'openai-local'
          ..['provider'] = 'openai'
          ..['allowances'] = <Object>[];
    final codex =
        source.primaryAccount!.toJson()
          ..['accountId'] = 'codex-local'
          ..['provider'] = 'codex'
          ..['allowances'] = [
            {
              'id': 'codex-purchased-credits',
              'source': 'purchased',
              'label': 'Purchased credits',
              'usedPercent': null,
              'used': null,
              'limit': null,
              'remaining': null,
              'unlimited': true,
              'windowMinutes': null,
              'resetsAt': null,
              'status': 'ok',
            },
          ]
          ..['buckets'] = <Object>[]
          ..['modelBreakdown'] = <Object>[];
    final dashboard = source.toJson()..['accounts'] = [openAi, codex];

    await tester.pumpWidget(
      MaterialApp(
        theme: wardPulseLightTheme,
        home: Scaffold(
          body: DashboardScreen(
            onRefresh: _noRefresh,
            snapshot: DashboardSnapshot.fromJson(dashboard),
          ),
        ),
      ),
    );

    expect(find.text('Codex'), findsOneWidget);
    expect(find.text('Purchased credits'), findsOneWidget);
    expect(find.text('Unlimited'), findsOneWidget);
    expect(find.text('Unknown'), findsNothing);
    // Healthy families say nothing at all.
    expect(find.byType(Badge), findsNothing);

    expect(find.text('OpenAI'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Usage history'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Usage history'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Model usage'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Model usage'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('Platform spend'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Today'), findsOneWidget);
  });

  testWidgets('shows Cursor Models and Other Models plan pools', (
    tester,
  ) async {
    final source = DashboardSnapshot.fromJsonString(
      File('../../fixtures/snapshots/dashboard_today.json').readAsStringSync(),
    );
    final cursor =
        source.primaryAccount!.toJson()
          ..['accountId'] = 'cursor-local'
          ..['provider'] = 'cursor'
          ..['allowances'] = [
            {
              'id': 'cursor-plan-models',
              'source': 'plan',
              'label': 'Cursor Models',
              'usedPercent': 47.0,
              'used': null,
              'limit': null,
              'remaining': null,
              'unlimited': false,
              'windowMinutes': null,
              'resetsAt': null,
              'status': 'ok',
            },
            {
              'id': 'cursor-plan-other',
              'source': 'plan',
              'label': 'Other Models',
              'usedPercent': 100.0,
              'used': null,
              'limit': null,
              'remaining': null,
              'unlimited': false,
              'windowMinutes': null,
              'resetsAt': null,
              'status': 'rateLimited',
            },
          ]
          ..['buckets'] = <Object>[]
          ..['modelBreakdown'] = <Object>[];
    final dashboard = source.toJson()..['accounts'] = [cursor];

    await tester.pumpWidget(
      MaterialApp(
        theme: wardPulseLightTheme,
        home: Scaffold(
          body: DashboardScreen(
            onRefresh: _noRefresh,
            snapshot: DashboardSnapshot.fromJson(dashboard),
          ),
        ),
      ),
    );

    expect(find.text('Cursor Models'), findsOneWidget);
    expect(find.text('Other Models'), findsOneWidget);
    expect(find.text('53% left'), findsOneWidget);
    expect(find.text('0% left'), findsOneWidget);
    expect(find.byIcon(Icons.speed), findsOneWidget);
    // A card marks a deviation, never health, and the header says how many
    // deviate below it (PHONE_DASHBOARD_DESIGN.md).
    expect(_pillsInCardOf(find.text('Cursor Models')), findsNothing);
    expect(_pillsInCardOf(find.text('Other Models')), findsOneWidget);
    expect(find.widgetWithText(Badge, '1'), findsOneWidget);
  });

  testWidgets('always shows platform spend when budgets are available', (
    tester,
  ) async {
    final source = DashboardSnapshot.fromJsonString(
      File('../../fixtures/snapshots/dashboard_today.json').readAsStringSync(),
    );
    final openAi =
        (source.toJson()['accounts'] as List).first as Map<String, dynamic>;
    openAi['provider'] = 'openai';
    final dashboard = source.toJson()..['accounts'] = [openAi];

    await tester.pumpWidget(
      MaterialApp(
        theme: wardPulseLightTheme,
        home: Scaffold(
          body: DashboardScreen(
            onRefresh: _noRefresh,
            snapshot: DashboardSnapshot.fromJson(dashboard),
          ),
        ),
      ),
    );

    await tester.scrollUntilVisible(
      find.text('Platform spend'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Platform spend'), findsOneWidget);
    expect(find.text('Today'), findsWidgets);
  });

  testWidgets('hides plan Unknowns for OpenAI-only and offers Providers help', (
    tester,
  ) async {
    final source = DashboardSnapshot.fromJsonString(
      File('../../fixtures/snapshots/dashboard_today.json').readAsStringSync(),
    );
    final openAi =
        source.primaryAccount!.toJson()
          ..['provider'] = 'openai'
          ..['allowances'] = <Object>[];
    final dashboard = source.toJson()..['accounts'] = [openAi];
    var openedProviders = false;

    await tester.pumpWidget(
      MaterialApp(
        theme: wardPulseLightTheme,
        home: Scaffold(
          body: DashboardScreen(
            onRefresh: _noRefresh,
            snapshot: DashboardSnapshot.fromJson(dashboard),
            onOpenProviders: () => openedProviders = true,
          ),
        ),
      ),
    );

    expect(find.text('Plan usage'), findsOneWidget);
    expect(find.text('Unknown'), findsNothing);

    await tester.tap(find.byTooltip('Why is this hidden?'));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Connect a Codex subscription on the Providers tab to see plan limits.',
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Open Providers'));
    await tester.pumpAndSettle();
    expect(openedProviders, isTrue);

    await tester.scrollUntilVisible(
      find.text('Platform spend'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Today'), findsOneWidget);
  });

  testWidgets('hides spend Unknowns for Codex-only and offers Settings help', (
    tester,
  ) async {
    final source = DashboardSnapshot.fromJsonString(
      File('../../fixtures/snapshots/dashboard_today.json').readAsStringSync(),
    );
    final codex =
        source.primaryAccount!.toJson()
          ..['provider'] = 'codex'
          ..['allowances'] = [
            {
              'id': 'codex-weekly',
              'source': 'plan',
              'label': 'Weekly plan',
              'usedPercent': 40,
              'used': null,
              'limit': null,
              'remaining': null,
              'unlimited': false,
              'windowMinutes': 10080,
              'resetsAt': '2026-07-29T07:14:22Z',
              'status': 'ok',
            },
          ]
          ..['modelBreakdown'] = <Object>[];
    final dashboard = source.toJson()..['accounts'] = [codex];

    await tester.pumpWidget(
      MaterialApp(
        theme: wardPulseLightTheme,
        home: Scaffold(
          body: DashboardScreen(
            onRefresh: _noRefresh,
            snapshot: DashboardSnapshot.fromJson(dashboard),
          ),
        ),
      ),
    );

    expect(find.text('Codex'), findsOneWidget);
    expect(find.text('Weekly plan'), findsOneWidget);
    expect(find.text('60% left'), findsOneWidget);
    expect(find.text('Model usage'), findsNothing);
    expect(find.text('Unknown'), findsNothing);

    await tester.scrollUntilVisible(
      find.text('Spend'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Spend'), findsOneWidget);
  });

  testWidgets('groups plan cards under each provider without summing', (
    tester,
  ) async {
    final source = DashboardSnapshot.fromJsonString(
      File('../../fixtures/snapshots/dashboard_today.json').readAsStringSync(),
    );
    Map<String, dynamic> planAccount(String provider, int usedPercent) {
      return source.primaryAccount!.toJson()
        ..['accountId'] = '$provider-local'
        ..['provider'] = provider
        ..['allowances'] = [
          {
            'id': '$provider-weekly',
            'source': 'plan',
            'label': 'Weekly plan',
            'usedPercent': usedPercent,
            'used': null,
            'limit': null,
            'remaining': null,
            'unlimited': false,
            'windowMinutes': 10080,
            'resetsAt': null,
            'status': 'ok',
          },
        ]
        ..['buckets'] = <Object>[]
        ..['modelBreakdown'] = <Object>[];
    }

    final dashboard =
        source.toJson()
          ..['accounts'] = [
            planAccount('codex', 40),
            planAccount('claude', 70),
          ];

    await tester.pumpWidget(
      MaterialApp(
        theme: wardPulseLightTheme,
        home: Scaffold(
          body: DashboardScreen(
            onRefresh: _noRefresh,
            snapshot: DashboardSnapshot.fromJson(dashboard),
          ),
        ),
      ),
    );

    expect(find.text('Codex'), findsOneWidget);
    expect(find.text('Claude'), findsOneWidget);
    expect(find.text('Weekly plan'), findsNWidgets(2));
    expect(find.text('60% left'), findsOneWidget);
    expect(find.text('30% left'), findsOneWidget);
  });

  testWidgets('nests usage history under the owning provider plaque', (
    tester,
  ) async {
    final source = DashboardSnapshot.fromJsonString(
      File('../../fixtures/snapshots/dashboard_today.json').readAsStringSync(),
    );
    final claude =
        source.primaryAccount!.toJson()
          ..['accountId'] = 'claude-local'
          ..['provider'] = 'claude'
          ..['allowances'] = [
            {
              'id': 'claude-five-hour',
              'source': 'plan',
              'label': '5-hour session',
              'usedPercent': 0,
              'used': null,
              'limit': null,
              'remaining': null,
              'unlimited': false,
              'windowMinutes': 300,
              'resetsAt': null,
              'status': 'ok',
            },
          ]
          ..['buckets'] = <Object>[]
          ..['modelBreakdown'] = <Object>[];
    final codex =
        source.primaryAccount!.toJson()
          ..['accountId'] = 'codex-local'
          ..['provider'] = 'codex'
          ..['allowances'] = <Object>[]
          ..['modelBreakdown'] = <Object>[];
    // Keep fixture buckets on Codex only.
    final dashboard = source.toJson()..['accounts'] = [claude, codex];

    await tester.pumpWidget(
      MaterialApp(
        theme: wardPulseLightTheme,
        home: Scaffold(
          body: DashboardScreen(
            onRefresh: _noRefresh,
            snapshot: DashboardSnapshot.fromJson(dashboard),
          ),
        ),
      ),
    );

    expect(find.text('Claude'), findsOneWidget);
    expect(find.text('Codex'), findsOneWidget);
    expect(find.text('Usage history'), findsOneWidget);
    expect(find.text('Codex usage history'), findsNothing);
    expect(find.text('Claude usage history'), findsNothing);

    final claudeHeader = tester.getTopLeft(find.text('Claude'));
    final codexHeader = tester.getTopLeft(find.text('Codex'));
    final historyTitle = tester.getTopLeft(find.text('Usage history'));
    expect(claudeHeader.dy, lessThan(codexHeader.dy));
    expect(codexHeader.dy, lessThan(historyTitle.dy));
  });

  testWidgets('keeps Cursor plan and platform under one provider plaque', (
    tester,
  ) async {
    final source = DashboardSnapshot.fromJsonString(
      File('../../fixtures/snapshots/dashboard_today.json').readAsStringSync(),
    );
    final plan =
        source.primaryAccount!.toJson()
          ..['accountId'] = 'cursor-plan'
          ..['provider'] = 'cursor'
          ..['status'] = 'ok'
          ..['allowances'] = [
            {
              'id': 'cursor-plan-models',
              'source': 'plan',
              'label': 'Cursor Models',
              'usedPercent': 47,
              'used': null,
              'limit': null,
              'remaining': null,
              'unlimited': false,
              'windowMinutes': null,
              'resetsAt': null,
              'status': 'ok',
            },
          ]
          ..['buckets'] = <Object>[]
          ..['modelBreakdown'] = <Object>[];
    final platform =
        source.primaryAccount!.toJson()
          ..['accountId'] = 'cursor-platform'
          ..['provider'] = 'cursor'
          ..['status'] = 'warning'
          ..['allowances'] = <Object>[]
          ..['modelBreakdown'] = <Object>[];
    final dashboard = source.toJson()..['accounts'] = [plan, platform];

    await tester.pumpWidget(
      MaterialApp(
        theme: wardPulseLightTheme,
        home: Scaffold(
          body: DashboardScreen(
            onRefresh: _noRefresh,
            snapshot: DashboardSnapshot.fromJson(dashboard),
          ),
        ),
      ),
    );

    expect(find.text('Cursor'), findsOneWidget);
    expect(find.text('Cursor Models'), findsOneWidget);
    expect(find.text('Usage history'), findsOneWidget);
    expect(find.byTooltip('Warning'), findsOneWidget);

    final cursorHeader = tester.getTopLeft(find.text('Cursor'));
    final historyTitle = tester.getTopLeft(find.text('Usage history'));
    expect(cursorHeader.dy, lessThan(historyTitle.dy));
  });

  testWidgets('explains missing purchased usage when enabled', (tester) async {
    final source = DashboardSnapshot.fromJsonString(
      File('../../fixtures/snapshots/dashboard_today.json').readAsStringSync(),
    );
    final codex =
        source.primaryAccount!.toJson()
          ..['provider'] = 'codex'
          ..['allowances'] = [
            {
              'id': 'codex-weekly',
              'source': 'plan',
              'label': 'Weekly plan',
              'usedPercent': 100,
              'used': null,
              'limit': null,
              'remaining': null,
              'unlimited': false,
              'windowMinutes': 10080,
              'resetsAt': '2026-07-29T07:14:22Z',
              'status': 'rate_limited',
            },
          ];
    final dashboard = source.toJson()..['accounts'] = [codex];

    await tester.pumpWidget(
      MaterialApp(
        theme: wardPulseLightTheme,
        home: Scaffold(
          body: DashboardScreen(
            onRefresh: _noRefresh,
            snapshot: DashboardSnapshot.fromJson(dashboard),
          ),
        ),
      ),
    );

    expect(find.text('Codex'), findsOneWidget);
    expect(find.text('Weekly plan'), findsOneWidget);
    expect(
      find.text(
        'Purchased usage: none reported. This account has no purchased credits right now.',
      ),
      findsOneWidget,
    );
  });

  group('the declared card order', () {
    final source = DashboardSnapshot.fromJsonString(
      File('../../fixtures/snapshots/dashboard_today.json').readAsStringSync(),
    );

    Map<String, dynamic> account(
      String provider, {
      String status = 'ok',
      int spent = 0,
      String currency = 'USD',
    }) {
      return source.primaryAccount!.toJson()
        ..['accountId'] = '$provider-local'
        ..['provider'] = provider
        ..['status'] = status
        ..['allowances'] = [
          {
            'id': '$provider-plan',
            'source': 'plan',
            'label': '$provider plan',
            'usedPercent': 50.0,
            'used': null,
            'limit': null,
            'remaining': null,
            'unlimited': false,
            'windowMinutes': null,
            'resetsAt': null,
            'status': status,
          },
        ]
        ..['buckets'] = <Object>[]
        ..['modelBreakdown'] = <Object>[]
        ..['month'] = {
          'period': 'month',
          'spent': {'minorUnits': spent, 'currency': currency},
          'limit': null,
          'remaining': null,
          'usedPercent': null,
          'projectedTotal': null,
          'status': status,
        };
    }

    DashboardSnapshot snapshotOf(List<Map<String, dynamic>> accounts) {
      return DashboardSnapshot.fromJson(
        source.toJson()..['accounts'] = accounts,
      );
    }

    /// Provider plaques top to bottom.
    List<String> renderedOrder(WidgetTester tester) {
      final headers =
          [
              'OpenAI',
              'Anthropic',
              'Cursor',
            ].where((label) => find.text(label).evaluate().isNotEmpty).toList()
            ..sort(
              (left, right) => tester
                  .getTopLeft(find.text(left))
                  .dy
                  .compareTo(tester.getTopLeft(find.text(right)).dy),
            );
      return headers;
    }

    Future<void> show(
      WidgetTester tester,
      DashboardSnapshot snapshot, {
      FrozenOrder? order,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: wardPulseLightTheme,
          home: Scaffold(
            body: DashboardScreen(
              snapshot: snapshot,
              order: order,
              onRefresh: _noRefresh,
            ),
          ),
        ),
      );
    }

    testWidgets('families retain separate connection histories and models', (
      tester,
    ) async {
      final connections = providerConnectionCatalog();
      final providers = [
        'codex',
        'openai',
        'claude',
        'claude',
        'cursor',
        'cursor',
      ];
      final accounts = [
        for (final (index, connection) in connections.indexed)
          account(providers[index])
            ..['accountId'] = 'source-$index'
            ..['connection'] = connection.id.storageKey
            ..['allowances'] = <Object>[]
            ..['buckets'] = [
              {
                'startAt': '2026-10-${10 + index}T00:00:00Z',
                'endAt': '2026-10-${11 + index}T00:00:00Z',
                'requests': 11 + index,
              },
            ]
            ..['modelBreakdown'] = [
              {'model': 'model-$index', 'requests': 101 + index},
            ],
      ];
      await show(tester, snapshotOf(accounts.reversed.toList()));

      for (final family in ProviderFamily.values) {
        expect(find.text(providerFamilyLabel(family)), findsOneWidget);
      }
      expect(find.byType(Badge), findsNothing);
      final charts = tester.widgetList<UsageHistoryChart>(
        find.byType(UsageHistoryChart),
      );
      expect(charts, hasLength(6));
      // No cross-source buckets, even when both accounts have the same kind.
      expect(charts.map((chart) => chart.buckets.single.requests), [
        13,
        14,
        15,
        16,
        11,
        12,
      ]);
      for (final (index, connection) in connections.indexed) {
        final caption = find.text(connection.title);
        final model = find.text('model-$index');
        final history = find.text('${11 + index} requests');
        expect(caption, findsOneWidget);
        expect(model, findsOneWidget);
        expect(history, findsOneWidget);
        final panel = find.ancestor(of: model, matching: find.byType(Card));
        expect(
          find.descendant(of: panel, matching: find.textContaining('model-')),
          findsOneWidget,
        );
        expect(
          tester.getTopLeft(caption).dy,
          lessThan(tester.getTopLeft(history).dy),
        );
        expect(
          tester.getTopLeft(history).dy,
          lessThan(tester.getTopLeft(model).dy),
        );
        expect(find.text('source-$index'), findsNothing);
      }
    });

    testWidgets('keeps meters and history separate within a connection', (
      tester,
    ) async {
      final accounts = [account('claude'), account('claude')];
      for (final (index, data) in accounts.indexed) {
        data['accountId'] = 'source-$index';
        data['connection'] = ProviderConnections.claudePlan.storageKey;
        final meter =
            (data['allowances'] as List).single as Map<String, dynamic>;
        meter['source'] = 'purchased';
        meter['usedPercent'] = null;
        meter['remaining'] = {
          'value': index == 0 ? '1234.56' : '50',
          'unit': index == 0 ? 'credits' : 'tokens',
        };
        data['buckets'] = [
          {
            'startAt': '2026-10-${10 + index}T00:00:00Z',
            'endAt': '2026-10-${11 + index}T00:00:00Z',
            'requests': 21 + index,
          },
        ];
      }
      await show(tester, snapshotOf(accounts.reversed.toList()));

      expect(find.text('Anthropic'), findsOneWidget);
      final balances = ['1,234.6 credits', '50 tokens'];
      for (final (index, balance) in balances.indexed) {
        final caption = find.text('Claude subscription · Source ${index + 1}');
        final history = find.text('${21 + index} requests');
        expect(caption, findsOneWidget);
        expect(find.text(balance), findsOneWidget);
        expect(history, findsOneWidget);
        expect(find.text('source-$index'), findsNothing);
        expect(
          tester.getTopLeft(caption).dy,
          lessThan(tester.getTopLeft(find.text(balance)).dy),
        );
        expect(
          tester.getTopLeft(find.text(balance)).dy,
          lessThan(tester.getTopLeft(history).dy),
        );
      }
      expect(
        tester.getTopLeft(find.text('21 requests')).dy,
        lessThan(
          tester.getTopLeft(find.text('Claude subscription · Source 2')).dy,
        ),
      );
      expect(find.byType(UsageHistoryChart), findsNWidgets(2));
      expect(find.byType(Badge), findsNothing);
    });

    testWidgets('retains fallback accounts and omits empty histories', (
      tester,
    ) async {
      final mock = account('mock', status: 'stale');
      final other =
          account('other')
            ..['buckets'] = source.primaryAccount!.toJson()['buckets']
            ..['modelBreakdown'] = [
              {'model': 'fallback-model', 'requests': 7},
            ];
      final empty = account('cursor')..['allowances'] = <Object>[];
      await show(tester, snapshotOf([account('codex'), mock, other, empty]));

      expect(find.text('Mock'), findsOneWidget);
      expect(find.text('other'), findsOneWidget);
      expect(find.text('mock plan'), findsOneWidget);
      expect(find.text('fallback-model'), findsOneWidget);
      expect(find.text('Cursor'), findsOneWidget);
      expect(find.byType(UsageHistoryChart), findsOneWidget);
      expect(dashboardProblems(snapshotOf([mock, other])).first, 'mock');
    });

    testWidgets('counts a cardless failed sibling and keeps the valid source', (
      tester,
    ) async {
      final plan =
          account('codex', status: 'warning')
            ..['connection'] = ProviderConnections.codexPlan.storageKey
            ..['buckets'] = source.primaryAccount!.toJson()['buckets'];
      final cards = plan['allowances'] as List;
      cards.add({...cards.single as Map<String, dynamic>, 'id': 'second-card'});
      final failed =
          account('openai', status: 'error')
            ..['connection'] = ProviderConnections.openAiPlatform.storageKey
            ..['allowances'] = <Object>[];
      const failure = ConnectionReportingOutcome(
        connection: ProviderConnections.openAiPlatform,
        category: ReportingOutcomeCategory.accessDenied,
        source: ReportingOutcomeSource.live,
      );
      final snapshot = snapshotOf([
        failed,
        plan,
      ]).withReportingOutcomes([failure]);
      ProviderConnectionId? repaired;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DashboardScreen(
              snapshot: snapshot,
              onRefresh: _noRefresh,
              onEditReportingKey: (id) => repaired = id,
            ),
          ),
        ),
      );
      expect(dashboardProblems(snapshot), (
        sections: 1,
        status: ProviderStatus.error,
        first: 'openai',
      ));
      expect(find.byType(Badge), findsOneWidget);
      expect(
        find.descendant(of: find.byType(Badge), matching: find.text('3')),
        findsOneWidget,
      );
      expect(find.byType(StatusPill), findsNWidgets(2));
      expect(find.byType(UsageHistoryChart), findsOneWidget);
      expect(
        find.textContaining('${failure.connectionLabel}: Access denied'),
        findsOneWidget,
      );
      await tester.tap(find.text('Edit key'));
      expect(repaired, ProviderConnections.openAiPlatform);

      // The failed account remains reachable even without any sibling data.
      await show(tester, snapshotOf([failed]).withReportingOutcomes([failure]));
      expect(find.text('OpenAI'), findsOneWidget);
      expect(find.byType(UsageHistoryChart), findsNothing);
      expect(dashboardProblems(snapshotOf([failed])).sections, 1);
    });

    for (final width in [360.0, 411.0]) {
      for (final textScale in [1.0, 1.3]) {
        testWidgets(
          'both aliases fully reveal a tall OpenAI heading at $width/$textScale',
          (tester) async {
            tester.view.devicePixelRatio = 1;
            tester.view.physicalSize = Size(width, 800);
            addTearDown(tester.view.resetDevicePixelRatio);
            addTearDown(tester.view.resetPhysicalSize);

            final plan =
                account('codex', status: 'warning')
                  ..['connection'] = ProviderConnections.codexPlan.storageKey
                  ..['buckets'] = source.primaryAccount!.toJson()['buckets'];
            final cards = plan['allowances'] as List;
            cards.add({
              ...cards.single as Map<String, dynamic>,
              'id': 'codex-weekly',
              'label': 'Weekly plan',
            });
            final platform =
                account('openai')
                  ..['connection'] =
                      ProviderConnections.openAiPlatform.storageKey
                  ..['allowances'] = <Object>[]
                  ..['buckets'] = source.primaryAccount!.toJson()['buckets']
                  ..['modelBreakdown'] = [
                    {'model': 'platform-model', 'requests': 7},
                  ];
            final snapshot = snapshotOf([
              account('claude', status: 'error')
                ..['buckets'] = source.primaryAccount!.toJson()['buckets'],
              account('cursor', status: 'error')
                ..['buckets'] = source.primaryAccount!.toJson()['buckets'],
              plan,
              platform,
            ]);
            var token = 0;
            Widget dashboard(({String provider, int token})? request) {
              return MaterialApp(
                theme: wardPulseLightTheme,
                builder:
                    (context, child) => MediaQuery(
                      data: MediaQuery.of(
                        context,
                      ).copyWith(textScaler: TextScaler.linear(textScale)),
                      child: child!,
                    ),
                home: Scaffold(
                  appBar: AppBar(title: const Text('Dashboard')),
                  body: DashboardScreen(
                    snapshot: snapshot,
                    onRefresh: _noRefresh,
                    reveal: request,
                  ),
                ),
              );
            }

            Future<void> reveal(String alias) async {
              await tester.pumpWidget(
                dashboard((provider: alias, token: ++token)),
              );
              // The shell clears the request after its first frame, before
              // the next layout can finish recovering an unmounted family.
              await tester.pumpWidget(dashboard(null));
              await tester.pumpAndSettle();
              final heading = find.text('OpenAI');
              final header =
                  find.ancestor(of: heading, matching: find.byType(Row)).first;
              final badge = find.descendant(
                of: header,
                matching: find.byType(Badge),
              );
              expect(badge, findsOneWidget);
              final viewport = tester.getRect(find.byType(Scrollable).first);
              expect(
                viewport.top,
                greaterThanOrEqualTo(
                  tester.getBottomLeft(find.byType(AppBar)).dy,
                ),
              );
              // The target really exceeds the viewport, including both sources.
              expect(
                tester.getBottomRight(find.text('platform-model')).dy -
                    tester.getTopLeft(heading).dy,
                greaterThan(viewport.height),
              );
              final visibleBounds = viewport.inflate(precisionErrorTolerance);
              for (final part in [header, heading, badge]) {
                final bounds = tester.getRect(part);
                expect(bounds.left, greaterThanOrEqualTo(visibleBounds.left));
                expect(bounds.top, greaterThanOrEqualTo(visibleBounds.top));
                expect(bounds.right, lessThanOrEqualTo(visibleBounds.right));
                expect(bounds.bottom, lessThanOrEqualTo(visibleBounds.bottom));
              }
            }

            // Either alias must also work on fresh construction (tab arrival).
            for (final initialAlias in ['codex', 'openai']) {
              await tester.pumpWidget(const SizedBox.shrink());
              final otherAlias = initialAlias == 'codex' ? 'openai' : 'codex';
              await reveal(initialAlias);
              for (final (index, alias)
                  in [
                    initialAlias,
                    initialAlias,
                    otherAlias,
                    otherAlias,
                  ].indexed) {
                final scroll = tester.state<ScrollableState>(
                  find.byType(Scrollable).first,
                );
                scroll.position.jumpTo(
                  index.isEven ? 0 : scroll.position.maxScrollExtent,
                );
                await tester.pump();
                final viewport = tester.getRect(find.byType(Scrollable).first);
                final heading = find.text('OpenAI');
                // A lazy child can be unmounted; only mounted headings have
                // bounds to compare with the unobscured viewport.
                if (heading.evaluate().isNotEmpty) {
                  final bounds = tester.getRect(heading);
                  expect(
                    bounds.bottom <= viewport.top ||
                        bounds.top >= viewport.bottom,
                    isTrue,
                  );
                }
                await reveal(alias);
              }
            }
          },
        );
      }
    }

    testWidgets(
      'family spend is ordering-only and mixed currencies do not sum',
      (tester) async {
        await show(
          tester,
          snapshotOf([
            account('codex', spent: 60),
            account('openai', spent: 60),
            account('claude', spent: 100),
          ]),
        );
        expect(renderedOrder(tester), ['OpenAI', 'Anthropic']);
        await show(
          tester,
          snapshotOf([
            account('codex', spent: 600, currency: 'EUR'),
            account('openai', spent: 600),
            account('claude', spent: 100),
          ]),
        );
        expect(renderedOrder(tester), ['Anthropic', 'OpenAI']);
      },
    );

    testWidgets('needs action first, then spend, then name', (tester) async {
      await show(
        tester,
        snapshotOf([
          account('claude', spent: 100),
          account('codex', spent: 900),
          account('cursor', status: 'error'),
        ]),
      );

      // Cursor is broken and comes first though it spent nothing; Codex
      // outspends Claude and takes the rest.
      expect(renderedOrder(tester), ['Cursor', 'OpenAI', 'Anthropic']);
    });

    testWidgets('equal keys fall back to the provider, not the label', (
      tester,
    ) async {
      await show(
        tester,
        snapshotOf([account('cursor'), account('codex'), account('claude')]),
      );

      expect(renderedOrder(tester), ['Anthropic', 'Cursor', 'OpenAI']);
    });

    testWidgets('the same accounts in another order render the same screen', (
      tester,
    ) async {
      final accounts = [
        account('claude', spent: 100),
        account('codex', spent: 900),
        account('cursor', status: 'error'),
      ];

      await show(tester, snapshotOf(accounts));
      final first = renderedOrder(tester);

      await show(tester, snapshotOf(accounts.reversed.toList()));

      expect(renderedOrder(tester), first);
    });

    testWidgets('a poll that only moves spend leaves the cards alone', (
      tester,
    ) async {
      final order = FrozenOrder();
      await show(
        tester,
        snapshotOf([
          account('claude', spent: 100),
          account('codex', spent: 900),
        ]),
        order: order,
      );
      expect(renderedOrder(tester), ['OpenAI', 'Anthropic']);

      // Claude overtakes Codex on spend; the reader's list must not swap under
      // the finger, because no provider changed state.
      await show(
        tester,
        snapshotOf([
          account('claude', spent: 5000),
          account('codex', spent: 900),
        ]),
        order: order,
      );

      expect(renderedOrder(tester), ['OpenAI', 'Anthropic']);
    });

    testWidgets('a family falling into error climbs the same poll', (
      tester,
    ) async {
      final order = FrozenOrder();
      await show(
        tester,
        snapshotOf([
          account('claude', spent: 100),
          account('codex', spent: 900),
        ]),
        order: order,
      );
      expect(renderedOrder(tester), ['OpenAI', 'Anthropic']);

      // The same two families, so nothing joined or left — but one of them now
      // needs the reader, and a held order must not sit on that.
      await show(
        tester,
        snapshotOf([
          account('claude', status: 'error', spent: 100),
          account('codex', spent: 900),
        ]),
        order: order,
      );

      expect(renderedOrder(tester), ['Anthropic', 'OpenAI']);
    });

    testWidgets('a family joining reranks, and the badge follows the cards', (
      tester,
    ) async {
      final order = FrozenOrder();
      await show(
        tester,
        snapshotOf([
          account('claude', spent: 100),
          account('codex', spent: 900),
        ]),
        order: order,
      );

      final withCursor = snapshotOf([
        account('claude', spent: 100),
        account('codex', spent: 900),
        account('cursor', status: 'error'),
      ]);
      await show(tester, withCursor, order: order);

      expect(renderedOrder(tester), ['Cursor', 'OpenAI', 'Anthropic']);
      // What the app-bar mark scrolls to is read off the same order, so it
      // cannot point past a card sitting higher up.
      expect(dashboardProblems(withCursor, order).first, 'cursor');
    });
  });
}

/// Status pills inside the card that carries [label], so a leaf assertion stays
/// a leaf assertion once family and app-bar rollups change around it.
Finder _pillsInCardOf(Finder label) {
  return find.descendant(
    of: find.ancestor(of: label, matching: find.byType(Card)),
    matching: find.byType(StatusPill),
  );
}

/// These tests drive the screen, not the reload behind the pull.
Future<void> _noRefresh() async {}
