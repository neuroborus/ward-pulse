import 'package:flutter/foundation.dart';
import 'package:ward_pulse_bindings/ward_pulse_bindings.dart';

import '../providers/connection_lifecycle.dart';
import 'dashboard_models.dart';

typedef DashboardJsonLoader = String Function();
typedef ReportingObserver = void Function(ConnectionReportingUpdate update);

abstract class DashboardRepository {
  const DashboardRepository();

  Future<DashboardSnapshot> load();

  Future<DashboardSnapshot> loadObserved(ReportingObserver observer) => load();

  Future<bool> isFailureCurrent(DashboardLoadException failure) =>
      isSnapshotCurrent(failure.selection);

  void invalidate() {}

  Future<bool> isSnapshotCurrent(DashboardSnapshot snapshot) async => true;

  /// Whether automatic cadence claimed under [version] still belongs to
  /// [connection]'s confirmed credential. Sources without that proof keep it.
  Future<bool> ownsAutomaticCadence(
    String connection,
    CredentialVersion version,
  ) async => true;
}

final class DashboardLoadException implements Exception {
  const DashboardLoadException({
    this.issue = DashboardSyncIssue.dashboardUnavailable,
    this.details,
    this.syncRejection,
    this.connectionVersions = const {},
    this.snapshotOrdering = const {},
  }) : reportingOutcomes = const [];

  DashboardLoadException.withOutcomes({
    this.issue = DashboardSyncIssue.dashboardUnavailable,
    this.details,
    this.syncRejection,
    required Iterable<ConnectionReportingOutcome> reportingOutcomes,
    Map<String, Map<String, String>> connectionVersions = const {},
    Map<String, SnapshotOrdering> snapshotOrdering = const {},
  }) : reportingOutcomes = List.unmodifiable(reportingOutcomes),
       connectionVersions = Map.unmodifiable({
         for (final entry in connectionVersions.entries)
           entry.key: Map<String, String>.unmodifiable(entry.value),
       }),
       snapshotOrdering = Map.unmodifiable(snapshotOrdering);

  final DashboardSyncIssue issue;
  final String? details;
  final ConnectionRejection? syncRejection;
  final List<ConnectionReportingOutcome> reportingOutcomes;
  final Map<String, Map<String, String>> connectionVersions;
  final Map<String, SnapshotOrdering> snapshotOrdering;

  /// The empty selection this failure proves: its credential versions, cache
  /// ordering and outcomes, without accounts.
  DashboardSnapshot get selection => DashboardSnapshot.empty()
      .withConnectionVersions(
        connectionVersions,
        snapshotOrdering: snapshotOrdering,
      )
      .withReportingOutcomes(reportingOutcomes);

  DashboardLoadException withConnectionVersions(
    Map<String, Map<String, String>> versions, {
    Map<String, SnapshotOrdering>? snapshotOrdering,
  }) => DashboardLoadException.withOutcomes(
    issue: issue,
    details: details,
    syncRejection: syncRejection,
    reportingOutcomes: reportingOutcomes,
    connectionVersions: versions,
    snapshotOrdering: snapshotOrdering ?? this.snapshotOrdering,
  );

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

/// The whole-second UTC anchor the Rust generator rebases samples to.
String demoCaptureAnchor(DateTime time) =>
    '${time.toUtc().toIso8601String().substring(0, 19)}Z';

/// Seeded synthetic dashboards: Debug Mock data or the public Demo sample.
///
/// Cached until [invalidate] so automatic sync ticks stay stable; phone refresh
/// and the mode switch clear the cache and draw a new seed.
/// A valid debug seed starts a reproducible sequence instead of time-based seeds.
final class DemoDashboardRepository extends DashboardRepository {
  /// Debug Mock data: the full multi-provider fixture dashboard.
  DemoDashboardRepository({
    this.loadDebugDashboardJson = loadDebugDashboardSnapshotJson,
    this.loadDatedDebugDashboardJson = _loadDatedDebugDashboardJson,
    this.seedForLoad,
    String? debugSeed,
    String? debugAnchor,
    bool debugMode = kDebugMode,
  }) : _captureAnchor = debugMode ? debugAnchor : null,
       _clock = null {
    if (debugMode &&
        debugSeed != null &&
        !debugSeed.contains(RegExp(r'[^0-9]'))) {
      _nextSeed = int.tryParse(debugSeed);
    }
  }

  /// The public Demo sample, available in every build. Each draw is rebased
  /// to the device's current time, so its dates stay current; it omits the
  /// Claude plan the Play build pauses.
  DemoDashboardRepository.product({
    DatedDebugDashboardJsonLoader loadDashboardJson =
        loadDemoDashboardSnapshotJson,
    this.seedForLoad,
    DateTime Function()? clock,
  }) : loadDebugDashboardJson = _unavailableSeedOnlySample,
       loadDatedDebugDashboardJson = loadDashboardJson,
       _captureAnchor = null,
       _clock = clock ?? DateTime.now;

  final DebugDashboardJsonLoader loadDebugDashboardJson;
  final DatedDebugDashboardJsonLoader loadDatedDebugDashboardJson;
  final int Function()? seedForLoad;
  final String? _captureAnchor;

  /// The product sample's anchor source; `null` for Debug Mock data.
  final DateTime Function()? _clock;
  int? _nextSeed;
  DashboardSnapshot? _cached;

  static String _unavailableSeedOnlySample(int seed) =>
      throw StateError('The Demo sample requires a capture anchor.');

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
      final clock = _clock;
      final anchor =
          clock == null ? _captureAnchor : demoCaptureAnchor(clock());
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
