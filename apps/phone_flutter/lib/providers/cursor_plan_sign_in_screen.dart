import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import 'cursor_session_token.dart';
import 'cursor_sign_in_native_guard.dart';
import 'cursor_webview_cookies.dart';

/// Narrow platform seam for deterministic screen event and lifetime coverage.
abstract interface class CursorSignInBrowser {
  Future<void> configure({
    required bool Function(String url, bool mainFrame) navigate,
    required VoidCallback pageStarted,
    required VoidCallback pageFinished,
    required void Function(bool mainFrame) resourceError,
  });
  Future<void> load(Uri url);
  Future<String?> currentUrl();
  Future<String?> probe(Uri? url);
  Future<bool> wipe();
  Future<void> stop({bool requireHealthy = false});
  Widget build();
}

/// Native adapter, exposed for platform-seam regression coverage.
class WebViewCursorSignInBrowser implements CursorSignInBrowser {
  WebViewCursorSignInBrowser({
    WebViewCookieManager? cookies,
    this.nativeGuardFactory,
  }) : _cookies = cookies ?? WebViewCookieManager();

  final WebViewController _controller = WebViewController();
  final WebViewCookieManager _cookies;
  final CursorSignInNativeGuard Function(void Function(String))?
  nativeGuardFactory;
  CursorSignInNativeGuard? _guard;
  bool _loadStarted = false;
  bool _retiring = false;
  Uri? _mainDocument;
  Completer<void>? _blanked;
  Future<void>? _stopping;

  @override
  Future<void> configure({
    required bool Function(String url, bool mainFrame) navigate,
    required VoidCallback pageStarted,
    required VoidCallback pageFinished,
    required void Function(bool mainFrame) resourceError,
  }) async {
    // Keep the platform's honest default UA; never impersonate a browser.
    await _controller.setJavaScriptMode(JavaScriptMode.unrestricted);
    final delegate = NavigationDelegate(
      onNavigationRequest: (request) {
        final allowed =
            _retiring
                ? request.url == 'about:blank'
                : navigate(request.url, request.isMainFrame);
        return allowed
            ? NavigationDecision.navigate
            : NavigationDecision.prevent;
      },
      onPageStarted: (url) {
        if (_retiring || url == 'about:blank') return;
        _mainDocument = Uri.tryParse(url);
        pageStarted();
      },
      onPageFinished: (url) {
        if (!_retiring) {
          if (url != 'about:blank') pageFinished();
        } else if (url == 'about:blank') {
          final blanked = _blanked;
          if (blanked != null && !blanked.isCompleted) blanked.complete();
        }
      },
      onWebResourceError: (error) {
        if (!_retiring) resourceError(error.isForMainFrame == true);
      },
      onHttpError: (error) {
        // Android's native guard retains the real isForMainFrame flag. Other
        // platforms expose only the failed URI; compare the current document.
        final uri = error.request?.uri;
        if (!_retiring &&
            _guard == null &&
            uri != null &&
            uri.replace(fragment: '') == _mainDocument?.replace(fragment: '')) {
          resourceError(true);
        }
      },
    );
    await _controller.setNavigationDelegate(delegate);
    final controller = _controller.platform;
    final cookies = _cookies.platform;
    if (!kIsWeb &&
        defaultTargetPlatform == TargetPlatform.android &&
        controller is AndroidWebViewController &&
        cookies is AndroidWebViewCookieManager) {
      await cookies.setAcceptThirdPartyCookies(controller, true);
    }
    void failure(String category) {
      if (_retiring) return;
      if (category == 'googleAuthorization') {
        // The native client already prevented the request. Pass a fixed,
        // secret-free identity to the screen's existing recovery policy.
        navigate('https://accounts.google.com/', false);
      } else if (category == 'navigationRejected') {
        // An empty location reaches the existing unsupported-redirect recovery
        // without forwarding the rejected URI or any of its private fields.
        navigate('', true);
      } else {
        resourceError(true);
      }
    }

    final factory = nativeGuardFactory;
    if (factory != null) {
      _guard = factory(failure);
    } else if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      if (controller is! AndroidWebViewController ||
          delegate.platform is! AndroidNavigationDelegate) {
        throw StateError('Android request guard unavailable');
      }
      final client =
          (delegate.platform as AndroidNavigationDelegate).androidWebViewClient;
      _guard = CursorSignInNativeGuard(
        view: controller.webViewIdentifier,
        client: client.pigeon_instanceManager.getIdentifier(client)!,
        onFailure: failure,
      );
    }
    await _guard?.attach();
  }

  @override
  Future<void> load(Uri url) {
    _loadStarted = true;
    _mainDocument = url;
    return _controller.loadRequest(url);
  }

  @override
  Future<String?> currentUrl() => _controller.currentUrl();
  @override
  Future<String?> probe(Uri? url) async {
    if (_guard != null && !await _guard!.check()) return null;
    final token = await probeCursorSessionToken(
      extraUrl: url,
      cookieManager: _cookies,
    );
    if (_guard != null && !await _guard!.check()) return null;
    return token;
  }

  @override
  Future<bool> wipe() => wipeCursorWebViewSession(_cookies);
  @override
  Future<void> stop({bool requireHealthy = false}) {
    final previous = _stopping;
    if (previous != null) return previous;
    final work = Future<void>.sync(() => _stopDocument(requireHealthy));
    _stopping = work;
    unawaited(
      work.then<void>(
        (_) {},
        onError: (Object _, StackTrace _) {
          if (identical(_stopping, work)) _stopping = null;
        },
      ),
    );
    return work;
  }

  Future<void> _stopDocument(bool requireHealthy) async {
    _retiring = true;
    if (_loadStarted && _blanked?.isCompleted != true) {
      await _guard?.beginRetirement();
      final blanked = _blanked = Completer<void>();
      try {
        await _controller.loadRequest(Uri.parse('about:blank'));
      } catch (_) {
        // The failed request supplies no finish event. A subsequent retirement
        // must issue a fresh request, while the shared jar remains fenced.
        _blanked = null;
        rethrow;
      }
      await blanked.future;
    }
    if (requireHealthy && _guard != null && !await _guard!.check()) {
      throw StateError('Sign-in document failed');
    }
    await _guard?.detach();
  }

  @override
  Widget build() => WebViewWidget(controller: _controller);
}

/// Dashboard compatibility login, not OAuth. Only a captured token is success.
class CursorPlanSignInScreen extends StatefulWidget {
  const CursorPlanSignInScreen({
    super.key,
    this.initialUrl = defaultSignInUrl,
    this.cookieManager,
    this.pollInterval = const Duration(seconds: 1),
    this.browserFactory,
  });

  static const defaultSignInUrl = 'https://cursor.com/dashboard';
  // Local platform work should settle quickly; network pages get longer.
  static const stageTimeout = Duration(seconds: 15);
  static const pageTimeout = Duration(seconds: 30);
  // Pause repeated jar reads after two minutes; longer password/MFA entry stays
  // editable and Check again resumes polling without restarting authentication.
  static const waitingTimeout = Duration(minutes: 2);

  static Future<String?> open(BuildContext context) {
    return Navigator.of(context).push<String>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (context) => const CursorPlanSignInScreen(),
      ),
    );
  }

  final String initialUrl;
  final WebViewCookieManager? cookieManager;
  final Duration pollInterval;
  final CursorSignInBrowser Function()? browserFactory;

  @override
  State<CursorPlanSignInScreen> createState() => _CursorPlanSignInScreenState();
}

class _Attempt {
  _Attempt(this.ready);
  Future<void> Function() ready;
  Future<void> pending = Future<void>.value();
  Future<void>? _release;
  CursorSignInBrowser? browser;
  Timer? poll;
  Timer? page;
  Timer? waiting;
  bool active = true;
  bool probing = false;
  bool finishing = false;
  bool paused = false;
  bool loaded = false;
  bool _clean = false;

  Future<void> retire({bool clean = false}) {
    active = false;
    poll?.cancel();
    page?.cancel();
    waiting?.cancel();
    _clean = _clean || clean;
    final previous = _release;
    if (previous != null) return previous;
    final work = _cleanup();
    _release = work;
    unawaited(
      work.then<void>(
        (_) {},
        onError: (Object _, StackTrace _) {
          // Retry/reopen may retry retirement while the barrier stays closed.
          if (identical(_release, work)) _release = null;
        },
      ),
    );
    return work;
  }

  Future<void> _cleanup() async {
    await pending;
    await ready();
    final current = browser;
    if (!_clean && current != null) {
      await current.stop();
      try {
        await current.wipe();
      } catch (_) {
        // Every new attempt independently verifies its startup wipe.
      }
    }
    browser = null;
    pending = Future<void>.value();
    ready = () async {};
  }
}

class _CursorPlanSignInScreenState extends State<CursorPlanSignInScreen> {
  // A timed-out native Future is not cancelled. Keep the shared jar leased until
  // old work settles and its WebView stops, including across close/reopen.
  static _Attempt? _jarAvailable;
  _Attempt? _attempt;
  String _message = '';
  bool _closed = false;
  bool _helpOpen = false;

  @override
  void initState() {
    super.initState();
    _retry();
  }

  bool _active(_Attempt a) =>
      mounted && !_closed && identical(a, _attempt) && a.active;

  void _retry() {
    if (_closed) return;
    final previous = _attempt;
    if (previous != null) _retire(previous);
    final a = _Attempt(_jarAvailable?.retire ?? () async {});
    _jarAvailable = a;
    _attempt = a;
    _message = 'Preparing a fresh Cursor sign-in…';
    unawaited(_start(a));
  }

  Future<T> _step<T>(_Attempt a, Future<T> Function() action) async {
    if (!_active(a)) throw StateError('Retired sign-in');
    final work = Future<T>.sync(action);
    a.pending = work.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    final result = await work.timeout(CursorPlanSignInScreen.stageTimeout);
    if (!_active(a)) throw StateError('Retired sign-in');
    return result;
  }

  Future<void> _start(_Attempt a) async {
    var stage = 'close the previous sign-in';
    try {
      await _step(a, a.ready);
      stage = 'prepare the sign-in browser';
      a.browser =
          widget.browserFactory?.call() ??
          WebViewCursorSignInBrowser(cookies: widget.cookieManager);
      await _step(
        a,
        () => a.browser!.configure(
          navigate: (url, mainFrame) => _navigate(a, url, mainFrame),
          pageStarted: () => _pageStarted(a),
          pageFinished: () {
            if (!_active(a) || a.finishing) return;
            a.page?.cancel();
            unawaited(_probe(a));
          },
          resourceError: (mainFrame) {
            if (mainFrame && !a.finishing) {
              _fail(a, 'Could not load the sign-in page.');
            }
          },
        ),
      );
      stage = 'clear the previous Cursor session';
      if (!await _step(a, a.browser!.wipe)) {
        throw StateError('Unverified wipe');
      }
      final url = Uri.tryParse(widget.initialUrl);
      if (url == null || !isAllowedCursorSignInUrl(url)) {
        _fail(a, 'This sign-in address is not supported.');
        return;
      }
      stage = 'open the sign-in page';
      _pageStarted(a);
      await _step(a, () => a.browser!.load(url));
      a.loaded = true;
      setState(() => _message = 'Sign in to the same Cursor account.');
      _watch(a);
    } catch (_) {
      _fail(a, 'Could not $stage.');
    }
  }

  bool _navigate(_Attempt a, String raw, bool mainFrame) {
    if (!_active(a) || a.finishing) return false;
    final url = Uri.tryParse(raw);
    if (url != null && isGoogleCursorAuthorizationUrl(url)) {
      _fail(
        a,
        'Google sign-in requires a supported browser. '
        'Use same-account email when offered, or Cancel and reopen. '
        'Help explains Advanced paste.',
      );
      return false;
    }
    if (!mainFrame) return true;
    if (url != null && isAllowedCursorSignInUrl(url)) return true;
    _fail(a, 'This sign-in redirect is not supported.');
    return false;
  }

  void _pageStarted(_Attempt a) {
    if (!_active(a) || a.finishing) return;
    // Redirects share a deadline; a redirect loop must not extend it forever.
    if (a.page?.isActive == true) return;
    a.page = Timer(CursorPlanSignInScreen.pageTimeout, () {
      _fail(a, 'The sign-in page did not finish loading.');
    });
  }

  void _watch(_Attempt a) {
    if (!_active(a) || a.finishing) return;
    a.paused = false;
    a.poll?.cancel();
    a.waiting?.cancel();
    a.poll = Timer.periodic(widget.pollInterval, (_) => unawaited(_probe(a)));
    a.waiting = Timer(CursorPlanSignInScreen.waitingTimeout, () {
      if (!_active(a) || a.finishing) return;
      a.paused = true;
      a.poll?.cancel();
      setState(() {
        _message =
            'Still signing in? Continue password or MFA entry, then tap '
            'Check again. No session has been captured. Retry starts over.';
      });
    });
  }

  Future<void> _probe(_Attempt a) async {
    if (!_active(a) ||
        !a.loaded ||
        a.probing ||
        a.finishing ||
        a.paused ||
        _helpOpen) {
      return;
    }
    a.probing = true;
    var stage = 'check the sign-in page';
    try {
      final current = await _step(a, a.browser!.currentUrl);
      if (current == null) throw StateError('Unreadable sign-in location');
      final page = Uri.tryParse(current);
      if (page == null) throw StateError('Unreadable sign-in location');
      if (!_navigate(a, current, true)) return;
      stage = 'read the Cursor session';
      final raw = await _step(a, () => a.browser!.probe(page));
      final token = raw == null ? null : normalizeCursorSessionToken(raw);
      if (token == null || _helpOpen || a.paused) return;
      a.finishing = true;
      _cancelTimers(a);
      setState(() => _message = 'Securing the captured session…');
      stage = 'clear the sign-in browser';
      await _step(a, () => a.browser!.stop(requireHealthy: true));
      if (!await _step(a, a.browser!.wipe)) {
        throw StateError('Unverified wipe');
      }
      _closed = true;
      _retire(a, clean: true);
      Navigator.of(context).pop(token);
    } catch (_) {
      _fail(a, 'Could not $stage.');
    } finally {
      a.probing = false;
    }
  }

  void _cancelTimers(_Attempt a) {
    a.poll?.cancel();
    a.page?.cancel();
    a.waiting?.cancel();
  }

  void _fail(_Attempt a, String message) {
    if (!_active(a)) return;
    _retire(a);
    setState(() => _message = '$message Retry, Cancel, or open Help.');
  }

  void _retire(_Attempt a, {bool clean = false}) {
    unawaited(
      a.retire(clean: clean).then<void>((_) {
        // A settled lease must not retain its browser, state or async zone.
        // Only its current owner may release it; unfinished work stays fenced.
        if (identical(_jarAvailable, a)) _jarAvailable = null;
      }, onError: (Object _, StackTrace _) {}),
    );
  }

  void _cancel() {
    if (_closed) return;
    _closed = true;
    _retire(_attempt!);
    Navigator.of(context).pop();
  }

  Future<void> _help() async {
    final a = _attempt!;
    if (_closed || _helpOpen || (a.active && a.finishing)) return;
    _helpOpen = true;
    try {
      await showDialog<void>(
        context: context,
        builder:
            (context) => AlertDialog(
              title: const Text('Cursor sign-in recovery'),
              content: const SingleChildScrollView(
                child: Text(
                  'Google does not allow this embedded browser for authorization. '
                  'Use email for the same Cursor account when offered. '
                  'Cancel and reopen to choose another offered method.\n\n'
                  'For Advanced paste, Cancel to Providers, open About Cursor plan '
                  'sign-in (?), then Advanced paste. Use the session cookie from '
                  'the same account. Never share it.\n\n'
                  'Retry clears the in-app session and starts over. Cancelling or '
                  'failing a replacement keeps the previously saved connection.',
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Close'),
                ),
              ],
            ),
      );
    } finally {
      _helpOpen = false;
    }
  }

  @override
  void dispose() {
    _closed = true;
    _retire(_attempt!);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final a = _attempt!;
    return PopScope<String>(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) {
          _closed = true;
          _retire(_attempt!);
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Cursor plan sign-in'),
          leading: IconButton(
            tooltip: 'Cancel',
            onPressed: _cancel,
            icon: const Icon(Icons.close),
          ),
          actions: [
            IconButton(
              tooltip: 'Help',
              onPressed: a.finishing && a.active ? null : _help,
              icon: const Icon(Icons.help_outline),
            ),
          ],
        ),
        body: Column(
          children: [
            Padding(padding: const EdgeInsets.all(16), child: Text(_message)),
            Wrap(
              spacing: 12,
              children: [
                TextButton(
                  onPressed: () => setState(_retry),
                  child: const Text('Retry'),
                ),
                if (a.active && a.paused)
                  TextButton(
                    onPressed: () {
                      if (!_active(a) || a.finishing) return;
                      _watch(a);
                      setState(
                        () => _message = 'Checking for a Cursor session…',
                      );
                      unawaited(_probe(a));
                    },
                    child: const Text('Check again'),
                  ),
              ],
            ),
            if (a.active && a.loaded && !a.finishing)
              Expanded(child: a.browser!.build()),
          ],
        ),
      ),
    );
  }
}
