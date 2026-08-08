import 'package:flutter_test/flutter_test.dart';
import 'package:ward_pulse_phone/providers/provider_connection.dart';
import 'package:ward_pulse_phone/settings/alert_threshold_preferences.dart';

void main() {
  test('defaults are opt-in off', () {
    const prefs = AlertThresholdPreferences();
    expect(prefs.hasEnabledRules, isFalse);
    expect(
      prefs.forConnection(ProviderConnections.codexPlan).isEnabled,
      isFalse,
    );
  });

  test('hasEnabledRules is true when any connection rule is set', () {
    expect(
      const AlertThresholdPreferences()
          .withConnection(
            ProviderConnections.openAiPlatform,
            const ConnectionAlertThresholds(
              today: AlertPercentThreshold(at: 80),
            ),
          )
          .hasEnabledRules,
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
      '{"connections":{"openai.plan":{"plan":{"warnAt":80,"criticalAt":100}}}}',
    );
    expect(decoded.forConnection(ProviderConnections.codexPlan).plan.at, 80);

    final criticalOnly = AlertPercentThreshold.fromJson({'criticalAt': 100});
    expect(criticalOnly.at, 100);
  });

  test('drops global budget rules saved before they moved to connections', () {
    final decoded = AlertThresholdPreferences.decode(
      '{"today":{"at":80},"week":{},"month":{},"connections":{}}',
    );

    expect(decoded.hasEnabledRules, isFalse);
  });

  test('encode omits disabled thresholds', () {
    final prefs = const AlertThresholdPreferences().withConnection(
      ProviderConnections.openAiPlatform,
      const ConnectionAlertThresholds(today: AlertPercentThreshold(at: 80)),
    );
    expect(prefs.encode(), contains('"today":{"at":80}'));
    expect(prefs.encode(), contains('"week":{}'));
    expect(prefs.encode(), isNot(contains('warnAt')));
    expect(prefs.encode(), isNot(contains('criticalAt')));
  });

  test('a budget limit alone survives storage', () {
    // A limit without a percentage is still a setting worth keeping: the user
    // may add the threshold later, and withConnection drops disabled rules.
    final prefs = const AlertThresholdPreferences().withConnection(
      ProviderConnections.openAiPlatform,
      const ConnectionAlertThresholds(budget: ConnectionBudget(month: 5000)),
    );

    final decoded = AlertThresholdPreferences.decode(prefs.encode());
    final saved = decoded.forConnection(ProviderConnections.openAiPlatform);

    expect(saved.budget.month, 5000);
    // Stored, but not an alert: the Providers bell must stay quiet.
    expect(saved.isEnabled, isTrue);
    expect(saved.hasAlertRules, isFalse);
  });

  test('clearing every limit drops the rule', () {
    final prefs = const AlertThresholdPreferences().withConnection(
      ProviderConnections.openAiPlatform,
      const ConnectionAlertThresholds(),
    );

    expect(prefs.hasEnabledRules, isFalse);
    expect(prefs.connections, isEmpty);
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
