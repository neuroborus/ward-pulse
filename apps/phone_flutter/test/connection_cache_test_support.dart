import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ward_pulse_phone/providers/connection_lifecycle.dart';
import 'package:ward_pulse_phone/sync/data_mode.dart';

/// Answers the default Wear service's startup claim as Android does when no
/// launch tap is pending. The app awaits this reply before its first load, and
/// an unmocked platform reply cannot arrive while a widget test runs in fake
/// time.
void answerNoPendingWatchRefresh() {
  const channel = MethodChannel('app.wardpulse/watch_refresh');
  final messenger =
      TestWidgetsFlutterBinding.ensureInitialized().defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(channel, (call) async {
    expect(call.method, 'watchRefreshChannelReady');
    return null;
  });
  addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
}

/// Ordinary map storage and the real Java engine: no test-only stronger CAS.
final class NativeCacheTestBridge {
  NativeCacheTestBridge._(this._process, this._directory) {
    _process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
          final fields = line.split('\t');
          final completion = _pending.remove(int.parse(fields[0]))!;
          final value = jsonDecode(utf8.decode(base64Decode(fields[2])));
          if (fields[1] == 'error') {
            if (value case {
              'code': final String code,
              'details': final details,
            }) {
              completion.completeError(
                PlatformException(code: code, details: details),
              );
            } else {
              completion.completeError(
                StateError('Test connection storage unavailable.'),
              );
            }
          } else {
            completion.complete(value);
          }
        });
    _process.stderr.transform(utf8.decoder).listen(_stderr.write);
  }
  final Process _process;
  final Directory _directory;
  final _pending = <int, Completer<Object?>>{};
  final _stderr = StringBuffer();
  void Function(Future<Object?>)? onInvoke;
  var _next = 0;
  static Future<NativeCacheTestBridge> start() async {
    final root = Directory('../..').absolute.path;
    final directory = await Directory.systemTemp.createTemp(
      'wardpulse-cache-test-',
    );
    final result = await Process.run('javac', [
      '-d',
      directory.path,
      '$root/apps/phone_flutter/plugins/ward_pulse_watch_sync/android/src/main/java/app/wardpulse/watchsync/ConnectionCacheEngine.java',
      '$root/tools/test-phone-cache/ConnectionCacheEngineBridge.java',
    ]);
    if (result.exitCode != 0)
      throw StateError('Native test compile failed: ${result.stderr}');
    return NativeCacheTestBridge._(
      await Process.start('java', [
        '-cp',
        directory.path,
        'app.wardpulse.watchsync.ConnectionCacheEngineBridge',
      ]),
      directory,
    );
  }

  ConnectionCachePlatform platform(String owner) =>
      _NativePlatform(this, owner);
  Future<Object?> invoke(
    String owner,
    String method,
    Map<String, Object?> arguments,
  ) {
    final id = ++_next;
    final result = Completer<Object?>();
    _pending[id] = result;
    final fields = <String>[id.toString(), method, owner];
    void flatten(String prefix, Object? value) {
      if (value is Map) {
        value.forEach(
          (key, item) =>
              flatten(prefix.isEmpty ? '$key' : '$prefix.$key', item),
        );
      } else if (value != null) {
        fields.add(prefix);
        fields.add(
          base64Encode(
            utf8.encode(value is List ? value.join('\n') : '$value'),
          ),
        );
      }
    }

    arguments.forEach(flatten);
    _process.stdin.writeln(fields.join('\t'));
    onInvoke?.call(result.future);
    return result.future;
  }

  Future<void> reset() async {
    await invoke('test', 'reset', {});
  }

  Future<void> close() async {
    await _process.stdin.close();
    final exit = await _process.exitCode;
    await _directory.delete(recursive: true);
    if (exit != 0) throw StateError('Native test process failed: $_stderr');
  }
}

final class _NativePlatform implements ConnectionCachePlatform {
  const _NativePlatform(this.bridge, this.owner);
  final NativeCacheTestBridge bridge;
  final String owner;
  @override
  Future<Object?> invoke(String method, Map<String, Object?> arguments) =>
      bridge.invoke(owner, method, arguments);
}

final class FakeSecureStorage extends FlutterSecureStorage {
  final values = <String, String>{};
  final deleted = <String>[];
  String? failDeleteKey;
  String? failReadKey;
  bool failRead = false;
  bool failWrite = false;
  Future<void> Function(String)? beforeWrite;
  Future<void> Function(String)? beforeRead;
  Future<void> Function(String)? beforeDelete;
  void Function(String, Future<String?>)? onRead;
  @override
  Future<Map<String, String>> readAll({
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (failRead) throw StateError('Sanitized storage read failure.');
    return Map.of(values);
  }

  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) {
    String? stored() {
      if (failRead || key == failReadKey)
        throw StateError('Sanitized storage read failure.');
      return values[key];
    }

    // A held read returns what was stored when it started.
    final hold = beforeRead;
    final read = Future<String?>.sync(stored);
    final result =
        hold == null
            ? read
            : read.then((value) async {
              await hold(key);
              return value;
            });
    onRead?.call(key, result);
    return result;
  }

  @override
  Future<void> write({
    required String key,
    required String? value,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (beforeWrite != null) await beforeWrite!(key);
    if (failWrite) throw StateError('Sanitized storage write failure.');
    if (value == null) {
      values.remove(key);
    } else {
      values[key] = value;
    }
  }

  @override
  Future<void> delete({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    await beforeDelete?.call(key);
    deleted.add(key);
    if (key == failDeleteKey)
      throw StateError('Sanitized storage delete failure.');
    values.remove(key);
  }
}

/// Delegates every operation, observing replies only after native completion.
final class ObservingCachePlatform implements ConnectionCachePlatform {
  ObservingCachePlatform(this.delegate);
  final ConnectionCachePlatform delegate;
  FutureOr<void> Function(String, Map<String, Object?>)? beforeInvoke;
  FutureOr<void> Function(String, Map<String, Object?>, Object?)? onComplete;

  @override
  Future<Object?> invoke(String method, Map<String, Object?> arguments) async {
    await beforeInvoke?.call(method, arguments);
    final result = await delegate.invoke(method, arguments);
    await onComplete?.call(method, arguments, result);
    return result;
  }
}

/// Holds one effect request before its same-generation lease is granted.
final class HeldModeAdmission implements ConnectionCachePlatform {
  HeldModeAdmission({this.skip = 0});

  final int skip;
  final entered = Completer<void>();
  final release = Completer<void>();
  var _admissions = 0;

  DataModeOperation operation() => DataModeOperation(
    authority: MethodChannelDataModeAuthority(platform: this),
    state: const DataModeState(
      installId: 'install',
      mode: DataMode.live,
      generation: 0,
    ),
    requestId: 'live-operation',
  );

  @override
  Future<Object?> invoke(String method, Map<String, Object?> arguments) async {
    switch (method) {
      case 'enterEffect':
        if (_admissions++ == skip) {
          entered.complete();
          await release.future;
        }
        return 'effect-lease';
      case 'exitEffect':
        return null;
      default:
        throw StateError('Unexpected mode request.');
    }
  }
}
