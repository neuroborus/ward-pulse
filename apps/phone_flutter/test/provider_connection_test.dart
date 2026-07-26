import 'package:flutter_test/flutter_test.dart';
import 'package:ward_pulse_phone/providers/provider_connection.dart';
import 'package:ward_pulse_phone/sync/poll_cadence.dart';

void main() {
  test('catalog groups plan before platform for every provider', () {
    final catalog = providerConnectionCatalog(
      platformLabels: {
        ProviderConnections.openAiPlatform.storageKey: 'Work org key',
      },
    );

    expect(catalog.map((connection) => connection.id.storageKey).toList(), [
      'openai.plan',
      'openai.platform',
      'anthropic.plan',
      'anthropic.platform',
      'cursor.plan',
      'cursor.platform',
    ]);
    expect(catalog[1].listTitle, 'Work org key');
    expect(providerFamilyLabel(ProviderFamily.openai), 'OpenAI');
  });

  test('plan sign-in rows omit pasted-secret hints', () {
    for (final connection in providerConnectionCatalog()) {
      final signInPlan =
          connection.id == ProviderConnections.codexPlan ||
          connection.id == ProviderConnections.claudePlan ||
          connection.id == ProviderConnections.cursorPlan;
      expect(
        connection.secretHint == null,
        signInPlan,
        reason: connection.id.storageKey,
      );
    }
  });

  test('Cursor plan catalog copy is dashboard sign-in, not paste/OAuth', () {
    final cursorPlan = providerConnectionCatalog().singleWhere(
      (connection) => connection.id == ProviderConnections.cursorPlan,
    );
    expect(cursorPlan.subtitle, 'Experimental · dashboard sign-in');
    expect(cursorPlan.subtitle.toLowerCase(), isNot(contains('oauth')));
    expect(cursorPlan.subtitle.toLowerCase(), isNot(contains('paste')));
  });

  test('only the Cursor Team Admin API row carries the freshness note', () {
    for (final connection in providerConnectionCatalog()) {
      expect(
        connection.listSubtitle.contains(PollCadence.cursorFreshnessNote),
        connection.id == ProviderConnections.cursorPlatform,
        reason: connection.id.storageKey,
      );
    }
  });
}
