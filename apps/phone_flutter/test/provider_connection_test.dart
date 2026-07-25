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

  test('only the Codex subscription is authorized without a pasted secret', () {
    for (final connection in providerConnectionCatalog()) {
      expect(
        connection.secretHint == null,
        connection.id == ProviderConnections.codexPlan,
        reason: connection.id.storageKey,
      );
    }
  });

  test('only Cursor rows carry the freshness note', () {
    for (final connection in providerConnectionCatalog()) {
      expect(
        connection.listSubtitle.contains(PollCadence.cursorFreshnessNote),
        connection.id.provider == ProviderFamily.cursor,
        reason: connection.id.storageKey,
      );
    }
  });
}
