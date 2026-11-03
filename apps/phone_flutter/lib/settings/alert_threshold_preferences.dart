import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../providers/provider_connection.dart';

/// Discrete remaining-% stops shown in the UI (null = off).
///
/// Custom input also accepts every whole percentage between the endpoints.
const alertRemainingStops = <int?>[null, 100, 50, 30, 20, 10, 0];

/// UI remaining → stored used percent.
int? alertRemainingToUsed(int? remainingLeft) {
  if (remainingLeft == null) {
    return null;
  }
  return 100 - remainingLeft;
}

/// Stored used percent → UI remaining, including custom values.
int? alertUsedToRemaining(int? used) {
  if (used == null) {
    return null;
  }
  return 100 - used;
}

/// Opt-in used-% threshold for Rust. Null = off.
final class AlertPercentThreshold {
  const AlertPercentThreshold({this.at});

  final int? at;

  bool get isEnabled => at != null;

  Map<String, Object?> toJson() => {if (at != null) 'at': at};

  static AlertPercentThreshold fromJson(Object? json) {
    if (json is! Map) {
      return const AlertPercentThreshold();
    }
    // Prefer `at`; accept legacy warnAt / criticalAt from older installs.
    return AlertPercentThreshold(
      at: _clampPercent(json['at'] ?? json['warnAt'] ?? json['criticalAt']),
    );
  }
}

/// User-entered spend limits in minor units, one per budget period.
///
/// Organization keys report spend but no budget, so a percentage is only
/// computable once the user sets a limit.
final class ConnectionBudget {
  const ConnectionBudget({this.today, this.week, this.month});

  final int? today;
  final int? week;
  final int? month;

  bool get isEmpty => today == null && week == null && month == null;

  Map<String, Object?> toJson() => {
    if (today != null) 'today': today,
    if (week != null) 'week': week,
    if (month != null) 'month': month,
  };

  static ConnectionBudget fromJson(
    Object? json, {
    bool preserveIntegers = false,
  }) {
    if (json is! Map) {
      return const ConnectionBudget();
    }
    int? read(Object? value) =>
        value is int && (preserveIntegers || value > 0) ? value : null;
    return ConnectionBudget(
      today: read(json['today']),
      week: read(json['week']),
      month: read(json['month']),
    );
  }
}

/// Connection-scoped rules: plan windows, purchased meters, spend budgets.
///
/// Budgets are per connection so a threshold on one organization key never
/// fires because a different provider spent money.
final class ConnectionAlertThresholds {
  const ConnectionAlertThresholds({
    this.plan = const AlertPercentThreshold(),
    this.planWindows = const {},
    this.purchased = const AlertPercentThreshold(),
    this.today = const AlertPercentThreshold(),
    this.week = const AlertPercentThreshold(),
    this.month = const AlertPercentThreshold(),
    this.budget = const ConnectionBudget(),
  });

  final AlertPercentThreshold plan;

  /// Absent IDs inherit Plan; a present disabled threshold explicitly means Off.
  final Map<String, AlertPercentThreshold> planWindows;
  final AlertPercentThreshold purchased;
  final AlertPercentThreshold today;
  final AlertPercentThreshold week;
  final AlertPercentThreshold month;
  final ConnectionBudget budget;

  /// True when a percent rule can fire. A budget alone is a ceiling, not a rule.
  bool get hasAlertRules =>
      plan.isEnabled ||
      planWindows.values.any((value) => value.isEnabled) ||
      purchased.isEnabled ||
      today.isEnabled ||
      week.isEnabled ||
      month.isEnabled;

  /// A bare budget also reaches Rust and shapes the dashboard.
  bool get isEnabled => hasAlertRules || !budget.isEmpty;

  /// Explicit Off overrides must survive even when nothing needs evaluation.
  bool get hasStoredSettings => isEnabled || planWindows.isNotEmpty;

  ConnectionAlertThresholds copyWith({
    AlertPercentThreshold? plan,
    Map<String, AlertPercentThreshold>? planWindows,
    AlertPercentThreshold? purchased,
    AlertPercentThreshold? today,
    AlertPercentThreshold? week,
    AlertPercentThreshold? month,
    ConnectionBudget? budget,
  }) {
    return ConnectionAlertThresholds(
      plan: plan ?? this.plan,
      planWindows: planWindows ?? this.planWindows,
      purchased: purchased ?? this.purchased,
      today: today ?? this.today,
      week: week ?? this.week,
      month: month ?? this.month,
      budget: budget ?? this.budget,
    );
  }

  Map<String, Object?> toJson() => {
    'plan': plan.toJson(),
    if (planWindows.isNotEmpty)
      'planWindows': {
        for (final entry in planWindows.entries)
          entry.key: entry.value.toJson(),
      },
    'purchased': purchased.toJson(),
    'today': today.toJson(),
    'week': week.toJson(),
    'month': month.toJson(),
    'budget': budget.toJson(),
  };

  static ConnectionAlertThresholds fromJson(
    Object? json, {
    bool preserveBudgetIntegers = false,
  }) {
    if (json is! Map) {
      return const ConnectionAlertThresholds();
    }
    return ConnectionAlertThresholds(
      plan: AlertPercentThreshold.fromJson(json['plan']),
      planWindows: Map.unmodifiable({
        if (json['planWindows'] case final Map windows)
          for (final entry in windows.entries)
            if (entry.key is String)
              entry.key as String: AlertPercentThreshold.fromJson(entry.value),
      }),
      purchased: AlertPercentThreshold.fromJson(json['purchased']),
      today: AlertPercentThreshold.fromJson(json['today']),
      week: AlertPercentThreshold.fromJson(json['week']),
      month: AlertPercentThreshold.fromJson(json['month']),
      budget: ConnectionBudget.fromJson(
        json['budget'],
        preserveIntegers: preserveBudgetIntegers,
      ),
    );
  }
}

/// Phone-local alert rules, one set per connection.
///
/// Defaults are all off (opt-in). Snapshot evaluation stays in Rust.
final class AlertThresholdPreferences {
  const AlertThresholdPreferences({this.connections = const {}});

  /// Keyed by [ProviderConnectionId.storageKey].
  final Map<String, ConnectionAlertThresholds> connections;

  bool get hasEnabledRules =>
      connections.values.any((value) => value.isEnabled);

  ConnectionAlertThresholds forConnection(ProviderConnectionId id) {
    return connections[id.storageKey] ?? const ConnectionAlertThresholds();
  }

  AlertThresholdPreferences withConnection(
    ProviderConnectionId id,
    ConnectionAlertThresholds value,
  ) {
    final next = Map<String, ConnectionAlertThresholds>.of(connections);
    if (value.hasStoredSettings) {
      next[id.storageKey] = value;
    } else {
      next.remove(id.storageKey);
    }
    return copyWith(connections: next);
  }

  AlertThresholdPreferences copyWith({
    Map<String, ConnectionAlertThresholds>? connections,
  }) {
    return AlertThresholdPreferences(
      connections: connections ?? this.connections,
    );
  }

  Map<String, Object?> toJson() => {
    'connections': {
      for (final entry in connections.entries)
        if (entry.value.hasStoredSettings) entry.key: entry.value.toJson(),
    },
  };

  static AlertThresholdPreferences fromJson(Object? json) {
    if (json is! Map) {
      return const AlertThresholdPreferences();
    }
    final rawConnections = json['connections'];
    final connections = <String, ConnectionAlertThresholds>{};
    if (rawConnections is Map) {
      for (final entry in rawConnections.entries) {
        final key = entry.key;
        if (key is! String) {
          continue;
        }
        final value = ConnectionAlertThresholds.fromJson(
          entry.value,
          preserveBudgetIntegers:
              key == ProviderConnections.cursorPlatform.storageKey,
        );
        if (value.hasStoredSettings) {
          connections[key] = value;
        }
      }
    }
    // Budget rules used to be global (top-level today/week/month). They now
    // belong to a connection, and an all-providers rule has no equivalent, so
    // older installs lose them rather than get them attached to a guess.
    return AlertThresholdPreferences(
      connections: Map.unmodifiable(connections),
    );
  }

  String encode() => jsonEncode(toJson());

  static AlertThresholdPreferences decode(String? raw) {
    if (raw == null || raw.trim().isEmpty) {
      return const AlertThresholdPreferences();
    }
    try {
      return AlertThresholdPreferences.fromJson(jsonDecode(raw));
    } catch (_) {
      return const AlertThresholdPreferences();
    }
  }
}

abstract interface class AlertThresholdPreferenceStore {
  Future<AlertThresholdPreferences> read();

  Future<void> write(AlertThresholdPreferences value);
}

final class SecureAlertThresholdPreferenceStore
    implements AlertThresholdPreferenceStore {
  SecureAlertThresholdPreferenceStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static const _key = 'wardpulse.alerts.thresholds';

  final FlutterSecureStorage _storage;

  @override
  Future<AlertThresholdPreferences> read() async {
    return AlertThresholdPreferences.decode(await _storage.read(key: _key));
  }

  @override
  Future<void> write(AlertThresholdPreferences value) {
    return _storage.write(key: _key, value: value.encode());
  }
}

final class DefaultAlertThresholdPreferenceStore
    implements AlertThresholdPreferenceStore {
  const DefaultAlertThresholdPreferenceStore();

  @override
  Future<AlertThresholdPreferences> read() async =>
      const AlertThresholdPreferences();

  @override
  Future<void> write(AlertThresholdPreferences value) async {}
}

int? _clampPercent(Object? value) {
  final parsed = switch (value) {
    int n => n,
    num n => n.round(),
    String s => int.tryParse(s),
    _ => null,
  };
  if (parsed == null) {
    return null;
  }
  if (parsed < 0 || parsed > 100) {
    return null;
  }
  return parsed;
}
