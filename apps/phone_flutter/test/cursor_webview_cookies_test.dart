import 'package:flutter_test/flutter_test.dart';
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
        isCursorSessionCookieHost(Uri.parse('https://authenticator.cursor.sh/')),
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

  group('isAllowedCursorSignInUrl', () {
    test('allows Cursor, authenticator, and known IdPs', () {
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
        isTrue,
      );
      expect(
        isAllowedCursorSignInUrl(Uri.parse('https://github.com/login')),
        isTrue,
      );
    });

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
