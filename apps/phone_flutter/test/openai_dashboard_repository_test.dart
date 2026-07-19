import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ward_pulse_phone/dashboard/dashboard_models.dart';
import 'package:ward_pulse_phone/dashboard/dashboard_repository.dart';
import 'package:ward_pulse_phone/dashboard/openai_dashboard_repository.dart';
import 'package:ward_pulse_phone/providers/provider_credential_store.dart';
import 'package:ward_pulse_phone/sync/openai_reporting_client.dart';
import 'package:ward_pulse_phone/sync/provider_sync_logger.dart';

void main() {
  late DashboardSnapshot fallbackSnapshot;
  late String dashboardFixture;

  setUp(() {
    dashboardFixture =
        File(
          '../../fixtures/snapshots/dashboard_today.json',
        ).readAsStringSync();
    fallbackSnapshot = DashboardSnapshot.fromJsonString(dashboardFixture);
  });

  test('uses mock data when no OpenAI credential is stored', () async {
    final logger = _RecordingLogger();
    final repository = OpenAiDashboardRepository(
      credentialStore: _MemoryCredentialStore(),
      fallback: ValueDashboardRepository(fallbackSnapshot),
      logger: logger,
    );

    final snapshot = await repository.load();

    expect(snapshot, same(fallbackSnapshot));
    expect(logger.events, [ProviderSyncEvent.skippedNoCredential]);
  });

  test('passes sanitized reporting pages to the Rust boundary', () async {
    final usage =
        File(
          '../../fixtures/providers/openai/usage_completions.json',
        ).readAsStringSync();
    final costs =
        File('../../fixtures/providers/openai/costs.json').readAsStringSync();
    final transport = _FixtureTransport(usage: usage, costs: costs);
    final logger = _RecordingLogger();
    String? normalizedInput;
    final repository = OpenAiDashboardRepository(
      credentialStore: _MemoryCredentialStore('secret-admin-key'),
      client: OpenAiReportingClient(transport: transport),
      fallback: ValueDashboardRepository(fallbackSnapshot),
      logger: logger,
      clock: () => DateTime.utc(2026, 7, 19, 12),
      normalizeReport: (value) {
        normalizedInput = value;
        return dashboardFixture;
      },
    );

    await repository.load();

    final input = jsonDecode(normalizedInput!) as Map<String, dynamic>;
    expect(input['accountId'], 'openai-local');
    expect(input['todayStart'], 1784419200);
    expect(input['weekStart'], 1783900800);
    expect(input['monthStart'], 1782864000);
    expect(input['usagePages'], [usage]);
    expect(input['costPages'], [costs]);
    expect(normalizedInput, isNot(contains('secret-admin-key')));
    expect(logger.events, [ProviderSyncEvent.succeeded]);
  });

  test('does not replace a failed live sync with mock data', () async {
    final logger = _RecordingLogger();
    final repository = OpenAiDashboardRepository(
      credentialStore: _MemoryCredentialStore('secret-admin-key'),
      client: OpenAiReportingClient(
        transport: _FixtureTransport(usage: '{}', costs: '{}')..fail = true,
      ),
      fallback: ValueDashboardRepository(fallbackSnapshot),
      logger: logger,
    );

    await expectLater(
      repository.load(),
      throwsA(isA<DashboardLoadException>()),
    );
    expect(logger.events, [ProviderSyncEvent.authenticationRequired]);
  });

  test('keeps the last live snapshot when refresh fails', () async {
    final usage =
        File(
          '../../fixtures/providers/openai/usage_completions.json',
        ).readAsStringSync();
    final costs =
        File('../../fixtures/providers/openai/costs.json').readAsStringSync();
    final transport = _FixtureTransport(usage: usage, costs: costs);
    final logger = _RecordingLogger();
    final repository = OpenAiDashboardRepository(
      credentialStore: _MemoryCredentialStore('secret-admin-key'),
      client: OpenAiReportingClient(transport: transport),
      fallback: ValueDashboardRepository(fallbackSnapshot),
      logger: logger,
      normalizeReport: (_) => dashboardFixture,
    );

    final first = await repository.load();
    transport.fail = true;
    final second = await repository.load();

    expect(second, isNot(same(first)));
    expect(second.generatedAt, first.generatedAt);
    expect(second.overallStatus, ProviderStatus.stale);
    expect(
      second.accounts.map((account) => account.status),
      everyElement(ProviderStatus.stale),
    );
    expect(second.todayTotal, same(first.todayTotal));
    expect(second.watchSummary.status, ProviderStatus.stale);
    expect(logger.events, [
      ProviderSyncEvent.succeeded,
      ProviderSyncEvent.authenticationRequired,
      ProviderSyncEvent.usingCachedSnapshot,
    ]);
  });

  test(
    'fetches prior-month days when they belong to the current week',
    () async {
      final emptyPage = jsonEncode({
        'object': 'page',
        'data': <Object>[],
        'has_more': false,
        'next_page': null,
      });
      final transport = _FixtureTransport(usage: emptyPage, costs: emptyPage);
      final repository = OpenAiDashboardRepository(
        credentialStore: _MemoryCredentialStore('secret-admin-key'),
        client: OpenAiReportingClient(transport: transport),
        fallback: ValueDashboardRepository(fallbackSnapshot),
        logger: const NullProviderSyncLogger(),
        clock: () => DateTime.utc(2026, 8, 1, 12),
        normalizeReport: (_) => dashboardFixture,
      );

      await repository.load();

      final expected = DateTime.utc(2026, 7, 27).millisecondsSinceEpoch ~/ 1000;
      expect(
        transport.uris.map((uri) => uri.queryParameters['start_time']),
        everyElement('$expected'),
      );
    },
  );
}

final class _MemoryCredentialStore implements ProviderCredentialStore {
  _MemoryCredentialStore([this.value]);

  String? value;

  @override
  Future<String?> readOpenAiAdminKey() async => value;

  @override
  Future<void> writeOpenAiAdminKey(String value) async {
    this.value = value;
  }

  @override
  Future<void> deleteOpenAiAdminKey() async {
    value = null;
  }
}

final class _FixtureTransport implements ProviderHttpTransport {
  _FixtureTransport({required this.usage, required this.costs});

  final String usage;
  final String costs;
  final uris = <Uri>[];
  bool fail = false;

  @override
  Future<ProviderHttpResponse> get(
    Uri uri, {
    required Map<String, String> headers,
  }) async {
    uris.add(uri);
    if (fail) {
      return const ProviderHttpResponse(
        statusCode: HttpStatus.unauthorized,
        headers: {},
        body: '{}',
      );
    }

    return ProviderHttpResponse(
      statusCode: HttpStatus.ok,
      headers: const {},
      body: uri.path.endsWith('/costs') ? costs : usage,
    );
  }
}

final class _RecordingLogger implements ProviderSyncLogger {
  final events = <ProviderSyncEvent>[];

  @override
  void record(ProviderSyncEvent event) {
    events.add(event);
  }
}
