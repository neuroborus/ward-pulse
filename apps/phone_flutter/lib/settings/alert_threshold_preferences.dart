import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../providers/provider_connection.dart';

/// Discrete remaining-% stops shown in the UI (null = off).
///
/// Maps to used% for storage/Rust: `100 - remaining` → 50/70/80/90/100.
const alertRemainingStops = <int?>[null, 50, 30, 20, 10, 0];

/// UI remaining → stored used percent.
int? alertRemainingToUsed(int? remainingLeft) {
  if (remainingLeft == null) {
    return null;
  }
  return 100 - remainingLeft;
}

/// Stored used percent → UI remaining (null if not a known stop).
int? alertUsedToRemaining(int? used) {
  if (used == null) {
    return null;
  }
  final remaining = 100 - used;
  return alertRemainingStops.contains(remaining) ? remaining : null;
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

  static ConnectionBudget fromJson(Object? json) {
    if (json is! Map) {
      return const ConnectionBudget();
    }
    int? read(Object? value) => value is int && value > 0 ? value : null;
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
    this.purchased = const AlertPercentThreshold(),
    this.today = const AlertPercentThreshold(),
    this.week = const AlertPercentThreshold(),
    this.month = const AlertPercentThreshold(),
    this.budget = const ConnectionBudget(),
  });

  final AlertPercentThreshold plan;
  final AlertPercentThreshold purchased;
  final AlertPercentThreshold today;
  final AlertPercentThreshold week;
  final AlertPercentThreshold month;
  final ConnectionBudget budget;

  /// True when a percent rule can fire. A budget alone is a ceiling, not a rule.
  bool get hasAlertRules =>
      plan.isEnabled ||
      purchased.isEnabled ||
      today.isEnabled ||
      week.isEnabled ||
      month.isEnabled;

  /// Worth storing: a bare budget still reaches Rust and shapes the dashboard.
  bool get isEnabled => hasAlertRules || !budget.isEmpty;

  ConnectionAlertThresholds copyWith({
    AlertPercentThreshold? plan,
    AlertPercentThreshold? purchased,
    AlertPercentThreshold? today,
    AlertPercentThreshold? week,
    AlertPercentThreshold? month,
    ConnectionBudget? budget,
  }) {
    return ConnectionAlertThresholds(
      plan: plan ?? this.plan,
      purchased: purchased ?? this.purchased,
      today: today ?? this.today,
      week: week ?? this.week,
      month: month ?? this.month,
      budget: budget ?? this.budget,
    );
  }

  Map<String, Object?> toJson() => {
    'plan': plan.toJson(),
    'purchased': purchased.toJson(),
    'today': today.toJson(),
    'week': week.toJson(),
    'month': month.toJson(),
    'budget': budget.toJson(),
  };

  static ConnectionAlertThresholds fromJson(Object? json) {
    if (json is! Map) {
      return const ConnectionAlertThresholds();
    }
    return ConnectionAlertThresholds(
      plan: AlertPercentThreshold.fromJson(json['plan']),
      purchased: AlertPercentThreshold.fromJson(json['purchased']),
      today: AlertPercentThreshold.fromJson(json['today']),
      week: AlertPercentThreshold.fromJson(json['week']),
      month: AlertPercentThreshold.fromJson(json['month']),
      budget: ConnectionBudget.fromJson(json['budget']),
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
    if (value.isEnabled) {
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
        if (entry.value.isEnabled) entry.key: entry.value.toJson(),
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
        final value = ConnectionAlertThresholds.fromJson(entry.value);
        if (value.isEnabled) {
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
  if (parsed < 1 || parsed > 100) {
    return null;
  }
  return parsed;
}
