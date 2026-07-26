import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';

import '../dashboard/dashboard_models.dart';
import '../settings/consumption_display_preferences.dart';
import '../settings/watch_ring_preferences.dart';
import 'manual_refresh_window.dart';
import 'watch_credits_glance.dart';

abstract interface class WatchSyncService {
  Future<void> sync(
    DashboardSnapshot snapshot,
    ConsumptionDisplayPreferences displayPreferences,
    WatchRingPreferences ringPreferences, {
    DateTime? manualRefreshAnchorAt,
  });

  /// Native → Dart: Wear Glance asked the phone to sync providers.
  void bindWatchRefreshListener(void Function() onRefresh);

  void unbindWatchRefreshListener();
}

class MethodChannelWatchSyncService implements WatchSyncService {
  const MethodChannelWatchSyncService();

  static const _channel = MethodChannel('app.wardpulse/watch_sync');
  static const _watchRefreshMethod = 'watchRefreshRequested';
  static const _watchRefreshReadyMethod = 'watchRefreshChannelReady';

  @override
  Future<void> sync(
    DashboardSnapshot snapshot,
    ConsumptionDisplayPreferences displayPreferences,
    WatchRingPreferences ringPreferences, {
    DateTime? manualRefreshAnchorAt,
  }) {
    return _channel.invokeMethod<void>(
      'syncWatchSummary',
      WatchDashboardSummaryPayload.fromSnapshot(
        snapshot,
        displayPreferences,
        ringPreferences,
        manualRefreshAnchorAt: manualRefreshAnchorAt,
      ).encode(),
    );
  }

  @override
  void bindWatchRefreshListener(void Function() onRefresh) {
    _channel.setMethodCallHandler((call) async {
      if (call.method == _watchRefreshMethod) {
        onRefresh();
      }
    });
    // Flush a refresh tap that arrived before the Dart handler was bound.
    unawaited(
      _channel.invokeMethod<void>(_watchRefreshReadyMethod).catchError((_) {}),
    );
  }

  @override
  void unbindWatchRefreshListener() {
    _channel.setMethodCallHandler(null);
  }
}

class WatchDashboardSummaryPayload {
  const WatchDashboardSummaryPayload._(this._value);

  final Map<String, Object?> _value;

  factory WatchDashboardSummaryPayload.fromSnapshot(
    DashboardSnapshot snapshot,
    ConsumptionDisplayPreferences displayPreferences,
    WatchRingPreferences ringPreferences, {
    DateTime? manualRefreshAnchorAt,
    DateTime? clock,
  }) {
    final rings = orderWatchRingsForSurface(
      resolveWatchRings(snapshot, ringPreferences),
      snapshot: snapshot,
    );
    final creditsGlance = resolveWatchCreditsGlance(
      snapshot,
      displayPreferences,
    );
    final window = ManualRefreshWindow.fromLastSync(
      lastSyncAt: manualRefreshAnchorAt ?? snapshot.generatedAt,
      now: clock,
    );
    return WatchDashboardSummaryPayload._({
      'schemaVersion': 7,
      'dataMode':
          snapshot.accounts.isNotEmpty &&
                  snapshot.accounts.every(
                    (account) => account.provider == 'mock',
                  )
              ? 'mock'
              : 'live',
      'generatedAt': snapshot.generatedAt.toUtc().toIso8601String(),
      'overallStatus': snapshot.overallStatus.wireName,
      'manualRefreshAllowed': window.allowed,
      'manualRefreshAvailableAt':
          window.availableAt?.toUtc().toIso8601String(),
      'rings': [
        for (final ring in rings)
          {
            'id': ring.id,
            'label': ring.label,
            // Round for glanceable surfaces — avoid float noise like 24.800000000000004.
            'usedPercent': double.parse(
              (ring.usedPercent ?? 0).toStringAsFixed(1),
            ),
            'status': ring.status.wireName,
          },
      ],
      'creditsGlance': creditsGlance?.toJson(),
      'today': _budgetToJson(snapshot.todayTotal),
      'week': _budgetToJson(snapshot.weekTotal),
      'allowances': [
        for (final account in snapshot.accounts)
          for (final allowance in account.allowances)
            if (displayPreferences.allows(allowance.source))
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
        for (final alert in snapshot.alerts)
          {'severity': alert.severity, 'message': alert.message},
      ],
      'isStale': snapshot.overallStatus == ProviderStatus.stale,
    });
  }

  String encode() => jsonEncode(_value);
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
