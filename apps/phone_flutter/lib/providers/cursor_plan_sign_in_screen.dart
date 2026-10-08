import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import 'cursor_webview_cookies.dart';

/// Fallback Chrome UA when the platform does not expose a WebView default.
const _chromeMobileUserAgent =
    'Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/121.0.0.0 Mobile Safari/537.36';

/// Full-screen Cursor dashboard sign-in (WebView session cookie capture).
///
/// Not OAuth — reads `WorkosCursorSessionToken` after the user signs in on
/// cursor.com, then returns the token to the caller.
class CursorPlanSignInScreen extends StatefulWidget {
  const CursorPlanSignInScreen({
    super.key,
    this.initialUrl = defaultSignInUrl,
    this.cookieManager,
    this.pollInterval = const Duration(seconds: 1),
  });

  static const defaultSignInUrl = 'https://cursor.com/dashboard';

  /// Opens the sign-in route. Returns the session token, or null if cancelled.
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

  @override
  State<CursorPlanSignInScreen> createState() => _CursorPlanSignInScreenState();
}

class _CursorPlanSignInScreenState extends State<CursorPlanSignInScreen> {
  late final WebViewController _controller;
  late final WebViewCookieManager _cookieManager;
  Timer? _poll;
  var _completing = false;
  var _probeInFlight = false;
  String? _startupError;

  @override
  void initState() {
    super.initState();
    _cookieManager = widget.cookieManager ?? WebViewCookieManager();
    _controller =
        WebViewController()
          ..setJavaScriptMode(JavaScriptMode.unrestricted)
          ..setNavigationDelegate(
            NavigationDelegate(
              onNavigationRequest: (request) {
                // Google/reCAPTCHA load many subframes; blocking them hangs
                // password / SMS steps. Cookie capture stays on cursor.com.
                if (!request.isMainFrame) {
                  return NavigationDecision.navigate;
                }
                final uri = Uri.tryParse(request.url);
                if (uri == null) {
                  return NavigationDecision.prevent;
                }
                if (uri.scheme == 'about') {
                  return NavigationDecision.navigate;
                }
                if (isAllowedCursorSignInUrl(uri)) {
                  return NavigationDecision.navigate;
                }
                return NavigationDecision.prevent;
              },
              onPageFinished: (_) {
                _enableAndroidThirdPartyCookies();
                unawaited(_probeCookies());
              },
            ),
          );
    unawaited(_configureAndStart());
  }

  Future<void> _configureAndStart() async {
    await _controller.setUserAgent(await _signInUserAgent());
    _enableAndroidThirdPartyCookies();
    if (!mounted) {
      return;
    }
    await _start();
  }

  /// Prefer the system WebView UA with the `; wv` marker removed — Google
  /// often stalls embedded WebViews that advertise themselves as such.
  Future<String> _signInUserAgent() async {
    try {
      final current = await _controller.getUserAgent();
      if (current != null && current.trim().isNotEmpty) {
        return current.replaceAll('; wv', '');
      }
    } catch (_) {}
    return _chromeMobileUserAgent;
  }

  void _enableAndroidThirdPartyCookies() {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return;
    }
    final platformController = _controller.platform;
    final platformCookies = _cookieManager.platform;
    if (platformController is! AndroidWebViewController ||
        platformCookies is! AndroidWebViewCookieManager) {
      return;
    }
    unawaited(
      platformCookies
          .setAcceptThirdPartyCookies(platformController, true)
          .catchError((Object _) {}),
    );
  }

  Future<void> _start() async {
    final wiped = await wipeCursorWebViewSession(_cookieManager);
    if (!mounted) {
      return;
    }
    if (!wiped) {
      setState(() {
        _startupError =
            'Could not clear a previous Cursor session on this phone. '
            'Close and try again, or use Advanced paste.';
      });
      return;
    }
    await _controller.loadRequest(Uri.parse(widget.initialUrl));
    if (!mounted) {
      return;
    }
    _poll = Timer.periodic(
      widget.pollInterval,
      (_) => unawaited(_probeCookies()),
    );
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _probeCookies() async {
    if (!mounted || _completing || _probeInFlight || _startupError != null) {
      return;
    }
    _probeInFlight = true;
    try {
      final currentUrl = await _controller.currentUrl();
      final pageUri = currentUrl == null ? null : Uri.tryParse(currentUrl);
      final token = await probeCursorSessionToken(
        extraUrl: pageUri,
        cookieManager: _cookieManager,
      );
      if (token == null || !mounted || _completing) {
        return;
      }
      _completing = true;
      _poll?.cancel();
      try {
        await _cookieManager.clearCookies();
      } catch (_) {}
      if (mounted) {
        Navigator.of(context).pop(token);
      }
    } finally {
      _probeInFlight = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final error = _startupError;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Cursor sign-in'),
        leading: IconButton(
          tooltip: 'Cancel',
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.close),
        ),
      ),
      body:
          error != null
              ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(error, textAlign: TextAlign.center),
                ),
              )
              : WebViewWidget(controller: _controller),
    );
  }
}
