import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ward_pulse_phone/app/ward_pulse_theme.dart';
import 'package:ward_pulse_phone/providers/credential_dialog.dart';
import 'package:ward_pulse_phone/providers/provider_connection.dart';

const _keyboardTop = 640.0 - 280.0;

void main() {
  for (final installed in [false, true]) {
    testWidgets(
      'Anthropic validates ${installed ? 'replacement' : 'new'} values before Save',
      (tester) async {
        final outcome = await _openCredential(
          tester,
          hasCredential: installed,
          valueValidator: validateAnthropicReportingKey,
        );
        final value = find.widgetWithText(
          TextFormField,
          installed ? 'Value (leave blank to keep)' : 'Value',
        );
        await tester.enterText(
          value,
          installed ? '  sk-ant-admin01-synthetic  ' : 'sk-ant-admin-synthetic',
        );
        await tester.tap(find.text('Save'));
        await tester.pumpAndSettle();
        expect(outcome.completed, isFalse);
        final error = find.text(anthropicReportingKeyGuidance);
        expect(error, findsOneWidget);
        expect(
          tester.renderObject<RenderParagraph>(error).didExceedMaxLines,
          isFalse,
        );
        await tester.ensureVisible(error);
        await tester.pumpAndSettle();
        final viewport = tester.getRect(
          find.descendant(
            of: find.byType(AlertDialog),
            matching: find.byType(SingleChildScrollView),
          ),
        );
        final errorBounds = tester.getRect(error);
        expect(errorBounds.top, greaterThanOrEqualTo(viewport.top));
        expect(errorBounds.bottom, lessThanOrEqualTo(viewport.bottom));
        expect(errorBounds.bottom, lessThanOrEqualTo(_keyboardTop));
        _expectActionsAboveKeyboard(tester);

        await tester.enterText(value, '  sk-ant-api03-synthetic  ');
        await tester.tap(find.text('Save'));
        await tester.pumpAndSettle();
        expect(outcome.change?.value, 'sk-ant-api03-synthetic');
        expect(outcome.change?.remove, isFalse);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('blank label-only, Cancel and Remove bypass value validation', (
    tester,
  ) async {
    var validations = 0;
    final outcome = await _openCredential(
      tester,
      hasCredential: true,
      valueValidator: (_) {
        validations++;
        return 'Rejected candidate';
      },
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Label (optional)'),
      'New label',
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(outcome.change?.updateLabelOnly, isTrue);
    expect(outcome.change?.label, 'New label');
    for (final action in ['Cancel', 'Remove']) {
      await tester.tap(find.text('Open credential'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Value (leave blank to keep)'),
        'invalid-candidate',
      );
      await tester.tap(find.text(action));
      await tester.pumpAndSettle();
      if (action == 'Cancel') {
        expect(outcome.change, isNull);
      } else {
        expect(outcome.change?.remove, isTrue);
      }
    }
    expect(validations, 0);
  });

  testWidgets(
    'large credential form validates and cancels above the keyboard',
    (tester) async {
      final outcome = await _openCredential(tester);
      expect(tester.takeException(), isNull);
      _expectActionsAboveKeyboard(tester);

      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(outcome.completed, isFalse);

      for (final target in [
        find.text('Enter a value'),
        find.byType(TextFormField).at(0),
        find.byType(TextFormField).at(1),
      ]) {
        await tester.ensureVisible(target);
        await tester.pumpAndSettle();
        expect(target.hitTestable(), findsOneWidget);
        expect(tester.getRect(target).bottom, lessThanOrEqualTo(_keyboardTop));
        expect(tester.takeException(), isNull);
        _expectActionsAboveKeyboard(tester);
      }

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(outcome.completed, isTrue);
      expect(outcome.change, isNull);
    },
  );

  testWidgets('large credential form submits a fake value and optional label', (
    tester,
  ) async {
    final outcome = await _openCredential(tester);
    expect(tester.takeException(), isNull);
    final value = find.byType(TextFormField).at(0);
    final label = find.byType(TextFormField).at(1);

    await tester.ensureVisible(value);
    await tester.pumpAndSettle();
    expect(value.hitTestable(), findsOneWidget);
    await tester.tap(value);
    await tester.enterText(value, ' wardpulse-test-not-a-real-key ');
    expect(
      tester.widget<TextField>(find.byType(TextField).first).obscureText,
      isTrue,
    );

    await tester.ensureVisible(label);
    await tester.pumpAndSettle();
    expect(label.hitTestable(), findsOneWidget);
    await tester.tap(label);
    await tester.enterText(label, ' Audit org ');
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    _expectActionsAboveKeyboard(tester);

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(outcome.completed, isTrue);
    expect(outcome.change?.value, 'wardpulse-test-not-a-real-key');
    expect(outcome.change?.label, 'Audit org');
    expect(outcome.change?.remove, isFalse);
    expect(outcome.change?.updateLabelOnly, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'guided credential starts without keyboard and stays reachable with it',
    (tester) async {
      const guidance =
          'Prepare a sample credential.\n\n'
          '1. Open the example account page.\n'
          '2. Locate the synthetic secret.\n'
          '3. Copy the synthetic value.\n'
          '4. Paste it below.';
      final outcome = await _openCredential(
        tester,
        guidance: guidance,
        autofocus: false,
        allowLabel: false,
        initialViewInsets: const FakeViewPadding(),
      );
      final guidanceText = find.text(guidance);
      final value = find.byType(TextFormField);

      expect(
        guidanceText.hitTestable(at: const Alignment(0, -0.9)),
        findsOneWidget,
      );
      expect(tester.testTextInput.isVisible, isFalse);
      expect(
        tester
            .widget<EditableText>(find.byType(EditableText))
            .focusNode
            .hasFocus,
        isFalse,
      );

      await tester.ensureVisible(value);
      await tester.pumpAndSettle();
      expect(value.hitTestable(), findsOneWidget);
      await tester.tap(value);
      await tester.pumpAndSettle();
      expect(tester.testTextInput.isVisible, isTrue);
      expect(
        tester
            .widget<EditableText>(find.byType(EditableText))
            .focusNode
            .hasFocus,
        isTrue,
      );

      tester.view.viewInsets = const FakeViewPadding(bottom: 280);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      for (final target in [find.text('Enter a value'), value]) {
        await tester.ensureVisible(target);
        await tester.pumpAndSettle();
        expect(target.hitTestable(), findsOneWidget);
        expect(tester.getRect(target).bottom, lessThanOrEqualTo(_keyboardTop));
        _expectActionsAboveKeyboard(tester);
      }

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(outcome.completed, isTrue);
      expect(outcome.change, isNull);
      expect(tester.takeException(), isNull);
    },
  );
}

void _expectActionsAboveKeyboard(WidgetTester tester) {
  for (final label in ['Cancel', 'Save']) {
    final action = find.text(label);
    expect(action.hitTestable(), findsOneWidget);
    expect(tester.getRect(action).bottom, lessThanOrEqualTo(_keyboardTop));
  }
}

Future<_CredentialOutcome> _openCredential(
  WidgetTester tester, {
  String? guidance,
  bool autofocus = true,
  bool allowLabel = true,
  bool hasCredential = false,
  String? Function(String)? valueValidator,
  FakeViewPadding initialViewInsets = const FakeViewPadding(bottom: 280),
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(320, 640);
  tester.view.viewInsets = initialViewInsets;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetViewInsets);

  final outcome = _CredentialOutcome();
  await tester.pumpWidget(
    MaterialApp(
      theme: wardPulseLightTheme,
      builder:
          (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(1.5)),
            child: child!,
          ),
      home: Scaffold(
        body: Builder(
          builder:
              (context) => TextButton(
                onPressed: () async {
                  outcome.change = await showDialog<CredentialChange>(
                    context: context,
                    builder:
                        (_) => CredentialDialog(
                          title: 'Anthropic · Organization reporting',
                          hint: 'API key',
                          allowLabel: allowLabel,
                          hasCredential: hasCredential,
                          valueValidator: valueValidator,
                          guidance: guidance,
                          autofocus: autofocus,
                        ),
                  );
                  outcome.completed = true;
                },
                child: const Text('Open credential'),
              ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open credential'));
  await tester.pumpAndSettle();
  return outcome;
}

final class _CredentialOutcome {
  bool completed = false;
  CredentialChange? change;
}
