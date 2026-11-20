import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ward_pulse_phone/dashboard/apply_alert_settings.dart';
import 'package:ward_pulse_phone/dashboard/dashboard_models.dart';
import 'package:ward_pulse_phone/providers/connection_lifecycle.dart';
import 'package:ward_pulse_phone/providers/provider_connection.dart';
import 'package:ward_pulse_phone/settings/alert_threshold_preferences.dart';
import 'package:ward_pulse_phone/sync/watch_sync_service.dart';
import 'package:ward_pulse_phone/settings/watch_ring_preferences.dart';
import 'package:ward_pulse_phone/sync/manual_refresh_window.dart';
import 'package:ward_pulse_phone/sync/provider_sync_once.dart';
import 'package:ward_pulse_phone/widget/phone_widget_payload.dart';
import 'package:ward_pulse_phone/widget/phone_widget_preferences.dart';

import 'selected_data_freshness_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final (label, settings) in [
    (
      'Plan threshold',
      const AlertThresholdPreferences(
        connections: {
          'openai.plan': ConnectionAlertThresholds(
            plan: AlertPercentThreshold(at: 80),
          ),
        },
      ),
    ),
    (
      'bare Today budget',
      const AlertThresholdPreferences(
        connections: {
          'openai.platform': ConnectionAlertThresholds(
            budget: ConnectionBudget(today: 2500),
          ),
        },
      ),
    ),
  ]) {
    test('configured empty settings preserve health: $label', () async {
      final published = _captureWatchPublications();
      final source = DashboardSnapshot.empty(
        generatedAt: DateTime.utc(2026, 11, 6, 12),
      );
      // No injected transform: the default effect loads the production FFI.
      final applied = applyUserAlertSettings(source, settings);
      final disabled = applyUserAlertSettings(
        source,
        const AlertThresholdPreferences(),
      );
      const service = MethodChannelWatchSyncService();
      const selection = WatchRingPreferences();
      await service.sync(applied, selection);
      await service.sync(disabled, selection);
      final emitted = jsonDecode(published.first.arguments as String);
      final disabledEmission = jsonDecode(published.last.arguments as String);
      // Synthetic inputs and actual outputs are collected before the joint
      // assertion so OLD's Unknown result remains a semantic replay witness.
      print(
        jsonEncode({
          'case': label,
          'input': source.toJson(),
          'settings': settings.toJson(),
          'result': applied.toJson(),
          'emitted': emitted,
          'disabledResult': disabled.toJson(),
          'disabledEmission': disabledEmission,
        }),
      );
      expect(published.map((call) => call.method), [
        'syncWatchSummary',
        'syncWatchSummary',
      ]);
      expect(
        [
          applied.overallStatus.name,
          applied.watchSummary.status.name,
          emitted['overallStatus'],
        ],
        ['ok', 'ok', 'ok'],
      );
      expect(settings.hasEnabledRules, isTrue);
      expect(applied.toJson(), source.toJson());
      expect(applied.generatedAt, source.generatedAt);
      expect(applied.accounts, isEmpty);
      expect(applied.alertConditions, isEmpty);
      expect(applied.alerts, isEmpty);
      expect(applied.watchSummary.todayUsedPercent, isNull);
      expect(applied.watchSummary.weekUsedPercent, isNull);
      for (final budget in [
        applied.todayTotal,
        applied.weekTotal,
        applied.monthTotal,
      ]) {
        expect(
          budget.toJson(),
          BudgetState.unknownPeriod(budget.period).toJson(),
        );
      }
      for (final payload in [emitted, disabledEmission]) {
        expect(payload['overallStatus'], 'ok');
        expect(payload['generatedAt'], source.generatedAt.toIso8601String());
        for (final key in ['providers', 'allowances', 'rings', 'alerts']) {
          expect(payload[key], isEmpty, reason: key);
        }
        expect(payload['creditsGlance'], isNull);
        expect(payload['today'], source.todayTotal.toJson());
        expect(payload['week'], source.weekTotal.toJson());
        expect(payload['isStale'], isFalse);
      }
      expect(disabled, same(source));
    });
  }

  test('nonhealthy empty native result retains phone-only metadata', () async {
    final published = _captureWatchPublications();
    final version = CredentialVersion({
      'generation': 'g1',
      'revision': 'r1',
      'epoch': 'e1',
      'identity': 'digest1',
    });
    final outcome = ConnectionReportingOutcome(
      connection: ProviderConnections.openAiPlatform,
      category: ReportingOutcomeCategory.authenticationRejected,
      source: ReportingOutcomeSource.live,
      credentialVersion: version,
    );
    final source = DashboardSnapshot.empty(
          generatedAt: DateTime.utc(2026, 11, 6, 12),
        )
        .withStaleStatus(
          syncIssue: DashboardSyncIssue.authentication,
          syncDetails: 'sanitized reporting rejection',
          syncRejection: (connection: 'openai.platform', eventId: 'event-1'),
        )
        .withConnectionVersions({'openai.platform': version.values})
        .withReportingOutcomes([outcome]);
    final applied = applyUserAlertSettings(
      source,
      const AlertThresholdPreferences(
        connections: {
          'openai.platform': ConnectionAlertThresholds(
            budget: ConnectionBudget(today: 2500),
          ),
        },
      ),
    );
    await const MethodChannelWatchSyncService().sync(
      applied,
      const WatchRingPreferences(),
    );
    final emitted = jsonDecode(published.single.arguments as String);
    expect(published.single.method, 'syncWatchSummary');
    expect(applied.toJson(), source.toJson());
    expect(applied.overallStatus, ProviderStatus.stale);
    expect(applied.watchSummary.status, ProviderStatus.stale);
    expect(applied.syncIssue, source.syncIssue);
    expect(applied.syncDetails, source.syncDetails);
    expect(applied.syncRejection, source.syncRejection);
    expect(applied.connectionVersions, source.connectionVersions);
    expect(applied.reportingOutcomes, [outcome]);
    expect(applied.reportingOutcomes.single.credentialVersion, same(version));
    expect(emitted['overallStatus'], 'stale');
    expect(emitted['isStale'], isTrue);
    expect(emitted['generatedAt'], source.generatedAt.toIso8601String());
    for (final key in ['providers', 'allowances', 'rings', 'alerts']) {
      expect(emitted[key], isEmpty, reason: key);
    }
    expect(emitted['creditsGlance'], isNull);
  });

  test('retained selection stays stale through mixed warning refreshes', () {
    final codex = freshnessAccount(
      'codex',
      'openai.plan',
      allowances: [
        freshnessAllowance('codex-primary'),
        freshnessAllowance('credits', purchased: true, remaining: '320'),
      ],
    );
    final success = freshnessSnapshot([codex], overall: ProviderStatus.ok);
    final retained = success.withStaleStatus().accounts.single;
    final warning = freshnessAccount(
      'claude',
      'anthropic.platform',
      status: ProviderStatus.warning,
    );
    const watchChoice = WatchRingPreferences(selectedIds: [codexPlanRingId]);
    const widgetChoice = PhoneWidgetPreferences(
      selectedIds: ['allowance.codex.codex-primary'],
    );
    // Production merge_dashboard_snapshots_json takes the newest time and
    // ProviderStatus::worst ranks Warning above Stale. Exercise that boundary
    // directly; the repository test merger instead forces aggregate Stale.
    for (final minute in [10, 20]) {
      final updatedAt = freshnessSuccessAt.add(Duration(minutes: minute));
      final freshWarning = freshnessAccount(
        'claude',
        'anthropic.platform',
        status: ProviderStatus.warning,
        at: updatedAt,
      );
      final mixed = freshnessSnapshot([retained, freshWarning], at: updatedAt);
      expect(mixed.overallStatus, ProviderStatus.warning);
      expect(
        mixed.generatedAt,
        freshnessSuccessAt.add(Duration(minutes: minute)),
      );
      expect(retained.toJson(), {...codex.toJson(), 'status': 'stale'});
      expect(retained.accountId, 'openai.plan-account');
      expect(retained.connection, 'openai.plan');
      expect(retained.lastSuccessfulSyncAt, freshnessSuccessAt);
      expect(retained.allowances.first.status, ProviderStatus.ok);
      expect(retained.month.status, ProviderStatus.ok);
      expect(retained.month.spent!.minorUnits, 2500);
      final watch = _freshnessWatch(mixed, watchChoice);
      expect(watch['overallStatus'], 'warning');
      expect(watch['generatedAt'], mixed.generatedAt.toIso8601String());
      final ring = (watch['rings'] as List).single;
      expect(ring['id'], codexPlanRingId);
      expect(ring['usedPercent'], 40);
      expect(ring['status'], 'ok');
      expect(watch['isStale'], isTrue);
      final widget = buildPhoneWidgetPayload(mixed, widgetChoice);
      expect(widget.rows.single.remainingPercent, 60);
      expect(widget.rows.single.creditsSuffix, '320 credits');
      expect(widget.stale, isTrue);
    }
    final recoveredAt = freshnessSuccessAt.add(const Duration(minutes: 30));
    final refreshed = ProviderSnapshot.fromJson({
      ...codex.toJson(),
      'lastSuccessfulSyncAt': recoveredAt.toIso8601String(),
    });
    final recovered = freshnessSnapshot([refreshed, warning], at: recoveredAt);
    expect(recovered.accounts.first.lastSuccessfulSyncAt, recoveredAt);
    expect(_freshnessWatch(recovered, watchChoice)['isStale'], isFalse);
    expect(buildPhoneWidgetPayload(recovered, widgetChoice).stale, isFalse);
  });

  test('Watch credits follow the first displayed balance, not the sum', () {
    final plan = freshnessAccount(
      'claude',
      'anthropic.plan',
      allowances: [
        freshnessAllowance('claude-five-hour'),
        freshnessAllowance('first', purchased: true, remaining: '5'),
      ],
    );
    final later = freshnessAccount(
      'claude',
      'anthropic.platform',
      status: ProviderStatus.stale,
      allowances: [
        freshnessAllowance('later', purchased: true, remaining: '7'),
      ],
    );
    const choice = WatchRingPreferences(selectedIds: [claudePlanRingId]);
    final mixed = freshnessSnapshot([
      plan,
      later,
    ], overall: ProviderStatus.stale);
    final watch = _freshnessWatch(mixed, choice);
    expect(watch['creditsGlance']['text'], '12');
    expect(
      watch['isStale'],
      isFalse,
    ); // Standalone total is hidden by the ring.
    final zero = freshnessAccount(
      'claude',
      'anthropic.platform',
      allowances: [
        freshnessAllowance(
          'zero',
          purchased: true,
          remaining: '0',
          status: ProviderStatus.stale,
        ),
      ],
    );
    expect(
      _freshnessWatch(freshnessSnapshot([zero, plan]), choice)['isStale'],
      isTrue,
    );
  });

  test('standalone Watch credits count only displayed contributors', () {
    final credits = freshnessAccount(
      'codex',
      'openai.plan',
      allowances: [
        freshnessAllowance('credits', purchased: true, remaining: '5'),
      ],
    );
    final tokens = freshnessAccount(
      'claude',
      'anthropic.plan',
      status: ProviderStatus.stale,
      allowances: [
        freshnessAllowance(
          'tokens',
          purchased: true,
          remaining: '9',
          unit: 'tokens',
        ),
      ],
    );
    const unavailable = WatchRingPreferences(selectedIds: [codexPlanRingId]);
    final mixed = freshnessSnapshot([
      credits,
      tokens,
    ], overall: ProviderStatus.stale);
    final watch = _freshnessWatch(mixed, unavailable);
    expect(watch['rings'], isEmpty);
    expect(watch['creditsGlance']['text'], '5');
    expect(watch['isStale'], isFalse);
    final unlimited = freshnessAccount(
      'claude',
      'anthropic.plan',
      allowances: [
        freshnessAllowance('unlimited', purchased: true, unlimited: true),
      ],
    );
    final overridden = _freshnessWatch(
      freshnessSnapshot([tokens, unlimited], overall: ProviderStatus.stale),
      unavailable,
    );
    expect(overridden['creditsGlance']['text'], '∞');
    expect(overridden['isStale'], isFalse);
    final retained =
        freshnessSnapshot([credits]).withStaleStatus().accounts.single;
    expect(
      _freshnessWatch(freshnessSnapshot([retained]), unavailable)['isStale'],
      isTrue,
    );
    final empty = _freshnessWatch(
      mixed,
      const WatchRingPreferences(selectedIds: []),
    );
    expect(empty['creditsGlance'], isNull);
    expect(empty['isStale'], isTrue); // No contributors: aggregate fallback.
  });

  for (final (claudeUsed, fableUsed) in <(double?, double?)>[
    (40, 90),
    (100, 0),
    (100, 100),
    (null, 90),
    (40, null),
  ]) {
    test(
      'Claude/Fable payload preserves fixed halves at $claudeUsed/$fableUsed',
      () {
        final dashboard = _pairedDashboard(
          claudeUsed: claudeUsed,
          fableUsed: fableUsed,
        );
        final payload =
            jsonDecode(
                  WatchDashboardSummaryPayload.fromSnapshot(
                    dashboard,
                    const WatchRingPreferences(
                      selectedIds: [claudeFableRingId, claudePlanRingId],
                    ),
                  ).encode(),
                )
                as Map<String, dynamic>;
        expect(payload['schemaVersion'], 9);
        final band = (payload['rings'] as List).single;
        if (claudeUsed != null && fableUsed != null) {
          expect(band['id'], claudePlanRingId);
          expect(band['label'], '5h');
          expect(band['usedPercent'], claudeUsed);
          expect(band['split']['id'], claudeFableRingId);
          expect(band['split']['label'], 'Fable weekly');
          expect(band['split']['usedPercent'], fableUsed);
        } else {
          expect(
            band['id'],
            claudeUsed == null ? claudeFableRingId : claudePlanRingId,
          );
          expect(band['usedPercent'], claudeUsed ?? fableUsed);
          expect(band['split'], isNull);
        }
        expect(payload.containsKey('selectedRingDataUnavailable'), isFalse);
        final allowances = payload['allowances'] as List;
        expect(
          allowances.firstWhere(
            (a) => a['label'] == 'Claude · Fable weekly',
          )['resetsAt'],
          '2026-11-08T08:00:00.000Z',
        );
        expect(
          allowances.firstWhere((a) => a['label'] == 'Claude · 5h')['resetsAt'],
          '2026-11-01T12:00:00.000Z',
        );
      },
    );
  }

  test(
    'invalid publication retains the last summary while local sync continues',
    () async {
      final published = <String>[];
      const channel = MethodChannel('app.wardpulse/watch_sync');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, (call) async {
        expect(call.method, 'syncWatchSummary');
        published.add(call.arguments as String);
        return null;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      final dashboard = _pairedDashboard(fableUsed: null);
      const valid = WatchRingPreferences(
        selectedIds: [claudePlanRingId, claudeFableRingId],
      );
      const invalid = WatchRingPreferences(
        selectedIds: [
          claudePlanRingId,
          claudeFableRingId,
          codexPlanRingId,
          codexSparkRingId,
          cursorOwnPoolId,
          cursorOtherPoolId,
        ],
      );
      const service = MethodChannelWatchSyncService();
      await service.sync(dashboard, valid);
      final lastSummary = published.single;
      // The unknown Fable half must not hide the invalid third saved pair.
      expect(
        () => WatchDashboardSummaryPayload.fromSnapshot(dashboard, invalid),
        throwsStateError,
      );
      expect(
        () => WatchDashboardSummaryPayload.fromSnapshot(
          dashboard,
          const WatchRingPreferences(
            selectedIds: ['missing-1', 'missing-2', 'missing-3', 'missing-4'],
          ),
        ),
        throwsStateError,
      );
      final localUpdates = <String>[];
      await providerSyncOnce(
        load:
            (_) async => ProviderSyncWork(
              syncWatch: () => service.sync(dashboard, invalid),
              syncWidget: () async {
                localUpdates.add('widget');
              },
              syncRecoveries: () async {
                localUpdates.add('recovery');
              },
            ),
        logFailure:
            (step, error, stack) => fail('Unexpected $step failure: $error'),
      );
      expect(published, [lastSummary]);
      expect(localUpdates, ['widget', 'recovery']);
      await service.sync(dashboard, valid);
      expect(published, hasLength(2));
      await service.sync(
        dashboard,
        const WatchRingPreferences(selectedIds: []),
      );
      expect(published, hasLength(3));
      expect(jsonDecode(published.last)['rings'], isEmpty);
    },
  );

  test('stored all-off clears credits and matches the preview', () async {
    final published = <Map<String, dynamic>>[];
    const channel = MethodChannel('app.wardpulse/watch_sync');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'syncWatchSummary');
      published.add(
        jsonDecode(call.arguments as String) as Map<String, dynamic>,
      );
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    final json =
        jsonDecode(
              File(
                '../../fixtures/snapshots/dashboard_today.json',
              ).readAsStringSync(),
            )
            as Map<String, dynamic>;
    final account = (json['accounts'] as List).first as Map<String, dynamic>;
    account['provider'] = 'claude';
    account['connection'] = 'anthropic.plan';
    for (final period in ['today', 'week', 'month']) {
      account[period] = BudgetState.unknownPeriod(period).toJson();
    }
    account['allowances'] = [
      _cursorPool('claude-five-hour', '5h', 100),
      {
        ..._cursorPool('purchased', 'Purchased credits', 0),
        'source': 'purchased',
        'usedPercent': null,
        'remaining': {'value': '1200', 'unit': 'credits'},
      },
    ];
    final dashboard = DashboardSnapshot.fromJson(json);
    final selected = watchRingPreferencesFromStoredIds([claudePlanRingId]);
    const credits = {
      'text': '1.2K',
      'label': 'Credits left',
      'provider': 'claude',
    };
    const service = MethodChannelWatchSyncService();

    expect(
      watchRingPayloadSubtitle(dashboard, selected),
      'Claude plan 0% left',
    );
    await service.sync(dashboard, selected);
    final populated = published.single;
    expect((populated['rings'] as List).single['usedPercent'], 100);
    expect(populated['creditsGlance'], credits);

    final allOff = watchRingPreferencesFromStoredIds([]);
    expect(allOff.selectedIds, isEmpty);
    expect(watchRingPayloadSubtitle(dashboard, allOff), 'No rings selected');
    await service.sync(dashboard, allOff);
    expect(published, hasLength(2));
    final cleared = published.last;
    expect(cleared['schemaVersion'], 9);
    expect(cleared['rings'], isEmpty);
    expect(cleared.containsKey('creditsGlance'), isTrue);
    expect(cleared['creditsGlance'], isNull);
    expect(cleared['allowances'], populated['allowances']);

    await service.sync(dashboard, selected);
    expect(published, hasLength(3));
    expect(published.last['rings'], populated['rings']);
    expect(published.last['creditsGlance'], credits);

    (account['allowances'] as List).first['usedPercent'] = null;
    final unknown = DashboardSnapshot.fromJson(json);
    await service.sync(unknown, const WatchRingPreferences());
    expect(published, hasLength(4));
    expect(published.last['rings'], isEmpty);
    expect(published.last.containsKey('selectedRingDataUnavailable'), isFalse);
    expect(published.last['creditsGlance'], credits);

    for (final id in [claudePlanRingId, 'allowance.claude.missing']) {
      final unavailable = watchRingPreferencesFromStoredIds([id]);
      expect(
        watchRingPayloadSubtitle(unknown, unavailable),
        'Selected ring data unavailable',
      );
      final count = published.length;
      await service.sync(unknown, unavailable);
      expect(published, hasLength(count + 1));
      expect(published.last['rings'], isEmpty);
      expect(published.last['creditsGlance'], credits);
    }
  });

  test('builds the sanitized watch summary fixture', () {
    final dashboard = DashboardSnapshot.fromJsonString(
      File('../../fixtures/snapshots/dashboard_today.json').readAsStringSync(),
    );
    final expected = jsonDecode(
      File(
        '../../fixtures/snapshots/watch_dashboard_summary.json',
      ).readAsStringSync(),
    );

    final payload = WatchDashboardSummaryPayload.fromSnapshot(
      dashboard,
      const WatchRingPreferences(),
      // Match fixture: PollCadence floor already elapsed.
      clock: dashboard.generatedAt.add(ManualRefreshWindow.floor),
    );

    expect(jsonDecode(payload.encode()), expected);
  });

  test('sends budget rings keyed by connection', () {
    final payload =
        jsonDecode(
              WatchDashboardSummaryPayload.fromSnapshot(
                DashboardSnapshot.fromJson(_anthropicPlatformJson()),
                const WatchRingPreferences(),
              ).encode(),
            )
            as Map<String, dynamic>;

    final rings = payload['rings'] as List;
    expect(rings.map((ring) => ring['id']), [
      'budget.anthropic.platform.week',
      'budget.anthropic.platform.month',
      'budget.anthropic.platform.today',
    ]);
    // Wear prefixes a family onto a bare pool name; a budget ring arrives named,
    // so Glance shows the connection (`glance-legend-budget.svg`).
    expect(rings.first['label'], 'Anthropic platform · Week');
    // Money travels as structure, currency included: the face strip spells the
    // symbol itself instead of assuming every connection bills in dollars.
    expect(rings.first['spent'], {'minorUnits': 7130, 'currency': 'USD'});
    expect(rings.first['limit'], {'minorUnits': 25000, 'currency': 'USD'});
  });

  // The golden is also what `WatchSummaryStoreTest.kt` decodes, so Wear reads
  // the phone's own publication rather than a literal written to match it.
  test('flags a selected ring whose data is unavailable', () async {
    final published = _captureWatchPublications();
    final json = _anthropicPlatformJson();
    final account = (json['accounts'] as List).first as Map<String, dynamic>;
    // Spend is still reported; the month's limit is gone, so no percentage.
    account['month'] = {
      ...account['month'] as Map<String, dynamic>,
      'limit': null,
      'remaining': null,
      'usedPercent': null,
      'status': 'unknown',
    };
    final dashboard = DashboardSnapshot.fromJson(json);
    const service = MethodChannelWatchSyncService();

    await service.sync(
      dashboard,
      const WatchRingPreferences(
        selectedIds: ['budget.anthropic.platform.month'],
      ),
    );
    await service.sync(dashboard, const WatchRingPreferences(selectedIds: []));

    final expected =
        jsonDecode(
              File(
                '../../fixtures/snapshots/watch_dashboard_summary_selected_ring_unavailable.json',
              ).readAsStringSync(),
            )
            as Map<String, dynamic>;
    expect(published.map((call) => call.method), [
      'syncWatchSummary',
      'syncWatchSummary',
    ]);
    expect(jsonDecode(published.first.arguments as String), expected);
    // Choosing no rings is not missing data: the same payload, flag omitted.
    expect(
      jsonDecode(published.last.arguments as String),
      {...expected}..remove('selectedRingDataUnavailable'),
    );
  });

  for (final sparkUsed in [59.0, 100.0]) {
    test('ships paired Codex exhaustion at Spark $sparkUsed', () {
      final source = DashboardSnapshot.fromJsonString(
        File(
          '../../fixtures/snapshots/dashboard_today.json',
        ).readAsStringSync(),
      );
      final base = source.primaryAccount!.toJson();
      final dashboard = DashboardSnapshot.fromJson(
        source.toJson()
          ..['accounts'] = [
            {
              ...base,
              'provider': 'codex',
              'connection': 'openai.plan',
              'allowances': [
                _cursorPool('codex-primary', 'Weekly plan', 18),
                _cursorPool('spark-primary', 'Spark 5h', sparkUsed),
                _cursorPool('spark-secondary', 'Spark Weekly', 100),
                {
                  ..._cursorPool(
                    'codex-purchased-credits',
                    'Purchased credits',
                    0,
                  ),
                  'source': 'purchased',
                  'remaining': {'value': '320', 'unit': 'credits'},
                },
              ],
            },
            {
              ...base,
              'provider': 'cursor',
              'connection': 'cursor.plan',
              'allowances': [
                _cursorPool('cursor-plan-models', 'Cursor Models', 70),
                _cursorPool('cursor-plan-other', 'Other Models', 40),
              ],
            },
            {
              ...base,
              'provider': 'claude',
              'connection': 'anthropic.plan',
              'allowances': [_cursorPool('claude-five-hour', '5h', 10)],
            },
          ],
      );
      const preferences = WatchRingPreferences(
        selectedIds: [
          'allowance.codex.codex-primary',
          'allowance.codex.spark-primary',
          cursorOwnPoolId,
          cursorOtherPoolId,
          claudePlanRingId,
        ],
      );
      final payload =
          jsonDecode(
                WatchDashboardSummaryPayload.fromSnapshot(
                  dashboard,
                  preferences,
                ).encode(),
              )
              as Map<String, dynamic>;
      expect(payload['schemaVersion'], 9);
      final rings = payload['rings'] as List;
      expect(rings.map((r) => r['id']), [
        codexPlanRingId,
        cursorOwnPoolId,
        claudePlanRingId,
      ]);
      expect(rings[1]['split']['id'], cursorOtherPoolId);
      final codex = rings.first;
      expect(codex['label'], 'Weekly plan');
      expect(codex['usedPercent'], 18);
      expect(codex['split']['id'], codexSparkRingId);
      expect(
        codex['split']['label'],
        sparkUsed < 100 ? 'Spark Weekly' : 'Spark 5h',
      );
      expect(codex['split']['usedPercent'], 100);
      expect(
        watchRingPayloadSubtitle(
          dashboard,
          const WatchRingPreferences(
            selectedIds: [codexPlanRingId, codexSparkRingId],
          ),
        ),
        'Codex plan 0% left',
      );
      final credits = (payload['allowances'] as List).where(
        (a) => a['source'] == 'purchased',
      );
      expect(credits, hasLength(1));
      expect(credits.single['remaining'], {'value': '320', 'unit': 'credits'});
    });
  }

  test('preserves zero and a tiny positive remainder in paired payloads', () {
    final source = DashboardSnapshot.fromJsonString(
      File('../../fixtures/snapshots/dashboard_today.json').readAsStringSync(),
    );
    for (final (inner, outer) in [
      (100.0, 99.96),
      (99.96, 100.0),
      (100.0, 100.0),
    ]) {
      final account =
          source.accounts.single.toJson()
            ..['accountId'] = 'cursor-local'
            ..['provider'] = 'cursor'
            ..['connection'] = 'cursor.plan'
            ..['allowances'] = [
              _cursorPool('cursor-plan-models', 'Cursor Models', inner),
              _cursorPool('cursor-plan-other', 'Other Models', outer),
            ];
      final dashboard = DashboardSnapshot.fromJson(
        source.toJson()..['accounts'] = [account],
      );
      final payload = jsonDecode(
        WatchDashboardSummaryPayload.fromSnapshot(
          dashboard,
          const WatchRingPreferences(
            selectedIds: [cursorOwnPoolId, cursorOtherPoolId],
          ),
        ).encode(),
      );
      expect(payload['schemaVersion'], 9);
      expect(payload['rings'], hasLength(1));
      final ring = payload['rings'].single;
      expect(ring['usedPercent'], inner);
      expect(ring['split']['usedPercent'], outer);
    }
  });

  /// Real core output (USD 0.04 of USD 100.00) published as the phone sends it.
  /// With `WARDPULSE_WATCH_WITNESS_DIR` set, this reads only the producer's
  /// fresh export there and writes both publications back for Wear replay.
  test('publishes fractional usage as positive partial use', () async {
    const producerName = 'dashboard_watch_fractional.json';
    const publicationNames = [
      'watch_dashboard_summary_fractional.json',
      'watch_dashboard_summary_fractional_pair.json',
    ];
    final witnessDir = Platform.environment['WARDPULSE_WATCH_WITNESS_DIR'];
    final controlled =
        File('../../fixtures/snapshots/$producerName').readAsStringSync();
    final produced =
        witnessDir == null
            ? controlled
            : File('$witnessDir/$producerName').readAsStringSync();
    // A missing, malformed or different export fails here, with no fallback.
    expect(jsonDecode(produced), jsonDecode(controlled));

    final published = <String>[];
    const channel = MethodChannel('app.wardpulse/watch_sync');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'syncWatchSummary');
      published.add(call.arguments as String);
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    final json = jsonDecode(produced) as Map<String, dynamic>;
    final account = (json['accounts'] as List).single as Map<String, dynamic>;
    final pairDashboard = DashboardSnapshot.fromJson({
      ...json,
      'accounts': [
        {
          ...account,
          'accountId': 'cursor-local',
          'provider': 'cursor',
          'connection': 'cursor.plan',
          'allowances': [
            _cursorPool('cursor-plan-models', 'Cursor Models', 0.04),
            _cursorPool('cursor-plan-other', 'Other Models', 0.03),
          ],
        },
      ],
    });
    const service = MethodChannelWatchSyncService();
    await service.sync(
      DashboardSnapshot.fromJson(json),
      const WatchRingPreferences(selectedIds: ['budget.openai.platform.today']),
    );
    await service.sync(
      pairDashboard,
      const WatchRingPreferences(
        selectedIds: [cursorOwnPoolId, cursorOtherPoolId],
      ),
    );
    expect(published, hasLength(2));
    if (witnessDir != null) {
      for (final (name, encoded) in [
        (publicationNames.first, published.first),
        (publicationNames.last, published.last),
      ]) {
        // Exclusive creation refuses a publication left by an earlier run.
        File('$witnessDir/$name')
          ..createSync(exclusive: true)
          ..writeAsStringSync(encoded, flush: true);
      }
    }

    final ordinary = jsonDecode(published.first) as Map<String, dynamic>;
    final ring = (ordinary['rings'] as List).single as Map<String, dynamic>;
    expect(ring['id'], 'budget.openai.platform.today');
    expect(ring['spent'], {'minorUnits': 4, 'currency': 'USD'});
    expect(ring['limit'], {'minorUnits': 10000, 'currency': 'USD'});
    expect(ring['split'], isNull);
    // Wear reads exact zero as a full ring, so positive use must stay positive.
    expect(ring['usedPercent'], allOf(greaterThan(0), lessThan(100)));
    expect(ring['usedPercent'], 0.04);
    final pair = jsonDecode(published.last) as Map<String, dynamic>;
    final band = (pair['rings'] as List).single as Map<String, dynamic>;
    expect(band['id'], cursorOwnPoolId);
    expect(band['usedPercent'], 0.04);
    expect(band['split']['id'], cursorOtherPoolId);
    expect(band['split']['usedPercent'], 0.03);
    for (final (name, payload) in [
      (publicationNames.first, ordinary),
      (publicationNames.last, pair),
    ]) {
      expect(
        payload,
        jsonDecode(File('../../fixtures/snapshots/$name').readAsStringSync()),
        reason: name,
      );
    }
  });

  test('ships a lone Cursor pool whole and packs both pools into one ring', () {
    final json =
        jsonDecode(
              File(
                '../../fixtures/snapshots/dashboard_today.json',
              ).readAsStringSync(),
            )
            as Map<String, dynamic>;
    final account = (json['accounts'] as List).first as Map<String, dynamic>;
    account['provider'] = 'cursor';
    account['connection'] = 'cursor.plan';
    account['allowances'] = [
      _cursorPool('cursor-plan-models', 'Cursor Models', 47.0),
      _cursorPool('cursor-plan-other', 'Other Models', 62.0),
    ];
    final expected = jsonDecode(
      File(
        '../../fixtures/snapshots/watch_dashboard_summary_paired.json',
      ).readAsStringSync(),
    );

    final dashboard = DashboardSnapshot.fromJson(json);
    final lonePayload =
        jsonDecode(
              WatchDashboardSummaryPayload.fromSnapshot(
                dashboard,
                const WatchRingPreferences(selectedIds: [cursorOwnPoolId]),
              ).encode(),
            )
            as Map<String, dynamic>;
    final loneRings = lonePayload['rings'] as List;
    expect(loneRings, hasLength(1));
    expect(loneRings.single['id'], cursorOwnPoolId);
    expect(loneRings.single['split'], isNull);

    final pairedPayload =
        jsonDecode(
              WatchDashboardSummaryPayload.fromSnapshot(
                dashboard,
                const WatchRingPreferences(
                  selectedIds: [cursorOwnPoolId, cursorOtherPoolId],
                ),
                // Match fixture: PollCadence floor already elapsed.
                clock: dashboard.generatedAt.add(ManualRefreshWindow.floor),
              ).encode(),
            )
            as Map<String, dynamic>;

    // One band, so one entry: the second pool rides inside the first
    // (`WATCH_RING_DESIGN.md`, Split band). The golden is the whole payload
    // because Wear parses this very file (`WatchSummaryStoreTest`) — a renamed
    // key has to fail on one side or the other, not quietly on neither.
    expect(pairedPayload, expected);
    final pairedRings = pairedPayload['rings'] as List;
    expect(pairedRings.single['split']['label'], 'Other Models');
  });

  for (final (innerUsed, outerUsed) in [(47.0, 62.0), (62.0, 47.0)]) {
    test('keeps Cursor payload order at $innerUsed/$outerUsed used', () {
      final json =
          jsonDecode(
                File(
                  '../../fixtures/snapshots/dashboard_today.json',
                ).readAsStringSync(),
              )
              as Map<String, dynamic>;
      final account = (json['accounts'] as List).first as Map<String, dynamic>;
      account['provider'] = 'cursor';
      account['connection'] = 'cursor.plan';
      account['allowances'] = [
        _cursorPool('cursor-plan-models', 'Cursor Models', innerUsed),
        _cursorPool('cursor-plan-other', 'Other Models', outerUsed),
      ];
      final dashboard = DashboardSnapshot.fromJson(json);
      const preferences = WatchRingPreferences(
        selectedIds: [cursorOtherPoolId, cursorOwnPoolId],
      );
      final payload =
          jsonDecode(
                WatchDashboardSummaryPayload.fromSnapshot(
                  dashboard,
                  preferences,
                ).encode(),
              )
              as Map<String, dynamic>;

      expect(payload['schemaVersion'], 9);
      expect(payload['rings'], [
        {
          'id': cursorOwnPoolId,
          'label': 'Cursor Models',
          'usedPercent': innerUsed,
          'status': 'ok',
          'spent': null,
          'limit': null,
          'split': {
            'id': cursorOtherPoolId,
            'label': 'Other Models',
            'usedPercent': outerUsed,
            'status': 'ok',
          },
        },
      ]);
      expect(
        watchRingPayloadSubtitle(dashboard, preferences),
        'Cursor plan 38% left',
      );
    });
  }

  test('marks the previous watch summary stale after a sync failure', () {
    final dashboard =
        DashboardSnapshot.fromJsonString(
          File(
            '../../fixtures/snapshots/dashboard_today.json',
          ).readAsStringSync(),
        ).withStaleStatus();

    final payload =
        jsonDecode(
              WatchDashboardSummaryPayload.fromSnapshot(
                dashboard,
                const WatchRingPreferences(),
              ).encode(),
            )
            as Map<String, dynamic>;

    expect(payload['overallStatus'], 'stale');
    expect(payload['isStale'], isTrue);
    expect(
      (payload['providers'] as List<dynamic>).map(
        (provider) => (provider as Map<String, dynamic>)['status'],
      ),
      everyElement('stale'),
    );
  });

  test('sends all reported allowance sources', () {
    final json =
        jsonDecode(
              File(
                '../../fixtures/snapshots/dashboard_today.json',
              ).readAsStringSync(),
            )
            as Map<String, dynamic>;
    final account = (json['accounts'] as List).first as Map<String, dynamic>;
    account['allowances'] = [
      {
        'id': 'plan',
        'source': 'plan',
        'label': 'Weekly plan',
        'usedPercent': 80,
        'used': null,
        'limit': null,
        'remaining': null,
        'windowMinutes': 10080,
        'resetsAt': null,
        'status': 'warning',
      },
      {
        'id': 'purchased',
        'source': 'purchased',
        'label': 'Purchased credits',
        'usedPercent': null,
        'used': null,
        'limit': null,
        'remaining': {'value': '12.5', 'unit': 'credits'},
        'unlimited': false,
        'windowMinutes': null,
        'resetsAt': null,
        'status': 'ok',
      },
    ];

    final payload =
        jsonDecode(
              WatchDashboardSummaryPayload.fromSnapshot(
                DashboardSnapshot.fromJson(json),
                const WatchRingPreferences(),
              ).encode(),
            )
            as Map<String, dynamic>;

    expect(payload['schemaVersion'], 9);
    expect(payload['creditsGlance'], {
      'text': '12.5',
      'label': 'Credits left',
      'provider': 'mock',
    });
    expect(payload['dataMode'], 'mock');
    final allowances = payload['allowances'] as List;
    expect(allowances, hasLength(2));
    expect(allowances.map((row) => row['source']), ['plan', 'purchased']);
    expect(allowances.last['label'], 'Mock · Purchased credits');
  });

  test(
    'marks multi-provider debug dashboards as mock dataMode when forced',
    () {
      final json =
          jsonDecode(
                File(
                  '../../fixtures/snapshots/dashboard_today.json',
                ).readAsStringSync(),
              )
              as Map<String, dynamic>;
      (json['accounts'] as List).first['provider'] = 'cursor';

      final payload =
          jsonDecode(
                WatchDashboardSummaryPayload.fromSnapshot(
                  DashboardSnapshot.fromJson(json),
                  const WatchRingPreferences(),
                  mockDataMode: true,
                ).encode(),
              )
              as Map<String, dynamic>;

      expect(payload['dataMode'], 'mock');
    },
  );

  test('sends unlimited purchased usage explicitly', () {
    final json =
        jsonDecode(
              File(
                '../../fixtures/snapshots/dashboard_today.json',
              ).readAsStringSync(),
            )
            as Map<String, dynamic>;
    final account = (json['accounts'] as List).first as Map<String, dynamic>;
    account['allowances'] = [
      {
        'id': 'purchased',
        'source': 'purchased',
        'label': 'Purchased credits',
        'usedPercent': null,
        'used': null,
        'limit': null,
        'remaining': null,
        'unlimited': true,
        'windowMinutes': null,
        'resetsAt': null,
        'status': 'ok',
      },
    ];

    final payload =
        jsonDecode(
              WatchDashboardSummaryPayload.fromSnapshot(
                DashboardSnapshot.fromJson(json),
                const WatchRingPreferences(),
              ).encode(),
            )
            as Map<String, dynamic>;

    expect((payload['allowances'] as List).first['unlimited'], isTrue);
  });

  test('embeds PollCadence floor window for Wear refresh chrome', () {
    final dashboard = DashboardSnapshot.fromJsonString(
      File('../../fixtures/snapshots/dashboard_today.json').readAsStringSync(),
    );
    final lastSync = dashboard.generatedAt;
    final payload =
        jsonDecode(
              WatchDashboardSummaryPayload.fromSnapshot(
                dashboard,
                const WatchRingPreferences(),
                manualRefreshAnchorAt: lastSync,
                clock: lastSync.add(const Duration(minutes: 2)),
              ).encode(),
            )
            as Map<String, dynamic>;

    expect(payload['manualRefreshAllowed'], isFalse);
    expect(
      payload['manualRefreshAvailableAt'],
      lastSync.add(ManualRefreshWindow.floor).toUtc().toIso8601String(),
    );
  });
}

List<MethodCall> _captureWatchPublications() {
  final published = <MethodCall>[];
  const channel = MethodChannel('app.wardpulse/watch_sync');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(channel, (call) async {
    published.add(call);
    return null;
  });
  addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
  return published;
}

/// The mock account as an Anthropic platform connection with budget limits.
Map<String, dynamic> _anthropicPlatformJson() {
  final json =
      jsonDecode(
            File(
              '../../fixtures/snapshots/dashboard_today.json',
            ).readAsStringSync(),
          )
          as Map<String, dynamic>;
  final account = (json['accounts'] as List).first as Map<String, dynamic>;
  // Mock accounts hold no rings, so only the connection differs here.
  account['provider'] = 'claude';
  account['connection'] = 'anthropic.platform';
  return json;
}

/// Synthetic values exercise three pair identities without provider calls.
DashboardSnapshot _pairedDashboard({
  double? claudeUsed = 40,
  double? fableUsed = 90,
}) {
  final source = DashboardSnapshot.fromJsonString(
    File('../../fixtures/snapshots/dashboard_today.json').readAsStringSync(),
  );
  final base = source.primaryAccount!.toJson();
  return DashboardSnapshot.fromJson(
    source.toJson()
      ..['accounts'] = [
        {
          ...base,
          'provider': 'claude',
          'connection': 'anthropic.plan',
          'allowances': [
            {
              ..._cursorPool('claude-five-hour', '5h', claudeUsed ?? 0),
              'usedPercent': claudeUsed,
              'resetsAt': '2026-11-01T12:00:00Z',
            },
            {
              ..._cursorPool(
                'claude-seven-day-fable',
                'Fable weekly',
                fableUsed ?? 0,
              ),
              'usedPercent': fableUsed,
              'resetsAt': '2026-11-08T08:00:00Z',
            },
          ],
        },
        {
          ...base,
          'provider': 'codex',
          'connection': 'openai.plan',
          'allowances': [
            _cursorPool('codex-primary', '5h', 30),
            _cursorPool('spark-primary', 'Spark 5h', 20),
          ],
        },
        {
          ...base,
          'provider': 'cursor',
          'connection': 'cursor.plan',
          'allowances': [
            _cursorPool('cursor-plan-models', 'Cursor Models', 70),
            _cursorPool('cursor-plan-other', 'Other Models', 20),
          ],
        },
      ],
  );
}

/// A plan pool as the Cursor adapter reports it: a percent and nothing to bill.
Map<String, dynamic> _cursorPool(String id, String label, double usedPercent) {
  return {
    'id': id,
    'source': 'plan',
    'label': label,
    'usedPercent': usedPercent,
    'used': null,
    'limit': null,
    'remaining': null,
    'unlimited': false,
    'windowMinutes': null,
    'resetsAt': null,
    'status': 'ok',
  };
}

Map<String, dynamic> _freshnessWatch(
  DashboardSnapshot snapshot,
  WatchRingPreferences preferences,
) =>
    jsonDecode(
          WatchDashboardSummaryPayload.fromSnapshot(
            snapshot,
            preferences,
          ).encode(),
        )
        as Map<String, dynamic>;
