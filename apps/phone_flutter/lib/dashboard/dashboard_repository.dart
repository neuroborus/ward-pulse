import 'package:flutter/foundation.dart';
import 'package:ward_pulse_bindings/ward_pulse_bindings.dart';

import '../settings/debug_data_preferences.dart';
import 'dashboard_models.dart';

typedef DashboardJsonLoader = String Function();
typedef ReportingObserver = void Function(ConnectionReportingUpdate update);

abstract class DashboardRepository {
  const DashboardRepository();

  Future<DashboardSnapshot> load();

  Future<DashboardSnapshot> loadObserved(ReportingObserver observer) => load();

  Future<bool> isFailureCurrent(DashboardLoadException failure) =>
      isSnapshotCurrent(
        DashboardSnapshot.empty().withReportingOutcomes(
          failure.reportingOutcomes,
        ),
      );

  void invalidate() {}
  Future<void> clearPersistentSnapshots() async {
    invalidate();
  }

  Future<bool> isSnapshotCurrent(DashboardSnapshot snapshot) async => true;
}

final class DashboardLoadException implements Exception {
  const DashboardLoadException({
    this.issue = DashboardSyncIssue.dashboardUnavailable,
    this.details,
  }) : reportingOutcomes = const [];

  DashboardLoadException.withOutcomes({
    this.issue = DashboardSyncIssue.dashboardUnavailable,
    this.details,
    required Iterable<ConnectionReportingOutcome> reportingOutcomes,
  }) : reportingOutcomes = List.unmodifiable(reportingOutcomes);

  final DashboardSyncIssue issue;
  final String? details;
  final List<ConnectionReportingOutcome> reportingOutcomes;

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
typedef DatedDebugDashboardJsonLoader =
    String Function(int seed, String anchor);

String _loadDatedDebugDashboardJson(int seed, String anchor) =>
    loadDebugDashboardSnapshotJson(seed, captureAnchor: anchor);

/// Debug Mock data: full multi-provider fixture dashboard.
///
/// Cached until [invalidate] so automatic sync ticks stay stable; phone refresh
/// and the Mock data toggle clear the cache and draw a new seed.
/// A valid debug seed starts a reproducible sequence instead of time-based seeds.
final class DemoDashboardRepository extends DashboardRepository {
  DemoDashboardRepository({
    this.loadDebugDashboardJson = loadDebugDashboardSnapshotJson,
    this.loadDatedDebugDashboardJson = _loadDatedDebugDashboardJson,
    this.seedForLoad,
    String? debugSeed,
    String? debugAnchor,
    bool debugMode = kDebugMode,
  }) : _captureAnchor = debugMode ? debugAnchor : null {
    if (debugMode &&
        debugSeed != null &&
        !debugSeed.contains(RegExp(r'[^0-9]'))) {
      _nextSeed = int.tryParse(debugSeed);
    }
  }

  final DebugDashboardJsonLoader loadDebugDashboardJson;
  final DatedDebugDashboardJsonLoader loadDatedDebugDashboardJson;
  final int Function()? seedForLoad;
  final String? _captureAnchor;
  int? _nextSeed;
  DashboardSnapshot? _cached;

  @override
  Future<DashboardSnapshot> load() async {
    final cached = _cached;
    if (cached != null) {
      return cached;
    }
    try {
      final seed =
          _nextSeed ??
          seedForLoad?.call() ??
          DateTime.now().microsecondsSinceEpoch;
      final anchor = _captureAnchor;
      final snapshot = DashboardSnapshot.fromJsonString(
        anchor == null
            ? loadDebugDashboardJson(seed)
            : loadDatedDebugDashboardJson(seed, anchor),
      );
      _cached = snapshot;
      return snapshot;
    } catch (_) {
      throw const DashboardLoadException();
    }
  }

  @override
  void invalidate() {
    final seed = _nextSeed;
    if (_cached != null && seed != null) {
      _nextSeed = seed == 9223372036854775807 ? 0 : seed + 1;
    }
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
  Future<DashboardSnapshot> loadObserved(ReportingObserver observer) async {
    final useMock = await _preferences.readMockDataEnabled();
    return useMock ? _mock.load() : _live.loadObserved(observer);
  }

  @override
  Future<void> clearPersistentSnapshots() async {
    await _live.clearPersistentSnapshots();
    _mock.invalidate();
  }

  @override
  Future<bool> isSnapshotCurrent(DashboardSnapshot snapshot) =>
      _live.isSnapshotCurrent(snapshot);
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
