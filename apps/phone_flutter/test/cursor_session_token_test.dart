import 'package:flutter_test/flutter_test.dart';
import 'package:ward_pulse_phone/providers/cursor_session_token.dart';

const _sampleToken =
    'user_01ABC::eyJhbGciOiJSUzI1NiJ9.payload.signature_padding==';

void main() {
  group('parseCursorSessionTokenFromCookieHeader', () {
    test('extracts WorkosCursorSessionToken', () {
      expect(
        parseCursorSessionTokenFromCookieHeader(
          'foo=bar; WorkosCursorSessionToken=user%3A%3A${'x' * 40}; other=1',
        ),
        'user::${'x' * 40}',
      );
    });

    test('returns null when cookie is missing', () {
      expect(
        parseCursorSessionTokenFromCookieHeader('session=other; foo=bar'),
        isNull,
      );
    });

    test('returns null for blank values', () {
      expect(
        parseCursorSessionTokenFromCookieHeader(
          'WorkosCursorSessionToken=   ; foo=bar',
        ),
        isNull,
      );
    });

    test('keeps undecodable values as trimmed raw text', () {
      expect(
        parseCursorSessionTokenFromCookieHeader(
          'WorkosCursorSessionToken=$_sampleToken',
        ),
        _sampleToken,
      );
    });

    test('preserves JWT padding after the first equals', () {
      const encoded =
          'user_01ABC%3A%3AeyJhbGciOiJSUzI1NiJ9.payload.signature_padding==';
      expect(
        parseCursorSessionTokenFromCookieHeader(
          'foo=1; WorkosCursorSessionToken=$encoded; bar=2',
        ),
        _sampleToken,
      );
    });

    test('rejects short placeholder values', () {
      expect(
        parseCursorSessionTokenFromCookieHeader(
          'WorkosCursorSessionToken=short',
        ),
        isNull,
      );
    });
  });

  group('normalizeCursorSessionToken', () {
    test('accepts a decoded session token', () {
      expect(normalizeCursorSessionToken(_sampleToken), _sampleToken);
    });

    test('rejects short values', () {
      expect(normalizeCursorSessionToken('short'), isNull);
    });
  });

  group('parseCursorSessionTokenFromCookies', () {
    test('matches cookie name exactly', () {
      expect(
        parseCursorSessionTokenFromCookies([
          (name: 'WorkosCursorSessionToken', value: _sampleToken),
          (name: 'other', value: 'x'),
        ]),
        _sampleToken,
      );
    });

    test('ignores similarly named cookies', () {
      expect(
        parseCursorSessionTokenFromCookies([
          (name: 'WorkosCursorSessionTokenX', value: _sampleToken),
        ]),
        isNull,
      );
    });
  });
}
