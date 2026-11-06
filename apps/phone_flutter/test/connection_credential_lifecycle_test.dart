import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ward_pulse_phone/dashboard/dashboard_load.dart';
import 'package:ward_pulse_phone/dashboard/dashboard_models.dart';
import 'package:ward_pulse_phone/dashboard/dashboard_repository.dart';
import 'package:ward_pulse_phone/dashboard/connection_snapshot_cache.dart';
import 'package:ward_pulse_phone/dashboard/codex_dashboard_repository.dart';
import 'package:ward_pulse_phone/dashboard/claude_dashboard_repository.dart';
import 'package:ward_pulse_phone/providers/connection_lifecycle.dart';
import 'package:ward_pulse_phone/providers/connection_rejection_notice.dart';
import 'package:ward_pulse_phone/providers/claude_account_service.dart';
import 'package:ward_pulse_phone/providers/claude_account_store.dart';
import 'package:ward_pulse_phone/providers/codex_account_service.dart';
import 'package:ward_pulse_phone/providers/codex_account_store.dart';
import 'package:ward_pulse_phone/providers/provider_connection.dart';
import 'package:ward_pulse_phone/providers/provider_credential_store.dart';
import 'package:ward_pulse_phone/sync/claude_account_client.dart';
import 'package:ward_pulse_phone/sync/codex_account_client.dart';
import 'package:ward_pulse_phone/sync/provider_sync_logger.dart';
import 'package:ward_pulse_phone/sync/automatic_poll.dart';

import 'connection_cache_test_support.dart';

void main() {
  late NativeCacheTestBridge bridge;
  late FakeSecureStorage secure;
  final now = DateTime.utc(2026, 10, 13, 9);
  setUpAll(() async {
    bridge = await NativeCacheTestBridge.start();
  });
  tearDownAll(() => bridge.close());
  setUp(() async {
    await bridge.reset();
    secure = FakeSecureStorage();
  });
  ConnectionCredentialStorage store(String owner) =>
      ConnectionCredentialStorage(
        connection: 'cursor.plan',
        legacyKey: 'wardpulse.cursor.plan.secret',
        principal: (value) => value,
        storage: secure,
        platform: bridge.platform(owner),
      );

  SecureProviderCredentialStore reportingStore(String owner) =>
      SecureProviderCredentialStore(
        storage: secure,
        platform: bridge.platform(owner),
      );

  test(
    'retained-session notices survive lifecycle changes and exact dismissal',
    () async {
      final access = store('session');
      final notices = NativeConnectionRejectionNoticeStore(
        platform: bridge.platform('notices'),
      );
      expect(await notices.read(), isEmpty);
      await access.write('synthetic-session');
      var captured = (await access.read())!;
      expect(
        await access.serializeFetch(
          () => access.rejectAuthentication(captured.version),
        ),
        isTrue,
      );
      final first = (await notices.read()).single;
      expect(await notices.dismiss(first), isTrue);
      await bridge.invoke('test', 'restart', {});
      captured = (await store('cold').read())!;
      expect(
        await access.serializeFetch(
          () => access.rejectAuthentication(captured.version),
        ),
        isTrue,
      );
      expect((await notices.read()).single.dismissed, isTrue);
      await access.write('synthetic-session');
      expect((await notices.read()).single.eventId, first.eventId);
      captured = (await access.read())!;
      await access.serializeFetch(
        () => access.rejectAuthentication(captured.version),
      );
      final second = (await notices.read()).single;
      expect(second.eventId, isNot(first.eventId));
      expect(await notices.dismiss(first), isFalse);
      await access.delete();
      expect(await store('cold2').read(), isNull);
      expect((await notices.read()).single.dismissed, isFalse);
      await bridge.invoke('test', 'restart', {});
      expect((await notices.read()).single.eventId, second.eventId);
      await notices.dismiss(second);
      await bridge.invoke('test', 'restart', {});
      expect(
        (await notices.read()).where((notice) => !notice.dismissed),
        isEmpty,
      );
    },
  );

  test(
    'notice-only storage failure preserves valid credentials and confirmed view',
    () async {
      final access = store('session');
      final notices = NativeConnectionRejectionNoticeStore(
        platform: bridge.platform('notices'),
      );
      await access.write('synthetic-session');
      final captured = (await access.read())!;
      await access.serializeFetch(
        () => access.rejectAuthentication(captured.version),
      );
      final event = (await notices.read()).single;
      await bridge.invoke('test', 'failCommit', {'value': true});
      await expectLater(notices.dismiss(event), throwsStateError);
      expect((await notices.read()).single.dismissed, isFalse);
      expect(await access.isCurrent(captured.version), isTrue);
      await bridge.invoke('test', 'failCommit', {'value': false});
      expect((await store('cold').read())?.value, 'synthetic-session');
    },
  );

  test(
    'optional reporting access retains only immutable read provenance',
    () async {
      const id = ProviderConnections.openAiPlatform;
      final credentials = reportingStore('reporting');
      final VersionedProviderCredentialStore capability = credentials;
      final access = capability.credentialAccess(id)!;
      expect(
        capability.credentialAccess(ProviderConnections.codexPlan),
        isNull,
      );
      expect(
        capability.credentialAccess(ProviderConnections.claudePlan),
        isNull,
      );
      await credentials.writeSecret(id, ' fake-current ');
      final read = (await access.read())!;
      expect(read.value, 'fake-current');
      expect((await credentials.readVersion(id))?.values, read.version.values);
      final original = Map.of(read.version.values);
      expect(
        original.keys,
        unorderedEquals([
          'generation',
          'revision',
          'identity',
          'epoch',
          'committedConnection',
        ]),
      );
      final outcome = ConnectionReportingOutcome(
        connection: id,
        category: ReportingOutcomeCategory.success,
        source: ReportingOutcomeSource.live,
        freshness: ReportingOutcomeFreshness.current,
        credentialVersion: read.version,
      );
      expect(
        () => outcome.credentialVersion!.values.clear(),
        throwsUnsupportedError,
      );
      final otherRevision = CredentialVersion({
        ...original,
        'revision': 'different-revision',
      });
      expect(read.version.sameCache(otherRevision), isTrue);
      expect(await access.isCurrent(otherRevision), isTrue);

      // Even an explicit replacement with the same value retires the old stamp.
      final replacement = reportingStore('replacement');
      await replacement.writeSecret(id, 'fake-current');
      final current = (await access.read())!;
      expect(read.version.sameCache(current.version), isFalse);
      expect(await access.isCurrent(read.version), isFalse);
      expect(await access.isCurrent(current.version), isTrue);
      expect(outcome.credentialVersion!.values, original);
      await replacement.deleteSecret(id);
      expect(await access.isCurrent(current.version), isFalse);
      expect(await access.read(), isNull);
    },
  );

  for (final failure in ['label', 'retired slot']) {
    test(
      'reporting removal stays retired after $failure cleanup fails',
      () async {
        const id = ProviderConnections.openAiPlatform;
        final credentials = reportingStore('reporting');
        await credentials.writeSecret(id, 'synthetic-key');
        await credentials.writeLabel(id, 'Synthetic label');
        final version =
            (await credentials.credentialAccess(id)!.read())!.version;
        final failedKey =
            failure == 'label'
                ? 'wardpulse.openai.admin-api-key.label'
                : secure.values.keys.singleWhere(
                  (key) => key.startsWith('wardpulse.connection.'),
                );
        secure.failDeleteKey = failedKey;
        await expectLater(credentials.deleteSecret(id), throwsStateError);
        expect(await reportingStore('cold').readSecret(id), isNull);
        expect(
          await credentials.credentialAccess(id)!.isCurrent(version),
          isFalse,
        );
        expect(secure.values[failedKey], isNotNull);
        secure.failDeleteKey = null;
        // A normal retry finishes both native-retired cleanup and label removal.
        await reportingStore('cold').deleteSecret(id);
        expect(secure.values[failedKey], isNull);
      },
    );
  }

  test(
    'reporting absence differs from a failed local read and releases storage',
    () async {
      const id = ProviderConnections.cursorPlatform;
      final credentials = reportingStore('reporting');
      final access = credentials.credentialAccess(id)!;
      Future<String?> readSecret(ProviderCredentialStore source) =>
          readConnectionSecret(
            store: source,
            id: id,
            logger: const NullProviderSyncLogger(),
          );
      expect(await access.read(), isNull);
      expect(await readSecret(credentials), isNull);
      expect(await readSecret(const EmptyProviderCredentialStore()), isNull);
      await credentials.writeSecret(id, 'fake-saved');
      secure.failRead = true;
      await expectLater(access.read(), throwsStateError);
      await expectLater(
        readSecret(credentials),
        throwsA(
          isA<DashboardLoadException>()
              .having(
                (error) => error.issue,
                'issue',
                DashboardSyncIssue.credentialUnavailable,
              )
              .having((error) => error.details, 'safe details', isNull)
              .having(
                (error) => error.reportingOutcomes.single.connection,
                'connection',
                id,
              )
              .having(
                (error) => error.reportingOutcomes.single.category,
                'category',
                ReportingOutcomeCategory.localReadFailure,
              )
              .having(
                (error) => error.reportingOutcomes.single.source,
                'source',
                ReportingOutcomeSource.local,
              )
              .having(
                (error) => error.reportingOutcomes.single.credentialVersion,
                'unavailable provenance',
                isNull,
              ),
        ),
      );
      secure.failRead = false;
      expect((await access.read())?.value, 'fake-saved');
    },
  );

  test(
    'reporting fetch ownership serializes reads without holding a storage transaction',
    () async {
      const id = ProviderConnections.anthropicPlatform;
      final credentials = reportingStore('reporting-a');
      await credentials.writeSecret(id, 'fake-old');
      final a = credentials.credentialAccess(id)!;
      final queued = Completer<void>();
      final platform = _RecordingPlatform(bridge.platform('reporting-b'))
        ..onInvoke = (method, _) {
          if (method == 'acquireFetch') queued.complete();
        };
      final b =
          SecureProviderCredentialStore(
            storage: secure,
            platform: platform,
          ).credentialAccess(id)!;
      final entered = Completer<CredentialVersion>();
      final release = Completer<void>();
      final loadingA = a.serializeFetch(() async {
        final read = (await a.read())!;
        entered.complete(read.version);
        await release.future;
        return ConnectionReportingOutcome(
          connection: id,
          category: ReportingOutcomeCategory.authenticationRejected,
          source: ReportingOutcomeSource.live,
          credentialVersion: read.version,
        );
      });
      final original = await entered.future;
      var bEntered = false;
      final loadingB = b.serializeFetch(() async {
        bEntered = true;
        return (await b.read())!;
      });
      await queued.future;
      // User replacement commits while A's simulated network request is held.
      await credentials.writeSecret(id, 'fake-new');
      expect(bEntered, isFalse);
      expect(await a.isCurrent(original), isFalse);
      release.complete();
      final oldResult = await loadingA;
      final newRead = await loadingB;
      expect(oldResult.credentialVersion, same(original));
      expect(await a.isCurrent(oldResult.credentialVersion!), isFalse);
      expect(newRead.value, 'fake-new');
      expect(await b.isCurrent(newRead.version), isTrue);
    },
  );

  test(
    'reporting fetch ownership releases on errors and rejects detached completion',
    () async {
      const id = ProviderConnections.openAiPlatform;
      final credentials = reportingStore('reporting-a');
      await credentials.writeSecret(id, 'fake-current');
      final a = credentials.credentialAccess(id)!;
      final b = reportingStore('reporting-b').credentialAccess(id)!;
      await expectLater(
        a.serializeFetch<void>(
          () async => throw StateError('Sanitized failure.'),
        ),
        throwsStateError,
      );
      expect(await b.serializeFetch(() => b.read()), isNotNull);

      final entered = Completer<void>();
      final release = Completer<void>();
      final loading = a.serializeFetch(() async {
        await a.read();
        entered.complete();
        await release.future;
      });
      final rejected = expectLater(loading, throwsStateError);
      await entered.future;
      await bridge.invoke('reporting-a', 'detach', {});
      expect(await b.serializeFetch(() => b.read()), isNotNull);
      release.complete();
      await rejected;
      expect(await b.serializeFetch(() => b.read()), isNotNull);
    },
  );

  test(
    'installed legacy credential survives cancelled and superseded reconnect',
    () async {
      secure.values['wardpulse.cursor.plan.secret'] = 'fake-installed';
      final a = await store('ui').beginReconnect();
      final b = await store('second').beginReconnect();
      expect(await store('ui').completeReconnect('fake-delayed-A', a), isFalse);
      await store('second').cancelReconnect(b);
      final restored = (await store('cold').read())!;
      expect(restored.value, 'fake-installed');
      expect(restored.version.generation, b.generation);
      expect(restored.version.generation, isNot(a.generation));
      expect(secure.values.values, isNot(contains('fake-delayed-A')));
      final old = await store('old').beginReconnect();
      final newer = await store('new').beginReconnect();
      expect(
        await store('new').completeReconnect('fake-new-account', newer),
        isTrue,
      );
      expect(
        await store('old').completeReconnect('fake-late-account', old),
        isFalse,
      );
      await store('old').cancelReconnect(old);
      final current = (await store('cold').read())!;
      expect(current.value, 'fake-new-account');
      expect(current.version.generation, newer.generation);
      expect(await store('cold').isCurrent(restored.version), isFalse);
      expect(secure.values.values, isNot(contains('fake-late-account')));
    },
  );
  test(
    'cancelled reconnect preserves guarded backup through cold missing-copy recovery',
    () async {
      const legacy = 'wardpulse.cursor.plan.secret';
      secure.values[legacy] = 'fake-installed';
      final migrated = (await store('ui').read())!;
      final ticket = await store('ui').beginReconnect();
      await store('ui').cancelReconnect(ticket);
      secure.values.removeWhere(
        (key, _) => key.startsWith('wardpulse.connection.'),
      );
      await bridge.invoke('test', 'restart', {});
      final recovered = (await store('cold').read())!;
      expect(recovered.value, 'fake-installed');
      expect(recovered.version.generation, ticket.generation);
      expect(recovered.version.generation, isNot(migrated.version.generation));
      expect(secure.values[legacy], 'fake-installed');
    },
  );
  test(
    'cold migration backup repairs a missing copied slot without resurrecting deletion',
    () async {
      const legacy = 'wardpulse.cursor.plan.secret';
      secure.values[legacy] = 'fake-installed';
      final original = (await store('ui').read())!;
      secure.values.removeWhere(
        (key, _) => key.startsWith('wardpulse.connection.'),
      );
      await bridge.invoke('test', 'restart', {});
      final repaired = (await store('cold').read())!;
      expect(repaired.value, 'fake-installed');
      expect(repaired.version.generation, original.version.generation);
      expect(repaired.version.revision, isNot(original.version.revision));
      secure.failDeleteKey = legacy;
      await expectLater(store('cold').delete(), throwsStateError);
      expect(await store('new-engine').read(), isNull);
    },
  );
  test(
    'first cancelled login stays empty, while migration failures preserve legacy recovery',
    () async {
      final first = await store('ui').beginReconnect();
      await store('ui').cancelReconnect(first);
      expect(await store('cold').read(), isNull);
      await bridge.reset();
      secure.values['wardpulse.cursor.plan.secret'] = 'fake-installed';
      secure.failWrite = true;
      await expectLater(store('ui').read(), throwsStateError);
      secure.failWrite = false;
      await bridge.invoke('test', 'restart', {});
      expect((await store('cold').read())?.value, 'fake-installed');
    },
  );
  test(
    'failed barrier leaves secure values untouched; explicit retry recovers',
    () async {
      await store('ui').write('fake-current');
      final before = Map<String, String>.from(secure.values);
      final deleted = secure.deleted.length;
      await bridge.invoke('test', 'failCommit', {'value': true});
      await expectLater(store('ui').delete(), throwsStateError);
      expect(secure.values, before);
      expect(secure.deleted.length, deleted);
      await bridge.invoke('test', 'failCommit', {'value': false});
      await store('retry').write('fake-new');
      expect((await store('cold').read())?.value, 'fake-new');
    },
  );
  test(
    'failed legacy deletion is retried by a fresh store after tombstone',
    () async {
      const legacy = 'wardpulse.cursor.plan.secret';
      secure.values[legacy] = 'fake-installed';
      await store('ui').read();
      secure.failDeleteKey = legacy;
      await expectLater(store('ui').delete(), throwsStateError);
      expect(secure.values[legacy], 'fake-installed');
      secure.failDeleteKey = null;
      expect(await store('cold').read(), isNull);
      expect(secure.values[legacy], isNull);
    },
  );
  test(
    'secure write/delete ordering spans independent store instances',
    () async {
      await store('ui').write('fake-first');
      final entered = Completer<void>();
      final release = Completer<void>();
      secure.beforeWrite = (_) async {
        entered.complete();
        await release.future;
      };
      final replacement = store('ui').write('fake-replacement');
      await entered.future;
      final deletion = store('worker').delete();
      await Future<void>.delayed(Duration.zero);
      expect(secure.values.values, contains('fake-first'));
      release.complete();
      await replacement;
      await deletion;
      expect(await store('cold').read(), isNull);
      expect(secure.values.values, isNot(contains('fake-replacement')));
    },
  );
  test(
    'detached pending SDK write cannot clobber new reconnect and cleans after restart',
    () async {
      await store('ui').write('fake-first');
      final entered = Completer<void>();
      final release = Completer<void>();
      secure.beforeWrite = (_) async {
        entered.complete();
        await release.future;
      };
      final delayed = store('ui').write('fake-late');
      final failed = expectLater(delayed, throwsStateError);
      await entered.future;
      await bridge.invoke('ui', 'detach', {});
      secure.beforeWrite = null;
      await store('new').write('fake-current');
      release.complete();
      await failed;
      expect((await store('cold').read())?.value, 'fake-current');
      expect(secure.values.values, contains('fake-late'));
      await bridge.invoke('test', 'restart', {});
      expect((await store('cold2').read())?.value, 'fake-current');
      expect(secure.values.values, isNot(contains('fake-late')));
    },
  );
  test(
    'Claude pasted-token cleanup retries durably without rotating OAuth',
    () async {
      final account = SecureClaudeAccountStore(
        storage: secure,
        platform: bridge.platform('oauth'),
      );
      await account.write(
        ClaudeAccountSession(
          accessToken: 'fake-OAuth',
          refreshToken: 'fake-refresh',
          expiresAt: now.add(const Duration(hours: 1)),
          accountId: 'fake-account',
        ),
      );
      final before = (await account.readVersioned())!.version;
      const paste = 'wardpulse.anthropic.plan.secret';
      secure.values[paste] = 'fake-old-paste';
      secure.failDeleteKey = paste;
      final pasted = SecureProviderCredentialStore(
        storage: secure,
        platform: bridge.platform('paste'),
      );
      await expectLater(
        pasted.deleteLegacySecret(ProviderConnections.claudePlan),
        throwsStateError,
      );
      secure.failDeleteKey = null;
      final after =
          await SecureClaudeAccountStore(
            storage: secure,
            platform: bridge.platform('cold'),
          ).readVersioned();
      expect(after?.value.accessToken, 'fake-OAuth');
      expect(after?.version.values, before.values);
      expect(secure.values[paste], isNull);
    },
  );
  test(
    'OAuth refresh retires the migration backup for the old credential revision',
    () async {
      const legacy = 'wardpulse.claude.account-session';
      final old = ClaudeAccountSession(
        accessToken: 'fake-old',
        refreshToken: 'fake-old-refresh',
        expiresAt: now.add(const Duration(hours: 1)),
        accountId: 'fake-account',
      );
      secure.values[legacy] = jsonEncode(old.toJson());
      final account = SecureClaudeAccountStore(
        storage: secure,
        platform: bridge.platform('oauth'),
      );
      final migrated = (await account.readVersioned())!;
      final changed = await account.refresh(
        ClaudeAccountSession(
          accessToken: 'fake-new',
          refreshToken: 'fake-new-refresh',
          expiresAt: now.add(const Duration(hours: 2)),
          accountId: 'fake-account',
        ),
        migrated.version,
      );
      expect(changed?.generation, migrated.version.generation);
      expect(changed?.revision, isNot(migrated.version.revision));
      secure.failDeleteKey = legacy;
      secure.values.removeWhere(
        (key, _) => key.startsWith('wardpulse.connection.'),
      );
      expect(
        await SecureClaudeAccountStore(
          storage: secure,
          platform: bridge.platform('cold'),
        ).readVersioned(),
        isNull,
      );
      expect(secure.values[legacy], isNotNull);
    },
  );
  test(
    'real secure account operations carry scoped fetch proof; user delete does not',
    () async {
      final platform = _RecordingPlatform(bridge.platform('oauth'));
      final account = SecureClaudeAccountStore(
        storage: secure,
        platform: platform,
      );
      final initial = ClaudeAccountSession(
        accessToken: 'fake-old',
        refreshToken: 'fake-refresh',
        expiresAt: now.add(const Duration(hours: 1)),
        accountId: 'fake-account',
      );
      await account.write(initial);
      final refreshed = Completer<void>();
      final release = Completer<void>();
      final fetch = account.serializeFetch(() async {
        final old = (await account.readVersioned())!;
        await account.refresh(initial, old.version);
        refreshed.complete();
        await release.future;
      });
      final failed = expectLater(fetch, throwsStateError);
      await refreshed.future;
      final refreshArgs =
          platform.calls
              .lastWhere(
                (call) =>
                    call.method == 'acquire' &&
                    call.arguments['action'] == 'refresh',
              )
              .arguments;
      expect(refreshArgs['fetchTicket'], isA<String>());
      await account.delete();
      final deleteArgs =
          platform.calls
              .lastWhere(
                (call) =>
                    call.method == 'acquire' &&
                    call.arguments['action'] == 'delete',
              )
              .arguments;
      expect(deleteArgs.containsKey('fetchTicket'), isFalse);
      // A detached owner invalidates even an otherwise completed network scope.
      await bridge.invoke('oauth', 'detach', {});
      release.complete();
      await failed;
    },
  );

  test(
    'Claude expired refresh failure cannot delete a newer explicit login',
    () async {
      final entered = Completer<void>();
      final release = Completer<_Response>();
      var tokenRequests = 0;
      var usageRequests = 0;
      String? tokenBody;
      final a = _runtime('claude', secure, bridge.platform('A'), now, (
        uri,
        headers,
        body,
      ) async {
        if (!entered.isCompleted) entered.complete();
        if (uri.path.endsWith('/token')) {
          tokenRequests++;
          tokenBody = body;
          return release.future;
        }
        usageRequests++;
        return _usageResponse(uri);
      });
      await a.write('fake-old-account', 'old', expired: true);
      final loading = a.fetch();
      final failed = expectLater(
        loading,
        throwsA(
          isA<ClaudeAccountException>()
              .having(
                (error) => error.failure,
                'failure',
                ClaudeAccountFailure.cancelled,
              )
              .having((error) => error.details, 'details', isNull),
        ),
      );
      await entered.future;
      final b = _runtime('claude', secure, bridge.platform('B'), now, (
        uri,
        headers,
        body,
      ) async {
        fail('Unexpected request from the newer login');
      });
      late final CredentialVersion newerVersion;
      try {
        await b.write('fake-new-account', 'new');
        newerVersion = (await b.read())!.version;
      } finally {
        release.complete((status: 400, body: '{"error":"invalid_grant"}'));
        await failed;
      }

      expect(
        await NativeConnectionRejectionNoticeStore(
          platform: bridge.platform('notices'),
        ).read(),
        isEmpty,
      );
      expect(tokenRequests, 1);
      expect(usageRequests, 0);
      expect(Uri.splitQueryString(tokenBody!)['grant_type'], 'refresh_token');
      final retained = (await b.read())!;
      expect(retained.value, 'new');
      expect(retained.version.values, newerVersion.values);
    },
  );

  for (final family in ['claude', 'codex']) {
    _Runtime runtime(String owner, _ResponseHandler handler) =>
        _runtime(family, secure, bridge.platform(owner), now, handler);
    test(
      '$family manual first failure survives later cache adoption and automatic denial',
      () async {
        final id = family == 'codex' ? 'openai.plan' : 'anthropic.plan';
        var limited = true, requests = 0;
        Future<_Response> response(
          Uri uri,
          Map<String, String> headers,
          String? body,
        ) async {
          requests++;
          return limited ? (status: 429, body: '{}') : _usageResponse(uri);
        }

        final manual = runtime('manual', response);
        await manual.write('synthetic-account', 'synthetic-token');
        final version = (await manual.read())!.version;
        final empty = DashboardSnapshot.empty(generatedAt: now);
        final normalized = DashboardSnapshot.fromJson({
          ...empty.toJson(),
          'accounts': [
            {
              'accountId': 'synthetic-account',
              'provider': family,
              'connection': id,
              'status': 'ok',
              'today': empty.todayTotal.toJson(),
              'week': empty.weekTotal.toJson(),
              'month': empty.monthTotal.toJson(),
              'credits': <Object>[],
              'allowances': <Object>[],
              'buckets': <Object>[],
              'modelBreakdown': <Object>[],
              'lastSuccessfulSyncAt': now.toIso8601String(),
            },
          ],
        });
        ConnectionSnapshotCache cache(String owner) => ConnectionSnapshotCache(
          connection: id,
          platform: bridge.platform(owner),
          readCredentialVersion:
              () async => (await runtime(owner, response).read())?.version,
        );
        DashboardRepository repository(String owner, _Runtime session) =>
            family == 'codex'
                ? codexDashboardRepository(
                  accountService: const EmptyCodexAccountService(),
                  fallback: const NoProvidersDashboardRepository(),
                  cache: cache(owner),
                  loadReport: session.fetch,
                  normalizeReport: (_) => normalized.toJsonString(),
                  logger: const NullProviderSyncLogger(),
                )
                : claudeDashboardRepository(
                  accountService: const EmptyClaudeAccountService(),
                  fallback: const NoProvidersDashboardRepository(),
                  cache: cache(owner),
                  loadReport: session.fetch,
                  normalizeReport: (_) => normalized.toJsonString(),
                  logger: const NullProviderSyncLogger(),
                );
        final foreground = repository('manual', manual);
        final failed = await CapturedDashboardLoad.capture(foreground.load);
        expect(
          () => failed.value,
          throwsA(
            isA<DashboardLoadException>().having(
              (error) => error.issue,
              'issue',
              DashboardSyncIssue.rateLimited,
            ),
          ),
        );
        expect(
          failed.reportingOutcomes.single.credentialVersion!.values,
          version.values,
        );
        expect((await cache('manual').capture()).snapshot, isNull);
        limited = false;
        AutomaticPollContext periodic() => AutomaticPollContext(
          readInterval: () async => const Duration(minutes: 5),
        );
        final worker = repository('headless', runtime('headless', response));
        await periodic().run(worker.load);
        final before = requests;
        final poll = periodic();
        final retained = await poll.run(foreground.load);
        expect(requests, before);
        expect(poll.whollySkipped, isTrue);
        expect(retained.syncIssue, DashboardSyncIssue.rateLimited);
        expect(retained.generatedAt, now);
        expect(retained.accounts.single.status, ProviderStatus.stale);
        expect(retained.accounts.single.lastSuccessfulSyncAt, now);
        expect(
          retained.reportingOutcomes.single.source,
          ReportingOutcomeSource.cache,
        );
        expect(
          retained.reportingOutcomes.single.credentialVersion!.values,
          version.values,
        );
      },
    );
    test(
      '$family recreated automatic clients skip before expired-token refresh; manual bypasses',
      () async {
        var calls = 0;
        Future<_Response> response(
          Uri uri,
          Map<String, String> headers,
          String? body,
        ) async {
          calls++;
          return _usageResponse(uri);
        }

        final foreground = runtime('foreground', response);
        await foreground.write('synthetic-account', 'synthetic-token');
        AutomaticPollContext periodic() => AutomaticPollContext(
          readInterval: () async => const Duration(minutes: 60),
        );
        await periodic().run(foreground.fetch);
        final before = calls;
        await bridge.invoke('test', 'setClock', {'value': 1000});
        final expired = _runtime(
          family,
          secure,
          bridge.platform('headless'),
          now.add(const Duration(days: 2)),
          response,
        );
        await expectLater(
          periodic().run(expired.fetch),
          throwsA(isA<AutomaticPollSkipped>()),
        );
        expect(calls, before);
        await foreground.fetch();
        expect(calls, greaterThan(before));
        await bridge.invoke('test', 'setClock', {'value': 300000});
        await AutomaticPollContext(
          origin: AutomaticPollOrigin.resetWake,
          readInterval: () async => const Duration(minutes: 60),
        ).run(foreground.fetch);
        final afterReset = calls;
        await bridge.invoke('test', 'setClock', {'value': 600000});
        await expectLater(
          periodic().run(foreground.fetch),
          throwsA(isA<AutomaticPollSkipped>()),
        );
        expect(calls, afterReset);
      },
    );
    test(
      '$family owned rejection persists after credential-null refresh and restart',
      () async {
        final a = runtime(
          'auth',
          (uri, headers, body) async => (status: 401, body: '{}'),
        );
        await a.write('synthetic-account', 'synthetic-token');
        await expectLater(a.fetch(), throwsA(anything));
        expect(await a.read(), isNull);
        final notices = NativeConnectionRejectionNoticeStore(
          platform: bridge.platform('notices'),
        );
        final event = (await notices.read()).single;
        expect(
          event.connection,
          family == 'claude'
              ? ProviderConnections.claudePlan
              : ProviderConnections.codexPlan,
        );
        expect(event.dismissed, isFalse);
        expect(await a.fetch(), isNull);
        await bridge.invoke('test', 'restart', {});
        final cold = runtime(
          'cold',
          (uri, headers, body) async => fail('No saved credential may fetch'),
        );
        expect(await cold.fetch(), isNull);
        expect((await notices.read()).single.eventId, event.eventId);
        await cold.write('synthetic-account', 'synthetic-token');
        final disconnected = runtime(
          'disconnect',
          (uri, headers, body) async => _usageResponse(uri),
        );
        await disconnected.disconnect();
        expect((await notices.read()).single.eventId, event.eventId);
      },
    );
    test(
      '$family permission failure retains credential without auth evidence',
      () async {
        final a = runtime(
          'permission',
          (uri, headers, body) async => (status: 403, body: '{}'),
        );
        await a.write('synthetic-account', 'synthetic-token');
        await expectLater(a.fetch(), throwsA(anything));
        expect(await a.read(), isNotNull);
        expect(
          await NativeConnectionRejectionNoticeStore(
            platform: bridge.platform('notices'),
          ).read(),
          isEmpty,
        );
      },
    );
    test(
      '$family cross-engine fetch exclusion rereads refreshed session',
      () async {
        final entered = Completer<void>();
        final release = Completer<_Response>();
        var bTokenRequests = 0;
        final a = runtime('A', (uri, headers, body) async {
          if (uri.path.endsWith('/token')) {
            entered.complete();
            return release.future;
          }
          return _usageResponse(uri);
        });
        await a.write('fake-account', 'old', expired: true);
        final before = (await a.read())!.version;
        final loadingA = a.fetch();
        await entered.future;
        final b = runtime('B', (uri, headers, body) async {
          if (uri.path.endsWith('/token')) {
            bTokenRequests++;
            return (status: 401, body: '{}');
          }
          expect(headers['Authorization'], contains('new'));
          return _usageResponse(uri);
        });
        final loadingB = b.fetch();
        await Future<void>.delayed(Duration.zero);
        expect(bTokenRequests, 0);
        release.complete((
          status: 200,
          body: jsonEncode({
            'access_token':
                family == 'codex'
                    ? _jwt(now.add(const Duration(days: 1)), 'new')
                    : 'new',
            'refresh_token': 'fake-new-refresh',
            'expires_in': 3600,
          }),
        ));
        expect(await loadingA, isNotNull);
        expect(await loadingB, isNotNull);
        expect(bTokenRequests, 0);
        final after = (await b.read())!;
        expect(after.version.generation, before.generation);
        expect(after.version.revision, isNot(before.revision));
      },
    );
    test(
      '$family stale auth failure cannot delete a newer explicit login',
      () async {
        final entered = Completer<void>();
        final release = Completer<_Response>();
        final a = runtime('A', (uri, headers, body) async {
          if (uri.path.endsWith('/token')) return (status: 401, body: '{}');
          if (uri.path.endsWith('/usage')) {
            entered.complete();
            return release.future;
          }
          return _usageResponse(uri);
        });
        await a.write('fake-old-account', 'old');
        final loading = a.fetch();
        final failed = expectLater(loading, throwsA(anything));
        await entered.future;
        final b = runtime(
          'B',
          (uri, headers, body) async => _usageResponse(uri),
        );
        await b.write('fake-new-account', 'new');
        release.complete((status: 401, body: '{}'));
        await failed;
        expect((await b.read())?.value, contains('new'));
      },
    );
    test(
      '$family disconnect commits before the held network returns',
      () async {
        final entered = Completer<void>();
        final release = Completer<_Response>();
        final a = runtime('A', (uri, headers, body) async {
          if (uri.path.endsWith('/usage')) {
            entered.complete();
            return release.future;
          }
          return _usageResponse(uri);
        });
        await a.write('fake-account', 'old');
        final loading = a.fetch();
        final failed = expectLater(loading, throwsA(anything));
        await entered.future;
        await a.disconnect();
        expect(await a.read(), isNull);
        release.complete(
          _usageResponse(Uri.parse('https://invalid.test/usage')),
        );
        await failed;
        expect(
          await runtime(
            'cold',
            (uri, headers, body) async => _usageResponse(uri),
          ).read(),
          isNull,
        );
      },
    );
  }
}

typedef _Response = ({int status, String body});
typedef _ResponseHandler =
    Future<_Response> Function(Uri, Map<String, String>, String?);

final class _Runtime {
  const _Runtime({
    required this.write,
    required this.read,
    required this.fetch,
    required this.disconnect,
  });
  final Future<void> Function(String account, String token, {bool expired})
  write;
  final Future<VersionedCredential<String>?> Function() read;
  final Future<String?> Function() fetch;
  final Future<void> Function() disconnect;
}

_Runtime _runtime(
  String family,
  FakeSecureStorage secure,
  ConnectionCachePlatform platform,
  DateTime now,
  _ResponseHandler handler,
) {
  if (family == 'claude') {
    final store = SecureClaudeAccountStore(storage: secure, platform: platform);
    final service = MobileClaudeAccountService(
      store: store,
      client: ClaudeAccountClient(
        transport: _ClaudeTransport(handler),
        clock: () => now,
      ),
    );
    return _Runtime(
      write:
          (account, token, {expired = false}) => store.write(
            ClaudeAccountSession(
              accessToken: token,
              refreshToken: 'fake-refresh',
              expiresAt: now.add(
                expired ? const Duration(minutes: 1) : const Duration(hours: 1),
              ),
              accountId: account,
            ),
          ),
      read: () async {
        final value = await store.readVersioned();
        return value == null
            ? null
            : VersionedCredential(value.value.accessToken, value.version);
      },
      fetch: service.fetchReport,
      disconnect: service.disconnect,
    );
  }
  final store = SecureCodexAccountStore(storage: secure, platform: platform);
  final service = MobileCodexAccountService(
    store: store,
    client: CodexAccountClient(
      transport: _CodexTransport(handler),
      clock: () => now,
    ),
  );
  return _Runtime(
    write:
        (account, token, {expired = false}) => store.write(
          CodexAccountSession(
            accessToken: _jwt(
              now.add(
                expired ? const Duration(days: -1) : const Duration(days: 1),
              ),
              token,
            ),
            refreshToken: 'fake-refresh',
            accountId: account,
            refreshedAt: now,
          ),
        ),
    read: () async {
      final value = await store.readVersioned();
      return value == null
          ? null
          : VersionedCredential(value.value.accessToken, value.version);
    },
    fetch: service.fetchReport,
    disconnect: service.disconnect,
  );
}

String _jwt(DateTime expires, String label) {
  String encode(Object json) =>
      base64UrlEncode(utf8.encode(jsonEncode(json))).replaceAll('=', '');
  return '${encode({'alg': 'none'})}.${encode({'exp': expires.millisecondsSinceEpoch ~/ 1000})}.$label';
}

_Response _usageResponse(Uri uri) => (
  status: 200,
  body: jsonEncode(
    uri.path.endsWith('/profiles/me')
        ? {
          'stats': {'daily_usage_buckets': <Object>[]},
        }
        : uri.path.contains('/wham/')
        ? {
          'rate_limit': null,
          'credits': {'has_credits': false, 'unlimited': false, 'balance': '0'},
        }
        : <String, Object?>{},
  ),
);

final class _ClaudeTransport implements ClaudeHttpTransport {
  const _ClaudeTransport(this.handler);
  final _ResponseHandler handler;
  @override
  Future<ClaudeHttpResponse> send(
    String method,
    Uri uri, {
    required Map<String, String> headers,
    String? body,
    Duration? timeout,
  }) async {
    final result = await handler(uri, headers, body);
    return ClaudeHttpResponse(statusCode: result.status, body: result.body);
  }
}

final class _CodexTransport implements CodexHttpTransport {
  const _CodexTransport(this.handler);
  final _ResponseHandler handler;
  @override
  Future<CodexHttpResponse> send(
    String method,
    Uri uri, {
    required Map<String, String> headers,
    String? body,
  }) async {
    final result = await handler(uri, headers, body);
    return CodexHttpResponse(statusCode: result.status, body: result.body);
  }
}

final class _RecordingPlatform implements ConnectionCachePlatform {
  _RecordingPlatform(this.delegate);
  final ConnectionCachePlatform delegate;
  final calls = <({String method, Map<String, Object?> arguments})>[];
  void Function(String, Map<String, Object?>)? onInvoke;
  @override
  Future<Object?> invoke(String method, Map<String, Object?> arguments) {
    calls.add((method: method, arguments: Map.of(arguments)));
    onInvoke?.call(method, arguments);
    return delegate.invoke(method, arguments);
  }
}
