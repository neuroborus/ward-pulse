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

  String get description {
    return switch (this) {
      ProviderStatus.ok => 'Provider data is current.',
      ProviderStatus.warning => 'Usage is approaching a configured limit.',
      ProviderStatus.error => 'Provider sync failed.',
      ProviderStatus.rateLimited => 'Provider rate limit reached.',
      ProviderStatus.authRequired => 'Provider authentication is required.',
      ProviderStatus.stale => 'Showing data from the last successful sync.',
      ProviderStatus.unknown => 'Provider status is unavailable.',
    };
  }
}

enum DashboardSyncIssue {
  credentialUnavailable,
  authentication,
  permissionDenied,
  rateLimited,
  providerUnavailable,
  invalidResponse,
  codexAuthentication,
  codexPermissionDenied,
  codexUnavailable,
  codexInvalidResponse,
  dashboardUnavailable,
}

extension DashboardSyncIssueMessage on DashboardSyncIssue {
  String get message {
    return switch (this) {
      DashboardSyncIssue.credentialUnavailable =>
        'The saved key could not be read. Re-enter it in Settings.',
      DashboardSyncIssue.authentication =>
        'OpenAI rejected the key. Check that you pasted the full Admin API key.',
      DashboardSyncIssue.permissionDenied =>
        'This key cannot read organization usage. Use an organization Admin API key.',
      DashboardSyncIssue.rateLimited =>
        'OpenAI rate limit reached. Try again shortly.',
      DashboardSyncIssue.providerUnavailable =>
        'OpenAI reporting is unavailable. Check your connection and try again.',
      DashboardSyncIssue.invalidResponse =>
        'OpenAI returned an unsupported reporting response.',
      DashboardSyncIssue.codexAuthentication =>
        'Codex sign-in expired. Reconnect your ChatGPT account in Settings.',
      DashboardSyncIssue.codexPermissionDenied =>
        'This Codex account cannot access usage reporting.',
      DashboardSyncIssue.codexUnavailable =>
        'Codex usage is unavailable. Check your connection and try again.',
      DashboardSyncIssue.codexInvalidResponse =>
        'Codex returned an unsupported usage response.',
      DashboardSyncIssue.dashboardUnavailable =>
        'Dashboard data could not be loaded.',
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
    this.syncIssue,
    this.syncDetails,
  });

  final DateTime generatedAt;
  final ProviderStatus overallStatus;
  final List<ProviderSnapshot> accounts;
  final BudgetState todayTotal;
  final BudgetState weekTotal;
  final BudgetState monthTotal;
  final List<AlertSummary> alerts;
  final WatchSummary watchSummary;
  final DashboardSyncIssue? syncIssue;
  final String? syncDetails;

  String? get syncTooltip {
    final issue = syncIssue;
    if (issue == null) {
      return null;
    }

    final details = syncDetails;
    return details == null ? issue.message : '${issue.message}\n$details';
  }

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

  String toJsonString() => jsonEncode(toJson());

  Map<String, dynamic> toJson() => {
    'generatedAt': generatedAt.toUtc().toIso8601String(),
    'overallStatus': overallStatus.name,
    'accounts': accounts.map((account) => account.toJson()).toList(),
    'todayTotal': todayTotal.toJson(),
    'weekTotal': weekTotal.toJson(),
    'monthTotal': monthTotal.toJson(),
    'alerts': alerts.map((alert) => alert.toJson()).toList(),
    'watchSummary': watchSummary.toJson(),
  };

  ProviderSnapshot? get primaryAccount {
    return accounts.isEmpty ? null : accounts.first;
  }

  String get accountCountLabel {
    return accounts.length == 1 ? '1 account' : '${accounts.length} accounts';
  }

  DashboardSnapshot withStaleStatus({
    DashboardSyncIssue? syncIssue,
    String? syncDetails,
  }) {
    return DashboardSnapshot(
      generatedAt: generatedAt,
      overallStatus: ProviderStatus.stale,
      accounts: accounts
          .map((account) => account._withStatus(ProviderStatus.stale))
          .toList(growable: false),
      todayTotal: todayTotal,
      weekTotal: weekTotal,
      monthTotal: monthTotal,
      alerts: alerts,
      watchSummary: watchSummary._withStatus(ProviderStatus.stale),
      syncIssue: syncIssue,
      syncDetails: syncDetails,
    );
  }

  DashboardSnapshot withSyncIssue(DashboardSyncIssue issue, {String? details}) {
    return DashboardSnapshot(
      generatedAt: generatedAt,
      overallStatus: overallStatus,
      accounts: accounts,
      todayTotal: todayTotal,
      weekTotal: weekTotal,
      monthTotal: monthTotal,
      alerts: alerts,
      watchSummary: watchSummary,
      syncIssue: issue,
      syncDetails: details,
    );
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
    required this.allowances,
    required this.buckets,
    required this.modelBreakdown,
    required this.lastSuccessfulSyncAt,
    this.lastError,
  });

  final String accountId;
  final String provider;
  final ProviderStatus status;
  final BudgetState today;
  final BudgetState week;
  final BudgetState month;
  final List<CreditState> credits;
  final List<AllowanceState> allowances;
  final List<UsageBucket> buckets;
  final List<ModelUsage> modelBreakdown;
  final DateTime? lastSuccessfulSyncAt;
  final ProviderErrorSummary? lastError;

  factory ProviderSnapshot.fromJson(Map<String, dynamic> json) {
    return ProviderSnapshot(
      accountId: json['accountId'] as String,
      provider: json['provider'] as String,
      status: _statusFromJson(json['status']),
      today: BudgetState.fromJson(_jsonMap(json['today'])),
      week: BudgetState.fromJson(_jsonMap(json['week'])),
      month: BudgetState.fromJson(_jsonMap(json['month'])),
      credits: _jsonList(json['credits'], CreditState.fromJson),
      allowances:
          json['allowances'] == null
              ? const <AllowanceState>[]
              : _jsonList(json['allowances'], AllowanceState.fromJson),
      buckets: _jsonList(json['buckets'], UsageBucket.fromJson),
      modelBreakdown: _jsonList(json['modelBreakdown'], ModelUsage.fromJson),
      lastSuccessfulSyncAt: _optionalDateTime(json['lastSuccessfulSyncAt']),
      lastError:
          json['lastError'] == null
              ? null
              : ProviderErrorSummary.fromJson(_jsonMap(json['lastError'])),
    );
  }

  Map<String, dynamic> toJson() => {
    'accountId': accountId,
    'provider': provider,
    'status': status.name,
    'today': today.toJson(),
    'week': week.toJson(),
    'month': month.toJson(),
    'credits': credits.map((credit) => credit.toJson()).toList(),
    'allowances': allowances.map((allowance) => allowance.toJson()).toList(),
    'buckets': buckets.map((bucket) => bucket.toJson()).toList(),
    'modelBreakdown': modelBreakdown.map((model) => model.toJson()).toList(),
    'lastSuccessfulSyncAt': lastSuccessfulSyncAt?.toUtc().toIso8601String(),
    'lastError': lastError?.toJson(),
  };

  String get providerLabel {
    return switch (provider) {
      'openai' => 'OpenAI',
      'codex' => 'Codex',
      'claude' => 'Claude',
      'cursor' => 'Cursor',
      'mock' => 'Mock',
      _ => provider,
    };
  }

  ProviderSnapshot _withStatus(ProviderStatus value) {
    return ProviderSnapshot(
      accountId: accountId,
      provider: provider,
      status: value,
      today: today,
      week: week,
      month: month,
      credits: credits,
      allowances: allowances,
      buckets: buckets,
      modelBreakdown: modelBreakdown,
      lastSuccessfulSyncAt: lastSuccessfulSyncAt,
      lastError: lastError,
    );
  }
}

class ProviderErrorSummary {
  const ProviderErrorSummary({required this.code, required this.message});

  final String code;
  final String message;

  factory ProviderErrorSummary.fromJson(Map<String, dynamic> json) {
    return ProviderErrorSummary(
      code: json['code'] as String,
      message: json['message'] as String,
    );
  }

  Map<String, dynamic> toJson() => {'code': code, 'message': message};
}

class UsageBucket {
  const UsageBucket({
    required this.startAt,
    required this.endAt,
    required this.cost,
    required this.inputTokens,
    required this.outputTokens,
    required this.cachedTokens,
    this.reportedTotalTokens,
    required this.requests,
    required this.model,
    this.project,
    this.user,
  });

  final DateTime startAt;
  final DateTime endAt;
  final Money? cost;
  final int? inputTokens;
  final int? outputTokens;
  final int? cachedTokens;
  final int? reportedTotalTokens;
  final int? requests;
  final String? model;
  final String? project;
  final String? user;

  factory UsageBucket.fromJson(Map<String, dynamic> json) {
    return UsageBucket(
      startAt: DateTime.parse(json['startAt'] as String),
      endAt: DateTime.parse(json['endAt'] as String),
      cost: Money.maybeFromJson(json['cost']),
      inputTokens: (json['inputTokens'] as num?)?.toInt(),
      outputTokens: (json['outputTokens'] as num?)?.toInt(),
      cachedTokens: (json['cachedTokens'] as num?)?.toInt(),
      reportedTotalTokens: (json['totalTokens'] as num?)?.toInt(),
      requests: (json['requests'] as num?)?.toInt(),
      model: json['model'] as String?,
      project: json['project'] as String?,
      user: json['user'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'startAt': startAt.toUtc().toIso8601String(),
    'endAt': endAt.toUtc().toIso8601String(),
    'cost': cost?.toJson(),
    'inputTokens': inputTokens,
    'outputTokens': outputTokens,
    'cachedTokens': cachedTokens,
    'totalTokens': reportedTotalTokens,
    'requests': requests,
    'model': model,
    'project': project,
    'user': user,
  };

  int? get totalTokens {
    if (reportedTotalTokens != null) {
      return reportedTotalTokens;
    }

    if (inputTokens == null && outputTokens == null) {
      return null;
    }

    return (inputTokens ?? 0) + (outputTokens ?? 0);
  }
}

enum AllowanceSource { plan, purchased }

class AllowanceState {
  const AllowanceState({
    required this.id,
    required this.source,
    required this.label,
    required this.usedPercent,
    required this.used,
    required this.limit,
    required this.remaining,
    this.unlimited = false,
    required this.windowMinutes,
    required this.resetsAt,
    required this.status,
  });

  final String id;
  final AllowanceSource source;
  final String label;
  final double? usedPercent;
  final Quantity? used;
  final Quantity? limit;
  final Quantity? remaining;
  final bool unlimited;
  final int? windowMinutes;
  final DateTime? resetsAt;
  final ProviderStatus status;

  factory AllowanceState.fromJson(Map<String, dynamic> json) {
    return AllowanceState(
      id: json['id'] as String,
      source: switch (json['source']) {
        'purchased' => AllowanceSource.purchased,
        _ => AllowanceSource.plan,
      },
      label: json['label'] as String,
      usedPercent: (json['usedPercent'] as num?)?.toDouble(),
      used: Quantity.maybeFromJson(json['used']),
      limit: Quantity.maybeFromJson(json['limit']),
      remaining: Quantity.maybeFromJson(json['remaining']),
      unlimited: json['unlimited'] == true,
      windowMinutes: (json['windowMinutes'] as num?)?.toInt(),
      resetsAt: _optionalDateTime(json['resetsAt']),
      status: _statusFromJson(json['status']),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'source': source.name,
    'label': label,
    'usedPercent': usedPercent,
    'used': used?.toJson(),
    'limit': limit?.toJson(),
    'remaining': remaining?.toJson(),
    'unlimited': unlimited,
    'windowMinutes': windowMinutes,
    'resetsAt': resetsAt?.toUtc().toIso8601String(),
    'status': status.name,
  };

  double? get usedFraction {
    final value = usedPercent;
    return value == null ? null : (value / 100).clamp(0.0, 1.0).toDouble();
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

class Quantity {
  const Quantity({required this.value, required this.unit});

  final String value;
  final String unit;

  factory Quantity.fromJson(Map<String, dynamic> json) {
    return Quantity(
      value: json['value'] as String,
      unit: json['unit'] as String,
    );
  }

  static Quantity? maybeFromJson(Object? value) {
    return value == null ? null : Quantity.fromJson(_jsonMap(value));
  }

  Map<String, dynamic> toJson() => {'value': value, 'unit': unit};

  String get label => '$value $unit';
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

  Map<String, dynamic> toJson() => {
    'period': period,
    'spent': spent?.toJson(),
    'limit': limit?.toJson(),
    'remaining': remaining?.toJson(),
    'usedPercent': usedPercent,
    'projectedTotal': projectedTotal?.toJson(),
    'status': status.name,
  };

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

  Map<String, dynamic> toJson() => {
    'minorUnits': minorUnits,
    'currency': currency,
  };

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

  Map<String, dynamic> toJson() => {
    'remaining': remaining?.toJson(),
    'granted': granted?.toJson(),
    'expiresAt': expiresAt?.toUtc().toIso8601String(),
    'source': source,
  };
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

  Map<String, dynamic> toJson() => {
    'model': model,
    'cost': cost?.toJson(),
    'inputTokens': inputTokens,
    'outputTokens': outputTokens,
    'requests': requests,
  };

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

  Map<String, dynamic> toJson() => {'severity': severity, 'message': message};
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

  Map<String, dynamic> toJson() => {
    'todayUsedPercent': todayUsedPercent,
    'weekUsedPercent': weekUsedPercent,
    'status': status.name,
  };

  WatchSummary _withStatus(ProviderStatus value) {
    return WatchSummary(
      todayUsedPercent: todayUsedPercent,
      weekUsedPercent: weekUsedPercent,
      status: value,
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
