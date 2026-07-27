import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../providers/provider_connection.dart';

/// Discrete opt-in percent stops for alert rules (null = off).
const alertThresholdStops = <int?>[null, 50, 70, 80, 90, 100];

/// Opt-in warn/critical percents. Null fields mean that rule is disabled.
final class AlertPercentThreshold {
  const AlertPercentThreshold({this.warnAt, this.criticalAt});

  final int? warnAt;
  final int? criticalAt;

  bool get isEnabled => warnAt != null || criticalAt != null;

  Map<String, Object?> toJson() => {'warnAt': warnAt, 'criticalAt': criticalAt};

  static AlertPercentThreshold fromJson(Object? json) {
    if (json is! Map) {
      return const AlertPercentThreshold();
    }
    return AlertPercentThreshold(
      warnAt: _clampPercent(json['warnAt']),
      criticalAt: _clampPercent(json['criticalAt']),
    ).normalized;
  }

  /// Ensures critical ≥ warn when both are set.
  AlertPercentThreshold get normalized {
    final warn = warnAt;
    final critical = criticalAt;
    if (warn == null || critical == null || critical >= warn) {
      return this;
    }
    return AlertPercentThreshold(warnAt: warn, criticalAt: warn);
  }
}

/// Connection-scoped rules for plan windows and purchased meters.
final class ConnectionAlertThresholds {
  const ConnectionAlertThresholds({
    this.plan = const AlertPercentThreshold(),
    this.purchased = const AlertPercentThreshold(),
  });

  final AlertPercentThreshold plan;
  final AlertPercentThreshold purchased;

  bool get isEnabled => plan.isEnabled || purchased.isEnabled;

  ConnectionAlertThresholds copyWith({
    AlertPercentThreshold? plan,
    AlertPercentThreshold? purchased,
  }) {
    return ConnectionAlertThresholds(
      plan: plan ?? this.plan,
      purchased: purchased ?? this.purchased,
    );
  }

  Map<String, Object?> toJson() => {
    'plan': plan.toJson(),
    'purchased': purchased.toJson(),
  };

  static ConnectionAlertThresholds fromJson(Object? json) {
    if (json is! Map) {
      return const ConnectionAlertThresholds();
    }
    return ConnectionAlertThresholds(
      plan: AlertPercentThreshold.fromJson(json['plan']),
      purchased: AlertPercentThreshold.fromJson(json['purchased']),
    );
  }
}

/// Phone-local alert rules: connection thresholds + global budget thresholds.
///
/// Defaults are all off (opt-in). Snapshot evaluation stays in Rust.
final class AlertThresholdPreferences {
  const AlertThresholdPreferences({
    this.connections = const {},
    this.today = const AlertPercentThreshold(),
    this.week = const AlertPercentThreshold(),
    this.month = const AlertPercentThreshold(),
  });

  /// Keyed by [ProviderConnectionId.storageKey].
  final Map<String, ConnectionAlertThresholds> connections;
  final AlertPercentThreshold today;
  final AlertPercentThreshold week;
  final AlertPercentThreshold month;

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
    AlertPercentThreshold? today,
    AlertPercentThreshold? week,
    AlertPercentThreshold? month,
  }) {
    return AlertThresholdPreferences(
      connections: connections ?? this.connections,
      today: today ?? this.today,
      week: week ?? this.week,
      month: month ?? this.month,
    );
  }

  Map<String, Object?> toJson() => {
    'connections': {
      for (final entry in connections.entries)
        if (entry.value.isEnabled) entry.key: entry.value.toJson(),
    },
    'today': today.toJson(),
    'week': week.toJson(),
    'month': month.toJson(),
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
    return AlertThresholdPreferences(
      connections: Map.unmodifiable(connections),
      today: AlertPercentThreshold.fromJson(json['today']),
      week: AlertPercentThreshold.fromJson(json['week']),
      month: AlertPercentThreshold.fromJson(json['month']),
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
