import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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
    expect(find.text('OpenAI usage history'), findsOneWidget);
    expect(find.text('OpenAI model usage'), findsOneWidget);
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
