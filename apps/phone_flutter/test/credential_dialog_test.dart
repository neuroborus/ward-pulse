import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ward_pulse_phone/app/ward_pulse_theme.dart';
import 'package:ward_pulse_phone/providers/credential_dialog.dart';

const _keyboardTop = 640.0 - 280.0;

void main() {
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
}

void _expectActionsAboveKeyboard(WidgetTester tester) {
  for (final label in ['Cancel', 'Save']) {
    final action = find.text(label);
    expect(action.hitTestable(), findsOneWidget);
    expect(tester.getRect(action).bottom, lessThanOrEqualTo(_keyboardTop));
  }
}

Future<_CredentialOutcome> _openCredential(WidgetTester tester) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(320, 640);
  tester.view.viewInsets = const FakeViewPadding(bottom: 280);
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
                        (_) => const CredentialDialog(
                          title: 'Anthropic · Organization reporting',
                          hint: 'API key',
                          allowLabel: true,
                          hasCredential: false,
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
