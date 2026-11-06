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

  test('retains sparse window intent through storage and connection edits', () {
    const windows = <String, AlertPercentThreshold>{
      'window/zero': AlertPercentThreshold(at: 0),
      'window/full': AlertPercentThreshold(at: 100),
      'window/custom': AlertPercentThreshold(at: 83),
      'temporarily-absent': AlertPercentThreshold(),
    };
    var prefs = const AlertThresholdPreferences()
        .withConnection(
          ProviderConnections.openAiPlatform,
          const ConnectionAlertThresholds(
            budget: ConnectionBudget(today: 2501, week: 9000, month: 20000),
            today: AlertPercentThreshold(at: 90),
          ),
        )
        .withConnection(
          ProviderConnections.codexPlan,
          const ConnectionAlertThresholds(planWindows: windows),
        );
    prefs = AlertThresholdPreferences.decode(prefs.encode());
    final saved = prefs.forConnection(ProviderConnections.codexPlan);
    expect(saved.hasAlertRules, isTrue);
    expect(saved.isEnabled, isTrue);
    expect(prefs.hasEnabledRules, isTrue);
    expect(saved.toJson()['planWindows'], {
      'window/zero': {'at': 0},
      'window/full': {'at': 100},
      'window/custom': {'at': 83},
      'temporarily-absent': <String, Object?>{},
    });
    expect(saved.planWindows.containsKey('inherited'), isFalse);

    // Unrelated edits must not rewrite unknown or temporarily absent IDs.
    prefs = prefs.withConnection(
      ProviderConnections.codexPlan,
      saved.copyWith(plan: const AlertPercentThreshold(at: 70)),
    );
    prefs = AlertThresholdPreferences.decode(prefs.encode());
    expect(
      prefs
          .forConnection(ProviderConnections.codexPlan)
          .toJson()['planWindows'],
      saved.toJson()['planWindows'],
    );
    expect(prefs.forConnection(ProviderConnections.openAiPlatform).toJson(), {
      'plan': {},
      'purchased': {},
      'today': {'at': 90},
      'week': {},
      'month': {},
      'budget': {'today': 2501, 'week': 9000, 'month': 20000},
    });

    final overrides = Map<String, AlertPercentThreshold>.of(saved.planWindows)
      ..remove('window/custom');
    prefs = prefs.withConnection(
      ProviderConnections.codexPlan,
      saved.copyWith(planWindows: overrides),
    );
    final inherited = AlertThresholdPreferences.decode(
      prefs.encode(),
    ).forConnection(ProviderConnections.codexPlan);
    expect(inherited.planWindows.containsKey('window/custom'), isFalse);
    expect(inherited.planWindows['temporarily-absent']!.isEnabled, isFalse);
  });

  test('Off-only windows are stored without routing to evaluation', () {
    final prefs = const AlertThresholdPreferences().withConnection(
      ProviderConnections.cursorPlan,
      const ConnectionAlertThresholds(
        planWindows: {'unknown-window': AlertPercentThreshold()},
      ),
    );
    final decoded = AlertThresholdPreferences.decode(prefs.encode());
    final saved = decoded.forConnection(ProviderConnections.cursorPlan);
    expect(saved.hasStoredSettings, isTrue);
    expect(saved.hasAlertRules, isFalse);
    expect(saved.isEnabled, isFalse);
    expect(decoded.hasEnabledRules, isFalse);
    expect(saved.toJson()['planWindows'], {'unknown-window': {}});
    expect(
      decoded
          .withConnection(
            ProviderConnections.cursorPlan,
            saved.copyWith(planWindows: const {}),
          )
          .connections,
      isEmpty,
    );
  });

  test('window decoding retains compatible legacy numbers and aliases', () {
    final decoded = AlertThresholdPreferences.fromJson({
      'connections': {
        'openai.plan': {
          'planWindows': {
            'zero': {'at': '0'},
            'full': {'warnAt': 100.0},
            'custom': {'criticalAt': 82.6},
            'preferred': {'at': 0, 'warnAt': 80},
            'off': {},
          },
        },
      },
    });
    expect(
      AlertThresholdPreferences.decode(
        decoded.encode(),
      ).forConnection(ProviderConnections.codexPlan).toJson()['planWindows'],
      {
        'zero': {'at': 0},
        'full': {'at': 100},
        'custom': {'at': 83},
        'preferred': {'at': 0},
        'off': {},
      },
    );
    expect(AlertPercentThreshold.fromJson({'at': -1}).at, isNull);
    expect(AlertPercentThreshold.fromJson({'at': 101}).at, isNull);
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
    expect(saved.budget.today, isNull);
    expect(saved.budget.week, isNull);
    expect(
      decoded.forConnection(ProviderConnections.codexPlan).budget.isEmpty,
      isTrue,
    );
    expect(
      decoded
          .forConnection(ProviderConnections.anthropicPlatform)
          .budget
          .isEmpty,
      isTrue,
    );
  });

  test(
    'Cursor preserves stored integer ceilings without changing other connections',
    () {
      final decoded = AlertThresholdPreferences.fromJson({
        'connections': {
          for (final id in [
            ProviderConnections.cursorPlatform,
            ProviderConnections.cursorPlan,
            ProviderConnections.anthropicPlatform,
          ])
            id.storageKey: {
              'budget': {'today': 0, 'week': -1, 'month': 5075},
            },
        },
      });
      final retained = AlertThresholdPreferences.decode(decoded.encode());
      final cursor = retained.forConnection(ProviderConnections.cursorPlatform);
      expect(cursor.budget.today, 0);
      expect(cursor.budget.week, -1);
      expect(cursor.budget.month, 5075);
      expect(cursor.hasStoredSettings, isTrue);
      for (final id in [
        ProviderConnections.cursorPlan,
        ProviderConnections.anthropicPlatform,
      ]) {
        expect(retained.forConnection(id).budget.today, isNull);
        expect(retained.forConnection(id).budget.week, isNull);
        expect(retained.forConnection(id).budget.month, 5075);
      }
      final zeroOnly = AlertThresholdPreferences.fromJson({
        'connections': {
          'cursor.platform': {
            'budget': {'month': 0},
          },
        },
      });
      expect(
        AlertThresholdPreferences.decode(
          zeroOnly.encode(),
        ).forConnection(ProviderConnections.cursorPlatform).budget.month,
        0,
      );
      expect(
        retained.forConnection(ProviderConnections.openAiPlatform).budget.month,
        isNull,
      );
    },
  );

  test('clearing every limit drops the rule', () {
    final prefs = const AlertThresholdPreferences().withConnection(
      ProviderConnections.openAiPlatform,
      const ConnectionAlertThresholds(),
    );

    expect(prefs.hasEnabledRules, isFalse);
    expect(prefs.connections, isEmpty);
  });

  test(
    'every whole remaining percentage reverses used percent and keeps Off',
    () {
      expect(alertRemainingToUsed(null), isNull);
      expect(alertRemainingToUsed(50), 50);
      expect(alertRemainingToUsed(30), 70);
      expect(alertRemainingToUsed(20), 80);
      expect(alertRemainingToUsed(10), 90);
      expect(alertRemainingToUsed(0), 100);

      expect(alertUsedToRemaining(null), isNull);
      expect(alertUsedToRemaining(70), 30);
      expect(alertUsedToRemaining(100), 0);
      for (var remaining = 0; remaining <= 100; remaining++) {
        expect(
          alertUsedToRemaining(alertRemainingToUsed(remaining)),
          remaining,
        );
        expect(
          alertRemainingToUsed(alertUsedToRemaining(remaining)),
          remaining,
        );
      }
    },
  );

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
