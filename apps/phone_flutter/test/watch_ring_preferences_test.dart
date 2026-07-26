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

  test('clamps stored ids to four slots', () {
    const preferences = WatchRingPreferences(
      selectedIds: ['a', 'b', 'c', 'd', 'e'],
    );

    expect(preferences.clampedIds, ['a', 'b', 'c', 'd']);
    expect(jsonEncode(preferences.clampedIds), '["a","b","c","d"]');
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

    expect(orderWatchRingsForSurface(rings).map((ring) => ring.id), [
      'c',
      'a',
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
      final collapsed = collapseClaudePlanRing(dash.accounts
          .firstWhere((a) => a.provider == 'claude')
          .allowances)!;

      expect(collapsed.id, claudePlanRingId);
      expect(collapsed.label, 'Weekly');
      expect(collapsed.settingsTitle, 'Claude plan');
      expect(collapsed.settingsSubtitle, 'Weekly · 30% left · OK');
      expect(collapsed.usedPercent, 70);
    });

    test('tie-break prefers 5h over weekly', () {
      final dash = _claudeCodexSnapshot(
        fiveHourUsed: 55,
        sevenDayUsed: 55,
        codexUsed: 10,
      );
      final collapsed = collapseClaudePlanRing(dash.accounts
          .firstWhere((a) => a.provider == 'claude')
          .allowances)!;

      expect(collapsed.label, '5h');
      expect(collapsed.usedPercent, 55);
    });

    test('prefers non-exhausted window over exhausted tighter weekly', () {
      final dash = _claudeCodexSnapshot(
        fiveHourUsed: 40,
        sevenDayUsed: 100,
        codexUsed: 10,
      );
      final collapsed = collapseClaudePlanRing(dash.accounts
          .firstWhere((a) => a.provider == 'claude')
          .allowances)!;

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
        [
          'budget.today',
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
      );

      expect(rings.map((r) => r.id), [
        claudePlanRingId,
        'allowance.codex.codex-weekly',
      ]);
      expect(rings.map((r) => r.label), ['Weekly', 'Weekly plan']);
    });
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
  Map<String, dynamic> allowance({
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

  final claude = source.primaryAccount!.toJson()
    ..['accountId'] = 'claude-local'
    ..['provider'] = 'claude'
    ..['allowances'] = [
      allowance(
        id: 'claude-five-hour',
        label: '5-hour session',
        usedPercent: fiveHourUsed,
        windowMinutes: 300,
      ),
      allowance(
        id: 'claude-seven-day',
        label: 'Weekly plan',
        usedPercent: sevenDayUsed,
        windowMinutes: 10080,
      ),
    ]
    ..['buckets'] = <Object>[]
    ..['modelBreakdown'] = <Object>[];
  final codex = source.primaryAccount!.toJson()
    ..['accountId'] = 'codex-local'
    ..['provider'] = 'codex'
    ..['allowances'] = [
      allowance(
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
