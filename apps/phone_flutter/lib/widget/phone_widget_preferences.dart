import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../dashboard/dashboard_models.dart';
import '../settings/watch_ring_preferences.dart';

/// Prefs / payload cap for the phone home-widget (launcher may show fewer rows).
const phoneWidgetSlotCount = 6;

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

  /// Clamped selection; Claude windows stay expanded (no Watchface collapse).
  List<String> get migratedIds => migratePhoneWidgetSelectedIds(clampedIds);
}

/// Phone-widget prefs migration: keep Claude windows and purchased meters.
///
/// Rewrites the retired Watchface-only [claudePlanRingId] into expanded window
/// ids so an older Claude selection is not dropped on upgrade.
List<String> migratePhoneWidgetSelectedIds(List<String> ids) {
  final out = <String>[];
  for (final id in ids) {
    if (id == claudePlanRingId) {
      for (final windowId in claudePlanWindowRingIds) {
        if (!out.contains(windowId)) {
          out.add(windowId);
        }
      }
      continue;
    }
    if (!out.contains(id)) {
      out.add(id);
    }
  }
  return out.take(phoneWidgetSlotCount).toList(growable: false);
}

/// Phone home-widget catalog: budgets, every Claude plan window, purchased meters.
List<WatchRingMetric> phoneWidgetCatalog(DashboardSnapshot? snapshot) {
  return watchRingCatalog(
    snapshot,
    includePurchased: true,
    collapseClaudePlan: false,
  );
}

/// Resolves widget metrics: available percent metrics, prefs order.
///
/// Exhausted meters (`usedPercent >= 100`) stay selectable / visible as 0% left
/// so sibling pools (e.g. Cursor Models + Other Models) remain together.
List<WatchRingMetric> resolvePhoneWidgetMetrics(
  DashboardSnapshot snapshot,
  PhoneWidgetPreferences preferences,
) {
  if (preferences.usesDefaults) {
    return _defaultPhoneWidgetMetrics(snapshot);
  }

  final catalog = {
    for (final metric in phoneWidgetCatalog(snapshot)) metric.id: metric,
  };
  return [
    for (final id in preferences.migratedIds)
      if (catalog[id] case final metric? when metric.isAvailable) metric,
  ];
}

/// Defaults: plan windows first, then purchased, then budgets.
List<WatchRingMetric> _defaultPhoneWidgetMetrics(DashboardSnapshot snapshot) {
  final purchasedIds = _purchasedAllowanceRingIds(snapshot);
  final plans = <WatchRingMetric>[];
  final purchased = <WatchRingMetric>[];
  final budgets = <WatchRingMetric>[];
  for (final metric in phoneWidgetCatalog(snapshot)) {
    if (!metric.isAvailable) {
      continue;
    }
    if (metric.id.startsWith('budget.')) {
      budgets.add(metric);
    } else if (purchasedIds.contains(metric.id)) {
      purchased.add(metric);
    } else {
      plans.add(metric);
    }
  }
  return [
    ...plans,
    ...purchased,
    ...budgets,
  ].take(phoneWidgetSlotCount).toList(growable: false);
}

Set<String> _purchasedAllowanceRingIds(DashboardSnapshot snapshot) {
  return {
    for (final account in snapshot.accounts)
      for (final allowance in account.allowances)
        if (allowance.source == AllowanceSource.purchased)
          'allowance.${account.provider}.${allowance.id}',
  };
}

/// Display order for the launcher: tightest remaining first; keep 0% left rows.
List<WatchRingMetric> orderPhoneWidgetMetrics(
  List<WatchRingMetric> metrics, {
  int maxSlots = phoneWidgetSlotCount,
}) {
  final rows = [...metrics];
  rows.sort((a, b) {
    final usedCmp = (b.usedPercent ?? 0).compareTo(a.usedPercent ?? 0);
    if (usedCmp != 0) {
      return usedCmp;
    }
    return a.id.compareTo(b.id);
  });
  return rows.take(maxSlots).toList(growable: false);
}

/// Short subtitle for Widget tab preview.
String phoneWidgetPayloadSubtitle(
  DashboardSnapshot snapshot,
  PhoneWidgetPreferences preferences,
) {
  final metrics = orderPhoneWidgetMetrics(
    resolvePhoneWidgetMetrics(snapshot, preferences),
  );
  if (metrics.isEmpty) {
    return 'No metrics selected';
  }
  if (metrics.length == 1) {
    final metric = metrics.single;
    return '${metric.catalogTitle} ${metric.remainingPercent!.round()}% left';
  }
  return '${metrics.length} metrics · '
      '${metrics.map((m) => m.catalogTitle).join(', ')}';
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
