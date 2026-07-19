import 'dart:convert';

import 'package:flutter/services.dart';

import '../dashboard/dashboard_models.dart';
import '../settings/consumption_display_preferences.dart';

abstract interface class WatchSyncService {
  Future<void> sync(
    DashboardSnapshot snapshot,
    ConsumptionDisplayPreferences displayPreferences,
  );
}

class MethodChannelWatchSyncService implements WatchSyncService {
  const MethodChannelWatchSyncService();

  static const _channel = MethodChannel('app.wardpulse/watch_sync');

  @override
  Future<void> sync(
    DashboardSnapshot snapshot,
    ConsumptionDisplayPreferences displayPreferences,
  ) {
    return _channel.invokeMethod<void>(
      'syncWatchSummary',
      WatchDashboardSummaryPayload.fromSnapshot(
        snapshot,
        displayPreferences,
      ).encode(),
    );
  }
}

class WatchDashboardSummaryPayload {
  const WatchDashboardSummaryPayload._(this._value);

  final Map<String, Object?> _value;

  factory WatchDashboardSummaryPayload.fromSnapshot(
    DashboardSnapshot snapshot,
    ConsumptionDisplayPreferences displayPreferences,
  ) {
    return WatchDashboardSummaryPayload._({
      'schemaVersion': 2,
      'generatedAt': snapshot.generatedAt.toUtc().toIso8601String(),
      'overallStatus': snapshot.overallStatus.wireName,
      'today': _budgetToJson(snapshot.todayTotal),
      'week': _budgetToJson(snapshot.weekTotal),
      'allowances': [
        for (final account in snapshot.accounts)
          for (final allowance in account.allowances)
            if (displayPreferences.allows(allowance.source))
              {
                'source': allowance.source.name,
                'label': allowance.label,
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
