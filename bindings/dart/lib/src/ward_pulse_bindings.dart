import 'dart:convert';
import 'dart:ffi';

import 'package:ffi/ffi.dart';

typedef _NativeDashboardSnapshotJson = Pointer<Utf8> Function();
typedef _DartDashboardSnapshotJson = Pointer<Utf8> Function();
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
    : _dashboardSnapshotJson = library
          .lookupFunction<
            _NativeDashboardSnapshotJson,
            _DartDashboardSnapshotJson
          >('ward_pulse_dashboard_snapshot_json'),
      _openAiDashboardSnapshotResultJson = library
          .lookupFunction<_NativeJsonTransform, _DartJsonTransform>(
            'ward_pulse_openai_dashboard_snapshot_result_json',
          ),
      _codexDashboardSnapshotResultJson = library
          .lookupFunction<_NativeJsonTransform, _DartJsonTransform>(
            'ward_pulse_codex_dashboard_snapshot_result_json',
          ),
      _mergeDashboardSnapshotsResultJson = library
          .lookupFunction<_NativeJsonTransform, _DartJsonTransform>(
            'ward_pulse_merge_dashboard_snapshots_result_json',
          ),
      _stringFree = library.lookupFunction<_NativeStringFree, _DartStringFree>(
        'ward_pulse_string_free',
      );

  factory _WardPulseBindings.open() {
    return _WardPulseBindings(DynamicLibrary.open(_libraryName));
  }

  final _DartDashboardSnapshotJson _dashboardSnapshotJson;
  final _DartJsonTransform _openAiDashboardSnapshotResultJson;
  final _DartJsonTransform _codexDashboardSnapshotResultJson;
  final _DartJsonTransform _mergeDashboardSnapshotsResultJson;
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

  String normalizeOpenAiReportJson(String reportJson) {
    return _normalizeReportJson(reportJson, _openAiDashboardSnapshotResultJson);
  }

  String normalizeCodexReportJson(String reportJson) {
    return _normalizeReportJson(reportJson, _codexDashboardSnapshotResultJson);
  }

  String mergeDashboardSnapshotsJson(Iterable<String> snapshotsJson) {
    final request = jsonEncode([
      for (final snapshotJson in snapshotsJson) jsonDecode(snapshotJson),
    ]);
    return _normalizeReportJson(request, _mergeDashboardSnapshotsResultJson);
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

String normalizeOpenAiReportJson(String reportJson) {
  return _bindings.normalizeOpenAiReportJson(reportJson);
}

String normalizeCodexReportJson(String reportJson) {
  return _bindings.normalizeCodexReportJson(reportJson);
}

String mergeDashboardSnapshotsJson(Iterable<String> snapshotsJson) {
  return _bindings.mergeDashboardSnapshotsJson(snapshotsJson);
}
