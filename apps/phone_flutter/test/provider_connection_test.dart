import 'package:flutter_test/flutter_test.dart';
import 'package:ward_pulse_phone/providers/provider_connection.dart';

void main() {
  test('catalog groups OpenAI plan and platform before deferred providers', () {
    final catalog = providerConnectionCatalog(
      openAiPlatformLabel: 'Work org key',
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
    expect(catalog[2].supported, isFalse);
    expect(providerFamilyLabel(ProviderFamily.openai), 'OpenAI');
  });
}
