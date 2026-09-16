import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../dashboard/dashboard_models.dart';
import '../providers/provider_connection.dart';
import '../sync/credit_request_runway.dart';

/// Maximum simultaneous rings on watch and watch-face surfaces.
const watchRingSlotCount = 3;

/// Synthetic watch-ring slot: Claude plan windows collapse to the tightest one.
const claudePlanRingId = 'allowance.claude.plan';
const codexPlanRingId = 'allowance.codex.plan';
const codexSparkRingId = 'allowance.codex.spark';

const _codexPlanLimits = [
  (
    id: codexPlanRingId,
    label: 'Codex plan',
    windows: ['codex-primary', 'codex-secondary'],
  ),
  (
    id: codexSparkRingId,
    label: 'Codex · Spark',
    windows: ['spark-primary', 'spark-secondary'],
  ),
];

/// Retired: for one build the two Cursor pools were a single catalog row. They
/// are picked separately again — a band is shared only when **both** are picked
/// (`WATCH_RING_DESIGN.md`, Split band) — so this id survives only to migrate a
/// selection stored under it.
const cursorPlanRingId = 'allowance.cursor.plan';

const cursorOwnPoolId = 'allowance.cursor.cursor-plan-models';
const cursorOtherPoolId = 'allowance.cursor.cursor-plan-other';

/// Disjoint pairs in fixed inner/outer order; band names are family + ` plan`.
const _splitBands = [
  (
    innerId: cursorOwnPoolId,
    outerId: cursorOtherPoolId,
    bandLabel: 'Cursor plan',
  ),
  (
    innerId: codexPlanRingId,
    outerId: codexSparkRingId,
    bandLabel: 'Codex plan',
  ),
];

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

  String? get _planTitle => switch (id) {
    claudePlanRingId => 'Claude plan',
    codexPlanRingId => 'Codex plan',
    codexSparkRingId => 'Codex · Spark',
    _ => null,
  };

  /// Catalog checkbox title, qualified by family so that a `Weekly plan` from
  /// two providers stays apart. Collapsed plan slots are synthetic — their labels
  /// follow the tightest window, so they keep stable names instead.
  String get catalogTitle {
    if (_planTitle case final title?) {
      return title;
    }
    final connection = connectionFromBudgetRingId(id);
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
    return _planTitle != null ? '$label · $left' : left;
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

  /// Migrate and deduplicate before applying the band budget.
  List<String> get clampedIds => migratedIds;

  List<String> get migratedIds =>
      migrateWatchRingSelectedIds(selectedIds ?? const <String>[]);
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

/// Coalesce legacy window ids into their per-limit ring ids, drop the retired
/// summed budget ids, and optionally drop retired purchased-meter ring ids
/// (Watchface only).
List<String> migrateWatchRingSelectedIds(
  List<String> ids, {
  bool dropPurchased = true,
  int maxSlots = watchRingSlotCount,
}) {
  final out = <String>[];
  void add(String id) {
    if (!out.contains(id)) out.add(id);
  }

  for (final id in ids) {
    // No successor to pick: which connection the sum stood for is unknown.
    if (retiredBudgetRingIds.contains(id) ||
        (dropPurchased && _retiredPurchasedRingIds.contains(id))) {
      continue;
    }
    if (id == claudePlanRingId || _isClaudePlanWindowRingId(id)) {
      add(claudePlanRingId);
    } else if (id == cursorPlanRingId) {
      add(cursorOwnPoolId);
      add(cursorOtherPoolId);
    } else {
      final limit =
          _codexPlanLimits
              .where(
                (limit) => limit.windows.any(
                  (window) => id == 'allowance.codex.$window',
                ),
              )
              .firstOrNull;
      add(limit?.id ?? id);
    }
  }
  return _withinSlotBudget(out, maxSlots).toList(growable: false);
}

/// Collapses Claude plan windows into one ring (tightest remaining).
///
/// Prefers non-exhausted windows so surface omit-exhausted does not hide a
/// usable shorter window behind a fully used weekly.
WatchRingMetric? collapseClaudePlanRing(Iterable<AllowanceState> allowances) {
  return _collapsePlanRing(
    allowances,
    id: claudePlanRingId,
    title: 'Claude plan',
    windowIds: _claudePlanWindowIds,
    labelFor:
        (window) => _claudePlanWindowGlanceLabel(window.id) ?? window.label,
  );
}

/// Collapse each Codex limit independently; neither can hide the other.
List<WatchRingMetric> collapseCodexPlanRings(
  Iterable<AllowanceState> allowances,
) {
  return [
    for (final limit in _codexPlanLimits)
      if (_collapsePlanRing(
            allowances,
            id: limit.id,
            title: limit.label,
            windowIds: limit.windows,
          )
          case final ring?)
        ring,
  ];
}

WatchRingMetric? _collapsePlanRing(
  Iterable<AllowanceState> allowances, {
  required String id,
  required String title,
  required List<String> windowIds,
  String Function(AllowanceState)? labelFor,
}) {
  final windows = [
    for (final allowance in allowances)
      if (allowance.source == AllowanceSource.plan &&
          windowIds.contains(allowance.id))
        allowance,
  ];
  if (windows.isEmpty) return null;
  final withPercent =
      windows.where((window) => window.usedPercent != null).toList();
  if (withPercent.isEmpty) {
    return WatchRingMetric(
      id: id,
      label: title,
      usedPercent: null,
      status: windows.first.status,
      unavailableReason: 'This allowance has no percentage to show.',
    );
  }
  final active =
      withPercent.where((window) => window.usedPercent! < 100).toList();
  final pool = active.isNotEmpty ? active : withPercent;
  pool.sort((a, b) => _comparePlanWindows(a, b, windowIds));
  final winner = pool.first;
  return WatchRingMetric(
    id: id,
    label: labelFor?.call(winner) ?? winner.label,
    usedPercent: winner.usedPercent,
    status: winner.status,
  );
}

int _comparePlanWindows(
  AllowanceState a,
  AllowanceState b,
  List<String> priority,
) {
  final usedCmp = b.usedPercent!.compareTo(a.usedPercent!);
  return usedCmp != 0
      ? usedCmp
      : priority.indexOf(a.id).compareTo(priority.indexOf(b.id));
}

/// Builds the catalog of ring metrics from the current dashboard snapshot.
///
/// Purchased meters (Extra usage, on-demand, Codex credits) are excluded by
/// default — they stay on phone cards / the Widget tab, not Wear rings.
///
/// [collapseClaudePlan] and [collapseCodexPlan] collapse plan windows for Watch/WFF.
/// The phone widget disables both so each window remains selectable.
List<WatchRingMetric> watchRingCatalog(
  DashboardSnapshot? snapshot, {
  bool includePurchased = false,
  bool collapseClaudePlan = true,
  bool collapseCodexPlan = true,
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
    if (account.provider == 'codex' && collapseCodexPlan) {
      metrics.addAll(collapseCodexPlanRings(account.allowances));
    }
    for (final allowance in account.allowances) {
      if (account.provider == 'codex' &&
          collapseCodexPlan &&
          allowance.source == AllowanceSource.plan &&
          _codexPlanLimits.any(
            (limit) => limit.windows.contains(allowance.id),
          )) {
        continue;
      }
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

/// What a selection costs in ring slots: **bands**, not pools. Both halves of a
/// configured pair share one band, so they cost one slot; either alone is an
/// ordinary ring (`WATCH_RING_DESIGN.md`, Split band).
int watchRingSlotCost(Iterable<String> ids) {
  final selected = ids.toList(growable: false);
  final shared = _splitBands.where(
    (band) =>
        selected.contains(band.innerId) && selected.contains(band.outerId),
  );
  return selected.length - shared.length;
}

/// Keeps ids in order while they fit the slot budget, counting by band.
///
/// Skips what does not fit rather than stopping at it: the second pool of a pair
/// costs nothing once the first is in, and it may sit behind a ring that no
/// longer fits — stopping there would split the pair and hand the watch a half.
List<String> _withinSlotBudget(Iterable<String> ids, int maxSlots) {
  final out = <String>[];
  for (final id in ids) {
    if (watchRingSlotCost([...out, id]) <= maxSlots) {
      out.add(id);
    }
  }
  return out;
}

/// Catalog rows the watch is set to show: the stored choice, or the defaults the
/// catalog offers when there is none.
///
/// These are catalog ids, before selected halves are packed into bands.
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

/// Packs configured pairs into one entry, with the outer half in its `split`.
///
/// The pair keeps the place of its **tighter** half, which is where the surface
/// order already put it. Inside the entry, the table fixes inner/outer order
/// because that side is a name, not a rank (`WATCH_RING_DESIGN.md`, Split band).
List<(WatchRingMetric, WatchRingMetric?)> pairWatchRings(
  List<WatchRingMetric> rings,
) {
  var bands = <(WatchRingMetric, WatchRingMetric?)>[
    for (final ring in rings) (ring, null),
  ];
  for (final definition in _splitBands) {
    final inner =
        rings.where((ring) => ring.id == definition.innerId).firstOrNull;
    final outer =
        rings.where((ring) => ring.id == definition.outerId).firstOrNull;
    if (inner == null || outer == null) {
      continue;
    }
    final tighter = rings.indexOf(inner) < rings.indexOf(outer) ? inner : outer;
    bands = [
      for (final band in bands)
        if (band.$1.id == tighter.id)
          (inner, outer)
        else if (band.$1.id != inner.id && band.$1.id != outer.id)
          band,
    ];
  }
  return bands;
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
  // By band, not by ring: a pair is two rings and one slot, so counting rings
  // here dropped one of its pools and the band arrived undivided.
  final kept =
      _withinSlotBudget([for (final ring in active) ring.id], maxSlots).toSet();
  return [
    for (final ring in active)
      if (kept.contains(ring.id)) ring,
  ];
}

/// Short subtitle for Watchface preview and Settings diagnostics.
///
/// Counts **bands**, not pools: a pair travels as one payload entry and costs
/// one slot, so it is named once using the table's band label.
String watchRingPayloadSubtitle(
  DashboardSnapshot snapshot,
  WatchRingPreferences ringPreferences,
) {
  final bands = pairWatchRings(
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
    final title = _watchRingBandTitle(ring, split);
    return '$title ${tightest.remainingPercent!.round()}% left';
  }
  final titles = [
    for (final (ring, split) in bands) _watchRingBandTitle(ring, split),
  ];
  return '${bands.length} rings · ${titles.join(', ')}';
}

String _watchRingBandTitle(WatchRingMetric ring, WatchRingMetric? split) {
  if (split == null) {
    return ring.catalogTitle;
  }
  return _splitBands
      .firstWhere((band) => band.innerId == ring.id && band.outerId == split.id)
      .bandLabel;
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
ProviderConnectionId? connectionFromBudgetRingId(String ringId) {
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
      // Persist the canonical selection once, including migrations and trimming.
      if (migrated == null) {
        await _storage.delete(key: _key);
      } else if (!_sameIds(ids, migrated)) {
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
