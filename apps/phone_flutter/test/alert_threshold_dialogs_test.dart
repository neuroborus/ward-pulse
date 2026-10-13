import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ward_pulse_phone/providers/alert_threshold_dialogs.dart';
import 'package:ward_pulse_phone/providers/claude_account_service.dart';
import 'package:ward_pulse_phone/providers/codex_account_service.dart';
import 'package:ward_pulse_phone/providers/provider_connection.dart';
import 'package:ward_pulse_phone/providers/provider_credential_store.dart';
import 'package:ward_pulse_phone/providers/providers_screen.dart';
import 'package:ward_pulse_phone/settings/alert_threshold_preferences.dart';

const _original = ConnectionBudget(today: 1250, week: 2000, month: 3000);

void main() {
  testWidgets('invalid edits and Save never throw or return a budget', (
    tester,
  ) async {
    final outcome = await _openBudget(tester);
    for (final input in [
      'NaN',
      'Infinity',
      '-Infinity',
      '1e309',
      '1e2',
      'abc',
      '-1',
      '0',
      '0.00',
      '0.001',
      '12.345',
      '1,2.3',
      '92233720368547758.08',
      '999999999999999999999999999999999999999',
    ]) {
      await tester.enterText(_field(0), input);
      await tester.pump();
      expect(tester.takeException(), isNull, reason: input);
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: input);
      expect(
        find.byType(ConnectionBudgetDialog),
        findsOneWidget,
        reason: input,
      );
      expect(outcome.completed, isFalse, reason: input);
    }
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(outcome.completed, isTrue);
    expect(outcome.budget, isNull);
    expect(_original.today, 1250);
  });

  testWidgets('Save validates every period and correction preserves others', (
    tester,
  ) async {
    final outcome = await _openBudget(tester);
    await tester.enterText(_field(0), 'NaN');
    await tester.enterText(_field(1), '0');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Enter at least 0.01'), findsOneWidget);
    expect(outcome.completed, isFalse);

    await tester.enterText(_field(0), '1.50');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(outcome.completed, isFalse);
    expect(find.text('Enter at least 0.01'), findsOneWidget);

    await tester.enterText(_field(1), '20');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(outcome.completed, isTrue);
    expect(outcome.budget?.today, 150);
    expect(outcome.budget?.week, 2000);
    expect(outcome.budget?.month, 3000);
    expect(tester.takeException(), isNull);
  });

  for (final entry
      in {
        '25': 2500,
        '12.50': 1250,
        '12,50': 1250,
        '.50': 50,
        ',50': 50,
        '12.': 1200,
        '12,': 1200,
        '0.01': 1,
        '0,01': 1,
        ' 12.50 ': 1250,
      }.entries) {
    testWidgets('saves decimal ${entry.key} as exact minor units', (
      tester,
    ) async {
      final outcome = await _openBudget(tester);
      await tester.enterText(_field(0), entry.key);
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(outcome.budget?.today, entry.value);
      expect(outcome.budget?.week, 2000);
      expect(outcome.budget?.month, 3000);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('existing signed-64 cents format and round-trip exactly', (
    tester,
  ) async {
    final outcome = await _openBudget(
      tester,
      budget: const ConnectionBudget(
        today: 9223372036854775807,
        week: 9007199254740993,
      ),
    );
    expect(
      tester.widget<TextFormField>(_field(0)).controller!.text,
      '92233720368547758.07',
    );
    expect(
      tester.widget<TextFormField>(_field(1)).controller!.text,
      '90071992547409.93',
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(outcome.budget?.today, 9223372036854775807);
    expect(outcome.budget?.week, 9007199254740993);
    expect(outcome.budget?.month, isNull);
  });

  testWidgets('empty or whitespace clears only its chosen period', (
    tester,
  ) async {
    final outcome = await _openBudget(tester);
    await tester.enterText(_field(0), '   ');
    await tester.enterText(_field(2), '');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(outcome.budget?.today, isNull);
    expect(outcome.budget?.week, 2000);
    expect(outcome.budget?.month, isNull);
  });

  testWidgets('Cancel returns no change after valid edits', (tester) async {
    final outcome = await _openBudget(tester);
    await tester.enterText(_field(0), '99');
    await tester.enterText(_field(1), '');
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(outcome.completed, isTrue);
    expect(outcome.budget, isNull);
    expect(_original.today, 1250);
    expect(_original.week, 2000);
  });

  testWidgets('invalid Save and Cancel do not update connection preferences', (
    tester,
  ) async {
    var preferences = const AlertThresholdPreferences().withConnection(
      ProviderConnections.openAiPlatform,
      const ConnectionAlertThresholds(budget: _original),
    );
    var saves = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ProvidersScreen(
            credentialStore: const EmptyProviderCredentialStore(),
            codexAccountService: const EmptyCodexAccountService(),
            claudeAccountService: const EmptyClaudeAccountService(),
            onCredentialsChanged: () => fail('Unexpected credential mutation'),
            alertThresholds: preferences,
            onAlertThresholdsChanged: (update) async {
              saves += 1;
              preferences = update(preferences);
            },
            onRefresh: () async {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Platform reporting'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    final button = find.descendant(
      of: find.widgetWithText(ListTile, 'Platform reporting'),
      matching: find.byTooltip('Budget limits'),
    );
    await tester.ensureVisible(button);
    await tester.pumpAndSettle();
    await tester.tap(button);
    await tester.pumpAndSettle();
    await tester.enterText(_field(0), 'NaN');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(saves, 0);
    expect(
      preferences
          .forConnection(ProviderConnections.openAiPlatform)
          .budget
          .today,
      1250,
    );
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(saves, 0);
    expect(
      preferences.forConnection(ProviderConnections.openAiPlatform).budget.week,
      2000,
    );
    expect(tester.takeException(), isNull);
  });
}

Finder _field(int index) => find.byType(TextFormField).at(index);

Future<_BudgetOutcome> _openBudget(
  WidgetTester tester, {
  ConnectionBudget budget = _original,
}) async {
  final outcome = _BudgetOutcome();
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder:
              (context) => TextButton(
                onPressed: () async {
                  outcome.budget = await showDialog<ConnectionBudget>(
                    context: context,
                    builder:
                        (_) => ConnectionBudgetDialog(
                          connectionTitle: 'Platform reporting',
                          budget: budget,
                        ),
                  );
                  outcome.completed = true;
                },
                child: const Text('Open budget'),
              ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open budget'));
  await tester.pumpAndSettle();
  return outcome;
}

final class _BudgetOutcome {
  bool completed = false;
  ConnectionBudget? budget;
}
