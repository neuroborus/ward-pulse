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

  test('what it says is the family and the window, and nothing else', () {
    const recovery = (
      accountId: 'claude-local',
      provider: 'claude',
      allowanceId: 'claude-weekly',
      label: 'Weekly plan',
      resetsAt: null,
    );

    final title = recoveryNotificationTitle(recovery);

    expect(title, 'Claude · Weekly plan');
    // The rule from SECURITY_MODEL.md, read off the text a locked screen shows.
    expect(title, isNot(contains(recovery.accountId)));
    expect(title, isNot(contains(recovery.allowanceId)));
    expect(recoveryNotificationBody, 'Usable again.');
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
