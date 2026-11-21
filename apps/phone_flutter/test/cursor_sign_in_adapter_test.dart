import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';
import 'package:ward_pulse_phone/providers/cursor_plan_sign_in_screen.dart';
import 'package:ward_pulse_phone/providers/cursor_sign_in_native_guard.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Platform platform;
  late WebViewPlatform? previous;
  final ios = TargetPlatformVariant.only(TargetPlatform.iOS);
  final browsers = <_Browser>[];
  const channel = MethodChannel(CursorSignInNativeGuard.channelName);
  final nativeCalls = <MethodCall>[];
  String? nativeFailure;

  setUp(() {
    previous = WebViewPlatform.instance;
    platform = _Platform();
    WebViewPlatform.instance = platform;
    nativeCalls.clear();
    browsers.clear();
    nativeFailure = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          nativeCalls.add(call);
          return call.method == 'failure' ? nativeFailure : null;
        });
  });
  tearDown(() {
    if (previous != null) WebViewPlatform.instance = previous;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  _Browser createBrowser({
    CursorSignInNativeGuard Function(void Function(String))? nativeGuardFactory,
  }) {
    final browser = _Browser(nativeGuardFactory: nativeGuardFactory);
    browsers.add(browser);
    return browser;
  }

  Future<void> retireScreen(WidgetTester tester) async {
    for (final controller in platform.controllers) {
      controller.blankFailures = 0;
      controller.beforeBlank = null;
    }
    await tester.pumpWidget(const SizedBox.shrink());
    await Future.wait(browsers.map((browser) => browser.stop()));
    await tester.pumpAndSettle();
  }

  Future<void> nativeEvent(int view, String category) async {
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
          CursorSignInNativeGuard.channelName,
          const StandardMethodCodec().encodeMethodCall(
            MethodCall('failure', {'view': view, 'category': category}),
          ),
          (_) {},
        );
  }

  for (final reopen in [false, true]) {
    testWidgets('blank request failure recovers (reopen: $reopen)', (
      tester,
    ) async {
      final results = <String?>[];
      try {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder:
                    (context) => TextButton(
                      onPressed: () async {
                        results.add(
                          await Navigator.of(context).push<String>(
                            MaterialPageRoute(
                              builder:
                                  (_) => CursorPlanSignInScreen(
                                    browserFactory: createBrowser,
                                  ),
                            ),
                          ),
                        );
                      },
                      child: const Text('Open'),
                    ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        final old = platform.controllers.single;
        await old.loaded.future;
        old.blankFailures = 1;
        platform.delegate.onError(
          const WebResourceError(
            errorCode: -2,
            description: 'Synthetic resource error',
            isForMainFrame: true,
          ),
        );
        await tester.pumpAndSettle();
        expect(find.textContaining('Could not load'), findsOneWidget);
        expect(old.blanks, 1);
        final clears = platform.cookies.clears;
        if (reopen) {
          await tester.tap(find.byTooltip('Cancel'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Open'));
        } else {
          await tester.tap(find.text('Retry'));
        }
        await tester.pumpAndSettle();
        expect(old.blanks, 2);
        expect(platform.controllers, hasLength(2));
        await platform.controllers.last.loaded.future;
        expect(
          platform.controllers.last.loads.single,
          Uri.parse(CursorPlanSignInScreen.defaultSignInUrl),
        );
        expect(platform.cookies.clears, greaterThan(clears));
        expect(results.whereType<String>(), isEmpty);
      } finally {
        await retireScreen(tester);
      }
    }, variant: ios);
  }

  const concurrentRetirement =
      'concurrent retirement shares the failed request and can retry it';
  _testIOS(concurrentRetirement, () async {
    final browser = WebViewCursorSignInBrowser();
    try {
      await _configure(browser);
      await browser.load(Uri.parse(CursorPlanSignInScreen.defaultSignInUrl));
      final controller = platform.controllers.single;
      controller.blankFailures = 1;
      final first = browser.stop();
      expect(browser.stop(), same(first));
      await expectLater(first, throwsStateError);
      await browser.stop();
      expect(controller.blanks, 2);
    } finally {
      await browser.stop();
    }
  });

  for (final status in [401, 503]) {
    final description =
        'adapter HTTP $status distinguishes current document and subresource';
    _testIOS(description, () async {
      final browser = WebViewCursorSignInBrowser();
      final errors = <bool>[];
      var finished = 0;
      try {
        await _configure(
          browser,
          error: errors.add,
          finished: () => finished++,
        );
        final document = Uri.parse('https://cursor.com/login');
        await browser.load(document);
        platform.delegate.onStarted(document.toString());
        platform.delegate.onHttpError(
          HttpResponseError(
            request: WebResourceRequest(
              uri: Uri.parse('https://cursor.com/icon'),
            ),
            response: WebResourceResponse(uri: null, statusCode: status),
          ),
        );
        expect(errors, isEmpty);
        platform.delegate.onHttpError(
          HttpResponseError(
            request: WebResourceRequest(uri: document),
            response: WebResourceResponse(uri: null, statusCode: status),
          ),
        );
        expect(errors, [true]);
        platform.delegate.onFinished(document.toString());
        expect(finished, 1);
      } finally {
        await browser.stop();
      }
    });
  }

  testWidgets(
    'main-document HTTP failure reaches screen recovery before waiting',
    (tester) async {
      try {
        await tester.pumpWidget(
          MaterialApp(
            home: CursorPlanSignInScreen(browserFactory: createBrowser),
          ),
        );
        await tester.pumpAndSettle();
        final controller = platform.controllers.single;
        await controller.loaded.future;
        controller.delegate.onHttpError(
          HttpResponseError(
            request: WebResourceRequest(
              uri: Uri.parse(CursorPlanSignInScreen.defaultSignInUrl),
            ),
            response: const WebResourceResponse(uri: null, statusCode: 503),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.textContaining('Could not load the sign-in page'),
          findsOneWidget,
        );
        await tester.pump(CursorPlanSignInScreen.waitingTimeout);
        expect(
          find.textContaining('Continue password or MFA entry'),
          findsNothing,
        );
        expect(find.text('Retry'), findsOneWidget);
        expect(find.byTooltip('Cancel'), findsOneWidget);
        expect(find.byTooltip('Help'), findsOneWidget);
      } finally {
        await retireScreen(tester);
      }
    },
    variant: ios,
  );

  testWidgets('guard attachment failure prevents the initial page load', (
    tester,
  ) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          nativeCalls.add(call);
          if (call.method == 'attach') {
            throw PlatformException(code: 'unavailable');
          }
          return null;
        });
    try {
      await tester.pumpWidget(
        MaterialApp(
          home: CursorPlanSignInScreen(
            browserFactory:
                () => createBrowser(
                  nativeGuardFactory:
                      (failure) => CursorSignInNativeGuard(
                        view: 31,
                        client: 32,
                        onFailure: failure,
                      ),
                ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final controller = platform.controllers.single;
      await controller.configured.future;
      expect(
        find.textContaining('prepare the sign-in browser'),
        findsOneWidget,
      );
      expect(platform.controllers.single.loads, isEmpty);
      expect(nativeCalls.map((call) => call.method), ['attach', 'detach']);
    } finally {
      await retireScreen(tester);
    }
  }, variant: ios);

  testWidgets('native POST rejection reaches unsupported-redirect recovery', (
    tester,
  ) async {
    try {
      await tester.pumpWidget(
        MaterialApp(
          home: CursorPlanSignInScreen(
            browserFactory:
                () => createBrowser(
                  nativeGuardFactory:
                      (failure) => CursorSignInNativeGuard(
                        view: 41,
                        client: 42,
                        onFailure: failure,
                      ),
                ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final controller = platform.controllers.single;
      await controller.loaded.future;
      controller.beforeBlank = () {
        expectSync(nativeCalls.last.method, 'retire');
      };
      await nativeEvent(41, 'navigationRejected');
      await tester.pumpAndSettle();
      expect(find.textContaining('redirect is not supported'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      expect(find.byTooltip('Cancel'), findsOneWidget);
      expect(find.byTooltip('Help'), findsOneWidget);
      final retiring = nativeCalls.firstWhere(
        (call) => call.method == 'retire',
      );
      expect(retiring.arguments, {'view': 41});
      await browsers.single.firstStop!;
      expect(nativeCalls.last.method, 'detach');
    } finally {
      await retireScreen(tester);
    }
  }, variant: ios);

  const guardEvents =
      'native guard events bind to the adapter and detach after retirement';
  _testIOS(guardEvents, () async {
    var blocked = 0;
    final errors = <bool>[];
    final browser = WebViewCursorSignInBrowser(
      nativeGuardFactory:
          (failure) =>
              CursorSignInNativeGuard(view: 7, client: 9, onFailure: failure),
    );
    try {
      await browser.configure(
        navigate: (url, mainFrame) {
          expect(url, 'https://accounts.google.com/');
          expect(mainFrame, isFalse);
          blocked++;
          return false;
        },
        pageStarted: () {},
        pageFinished: () {},
        resourceError: errors.add,
      );
      expect(nativeCalls.single.method, 'attach');
      expect(nativeCalls.single.arguments, {'view': 7, 'client': 9});
      await browser.load(Uri.parse(CursorPlanSignInScreen.defaultSignInUrl));
      await nativeEvent(8, 'googleAuthorization');
      expect(blocked, 0);
      await nativeEvent(7, 'googleAuthorization');
      expect(blocked, 1);
      expect(await browser.probe(Uri.parse('https://cursor.com/')), isNull);
      expect(platform.cookies.reads, isEmpty);
      await browser.stop();
      expect(nativeCalls.last.method, 'detach');
      await nativeEvent(7, 'mainFrameHttpError');
      expect(errors, isEmpty);
      expect(blocked, 1);
    } finally {
      await browser.stop();
    }
  });

  const blankingFailure =
      'HTTP failure during blanking refuses completion but retirement can recover';
  _testIOS(blankingFailure, () async {
    final browser = WebViewCursorSignInBrowser(
      nativeGuardFactory:
          (failure) =>
              CursorSignInNativeGuard(view: 21, client: 22, onFailure: failure),
    );
    try {
      await _configure(browser);
      await browser.load(Uri.parse(CursorPlanSignInScreen.defaultSignInUrl));
      platform.controllers.single.beforeBlank =
          () => nativeFailure = 'mainFrameHttpError';
      await expectLater(browser.stop(requireHealthy: true), throwsStateError);
      expect(nativeCalls.where((call) => call.method == 'detach'), isEmpty);
      await browser.stop();
      expect(platform.controllers.single.blanks, 1);
      expect(nativeCalls.last.method, 'detach');
    } finally {
      await browser.stop();
    }
  });

  const queuedHttpFailure =
      'queued native HTTP failure prevents capture without relying on event order';
  _testIOS(queuedHttpFailure, () async {
    final errors = <bool>[];
    final browser = WebViewCursorSignInBrowser(
      nativeGuardFactory:
          (failure) =>
              CursorSignInNativeGuard(view: 11, client: 12, onFailure: failure),
    );
    try {
      await _configure(browser, error: errors.add);
      await browser.load(Uri.parse(CursorPlanSignInScreen.defaultSignInUrl));
      nativeFailure = 'mainFrameHttpError';
      expect(await browser.probe(Uri.parse('https://cursor.com/')), isNull);
      expect(errors, [true]);
      expect(platform.cookies.reads, isEmpty);
    } finally {
      await browser.stop();
    }
  });
}

void _testIOS(String description, Future<void> Function() body) {
  test(description, () async {
    final previous = debugDefaultTargetPlatformOverride;
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      await body();
    } finally {
      debugDefaultTargetPlatformOverride = previous;
    }
  });
}

Future<void> _configure(
  WebViewCursorSignInBrowser browser, {
  void Function(bool)? error,
  VoidCallback? finished,
}) => browser.configure(
  navigate: (_, _) => true,
  pageStarted: () {},
  pageFinished: finished ?? () {},
  resourceError: error ?? (_) {},
);

class _Browser extends WebViewCursorSignInBrowser {
  _Browser({super.nativeGuardFactory});

  Future<void>? firstStop;

  @override
  Future<void> stop({bool requireHealthy = false}) {
    final work = super.stop(requireHealthy: requireHealthy);
    firstStop ??= work;
    return work;
  }
}

class _Platform extends WebViewPlatform {
  final controllers = <_Controller>[];
  final cookies = _Cookies();
  late _Delegate delegate;

  @override
  PlatformWebViewController createPlatformWebViewController(
    PlatformWebViewControllerCreationParams params,
  ) {
    final controller = _Controller(params);
    controllers.add(controller);
    return controller;
  }

  @override
  PlatformNavigationDelegate createPlatformNavigationDelegate(
    PlatformNavigationDelegateCreationParams params,
  ) => delegate = _Delegate(params);
  @override
  PlatformWebViewCookieManager createPlatformCookieManager(
    PlatformWebViewCookieManagerCreationParams params,
  ) => cookies;
  @override
  PlatformWebViewWidget createPlatformWebViewWidget(
    PlatformWebViewWidgetCreationParams params,
  ) => _PlatformWidget(params);
}

class _PlatformWidget extends PlatformWebViewWidget {
  _PlatformWidget(super.params) : super.implementation();
  @override
  Widget build(BuildContext context) => const SizedBox();
}

class _Controller extends PlatformWebViewController {
  _Controller(super.params) : super.implementation();
  final loads = <Uri>[];
  final configured = Completer<void>();
  final loaded = Completer<void>();
  late _Delegate delegate;
  VoidCallback? beforeBlank;
  int blankFailures = 0;
  int blanks = 0;
  String? url;

  @override
  Future<void> setJavaScriptMode(JavaScriptMode mode) async {}
  @override
  Future<void> setPlatformNavigationDelegate(
    PlatformNavigationDelegate value,
  ) async {
    delegate = value as _Delegate;
    configured.complete();
  }

  @override
  Future<void> loadRequest(LoadRequestParams params) async {
    if (params.uri.toString() == 'about:blank') {
      blanks++;
      beforeBlank?.call();
      if (blankFailures > 0) {
        blankFailures--;
        throw StateError('Synthetic blank request failure');
      }
    }
    loads.add(params.uri);
    url = params.uri.toString();
    if (url == 'about:blank') {
      delegate.onFinished(url!);
    } else if (!loaded.isCompleted) {
      loaded.complete();
    }
  }

  @override
  Future<String?> currentUrl() async => url;
}

class _Cookies extends PlatformWebViewCookieManager {
  _Cookies()
    : super.implementation(const PlatformWebViewCookieManagerCreationParams());
  final reads = <Uri>[];
  int clears = 0;
  @override
  Future<bool> clearCookies() async {
    clears++;
    return true;
  }

  @override
  Future<List<WebViewCookie>> getCookies(Uri url) async {
    reads.add(url);
    return [];
  }
}

class _Delegate extends PlatformNavigationDelegate {
  _Delegate(super.params) : super.implementation();
  late PageEventCallback onStarted;
  late PageEventCallback onFinished;
  late WebResourceErrorCallback onError;
  late HttpResponseErrorCallback onHttpError;
  @override
  Future<void> setOnNavigationRequest(
    NavigationRequestCallback callback,
  ) async {}
  @override
  Future<void> setOnPageStarted(PageEventCallback callback) async {
    onStarted = callback;
  }

  @override
  Future<void> setOnPageFinished(PageEventCallback callback) async {
    onFinished = callback;
  }

  @override
  Future<void> setOnWebResourceError(WebResourceErrorCallback callback) async {
    onError = callback;
  }

  @override
  Future<void> setOnHttpError(HttpResponseErrorCallback callback) async {
    onHttpError = callback;
  }
}
