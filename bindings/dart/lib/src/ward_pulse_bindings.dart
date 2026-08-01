import 'dart:convert';
import 'dart:ffi';

import 'package:ffi/ffi.dart';

typedef _NativeDashboardSnapshotJson = Pointer<Utf8> Function();
typedef _DartDashboardSnapshotJson = Pointer<Utf8> Function();
typedef _NativeDebugDashboardSnapshotJson = Pointer<Utf8> Function(Uint64);
typedef _DartDebugDashboardSnapshotJson = Pointer<Utf8> Function(int);
typedef _NativeJsonTransform = Pointer<Utf8> Function(Pointer<Utf8>);
typedef _DartJsonTransform = Pointer<Utf8> Function(Pointer<Utf8>);
typedef _NativeStringFree = Void Function(Pointer<Utf8>);
typedef _DartStringFree = void Function(Pointer<Utf8>);

const _libraryName = 'libward_pulse_ffi.so';

final class WardPulseBindingsException implements Exception {
  const WardPulseBindingsException([
    this.message = 'The Rust core did not return a dashboard snapshot.',
  ]);

  final String message;

  @override
  String toString() => message;
}

final class _WardPulseBindings {
  _WardPulseBindings(DynamicLibrary library)
    : _dashboardSnapshotJson = library.lookupFunction<
        _NativeDashboardSnapshotJson,
        _DartDashboardSnapshotJson
      >('ward_pulse_dashboard_snapshot_json'),
      _debugDashboardSnapshotJson = library.lookupFunction<
        _NativeDebugDashboardSnapshotJson,
        _DartDebugDashboardSnapshotJson
      >('ward_pulse_debug_dashboard_snapshot_json'),
      _openAiDashboardSnapshotResultJson = library
          .lookupFunction<_NativeJsonTransform, _DartJsonTransform>(
            'ward_pulse_openai_dashboard_snapshot_result_json',
          ),
      _codexDashboardSnapshotResultJson = library
          .lookupFunction<_NativeJsonTransform, _DartJsonTransform>(
            'ward_pulse_codex_dashboard_snapshot_result_json',
          ),
      _anthropicDashboardSnapshotResultJson = library
          .lookupFunction<_NativeJsonTransform, _DartJsonTransform>(
            'ward_pulse_anthropic_dashboard_snapshot_result_json',
          ),
      _claudeDashboardSnapshotResultJson = library
          .lookupFunction<_NativeJsonTransform, _DartJsonTransform>(
            'ward_pulse_claude_dashboard_snapshot_result_json',
          ),
      _cursorPlanDashboardSnapshotResultJson = library
          .lookupFunction<_NativeJsonTransform, _DartJsonTransform>(
            'ward_pulse_cursor_plan_dashboard_snapshot_result_json',
          ),
      _cursorPlatformDashboardSnapshotResultJson = library
          .lookupFunction<_NativeJsonTransform, _DartJsonTransform>(
            'ward_pulse_cursor_platform_dashboard_snapshot_result_json',
          ),
      _mergeDashboardSnapshotsResultJson = library
          .lookupFunction<_NativeJsonTransform, _DartJsonTransform>(
            'ward_pulse_merge_dashboard_snapshots_result_json',
          ),
      _applyAlertSettingsResultJson = library
          .lookupFunction<_NativeJsonTransform, _DartJsonTransform>(
            'ward_pulse_apply_alert_settings_result_json',
          ),
      _stringFree = library.lookupFunction<_NativeStringFree, _DartStringFree>(
        'ward_pulse_string_free',
      );

  factory _WardPulseBindings.open() {
    return _WardPulseBindings(DynamicLibrary.open(_libraryName));
  }

  final _DartDashboardSnapshotJson _dashboardSnapshotJson;
  final _DartDebugDashboardSnapshotJson _debugDashboardSnapshotJson;
  final _DartJsonTransform _openAiDashboardSnapshotResultJson;
  final _DartJsonTransform _codexDashboardSnapshotResultJson;
  final _DartJsonTransform _anthropicDashboardSnapshotResultJson;
  final _DartJsonTransform _claudeDashboardSnapshotResultJson;
  final _DartJsonTransform _cursorPlanDashboardSnapshotResultJson;
  final _DartJsonTransform _cursorPlatformDashboardSnapshotResultJson;
  final _DartJsonTransform _mergeDashboardSnapshotsResultJson;
  final _DartJsonTransform _applyAlertSettingsResultJson;
  final _DartStringFree _stringFree;

  String loadDashboardSnapshotJson() {
    final value = _dashboardSnapshotJson();
    if (value == nullptr) {
      throw const WardPulseBindingsException();
    }

    try {
      return value.toDartString();
    } finally {
      _stringFree(value);
    }
  }

  String loadDebugDashboardSnapshotJson(int seed) {
    final value = _debugDashboardSnapshotJson(seed);
    if (value == nullptr) {
      throw const WardPulseBindingsException(
        'The Rust core did not return a debug dashboard snapshot.',
      );
    }

    try {
      return value.toDartString();
    } finally {
      _stringFree(value);
    }
  }

  String normalizeOpenAiReportJson(String reportJson) {
    return _normalizeReportJson(reportJson, _openAiDashboardSnapshotResultJson);
  }

  String normalizeCodexReportJson(String reportJson) {
    return _normalizeReportJson(reportJson, _codexDashboardSnapshotResultJson);
  }

  String normalizeAnthropicReportJson(String reportJson) {
    return _normalizeReportJson(
      reportJson,
      _anthropicDashboardSnapshotResultJson,
    );
  }

  String normalizeClaudeReportJson(String reportJson) {
    return _normalizeReportJson(reportJson, _claudeDashboardSnapshotResultJson);
  }

  String normalizeCursorPlanReportJson(String reportJson) {
    return _normalizeReportJson(
      reportJson,
      _cursorPlanDashboardSnapshotResultJson,
    );
  }

  String normalizeCursorPlatformReportJson(String reportJson) {
    return _normalizeReportJson(
      reportJson,
      _cursorPlatformDashboardSnapshotResultJson,
    );
  }

  String mergeDashboardSnapshotsJson(Iterable<String> snapshotsJson) {
    final request = jsonEncode([
      for (final snapshotJson in snapshotsJson) jsonDecode(snapshotJson),
    ]);
    return _normalizeReportJson(request, _mergeDashboardSnapshotsResultJson);
  }

  String applyAlertSettingsJson(String snapshotJson, String settingsJson) {
    final request = jsonEncode({
      'snapshot': jsonDecode(snapshotJson),
      'settings': jsonDecode(settingsJson),
    });
    return _normalizeReportJson(request, _applyAlertSettingsResultJson);
  }

  String _normalizeReportJson(
    String reportJson,
    Pointer<Utf8> Function(Pointer<Utf8>) normalize,
  ) {
    final request = reportJson.toNativeUtf8();
    try {
      final value = normalize(request);
      if (value == nullptr) {
        throw const WardPulseBindingsException();
      }

      try {
        final result = jsonDecode(value.toDartString());
        if (result is! Map<String, dynamic>) {
          throw const WardPulseBindingsException();
        }

        return switch (result['status']) {
          'success' when result['dashboardJson'] is String =>
            result['dashboardJson'] as String,
          'error' when result['message'] is String =>
            throw WardPulseBindingsException(result['message'] as String),
          _ => throw const WardPulseBindingsException(),
        };
      } finally {
        _stringFree(value);
      }
    } finally {
      malloc.free(request);
    }
  }
}

final _bindings = _WardPulseBindings.open();

String loadDashboardSnapshotJson() {
  return _bindings.loadDashboardSnapshotJson();
}

String loadDebugDashboardSnapshotJson(int seed) {
  return _bindings.loadDebugDashboardSnapshotJson(seed);
}

String normalizeOpenAiReportJson(String reportJson) {
  return _bindings.normalizeOpenAiReportJson(reportJson);
}

String normalizeCodexReportJson(String reportJson) {
  return _bindings.normalizeCodexReportJson(reportJson);
}

String normalizeAnthropicReportJson(String reportJson) {
  return _bindings.normalizeAnthropicReportJson(reportJson);
}

String normalizeClaudeReportJson(String reportJson) {
  return _bindings.normalizeClaudeReportJson(reportJson);
}

String normalizeCursorPlanReportJson(String reportJson) {
  return _bindings.normalizeCursorPlanReportJson(reportJson);
}

String normalizeCursorPlatformReportJson(String reportJson) {
  return _bindings.normalizeCursorPlatformReportJson(reportJson);
}

String mergeDashboardSnapshotsJson(Iterable<String> snapshotsJson) {
  return _bindings.mergeDashboardSnapshotsJson(snapshotsJson);
}

String applyAlertSettingsJson(String snapshotJson, String settingsJson) {
  return _bindings.applyAlertSettingsJson(snapshotJson, settingsJson);
}
