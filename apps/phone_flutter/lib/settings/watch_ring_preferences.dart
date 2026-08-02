import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../dashboard/dashboard_models.dart';
import '../sync/credit_request_runway.dart';

/// Maximum simultaneous rings on watch and watch-face surfaces.
const watchRingSlotCount = 3;

/// Synthetic watch-ring slot: Claude plan windows collapse to the tightest one.
const claudePlanRingId = 'allowance.claude.plan';

/// Claude plan window allowance ids, tie-break order (shorter / primary first).
const _claudePlanWindowIds = <String>[
  'claude-five-hour',
  'claude-seven-day',
  'claude-seven-day-opus',
  'claude-seven-day-sonnet',
];

/// Former ring-catalog ids for purchased meters (no longer selectable).
const _retiredPurchasedRingIds = <String>{
  'allowance.claude.claude-extra-usage',
  'allowance.cursor.cursor-on-demand',
  'allowance.codex.codex-purchased-credits',
};

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

  /// Watch payload / Glance metric label (`5h`, `Weekly plan`, …).
  final String label;

  /// Consumed capacity 0–100 from the provider (Watch/WFF arcs use remaining).
  final double? usedPercent;
  final ProviderStatus status;

  /// When set, the Settings row is disabled and the reason is shown as help.
  final String? unavailableReason;

  bool get isAvailable => usedPercent != null && unavailableReason == null;

  bool get _isClaudePlanSlot => id == claudePlanRingId;

  /// Catalog checkbox title, qualified by family so that a `Weekly plan` from
  /// two providers stays apart. The Claude plan slot is synthetic — its label
  /// follows the tightest window, so it keeps a stable name instead.
  String get catalogTitle {
    if (_isClaudePlanSlot) {
      return 'Claude plan';
    }
    final provider = providerFromRingId(id);
    if (provider == null) {
      return label;
    }
    final family = providerDisplayLabel(provider);
    // A few pool names already open with the family (`Cursor Models`).
    return label.split(' ').first == family ? label : '$family · $label';
  }

  /// Catalog checkbox subtitle.
  String get catalogSubtitle {
    final reason = unavailableReason;
    if (reason != null) {
      return reason;
    }
    final remaining = remainingPercent;
    if (remaining == null) {
      return status.label;
    }
    final left = '${remaining.round()}% left · ${status.label}';
    return _isClaudePlanSlot ? '$label · $left' : left;
  }

  /// Remaining capacity for display — matches Wear/WFF remaining arcs.
  double? get remainingPercent {
    final used = usedPercent;
    if (used == null) {
      return null;
    }
    return (100.0 - used).clamp(0.0, 100.0);
  }
}

/// Ordered ring metric ids for Watchface (at most [watchRingSlotCount]).
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

  /// Clamped selection with legacy Claude / purchased ring ids migrated.
  List<String> get migratedIds => migrateWatchRingSelectedIds(clampedIds);
}

String? _claudePlanWindowGlanceLabel(String allowanceId) {
  return switch (allowanceId) {
    'claude-five-hour' => '5h',
    'claude-seven-day' => 'Weekly',
    'claude-seven-day-opus' => 'Opus weekly',
    'claude-seven-day-sonnet' => 'Sonnet weekly',
    _ => null,
  };
}

bool _isClaudePlanWindowAllowanceId(String allowanceId) {
  return _claudePlanWindowIds.contains(allowanceId);
}

bool _isClaudePlanWindowRingId(String ringId) {
  const prefix = 'allowance.claude.';
  if (!ringId.startsWith(prefix)) {
    return false;
  }
  return _isClaudePlanWindowAllowanceId(ringId.substring(prefix.length));
}

/// Expanded Claude plan window ring ids for phone-widget prefs migration.
final claudePlanWindowRingIds = [
  for (final id in _claudePlanWindowIds) 'allowance.claude.$id',
];

/// Coalesce legacy Claude window ids into [claudePlanRingId] and optionally
/// drop retired purchased-meter ring ids (Watchface only).
List<String> migrateWatchRingSelectedIds(
  List<String> ids, {
  bool dropPurchased = true,
  int maxSlots = watchRingSlotCount,
}) {
  final out = <String>[];
  var sawClaudePlan = false;
  for (final id in ids) {
    if (dropPurchased && _retiredPurchasedRingIds.contains(id)) {
      continue;
    }
    if (id == claudePlanRingId || _isClaudePlanWindowRingId(id)) {
      if (!sawClaudePlan) {
        out.add(claudePlanRingId);
        sawClaudePlan = true;
      }
      continue;
    }
    out.add(id);
  }
  return out.take(maxSlots).toList(growable: false);
}

/// Collapses Claude plan windows into one ring (tightest remaining).
///
/// Prefers non-exhausted windows so surface omit-exhausted does not hide a
/// usable shorter window behind a fully used weekly.
WatchRingMetric? collapseClaudePlanRing(Iterable<AllowanceState> allowances) {
  final windows = [
    for (final allowance in allowances)
      if (allowance.source == AllowanceSource.plan &&
          _isClaudePlanWindowAllowanceId(allowance.id))
        allowance,
  ];
  if (windows.isEmpty) {
    return null;
  }

  final withPercent = [
    for (final window in windows)
      if (window.usedPercent != null) window,
  ];
  if (withPercent.isEmpty) {
    return WatchRingMetric(
      id: claudePlanRingId,
      label: 'Claude plan',
      usedPercent: null,
      status: windows.first.status,
      unavailableReason: 'This allowance has no percentage to show.',
    );
  }

  final active = [
    for (final window in withPercent)
      if (window.usedPercent! < 100) window,
  ];
  final pool = active.isNotEmpty ? active : withPercent;
  pool.sort(_compareClaudePlanWindows);
  final winner = pool.first;

  return WatchRingMetric(
    id: claudePlanRingId,
    label: _claudePlanWindowGlanceLabel(winner.id) ?? winner.label,
    usedPercent: winner.usedPercent,
    status: winner.status,
  );
}

int _compareClaudePlanWindows(AllowanceState a, AllowanceState b) {
  final usedCmp = b.usedPercent!.compareTo(a.usedPercent!);
  if (usedCmp != 0) {
    return usedCmp;
  }
  return _claudePlanWindowIds
      .indexOf(a.id)
      .compareTo(_claudePlanWindowIds.indexOf(b.id));
}

/// Builds the catalog of ring metrics from the current dashboard snapshot.
///
/// Purchased meters (Extra usage, on-demand, Codex credits) are excluded by
/// default — they stay on phone cards / the Widget tab, not Wear rings.
///
/// [collapseClaudePlan] keeps Watch/WFF on one Claude slot. The phone widget
/// passes `false` so every Claude plan window is selectable on its own.
List<WatchRingMetric> watchRingCatalog(
  DashboardSnapshot? snapshot, {
  bool includePurchased = false,
  bool collapseClaudePlan = true,
}) {
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
    if (account.provider == 'claude' && collapseClaudePlan) {
      final collapsed = collapseClaudePlanRing(account.allowances);
      if (collapsed != null) {
        metrics.add(collapsed);
      }
      if (includePurchased) {
        for (final allowance in account.allowances) {
          if (allowance.source == AllowanceSource.purchased) {
            metrics.add(_allowanceMetric(account.provider, allowance));
          }
        }
      }
      continue;
    }
    for (final allowance in account.allowances) {
      if (allowance.source == AllowanceSource.purchased && !includePurchased) {
        continue;
      }
      metrics.add(_allowanceMetric(account.provider, allowance));
    }
  }

  return metrics;
}

/// Resolves rings for the watch payload: only available percent metrics.
///
/// Order follows Watchface selection (or catalog defaults). Use
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
    for (final id in preferences.migratedIds)
      if (catalog[id] case final metric? when metric.isAvailable) metric,
  ];
}

/// Display order for Wear/WFF/Glance: omit exhausted layers, tightest remaining first.
///
/// Payload index 0 = critical limit. Face maps that to the **innermost** ring and the
/// strip nearest the center; Glance keeps the same order top-first.
///
/// Sort: plan `usedPercent` descending, then credit request-runway ascending
/// (internal cost estimates; never shown as requests), then stable ring id.
List<WatchRingMetric> orderWatchRingsForSurface(
  List<WatchRingMetric> rings, {
  DashboardSnapshot? snapshot,
  int maxSlots = watchRingSlotCount,
}) {
  final active = [
    for (final ring in rings)
      if ((ring.usedPercent ?? 0) < 100) ring,
  ];
  final runways = <String, double?>{};
  if (snapshot != null) {
    for (final ring in active) {
      final provider = providerFromRingId(ring.id);
      if (provider == null) {
        continue;
      }
      runways.putIfAbsent(
        provider,
        () => creditRequestRunwayForProvider(snapshot, provider),
      );
    }
  }
  active.sort((a, b) {
    final usedCmp = (b.usedPercent ?? 0).compareTo(a.usedPercent ?? 0);
    if (usedCmp != 0) {
      return usedCmp;
    }
    final providerA = providerFromRingId(a.id);
    final providerB = providerFromRingId(b.id);
    final runwayA = providerA == null ? null : runways[providerA];
    final runwayB = providerB == null ? null : runways[providerB];
    // Missing / unlimited → +∞ (no secondary tightness pressure).
    if (runwayA != null || runwayB != null) {
      final runwayCmp = (runwayA ?? double.infinity).compareTo(
        runwayB ?? double.infinity,
      );
      if (runwayCmp != 0) {
        return runwayCmp;
      }
    }
    return a.id.compareTo(b.id);
  });
  return active.take(maxSlots).toList(growable: false);
}

/// Short subtitle for Watchface preview and Settings diagnostics.
String watchRingPayloadSubtitle(
  DashboardSnapshot snapshot,
  WatchRingPreferences ringPreferences,
) {
  final rings = orderWatchRingsForSurface(
    resolveWatchRings(snapshot, ringPreferences),
    snapshot: snapshot,
  );
  if (rings.isEmpty) {
    return 'No rings selected';
  }
  if (rings.length == 1) {
    final ring = rings.single;
    return '${ring.catalogTitle} ${ring.remainingPercent!.round()}% left';
  }
  return '${rings.length} rings · '
      '${rings.map((ring) => ring.catalogTitle).join(', ')}';
}

/// Owning provider for `allowance.<provider>.…`, or null for budgets / unknown.
String? providerFromRingId(String ringId) {
  if (!ringId.startsWith('allowance.')) {
    return null;
  }
  final parts = ringId.split('.');
  if (parts.length < 3) {
    return null;
  }
  return parts[1];
}

WatchRingMetric _allowanceMetric(String provider, AllowanceState allowance) {
  final percent = allowance.usedPercent;
  return WatchRingMetric(
    id: 'allowance.$provider.${allowance.id}',
    label: allowance.label,
    usedPercent: percent,
    status: allowance.status,
    unavailableReason:
        percent == null ? 'This allowance has no percentage to show.' : null,
  );
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
      ];
      final migrated = migrateWatchRingSelectedIds(ids);
      if (!_sameIds(ids.take(watchRingSlotCount).toList(), migrated)) {
        await _storage.write(key: _key, value: jsonEncode(migrated));
      }
      return WatchRingPreferences(selectedIds: migrated);
    } on FormatException {
      return const WatchRingPreferences();
    }
  }

  @override
  Future<void> write(WatchRingPreferences value) {
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

final class DefaultWatchRingPreferenceStore
    implements WatchRingPreferenceStore {
  const DefaultWatchRingPreferenceStore();

  @override
  Future<WatchRingPreferences> read() async => const WatchRingPreferences();

  @override
  Future<void> write(WatchRingPreferences value) async {}
}
