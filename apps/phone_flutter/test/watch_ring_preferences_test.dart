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

  test('surface order puts tightest remaining outermost and drops exhausted', () {
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
}
