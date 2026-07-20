import 'package:ward_pulse_bindings/ward_pulse_bindings.dart';

import '../settings/debug_data_preferences.dart';
import 'dashboard_models.dart';

typedef DashboardJsonLoader = String Function();

abstract class DashboardRepository {
  const DashboardRepository();

  Future<DashboardSnapshot> load();

  void invalidate() {}
}

final class DashboardLoadException implements Exception {
  const DashboardLoadException({
    this.issue = DashboardSyncIssue.dashboardUnavailable,
    this.details,
  });

  final DashboardSyncIssue issue;
  final String? details;

  @override
  String toString() => issue.message;
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

final class DebugDashboardRepository extends DashboardRepository {
  const DebugDashboardRepository({
    required DashboardRepository live,
    required DebugDataPreferenceStore preferences,
    DashboardRepository mock = const RustDashboardRepository(),
  }) : _live = live,
       _mock = mock,
       _preferences = preferences;

  final DashboardRepository _live;
  final DashboardRepository _mock;
  final DebugDataPreferenceStore _preferences;

  @override
  Future<DashboardSnapshot> load() async {
    final useMock = await _preferences.readMockDataEnabled();
    return useMock ? _mock.load() : _live.load();
  }

  @override
  void invalidate() {
    _live.invalidate();
    _mock.invalidate();
  }
}

class ValueDashboardRepository extends DashboardRepository {
  const ValueDashboardRepository(this.snapshot);

  final DashboardSnapshot snapshot;

  @override
  Future<DashboardSnapshot> load() async => snapshot;
}
