import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../dashboard/dashboard_models.dart';

/// Which consumption surfaces appear on Dashboard / watch payloads.
///
/// Always-on for plan, purchased, and platform — Settings no longer toggles these.
class ConsumptionDisplayPreferences {
  const ConsumptionDisplayPreferences({
    this.plan = true,
    this.purchased = true,
    this.platform = true,
  });

  final bool plan;
  final bool purchased;
  final bool platform;

  bool get hasVisibleSurface => true;

  bool allows(AllowanceSource source) {
    // Surfaces are not user-hideable; always include reported allowances.
    return true;
  }

  ConsumptionDisplayPreferences copyWith({
    bool? plan,
    bool? purchased,
    bool? platform,
  }) {
    return const ConsumptionDisplayPreferences();
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
  static const _platformKey = 'wardpulse.display.platform';

  final FlutterSecureStorage _storage;

  @override
  Future<ConsumptionDisplayPreferences> read() async {
    // Legacy keys may exist; ignore them and always show all surfaces.
    return const ConsumptionDisplayPreferences();
  }

  @override
  Future<void> write(ConsumptionDisplayPreferences value) {
    return Future.wait([
      _storage.write(key: _planKey, value: 'true'),
      _storage.write(key: _purchasedKey, value: 'true'),
      _storage.write(key: _platformKey, value: 'true'),
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
