import 'package:ward_pulse_bindings/ward_pulse_bindings.dart';

import 'dashboard_models.dart';

typedef DashboardJsonLoader = String Function();

abstract class DashboardRepository {
  const DashboardRepository();

  Future<DashboardSnapshot> load();

  void invalidate() {}
}

final class DashboardLoadException implements Exception {
  const DashboardLoadException();

  @override
  String toString() => 'Dashboard data is unavailable.';
}

final class RustDashboardRepository extends DashboardRepository {
  const RustDashboardRepository({
    this.loadDashboardJson = loadDashboardSnapshotJson,
  });

  final DashboardJsonLoader loadDashboardJson;

  @override
  Future<DashboardSnapshot> load() async {
    try {
      return DashboardSnapshot.fromJsonString(loadDashboardJson());
    } catch (_) {
      throw const DashboardLoadException();
    }
  }
}

class ValueDashboardRepository extends DashboardRepository {
  const ValueDashboardRepository(this.snapshot);

  final DashboardSnapshot snapshot;

  @override
  Future<DashboardSnapshot> load() async => snapshot;
}
