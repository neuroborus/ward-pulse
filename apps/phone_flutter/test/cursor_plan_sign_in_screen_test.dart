import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ward_pulse_phone/providers/cursor_plan_sign_in_screen.dart';

const _token = 'synthetic-user::header.payload.signature_padding==';

void main() {
  testWidgets('controller creation failure exposes recovery and Help', (
    tester,
  ) async {
    await _withScreen(tester, (h) async {
      expect(find.textContaining('prepare the sign-in browser'), findsOneWidget);
      await tester.tap(find.byTooltip('Help'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Advanced paste'), findsOneWidget);
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(h.browsers.single.calls, contains('load'));
      await tester.tap(find.byTooltip('Cancel'));
      await tester.pumpAndSettle();
      expect(h.results, [null]);
    }, creationFailure: true);
  });

  for (final stage in ['configure', 'wipe', 'load', 'url', 'probe']) {
    testWidgets('$stage failure is visible and Retry starts a verified attempt', (
      tester,
    ) async {
      await _withScreen(tester, (h) async {
        final first = h.browsers.first;
        if (stage == 'url' || stage == 'probe') {
          first.pageFinished();
          await tester.pumpAndSettle();
        }
        expect(find.textContaining('Could not'), findsOneWidget);
        expect(h.results, isEmpty);
        if (stage == 'configure' || stage == 'wipe') {
          expect(first.calls, isNot(contains('load')));
        }
        await tester.tap(find.text('Retry'));
        await tester.pumpAndSettle();
        expect(h.browsers.last.calls.take(3), ['configure', 'wipe', 'load']);
        expect(h.browsers.last, isNot(same(first)));
      }, setup: (browser, index) {
        if (index == 0) browser.failure = stage;
      });
    });

    testWidgets('$stage work has a finite deadline without releasing old work', (
      tester,
    ) async {
      await _withScreen(tester, (h) async {
        final first = h.browsers.first;
        if (stage == 'url' || stage == 'probe') {
          first.pageFinished();
          await tester.pump();
        }
        await tester.pump(CursorPlanSignInScreen.stageTimeout);
        expect(find.textContaining('Could not'), findsOneWidget);
        await tester.tap(find.text('Retry'));
        await tester.pump();
        expect(h.browsers, hasLength(1));
        first.release();
        await tester.pumpAndSettle();
        expect(h.browsers, hasLength(2));
        expect(h.browsers.last.calls.take(3), ['configure', 'wipe', 'load']);
        expect(h.results, isEmpty);
      }, setup: (browser, index) {
        if (index == 0) browser.hold = stage;
      });
    });
  }

  testWidgets('unverified startup wipe fails closed', (tester) async {
    await _withScreen(tester, (h) async {
      expect(
        find.textContaining('clear the previous Cursor session'),
        findsOneWidget,
      );
      expect(h.browsers.single.calls, isNot(contains('load')));
      expect(h.results, isEmpty);
    }, setup: (browser, _) => browser.wiped = false);
  });

  for (final (location, url) in [
    ('unreadable', null),
    ('unapproved', 'https://unapproved.example/login'),
  ]) {
    testWidgets('$location current location cannot capture', (
      tester,
    ) async {
      await _withScreen(tester, (h) async {
        final browser = h.browsers.single;
        browser.url = url;
        browser.token = _token;
        browser.pageFinished();
        await tester.pumpAndSettle();
        expect(find.textContaining('Retry, Cancel, or open Help'), findsOneWidget);
        expect(browser.calls, isNot(contains('probe')));
        expect(h.results, isEmpty);
      });
    });
  }

  testWidgets('main-frame failures differ from harmless subresource errors', (
    tester,
  ) async {
    await _withScreen(tester, (h) async {
      final browser = h.browsers.single;
      browser.resourceError(false);
      await tester.pump();
      expect(find.byKey(const ValueKey('browser')), findsOneWidget);
      expect(h.results, isEmpty);
      browser.resourceError(true);
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Could not load the sign-in page'),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('browser')), findsNothing);
    });
  });

  for (final mainFrame in [true, false]) {
    testWidgets('Google authorization callbacks are rejected (main: $mainFrame)', (
      tester,
    ) async {
      await _withScreen(tester, (h) async {
        final browser = h.browsers.single;
        expect(
          browser.navigate('https://www.gstatic.com/resource', false),
          isTrue,
        );
        expect(
          browser.navigate('https://www.google.com/recaptcha/api2', false),
          isTrue,
        );
        expect(browser.navigate('https://accounts.google.com/gsi/client', false), isTrue);
        expect(browser.navigate('https://accounts.google.com/gsi/button', false), isTrue);
        expect(
          browser.navigate('https://accounts.google.com/signin', mainFrame),
          isFalse,
        );
        await tester.pumpAndSettle();
        expect(find.textContaining('same-account email'), findsOneWidget);
        expect(h.results, isEmpty);
      });
    });
  }

  testWidgets('unapproved main-frame redirect is recoverable and cannot succeed', (
    tester,
  ) async {
    await _withScreen(tester, (h) async {
      final browser = h.browsers.single;
      expect(browser.navigate('https://auth.x.ai/login', true), isTrue);
      expect(h.results, isEmpty);
      expect(browser.navigate('https://auth.x.ai.example/login', true), isFalse);
      browser.token = _token;
      browser.pageFinished();
      await tester.pumpAndSettle();
      expect(find.textContaining('redirect is not supported'), findsOneWidget);
      expect(h.results, isEmpty);
    });
  });

  testWidgets('a page that never finishes has finite recovery', (tester) async {
    await _withScreen(tester, (h) async {
      await tester.pump(const Duration(seconds: 20));
      h.browsers.single.pageStarted();
      await tester.pump(const Duration(seconds: 10));
      expect(find.textContaining('did not finish loading'), findsOneWidget);
      expect(h.results, isEmpty);
    }, setup: (browser, _) => browser.finishPage = false);
  });

  testWidgets('human input remains waiting; Check again resumes bounded probing', (
    tester,
  ) async {
    await _withScreen(tester, (h) async {
      final browser = h.browsers.single;
      await tester.pump(CursorPlanSignInScreen.waitingTimeout);
      expect(
        find.textContaining('Continue password or MFA entry'),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('browser')), findsOneWidget);
      final probes = browser.calls.where((call) => call == 'probe').length;
      await tester.pump(CursorPlanSignInScreen.waitingTimeout);
      browser.pageFinished();
      await tester.pump();
      expect(browser.calls.where((call) => call == 'probe').length, probes);
      expect(h.results, isEmpty);
      browser.token = _token;
      await tester.tap(find.text('Check again'));
      await tester.pumpAndSettle();
      expect(h.results, [_token]);
    });
  });

  testWidgets('rapid Retry fences superseded work and late callbacks', (
    tester,
  ) async {
    await _withScreen(tester, (h) async {
      final old = h.browsers.single;
      old.hold = 'probe';
      old.token = _token;
      old.pageFinished();
      await tester.pump();
      await tester.tap(find.text('Retry'));
      await tester.tap(find.text('Retry'));
      await tester.pump();
      expect(h.browsers, hasLength(1));
      old.release();
      await tester.pumpAndSettle();
      expect(h.browsers, hasLength(2));
      final calls = List<String>.of(old.calls);
      old.pageStarted();
      old.pageFinished();
      old.resourceError(true);
      expect(old.navigate('https://cursor.com/dashboard', true), isFalse);
      await tester.pump();
      expect(old.calls, calls);
      expect(h.results, isEmpty);
      h.browsers.last.token = _token;
      h.browsers.last.pageFinished();
      await tester.pumpAndSettle();
      expect(h.results, [_token]);
      expect(old.calls, calls);
    });
  });

  for (final action in ['Cancel', 'back', 'dispose']) {
    testWidgets('$action invalidates a pending probe before late completion', (
      tester,
    ) async {
      await _withScreen(tester, (h) async {
        final browser = h.browsers.single;
        browser.hold = 'probe';
        browser.token = _token;
        browser.pageFinished();
        await tester.pump();
        if (action == 'Cancel') {
          await tester.tap(find.byTooltip('Cancel'));
        } else if (action == 'back') {
          h.navigator.currentState!.pop();
        } else {
          await tester.pumpWidget(const SizedBox.shrink());
        }
        await tester.pumpAndSettle();
        browser.release();
        browser.pageFinished();
        await tester.pumpAndSettle();
        expect(h.results.whereType<String>(), isEmpty);
        expect(browser.calls.last, 'wipe');
      });
    });
  }

  testWidgets('reopen waits for old cleanup; blocked cleanup has finite recovery', (
    tester,
  ) async {
    await _withScreen(tester, (h) async {
      final old = h.browsers.single;
      old.hold = 'stop';
      await tester.tap(find.byTooltip('Cancel'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open'));
      await tester.pump();
      expect(h.browsers, hasLength(1));
      await tester.pump(CursorPlanSignInScreen.stageTimeout);
      expect(find.textContaining('close the previous sign-in'), findsOneWidget);
      old.release();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(h.browsers, hasLength(2));
      expect(old.calls.last, 'wipe');
    });
  });

  testWidgets('completion is normalized, verified clean and returned once', (
    tester,
  ) async {
    await _withScreen(tester, (h) async {
      final browser = h.browsers.single;
      browser.token = 'placeholder';
      browser.pageFinished();
      await tester.pump();
      expect(h.results, isEmpty);
      browser.token = ' ${Uri.encodeComponent(_token)} ';
      browser.pageFinished();
      browser.pageFinished();
      await tester.pumpAndSettle();
      expect(h.results, [_token]);
      expect(browser.calls.where((call) => call == 'probe'), hasLength(2));
      expect(browser.calls, [
        'configure',
        'wipe',
        'load',
        'url',
        'probe',
        'url',
        'probe',
        'stop',
        'wipe',
      ]);
      browser.pageFinished();
      await tester.pumpAndSettle();
      expect(h.results, [_token]);
    });
  });

  testWidgets('Help cannot be dismissed by a pending credential result', (
    tester,
  ) async {
    await _withScreen(tester, (h) async {
      final browser = h.browsers.single;
      browser.hold = 'probe';
      browser.token = _token;
      browser.pageFinished();
      await tester.pump();
      await tester.tap(find.byTooltip('Help'));
      await tester.pumpAndSettle();
      browser.release();
      await tester.pump();
      expect(find.text('Cursor sign-in recovery'), findsOneWidget);
      expect(h.results, isEmpty);
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      browser.pageFinished();
      await tester.pumpAndSettle();
      expect(h.results, [_token]);
    });
  });

  testWidgets('completion cleanup timeout is recoverable and cannot return late', (
    tester,
  ) async {
    await _withScreen(tester, (h) async {
      final browser = h.browsers.single;
      browser.hold = 'wipe';
      browser.token = _token;
      browser.pageFinished();
      await tester.pump();
      await tester.pump(CursorPlanSignInScreen.stageTimeout);
      expect(find.textContaining('clear the sign-in browser'), findsOneWidget);
      await tester.tap(find.byTooltip('Cancel'));
      await tester.pumpAndSettle();
      browser.release();
      await tester.pumpAndSettle();
      expect(h.results, [null]);
    });
  });

  testWidgets('unverified completion cleanup never returns a credential', (
    tester,
  ) async {
    await _withScreen(tester, (h) async {
      final browser = h.browsers.single;
      browser.token = _token;
      browser.wiped = false;
      browser.pageFinished();
      await tester.pumpAndSettle();
      expect(find.textContaining('clear the sign-in browser'), findsOneWidget);
      expect(h.results, isEmpty);
    });
  });
}

Future<void> _withScreen(
  WidgetTester tester,
  Future<void> Function(_Harness) body, {
  void Function(_FakeBrowser browser, int index)? setup,
  bool creationFailure = false,
}) async {
  final h = _Harness();
  try {
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: h.navigator,
        home: Builder(
          builder:
              (context) => Scaffold(
                body: TextButton(
                  onPressed: () async {
                    final result = await Navigator.of(context).push<String>(
                      MaterialPageRoute(
                        builder:
                            (_) => CursorPlanSignInScreen(
                              browserFactory: () {
                                if (creationFailure) {
                                  creationFailure = false;
                                  throw StateError('Synthetic creation failure');
                                }
                                final browser = _FakeBrowser();
                                setup?.call(browser, h.browsers.length);
                                h.browsers.add(browser);
                                return browser;
                              },
                            ),
                      ),
                    );
                    h.results.add(result);
                  },
                  child: const Text('Open'),
                ),
              ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await body(h);
  } finally {
    // Retire the screen first, then settle all owned platform work, even when
    // an assertion fails. No pending native effect may leak to the next test.
    await tester.pumpWidget(const SizedBox.shrink());
    for (final browser in h.browsers) {
      browser.release();
    }
    await tester.pumpAndSettle();
  }
}

class _Harness {
  final navigator = GlobalKey<NavigatorState>();
  final browsers = <_FakeBrowser>[];
  final results = <String?>[];
}

class _FakeBrowser implements CursorSignInBrowser {
  final calls = <String>[];
  final _gate = Completer<void>();
  String? failure;
  String? hold;
  String? token;
  String? url = 'https://cursor.com/dashboard';
  bool wiped = true;
  bool finishPage = true;
  late bool Function(String, bool) navigate;
  late VoidCallback pageStarted;
  late VoidCallback pageFinished;
  late void Function(bool) resourceError;

  void release() {
    if (!_gate.isCompleted) _gate.complete();
  }

  Future<T> _effect<T>(String stage, T result) async {
    calls.add(stage);
    if (hold == stage) await _gate.future;
    if (failure == stage) throw StateError('Synthetic $stage failure');
    return result;
  }

  @override
  Future<void> configure({
    required bool Function(String url, bool mainFrame) navigate,
    required VoidCallback pageStarted,
    required VoidCallback pageFinished,
    required void Function(bool mainFrame) resourceError,
  }) {
    this.navigate = navigate;
    this.pageStarted = pageStarted;
    this.pageFinished = pageFinished;
    this.resourceError = resourceError;
    return _effect<void>('configure', null);
  }

  @override
  Future<void> load(Uri url) async {
    await _effect<void>('load', null);
    pageStarted();
    if (finishPage) pageFinished();
  }

  @override
  Future<String?> currentUrl() => _effect('url', url);
  @override
  Future<String?> probe(Uri? url) => _effect('probe', token);
  @override
  Future<bool> wipe() => _effect('wipe', wiped);
  @override
  Future<void> stop({bool requireHealthy = false}) => _effect<void>('stop', null);
  @override
  Widget build() => const SizedBox(key: ValueKey('browser'));
}
