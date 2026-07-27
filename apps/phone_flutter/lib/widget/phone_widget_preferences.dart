import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../dashboard/dashboard_models.dart';
import '../settings/watch_ring_preferences.dart';

/// Default medium-size slot cap until phone widget design locks per-size counts.
///
/// Denser than [watchRingSlotCount] (3); small/large caps land with the design lock.
const phoneWidgetSlotCount = 4;

/// Ordered metric ids for the phone home-screen widget (independent of Watchface).
///
/// `selectedIds == null` means unset → use the default available metrics.
/// An empty list means the user chose zero metrics.
final class PhoneWidgetPreferences {
  const PhoneWidgetPreferences({this.selectedIds});

  final List<String>? selectedIds;

  bool get usesDefaults => selectedIds == null;

  List<String> get clampedIds => (selectedIds ?? const <String>[])
      .take(phoneWidgetSlotCount)
      .toList(growable: false);

  /// Clamped selection with legacy Claude window ids collapsed to one plan slot.
  List<String> get migratedIds => migratePhoneWidgetSelectedIds(clampedIds);
}

/// Claude plan collapse for widget prefs; purchased meters stay selectable.
List<String> migratePhoneWidgetSelectedIds(List<String> ids) {
  return migrateWatchRingSelectedIds(
    ids,
    dropPurchased: false,
    maxSlots: phoneWidgetSlotCount,
  );
}

/// Phone home-widget catalog: budgets, plan windows, and purchased meters.
List<WatchRingMetric> phoneWidgetCatalog(DashboardSnapshot? snapshot) {
  return watchRingCatalog(snapshot, includePurchased: true);
}

/// Resolves widget metrics: only available non-exhausted percent metrics, prefs order.
List<WatchRingMetric> resolvePhoneWidgetMetrics(
  DashboardSnapshot snapshot,
  PhoneWidgetPreferences preferences,
) {
  bool usable(WatchRingMetric metric) {
    final used = metric.usedPercent;
    return metric.isAvailable && used != null && used < 100;
  }

  if (preferences.usesDefaults) {
    return phoneWidgetCatalog(
      snapshot,
    ).where(usable).take(phoneWidgetSlotCount).toList();
  }

  final catalog = {
    for (final metric in phoneWidgetCatalog(snapshot)) metric.id: metric,
  };
  return [
    for (final id in preferences.migratedIds)
      if (catalog[id] case final metric? when usable(metric)) metric,
  ];
}

/// Short subtitle for Widget tab preview.
String phoneWidgetPayloadSubtitle(
  DashboardSnapshot snapshot,
  PhoneWidgetPreferences preferences,
) {
  final metrics = orderWatchRingsForSurface(
    resolvePhoneWidgetMetrics(snapshot, preferences),
    snapshot: snapshot,
    maxSlots: phoneWidgetSlotCount,
  );
  if (metrics.isEmpty) {
    return 'No metrics selected';
  }
  if (metrics.length == 1) {
    final metric = metrics.single;
    return '${metric.label} ${metric.remainingPercent!.round()}% left';
  }
  return '${metrics.length} metrics · ${metrics.map((m) => m.label).join(', ')}';
}

abstract interface class PhoneWidgetPreferenceStore {
  Future<PhoneWidgetPreferences> read();

  Future<void> write(PhoneWidgetPreferences value);
}

final class SecurePhoneWidgetPreferenceStore
    implements PhoneWidgetPreferenceStore {
  SecurePhoneWidgetPreferenceStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static const _key = 'wardpulse.widget.selectedIds';

  final FlutterSecureStorage _storage;

  @override
  Future<PhoneWidgetPreferences> read() async {
    final raw = await _storage.read(key: _key);
    if (raw == null || raw.trim().isEmpty) {
      return const PhoneWidgetPreferences();
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) {
        return const PhoneWidgetPreferences();
      }
      final ids = [
        for (final entry in decoded)
          if (entry is String) entry,
      ];
      final migrated = migratePhoneWidgetSelectedIds(ids);
      if (!_sameIds(ids.take(phoneWidgetSlotCount).toList(), migrated)) {
        await _storage.write(key: _key, value: jsonEncode(migrated));
      }
      return PhoneWidgetPreferences(selectedIds: migrated);
    } on FormatException {
      return const PhoneWidgetPreferences();
    }
  }

  @override
  Future<void> write(PhoneWidgetPreferences value) {
    if (value.selectedIds == null) {
      return _storage.delete(key: _key);
    }
    return _storage.write(key: _key, value: jsonEncode(value.migratedIds));
  }
}

bool _sameIds(List<String> a, List<String> b) {
  if (a.length != b.length) {
    return false;
  }
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) {
      return false;
    }
  }
  return true;
}

final class DefaultPhoneWidgetPreferenceStore
    implements PhoneWidgetPreferenceStore {
  const DefaultPhoneWidgetPreferenceStore();

  @override
  Future<PhoneWidgetPreferences> read() async => const PhoneWidgetPreferences();

  @override
  Future<void> write(PhoneWidgetPreferences value) async {}
}
