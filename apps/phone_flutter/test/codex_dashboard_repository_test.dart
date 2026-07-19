import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ward_pulse_phone/dashboard/codex_dashboard_repository.dart';
import 'package:ward_pulse_phone/dashboard/dashboard_models.dart';
import 'package:ward_pulse_phone/dashboard/dashboard_repository.dart';
import 'package:ward_pulse_phone/providers/codex_account_service.dart';
import 'package:ward_pulse_phone/sync/codex_account_client.dart';

void main() {
  final snapshot = DashboardSnapshot.fromJsonString(
    File('../../fixtures/snapshots/dashboard_today.json').readAsStringSync(),
  );

  test('uses the platform fallback without a Codex account', () async {
    final repository = CodexDashboardRepository(
      accountService: const EmptyCodexAccountService(),
      fallback: ValueDashboardRepository(snapshot),
      loadReport: () async => null,
      normalizeReport: (_) => throw StateError('must not normalize'),
    );

    expect(await repository.load(), same(snapshot));
  });

  test('handles an early fallback failure while Codex loads', () async {
    final report = Completer<String?>();
    const failure = DashboardLoadException(
      details: 'Platform reporting failed',
    );
    final repository = CodexDashboardRepository(
      accountService: const EmptyCodexAccountService(),
      fallback: const _FailingDashboardRepository(failure),
      loadReport: () => report.future,
    );

    final load = repository.load();
    await Future<void>.delayed(Duration.zero);
    report.complete(null);

    await expectLater(load, throwsA(same(failure)));
  });

  test('normalizes an on-device Codex report', () async {
    String? receivedReport;
    final repository = CodexDashboardRepository(
      accountService: const EmptyCodexAccountService(),
      fallback: ValueDashboardRepository(snapshot),
      loadReport: () async => '{"sanitized":true}',
      normalizeReport: (value) {
        receivedReport = value;
        return File(
          '../../fixtures/snapshots/dashboard_today.json',
        ).readAsStringSync();
      },
    );

    expect((await repository.load()).primaryAccount?.provider, 'mock');
    expect(receivedReport, '{"sanitized":true}');
  });

  test('surfaces Codex authentication failures', () async {
    final repository = CodexDashboardRepository(
      accountService: const EmptyCodexAccountService(),
      fallback: ValueDashboardRepository(snapshot),
      loadReport:
          () =>
              throw const CodexAccountException(
                CodexAccountFailure.authentication,
              ),
      normalizeReport: (_) => throw StateError('must not normalize'),
    );

    await expectLater(
      repository.load(),
      throwsA(
        isA<DashboardLoadException>().having(
          (error) => error.issue,
          'issue',
          DashboardSyncIssue.codexAuthentication,
        ),
      ),
    );
  });

  test('merges Codex and OpenAI Platform accounts', () async {
    final platformJson = snapshot.toJson();
    final platformAccount = (platformJson['accounts'] as List).first;
    platformAccount['provider'] = 'openai';
    (platformAccount['buckets'] as List).first
      ..['project'] = 'project-1'
      ..['user'] = 'user-1';
    platformAccount['lastError'] = {
      'code': 'stale_data',
      'message': 'Previous data retained',
    };
    final platformSnapshot = DashboardSnapshot.fromJson(platformJson);
    final codexJson = snapshot.toJson();
    (codexJson['accounts'] as List).first['provider'] = 'codex';
    final repository = CodexDashboardRepository(
      accountService: const EmptyCodexAccountService(),
      fallback: ValueDashboardRepository(platformSnapshot),
      loadReport: () async => '{"sanitized":true}',
      normalizeReport: (_) => jsonEncode(codexJson),
      mergeSnapshots: (values) {
        final decoded =
            values
                .map((value) => jsonDecode(value) as Map<String, dynamic>)
                .toList();
        final merged = Map<String, dynamic>.from(decoded.first);
        merged['accounts'] = [
          ...(decoded.first['accounts'] as List),
          ...(decoded.last['accounts'] as List),
        ];
        return jsonEncode(merged);
      },
    );

    final result = await repository.load();

    expect(result.accounts.map((account) => account.provider), [
      'openai',
      'codex',
    ]);
    expect(result.accounts.first.buckets.first.project, 'project-1');
    expect(result.accounts.first.buckets.first.user, 'user-1');
    expect(result.accounts.first.lastError?.code, 'stale_data');
    expect(result.accounts.first.lastError?.message, 'Previous data retained');
  });

  test('keeps a live platform snapshot when Codex is forbidden', () async {
    final platformJson = snapshot.toJson();
    (platformJson['accounts'] as List).first['provider'] = 'openai';
    final repository = CodexDashboardRepository(
      accountService: const EmptyCodexAccountService(),
      fallback: ValueDashboardRepository(
        DashboardSnapshot.fromJson(platformJson),
      ),
      loadReport:
          () =>
              throw const CodexAccountException(
                CodexAccountFailure.permissionDenied,
                'Codex limits · HTTP 403',
              ),
    );

    final result = await repository.load();

    expect(result.primaryAccount?.provider, 'openai');
    expect(result.syncIssue, DashboardSyncIssue.codexPermissionDenied);
  });
}

final class _FailingDashboardRepository extends DashboardRepository {
  const _FailingDashboardRepository(this.error);

  final Object error;

  @override
  Future<DashboardSnapshot> load() => Future.error(error);
}
