/// Cookie name for Cursor dashboard session auth (`GET /api/usage-summary`).
const cursorSessionCookieName = 'WorkosCursorSessionToken';

/// Rejects empty/placeholder values; real session tokens are `sub::jwt`.
const _minCursorSessionTokenLength = 32;

/// Extracts [cursorSessionCookieName] from a `Cookie` request header string.
///
/// Values are URL-decoded. Returns null when missing, blank, or too short.
/// Uses the first `=` as the name/value separator so JWT padding is preserved.
String? parseCursorSessionTokenFromCookieHeader(String cookieHeader) {
  final cookies = <({String name, String value})>[];
  for (final part in cookieHeader.split(';')) {
    final trimmed = part.trim();
    if (trimmed.isEmpty) {
      continue;
    }
    final separator = trimmed.indexOf('=');
    if (separator <= 0) {
      continue;
    }
    cookies.add((
      name: trimmed.substring(0, separator).trim(),
      value: trimmed.substring(separator + 1).trim(),
    ));
  }
  return parseCursorSessionTokenFromCookies(cookies);
}

/// Extracts [cursorSessionCookieName] from name/value cookie pairs.
String? parseCursorSessionTokenFromCookies(
  Iterable<({String name, String value})> cookies,
) {
  for (final cookie in cookies) {
    if (cookie.name != cursorSessionCookieName) {
      continue;
    }
    final value = normalizeCursorSessionToken(cookie.value);
    if (value != null) {
      return value;
    }
  }
  return null;
}

/// Decodes and validates a pasted or captured session token value.
String? normalizeCursorSessionToken(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) {
    return null;
  }
  try {
    final decoded = Uri.decodeComponent(trimmed).trim();
    if (decoded.length < _minCursorSessionTokenLength) {
      return null;
    }
    return decoded;
  } on ArgumentError {
    return trimmed.length < _minCursorSessionTokenLength ? null : trimmed;
  }
}
