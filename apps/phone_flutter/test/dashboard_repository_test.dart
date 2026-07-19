import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ward_pulse_phone/dashboard/dashboard_repository.dart';

void main() {
  test('loads a Rust-produced dashboard JSON document', () async {
    final fixture =
        File(
          '../../fixtures/snapshots/dashboard_today.json',
        ).readAsStringSync();
    final repository = RustDashboardRepository(
      loadDashboardJson: () => fixture,
    );

    final snapshot = await repository.load();

    expect(snapshot.accounts.single.accountId, 'mock-local');
  });

  test('maps bridge failures to a safe dashboard error', () {
    final repository = RustDashboardRepository(
      loadDashboardJson: () => throw StateError('native details'),
    );

    expect(repository.load(), throwsA(isA<DashboardLoadException>()));
  });
}
