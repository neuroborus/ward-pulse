import 'package:flutter_test/flutter_test.dart';
import 'package:ward_pulse_phone/settings/recovery_notification_preferences.dart';

void main() {
  test('a phone that was never asked interrupts', () {
    // Unset is not "off": the reader has said nothing yet, and Android still
    // gates the post behind its own permission.
    expect(recoveryNotificationsFrom(null), isTrue);
  });

  test('only an explicit no turns it off', () {
    expect(recoveryNotificationsFrom('false'), isFalse);
    expect(recoveryNotificationsFrom('true'), isTrue);
    // Anything unreadable leans the way the unset store does.
    expect(recoveryNotificationsFrom('yes please'), isTrue);
  });
}
