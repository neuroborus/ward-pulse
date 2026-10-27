import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:ward_pulse_phone/providers/cursor_webview_cookies.dart';

void main() {
  group('ensureCursorSessionCookieCleared', () {
    test('succeeds when probe is empty after clear', () async {
      var clears = 0;
      final wiped = await ensureCursorSessionCookieCleared(
        clear: () async {
          clears++;
        },
        probe: () async => null,
      );
      expect(wiped, isTrue);
      expect(clears, 1);
    });

    test('retries once when a stale token remains', () async {
      var clears = 0;
      final wiped = await ensureCursorSessionCookieCleared(
        clear: () async {
          clears++;
        },
        probe: () async => clears < 2 ? 'stale-token' : null,
      );
      expect(wiped, isTrue);
      expect(clears, 2);
    });

    test('fails when the token survives both clears', () async {
      var clears = 0;
      final wiped = await ensureCursorSessionCookieCleared(
        clear: () async {
          clears++;
        },
        probe: () async => 'stale-token',
      );
      expect(wiped, isFalse);
      expect(clears, 2);
    });

    test('fails closed when probe throws', () async {
      final wiped = await ensureCursorSessionCookieCleared(
        clear: () async {},
        probe: () async => throw StateError('cookie read failed'),
      );
      expect(wiped, isFalse);
    });
  });

  group('isCursorSessionCookieHost', () {
    test('allows cursor.com https hosts only', () {
      expect(
        isCursorSessionCookieHost(Uri.parse('https://cursor.com/dashboard')),
        isTrue,
      );
      expect(
        isCursorSessionCookieHost(Uri.parse('https://www.cursor.com/')),
        isTrue,
      );
      expect(
        isCursorSessionCookieHost(
          Uri.parse('https://authenticator.cursor.sh/'),
        ),
        isFalse,
      );
      expect(
        isCursorSessionCookieHost(Uri.parse('https://evil.com/')),
        isFalse,
      );
      expect(
        isCursorSessionCookieHost(Uri.parse('http://cursor.com/')),
        isFalse,
      );
    });
  });

  const identities = [
    'accounts.x.ai',
    'accounts.spacex.ai',
    'auth.x.ai',
    'auth.grok.com',
    'auth.grokusercontent.com',
    'auth.grokipedia.com',
  ];
  for (final host in identities) {
    test('$host navigation is exact HTTPS and never a cookie source', () async {
      final previousPlatform = debugDefaultTargetPlatformOverride;
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = previousPlatform);
      final cookies = _RecordingCookies();
      final url = Uri.https(host, '/login');
      expect(isAllowedCursorSignInUrl(url), isTrue);
      for (final rejected in [
        Uri.parse('http://$host/login'),
        Uri.parse('ftp://$host/login'),
        Uri.https('child.$host', '/'),
        Uri.https('$host.example', '/'),
        Uri.https('prefix$host', '/'),
        Uri.parse('https://$host@evil.example/'),
      ]) {
        expect(
          isAllowedCursorSignInUrl(rejected),
          isFalse,
          reason: '$rejected',
        );
        expect(isCursorSessionCookieHost(rejected), isFalse);
        expect(
          await readWebViewCookieHeader(rejected, cookieManager: cookies),
          isNull,
        );
      }
      expect(isCursorSessionCookieHost(url), isFalse);
      expect(
        await readWebViewCookieHeader(url, cookieManager: cookies),
        isNull,
      );
      expect(cookies.reads, isEmpty);
      expect(
        await probeCursorSessionToken(extraUrl: url, cookieManager: cookies),
        isNull,
      );
      expect(cookies.reads.map((uri) => uri.toString()), [
        'https://cursor.com/',
        'https://www.cursor.com/',
      ]);
    });
  }

  group('isAllowedCursorSignInUrl', () {
    test(
      'retains non-Google compatibility and rejects Google authorization',
      () {
        expect(
          isAllowedCursorSignInUrl(Uri.parse('https://cursor.com/dashboard')),
          isTrue,
        );
        expect(
          isAllowedCursorSignInUrl(
            Uri.parse('https://authenticator.cursor.sh/login'),
          ),
          isTrue,
        );
        expect(
          isAllowedCursorSignInUrl(Uri.parse('https://accounts.google.com/o')),
          isFalse,
        );
        expect(
          isAllowedCursorSignInUrl(Uri.parse('https://accounts.youtube.com/')),
          isFalse,
        );
        expect(
          isAllowedCursorSignInUrl(
            Uri.parse('https://www.google.com/accounts/SetOSID'),
          ),
          isFalse,
        );
        expect(
          isAllowedCursorSignInUrl(Uri.parse('https://github.com/login')),
          isTrue,
        );
        expect(
          isAllowedCursorSignInUrl(Uri.parse('https://www.recaptcha.net/')),
          isTrue,
        );
      },
    );

    test('blocks unrelated https hosts and non-https', () {
      expect(
        isAllowedCursorSignInUrl(Uri.parse('https://evil.example/login')),
        isFalse,
      );
      expect(
        isAllowedCursorSignInUrl(Uri.parse('http://cursor.com/dashboard')),
        isFalse,
      );
      expect(
        isAllowedCursorSignInUrl(Uri.parse('https://notcursor.com/')),
        isFalse,
      );
    });
  });
}

class _RecordingCookies implements WebViewCookieManager {
  final reads = <Uri>[];

  @override
  Future<List<WebViewCookie>> getCookies({required Uri domain}) async {
    reads.add(domain);
    return [];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
