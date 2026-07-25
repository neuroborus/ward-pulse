import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../dashboard/dashboard_models.dart';

/// Maximum simultaneous rings on watch and watch-face surfaces.
const watchRingSlotCount = 4;

/// One selectable percent metric for a watch ring.
final class WatchRingMetric {
  const WatchRingMetric({
    required this.id,
    required this.label,
    required this.usedPercent,
    required this.status,
    this.unavailableReason,
  });

  final String id;
  final String label;
  final double? usedPercent;
  final ProviderStatus status;

  /// When set, the Settings row is disabled and the reason is shown as help.
  final String? unavailableReason;

  bool get isAvailable => usedPercent != null && unavailableReason == null;
}

/// Ordered ring metric ids chosen in Settings (at most [watchRingSlotCount]).
///
/// `selectedIds == null` means unset → use the default available metrics.
/// An empty list means the user chose zero rings.
final class WatchRingPreferences {
  const WatchRingPreferences({this.selectedIds});

  final List<String>? selectedIds;

  bool get usesDefaults => selectedIds == null;

  List<String> get clampedIds => (selectedIds ?? const <String>[])
      .take(watchRingSlotCount)
      .toList(growable: false);
}

/// Builds the catalog of ring metrics from the current dashboard snapshot.
List<WatchRingMetric> watchRingCatalog(DashboardSnapshot? snapshot) {
  final metrics = <WatchRingMetric>[
    _budgetMetric('budget.today', 'Today', snapshot?.todayTotal),
    _budgetMetric('budget.week', 'Week', snapshot?.weekTotal),
    _budgetMetric('budget.month', 'Month', snapshot?.monthTotal),
  ];

  if (snapshot == null) {
    return metrics;
  }

  for (final account in snapshot.accounts) {
    if (account.provider == 'mock') {
      continue;
    }
    for (final allowance in account.allowances) {
      final id = 'allowance.${account.provider}.${allowance.id}';
      final percent = allowance.usedPercent;
      metrics.add(
        WatchRingMetric(
          id: id,
          label: allowance.label,
          usedPercent: percent,
          status: allowance.status,
          unavailableReason:
              percent == null
                  ? 'This allowance has no percentage to show as a ring.'
                  : null,
        ),
      );
    }
  }

  return metrics;
}

/// Resolves rings for the watch payload: only available percent metrics.
///
/// Order follows Settings selection (or catalog defaults). Use
/// [orderWatchRingsForSurface] before sending to Wear/WFF.
List<WatchRingMetric> resolveWatchRings(
  DashboardSnapshot snapshot,
  WatchRingPreferences preferences,
) {
  if (preferences.usesDefaults) {
    return watchRingCatalog(
      snapshot,
    ).where((metric) => metric.isAvailable).take(watchRingSlotCount).toList();
  }

  final catalog = {
    for (final metric in watchRingCatalog(snapshot)) metric.id: metric,
  };
  return [
    for (final id in preferences.clampedIds)
      if (catalog[id] case final metric? when metric.isAvailable) metric,
  ];
}

/// Display order for Wear/WFF: omit exhausted layers, tightest remaining outermost.
List<WatchRingMetric> orderWatchRingsForSurface(List<WatchRingMetric> rings) {
  final active = [
    for (final ring in rings)
      if ((ring.usedPercent ?? 0) < 100) ring,
  ];
  active.sort((a, b) {
    final usedA = a.usedPercent ?? 0;
    final usedB = b.usedPercent ?? 0;
    return usedB.compareTo(usedA);
  });
  return active.take(watchRingSlotCount).toList(growable: false);
}

WatchRingMetric _budgetMetric(String id, String label, BudgetState? budget) {
  final percent = budget?.usedPercent;
  return WatchRingMetric(
    id: id,
    label: label,
    usedPercent: percent,
    status: budget?.status ?? ProviderStatus.unknown,
    unavailableReason:
        percent == null
            ? 'Connect a spend-reporting provider to fill this budget ring.'
            : null,
  );
}

abstract interface class WatchRingPreferenceStore {
  Future<WatchRingPreferences> read();

  Future<void> write(WatchRingPreferences value);
}

final class SecureWatchRingPreferenceStore implements WatchRingPreferenceStore {
  SecureWatchRingPreferenceStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static const _key = 'wardpulse.watch.ringIds';

  final FlutterSecureStorage _storage;

  @override
  Future<WatchRingPreferences> read() async {
    final raw = await _storage.read(key: _key);
    if (raw == null || raw.isEmpty) {
      return const WatchRingPreferences();
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) {
        return const WatchRingPreferences();
      }
      final ids = [
        for (final entry in decoded)
          if (entry is String && entry.isNotEmpty) entry,
      ].take(watchRingSlotCount).toList(growable: false);
      return WatchRingPreferences(selectedIds: ids);
    } on FormatException {
      return const WatchRingPreferences();
    }
  }

  @override
  Future<void> write(WatchRingPreferences value) {
    if (value.selectedIds == null) {
      return _storage.delete(key: _key);
    }
    return _storage.write(key: _key, value: jsonEncode(value.clampedIds));
  }
}

final class DefaultWatchRingPreferenceStore
    implements WatchRingPreferenceStore {
  const DefaultWatchRingPreferenceStore();

  @override
  Future<WatchRingPreferences> read() async => const WatchRingPreferences();

  @override
  Future<void> write(WatchRingPreferences value) async {}
}
