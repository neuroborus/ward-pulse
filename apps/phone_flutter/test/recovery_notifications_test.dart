import 'package:flutter_test/flutter_test.dart';
import 'package:ward_pulse_phone/sync/recovery_notifications.dart';

void main() {
  int idOf(String accountId, String allowanceId) => recoveryNotificationId((
    accountId: accountId,
    provider: 'claude',
    allowanceId: allowanceId,
    label: 'Weekly plan',
    resetsAt: null,
  ));

  test('a window keeps its id, so a second telling replaces the first', () {
    // The reporting order risks a repeat on purpose, and that is only harmless
    // while the id stays the same one — run after run, not just call after
    // call, which is why it is not a `hashCode`.
    expect(idOf('claude-local', 'weekly'), 2077179748);
  });

  test('two windows of one account do not share an id', () {
    expect(idOf('claude-local', 'weekly'), isNot(idOf('claude-local', 'five')));
  });

  test('one window name under two accounts does not collide', () {
    expect(
      idOf('claude-local', 'weekly'),
      isNot(idOf('codex-local', 'weekly')),
    );
  });
}
