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

typedef DebugDashboardJsonLoader = String Function(int seed);

/// Debug Mock data: full multi-provider fixture dashboard.
///
/// Cached until [invalidate] so automatic sync ticks stay stable; phone refresh
/// and the Mock data toggle clear the cache and draw a new seed.
final class DemoDashboardRepository extends DashboardRepository {
  DemoDashboardRepository({
    this.loadDebugDashboardJson = loadDebugDashboardSnapshotJson,
    this.seedForLoad,
  });

  final DebugDashboardJsonLoader loadDebugDashboardJson;
  final int Function()? seedForLoad;
  DashboardSnapshot? _cached;

  @override
  Future<DashboardSnapshot> load() async {
    final cached = _cached;
    if (cached != null) {
      return cached;
    }
    try {
      final seed = seedForLoad?.call() ?? DateTime.now().microsecondsSinceEpoch;
      final snapshot = DashboardSnapshot.fromJsonString(
        loadDebugDashboardJson(seed),
      );
      _cached = snapshot;
      return snapshot;
    } catch (_) {
      throw const DashboardLoadException();
    }
  }

  @override
  void invalidate() {
    _cached = null;
  }
}

final class DebugDashboardRepository extends DashboardRepository {
  DebugDashboardRepository({
    required DashboardRepository live,
    required DebugDataPreferenceStore preferences,
    DashboardRepository? mock,
  }) : _live = live,
       _mock = mock ?? DemoDashboardRepository(),
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

/// Root fallback when no credential-backed connection is configured.
///
/// Returns an empty live snapshot (not an error) so the phone can push a
/// cleared watch summary and Wear Glance refresh still has a handler target.
final class NoProvidersDashboardRepository extends DashboardRepository {
  const NoProvidersDashboardRepository();

  @override
  Future<DashboardSnapshot> load() async => DashboardSnapshot.empty();
}
