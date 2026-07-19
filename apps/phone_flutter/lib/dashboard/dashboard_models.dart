import 'dart:convert';

enum ProviderStatus {
  ok,
  warning,
  error,
  rateLimited,
  authRequired,
  stale,
  unknown,
}

extension ProviderStatusLabel on ProviderStatus {
  String get label {
    return switch (this) {
      ProviderStatus.ok => 'OK',
      ProviderStatus.warning => 'Warning',
      ProviderStatus.error => 'Error',
      ProviderStatus.rateLimited => 'Rate limited',
      ProviderStatus.authRequired => 'Auth required',
      ProviderStatus.stale => 'Stale',
      ProviderStatus.unknown => 'Unknown',
    };
  }
}

class DashboardSnapshot {
  const DashboardSnapshot({
    required this.generatedAt,
    required this.overallStatus,
    required this.accounts,
    required this.todayTotal,
    required this.weekTotal,
    required this.monthTotal,
    required this.alerts,
    required this.watchSummary,
  });

  final DateTime generatedAt;
  final ProviderStatus overallStatus;
  final List<ProviderSnapshot> accounts;
  final BudgetState todayTotal;
  final BudgetState weekTotal;
  final BudgetState monthTotal;
  final List<AlertSummary> alerts;
  final WatchSummary watchSummary;

  factory DashboardSnapshot.fromJsonString(String source) {
    return DashboardSnapshot.fromJson(_jsonMap(jsonDecode(source)));
  }

  factory DashboardSnapshot.fromJson(Map<String, dynamic> json) {
    return DashboardSnapshot(
      generatedAt: DateTime.parse(json['generatedAt'] as String),
      overallStatus: _statusFromJson(json['overallStatus']),
      accounts: _jsonList(json['accounts'], ProviderSnapshot.fromJson),
      todayTotal: BudgetState.fromJson(_jsonMap(json['todayTotal'])),
      weekTotal: BudgetState.fromJson(_jsonMap(json['weekTotal'])),
      monthTotal: BudgetState.fromJson(_jsonMap(json['monthTotal'])),
      alerts: _jsonList(json['alerts'], AlertSummary.fromJson),
      watchSummary: WatchSummary.fromJson(_jsonMap(json['watchSummary'])),
    );
  }

  ProviderSnapshot? get primaryAccount {
    return accounts.isEmpty ? null : accounts.first;
  }

  String get accountCountLabel {
    return accounts.length == 1 ? '1 account' : '${accounts.length} accounts';
  }
}

class ProviderSnapshot {
  const ProviderSnapshot({
    required this.accountId,
    required this.provider,
    required this.status,
    required this.today,
    required this.week,
    required this.month,
    required this.credits,
    required this.buckets,
    required this.modelBreakdown,
    required this.lastSuccessfulSyncAt,
  });

  final String accountId;
  final String provider;
  final ProviderStatus status;
  final BudgetState today;
  final BudgetState week;
  final BudgetState month;
  final List<CreditState> credits;
  final List<UsageBucket> buckets;
  final List<ModelUsage> modelBreakdown;
  final DateTime? lastSuccessfulSyncAt;

  factory ProviderSnapshot.fromJson(Map<String, dynamic> json) {
    return ProviderSnapshot(
      accountId: json['accountId'] as String,
      provider: json['provider'] as String,
      status: _statusFromJson(json['status']),
      today: BudgetState.fromJson(_jsonMap(json['today'])),
      week: BudgetState.fromJson(_jsonMap(json['week'])),
      month: BudgetState.fromJson(_jsonMap(json['month'])),
      credits: _jsonList(json['credits'], CreditState.fromJson),
      buckets: _jsonList(json['buckets'], UsageBucket.fromJson),
      modelBreakdown: _jsonList(json['modelBreakdown'], ModelUsage.fromJson),
      lastSuccessfulSyncAt: _optionalDateTime(json['lastSuccessfulSyncAt']),
    );
  }

  String get providerLabel {
    return switch (provider) {
      'openai' => 'OpenAI',
      'claude' => 'Claude',
      'cursor' => 'Cursor',
      'mock' => 'Mock',
      _ => provider,
    };
  }
}

class UsageBucket {
  const UsageBucket({
    required this.startAt,
    required this.endAt,
    required this.cost,
    required this.inputTokens,
    required this.outputTokens,
    required this.cachedTokens,
    required this.requests,
    required this.model,
  });

  final DateTime startAt;
  final DateTime endAt;
  final Money? cost;
  final int? inputTokens;
  final int? outputTokens;
  final int? cachedTokens;
  final int? requests;
  final String? model;

  factory UsageBucket.fromJson(Map<String, dynamic> json) {
    return UsageBucket(
      startAt: DateTime.parse(json['startAt'] as String),
      endAt: DateTime.parse(json['endAt'] as String),
      cost: Money.maybeFromJson(json['cost']),
      inputTokens: (json['inputTokens'] as num?)?.toInt(),
      outputTokens: (json['outputTokens'] as num?)?.toInt(),
      cachedTokens: (json['cachedTokens'] as num?)?.toInt(),
      requests: (json['requests'] as num?)?.toInt(),
      model: json['model'] as String?,
    );
  }

  int? get totalTokens {
    if (inputTokens == null && outputTokens == null) {
      return null;
    }

    return (inputTokens ?? 0) + (outputTokens ?? 0);
  }
}

class BudgetState {
  const BudgetState({
    required this.period,
    required this.spent,
    required this.limit,
    required this.remaining,
    required this.usedPercent,
    required this.projectedTotal,
    required this.status,
  });

  final String period;
  final Money? spent;
  final Money? limit;
  final Money? remaining;
  final double? usedPercent;
  final Money? projectedTotal;
  final ProviderStatus status;

  factory BudgetState.fromJson(Map<String, dynamic> json) {
    return BudgetState(
      period: json['period'] as String,
      spent: Money.maybeFromJson(json['spent']),
      limit: Money.maybeFromJson(json['limit']),
      remaining: Money.maybeFromJson(json['remaining']),
      usedPercent: (json['usedPercent'] as num?)?.toDouble(),
      projectedTotal: Money.maybeFromJson(json['projectedTotal']),
      status: _statusFromJson(json['status']),
    );
  }

  double? get usedFraction {
    final value = usedPercent;
    if (value == null) {
      return null;
    }

    return (value / 100).clamp(0.0, 1.0).toDouble();
  }

  String get periodLabel {
    return switch (period) {
      'today' => 'Today',
      'week' => 'Week',
      'month' => 'Month',
      _ => period,
    };
  }

  String get usedPercentLabel {
    final value = usedPercent;
    if (value == null) {
      return 'Unknown';
    }

    final places = value.truncateToDouble() == value ? 0 : 1;
    return '${value.toStringAsFixed(places)}%';
  }
}

class Money {
  const Money({required this.minorUnits, required this.currency});

  final int minorUnits;
  final String currency;

  factory Money.fromJson(Map<String, dynamic> json) {
    return Money(
      minorUnits: (json['minorUnits'] as num).toInt(),
      currency: json['currency'] as String,
    );
  }

  static Money? maybeFromJson(Object? value) {
    if (value == null) {
      return null;
    }

    return Money.fromJson(_jsonMap(value));
  }

  String get label {
    final sign = minorUnits < 0 ? '-' : '';
    final absolute = minorUnits.abs();
    final major = absolute ~/ 100;
    final minor = (absolute % 100).toString().padLeft(2, '0');

    return '$sign$currency $major.$minor';
  }
}

class CreditState {
  const CreditState({
    required this.remaining,
    required this.granted,
    required this.expiresAt,
    required this.source,
  });

  final Money? remaining;
  final Money? granted;
  final DateTime? expiresAt;
  final String source;

  factory CreditState.fromJson(Map<String, dynamic> json) {
    return CreditState(
      remaining: Money.maybeFromJson(json['remaining']),
      granted: Money.maybeFromJson(json['granted']),
      expiresAt: _optionalDateTime(json['expiresAt']),
      source: json['source'] as String,
    );
  }
}

class ModelUsage {
  const ModelUsage({
    required this.model,
    required this.cost,
    required this.inputTokens,
    required this.outputTokens,
    required this.requests,
  });

  final String model;
  final Money? cost;
  final int? inputTokens;
  final int? outputTokens;
  final int? requests;

  factory ModelUsage.fromJson(Map<String, dynamic> json) {
    return ModelUsage(
      model: json['model'] as String,
      cost: Money.maybeFromJson(json['cost']),
      inputTokens: (json['inputTokens'] as num?)?.toInt(),
      outputTokens: (json['outputTokens'] as num?)?.toInt(),
      requests: (json['requests'] as num?)?.toInt(),
    );
  }

  int? get totalTokens {
    if (inputTokens == null && outputTokens == null) {
      return null;
    }

    return (inputTokens ?? 0) + (outputTokens ?? 0);
  }
}

class AlertSummary {
  const AlertSummary({required this.severity, required this.message});

  final String severity;
  final String message;

  factory AlertSummary.fromJson(Map<String, dynamic> json) {
    return AlertSummary(
      severity: json['severity'] as String,
      message: json['message'] as String,
    );
  }
}

class WatchSummary {
  const WatchSummary({
    required this.todayUsedPercent,
    required this.weekUsedPercent,
    required this.status,
  });

  final double? todayUsedPercent;
  final double? weekUsedPercent;
  final ProviderStatus status;

  factory WatchSummary.fromJson(Map<String, dynamic> json) {
    return WatchSummary(
      todayUsedPercent: (json['todayUsedPercent'] as num?)?.toDouble(),
      weekUsedPercent: (json['weekUsedPercent'] as num?)?.toDouble(),
      status: _statusFromJson(json['status']),
    );
  }
}

String formatUtc(DateTime value) {
  final utc = value.toUtc();
  final date = utc.toIso8601String().split('.').first.replaceFirst('T', ' ');
  return '$date UTC';
}

String formatCount(int? value) {
  if (value == null) {
    return 'Unknown';
  }

  final digits = value.toString();
  final buffer = StringBuffer();

  for (var index = 0; index < digits.length; index += 1) {
    final remaining = digits.length - index;
    buffer.write(digits[index]);

    if (remaining > 1 && remaining % 3 == 1) {
      buffer.write(',');
    }
  }

  return buffer.toString();
}

ProviderStatus _statusFromJson(Object? value) {
  return switch (value as String) {
    'ok' => ProviderStatus.ok,
    'warning' => ProviderStatus.warning,
    'error' => ProviderStatus.error,
    'rateLimited' => ProviderStatus.rateLimited,
    'authRequired' => ProviderStatus.authRequired,
    'stale' => ProviderStatus.stale,
    _ => ProviderStatus.unknown,
  };
}

DateTime? _optionalDateTime(Object? value) {
  if (value == null) {
    return null;
  }

  return DateTime.parse(value as String);
}

Map<String, dynamic> _jsonMap(Object? value) {
  return Map<String, dynamic>.from(value as Map);
}

List<T> _jsonList<T>(
  Object? value,
  T Function(Map<String, dynamic> json) decode,
) {
  return (value as List)
      .map((item) => decode(_jsonMap(item)))
      .toList(growable: false);
}
