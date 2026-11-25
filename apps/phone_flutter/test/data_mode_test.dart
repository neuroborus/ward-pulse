import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ward_pulse_phone/dashboard/connection_snapshot_cache.dart';
import 'package:ward_pulse_phone/dashboard/dashboard_models.dart';
import 'package:ward_pulse_phone/providers/claude_account_service.dart';
import 'package:ward_pulse_phone/providers/claude_account_store.dart';
import 'package:ward_pulse_phone/providers/codex_account_store.dart';
import 'package:ward_pulse_phone/providers/connection_lifecycle.dart';
import 'package:ward_pulse_phone/settings/debug_data_preferences.dart';
import 'package:ward_pulse_phone/sync/automatic_poll.dart';
import 'package:ward_pulse_phone/sync/claude_account_client.dart';
import 'package:ward_pulse_phone/sync/codex_account_client.dart';
import 'package:ward_pulse_phone/sync/data_mode.dart';
import 'package:ward_pulse_phone/sync/provider_reporting.dart';

import 'connection_cache_test_support.dart';

const _debug = DataModePolicy(debugBuild: true);
const _production = DataModePolicy(debugBuild: false);

final _now = DateTime.utc(2026, 7, 26, 12);
final _token = Uri.parse('https://example.test/v1/oauth/token');
final _expired = ClaudeAccountSession(
  accessToken: 'synthetic-access',
  refreshToken: 'synthetic-refresh',
  expiresAt: _now,
  accountId: 'synthetic-account',
);
_Response _rotated() => _Response(
  HttpStatus.ok,
  body: jsonEncode({
    'access_token': 'rotated-access',
    'refresh_token': 'rotated-refresh',
    'expires_in': 3600,
  }),
);
bool _isToken(_Request request) => request.url.path.endsWith('/token');
ClaudeAccountClient _claude(_Client client) => ClaudeAccountClient(
  transport: IoClaudeHttpTransport(client: client),
  clock: () => _now,
);

void main() {
  group('operation fencing', () {
    test('a dispatch lease lasts only until the send is initiated', () async {
      final authority = MemoryDataModeAuthority();
      final operation = await authority.begin();
      final response = Completer<String>();
      final initiated = Completer<void>();
      var leasesDuringSend = -1;
      final sent = operation.run(
        () => DataModeOperation.dispatch(() {
          leasesDuringSend = authority.openLeases;
          initiated.complete();
          return response.future;
        }),
      );
      await initiated.future;
      expect(leasesDuringSend, 1);
      expect(authority.openLeases, 0);
      // The in-flight response does not hold a switch open.
      final switched = await authority.switchTo(DataMode.demo);
      expect(switched.state.generation, 1);
      response.complete('late');
      expect(await sent, 'late');
    });

    for (final cacheOnly in [false, true]) {
      final why = cacheOnly ? 'a cache-only' : 'a retired';
      test('$why operation aborts before any send', () async {
        final authority = MemoryDataModeAuthority();
        final operation = await authority.begin(cacheOnly: cacheOnly);
        if (!cacheOnly) await authority.switchTo(DataMode.mock);
        var sends = 0;
        var aborts = 0;
        await expectLater(
          operation.run(
            () => DataModeOperation.dispatch(
              () async => sends++,
              abort: () => aborts++,
            ),
          ),
          throwsA(isA<DataModeRetired>()),
        );
        expect(sends, 0);
        expect(aborts, 1);
        expect(authority.openLeases, 0);
      });
    }

    test('account actions outside an operation send unchanged', () async {
      expect(await DataModeOperation.dispatch(() async => 'sent'), 'sent');
    });

    test('a failed send is observed while its lease is released', () async {
      final memory = MemoryDataModeAuthority();
      final authority = _Held(memory, release: Completer<void>());
      final operation = await authority.begin();
      final initiated = Completer<void>();
      final sent = expectLater(
        operation.run(
          () => DataModeOperation.dispatch<void>(() {
            initiated.complete();
            return Future.error(
              const SocketException('Sanitized connection failure.'),
            );
          }),
        ),
        throwsA(isA<SocketException>()),
      );
      await initiated.future;
      // Microtasks run first: the send fails before its lease is released.
      await Future<void>.delayed(Duration.zero);
      expect(memory.openLeases, 1);
      authority.release!.complete();
      await sent;
      expect(memory.openLeases, 0);
    });

    test('a retired guard skips its effect', () async {
      final authority = MemoryDataModeAuthority();
      final operation = await authority.begin();
      await authority.switchTo(DataMode.demo);
      var ran = false;
      expect(await operation.guard(() async => ran = true), isFalse);
      expect(ran, isFalse);
    });

    test('a delayed guard cannot reuse a released lease', () async {
      final authority = MemoryDataModeAuthority();
      final operation = await authority.begin();
      final resume = Completer<void>();
      late Future<bool> publication;
      var published = false;
      await operation.guard(() async {
        publication = resume.future.then(
          (_) => operation.guard(() async => published = true),
        );
      });
      expect(authority.openLeases, 0);
      await authority.switchTo(DataMode.demo);
      resume.complete();
      expect(await publication, isFalse);
      expect(published, isFalse);
    });

    test('admission closes while a switch drains', () async {
      final authority = MemoryDataModeAuthority();
      final operation = await authority.begin();
      final held = Completer<void>();
      final entered = Completer<void>();
      final effect = operation.guard(() async {
        entered.complete();
        await held.future;
        expect(await operation.guard(() async {}), isTrue);
      });
      await entered.future;
      final switched = authority.switchTo(DataMode.demo);
      expect(await operation.isCurrent(), isFalse);
      await expectLater(authority.begin(), throwsA(isA<DataModeRetired>()));
      held.complete();
      expect(await effect, isTrue);
      expect((await switched).state.mode, DataMode.demo);
      expect((await authority.begin()).generation, 1);
    });

    test('a held rotation persists and later Live reuses it', () async {
      final authority = MemoryDataModeAuthority();
      var stored = 'session-0';
      final operation = await authority.begin();
      final response = Completer<String>();
      final initiated = Completer<void>();
      final rotation = operation.run(
        () => DataModeOperation.settle(
          () => DataModeOperation.dispatch(() {
            initiated.complete();
            return response.future;
          }),
          (rotated) async => stored = rotated,
        ),
      );
      await initiated.future;
      expect(authority.openLeases, 1);
      final toDemo = authority.switchTo(DataMode.demo);
      // The sent refresh holds its lease, so the switch cannot commit.
      expect(authority.writes, isEmpty);
      response.complete('session-1');
      expect(await rotation, 'session-1');
      final switched = await toDemo;
      expect(switched.unresolvedStorageFailure, isFalse);
      expect(stored, 'session-1');

      // Live -> synthetic -> Live: the new Live operation uses the rotation.
      await authority.switchTo(DataMode.live);
      final later = await authority.begin();
      expect(later.mode, DataMode.live);
      expect(later.generation, 2);
      expect(
        await later.run(
          () => DataModeOperation.dispatch(() async => 'used $stored'),
        ),
        'used session-1',
      );
    });

    test('a held settlement is confined to its operation', () async {
      final authority = MemoryDataModeAuthority();
      final live = await authority.begin();
      final cacheOnly = await authority.begin(cacheOnly: true);
      final otherLive = await authority.begin();
      var cacheSends = 0;
      await live.run(
        () => DataModeOperation.settle(() async {
          await DataModeOperation.dispatch(() async {});
          expect(authority.openLeases, 1);
          await expectLater(
            cacheOnly.run(
              () => DataModeOperation.dispatch(() async => cacheSends++),
            ),
            throwsA(isA<DataModeRetired>()),
          );
          final leasesDuringSend = await otherLive.run(
            () => DataModeOperation.dispatch(() async => authority.openLeases),
          );
          expect(leasesDuringSend, 2);
          expect(authority.openLeases, 1);
        }, (_) async {}),
      );
      expect(cacheSends, 0);
      expect(authority.openLeases, 0);
    });

    test('an unstored rotation is reported by the switch it held', () async {
      final authority = MemoryDataModeAuthority();
      final operation = await authority.begin();
      final response = Completer<String>();
      final initiated = Completer<void>();
      final rotation = operation.run(
        () => DataModeOperation.settle(
          () => DataModeOperation.dispatch(() {
            initiated.complete();
            return response.future;
          }),
          (_) async => throw StateError('Sanitized account storage failure.'),
        ),
      );
      await initiated.future;
      final switched = authority.switchTo(DataMode.demo);
      response.complete('session-1');
      await expectLater(rotation, throwsStateError);
      final result = await switched;
      expect(result.unresolvedStorageFailure, isTrue);
      expect(result.state.mode, DataMode.demo);
      // Reported once: the next switch starts clean.
      final next = await authority.switchTo(DataMode.live);
      expect(next.unresolvedStorageFailure, isFalse);
    });

    test('a retired rotation is never sent', () async {
      final authority = MemoryDataModeAuthority();
      final operation = await authority.begin();
      await authority.switchTo(DataMode.mock);
      var sends = 0;
      await expectLater(
        operation.run(
          () => DataModeOperation.settle(
            () => DataModeOperation.dispatch(() async => sends++),
            (_) async {},
          ),
        ),
        throwsA(isA<DataModeRetired>()),
      );
      expect(sends, 0);
    });

    test('a failed mode write keeps the record and admission', () async {
      final authority = MemoryDataModeAuthority()..failWrite = true;
      final before = await authority.begin();
      await expectLater(authority.switchTo(DataMode.mock), throwsStateError);
      expect(authority.state.mode, DataMode.live);
      expect(authority.generation, 0);
      expect(await before.isCurrent(), isTrue);
      expect((await authority.begin()).generation, 0);
    });

    test('a superseded rotation is not reported unresolved', () async {
      final authority = MemoryDataModeAuthority();
      final operation = await authority.begin();
      final response = Completer<String>();
      final initiated = Completer<void>();
      final rotation = expectLater(
        operation.run(
          () => DataModeOperation.settle(
            () => DataModeOperation.dispatch(() {
              initiated.complete();
              return response.future;
            }),
            (_) async => throw StateError('Sanitized replaced session.'),
            superseded: (error) => error is StateError,
          ),
        ),
        throwsStateError,
      );
      await initiated.future;
      final switched = authority.switchTo(DataMode.demo);
      response.complete('session-1');
      await rotation;
      expect((await switched).unresolvedStorageFailure, isFalse);
    });

    test('production policy never holds Mock', () {
      final authority = MemoryDataModeAuthority(
        mode: DataMode.mock,
        policy: _production,
      );
      expect(authority.state.mode, DataMode.live);
      expect(() => authority.switchTo(DataMode.mock), throwsArgumentError);
    });
  });

  group('transport fencing', () {
    final report = Uri.parse('https://example.test/report');
    final usage = Uri.parse('https://example.test/api/oauth/usage');
    Never unsent(_Request _) => throw StateError('Nothing is sent.');

    for (final (mode, cacheOnly) in [
      (DataMode.demo, false),
      (DataMode.mock, false),
      (DataMode.live, true),
    ]) {
      final what = cacheOnly ? 'cache-only work' : '${mode.name} work';
      test('$what never opens a transport', () async {
        final authority = MemoryDataModeAuthority(mode: mode, policy: _debug);
        final operation = await authority.begin(cacheOnly: cacheOnly);
        final client = _Client(unsent);
        await expectLater(
          operation.run(
            () => IoProviderHttpTransport(
              client: client,
            ).get(report, headers: const {}),
          ),
          throwsA(isA<DataModeRetired>()),
        );
        expect(client.requests, isEmpty);
      });
    }

    test('a switch during transport setup sends nothing', () async {
      final authority = MemoryDataModeAuthority();
      final opened = Completer<void>();
      final held = Completer<void>();
      final client = _Client(
        unsent,
        beforeOpen: () {
          opened.complete();
          return held.future;
        },
      );
      final operation = await authority.begin();
      final sent = expectLater(
        operation.run(
          () => IoProviderHttpTransport(
            client: client,
          ).post(report, headers: const {}, body: '{}'),
        ),
        throwsA(isA<DataModeRetired>()),
      );
      await opened.future;
      // Nothing was initiated, so the switch commits at once.
      expect((await authority.switchTo(DataMode.demo)).state.generation, 1);
      held.complete();
      await sent;
      expect(client.requests.single.events, ['abort']);
    });

    for (final reuse in [false, true]) {
      final admission = reuse ? 'settlement recheck' : 'lease admission';
      test('a failed $admission aborts the opened request', () async {
        final memory = MemoryDataModeAuthority();
        final authority = _Held(memory);
        final operation = await authority.begin();
        final client = _Client(unsent);
        final error = StateError('Sanitized admission failure.');
        Future<ProviderHttpResponse> post() => IoProviderHttpTransport(
          client: client,
        ).post(report, headers: const {}, body: '{}');

        final sent = operation.run(() {
          if (!reuse) {
            authority.enterError = error;
            return post();
          }
          return DataModeOperation.settle(() async {
            await DataModeOperation.dispatch(() async {});
            authority.currentError = error;
            return post();
          }, (_) async {});
        });

        await expectLater(sent, throwsA(same(error)));
        expect(client.requests.single.events, ['abort']);
        expect(memory.openLeases, 0);
      });
    }

    test('a request body is written under the dispatch lease', () async {
      final authority = MemoryDataModeAuthority();
      int? leasesDuringAdd;
      final client = _Client(
        (_) async => _Response(HttpStatus.ok, body: '{}'),
        onAdd: () => leasesDuringAdd = authority.openLeases,
      );
      final operation = await authority.begin();
      final response = await operation.run(
        () => IoClaudeHttpTransport(
          client: client,
        ).send('POST', report, headers: const {}, body: 'grant_type=synthetic'),
      );
      expect(response.statusCode, HttpStatus.ok);
      expect(leasesDuringAdd, 1);
      expect(authority.openLeases, 0);
      expect(client.requests.single.events, ['add', 'close']);
    });

    test('a provider retry after a switch is never sent', () async {
      final authority = MemoryDataModeAuthority();
      final client = _Client(
        (_) async => _Response(HttpStatus.tooManyRequests),
      );
      final http = ProviderReportingHttp(
        transport: IoProviderHttpTransport(client: client),
        delay: (_) => authority.switchTo(DataMode.demo),
        random: () => 0,
      );
      final operation = await authority.begin();
      await expectLater(
        operation.run(
          () => http.post(
            report,
            headers: const {},
            body: '{}',
            label: 'Synthetic report',
          ),
        ),
        throwsA(isA<DataModeRetired>()),
      );
      expect(client.requests.map((request) => request.events).toList(), [
        ['add', 'close'],
        ['abort'],
      ]);
    });

    test('scoped work never follows a redirect', () async {
      final authority = MemoryDataModeAuthority();
      final redirect = _Response(
        HttpStatus.found,
        next: () async => _Response(HttpStatus.ok),
      );
      final client = _Client((_) async => redirect);
      final operation = await authority.begin();
      await expectLater(
        operation.run(
          () => IoClaudeHttpTransport(
            client: client,
          ).send('GET', usage, headers: const {}),
        ),
        throwsA(
          isA<ClaudeAccountException>().having(
            (error) => error.failure,
            'failure',
            ClaudeAccountFailure.invalidResponse,
          ),
        ),
      );
      // No redirected connection is opened outside the lease.
      expect(redirect.redirectCalls, 0);
      expect(client.requests.single.followRedirects, isFalse);
      expect(authority.openLeases, 0);
    });

    test('account actions keep automatic redirects', () async {
      final client = _Client((_) async => _Response(HttpStatus.ok, body: '{}'));
      await IoClaudeHttpTransport(
        client: client,
      ).send('GET', usage, headers: const {});
      expect(client.requests.single.followRedirects, isTrue);
      expect(client.requests.single.events, ['close']);
    });
  });

  group('Claude rotation', () {
    test('a switch during refresh setup commits at once', () async {
      final authority = MemoryDataModeAuthority();
      final opened = Completer<void>();
      final held = Completer<void>();
      final client = _Client(
        (_) => throw StateError('Nothing is sent.'),
        beforeOpen: () {
          opened.complete();
          return held.future;
        },
      );
      ClaudeAccountSession? stored;
      final operation = await authority.begin();
      final report = expectLater(
        operation.run(
          () => _claude(client).fetchReport(
            _expired,
            onSessionChanged: (session) async => stored = session,
          ),
        ),
        throwsA(isA<DataModeRetired>()),
      );
      await opened.future;
      final switched = await authority.switchTo(DataMode.demo);
      expect(switched.unresolvedStorageFailure, isFalse);
      held.complete();
      await report;
      expect(client.requests.single.events, ['abort']);
      expect(stored, isNull);
    });

    test('a replaced session is not an unresolved rotation', () async {
      final authority = MemoryDataModeAuthority();
      final token = Completer<HttpClientResponse>();
      final tokenSent = Completer<void>();
      final client = _Client((_) {
        tokenSent.complete();
        return token.future;
      });
      final operation = await authority.begin();
      final report = expectLater(
        operation.run(
          () => _claude(client).fetchReport(
            _expired,
            onSessionChanged:
                (_) async =>
                    throw const ClaudeAccountException(
                      ClaudeAccountFailure.cancelled,
                      'Sanitized replaced session.',
                    ),
          ),
        ),
        throwsA(isA<ClaudeAccountException>()),
      );
      await tokenSent.future;
      final switched = authority.switchTo(DataMode.demo);
      token.complete(_rotated());
      expect((await switched).unresolvedStorageFailure, isFalse);
      await report;
    });

    test('an expired refresh send ends while still owned', () async {
      final authority = MemoryDataModeAuthority();
      int? leasesAtAbort;
      final client = _Client(
        (_) => Completer<HttpClientResponse>().future,
        onAbort: () => leasesAtAbort = authority.openLeases,
      );
      final operation = await authority.begin();
      await expectLater(
        operation.run(
          () => DataModeOperation.settle(
            () => IoClaudeHttpTransport(client: client).send(
              'POST',
              _token,
              headers: const {},
              body: 'grant_type=synthetic',
              timeout: const Duration(milliseconds: 1),
            ),
            (_) async {},
          ),
        ),
        throwsA(
          isA<ClaudeAccountException>().having(
            (error) => error.failure,
            'failure',
            ClaudeAccountFailure.unavailable,
          ),
        ),
      );
      // The timed-out send is aborted before its settlement lease is released.
      expect(leasesAtAbort, 1);
      expect(authority.openLeases, 0);
      expect(client.requests.single.events, ['add', 'close', 'abort']);
    });

    test('a stalled redirect body cannot hold a refresh', () async {
      final authority = MemoryDataModeAuthority();
      final listening = Completer<void>();
      final cancelled = Completer<void>();
      final body = StreamController<List<int>>(
        onListen: listening.complete,
        onCancel: cancelled.complete,
      );
      final redirect = _Response(
        HttpStatus.seeOther,
        stream: body.stream,
        next: () async => _Response(HttpStatus.ok),
      );
      final response = Completer<HttpClientResponse>();
      addTearDown(() async {
        if (!response.isCompleted) response.complete(redirect);
        if (!listening.isCompleted) {
          await body.stream.listen(null).cancel();
        }
        await body.close();
      });
      final tokenSent = Completer<void>();
      final client = _Client((_) {
        tokenSent.complete();
        return response.future;
      });
      final operation = await authority.begin();
      final rotation = expectLater(
        operation.run(
          () => _claude(client).fetchReport(
            _expired,
            onSessionChanged: (_) async => fail('Redirect stored a session.'),
          ),
        ),
        throwsA(
          isA<ClaudeAccountException>().having(
            (error) => error.failure,
            'failure',
            ClaudeAccountFailure.invalidResponse,
          ),
        ),
      );
      await tokenSent.future;
      final switched = authority.switchTo(DataMode.demo);
      expect(authority.switching, isTrue);
      expect(authority.openLeases, 1);
      // Redirect headers arrive; the body never finishes.
      response.complete(redirect);
      await listening.future;
      expect(cancelled.isCompleted, isTrue);
      expect((await switched).state.mode, DataMode.demo);
      await rotation;
      expect(redirect.redirectCalls, 0);
      expect(_isToken(client.requests.single), isTrue);
      expect(client.requests.single.method, 'POST');
      expect(client.requests.single.followRedirects, isFalse);
      expect(client.requests.single.events, ['add', 'close']);
      expect(authority.openLeases, 0);
    });

    test('a refresh abandoned during admission is never sent', () async {
      final memory = MemoryDataModeAuthority();
      final authority = _Held(memory, admit: Completer<void>());
      addTearDown(() {
        if (!authority.admit!.isCompleted) authority.admit!.complete();
      });
      final operation = await authority.begin();
      var sends = 0;
      var aborts = 0;
      await expectLater(
        operation.run(
          () => DataModeOperation.settle(
            () => DataModeOperation.dispatch(
              () async => ++sends,
              abort: () => aborts++,
            ).timeout(Duration.zero),
            (_) async {},
          ),
        ),
        throwsA(isA<TimeoutException>()),
      );
      // Admission is granted only after the caller gave up.
      authority.admit!.complete();
      await authority.exited.future;
      expect(sends, 0);
      expect(aborts, 1);
      expect(memory.openLeases, 0);
      expect((await memory.switchTo(DataMode.demo)).state.generation, 1);
    });
  });

  group('Codex rotation', () {
    for (final expired in [true, false]) {
      final trigger = expired ? 'expiry' : 'authentication failure';
      test('a scoped refresh after $trigger requires storage', () async {
        final authority = MemoryDataModeAuthority();
        final operation = await authority.begin();
        final client = _Client(
          (request) async => _Response(
            request.url.path.endsWith('/usage')
                ? HttpStatus.unauthorized
                : HttpStatus.ok,
            body: '{}',
          ),
        );
        final codex = CodexAccountClient(
          transport: IoCodexHttpTransport(client: client),
          clock: () => _now,
        );
        final session = CodexAccountSession(
          accessToken: 'synthetic-access',
          refreshToken: 'synthetic-refresh',
          accountId: 'synthetic-account',
          refreshedAt: expired ? _now.subtract(const Duration(days: 9)) : _now,
        );

        await expectLater(
          operation.run(() => codex.fetchReport(session)),
          throwsA(
            isA<CodexAccountException>().having(
              (error) => error.failure,
              'failure',
              CodexAccountFailure.unavailable,
            ),
          ),
        );
        expect(
          client.requests.map((request) => request.method),
          expired ? isEmpty : orderedEquals(['GET', 'GET']),
        );
      });
    }
  });

  group('native authority', () {
    late NativeCacheTestBridge bridge;
    setUpAll(() async {
      bridge = await NativeCacheTestBridge.start();
    });
    setUp(() => bridge.reset());
    tearDownAll(() => bridge.close());

    MethodChannelDataModeAuthority authority(
      String engine, {
      DataModePolicy policy = _debug,
      DebugDataPreferenceStore? legacy,
      ConnectionCachePlatform? platform,
    }) => MethodChannelDataModeAuthority(
      platform: platform ?? bridge.platform(engine),
      policy: policy,
      legacy: legacy ?? _Legacy(false),
    );

    test('Debug migrates the legacy Mock key once', () async {
      final legacy = _Legacy(true);
      final foreground = authority('ui', legacy: legacy);
      final first = await foreground.read();
      expect(first.mode, DataMode.mock);
      expect(first.generation, 0);
      expect(legacy.reads, 1);

      // The worker sees the same record; a later legacy value is ignored.
      final laterLegacy = _Legacy(false);
      final worker = authority('worker', legacy: laterLegacy);
      final shared = await worker.read();
      expect(shared.mode, DataMode.mock);
      expect(shared.installId, first.installId);
      expect(laterLegacy.reads, 0);
    });

    test('an unreadable legacy key leaves the record absent', () async {
      final legacy = _Legacy(null);
      final foreground = authority('ui', legacy: legacy);
      await expectLater(foreground.read(), throwsStateError);
      expect(
        (await bridge.invoke('ui', 'readMode', {}) as Map)['initialized'],
        isFalse,
      );
      legacy.mock = false;
      expect((await foreground.read()).mode, DataMode.live);
      expect(legacy.reads, 2);
    });

    test('production startup with a legacy Mock key is Live', () async {
      await bridge.invoke('test', 'setMockAllowed', {'value': false});
      final legacy = _Legacy(true);
      final production = authority('ui', policy: _production, legacy: legacy);
      final state = await production.read();
      expect(state.mode, DataMode.live);
      expect(legacy.reads, 0);
      final operation = await production.begin();
      expect(operation.mode, DataMode.live);
      expect(() => production.switchTo(DataMode.mock), throwsArgumentError);
    });

    test('build policy retires the Debug Mock generation', () async {
      final debug = authority('ui', legacy: _Legacy(true));
      final mock = await debug.begin();
      expect(mock.mode, DataMode.mock);

      // Profile and Release share the production policy in this bridge.
      await bridge.invoke('test', 'setMockAllowed', {'value': false});
      final profile = await authority('ui', policy: _production).begin();
      expect(profile.mode, DataMode.live);
      expect(profile.state.installId, mock.state.installId);
      expect(profile.generation, mock.generation + 1);
      // A delayed request from the Debug process is no longer current.
      expect(await mock.isCurrent(), isFalse);

      await bridge.invoke('test', 'restart', {});
      final release = await authority('ui', policy: _production).begin();
      expect(release.mode, DataMode.live);
      expect(release.state.installId, profile.state.installId);
      expect(release.generation, profile.generation);

      await bridge.invoke('test', 'setMockAllowed', {'value': true});
      final legacy = _Legacy(true);
      final restoredDebug = authority('ui', legacy: legacy);
      final restored = await restoredDebug.begin();
      expect(restored.mode, DataMode.live);
      expect(restored.state.installId, mock.state.installId);
      expect(restored.generation, release.generation);
      expect(legacy.reads, 0);

      final selectedMock = (await restoredDebug.switchTo(DataMode.mock)).state;
      expect(selectedMock.mode, DataMode.mock);
      expect(selectedMock.generation, restored.generation + 1);
      // Returning to Mock cannot admit a pending publication from old Mock.
      expect(await mock.isCurrent(), isFalse);
      expect(
        await mock.guard(() async => fail('Retired publication ran.')),
        isFalse,
      );
      expect(await release.isCurrent(), isFalse);
    });

    /// Collects futures a test starts against the bridge. Teardown releases
    /// held responses, then waits for them so the next reset starts idle;
    /// their failures were already reported by the test itself.
    List<Future<Object?>> inFlight(void Function() release) {
      final started = <Future<Object?>>[];
      addTearDown(() async {
        release();
        for (final future in started) {
          await future.then<void>((_) {}, onError: (Object _) {});
        }
      });
      return started;
    }

    /// Reads native state after every earlier request on the ordered bridge.
    Future<bool> switching() async =>
        (await bridge.invoke('ui', 'readMode', {}) as Map)['switching'] == true;

    test('both engines drain a held rotation before the switch', () async {
      final submitted = _Observed(bridge.platform('ui'));
      final foreground = authority('ui', platform: submitted);
      final worker = authority('worker');
      final operation = await worker.begin();
      final response = Completer<String>();
      final started = inFlight(() {
        if (!response.isCompleted) response.complete('session-1');
      });
      final initiated = Completer<void>();
      var stored = 'session-0';
      final rotation = operation.run(
        () => DataModeOperation.settle(
          () => DataModeOperation.dispatch(() {
            initiated.complete();
            return response.future;
          }),
          (rotated) async => stored = rotated,
        ),
      );
      started.add(rotation);
      await initiated.future;
      var committed = false;
      final switched = foreground
          .switchTo(DataMode.demo)
          .whenComplete(() => committed = true);
      started.add(switched);
      await submitted.switchSubmitted.future;
      expect(await switching(), isTrue);
      expect(committed, isFalse);
      // Neither engine admits new work while the switch drains.
      await expectLater(worker.begin(), throwsA(isA<DataModeRetired>()));
      await expectLater(foreground.begin(), throwsA(isA<DataModeRetired>()));
      expect(await worker.enter(operation.generation), isNull);
      expect(committed, isFalse);
      response.complete('session-1');
      await rotation;
      final result = await switched;
      expect(stored, 'session-1');
      expect(result.state.mode, DataMode.demo);
      expect(result.state.generation, 1);
      expect(result.unresolvedStorageFailure, isFalse);
      expect(await operation.isCurrent(), isFalse);
    });

    test('a worker storage failure is surfaced by the UI switch', () async {
      final submitted = _Observed(bridge.platform('ui'));
      final foreground = authority('ui', platform: submitted);
      final operation = await authority('worker').begin();
      final response = Completer<String>();
      final started = inFlight(() {
        if (!response.isCompleted) response.complete('session-1');
      });
      final initiated = Completer<void>();
      final rotation = operation.run(
        () => DataModeOperation.settle(
          () => DataModeOperation.dispatch(() {
            initiated.complete();
            return response.future;
          }),
          (_) async => throw StateError('Sanitized account storage failure.'),
        ),
      );
      started.add(rotation);
      await initiated.future;
      final switched = foreground.switchTo(DataMode.demo);
      started.add(switched);
      await submitted.switchSubmitted.future;
      expect(await switching(), isTrue);
      response.complete('session-1');
      await expectLater(rotation, throwsStateError);
      expect((await switched).unresolvedStorageFailure, isTrue);
    });

    test('a held refresh is stored, then Live reloads it', () async {
      await bridge.invoke('test', 'setClock', {
        'value': _now.millisecondsSinceEpoch,
      });
      final secure = FakeSecureStorage();
      final store = SecureClaudeAccountStore(
        storage: secure,
        platform: bridge.platform('worker'),
      );
      await store.write(_expired);
      final token = Completer<HttpClientResponse>();
      final started = inFlight(() {
        if (!token.isCompleted) token.complete(_rotated());
      });
      final tokenSent = Completer<void>();
      final client = _Client((request) {
        if (!_isToken(request)) {
          return Future.value(_Response(HttpStatus.ok, body: '{}'));
        }
        tokenSent.complete();
        return token.future;
      });
      final service = MobileClaudeAccountService(
        store: store,
        client: _claude(client),
      );
      final worker = authority('worker');
      final submitted = _Observed(bridge.platform('ui'));
      final foreground = authority('ui', platform: submitted);

      final report = expectLater(
        (await worker.begin()).run(service.fetchReport),
        // The retired operation never sends its usage request.
        throwsA(isA<ConnectionFetchRetired>()),
      );
      started.add(report);
      await tokenSent.future;
      var storedAtCommit = false;
      final switched = foreground.switchTo(DataMode.demo).then((result) {
        storedAtCommit = secure.values.values.any(
          (value) => value.contains('rotated-refresh'),
        );
        return result;
      });
      started.add(switched);
      await submitted.switchSubmitted.future;
      expect(await switching(), isTrue);
      token.complete(_rotated());
      expect((await switched).unresolvedStorageFailure, isFalse);
      // The switch committed only after versioned storage accepted it.
      expect(storedAtCommit, isTrue);
      await report;
      expect(client.requests.last.events, ['abort']);

      // Live -> Demo -> Live: a fresh operation reloads the rotation.
      await foreground.switchTo(DataMode.live);
      expect(await (await worker.begin()).run(service.fetchReport), isNotNull);
      expect((await store.read())?.refreshToken, 'rotated-refresh');
      expect(
        client.requests.last.headers.fields['Authorization'],
        'Bearer rotated-access',
      );
    });

    test('a failed mode write keeps the old generation', () async {
      final foreground = authority('ui');
      final operation = await foreground.begin();
      await bridge.invoke('test', 'failModeCommit', {'value': true});
      await expectLater(foreground.switchTo(DataMode.demo), throwsStateError);
      await bridge.invoke('test', 'failModeCommit', {'value': false});
      expect((await foreground.read()).mode, DataMode.live);
      expect(await operation.isCurrent(), isTrue);
      expect((await foreground.begin()).generation, 0);
    });

    test('Demo survives a restart under production policy', () async {
      final before = await authority('ui').switchTo(DataMode.demo);
      await bridge.invoke('test', 'setMockAllowed', {'value': false});
      final after = await authority('worker', policy: _production).read();
      expect(after.installId, before.state.installId);
      expect(after.mode, DataMode.demo);
      expect(after.generation, 1);
    });

    ConnectionCredentialStorage credentials(
      String engine, {
      ConnectionCachePlatform? platform,
      FakeSecureStorage? storage,
    }) => ConnectionCredentialStorage(
      connection: 'cursor.plan',
      legacyKey: 'wardpulse.cursor.plan.secret',
      principal: (value) => value,
      storage: storage ?? FakeSecureStorage(),
      platform: platform ?? bridge.platform(engine),
    );
    AutomaticPollContext periodic() => AutomaticPollContext(
      readInterval: () async => const Duration(minutes: 5),
    );

    test('unscoped fetches leave the legacy Debug choice in charge', () async {
      final access = credentials('ui');
      await access.write('synthetic-key');
      final version = (await access.read())!.version;
      final poll = periodic();
      await poll.run(
        () => access.serializeFetch(() => access.admitAutomatic(version)),
      );
      expect(poll.attempted, {'cursor.plan'});
      expect(
        (await bridge.invoke('ui', 'readMode', {}) as Map)['initialized'],
        isFalse,
      );
      // A Debug toggle made before the import is read when it first runs.
      final legacy = _Legacy(false);
      await legacy.writeMockDataEnabled(true);
      final imported = await authority('ui', legacy: legacy).read();
      expect(imported.mode, DataMode.mock);
      expect(legacy.reads, 1);
    });

    test('a bound fetch retired before native release cannot finish', () async {
      final mode = authority('ui');
      final access = credentials('ui');
      await access.write('synthetic-key');
      final operation = await mode.begin();
      await expectLater(
        operation.run(
          () => access.serializeFetch(() async {
            await mode.switchTo(DataMode.demo);
            return 1;
          }),
        ),
        throwsA(isA<ConnectionFetchRetired>()),
      );
      await expectLater(
        operation.run(() => access.serializeFetch(() async => 2)),
        throwsA(isA<ConnectionFetchRetired>()),
      );
      // The retired fetch released its reservation for current Live work.
      await mode.switchTo(DataMode.live);
      final current = await mode.begin();
      expect(await current.run(() => access.serializeFetch(() async => 3)), 3);
    });

    test(
      'a fetch grant delivered after switching never starts its callback',
      () async {
        final platform = ObservingCachePlatform(bridge.platform('worker'));
        final grant = Completer<void>();
        final deliver = Completer<void>();
        final started = inFlight(() {
          if (!deliver.isCompleted) deliver.complete();
        });
        platform.onComplete = (method, _, _) async {
          if (method != 'acquireFetch') return;
          grant.complete();
          await deliver.future;
        };
        var acquisitions = 0;
        platform.beforeInvoke = (method, _) {
          if (method == 'acquire') acquisitions++;
        };
        final access = credentials('worker', platform: platform);
        final operation = await authority('worker').begin();
        var callbacks = 0;
        final fetch = expectLater(
          operation.run(
            () => access.serializeFetch(() async {
              callbacks++;
              return access.read();
            }),
          ),
          throwsA(isA<ConnectionFetchRetired>()),
        );
        started.add(fetch);
        await grant.future;

        final submitted = _Observed(bridge.platform('ui'));
        final mode = authority('ui', platform: submitted);
        final switched = mode.switchTo(DataMode.demo);
        started.add(switched);
        await submitted.switchSubmitted.future;
        expect(await switching(), isFalse);
        expect((await switched).state.mode, DataMode.demo);
        deliver.complete();
        await fetch;
        expect(callbacks, 0);
        expect(acquisitions, 0);
      },
    );

    test(
      'native rejects a credential read after Dart validated the fetch',
      () async {
        final mode = authority('ui');
        final platform = ObservingCachePlatform(bridge.platform('worker'));
        final secure = FakeSecureStorage();
        final access = credentials(
          'worker',
          platform: platform,
          storage: secure,
        );
        secure.values[access.legacyKey] = 'synthetic-key';
        var reads = 0;
        secure.onRead = (_, _) => reads++;
        Object? admitted;
        Object? fetchTicket;
        Object? requestedReadTicket;
        var grantedRead = false;
        platform.onComplete = (method, arguments, result) {
          if (method == 'validFetch' && arguments['forAdmission'] == true) {
            admitted = result;
            fetchTicket = arguments['fetchTicket'];
          } else if (method == 'acquire') {
            grantedRead = true;
          }
        };
        platform.beforeInvoke = (method, arguments) async {
          if (method != 'acquire') return;
          requestedReadTicket = arguments['fetchTicket'];
          await mode.switchTo(DataMode.demo);
        };
        final operation = await authority('worker').begin();
        await expectLater(
          operation.run(() => access.serializeFetch(access.read)),
          throwsA(isA<ConnectionFetchRetired>()),
        );
        expect(admitted, isTrue);
        expect(fetchTicket, isA<String>());
        expect(requestedReadTicket, fetchTicket);
        expect((await mode.read()).mode, DataMode.demo);
        expect(grantedRead, isFalse);
        expect(reads, 0);
        expect(secure.deleted, isEmpty);
        expect(secure.values, {access.legacyKey: 'synthetic-key'});
      },
    );

    test(
      'a pre-fetch cache read cannot enter storage after a switch',
      () async {
        final mode = authority('ui');
        final worker = authority('worker');
        final platform = ObservingCachePlatform(bridge.platform('worker'));
        final secure = FakeSecureStorage();
        final access = credentials(
          'worker',
          platform: platform,
          storage: secure,
        );
        secure.values[access.legacyKey] = 'synthetic-key';
        var reads = 0;
        var writes = 0;
        secure.onRead = (_, _) => reads++;
        secure.beforeWrite = (_) async {
          writes++;
        };
        final cache = ConnectionSnapshotCache(
          connection: access.connection,
          platform: platform,
          readCredentialVersion: () async => (await access.read())?.version,
        );
        final request = Completer<Map<String, Object?>>();
        final resume = Completer<void>();
        final started = inFlight(() {
          if (!resume.isCompleted) resume.complete();
        });
        platform.beforeInvoke = (method, arguments) async {
          if (method != 'acquire') return;
          request.complete(arguments);
          await resume.future;
        };
        final operation = await worker.begin(cacheOnly: true);
        final capture = expectLater(
          operation.run(() => cache.capture()),
          throwsStateError,
        );
        started.add(capture);
        final arguments = await request.future;
        expect(arguments['action'], 'read');
        expect(arguments['fetchTicket'], isNull);

        expect((await mode.switchTo(DataMode.demo)).state.mode, DataMode.demo);
        resume.complete();
        await capture;
        expect(arguments['generation'], operation.generation);
        expect(reads, 0);
        expect(writes, 0);
        expect(secure.deleted, isEmpty);
        expect(secure.values, {access.legacyKey: 'synthetic-key'});

        platform.beforeInvoke = null;
        await mode.switchTo(DataMode.live);
        final current = await worker.begin(cacheOnly: true);
        expect((await current.run(() => cache.capture())).version, isNotNull);
      },
    );

    test('a retired cache repair preserves the new Live snapshot', () async {
      final mode = authority('ui');
      final worker = authority('worker');
      final platform = ObservingCachePlatform(bridge.platform('worker'));
      final access = credentials('worker', platform: platform);
      await access.write('synthetic-key');
      final version = (await access.read())!.version;
      const malformed = '{';
      expect(
        await bridge.invoke('ui', 'writeSnapshot', {
          'connection': access.connection,
          'expected': version.values,
          'snapshot': malformed,
          'generatedAt': _now.microsecondsSinceEpoch,
        }),
        isTrue,
      );
      final cache = ConnectionSnapshotCache(
        connection: access.connection,
        platform: platform,
        readCredentialVersion: () async => (await access.read())?.version,
      );
      final oldReply = Completer<Object?>();
      final deliver = Completer<void>();
      final started = inFlight(() {
        if (!deliver.isCompleted) deliver.complete();
      });
      platform.onComplete = (method, _, result) async {
        if (method != 'readSnapshot' || oldReply.isCompleted) return;
        oldReply.complete(result);
        await deliver.future;
      };
      final repairs = <Object?>[];
      platform.beforeInvoke = (method, arguments) {
        if (method == 'clearSnapshot') repairs.add(arguments['generation']);
      };
      final old = await worker.begin(cacheOnly: true);
      final capture = expectLater(
        old.run(() => cache.capture()),
        throwsStateError,
      );
      started.add(capture);
      expect((await oldReply.future as Map)['snapshot'], malformed);

      await mode.switchTo(DataMode.demo);
      await mode.switchTo(DataMode.live);
      final current = await worker.begin();
      final replacement = DashboardSnapshot.empty(
        generatedAt: _now.add(const Duration(seconds: 1)),
      );
      expect(
        await current.run(() => cache.store(replacement, version)),
        isTrue,
      );
      deliver.complete();
      await capture;
      expect(repairs, [old.generation]);

      final retained = await current.run(() => cache.capture());
      expect(retained.snapshot?.generatedAt, replacement.generatedAt);
      expect(retained.version?.values['epoch'], version.values['epoch']);
    });

    test('native release rejects a fetch retired after validation', () async {
      final mode = authority('ui');
      final platform = ObservingCachePlatform(bridge.platform('worker'));
      final access = credentials('worker', platform: platform);
      final operation = await mode.begin();
      Object? validated;
      Object? released;
      platform.onComplete = (method, arguments, result) async {
        if (method == 'validFetch' && arguments['forAdmission'] != true) {
          validated = result;
          await mode.switchTo(DataMode.demo);
        } else if (method == 'releaseFetch') {
          released = result;
        }
      };

      await expectLater(
        operation.run(() => access.serializeFetch(() async => 1)),
        throwsA(isA<ConnectionFetchRetired>()),
      );
      expect(validated, isTrue);
      expect(released, isFalse);

      platform.onComplete = null;
      await mode.switchTo(DataMode.live);
      final current = await mode.begin();
      expect(await current.run(() => access.serializeFetch(() async => 2)), 2);
    });

    test('admitted failures count; cache-only work never anchors', () async {
      final mode = authority('worker');
      final access = credentials('worker');
      await access.write('synthetic-key');
      final version = (await access.read())!.version;
      Future<void> poll(
        DataModeOperation operation,
        AutomaticPollContext context, {
        Exception? failure,
      }) => operation.run(
        () => context.run(
          () => access.serializeFetch(() async {
            await access.admitAutomatic(version);
            if (failure != null) throw failure;
          }),
        ),
      );

      // Outside a poll, cache-only work is still denied before any transport.
      await expectLater(
        (await mode.begin(cacheOnly: true)).run(
          () => access.serializeFetch(() => access.admitAutomatic(version)),
        ),
        throwsA(isA<AutomaticPollSkipped>()),
      );

      final cacheOnly = periodic();
      await expectLater(
        poll(await mode.begin(cacheOnly: true), cacheOnly),
        throwsA(isA<AutomaticPollSkipped>()),
      );
      expect(cacheOnly.automaticAt, isEmpty);
      expect(cacheOnly.attempted, isEmpty);

      final admitted = periodic();
      await expectLater(
        poll(
          await mode.begin(),
          admitted,
          failure: const SocketException('Sanitized connection failure.'),
        ),
        throwsA(isA<SocketException>()),
      );
      expect(admitted.attempted, {'cursor.plan'});

      await bridge.invoke('test', 'setClock', {'value': 1000});
      final denied = periodic();
      await expectLater(
        poll(await mode.begin(), denied),
        throwsA(isA<AutomaticPollSkipped>()),
      );
      expect(denied.attempted, isEmpty);
      expect(denied.automaticAt, admitted.automaticAt);
    });
  });
}

final class _Legacy implements DebugDataPreferenceStore {
  _Legacy(this.mock);

  /// `null` makes the legacy key unreadable.
  bool? mock;
  var reads = 0;

  @override
  Future<bool> readMockDataEnabled() async {
    reads++;
    final value = mock;
    if (value == null) throw StateError('Sanitized legacy preference failure.');
    return value;
  }

  @override
  Future<void> writeMockDataEnabled(bool value) async {
    mock = value;
  }
}

/// Holds lease admission or release until the matching completer completes.
final class _Held implements DataModeAuthority {
  _Held(this._inner, {this.admit, this.release});

  final MemoryDataModeAuthority _inner;
  final Completer<void>? admit;
  final Completer<void>? release;
  Object? enterError;
  Object? currentError;

  /// Completes once a lease has been released.
  final exited = Completer<void>();

  @override
  Future<DataModeState> read() => _inner.read();

  @override
  Future<DataModeOperation> begin({bool cacheOnly = false}) async {
    final operation = await _inner.begin(cacheOnly: cacheOnly);
    return DataModeOperation(
      authority: this,
      state: operation.state,
      requestId: operation.requestId,
      cacheOnly: cacheOnly,
    );
  }

  @override
  Future<bool> isCurrent(int generation) async {
    if (currentError case final error?) throw error;
    return _inner.isCurrent(generation);
  }

  @override
  Future<String?> enter(int generation, {bool settlement = false}) async {
    await admit?.future;
    if (enterError case final error?) throw error;
    return _inner.enter(generation, settlement: settlement);
  }

  @override
  Future<void> exit(String lease, {bool unresolved = false}) async {
    await release?.future;
    await _inner.exit(lease, unresolved: unresolved);
    if (!exited.isCompleted) exited.complete();
  }

  @override
  Future<DataModeSwitch> switchTo(DataMode mode) => _inner.switchTo(mode);
}

/// Signals once a switch request is written to the ordered native bridge.
final class _Observed implements ConnectionCachePlatform {
  _Observed(this._inner);

  final ConnectionCachePlatform _inner;
  final switchSubmitted = Completer<void>();

  @override
  Future<Object?> invoke(String method, Map<String, Object?> arguments) {
    final result = _inner.invoke(method, arguments);
    if (method == 'switchMode' && !switchSubmitted.isCompleted) {
      switchSubmitted.complete();
    }
    return result;
  }
}

/// Records each request; [respond] answers its `close`.
final class _Client extends Fake implements HttpClient {
  _Client(this.respond, {this.beforeOpen, this.onAdd, this.onAbort});

  final Future<HttpClientResponse> Function(_Request request) respond;

  /// Holds `openUrl` until the returned future completes.
  final Future<void> Function()? beforeOpen;
  final void Function()? onAdd;
  final void Function()? onAbort;
  final requests = <_Request>[];

  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) async {
    await beforeOpen?.call();
    final request = _Request(this, method, url);
    requests.add(request);
    return request;
  }

  @override
  Future<HttpClientRequest> getUrl(Uri url) => openUrl('GET', url);

  @override
  Future<HttpClientRequest> postUrl(Uri url) => openUrl('POST', url);
}

final class _Request extends Fake implements HttpClientRequest {
  _Request(this._client, this.method, this.url);

  final _Client _client;
  @override
  final String method;
  final Uri url;
  final events = <String>[];

  @override
  final _Headers headers = _Headers();

  @override
  bool followRedirects = true;

  @override
  int maxRedirects = 5;

  @override
  int contentLength = -1;

  @override
  void add(List<int> data) {
    events.add('add');
    _client.onAdd?.call();
  }

  @override
  void write(Object? object) => events.add('write');

  /// Completed by the response, or by [abort] like a real request.
  Completer<HttpClientResponse>? _done;

  @override
  Future<HttpClientResponse> close() {
    events.add('close');
    final done = _done = Completer<HttpClientResponse>();
    _client
        .respond(this)
        .then(
          (response) {
            if (response is _Response) response.requestMethod = method;
            if (!done.isCompleted) done.complete(response);
          },
          onError: (Object error, StackTrace stackTrace) {
            if (!done.isCompleted) done.completeError(error, stackTrace);
          },
        );
    return done.future;
  }

  @override
  void abort([Object? exception, StackTrace? stackTrace]) {
    events.add('abort');
    _client.onAbort?.call();
    if (_done case final done? when !done.isCompleted) {
      done.completeError(
        exception ?? const HttpException('Request aborted.'),
        stackTrace,
      );
    }
  }
}

final class _Headers extends Fake implements HttpHeaders {
  final fields = <String, String>{};

  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {
    fields[name] = '$value';
  }

  @override
  void forEach(void Function(String name, List<String> values) action) =>
      fields.forEach((name, value) => action(name, [value]));
}

final class _Response extends StreamView<List<int>>
    implements HttpClientResponse {
  _Response(
    this.statusCode, {
    String body = '',
    Stream<List<int>>? stream,
    this.next,
  }) : super(stream ?? Stream.value(utf8.encode(body)));

  @override
  final int statusCode;

  /// The redirect target, when this response is a redirect.
  final Future<HttpClientResponse> Function()? next;
  String? requestMethod;
  var redirectCalls = 0;

  @override
  bool get isRedirect => switch (requestMethod) {
    'GET' || 'HEAD' =>
      statusCode == HttpStatus.found || statusCode == HttpStatus.seeOther,
    'POST' => statusCode == HttpStatus.seeOther,
    _ => false,
  };

  @override
  List<RedirectInfo> get redirects => const [];

  @override
  final HttpHeaders headers = _Headers();

  @override
  Future<HttpClientResponse> redirect([
    String? method,
    Uri? url,
    bool? followLoops,
  ]) {
    redirectCalls++;
    return next!();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
