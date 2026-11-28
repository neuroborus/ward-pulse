import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:ward_pulse_bindings/ward_pulse_bindings.dart'
    show mergeDashboardSnapshotsJson;
import 'package:ward_pulse_watch_sync/ward_pulse_watch_sync.dart';

import '../dashboard/connection_snapshot_cache.dart';
import '../dashboard/dashboard_models.dart';
import '../providers/claude_plan_pause.dart';
import '../providers/provider_connection.dart';
import '../settings/watch_ring_preferences.dart';
import '../widget/phone_widget_sync.dart';
import 'data_mode.dart';
import 'manual_refresh_window.dart';
import 'selected_data_freshness.dart';
import 'watch_credits_glance.dart';

/// The ordered summary in the `summary` key of the watch Data Item.
const watchSummarySchemaVersion = 10;

/// The `payload` projection that Wear apps without v10 read.
const legacyWatchSummarySchemaVersion = 9;

/// A newer accepted load, or a settings save after the revision the summary
/// was built from, retired a [WatchSyncService.sync]; a fresh read answers.
final class WatchSummarySuperseded implements Exception {
  const WatchSummarySuperseded();
}

abstract interface class WatchSyncService {
  /// Queues [snapshot] for Wear. [isCurrent] proves its load and credential
  /// ownership again at the native send boundary, after Google Play services
  /// is ready; a `false` answer drops the summary for its newer owner and
  /// throws [WatchSummarySuperseded]. In
  /// Live, Android then admits the send with [snapshot]'s native selection
  /// proof, its credential versions and cache ordering, in one step. A
  /// credential retirement or cache write after that answer throws
  /// [DataModeRetired] instead of publishing.
  ///
  /// Under a [PhoneWidgetPublicationInput.current] claim, the summary is
  /// ordered by the shared accepted load and settings revision too: once
  /// either is replaced, it throws [WatchSummarySuperseded] instead of
  /// publishing, and none of its later puts is sent.
  Future<void> sync(
    DashboardSnapshot snapshot,
    WatchRingPreferences ringPreferences, {
    DateTime? manualRefreshAnchorAt,
    bool mockDataMode = false,
    Future<bool> Function()? isCurrent,
  });

  /// Whether Wear's desired summary is a published v10 summary of the current
  /// data-mode generation. A cadence-skipped load republishes retained input
  /// until it is: an upgrade from v9, or the empty summary a mode transition
  /// left. Unknown state reads as established. Asking also resumes pending
  /// native publication.
  Future<bool> isEstablished();

  /// Replaces a summary the data-mode record owes Wear, or resumes a pending
  /// or retrying native publication: warm resume and explicit sync, also when
  /// the current load cannot build a replacement. Never throws.
  Future<void> resume();

  /// Binds warm requests and claims the pending launch request before loading.
  Future<WatchRefreshIntent?> bindWatchRefreshListener(
    void Function(WatchRefreshIntent) onRefresh,
  );

  void unbindWatchRefreshListener();
}

/// A tap can refresh only the operation captured at native ingress: a v10 tap
/// naming the current install and generation, or a v9 tap in generation 0.
final class WatchRefreshIntent {
  const WatchRefreshIntent.resend() : _state = null, _requestId = null;

  const WatchRefreshIntent._(this._state, this._requestId);

  factory WatchRefreshIntent.fromMessage(Object? message) {
    final ordered = message is Map && message['ordered'] == true;
    if (message
        case {
          'kind': 'refresh',
          'generation': final int generation,
          'installId': final String installId,
          'requestId': final String requestId,
          'mode': final String mode,
        }
        when (generation == 0 || ordered) &&
            generation >= 0 &&
            installId.isNotEmpty &&
            requestId.isNotEmpty) {
      try {
        return WatchRefreshIntent._(
          DataModeState(
            installId: installId,
            generation: generation,
            mode: DataMode.parse(mode),
          ),
          requestId,
        );
      } on StateError {
        // Unknown ownership can only request a resend.
      }
    }
    return const WatchRefreshIntent.resend();
  }

  /// The owner and request captured at native ingress; `null` for a resend.
  final DataModeState? _state;
  final String? _requestId;

  /// Starts a cache-only resend if the captured owner is no longer current.
  Future<DataModeOperation> operation(DataModeAuthority authority) async {
    final state = _state;
    if (state != null) {
      final current = await authority.read();
      if (current.installId == state.installId &&
          current.generation == state.generation &&
          current.mode == state.mode &&
          await authority.isCurrent(state.generation)) {
        return DataModeOperation(
          authority: authority,
          state: state,
          requestId: _requestId!,
        );
      }
    }
    return authority.begin(cacheOnly: true, waitForSwitch: true);
  }
}

class MethodChannelWatchSyncService implements WatchSyncService {
  const MethodChannelWatchSyncService({
    this.claudePlanPaused = claudePlanPausedInBuild,
  });

  final bool claudePlanPaused;

  static const _watchRefreshChannel = MethodChannel(
    'app.wardpulse/watch_refresh',
  );
  static const _watchRefreshMethod = 'watchRefreshRequested';
  static const _watchRefreshReadyMethod = 'watchRefreshChannelReady';

  @override
  Future<void> sync(
    DashboardSnapshot snapshot,
    WatchRingPreferences ringPreferences, {
    DateTime? manualRefreshAnchorAt,
    bool mockDataMode = false,
    Future<bool> Function()? isCurrent,
  }) async {
    // Keep the last valid publication while the owner corrects saved choices.
    if (watchRingCapacityReason(
          watchRingSelectionIds(
            snapshot,
            ringPreferences,
            claudePlanPaused: claudePlanPaused,
          ),
          claudePlanPaused: claudePlanPaused,
        ) !=
        null) {
      // Pending native work still resumes, though this sync replaces nothing.
      await resume();
      return;
    }
    final operation = DataModeOperation.current;
    final input = PhoneWidgetPublicationInput.current;
    final payload = WatchDashboardSummaryPayload.fromSnapshot(
      snapshot,
      ringPreferences,
      manualRefreshAnchorAt: manualRefreshAnchorAt,
      mockDataMode: mockDataMode,
      demoDataMode: operation?.mode == DataMode.demo,
      claudePlanPaused: claudePlanPaused,
    );
    try {
      await WardPulseWatchSync.syncSummary(
        payload.encode(),
        // Android adds the owner and order fields at the send boundary.
        summary: operation == null ? null : payload.encodeSummary(),
        generation: operation?.generation,
        isCurrent: isCurrent,
        selection:
            operation?.mode == DataMode.live
                ? snapshotSelectionProof(snapshot)
                : null,
        load: input?.load,
        settingsRevision: input?.settingsRevision,
      );
    } on PlatformException catch (error) {
      if (error.code == 'watch_summary_retired') throw DataModeRetired();
      if (error.code == 'watch_summary_superseded') {
        throw const WatchSummarySuperseded();
      }
      rethrow;
    }
  }

  @override
  Future<bool> isEstablished() async {
    try {
      return await WardPulseWatchSync.isSummaryEstablished();
    } catch (_) {
      // Unknown state cannot hold a cadence-skipped load's publication.
      return true;
    }
  }

  @override
  Future<void> resume() async {
    try {
      await WardPulseWatchSync.resumeSummary();
    } catch (_) {
      // Startup, a Wear route proof or a later sync resumes it instead.
    }
  }

  @override
  Future<WatchRefreshIntent?> bindWatchRefreshListener(
    void Function(WatchRefreshIntent) onRefresh,
  ) async {
    _watchRefreshChannel.setMethodCallHandler((call) async {
      if (call.method == _watchRefreshMethod) {
        onRefresh(WatchRefreshIntent.fromMessage(call.arguments));
      }
    });
    try {
      final pending = await _watchRefreshChannel.invokeMethod<Object?>(
        _watchRefreshReadyMethod,
      );
      return pending == null ? null : WatchRefreshIntent.fromMessage(pending);
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return const WatchRefreshIntent.resend();
    }
  }

  @override
  void unbindWatchRefreshListener() {
    _watchRefreshChannel.setMethodCallHandler(null);
  }
}

class WatchDashboardSummaryPayload {
  const WatchDashboardSummaryPayload._(this._value);

  final Map<String, Object?> _value;

  factory WatchDashboardSummaryPayload.fromSnapshot(
    DashboardSnapshot source,
    WatchRingPreferences ringPreferences, {
    DateTime? manualRefreshAnchorAt,
    DateTime? clock,
    bool mockDataMode = false,
    bool demoDataMode = false,
    bool claudePlanPaused = claudePlanPausedInBuild,
  }) {
    final planConnection = ProviderConnections.claudePlan.storageKey;
    final accounts =
        claudePlanPaused
            ? source.accounts
                .where((account) {
                  final connection =
                      account.connection ?? account.historyOwner?.connection;
                  return connection != planConnection &&
                      !(connection == null &&
                          account.provider == 'claude' &&
                          account.allowances.isNotEmpty);
                })
                .toList(growable: false)
            : source.accounts;
    final removedPlan = accounts.length != source.accounts.length;
    // Rebuild totals and health from the surviving accounts when a caller
    // supplies an older snapshot. Ordinary live snapshots are already scoped.
    final snapshot =
        !removedPlan
            ? source
            : accounts.isEmpty
            ? DashboardSnapshot.empty(generatedAt: source.generatedAt)
            : DashboardSnapshot.fromJsonString(
              mergeDashboardSnapshotsJson([
                source.withAccounts(accounts).toJsonString(),
              ]),
            );
    final alerts =
        removedPlan ||
                (claudePlanPaused &&
                    source.alertConditions.any(
                      (condition) => condition.key.connection == planConnection,
                    ))
            ? [
              for (final condition in source.alertConditions)
                if (condition.key.connection != planConnection)
                  if (condition.alert case final alert?) alert,
            ]
            : source.alerts;
    final selectionIds = watchRingSelectionIds(
      snapshot,
      ringPreferences,
      claudePlanPaused: claudePlanPaused,
    );
    final capacityReason = watchRingCapacityReason(
      selectionIds,
      claudePlanPaused: claudePlanPaused,
    );
    if (capacityReason != null) {
      throw StateError(capacityReason);
    }
    final rings = orderWatchRingsForSurface(
      resolveWatchRings(
        snapshot,
        ringPreferences,
        claudePlanPaused: claudePlanPaused,
      ),
      snapshot: snapshot,
    );
    final creditsGlance =
        ringPreferences.selectedIds?.isEmpty == true
            ? null
            : resolveWatchCreditsGlance(snapshot);
    final window = ManualRefreshWindow.fromLastSync(
      lastSyncAt: manualRefreshAnchorAt ?? snapshot.generatedAt,
      now: clock,
    );
    final isLegacyMockProvider =
        snapshot.accounts.isNotEmpty &&
        snapshot.accounts.every((account) => account.provider == 'mock');
    return WatchDashboardSummaryPayload._({
      'dataMode':
          demoDataMode
              ? 'demo'
              : mockDataMode || isLegacyMockProvider
              ? 'mock'
              : 'live',
      'generatedAt': snapshot.generatedAt.toUtc().toIso8601String(),
      'overallStatus': snapshot.overallStatus.wireName,
      'manualRefreshAllowed': window.allowed,
      'manualRefreshAvailableAt': window.availableAt?.toUtc().toIso8601String(),
      'rings': [
        for (final (ring, split) in pairWatchRings(rings))
          {
            'id': ring.id,
            'label': _ringLabel(ring),
            'usedPercent': _watchUsedPercent(ring.usedPercent!),
            'status': ring.status.wireName,
            // Budget strips read money, so it travels as structure — the
            // currency code included, or Wear would have to assume one.
            'spent': _moneyToJson(ring.spent),
            'limit': _moneyToJson(ring.limit),
            'split': split == null ? null : _splitToJson(split),
          },
      ],
      // Rings were chosen but none has a usable percentage; Wear says so
      // instead of asking the owner to choose rings again.
      if (selectionIds.isNotEmpty && rings.isEmpty)
        'selectedRingDataUnavailable': true,
      'creditsGlance': creditsGlance?.toJson(),
      'today': _budgetToJson(snapshot.todayTotal),
      'week': _budgetToJson(snapshot.weekTotal),
      'allowances': [
        for (final account in snapshot.accounts)
          for (final allowance in account.allowances)
            {
              'source': allowance.source.name,
              // Disambiguate multi-provider Usage rows on Wear (no schema bump).
              'label': '${account.providerLabel} · ${allowance.label}',
              'usedPercent': allowance.usedPercent,
              'remaining': _quantityToJson(allowance.remaining),
              if (allowance.unlimited) 'unlimited': true,
              'resetsAt': allowance.resetsAt?.toUtc().toIso8601String(),
              'status': allowance.status.wireName,
            },
      ],
      'providers': [
        for (final account in snapshot.accounts)
          {
            'provider': account.provider,
            'status': account.status.wireName,
            'todaySpent': _moneyToJson(account.today.spent),
          },
      ],
      'alerts': [
        for (final alert in alerts)
          {'severity': alert.severity, 'message': alert.message},
      ],
      'isStale': selectedDataIsStale(snapshot, [
        for (final ring in rings) ...[
          if (ring.contributor case final contributor?) contributor,
          if (providerFromRingId(ring.id) case final provider?)
            if (watchRingCreditContributor(snapshot, provider)
                case final contributor?)
              contributor,
        ],
        if (rings.isEmpty) ...?creditsGlance?.contributors,
      ]),
    });
  }

  /// The v9 `payload` projection. v9 has no product Demo, so Demo projects
  /// as a neutral empty Live summary with refresh disabled.
  String encode() => jsonEncode(
    _value['dataMode'] == 'demo'
        ? {
          'schemaVersion': legacyWatchSummarySchemaVersion,
          'dataMode': 'live',
          'generatedAt': _value['generatedAt'],
          'overallStatus': ProviderStatus.unknown.wireName,
          'manualRefreshAllowed': false,
          'manualRefreshAvailableAt': null,
          'rings': const <Object?>[],
          'creditsGlance': null,
          'today': _budgetToJson(const BudgetState.unknownPeriod('today')),
          'week': _budgetToJson(const BudgetState.unknownPeriod('week')),
          'allowances': const <Object?>[],
          'providers': const <Object?>[],
          'alerts': const <Object?>[],
          'isStale': false,
        }
        : {'schemaVersion': legacyWatchSummarySchemaVersion, ..._value},
  );

  /// The v10 body with its provenance, before Android adds `installId`,
  /// `generation` and `sequence`.
  String encodeSummary() =>
      jsonEncode({'schemaVersion': watchSummarySchemaVersion, ..._value});
}

extension _ProviderStatusWireName on ProviderStatus {
  String get wireName {
    return switch (this) {
      ProviderStatus.ok => 'ok',
      ProviderStatus.warning => 'warning',
      ProviderStatus.error => 'error',
      ProviderStatus.rateLimited => 'rateLimited',
      ProviderStatus.authRequired => 'authRequired',
      ProviderStatus.stale => 'stale',
      ProviderStatus.unknown => 'unknown',
    };
  }
}

/// Budget rings travel named (`Anthropic platform · Month`): the connection is
/// the phone's vocabulary, and three bare `Month` rows read alike on Wear.
/// Plan windows keep the pool name that Glance prefixes with its family.
Map<String, Object?> _splitToJson(WatchRingMetric ring) {
  return {
    'id': ring.id,
    'label': _ringLabel(ring),
    'usedPercent': _watchUsedPercent(ring.usedPercent!),
    'status': ring.status.wireName,
  };
}

/// Trim ordinary float noise without rounding a positive remainder to zero
/// or positive usage to none: Wear reads exact zero as a full ring.
double _watchUsedPercent(double used) {
  final rounded = double.parse(used.toStringAsFixed(1));
  if (used < 100 && rounded >= 100) return used;
  if (used > 0 && rounded <= 0) return used;
  return rounded;
}

String _ringLabel(WatchRingMetric ring) {
  return ring.id.startsWith('budget.') ? ring.catalogTitle : ring.label;
}

Map<String, Object?> _budgetToJson(BudgetState budget) {
  return {
    'period': budget.period,
    'spent': _moneyToJson(budget.spent),
    'limit': _moneyToJson(budget.limit),
    'remaining': _moneyToJson(budget.remaining),
    'usedPercent': budget.usedPercent,
    'projectedTotal': _moneyToJson(budget.projectedTotal),
    'status': budget.status.wireName,
  };
}

Map<String, Object?>? _moneyToJson(Money? money) {
  if (money == null) {
    return null;
  }

  return {'minorUnits': money.minorUnits, 'currency': money.currency};
}

Map<String, Object?>? _quantityToJson(Quantity? quantity) {
  if (quantity == null) {
    return null;
  }

  return {'value': quantity.value, 'unit': quantity.unit};
}
