import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ward_pulse_phone/dashboard/dashboard_models.dart';
import 'package:ward_pulse_phone/settings/watch_ring_preferences.dart';

void main() {
  final snapshot = DashboardSnapshot.fromJsonString(
    File('../../fixtures/snapshots/dashboard_today.json').readAsStringSync(),
  );

  test('mock accounts offer no rings at all', () {
    expect(watchRingCatalog(snapshot), isEmpty);
    expect(watchRingCatalog(null), isEmpty);
  });

  test('offers a budget ring per period a connection reports spend for', () {
    final catalog = watchRingCatalog(_planAndBudgetSnapshot());

    // Week reports no spend, so it never becomes a slot.
    expect(catalog.map((ring) => ring.id), [
      'allowance.codex.codex-weekly',
      'budget.anthropic.platform.today',
      'budget.anthropic.platform.month',
    ]);
    final today = catalog[1];
    expect(today.isAvailable, isFalse);
    // The reason names the budget entry, not the alert dialog.
    expect(today.unavailableReason, contains('Providers · Budget limits'));
    expect(today.catalogTitle, 'Anthropic platform · Today');
    expect(catalog.last.isAvailable, isTrue);
  });

  test('defaults to the first available percent metrics when unset', () {
    final rings = resolveWatchRings(
      _planAndBudgetSnapshot(),
      const WatchRingPreferences(),
    );

    // Plan windows first; a budget ring without a limit is not a candidate.
    expect(rings.map((ring) => ring.id), [
      'allowance.codex.codex-weekly',
      'budget.anthropic.platform.month',
    ]);
    expect(rings.every((ring) => ring.usedPercent != null), isTrue);
  });

  test('honors an explicit empty selection', () {
    final rings = resolveWatchRings(
      _planAndBudgetSnapshot(),
      const WatchRingPreferences(selectedIds: []),
    );

    expect(rings, isEmpty);
  });

  test('keeps selection order and drops unavailable ids', () {
    final rings = resolveWatchRings(
      _planAndBudgetSnapshot(),
      const WatchRingPreferences(
        selectedIds: [
          'budget.anthropic.platform.month',
          'missing',
          'allowance.codex.codex-weekly',
        ],
      ),
    );

    expect(rings.map((ring) => ring.id), [
      'budget.anthropic.platform.month',
      'allowance.codex.codex-weekly',
    ]);
  });

  test('clamps stored ids to three slots', () {
    const preferences = WatchRingPreferences(
      selectedIds: ['a', 'b', 'c', 'd', 'e'],
    );

    expect(preferences.clampedIds, ['a', 'b', 'c']);
    expect(jsonEncode(preferences.clampedIds), '["a","b","c"]');
  });

  WatchRingMetric ring(String id, double used) => WatchRingMetric(
    id: id,
    label: id,
    usedPercent: used,
    status: ProviderStatus.ok,
  );

  test('the Cursor pools travel as one entry, own models first', () {
    final packed = pairCursorPools([
      ring(cursorOtherPoolId, 90),
      ring('allowance.claude.plan', 40),
      ring(cursorOwnPoolId, 10),
    ]);

    // One band, so one entry — and it keeps the place of the tighter half.
    expect(packed.length, 2);
    expect(packed.first.$1.id, cursorOwnPoolId);
    expect(packed.first.$2?.id, cursorOtherPoolId);
    expect(packed.last.$1.id, 'allowance.claude.plan');
    expect(packed.last.$2, isNull);
  });

  test('one Cursor pool alone is an ordinary ring', () {
    final packed = pairCursorPools([ring(cursorOwnPoolId, 10)]);

    expect(packed.length, 1);
    expect(packed.single.$2, isNull);
  });

  test('two pools cost one slot, one pool costs one too', () {
    // The pair is a band, not two rings: picking both spends a single slot, so
    // a third ring still fits (`WATCH_RING_DESIGN.md`, Split band).
    expect(watchRingSlotCost([cursorOwnPoolId, cursorOtherPoolId]), 1);
    expect(watchRingSlotCost([cursorOwnPoolId]), 1);
    expect(
      watchRingSlotCost([
        cursorOwnPoolId,
        cursorOtherPoolId,
        'allowance.claude.plan',
        'budget.anthropic.platform.week',
      ]),
      3,
    );
  });

  test('surface order puts tightest remaining first and drops exhausted', () {
    const rings = [
      WatchRingMetric(
        id: 'a',
        label: 'A',
        usedPercent: 20,
        status: ProviderStatus.ok,
      ),
      WatchRingMetric(
        id: 'b',
        label: 'B',
        usedPercent: 100,
        status: ProviderStatus.ok,
      ),
      WatchRingMetric(
        id: 'c',
        label: 'C',
        usedPercent: 80,
        status: ProviderStatus.ok,
      ),
    ];

    expect(orderWatchRingsForSurface(rings).map((ring) => ring.id), ['c', 'a']);
  });

  test('equal plan percent prefers lower credit request runway', () {
    final dash = _twoPlanProvidersSnapshot(
      codexUsed: 40,
      claudeUsed: 40,
      codexCredits: 3,
      claudeCredits: 12,
    );
    final rings = orderWatchRingsForSurface([
      const WatchRingMetric(
        id: 'allowance.claude.plan',
        label: 'Weekly',
        usedPercent: 40,
        status: ProviderStatus.ok,
      ),
      const WatchRingMetric(
        id: 'allowance.codex.codex-weekly',
        label: 'Weekly plan',
        usedPercent: 40,
        status: ProviderStatus.ok,
      ),
    ], snapshot: dash);

    expect(rings.map((ring) => ring.id), [
      'allowance.codex.codex-weekly',
      'allowance.claude.plan',
    ]);
  });

  test(
    'unlimited credits do not win secondary tightness over finite runway',
    () {
      final dash = _twoPlanProvidersSnapshot(
        codexUsed: 50,
        claudeUsed: 50,
        codexCredits: 4,
        claudeUnlimitedPurchased: true,
      );
      final rings = orderWatchRingsForSurface([
        const WatchRingMetric(
          id: 'allowance.claude.plan',
          label: 'Weekly',
          usedPercent: 50,
          status: ProviderStatus.ok,
        ),
        const WatchRingMetric(
          id: 'allowance.codex.codex-weekly',
          label: 'Weekly plan',
          usedPercent: 50,
          status: ProviderStatus.ok,
        ),
      ], snapshot: dash);

      expect(rings.first.id, 'allowance.codex.codex-weekly');
    },
  );

  test('missing credits on both sides falls through to stable ring id', () {
    final dash = _twoPlanProvidersSnapshot(codexUsed: 50, claudeUsed: 50);
    final rings = orderWatchRingsForSurface([
      const WatchRingMetric(
        id: 'allowance.claude.plan',
        label: 'Weekly',
        usedPercent: 50,
        status: ProviderStatus.ok,
      ),
      const WatchRingMetric(
        id: 'allowance.codex.codex-weekly',
        label: 'Weekly plan',
        usedPercent: 50,
        status: ProviderStatus.ok,
      ),
    ], snapshot: dash);

    expect(rings.map((ring) => ring.id), [
      'allowance.claude.plan',
      'allowance.codex.codex-weekly',
    ]);
  });

  group('Claude plan collapse', () {
    test('catalog exposes one Claude plan slot for multiple windows', () {
      final dash = _claudeCodexSnapshot(
        fiveHourUsed: 40,
        sevenDayUsed: 70,
        codexUsed: 10,
      );
      final ids = watchRingCatalog(dash).map((m) => m.id).toList();

      expect(ids.where((id) => id == claudePlanRingId), hasLength(1));
      expect(ids, isNot(contains('allowance.claude.claude-five-hour')));
      expect(ids, isNot(contains('allowance.claude.claude-seven-day')));
      expect(ids, contains('allowance.codex.codex-weekly'));
    });

    test('picks the tighter window and short Glance label', () {
      final dash = _claudeCodexSnapshot(
        fiveHourUsed: 40,
        sevenDayUsed: 70,
        codexUsed: 10,
      );
      final collapsed =
          collapseClaudePlanRing(
            dash.accounts.firstWhere((a) => a.provider == 'claude').allowances,
          )!;

      expect(collapsed.id, claudePlanRingId);
      expect(collapsed.label, 'Weekly');
      expect(collapsed.catalogTitle, 'Claude plan');
      expect(collapsed.catalogSubtitle, 'Weekly · 30% left · OK');
      expect(collapsed.usedPercent, 70);
    });

    test('tie-break prefers 5h over weekly', () {
      final dash = _claudeCodexSnapshot(
        fiveHourUsed: 55,
        sevenDayUsed: 55,
        codexUsed: 10,
      );
      final collapsed =
          collapseClaudePlanRing(
            dash.accounts.firstWhere((a) => a.provider == 'claude').allowances,
          )!;

      expect(collapsed.label, '5h');
      expect(collapsed.usedPercent, 55);
    });

    test('prefers non-exhausted window over exhausted tighter weekly', () {
      final dash = _claudeCodexSnapshot(
        fiveHourUsed: 40,
        sevenDayUsed: 100,
        codexUsed: 10,
      );
      final collapsed =
          collapseClaudePlanRing(
            dash.accounts.firstWhere((a) => a.provider == 'claude').allowances,
          )!;

      expect(collapsed.label, '5h');
      expect(collapsed.usedPercent, 40);
    });

    test('migrates legacy Claude window ids to one plan slot', () {
      expect(
        migrateWatchRingSelectedIds([
          'budget.anthropic.platform.month',
          'allowance.claude.claude-five-hour',
          'allowance.claude.claude-seven-day',
          'allowance.codex.codex-weekly',
        ]),
        [
          'budget.anthropic.platform.month',
          claudePlanRingId,
          'allowance.codex.codex-weekly',
        ],
      );
    });

    test('surface has one Claude ring with Codex, not two', () {
      final dash = _claudeCodexSnapshot(
        fiveHourUsed: 40,
        sevenDayUsed: 70,
        codexUsed: 10,
      );
      final rings = orderWatchRingsForSurface(
        resolveWatchRings(
          dash,
          const WatchRingPreferences(
            selectedIds: [
              'allowance.codex.codex-weekly',
              'allowance.claude.claude-five-hour',
              'allowance.claude.claude-seven-day',
            ],
          ),
        ),
        snapshot: dash,
      );

      expect(rings.map((r) => r.id), [
        claudePlanRingId,
        'allowance.codex.codex-weekly',
      ]);
      expect(rings.map((r) => r.label), ['Weekly', 'Weekly plan']);
    });
  });

  test('drops retired purchased meter ring ids from prefs', () {
    expect(
      migrateWatchRingSelectedIds([
        'allowance.claude.claude-extra-usage',
        'allowance.cursor.cursor-plan-models',
        'allowance.cursor.cursor-on-demand',
        'allowance.codex.codex-purchased-credits',
      ]),
      // A pool id is a catalog row and survives as itself.
      [cursorOwnPoolId],
    );
  });

  test('a stored pair keeps both pools and still costs one slot', () {
    const stored = [cursorOwnPoolId, cursorOtherPoolId, claudePlanRingId];

    expect(migrateWatchRingSelectedIds(stored), stored);
    // Three ids, two bands: the budget for a third ring is untouched.
    expect(watchRingSlotCost(migrateWatchRingSelectedIds(stored)), 2);
  });

  test('the retired one-row id unfolds into the pools it stood for', () {
    // One build stored the pair as a single row; those users keep both pools.
    expect(migrateWatchRingSelectedIds([cursorPlanRingId, claudePlanRingId]), [
      cursorOwnPoolId,
      cursorOtherPoolId,
      claudePlanRingId,
    ]);
  });

  test('a stored selection of only retired ids reads back as unset', () {
    // Upgrade path: the summed budgets were the only rings a platform-only
    // user could pick, so an emptied selection must not mean "no rings".
    expect(
      watchRingPreferencesFromStoredIds([
        'budget.today',
        'budget.week',
      ]).usesDefaults,
      isTrue,
    );
    // Stored empty stays the user's explicit choice.
    expect(watchRingPreferencesFromStoredIds([]).selectedIds, isEmpty);
    expect(
      watchRingPreferencesFromStoredIds([
        'budget.today',
        'budget.anthropic.platform.month',
      ]).selectedIds,
      ['budget.anthropic.platform.month'],
    );
  });

  test('drops the retired summed budget ring ids from prefs', () {
    // The sum stood for no single connection, so there is no successor id.
    expect(
      migrateWatchRingSelectedIds([
        'budget.today',
        'budget.anthropic.platform.month',
        'budget.week',
        'budget.month',
      ]),
      ['budget.anthropic.platform.month'],
    );
  });

  test('includes Cursor Models and Other Models in watch ring catalog', () {
    final cursor = _asPlanConnection(
      Map<String, dynamic>.from(
        (snapshot.toJson()['accounts'] as List).first as Map,
      ),
      'cursor.plan',
    );
    cursor['provider'] = 'cursor';
    cursor['accountId'] = 'cursor-local';
    cursor['allowances'] = [
      {
        'id': 'cursor-plan-models',
        'source': 'plan',
        'label': 'Cursor Models',
        'usedPercent': 47.0,
        'used': null,
        'limit': null,
        'remaining': null,
        'unlimited': false,
        'windowMinutes': null,
        'resetsAt': null,
        'status': 'ok',
      },
      {
        'id': 'cursor-plan-other',
        'source': 'plan',
        'label': 'Other Models',
        'usedPercent': 100.0,
        'used': null,
        'limit': null,
        'remaining': null,
        'unlimited': false,
        'windowMinutes': null,
        'resetsAt': null,
        'status': 'rateLimited',
      },
      {
        'id': 'cursor-on-demand',
        'source': 'purchased',
        'label': 'On-demand usage',
        'usedPercent': 45.0,
        'used': {'value': '4.50', 'unit': 'credits'},
        'limit': {'value': '10.00', 'unit': 'credits'},
        'remaining': {'value': '5.50', 'unit': 'credits'},
        'unlimited': false,
        'windowMinutes': null,
        'resetsAt': null,
        'status': 'ok',
      },
    ];
    final withCursor = DashboardSnapshot.fromJson({
      ...snapshot.toJson(),
      'accounts': [cursor],
      'todayTotal': {
        'period': 'today',
        'spent': null,
        'limit': null,
        'remaining': null,
        'usedPercent': null,
        'projectedTotal': null,
        'status': 'unknown',
        'statusExplanation': null,
      },
      'weekTotal': {
        'period': 'week',
        'spent': null,
        'limit': null,
        'remaining': null,
        'usedPercent': null,
        'projectedTotal': null,
        'status': 'unknown',
        'statusExplanation': null,
      },
      'monthTotal': {
        'period': 'month',
        'spent': null,
        'limit': null,
        'remaining': null,
        'usedPercent': null,
        'projectedTotal': null,
        'status': 'unknown',
        'statusExplanation': null,
      },
    });

    // Both pools are offered on their own: a band is shared only when the user
    // ticks both (`WATCH_RING_DESIGN.md`, Split band).
    final catalogIds =
        watchRingCatalog(withCursor).map((ring) => ring.id).toList();
    expect(catalogIds, contains(cursorOwnPoolId));
    expect(catalogIds, contains(cursorOtherPoolId));
    expect(catalogIds, isNot(contains(cursorPlanRingId)));
    expect(catalogIds, isNot(contains('allowance.cursor.cursor-on-demand')));

    final surface = orderWatchRingsForSurface(
      resolveWatchRings(withCursor, const WatchRingPreferences()),
      snapshot: withCursor,
    );
    // Exhausted Other Models (100% used) is omitted from the face.
    // Purchased on-demand is never a ring candidate.
    expect(surface.map((ring) => ring.id), [
      'allowance.cursor.cursor-plan-models',
    ]);
  });

  test('a pool answers to the row the user ticked', () {
    final withPair = _cursorPairAndCodexSnapshot();
    const picked = WatchRingPreferences(selectedIds: [cursorOwnPoolId]);

    // The Watchface tab ticks catalog rows, so the selection speaks their ids.
    expect(watchRingSelectionIds(withPair, picked), [cursorOwnPoolId]);
    expect(resolveWatchRings(withPair, picked).map((ring) => ring.id), [
      cursorOwnPoolId,
    ]);
    // Unticking removes what was ticked; before this the screen looked for a
    // pool by an id the catalog never showed, and the ring lived on.
    final left = [...watchRingSelectionIds(withPair, picked)]
      ..remove(cursorOwnPoolId);
    expect(left, isEmpty);
  });

  test('the band is shared only when both pools are ticked', () {
    final withPair = _cursorPairAndCodexSnapshot();
    const both = WatchRingPreferences(
      selectedIds: [cursorOwnPoolId, cursorOtherPoolId],
    );

    // Two rows, one band: the payload packs them into a single entry.
    final packed = pairCursorPools(resolveWatchRings(withPair, both));
    expect(packed.length, 1);
    expect(packed.single.$1.id, cursorOwnPoolId);
    expect(packed.single.$2?.id, cursorOtherPoolId);

    // One pool alone stays an ordinary ring, undivided.
    const own = WatchRingPreferences(selectedIds: [cursorOwnPoolId]);
    final alone = pairCursorPools(resolveWatchRings(withPair, own));
    expect(alone.single.$2, isNull);
  });

  test('the payload preview counts a pair as one band', () {
    final withPair = _cursorPairAndCodexSnapshot();

    // Three pools, two bands, three payload entries would be wrong: the pair is
    // one entry and one slot, named by the row the user checked.
    expect(
      watchRingPayloadSubtitle(withPair, const WatchRingPreferences()),
      '2 rings · Codex · Weekly plan, Cursor plan',
    );

    // Alone, a pair reads like any single band — through its tighter half.
    expect(
      watchRingPayloadSubtitle(
        withPair,
        const WatchRingPreferences(
          selectedIds: [cursorOwnPoolId, cursorOtherPoolId],
        ),
      ),
      'Cursor plan 53% left',
    );
  });

  test('catalog titles name the family without repeating it', () {
    WatchRingMetric metric(String id, String label) => WatchRingMetric(
      id: id,
      label: label,
      usedPercent: 10,
      status: ProviderStatus.ok,
    );

    // The collision this exists for: one `Weekly plan` per provider.
    expect(
      metric('allowance.codex.codex-weekly', 'Weekly plan').catalogTitle,
      'Codex · Weekly plan',
    );
    expect(
      metric('allowance.claude.claude-seven-day', 'Weekly plan').catalogTitle,
      'Claude · Weekly plan',
    );

    // Already opens with its family.
    expect(
      metric(
        'allowance.cursor.cursor-plan-models',
        'Cursor Models',
      ).catalogTitle,
      'Cursor Models',
    );
    // A budget ring names its connection: three `Month` rows are ambiguous.
    expect(
      metric('budget.anthropic.platform.month', 'Month').catalogTitle,
      'Anthropic platform · Month',
    );
    // Unknown connection key — keep the bare period rather than invent one.
    expect(metric('budget.mock.plan.today', 'Today').catalogTitle, 'Today');
  });

  test('excludes purchased Claude Extra usage from watch ring catalog', () {
    final dash = _claudeCodexSnapshot(
      fiveHourUsed: 40,
      sevenDayUsed: 70,
      codexUsed: 10,
    );
    final claude = Map<String, Object?>.from(
      (dash.toJson()['accounts'] as List).firstWhere(
            (account) => (account as Map)['provider'] == 'claude',
          )
          as Map,
    );
    final allowances = List<Object?>.from(claude['allowances'] as List);
    allowances.add({
      'id': 'claude-extra-usage',
      'source': 'purchased',
      'label': 'Extra usage',
      'usedPercent': 84.0,
      'used': {'value': '84.90', 'unit': 'credits'},
      'limit': {'value': '100.00', 'unit': 'credits'},
      'remaining': {'value': '15.10', 'unit': 'credits'},
      'unlimited': false,
      'windowMinutes': null,
      'resetsAt': null,
      'status': 'warning',
    });
    claude['allowances'] = allowances;
    final withExtra = DashboardSnapshot.fromJson({
      ...dash.toJson(),
      'accounts': [claude, ...(dash.toJson()['accounts'] as List).skip(1)],
    });

    final catalogIds =
        watchRingCatalog(withExtra).map((ring) => ring.id).toList();
    expect(catalogIds, contains(claudePlanRingId));
    expect(catalogIds, isNot(contains('allowance.claude.claude-extra-usage')));
  });
}

/// A plan window plus a spend-reporting platform connection: Anthropic
/// platform reports Today (no limit yet) and Month (limit set), never Week.
DashboardSnapshot _planAndBudgetSnapshot() {
  final source = DashboardSnapshot.fromJsonString(
    File('../../fixtures/snapshots/dashboard_today.json').readAsStringSync(),
  );
  final codex = _asPlanConnection(
    source.primaryAccount!.toJson()
      ..['accountId'] = 'codex-local'
      ..['provider'] = 'codex'
      ..['allowances'] = [
        _planAllowance(
          id: 'codex-weekly',
          label: 'Weekly plan',
          usedPercent: 55,
          windowMinutes: 10080,
        ),
      ]
      ..['buckets'] = <Object>[]
      ..['modelBreakdown'] = <Object>[],
    'openai.plan',
  );
  final platform =
      source.primaryAccount!.toJson()
        ..['accountId'] = 'anthropic-platform'
        ..['provider'] = 'claude'
        ..['connection'] = 'anthropic.platform'
        ..['allowances'] = <Object>[]
        ..['buckets'] = <Object>[]
        ..['modelBreakdown'] = <Object>[]
        ..['today'] = _spentBudget('today')
        ..['week'] = _reportsNothingBudget('week')
        ..['month'] = _spentBudget('month', usedPercent: 40);

  return DashboardSnapshot.fromJson(
    source.toJson()..['accounts'] = [codex, platform],
  );
}

/// Plan connections report no spend, so they offer no budget ring.
Map<String, dynamic> _asPlanConnection(
  Map<String, dynamic> account,
  String connection,
) {
  return account
    ..['connection'] = connection
    ..['today'] = _reportsNothingBudget('today')
    ..['week'] = _reportsNothingBudget('week')
    ..['month'] = _reportsNothingBudget('month');
}

Map<String, dynamic> _reportsNothingBudget(String period) {
  return {
    'period': period,
    'spent': null,
    'limit': null,
    'remaining': null,
    'usedPercent': null,
    'projectedTotal': null,
    'status': 'unknown',
  };
}

/// Reported spend; a percentage only exists once the user set a local limit.
Map<String, dynamic> _spentBudget(String period, {double? usedPercent}) {
  final limited = usedPercent != null;
  return {
    'period': period,
    'spent': {'minorUnits': 4000, 'currency': 'USD'},
    'limit': limited ? {'minorUnits': 10000, 'currency': 'USD'} : null,
    'remaining': limited ? {'minorUnits': 6000, 'currency': 'USD'} : null,
    'usedPercent': usedPercent,
    'projectedTotal': null,
    'status': 'ok',
  };
}

DashboardSnapshot _claudeCodexSnapshot({
  required double fiveHourUsed,
  required double sevenDayUsed,
  required double codexUsed,
}) {
  final source = DashboardSnapshot.fromJsonString(
    File('../../fixtures/snapshots/dashboard_today.json').readAsStringSync(),
  );
  final claude = _asPlanConnection(
    source.primaryAccount!.toJson()
      ..['accountId'] = 'claude-local'
      ..['provider'] = 'claude'
      ..['allowances'] = [
        _planAllowance(
          id: 'claude-five-hour',
          label: '5-hour session',
          usedPercent: fiveHourUsed,
          windowMinutes: 300,
        ),
        _planAllowance(
          id: 'claude-seven-day',
          label: 'Weekly plan',
          usedPercent: sevenDayUsed,
          windowMinutes: 10080,
        ),
      ]
      ..['buckets'] = <Object>[]
      ..['modelBreakdown'] = <Object>[],
    'anthropic.plan',
  );
  final codex = _asPlanConnection(
    source.primaryAccount!.toJson()
      ..['accountId'] = 'codex-local'
      ..['provider'] = 'codex'
      ..['allowances'] = [
        _planAllowance(
          id: 'codex-weekly',
          label: 'Weekly plan',
          usedPercent: codexUsed,
          windowMinutes: 10080,
        ),
      ]
      ..['buckets'] = <Object>[]
      ..['modelBreakdown'] = <Object>[],
    'openai.plan',
  );

  return DashboardSnapshot.fromJson(
    source.toJson()..['accounts'] = [claude, codex],
  );
}

/// Cursor with both plan pools alive, beside a tighter Codex plan.
DashboardSnapshot _cursorPairAndCodexSnapshot() {
  final source = DashboardSnapshot.fromJsonString(
    File('../../fixtures/snapshots/dashboard_today.json').readAsStringSync(),
  );
  final cursor = _asPlanConnection(
    source.primaryAccount!.toJson()
      ..['accountId'] = 'cursor-local'
      ..['provider'] = 'cursor'
      ..['allowances'] = [
        _planAllowance(
          id: 'cursor-plan-models',
          label: 'Cursor Models',
          usedPercent: 47,
          windowMinutes: 43200,
        ),
        _planAllowance(
          id: 'cursor-plan-other',
          label: 'Other Models',
          usedPercent: 38,
          windowMinutes: 43200,
        ),
      ]
      ..['buckets'] = <Object>[]
      ..['modelBreakdown'] = <Object>[],
    'cursor.plan',
  );
  final codex = _asPlanConnection(
    source.primaryAccount!.toJson()
      ..['accountId'] = 'codex-local'
      ..['provider'] = 'codex'
      ..['allowances'] = [
        _planAllowance(
          id: 'codex-weekly',
          label: 'Weekly plan',
          usedPercent: 92,
          windowMinutes: 10080,
        ),
      ]
      ..['buckets'] = <Object>[]
      ..['modelBreakdown'] = <Object>[],
    'openai.plan',
  );

  return DashboardSnapshot.fromJson(
    source.toJson()..['accounts'] = [cursor, codex],
  );
}

DashboardSnapshot _twoPlanProvidersSnapshot({
  required double codexUsed,
  required double claudeUsed,
  double? codexCredits,
  double? claudeCredits,
  bool claudeUnlimitedPurchased = false,
}) {
  final source = DashboardSnapshot.fromJsonString(
    File('../../fixtures/snapshots/dashboard_today.json').readAsStringSync(),
  );
  final claudeAllowances = <Map<String, dynamic>>[
    _planAllowance(
      id: 'claude-seven-day',
      label: 'Weekly plan',
      usedPercent: claudeUsed,
      windowMinutes: 10080,
    ),
  ];
  if (claudeUnlimitedPurchased) {
    claudeAllowances.add(_purchasedAllowance(unlimited: true));
  } else if (claudeCredits != null) {
    claudeAllowances.add(_purchasedAllowance(remaining: claudeCredits));
  }
  final codexAllowances = <Map<String, dynamic>>[
    _planAllowance(
      id: 'codex-weekly',
      label: 'Weekly plan',
      usedPercent: codexUsed,
      windowMinutes: 10080,
    ),
  ];
  if (codexCredits != null) {
    codexAllowances.add(_purchasedAllowance(remaining: codexCredits));
  }

  final claude = _asPlanConnection(
    source.primaryAccount!.toJson()
      ..['accountId'] = 'claude-local'
      ..['provider'] = 'claude'
      ..['allowances'] = claudeAllowances
      ..['buckets'] = <Object>[]
      ..['modelBreakdown'] = <Object>[],
    'anthropic.plan',
  );
  final codex = _asPlanConnection(
    source.primaryAccount!.toJson()
      ..['accountId'] = 'codex-local'
      ..['provider'] = 'codex'
      ..['allowances'] = codexAllowances
      ..['buckets'] = <Object>[]
      ..['modelBreakdown'] = <Object>[],
    'openai.plan',
  );

  return DashboardSnapshot.fromJson(
    source.toJson()..['accounts'] = [claude, codex],
  );
}

Map<String, dynamic> _planAllowance({
  required String id,
  required String label,
  required double usedPercent,
  required int windowMinutes,
}) {
  return {
    'id': id,
    'source': 'plan',
    'label': label,
    'usedPercent': usedPercent,
    'used': null,
    'limit': null,
    'remaining': null,
    'unlimited': false,
    'windowMinutes': windowMinutes,
    'resetsAt': null,
    'status': 'ok',
  };
}

Map<String, dynamic> _purchasedAllowance({
  double? remaining,
  bool unlimited = false,
}) {
  return {
    'id': 'purchased-credits',
    'source': 'purchased',
    'label': 'Purchased credits',
    'usedPercent': null,
    'used': null,
    'limit': null,
    'remaining':
        remaining == null
            ? null
            : {'value': remaining.toString(), 'unit': 'credits'},
    'unlimited': unlimited,
    'windowMinutes': null,
    'resetsAt': null,
    'status': 'ok',
  };
}
