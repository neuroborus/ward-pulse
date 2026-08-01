import 'package:flutter_test/flutter_test.dart';
import 'package:ward_pulse_phone/providers/provider_connection.dart';
import 'package:ward_pulse_phone/settings/alert_threshold_preferences.dart';

void main() {
  test('defaults are opt-in off', () {
    const prefs = AlertThresholdPreferences();
    expect(prefs.today.isEnabled, isFalse);
    expect(prefs.hasEnabledRules, isFalse);
    expect(
      prefs.forConnection(ProviderConnections.codexPlan).isEnabled,
      isFalse,
    );
  });

  test('hasEnabledRules is true when any budget or connection rule is set', () {
    expect(
      const AlertThresholdPreferences(
        today: AlertPercentThreshold(at: 80),
      ).hasEnabledRules,
      isTrue,
    );
    expect(
      const AlertThresholdPreferences()
          .withConnection(
            ProviderConnections.codexPlan,
            const ConnectionAlertThresholds(
              plan: AlertPercentThreshold(at: 100),
            ),
          )
          .hasEnabledRules,
      isTrue,
    );
  });

  test('round-trips JSON and drops empty connection rules', () {
    final prefs = AlertThresholdPreferences(
      today: const AlertPercentThreshold(at: 80),
      connections: {
        ProviderConnections
            .codexPlan
            .storageKey: const ConnectionAlertThresholds(
          plan: AlertPercentThreshold(at: 70),
        ),
        ProviderConnections.claudePlan.storageKey:
            const ConnectionAlertThresholds(),
      },
    );

    final decoded = AlertThresholdPreferences.decode(prefs.encode());
    expect(decoded.today.at, 80);
    expect(decoded.forConnection(ProviderConnections.codexPlan).plan.at, 70);
    expect(
      decoded.connections.containsKey(
        ProviderConnections.claudePlan.storageKey,
      ),
      isFalse,
    );
  });

  test('reads legacy warnAt / criticalAt as a single at threshold', () {
    final decoded = AlertThresholdPreferences.decode(
      '{"today":{"warnAt":80,"criticalAt":100},"week":{},"month":{},'
      '"connections":{}}',
    );
    expect(decoded.today.at, 80);

    final criticalOnly = AlertPercentThreshold.fromJson({'criticalAt': 100});
    expect(criticalOnly.at, 100);
  });

  test('encode omits disabled thresholds', () {
    const prefs = AlertThresholdPreferences(
      today: AlertPercentThreshold(at: 80),
    );
    expect(prefs.encode(), contains('"today":{"at":80}'));
    expect(prefs.encode(), contains('"week":{}'));
    expect(prefs.encode(), isNot(contains('warnAt')));
    expect(prefs.encode(), isNot(contains('criticalAt')));
  });

  test('remaining stops map to used percent for storage', () {
    expect(alertRemainingToUsed(null), isNull);
    expect(alertRemainingToUsed(50), 50);
    expect(alertRemainingToUsed(30), 70);
    expect(alertRemainingToUsed(20), 80);
    expect(alertRemainingToUsed(10), 90);
    expect(alertRemainingToUsed(0), 100);

    expect(alertUsedToRemaining(null), isNull);
    expect(alertUsedToRemaining(70), 30);
    expect(alertUsedToRemaining(100), 0);
    expect(alertUsedToRemaining(75), isNull);
  });

  test('withConnection removes disabled rules', () {
    final enabled = const AlertThresholdPreferences().withConnection(
      ProviderConnections.cursorPlan,
      const ConnectionAlertThresholds(
        purchased: AlertPercentThreshold(at: 100),
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
