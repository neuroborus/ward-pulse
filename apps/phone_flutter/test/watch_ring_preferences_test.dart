import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ward_pulse_phone/dashboard/dashboard_models.dart';
import 'package:ward_pulse_phone/settings/watch_ring_preferences.dart';

void main() {
  final snapshot = DashboardSnapshot.fromJsonString(
    File('../../fixtures/snapshots/dashboard_today.json').readAsStringSync(),
  );

  test('defaults to the first available percent metrics when unset', () {
    final rings = resolveWatchRings(snapshot, const WatchRingPreferences());

    expect(rings.map((ring) => ring.id), [
      'budget.today',
      'budget.week',
      'budget.month',
    ]);
    expect(rings.every((ring) => ring.usedPercent != null), isTrue);
  });

  test('honors an explicit empty selection', () {
    final rings = resolveWatchRings(
      snapshot,
      const WatchRingPreferences(selectedIds: []),
    );

    expect(rings, isEmpty);
  });

  test('keeps selection order and drops unavailable ids', () {
    final rings = resolveWatchRings(
      snapshot,
      const WatchRingPreferences(
        selectedIds: ['budget.week', 'missing', 'budget.today'],
      ),
    );

    expect(rings.map((ring) => ring.id), ['budget.week', 'budget.today']);
  });

  test('clamps stored ids to three slots', () {
    const preferences = WatchRingPreferences(
      selectedIds: ['a', 'b', 'c', 'd', 'e'],
    );

    expect(preferences.clampedIds, ['a', 'b', 'c']);
    expect(jsonEncode(preferences.clampedIds), '["a","b","c"]');
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
          'budget.today',
          'allowance.claude.claude-five-hour',
          'allowance.claude.claude-seven-day',
          'allowance.codex.codex-weekly',
        ]),
        ['budget.today', claudePlanRingId, 'allowance.codex.codex-weekly'],
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
      ['allowance.cursor.cursor-plan-models'],
    );
  });

  test('includes Cursor Models and Other Models in watch ring catalog', () {
    final cursor = Map<String, Object?>.from(
      (snapshot.toJson()['accounts'] as List).first as Map,
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

    final catalogIds =
        watchRingCatalog(withCursor).map((ring) => ring.id).toList();
    expect(catalogIds, contains('allowance.cursor.cursor-plan-models'));
    expect(catalogIds, contains('allowance.cursor.cursor-plan-other'));
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
    // Budgets belong to no family.
    expect(metric('budget.today', 'Today').catalogTitle, 'Today');
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

DashboardSnapshot _claudeCodexSnapshot({
  required double fiveHourUsed,
  required double sevenDayUsed,
  required double codexUsed,
}) {
  final source = DashboardSnapshot.fromJsonString(
    File('../../fixtures/snapshots/dashboard_today.json').readAsStringSync(),
  );
  final claude =
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
        ..['modelBreakdown'] = <Object>[];
  final codex =
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
        ..['modelBreakdown'] = <Object>[];

  return DashboardSnapshot.fromJson(
    source.toJson()..['accounts'] = [claude, codex],
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

  final claude =
      source.primaryAccount!.toJson()
        ..['accountId'] = 'claude-local'
        ..['provider'] = 'claude'
        ..['allowances'] = claudeAllowances
        ..['buckets'] = <Object>[]
        ..['modelBreakdown'] = <Object>[];
  final codex =
      source.primaryAccount!.toJson()
        ..['accountId'] = 'codex-local'
        ..['provider'] = 'codex'
        ..['allowances'] = codexAllowances
        ..['buckets'] = <Object>[]
        ..['modelBreakdown'] = <Object>[];

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
