import 'package:flutter_test/flutter_test.dart';
import 'package:ward_pulse_phone/dashboard/dashboard_models.dart';
import 'package:ward_pulse_phone/settings/consumption_display_preferences.dart';
import 'package:ward_pulse_phone/settings/watch_ring_preferences.dart';
import 'package:ward_pulse_phone/sync/watch_sync_service.dart';
import 'package:ward_pulse_phone/settings/recovery_notification_preferences.dart';

void main() {
  test('the switch is the phone\'s alone, so other surfaces cannot lose it', () {
    final payload =
        WatchDashboardSummaryPayload.fromSnapshot(
          DashboardSnapshot.empty(generatedAt: DateTime.utc(2026, 8, 17)),
          const ConsumptionDisplayPreferences(),
          const WatchRingPreferences(),
        ).encode();

    // Reinstalling the watch app or re-adding the widget cannot reset a setting
    // they never carry: it lives in phone storage and travels nowhere.
    expect(payload, isNot(contains('recovery')));
    expect(payload, isNot(contains('notify')));
  });

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
