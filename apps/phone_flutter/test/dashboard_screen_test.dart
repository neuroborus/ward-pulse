import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ward_pulse_phone/app/ward_pulse_theme.dart';
import 'package:ward_pulse_phone/dashboard/dashboard_models.dart';
import 'package:ward_pulse_phone/dashboard/dashboard_screen.dart';
import 'package:ward_pulse_phone/settings/consumption_display_preferences.dart';

void main() {
  testWidgets('shows allowances from every connected provider', (tester) async {
    final source = DashboardSnapshot.fromJsonString(
      File('../../fixtures/snapshots/dashboard_today.json').readAsStringSync(),
    );
    final openAi =
        source.primaryAccount!.toJson()
          ..['provider'] = 'openai'
          ..['allowances'] = <Object>[];
    final codex =
        source.primaryAccount!.toJson()
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
          ];
    final dashboard = source.toJson()..['accounts'] = [openAi, codex];

    await tester.pumpWidget(
      MaterialApp(
        theme: wardPulseLightTheme,
        home: Scaffold(
          body: DashboardScreen(
            snapshot: DashboardSnapshot.fromJson(dashboard),
            displayPreferences: const ConsumptionDisplayPreferences(
              purchased: true,
            ),
          ),
        ),
      ),
    );

    expect(find.text('Purchased credits'), findsOneWidget);
    expect(find.text('Unlimited'), findsOneWidget);
    expect(find.text('Today'), findsOneWidget);
    expect(find.text('Unknown'), findsNothing);

    await tester.scrollUntilVisible(
      find.text('OpenAI usage history'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('OpenAI usage history'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('OpenAI model usage'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('OpenAI model usage'), findsOneWidget);
  });

  testWidgets('hides plan Unknowns for OpenAI-only and offers Settings help', (
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
    var openedSettings = false;

    await tester.pumpWidget(
      MaterialApp(
        theme: wardPulseLightTheme,
        home: Scaffold(
          body: DashboardScreen(
            snapshot: DashboardSnapshot.fromJson(dashboard),
            onOpenSettings: () => openedSettings = true,
          ),
        ),
      ),
    );

    expect(find.text('Plan usage'), findsOneWidget);
    expect(find.text('Today'), findsOneWidget);
    expect(find.text('Unknown'), findsNothing);

    await tester.tap(find.byTooltip('Why is this hidden?'));
    await tester.pumpAndSettle();
    expect(
      find.text('Connect a Codex subscription in Settings to see plan limits.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Open Settings'));
    await tester.pumpAndSettle();
    expect(openedSettings, isTrue);
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
            snapshot: DashboardSnapshot.fromJson(dashboard),
          ),
        ),
      ),
    );

    expect(find.text('Weekly plan'), findsOneWidget);
    expect(find.text('Spend'), findsOneWidget);
    expect(find.text('Model usage'), findsNothing);
    expect(find.text('Unknown'), findsNothing);
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
            snapshot: DashboardSnapshot.fromJson(dashboard),
            displayPreferences: const ConsumptionDisplayPreferences(
              plan: true,
              purchased: true,
            ),
          ),
        ),
      ),
    );

    expect(find.text('Weekly plan'), findsOneWidget);
    expect(
      find.text(
        'Purchased usage: none reported. This account has no purchased credits right now.',
      ),
      findsOneWidget,
    );
  });
}
