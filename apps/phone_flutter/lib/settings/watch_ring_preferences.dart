import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../dashboard/dashboard_models.dart';
import '../providers/provider_connection.dart';
import '../sync/credit_request_runway.dart';

/// Maximum simultaneous rings on watch and watch-face surfaces.
const watchRingSlotCount = 3;

/// Synthetic watch-ring slot: Claude plan windows collapse to the tightest one.
const claudePlanRingId = 'allowance.claude.plan';

/// Retired: for one build the two Cursor pools were a single catalog row. They
/// are picked separately again — a band is shared only when **both** are picked
/// (`WATCH_RING_DESIGN.md`, Split band) — so this id survives only to migrate a
/// selection stored under it.
const cursorPlanRingId = 'allowance.cursor.plan';

/// What a shared band is called where a pair counts as one: the payload preview.
const cursorPlanRingLabel = 'Cursor plan';

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

/// Former ring-catalog ids for the summed budgets, now keyed by connection.
const retiredBudgetRingIds = <String>{
  'budget.today',
  'budget.week',
  'budget.month',
};

/// One selectable percent metric for a watch ring.
final class WatchRingMetric {
  const WatchRingMetric({
    required this.id,
    required this.label,
    required this.usedPercent,
    required this.status,
    this.spent,
    this.limit,
    this.unavailableReason,
  });

  final String id;

  /// Watch payload / Glance metric label (`5h`, `Weekly plan`, …).
  final String label;

  /// Consumed capacity 0–100 from the provider (Watch/WFF arcs use remaining).
  final double? usedPercent;
  final ProviderStatus status;

  /// Money behind a budget ring — the face strip reads it instead of a percent.
  /// Allowance rings leave both null: a plan window has no price.
  final Money? spent;
  final Money? limit;

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
    final connection = _connectionFromBudgetRingId(id);
    if (connection != null) {
      // The family alone cannot tell two connections of one provider apart,
      // and the label is only the period (`Anthropic platform · Month`).
      return '${providerFamilyLabel(connection.provider)} '
          '${connectionKindLabel(connection.kind)} · $label';
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

/// Storage → prefs, reading an all-retired selection as unset.
///
/// An empty *stored* list is a real choice ("no rings"); a list that migration
/// empties is not — those ids no longer exist, so defaults apply again rather
/// than leaving the watch blank until the user re-picks.
WatchRingPreferences watchRingPreferencesFromStoredIds(List<String> ids) {
  final migrated = migrateWatchRingSelectedIds(ids);
  if (ids.isNotEmpty && migrated.isEmpty) {
    return const WatchRingPreferences();
  }
  return WatchRingPreferences(selectedIds: migrated);
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

/// Coalesce legacy Claude window ids into [claudePlanRingId], drop the retired
/// summed budget ids, and optionally drop retired purchased-meter ring ids
/// (Watchface only).
List<String> migrateWatchRingSelectedIds(
  List<String> ids, {
  bool dropPurchased = true,
  int maxSlots = watchRingSlotCount,
}) {
  final out = <String>[];
  var sawClaudePlan = false;
  var sawCursorPlan = false;
  for (final id in ids) {
    // No successor to pick: which connection the sum stood for is unknown.
    if (retiredBudgetRingIds.contains(id)) {
      continue;
    }
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
    // One build stored the pair under a single id. Pools are picked separately
    // again, so that id unfolds into the two it stood for.
    if (id == cursorPlanRingId) {
      if (!sawCursorPlan) {
        out.addAll([cursorOwnPoolId, cursorOtherPoolId]);
        sawCursorPlan = true;
      }
      continue;
    }
    if (out.contains(id)) {
      continue;
    }
    out.add(id);
  }
  return _withinSlotBudget(out, maxSlots).toList(growable: false);
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
  if (snapshot == null) {
    return const [];
  }

  final metrics = <WatchRingMetric>[];
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

  // Budgets last: a plan window always carries a percentage, while a budget
  // ring waits for a limit, and unset Watchface defaults take the first slots.
  for (final account in snapshot.accounts) {
    if (account.provider == 'mock') {
      continue;
    }
    metrics.addAll(_connectionBudgetMetrics(account));
  }

  return metrics;
}

/// What a selection costs in ring slots: **bands**, not pools. Both Cursor pools
/// picked together share one band, so they cost one slot; either alone is an
/// ordinary ring (`WATCH_RING_DESIGN.md`, Split band).
int watchRingSlotCost(Iterable<String> ids) {
  final selected = ids.toList(growable: false);
  final shared =
      selected.contains(cursorOwnPoolId) &&
      selected.contains(cursorOtherPoolId);
  return selected.length - (shared ? 1 : 0);
}

/// Keeps ids in order while they fit the slot budget, counting by band.
List<String> _withinSlotBudget(Iterable<String> ids, int maxSlots) {
  final out = <String>[];
  for (final id in ids) {
    if (watchRingSlotCost([...out, id]) > maxSlots) {
      break;
    }
    out.add(id);
  }
  return out;
}

/// Catalog rows the watch is set to show: the stored choice, or the defaults the
/// catalog offers when there is none.
///
/// These are **catalog** ids — a Cursor pair is one id here, not its two pools.
/// [resolveWatchRings] expands them; the Watchface tab must not, or its
/// checkboxes would look for a pair by an id the catalog never shows.
List<String> watchRingSelectionIds(
  DashboardSnapshot? snapshot,
  WatchRingPreferences preferences,
) {
  if (!preferences.usesDefaults || snapshot == null) {
    return preferences.migratedIds;
  }
  return _withinSlotBudget([
    for (final metric in watchRingCatalog(snapshot))
      if (metric.isAvailable) metric.id,
  ], watchRingSlotCount).toList(growable: false);
}

/// Resolves rings for the watch payload: only available percent metrics.
///
/// Order follows Watchface selection (or catalog defaults). Use
/// [orderWatchRingsForSurface] before sending to Wear/WFF.
List<WatchRingMetric> resolveWatchRings(
  DashboardSnapshot snapshot,
  WatchRingPreferences preferences,
) {
  final catalog = {
    for (final metric in watchRingCatalog(snapshot)) metric.id: metric,
  };
  return [
    for (final id in watchRingSelectionIds(snapshot, preferences))
      if (catalog[id] case final metric? when metric.isAvailable) metric,
  ];
}

/// The Cursor plan's two pools share one band, so they travel as one entry: the
/// own-models pool with the external one folded into its `split`
/// (`WATCH_RING_DESIGN.md`, Split band).
///
/// The pair keeps the place of its **tighter** half, which is where the surface
/// order already put it, while inside the entry the order is by pool — own
/// first — because that side is a name, not a rank.
const cursorOwnPoolId = 'allowance.cursor.cursor-plan-models';
const cursorOtherPoolId = 'allowance.cursor.cursor-plan-other';

List<(WatchRingMetric, WatchRingMetric?)> pairCursorPools(
  List<WatchRingMetric> rings,
) {
  final own = rings.where((ring) => ring.id == cursorOwnPoolId).firstOrNull;
  final other = rings.where((ring) => ring.id == cursorOtherPoolId).firstOrNull;
  if (own == null || other == null) {
    return [for (final ring in rings) (ring, null)];
  }
  final tighter = rings.indexOf(own) < rings.indexOf(other) ? own : other;
  return [
    for (final ring in rings)
      if (ring.id == tighter.id)
        (own, other)
      else if (ring.id != cursorOwnPoolId && ring.id != cursorOtherPoolId)
        (ring, null),
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
///
/// Counts **bands**, not pools: a Cursor pair travels as one payload entry and
/// costs one slot, so it is named once, by the row the user checked.
String watchRingPayloadSubtitle(
  DashboardSnapshot snapshot,
  WatchRingPreferences ringPreferences,
) {
  final bands = pairCursorPools(
    orderWatchRingsForSurface(
      resolveWatchRings(snapshot, ringPreferences),
      snapshot: snapshot,
    ),
  );
  if (bands.isEmpty) {
    return 'No rings selected';
  }
  if (bands.length == 1) {
    final (ring, split) = bands.single;
    // A band speaks with its tighter half, the way the face ranks it.
    final tightest =
        split == null || ring.remainingPercent! <= split.remainingPercent!
            ? ring
            : split;
    final title = split == null ? ring.catalogTitle : cursorPlanRingLabel;
    return '$title ${tightest.remainingPercent!.round()}% left';
  }
  final titles = [
    for (final (ring, split) in bands)
      if (split == null) ring.catalogTitle else cursorPlanRingLabel,
  ];
  return '${bands.length} rings · ${titles.join(', ')}';
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

/// Local budget rings of one connection: one per period it reports spend for.
///
/// Reported spend is what makes a ceiling meaningful — subscription plans
/// report none, and a connection may report only some periods.
List<WatchRingMetric> _connectionBudgetMetrics(ProviderSnapshot account) {
  final connection = account.connection;
  if (connection == null) {
    return const [];
  }
  return [
    for (final budget in [account.today, account.week, account.month])
      if (budget.spent != null) _budgetMetric(connection, budget),
  ];
}

WatchRingMetric _budgetMetric(String connection, BudgetState budget) {
  final percent = budget.usedPercent;
  return WatchRingMetric(
    id: 'budget.$connection.${budget.period}',
    label: budget.periodLabel,
    usedPercent: percent,
    status: budget.status,
    spent: budget.spent,
    limit: budget.limit,
    unavailableReason:
        percent == null
            ? 'Set this period’s limit under Providers · Budget limits.'
            : null,
  );
}

/// Connection of a `budget.<connection>.<period>` ring, or null for other ids.
ProviderConnectionId? _connectionFromBudgetRingId(String ringId) {
  const prefix = 'budget.';
  if (!ringId.startsWith(prefix)) {
    return null;
  }
  final key = ringId.substring(prefix.length);
  final period = key.lastIndexOf('.');
  if (period < 0) {
    return null;
  }
  return ProviderConnectionId.fromStorageKey(key.substring(0, period));
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
      final preferences = watchRingPreferencesFromStoredIds(ids);
      final migrated = preferences.selectedIds;
      if (migrated == null) {
        await _storage.delete(key: _key);
      } else if (!_sameIds(ids.take(watchRingSlotCount).toList(), migrated)) {
        await _storage.write(key: _key, value: jsonEncode(migrated));
      }
      return preferences;
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
