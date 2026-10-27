import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ward_pulse_phone/dashboard/dashboard_models.dart';
import 'package:ward_pulse_phone/providers/alert_threshold_dialogs.dart';
import 'package:ward_pulse_phone/providers/claude_account_service.dart';
import 'package:ward_pulse_phone/providers/codex_account_service.dart';
import 'package:ward_pulse_phone/providers/provider_connection.dart';
import 'package:ward_pulse_phone/providers/provider_connection_row.dart';
import 'package:ward_pulse_phone/providers/provider_credential_store.dart';
import 'package:ward_pulse_phone/providers/providers_screen.dart';
import 'package:ward_pulse_phone/settings/alert_threshold_preferences.dart';
import 'package:ward_pulse_phone/settings/alert_percent_threshold_editor.dart';

const _original = ConnectionBudget(today: 1250, week: 2000, month: 3000);

void main() {
  for (final category in [
    'Plan',
    'Window',
    'Purchased',
    'Today',
    'Week',
    'Month',
  ]) {
    testWidgets('$category custom and endpoint rules save, reload and reopen', (
      tester,
    ) async {
      final connection =
          ['Today', 'Week', 'Month'].contains(category)
              ? ProviderConnections.anthropicPlatform
              : ProviderConnections.codexPlan;
      var rules = const ConnectionAlertThresholds(budget: _original);
      for (final remaining in [17, 0, 100]) {
        final outcome = await _openAlerts(
          tester,
          rules: rules,
          connection: connection,
          windows: [_window('window', 'Window')],
        );
        await _choose(tester, category, 'Custom % left');
        final field = _percentField(category);
        await tester.ensureVisible(field);
        await tester.enterText(field, '$remaining');
        await tester.tap(find.text('Save'));
        await tester.pumpAndSettle();
        expect(outcome.completed, isTrue);
        rules = ConnectionAlertThresholds.fromJson(outcome.rules!.toJson());
        final reopened = await _openAlerts(
          tester,
          rules: rules,
          connection: connection,
          windows: [_window('window', 'Window')],
        );
        final editor = tester.widget<AlertPercentThresholdEditor>(
          _editor(category),
        );
        expect(editor.value.at, 100 - remaining);
        expect(editor.usePlanDefault, isFalse);
        if (remaining == 17) {
          expect(
            tester
                .widget<TextFormField>(_percentField(category))
                .controller!
                .text,
            '17',
          );
        } else {
          expect(
            tester.widget<DropdownButton<int?>>(_dropdown(category)).value,
            remaining,
          );
        }
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
        expect(reopened.rules, isNull);
      }
    });
  }

  testWidgets('window default, Off and enabled intent stay independent', (
    tester,
  ) async {
    final outcome = await _openAlerts(
      tester,
      rules: const ConnectionAlertThresholds(
        plan: AlertPercentThreshold(at: 70),
        planWindows: {
          'a': AlertPercentThreshold(),
          'missing': AlertPercentThreshold(at: 83),
        },
      ),
      windows: [_window('a', 'Shared'), _window('b', 'Shared')],
    );
    expect(_editor('Shared · a'), findsOneWidget);
    expect(_editor('Shared · b'), findsOneWidget);
    expect(_editor('Plan window · missing'), findsOneWidget);
    expect(
      tester
          .widget<AlertPercentThresholdEditor>(_editor('Shared · a'))
          .usePlanDefault,
      isFalse,
    );
    await _choose(tester, 'Plan', '50% left');
    await _choose(tester, 'Shared · b', 'Off');
    await _choose(tester, 'Shared · a', 'Use Plan default');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(outcome.rules!.plan.at, 50);
    expect(outcome.rules!.planWindows.containsKey('a'), isFalse);
    expect(outcome.rules!.planWindows['b']!.at, isNull);
    expect(outcome.rules!.planWindows['missing']!.at, 83);

    final reset = await _openAlerts(tester, rules: outcome.rules!);
    await _choose(tester, 'Plan window · missing', 'Use Plan default');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(reset.rules!.planWindows.keys, ['b']);
  });

  testWidgets(
    'strict invalid custom drafts block Save and explicit Off recovers',
    (tester) async {
      final outcome = await _openAlerts(tester);
      await _choose(tester, 'Plan', 'Custom % left');
      for (final input in ['', '1.5', 'NaN', '-1', '101', '17x', '1e2']) {
        await tester.enterText(_percentField('Plan'), input);
        await tester.tap(find.text('Save'));
        await tester.pumpAndSettle();
        expect(outcome.completed, isFalse, reason: input);
        expect(find.text('Enter a whole number from 0 to 100'), findsOneWidget);
      }
      await _choose(tester, 'Plan', 'Off');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(outcome.rules!.plan.at, isNull);
    },
  );

  testWidgets('Cancel and barrier dismissal discard custom window drafts', (
    tester,
  ) async {
    for (final barrier in [false, true]) {
      final outcome = await _openAlerts(
        tester,
        windows: [_window('window', 'Window')],
      );
      await _choose(tester, 'Window', 'Custom % left');
      await tester.ensureVisible(_percentField('Window'));
      await tester.enterText(_percentField('Window'), '17');
      if (barrier) {
        await tester.tapAt(const Offset(2, 2));
      } else {
        await tester.tap(find.text('Cancel'));
      }
      await tester.pumpAndSettle();
      expect(outcome.completed, isTrue);
      expect(outcome.rules, isNull);
    }
  });

  testWidgets(
    'missing limits retain custom values and allow another period edit',
    (tester) async {
      final outcome = await _openAlerts(
        tester,
        connection: ProviderConnections.cursorPlatform,
        rules: const ConnectionAlertThresholds(
          today: AlertPercentThreshold(at: 83),
          week: AlertPercentThreshold(at: 0),
          budget: ConnectionBudget(month: 12345),
        ),
      );
      expect(
        tester.widget<TextFormField>(_percentField('Today')).enabled,
        isFalse,
      );
      await _choose(tester, 'Month', 'Custom % left');
      await tester.ensureVisible(_percentField('Month'));
      await tester.enterText(_percentField('Month'), '17');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(outcome.rules!.today.at, 83);
      expect(outcome.rules!.week.at, 0);
      expect(outcome.rules!.month.at, 83);
      expect(outcome.rules!.budget.month, 12345);
    },
  );

  for (final keyboardAfterSave in [false, true]) {
    testWidgets(
      keyboardAfterSave
          ? 'offscreen validation stays revealed when keyboard opens after Save'
          : 'offscreen validation reveals focus in a bounded accessible dialog',
      (tester) async {
        tester.view.physicalSize = const Size(360, 740);
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = 1.5;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetViewInsets);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        const label =
            'Window with a long descriptive label that must wrap fully';
        final outcome = await _openAlerts(
          tester,
          connectionTitle: 'Connection with a long descriptive name that wraps',
          windows: [for (var i = 0; i < 5; i++) _window('$i', '$label $i')],
        );
        await _choose(tester, 'Plan', 'Custom % left');
        await tester.enterText(_percentField('Plan'), '17');
        await _choose(tester, '$label 4', 'Custom % left');
        final invalidField = _percentField('$label 4');
        await tester.ensureVisible(invalidField);
        await tester.pumpAndSettle();
        expect(invalidField.hitTestable(), findsOneWidget);
        await tester.enterText(invalidField, '1.5');
        await tester.pumpAndSettle();
        final paragraph = tester.renderObject<RenderParagraph>(
          find.text('$label 4'),
        );
        expect(paragraph.didExceedMaxLines, isFalse);
        expect(paragraph.textScaler.scale(10), 15);
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.ensureVisible(_dropdown('Plan'));
        await tester.pumpAndSettle();
        expect(invalidField.hitTestable(), findsNothing);
        if (!keyboardAfterSave) {
          tester.view.viewInsets = const FakeViewPadding(bottom: 240);
          await tester.pumpAndSettle();
        }
        await tester.tap(find.text('Save'));
        await tester.pumpAndSettle();
        const error = 'Enter a whole number from 0 to 100';
        final errorText = find.descendant(
          of: invalidField,
          matching: find.text(error),
        );
        void expectValidationVisible(double keyboardInset) {
          expect(outcome.completed, isFalse);
          expect(errorText, findsOneWidget);
          expect(invalidField.hitTestable(), findsOneWidget);
          final inputFinder = find.descendant(
            of: invalidField,
            matching: find.byType(EditableText),
          );
          final input = tester.widget<EditableText>(inputFinder);
          expect(input.focusNode.hasFocus, isTrue);
          final editable =
              tester.state<EditableTextState>(inputFinder).renderEditable;
          final errorParagraph = tester.renderObject<RenderParagraph>(
            errorText,
          );
          expect(errorParagraph.didExceedMaxLines, isFalse);
          expect(
            tester
                .widget<FadeTransition>(
                  find
                      .ancestor(
                        of: errorText,
                        matching: find.byType(FadeTransition),
                      )
                      .first,
                )
                .opacity
                .value,
            1,
          );
          Rect bounds(RenderBox box) => MatrixUtils.transformRect(
            box.getTransformTo(null),
            Offset.zero & box.size,
          );
          final viewport =
              RenderAbstractViewport.of(tester.renderObject(invalidField))
                  as RenderBox;
          final viewportBounds = bounds(viewport);
          final unobscuredBounds = Rect.fromLTWH(
            0,
            0,
            360,
            740 - keyboardInset,
          );
          expect(viewportBounds.intersect(unobscuredBounds), viewportBounds);
          for (final (name, box) in [
            ('input', editable),
            ('error', errorParagraph),
          ]) {
            final region = bounds(box);
            expect(
              region.intersect(viewportBounds),
              region,
              reason: 'The complete $name must fit inside the scroll viewport',
            );
          }
          expect(
            tester
                .hitTestOnBinding(bounds(editable).center)
                .path
                .any((entry) => identical(entry.target, editable)),
            isTrue,
          );
          expect(
            find.bySemanticsLabel(RegExp('$label 4 remaining percentage')),
            findsWidgets,
          );
          final inputSemantics =
              tester.getSemantics(inputFinder).getSemanticsData();
          expect(
            inputSemantics.label,
            contains('$label 4 remaining percentage'),
          );
          expect(inputSemantics.hint, contains(error));
          expect(inputSemantics.value, '1.5');
          expect(inputSemantics.hasAction(SemanticsAction.setText), isTrue);
          for (final action in ['Save', 'Cancel']) {
            expect(find.text(action).hitTestable(), findsOneWidget);
            final actionBounds = tester.getRect(find.text(action));
            expect(actionBounds.intersect(unobscuredBounds), actionBounds);
          }
          expect(tester.takeException(), isNull);
        }

        expectValidationVisible(keyboardAfterSave ? 0 : 240);
        if (keyboardAfterSave) {
          tester.view.viewInsets = const FakeViewPadding(bottom: 240);
          await tester.pumpAndSettle();
          expectValidationVisible(240);
        }
        await tester.enterText(invalidField, '17');
        await tester.pumpAndSettle();
        expect(errorText, findsNothing);
        // Tab past Purchased to both dialog actions, then activate Save.
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pumpAndSettle();
        for (final action in ['Cancel', 'Save']) {
          await tester.sendKeyEvent(LogicalKeyboardKey.tab);
          await tester.pumpAndSettle();
          expect(Focus.of(tester.element(find.text(action))).hasFocus, isTrue);
          expect(find.text(action).hitTestable(), findsOneWidget);
        }
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        expect(outcome.completed, isTrue);
        expect(outcome.rules!.plan.at, 83);
        expect(outcome.rules!.planWindows['4']!.at, 83);
        expect(tester.takeException(), isNull);
        tester.view.resetViewInsets();
      },
    );
  }

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
      of: find.widgetWithText(ProviderConnectionRow, 'Platform reporting'),
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

Finder _editor(String title) =>
    find.widgetWithText(AlertPercentThresholdEditor, title);

Finder _dropdown(String title) => find.descendant(
  of: _editor(title),
  matching: find.byType(DropdownButton<int?>),
);

Finder _percentField(String title) =>
    find.descendant(of: _editor(title), matching: find.byType(TextFormField));

Future<void> _choose(WidgetTester tester, String title, String choice) async {
  // Finish text-entry caret scrolling before revealing the next control.
  await tester.pumpAndSettle();
  final dropdown = _dropdown(title);
  await Scrollable.ensureVisible(tester.element(dropdown), alignment: 0.5);
  await tester.pumpAndSettle();
  expect(dropdown.hitTestable(), findsOneWidget);
  await tester.tap(dropdown);
  await tester.pumpAndSettle();
  final option = find.text(choice).last;
  await tester.ensureVisible(option);
  await tester.pumpAndSettle();
  expect(option.hitTestable(), findsOneWidget);
  await tester.tap(option);
  await tester.pumpAndSettle();
}

AllowanceState _window(String id, String label) => AllowanceState(
  id: id,
  source: AllowanceSource.plan,
  label: label,
  usedPercent: null,
  used: null,
  limit: null,
  remaining: null,
  windowMinutes: null,
  resetsAt: null,
  status: ProviderStatus.ok,
);

Future<_AlertOutcome> _openAlerts(
  WidgetTester tester, {
  String connectionTitle = 'Connection',
  ConnectionAlertThresholds rules = const ConnectionAlertThresholds(),
  ProviderConnectionId connection = ProviderConnections.codexPlan,
  List<AllowanceState> windows = const [],
}) async {
  final outcome = _AlertOutcome();
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder:
              (context) => TextButton(
                onPressed: () async {
                  outcome.rules = await showDialog<ConnectionAlertThresholds>(
                    context: context,
                    builder:
                        (_) => ConnectionAlertsDialog(
                          connectionTitle: connectionTitle,
                          connection: connection,
                          thresholds: rules,
                          planWindows: windows,
                        ),
                  );
                  outcome.completed = true;
                },
                child: const Text('Open alerts'),
              ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open alerts'));
  await tester.pumpAndSettle();
  return outcome;
}

final class _AlertOutcome {
  bool completed = false;
  ConnectionAlertThresholds? rules;
}

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
