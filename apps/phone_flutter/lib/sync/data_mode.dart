import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../providers/connection_lifecycle.dart';
import '../settings/debug_data_preferences.dart';

/// Where dashboard data comes from. Only [live] may reach provider networks.
enum DataMode {
  live,
  demo,
  mock;

  bool get synthetic => this != live;

  static DataMode parse(Object? value) => switch (value) {
    'live' => live,
    'demo' => demo,
    'mock' => mock,
    _ => throw StateError('Data mode unavailable.'),
  };
}

/// Mock is available only in Debug builds.
final class DataModePolicy {
  const DataModePolicy({this.debugBuild = kDebugMode});

  final bool debugBuild;

  bool allows(DataMode mode) => mode != DataMode.mock || debugBuild;
}

/// The durable record shared by every isolate in the Android process.
final class DataModeState {
  const DataModeState({
    required this.installId,
    required this.mode,
    required this.generation,
  });

  factory DataModeState.fromMap(Map<Object?, Object?> map) => DataModeState(
    installId: map['installId']! as String,
    mode: DataMode.parse(map['mode']),
    generation: (map['generation']! as num).toInt(),
  );

  final String installId;
  final DataMode mode;

  /// Advances on every committed mode change; retires older operations.
  final int generation;
}

/// A committed switch, and whether a drained effect could not persist.
typedef DataModeSwitch = ({DataModeState state, bool unresolvedStorageFailure});

/// Work that belongs to an earlier data mode, or one whose switch is draining.
final class DataModeRetired extends StateError {
  DataModeRetired() : super('Data mode changed.');
}

/// The old mode remains authoritative. A drained account write may also have failed.
final class DataModeWriteFailure extends StateError {
  DataModeWriteFailure({required this.unresolvedStorageFailure})
    : super('Could not save data mode.');

  final bool unresolvedStorageFailure;
}

/// One operation's view of the mode authority.
abstract interface class DataModeAuthority {
  Future<DataModeState> read();

  /// Captures the current mode, optionally waiting for a draining switch.
  Future<DataModeOperation> begin({
    bool cacheOnly = false,
    bool waitForSwitch = false,
  });

  Future<bool> isCurrent(int generation);

  /// Returns a lease a switch waits for, or `null` once [generation] retired.
  ///
  /// A [settlement] lease covers a sent OAuth refresh; if its engine detaches
  /// first, the switch reports the rotation as unresolved.
  Future<String?> enter(int generation, {bool settlement = false});
  Future<void> exit(String lease, {bool unresolved = false});

  /// Closes admission, drains admitted effects, then commits [mode].
  Future<DataModeSwitch> switchTo(DataMode mode);
}

/// One foreground load, headless invocation or other unit of provider work.
///
/// Network sends and report-derived effects run only while this operation's
/// generation is current; a switch retires every older operation.
final class DataModeOperation {
  DataModeOperation({
    required this.authority,
    required this.state,
    required this.requestId,
    this.cacheOnly = false,
  });

  final DataModeAuthority authority;
  final DataModeState state;
  final String requestId;

  /// Cache-only work reads caches and samples and never opens a transport.
  final bool cacheOnly;

  DataMode get mode => state.mode;
  int get generation => state.generation;

  /// Keeps the captured Wear request and generation for a cache-only read.
  DataModeOperation asCacheOnly() => DataModeOperation(
    authority: authority,
    state: state,
    requestId: requestId,
    cacheOnly: true,
  );

  static final _zoneKey = Object();
  static final _leaseKey = Object();
  static final _settlementKey = Object();

  static DataModeOperation? get current =>
      Zone.current[_zoneKey] as DataModeOperation?;

  /// Proof that a sent OAuth rotation may finish storing while a switch drains.
  static String? get credentialSettlementLease {
    final settlement = Zone.current[_settlementKey] as _Settlement?;
    return settlement != null &&
            !settlement.closed &&
            settlement.operation == current
        ? settlement.lease
        : null;
  }

  Future<T> run<T>(Future<T> Function() body) =>
      runZoned(body, zoneValues: {_zoneKey: this});

  Future<bool> isCurrent() => authority.isCurrent(generation);

  /// Runs an effect in the current operation, or directly for unscoped calls.
  /// An optional ownership check runs after lease admission.
  static Future<bool> guardCurrent(
    Future<void> Function() effect, {
    Future<bool> Function()? isCurrent,
  }) async {
    var ran = false;
    Future<void> guarded() async {
      if (isCurrent != null && !await isCurrent()) return;
      ran = true;
      await effect();
    }

    final operation = current;
    if (operation == null) {
      await guarded();
    } else {
      await operation.guard(guarded);
    }
    return ran;
  }

  /// Native fetch admission binds its lease to this generation.
  Map<String, Object?> get fetchArguments => {'generation': generation};

  /// Runs a report-derived effect under a lease, or skips it once retired.
  ///
  /// Returns `false` when the effect did not run.
  Future<bool> guard(Future<void> Function() effect) async {
    final inherited = Zone.current[_leaseKey] as _GuardLease?;
    if (inherited != null && inherited.operation == this && inherited.open) {
      await inherited.runNested(effect);
      return true;
    }
    final lease = await authority.enter(generation);
    if (lease == null) return false;
    final guard = _GuardLease(this);
    try {
      await runZoned(effect, zoneValues: {_leaseKey: guard});
      return true;
    } finally {
      final drained = guard.close();
      if (drained != null) await drained;
      await authority.exit(lease);
    }
  }

  /// Whether this operation can poll providers and handle real alerts.
  bool get allowsLiveWork => !cacheOnly && mode == DataMode.live;

  /// Denies synthetic and cache-only work before any transport setup.
  ///
  /// Outside an operation (explicit account actions) nothing is checked.
  static void admitTransport() {
    if (current case final operation? when !operation.allowsLiveWork) {
      throw DataModeRetired();
    }
  }

  /// Holds a dispatch lease until [send] has initiated its request.
  ///
  /// Inside [settle] the lease is held until the rotation is stored. Outside
  /// an operation (explicit account actions) the send is unchanged.
  static Future<T> dispatch<T>(
    Future<T> Function() send, {
    void Function()? abort,
  }) async {
    final operation = current;
    if (operation == null) return send();
    final inherited = Zone.current[_settlementKey] as _Settlement?;
    final settlement = inherited?.operation == operation ? inherited : null;
    final held = settlement?.lease;
    String? acquired;
    final String lease;
    try {
      if (!operation.allowsLiveWork || settlement?.closed == true) {
        throw DataModeRetired();
      }
      if (held == null) {
        acquired = await operation.authority.enter(
          operation.generation,
          settlement: settlement != null,
        );
      }
      final admitted =
          held == null ? acquired : (await operation.isCurrent() ? held : null);
      if (admitted == null || settlement?.closed == true) {
        throw DataModeRetired();
      }
      lease = admitted;
    } catch (_) {
      try {
        abort?.call();
      } catch (_) {
        // Preserve the admission error if request cleanup also fails.
      }
      if (acquired != null) {
        // Settlement ended while this grant was pending.
        try {
          await operation.authority.exit(acquired);
        } catch (_) {
          // Preserve the admission error if lease cleanup also fails.
        }
      }
      rethrow;
    }
    if (settlement != null) {
      settlement.lease = lease;
      return send();
    }
    final Future<T> sent;
    try {
      sent = send();
    } catch (_) {
      await operation.authority.exit(lease);
      rethrow;
    }
    // Observe the send at once; releasing the lease cannot hide its error.
    final results = await Future.wait<Object?>([
      sent,
      operation.authority.exit(lease),
    ]);
    return results.first as T;
  }

  /// Writes and sends [request] under a dispatch lease.
  ///
  /// [write] adds the body inside the lease. [timeout] bounds the send, not
  /// admission: an expired send is aborted, so it ends while still owned.
  ///
  /// A redirect would open a new connection outside the lease, so inside an
  /// operation it is rejected; explicit account actions keep following them.
  static Future<HttpClientResponse> sendRequest(
    HttpClientRequest request, {
    void Function()? write,
    Duration? timeout,
  }) async {
    final reject = current != null && request.followRedirects;
    if (reject) request.followRedirects = false;
    final response = await dispatch(() {
      write?.call();
      final sent = request.close();
      if (timeout == null) return sent;
      // close() may return a future with a narrower runtime response type.
      Never abortTimedOutRequest() {
        final error = TimeoutException('Request timed out.', timeout);
        request.abort(error);
        throw error;
      }

      return sent.timeout(timeout, onTimeout: abortTimedOutRequest);
    }, abort: request.abort);
    if (reject && response.isRedirect) {
      // Discard the body unread; a stalled body cannot hold a lease.
      response.listen(null).cancel().ignore();
      throw RedirectException('Redirect not followed.', response.redirects);
    }
    return response;
  }

  /// Lets an already-sent OAuth refresh settle and persist before a switch.
  ///
  /// The lease is taken where [send] dispatches its request, after transport
  /// setup, and held while [persist] stores the rotated session. A failed
  /// store is reported to the switch unless [superseded] recognizes an
  /// explicit account action that replaced the session.
  static Future<T> settle<T>(
    Future<T> Function() send,
    Future<void> Function(T value) persist, {
    bool Function(Object error)? superseded,
  }) async {
    final operation = current;
    if (operation == null) {
      final value = await send();
      await persist(value);
      return value;
    }
    final settlement = _Settlement(operation);
    var unresolved = false;
    try {
      final value = await runZoned(
        send,
        zoneValues: {_settlementKey: settlement},
      );
      try {
        await runZoned(
          () => persist(value),
          zoneValues: {_settlementKey: settlement},
        );
      } catch (error) {
        unresolved = !(superseded?.call(error) ?? false);
        rethrow;
      }
      return value;
    } finally {
      settlement.closed = true;
      if (settlement.lease case final lease?) {
        await operation.authority.exit(lease, unresolved: unresolved);
      }
    }
  }
}

/// Tracks guarded effects that reuse an outer lease before it closes.
final class _GuardLease {
  _GuardLease(this.operation);

  final DataModeOperation operation;
  bool open = true;
  int _nested = 0;
  Completer<void>? _drained;

  Future<void> runNested(Future<void> Function() effect) async {
    _nested++;
    try {
      await effect();
    } finally {
      if (--_nested == 0) _drained?.complete();
    }
  }

  Future<void>? close() {
    open = false;
    return _nested == 0 ? null : (_drained = Completer<void>()).future;
  }
}

/// The lease one OAuth refresh holds from its send until its session is stored.
final class _Settlement {
  _Settlement(this.operation);

  final DataModeOperation operation;
  String? lease;

  /// Set once [DataModeOperation.settle] unwinds; a later grant is released.
  var closed = false;
}

/// Android authority: one record and admission monitor for every engine.
///
/// Its first use creates the record, importing the legacy Debug Mock choice.
final class MethodChannelDataModeAuthority implements DataModeAuthority {
  MethodChannelDataModeAuthority({
    ConnectionCachePlatform? platform,
    this.policy = const DataModePolicy(),
    DebugDataPreferenceStore? legacy,
  }) : _platform = platform ?? const MethodChannelConnectionCachePlatform(),
       _legacy = legacy ?? SecureDebugDataPreferenceStore();

  final ConnectionCachePlatform _platform;
  final DataModePolicy policy;

  /// Imported once in Debug when the record is absent; production ignores it.
  final DebugDataPreferenceStore _legacy;
  Future<void>? _initialized;

  Future<void> _ensureInitialized() =>
      _initialized ??= _initialize().catchError((Object error) {
        _initialized = null;
        throw error;
      });

  Future<void> _initialize() async {
    final token = await _platform.invoke('beginModeImport', {}) as String?;
    if (token == null) return;
    bool? legacyMock;
    try {
      // An unreadable choice leaves the record absent for the next claimant.
      legacyMock = policy.debugBuild && await _legacy.readMockDataEnabled();
    } finally {
      await _platform.invoke('finishModeImport', {
        'token': token,
        if (legacyMock != null) 'legacyMock': legacyMock,
      });
    }
  }

  Future<Map<Object?, Object?>> _invoke(
    String method, [
    Map<String, Object?> arguments = const {},
  ]) async => (await _platform.invoke(method, arguments))! as Map;

  DataModeState _state(Map<Object?, Object?> view) {
    final state = DataModeState.fromMap(view);
    if (!policy.allows(state.mode)) throw StateError('Data mode unavailable.');
    return state;
  }

  @override
  Future<DataModeState> read() async {
    await _ensureInitialized();
    return _state(await _invoke('readMode'));
  }

  @override
  Future<DataModeOperation> begin({
    bool cacheOnly = false,
    bool waitForSwitch = false,
  }) async {
    await _ensureInitialized();
    final Map<Object?, Object?> view;
    try {
      view = await _invoke('beginOperation', {
        if (waitForSwitch) 'waitForSwitch': true,
      });
    } catch (_, stackTrace) {
      if (waitForSwitch) rethrow;
      // Admission is closed while a switch drains or the record is unreadable.
      Error.throwWithStackTrace(DataModeRetired(), stackTrace);
    }
    return DataModeOperation(
      authority: this,
      state: _state(view),
      requestId: view['requestId']! as String,
      cacheOnly: cacheOnly,
    );
  }

  @override
  Future<bool> isCurrent(int generation) async =>
      await _platform.invoke('operationCurrent', {'generation': generation}) ==
      true;

  @override
  Future<String?> enter(int generation, {bool settlement = false}) async =>
      await _platform.invoke('enterEffect', {
            'generation': generation,
            'settlement': settlement,
          })
          as String?;

  @override
  Future<void> exit(String lease, {bool unresolved = false}) async {
    await _platform.invoke('exitEffect', {
      'lease': lease,
      'unresolved': unresolved,
    });
  }

  @override
  Future<DataModeSwitch> switchTo(DataMode mode) async {
    if (!policy.allows(mode)) throw ArgumentError.value(mode, 'mode');
    await _ensureInitialized();
    final Map<Object?, Object?> view;
    try {
      view = await _invoke('switchMode', {'mode': mode.name});
    } on PlatformException catch (error) {
      if (error.code != 'data_mode_write_failed') rethrow;
      throw DataModeWriteFailure(
        unresolvedStorageFailure: error.details == true,
      );
    }
    return (
      state: _state(view),
      unresolvedStorageFailure: view['unresolved'] == true,
    );
  }
}

/// In-process authority for hosts without the Android plugin, and for tests.
final class MemoryDataModeAuthority implements DataModeAuthority {
  MemoryDataModeAuthority({
    DataMode mode = DataMode.live,
    this.policy = const DataModePolicy(),
    this.installId = 'memory-install',
  }) : _mode = policy.allows(mode) ? mode : DataMode.live;

  final DataModePolicy policy;
  final String installId;
  DataMode _mode;
  var _generation = 0;
  var _requests = 0;
  final _leases = <String>{};
  var _nextLease = 0;
  var _unresolved = false;
  Completer<void>? _drained;
  Future<void> _switches = Future.value();
  var _switching = 0;

  /// Fails the next committed mode write, keeping the old record.
  bool failWrite = false;

  /// Holds the next mode write after admission closes and effects drain.
  Completer<void>? pendingWrite;

  /// Every committed mode, in order.
  final writes = <DataMode>[];

  int get generation => _generation;
  int get openLeases => _leases.length;
  bool get switching => _switching > 0;

  DataModeState get state =>
      DataModeState(installId: installId, mode: _mode, generation: _generation);

  @override
  Future<DataModeState> read() async => state;

  @override
  Future<DataModeOperation> begin({
    bool cacheOnly = false,
    bool waitForSwitch = false,
  }) async {
    while (waitForSwitch && switching) {
      await _switches;
    }
    if (switching) throw DataModeRetired();
    return DataModeOperation(
      authority: this,
      state: state,
      requestId: 'request-${++_requests}',
      cacheOnly: cacheOnly,
    );
  }

  @override
  Future<bool> isCurrent(int generation) async =>
      !switching && generation == _generation;

  @override
  Future<String?> enter(int generation, {bool settlement = false}) async {
    // Checked and inserted in one step, like the native monitor.
    if (switching || generation != _generation) return null;
    final lease = 'lease-${++_nextLease}';
    _leases.add(lease);
    return lease;
  }

  @override
  Future<void> exit(String lease, {bool unresolved = false}) async {
    if (!_leases.remove(lease)) return;
    if (unresolved) _unresolved = true;
    if (_leases.isEmpty) _drained?.complete();
  }

  @override
  Future<DataModeSwitch> switchTo(DataMode mode) {
    if (!policy.allows(mode)) throw ArgumentError.value(mode, 'mode');
    _switching++;
    final result = _switches.then((_) => _commit(mode));
    final settled = result.whenComplete(() => _switching--);
    _switches = settled.then<void>((_) {}, onError: (_) {});
    return settled;
  }

  Future<DataModeSwitch> _commit(DataMode mode) async {
    while (_leases.isNotEmpty) {
      await (_drained = Completer<void>()).future;
    }
    _drained = null;
    final unresolved = _unresolved;
    _unresolved = false;
    if (mode != _mode) {
      final pending = pendingWrite;
      pendingWrite = null;
      if (pending != null) await pending.future;
      if (failWrite) {
        failWrite = false;
        _unresolved = _unresolved || unresolved;
        throw DataModeWriteFailure(unresolvedStorageFailure: unresolved);
      }
      _mode = mode;
      _generation++;
      writes.add(mode);
    }
    return (state: state, unresolvedStorageFailure: unresolved);
  }
}
