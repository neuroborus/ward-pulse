import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ward_pulse_phone/dashboard/dashboard_models.dart';
import 'package:ward_pulse_phone/dashboard/provider_status_severity.dart';

void main() {
  test('worst status of nothing is unknown', () {
    expect(worstProviderStatus([]), ProviderStatus.unknown);
  });

  test('ranks statuses exactly like the Rust core', () {
    final order = _rustSeverityOrder();
    expect(order.toSet(), ProviderStatus.values.toSet());

    for (var lower = 0; lower < order.length; lower++) {
      for (var higher = lower + 1; higher < order.length; higher++) {
        final pair = [order[lower], order[higher]];

        expect(worstProviderStatus(pair), order[higher], reason: '$pair');
        expect(
          worstProviderStatus(pair.reversed),
          order[higher],
          reason: '$pair reversed',
        );
      }
    }
  });
}

/// Statuses ordered by `ProviderStatus::severity` in the Rust core, weakest
/// first.
///
/// Scoped to the `fn severity` body so neighbouring `match` arms cannot leak in.
List<ProviderStatus> _rustSeverityOrder() {
  final source =
      File('../../core/ward-pulse-core/src/model/mod.rs').readAsStringSync();
  final table = RegExp(
    r'fn severity.*?\n    \}',
    dotAll: true,
  ).firstMatch(source);
  expect(table, isNotNull, reason: 'severity not found in Rust');

  final ranks = {
    for (final match in RegExp(
      r'Self::(\w+) => (\d+),',
    ).allMatches(table!.group(0)!))
      ProviderStatus.values.byName(_dartName(match.group(1)!)): int.parse(
        match.group(2)!,
      ),
  };
  expect(ranks, isNotEmpty, reason: 'no severities parsed from Rust');
  // A tie would make the order below ambiguous and the comparisons meaningless.
  expect(
    ranks.values.toSet(),
    hasLength(ranks.length),
    reason: 'Rust severities must stay distinct',
  );

  return ranks.keys.toList()
    ..sort((left, right) => ranks[left]!.compareTo(ranks[right]!));
}

/// `RateLimited` in Rust is `rateLimited` in Dart.
String _dartName(String rustVariant) {
  return rustVariant[0].toLowerCase() + rustVariant.substring(1);
}
