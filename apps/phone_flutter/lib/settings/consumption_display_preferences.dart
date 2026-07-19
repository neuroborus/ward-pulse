import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../dashboard/dashboard_models.dart';

class ConsumptionDisplayPreferences {
  const ConsumptionDisplayPreferences({
    this.plan = true,
    this.purchased = false,
  });

  final bool plan;
  final bool purchased;

  bool allows(AllowanceSource source) {
    return switch (source) {
      AllowanceSource.plan => plan,
      AllowanceSource.purchased => purchased,
    };
  }

  ConsumptionDisplayPreferences copyWith({bool? plan, bool? purchased}) {
    return ConsumptionDisplayPreferences(
      plan: plan ?? this.plan,
      purchased: purchased ?? this.purchased,
    );
  }
}

abstract interface class ConsumptionDisplayPreferenceStore {
  Future<ConsumptionDisplayPreferences> read();

  Future<void> write(ConsumptionDisplayPreferences value);
}

final class SecureConsumptionDisplayPreferenceStore
    implements ConsumptionDisplayPreferenceStore {
  SecureConsumptionDisplayPreferenceStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static const _planKey = 'wardpulse.display.plan';
  static const _purchasedKey = 'wardpulse.display.purchased';

  final FlutterSecureStorage _storage;

  @override
  Future<ConsumptionDisplayPreferences> read() async {
    final values = await Future.wait([
      _storage.read(key: _planKey),
      _storage.read(key: _purchasedKey),
    ]);
    final preferences = ConsumptionDisplayPreferences(
      plan: values[0] == null || values[0] == 'true',
      purchased: values[1] == 'true',
    );
    return preferences.plan || preferences.purchased
        ? preferences
        : const ConsumptionDisplayPreferences();
  }

  @override
  Future<void> write(ConsumptionDisplayPreferences value) {
    return Future.wait([
      _storage.write(key: _planKey, value: value.plan.toString()),
      _storage.write(key: _purchasedKey, value: value.purchased.toString()),
    ]);
  }
}

final class DefaultConsumptionDisplayPreferenceStore
    implements ConsumptionDisplayPreferenceStore {
  const DefaultConsumptionDisplayPreferenceStore();

  @override
  Future<ConsumptionDisplayPreferences> read() async =>
      const ConsumptionDisplayPreferences();

  @override
  Future<void> write(ConsumptionDisplayPreferences value) async {}
}
