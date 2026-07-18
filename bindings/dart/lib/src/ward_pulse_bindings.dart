import 'dart:ffi';

import 'package:ffi/ffi.dart';

typedef _NativeDashboardSnapshotJson = Pointer<Utf8> Function();
typedef _DartDashboardSnapshotJson = Pointer<Utf8> Function();
typedef _NativeStringFree = Void Function(Pointer<Utf8>);
typedef _DartStringFree = void Function(Pointer<Utf8>);

const _libraryName = 'libward_pulse_ffi.so';

final class WardPulseBindingsException implements Exception {
  const WardPulseBindingsException();

  @override
  String toString() => 'The Rust core did not return a dashboard snapshot.';
}

final class _WardPulseBindings {
  _WardPulseBindings(DynamicLibrary library)
    : _dashboardSnapshotJson = library
          .lookupFunction<
            _NativeDashboardSnapshotJson,
            _DartDashboardSnapshotJson
          >('ward_pulse_dashboard_snapshot_json'),
      _stringFree = library.lookupFunction<_NativeStringFree, _DartStringFree>(
        'ward_pulse_string_free',
      );

  factory _WardPulseBindings.open() {
    return _WardPulseBindings(DynamicLibrary.open(_libraryName));
  }

  final _DartDashboardSnapshotJson _dashboardSnapshotJson;
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
}

final _bindings = _WardPulseBindings.open();

String loadDashboardSnapshotJson() {
  return _bindings.loadDashboardSnapshotJson();
}
