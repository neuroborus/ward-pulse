import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:ward_pulse_phone/providers/connection_lifecycle.dart';

/// Ordinary map storage and the real Java engine: no test-only stronger CAS.
final class NativeCacheTestBridge {
  NativeCacheTestBridge._(this._process, this._directory) {
    _process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
          final fields = line.split('\t');
          final completion = _pending.remove(int.parse(fields[0]))!;
          if (fields[1] == 'error') {
            completion.completeError(
              StateError('Test connection storage unavailable.'),
            );
          } else {
            completion.complete(
              jsonDecode(utf8.decode(base64Decode(fields[2]))),
            );
          }
        });
    _process.stderr.transform(utf8.decoder).listen(_stderr.write);
  }
  final Process _process;
  final Directory _directory;
  final _pending = <int, Completer<Object?>>{};
  final _stderr = StringBuffer();
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
  bool failRead = false;
  bool failWrite = false;
  Future<void> Function(String)? beforeWrite;
  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (failRead) throw StateError('Sanitized storage read failure.');
    return values[key];
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
    deleted.add(key);
    if (key == failDeleteKey)
      throw StateError('Sanitized storage delete failure.');
    values.remove(key);
  }
}
