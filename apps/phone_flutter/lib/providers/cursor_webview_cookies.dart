import 'package:flutter/foundation.dart';
import 'package:webview_flutter/webview_flutter.dart';
// Android WebViewCookieManager.getCookies splits values on every '=', which
// truncates JWT padding. Read the raw Cookie header string instead.
// ignore: implementation_imports
import 'package:webview_flutter_android/src/android_webkit.g.dart'
    as android_webview;

import 'cursor_session_token.dart';

/// Hosts that may hold [cursorSessionCookieName] after dashboard login.
final _cursorCookieProbeUris = <Uri>[
  Uri.parse('https://cursor.com/'),
  Uri.parse('https://www.cursor.com/'),
];

/// Exact IdP hosts not covered by the apex suffixes below.
const _cursorSignInIdpHosts = <String>{
  'accounts.youtube.com',
  'github.com',
  'www.github.com',
  'challenges.cloudflare.com',
};

bool _hostMatches(String host, String apex) =>
    host == apex || host.endsWith('.$apex');

/// Session cookie is scoped to cursor.com (capture only these hosts).
bool isCursorSessionCookieHost(Uri url) {
  if (!url.isScheme('https') || url.host.isEmpty) {
    return false;
  }
  return _hostMatches(url.host.toLowerCase(), 'cursor.com');
}

/// Navigation allowlist for the Cursor sign-in WebView.
///
/// Google login hops across several Google apexes; cookie capture stays on
/// [isCursorSessionCookieHost] only.
bool isAllowedCursorSignInUrl(Uri url) {
  if (!url.isScheme('https') || url.host.isEmpty) {
    return false;
  }
  final host = url.host.toLowerCase();
  if (_hostMatches(host, 'cursor.com') || _hostMatches(host, 'cursor.sh')) {
    return true;
  }
  if (_cursorSignInIdpHosts.contains(host)) {
    return true;
  }
  return _hostMatches(host, 'google.com') ||
      _hostMatches(host, 'googleusercontent.com') ||
      _hostMatches(host, 'gstatic.com') ||
      _hostMatches(host, 'googleapis.com') ||
      _hostMatches(host, 'recaptcha.net') ||
      _hostMatches(host, 'microsoftonline.com') ||
      _hostMatches(host, 'workos.com');
}

String _cookieProbeKey(Uri url) => '${url.scheme}://${url.host}';

/// Clears then verifies no session cookie remains (retries once).
///
/// Used by disconnect and before Sign in so a failed wipe cannot silently
/// re-bind a stale `WorkosCursorSessionToken`.
Future<bool> ensureCursorSessionCookieCleared({
  required Future<void> Function() clear,
  required Future<String?> Function() probe,
  int attempts = 2,
}) async {
  for (var i = 0; i < attempts; i++) {
    try {
      await clear();
    } catch (_) {
      // Verification below decides success.
    }
    try {
      if (await probe() == null) {
        return true;
      }
    } catch (_) {
      return false;
    }
  }
  return false;
}

/// Wipes the shared WebView jar and confirms the Cursor session cookie is gone.
Future<bool> wipeCursorWebViewSession([
  WebViewCookieManager? cookieManager,
]) {
  final manager = cookieManager ?? WebViewCookieManager();
  return ensureCursorSessionCookieCleared(
    clear: manager.clearCookies,
    probe: () => probeCursorSessionToken(cookieManager: manager),
  );
}

/// Reads a `Cookie` request header for [url] from the shared WebView jar.
Future<String?> readWebViewCookieHeader(
  Uri url, {
  WebViewCookieManager? cookieManager,
}) async {
  if (!isCursorSessionCookieHost(url)) {
    return null;
  }
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    final header = await android_webview.CookieManager.instance.getCookies(
      url.toString(),
    );
    if (header == null || header.trim().isEmpty) {
      return null;
    }
    return header;
  }

  final manager = cookieManager ?? WebViewCookieManager();
  final cookies = await manager.getCookies(domain: url);
  if (cookies.isEmpty) {
    return null;
  }
  return [
    for (final cookie in cookies) '${cookie.name}=${cookie.value}',
  ].join('; ');
}

/// Probes Cursor session hosts (and optional allowlisted [extraUrl]) for the token.
Future<String?> probeCursorSessionToken({
  Uri? extraUrl,
  WebViewCookieManager? cookieManager,
}) async {
  final seen = <String>{};
  for (final url in [
    ..._cursorCookieProbeUris,
    if (extraUrl != null && isCursorSessionCookieHost(extraUrl)) extraUrl,
  ]) {
    if (!seen.add(_cookieProbeKey(url))) {
      continue;
    }
    final header = await readWebViewCookieHeader(
      url,
      cookieManager: cookieManager,
    );
    if (header == null) {
      continue;
    }
    final token = parseCursorSessionTokenFromCookieHeader(header);
    if (token != null) {
      return token;
    }
  }
  return null;
}
