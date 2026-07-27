import 'package:flutter_test/flutter_test.dart';
import 'package:ward_pulse_phone/providers/provider_connection.dart';
import 'package:ward_pulse_phone/settings/alert_threshold_preferences.dart';

void main() {
  test('defaults are opt-in off', () {
    const prefs = AlertThresholdPreferences();
    expect(prefs.today.isEnabled, isFalse);
    expect(
      prefs.forConnection(ProviderConnections.codexPlan).isEnabled,
      isFalse,
    );
  });

  test('round-trips JSON and drops empty connection rules', () {
    final prefs = AlertThresholdPreferences(
      today: const AlertPercentThreshold(warnAt: 80, criticalAt: 100),
      connections: {
        ProviderConnections
            .codexPlan
            .storageKey: const ConnectionAlertThresholds(
          plan: AlertPercentThreshold(warnAt: 70),
        ),
        ProviderConnections.claudePlan.storageKey:
            const ConnectionAlertThresholds(),
      },
    );

    final decoded = AlertThresholdPreferences.decode(prefs.encode());
    expect(decoded.today.warnAt, 80);
    expect(decoded.today.criticalAt, 100);
    expect(
      decoded.forConnection(ProviderConnections.codexPlan).plan.warnAt,
      70,
    );
    expect(
      decoded.connections.containsKey(
        ProviderConnections.claudePlan.storageKey,
      ),
      isFalse,
    );
  });

  test('normalized raises critical to match warn', () {
    const raw = AlertPercentThreshold(warnAt: 90, criticalAt: 50);
    expect(raw.normalized.criticalAt, 90);
  });

  test('withConnection removes disabled rules', () {
    final enabled = const AlertThresholdPreferences().withConnection(
      ProviderConnections.cursorPlan,
      const ConnectionAlertThresholds(
        purchased: AlertPercentThreshold(criticalAt: 100),
      ),
    );
    expect(
      enabled.forConnection(ProviderConnections.cursorPlan).isEnabled,
      isTrue,
    );

    final cleared = enabled.withConnection(
      ProviderConnections.cursorPlan,
      const ConnectionAlertThresholds(),
    );
    expect(
      cleared.connections.containsKey(
        ProviderConnections.cursorPlan.storageKey,
      ),
      isFalse,
    );
  });
}
