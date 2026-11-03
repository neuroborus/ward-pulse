import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ward_pulse_phone/dashboard/dashboard_models.dart';
import 'package:ward_pulse_phone/dashboard/provider_status_color.dart';
import 'package:ward_pulse_phone/providers/provider_connection.dart';
import 'package:ward_pulse_phone/widget/phone_widget_payload.dart';
import 'package:ward_pulse_phone/widget/phone_widget_preferences.dart';

void main() {
  final snapshot = DashboardSnapshot.fromJsonString(
    File('../../fixtures/snapshots/dashboard_today.json').readAsStringSync(),
  );

  test('builds remaining rows from available percent metrics', () {
    final payload = buildPhoneWidgetPayload(
      _asConnection(snapshot),
      const PhoneWidgetPreferences(),
    );
    expect(payload.stale, isFalse);
    expect(payload.rows, isNotEmpty);
    for (final row in payload.rows) {
      expect(row.remainingPercent, inInclusiveRange(0, 100));
      expect(row.line, contains('% left ·'));
    }
  });

  test(
    'Fable widget zero retains its accent and reset while unknown is omitted',
    () {
      const fableId = 'allowance.claude.claude-seven-day-fable';
      final reset = DateTime.utc(2026, 11, 8, 8);
      for (final used in [100.0, null]) {
        final account =
            snapshot.primaryAccount!.toJson()
              ..['accountId'] = 'claude-local'
              ..['provider'] = 'claude'
              ..['connection'] = ProviderConnections.claudePlan.storageKey
              ..['allowances'] = [
                {
                  ..._allowance(
                    'claude-seven-day-fable',
                    'Fable weekly',
                    100,
                    resetsAt: reset,
                  ),
                  'usedPercent': used,
                  'windowMinutes': 7 * 24 * 60,
                  'status': used == null ? 'unknown' : 'rateLimited',
                },
                _allowance('claude-seven-day', 'Weekly plan', 60),
              ];
        final payload = buildPhoneWidgetPayload(
          DashboardSnapshot.fromJson({
            ...snapshot.toJson(),
            'accounts': [account],
          }),
          const PhoneWidgetPreferences(
            selectedIds: [fableId, 'allowance.claude.claude-seven-day'],
          ),
        );
        expect(payload.rows.last.poolLabel, 'Weekly plan');
        expect(payload.rows.last.accentArgb, 0xFFE8915A);
        if (used == null) {
          expect(payload.rows, hasLength(1));
        } else {
          expect(payload.rows, hasLength(2));
          final fable = payload.rows.first;
          expect(fable.poolLabel, 'Fable weekly');
          expect(fable.remainingPercent, 0);
          expect(fable.accentArgb, 0xFFFF603D);
          expect(fable.resetsAt, reset);
        }
      }
    },
  );

  test('Extra usage rows require a reported valid percent but no cap', () {
    const preferences = PhoneWidgetPreferences(
      selectedIds: ['allowance.claude.claude-extra-usage'],
    );
    for (final percent in [
      0.0,
      20.0,
      100.0,
      150.0,
      null,
      -1.0,
      double.nan,
      double.infinity,
    ]) {
      final input = DashboardSnapshot.fromJson({
        ...DashboardSnapshot.empty().toJson(),
        'accounts': [
          {
            'accountId': 'claude-local',
            'provider': 'claude',
            'connection': 'anthropic.plan',
            'status': 'ok',
            'credits': <Object>[],
            'buckets': <Object>[],
            'modelBreakdown': <Object>[],
            for (final period in ['today', 'week', 'month'])
              period: BudgetState.unknownPeriod(period).toJson(),
            'allowances': [
              {
                'id': 'claude-extra-usage',
                'status': 'ok',
                'source': 'purchased',
                'label': 'Extra usage',
                'usedPercent': percent,
                'limit': null,
              },
            ],
          },
        ],
      });
      final rows = buildPhoneWidgetPayload(input, preferences).rows;
      if (percent == null || !percent.isFinite || percent < 0) {
        expect(rows, isEmpty);
      } else {
        expect(rows, hasLength(1));
        expect(
          rows.single.remainingPercent,
          (100 - percent).clamp(0, 100).round(),
        );
        expect(rows.single.poolLabel, 'Extra usage');
        expect(rows.single.creditsSuffix, isNull);
        expect(rows.single.resetsAt, isNull);
      }
    }
  });

  test('marks stale when overall status is stale', () {
    final stale = snapshot.withStaleStatus(
      syncIssue: DashboardSyncIssue.authentication,
    );
    final payload = buildPhoneWidgetPayload(
      stale,
      const PhoneWidgetPreferences(),
    );
    expect(payload.stale, isTrue);
  });

  test('empty selection yields empty payload', () {
    final payload = buildPhoneWidgetPayload(
      snapshot,
      const PhoneWidgetPreferences(selectedIds: []),
    );
    expect(payload.isEmpty, isTrue);
    expect(payload.rows, isEmpty);
  });

  test('preserves exact window resets and complete pool labels', () {
    final shortReset = DateTime.utc(2028, 2, 10, 9, 15);
    final longReset = DateTime.utc(2028, 2, 17, 11, 45);
    final otherProviderReset = DateTime.utc(2028, 2, 11, 14, 30);
    const pool = 'Weekly pool · Complete name';
    final account = snapshot.primaryAccount!.toJson();
    final source = DashboardSnapshot.fromJson({
      ...snapshot.toJson(),
      'accounts': [
        {
          ...account,
          'accountId': 'claude-local',
          'provider': 'claude',
          'allowances': [
            _allowance('window.short', pool, 80, resetsAt: shortReset),
            _allowance('window.long', pool, 60, resetsAt: longReset),
          ],
        },
        {
          ...account,
          'accountId': 'codex-local',
          'provider': 'codex',
          'allowances': [
            _allowance('window.short', pool, 40, resetsAt: otherProviderReset),
            _allowance('window.no-reset', pool, 20),
          ],
        },
      ],
    });

    final payload = buildPhoneWidgetPayload(
      source,
      const PhoneWidgetPreferences(
        selectedIds: [
          'allowance.claude.window.short',
          'allowance.claude.window.long',
          'allowance.codex.window.short',
          'allowance.codex.window.no-reset',
        ],
      ),
    );

    expect(
      payload.rows.map(
        (row) => (
          row.familyLabel,
          row.poolLabel,
          row.remainingPercent,
          row.resetsAt,
        ),
      ),
      [
        ('Claude', pool, 20, shortReset),
        ('Claude', pool, 40, longReset),
        ('Codex', pool, 60, otherProviderReset),
        ('Codex', pool, 80, null),
      ],
    );
  });

  test('budget identity retains its connection without an allowance reset', () {
    final account = _asConnection(snapshot).primaryAccount!.toJson();
    account['allowances'] = [
      _allowance(
        'window.short',
        'Today',
        50,
        resetsAt: DateTime.utc(2028, 2, 10, 9, 15),
      ),
    ];
    final source = DashboardSnapshot.fromJson({
      ...snapshot.toJson(),
      'accounts': [account],
    });

    final payload = buildPhoneWidgetPayload(
      source,
      const PhoneWidgetPreferences(
        selectedIds: ['budget.anthropic.platform.today'],
      ),
    );

    expect(payload.rows, hasLength(1));
    final row = payload.rows.single;
    expect(row.label, 'Anthropic platform · Today');
    expect(row.familyLabel, 'Anthropic platform');
    expect(row.poolLabel, 'Today');
    expect(row.resetsAt, isNull);
    expect(row.creditsSuffix, isNull);
  });

  test('family accents follow the family named in the metric id', () {
    final claude = providerFamilyColor('claude').toARGB32();
    expect(phoneWidgetAccentArgb('allowance.claude.plan'), claude);
    expect(
      phoneWidgetAccentArgb('allowance.claude.claude-seven-day-fable'),
      0xFFFF603D,
    );
    for (final id in [
      'allowance.claude.claude-seven-day',
      'allowance.claude.claude-seven-day-fable-other',
      'budget.anthropic.platform.claude-seven-day-fable',
    ]) {
      expect(phoneWidgetAccentArgb(id), claude, reason: id);
    }
    // A budget ring carries its connection, so it takes that family too.
    expect(phoneWidgetAccentArgb('budget.anthropic.platform.month'), claude);
    expect(
      phoneWidgetAccentArgb('budget.openai.platform.today'),
      providerFamilyColor('codex').toARGB32(),
    );
    // No family named in the id: fall back to the colourless accent.
    expect(
      phoneWidgetAccentArgb('budget.mock.plan.today'),
      familyFallbackColor.toARGB32(),
    );
    // The Cursor plan's own models leave the family colour; everything else
    // Cursor keeps it.
    expect(
      phoneWidgetAccentArgb('allowance.cursor.cursor-plan-models'),
      familyCursorOwnColor.toARGB32(),
    );
    expect(
      phoneWidgetAccentArgb('allowance.cursor.cursor-plan-other'),
      providerFamilyColor('cursor').toARGB32(),
    );
    // The Spark limit leaves the family colour; the plan's own windows keep it.
    expect(
      phoneWidgetAccentArgb('allowance.codex.spark-primary'),
      familyCodexSparkColor.toARGB32(),
    );
    expect(
      phoneWidgetAccentArgb('allowance.codex.codex-primary'),
      providerFamilyColor('codex').toARGB32(),
    );
  });

  test('keeps exhausted Cursor Models as 0% left beside Other Models', () {
    final cursor =
        snapshot.primaryAccount!.toJson()
          ..['accountId'] = 'cursor-local'
          ..['provider'] = 'cursor'
          ..['status'] = 'rateLimited'
          ..['allowances'] = [
            {
              'id': 'cursor-plan-models',
              'source': 'plan',
              'label': 'Cursor Models',
              'usedPercent': 100.0,
              'used': null,
              'limit': null,
              'remaining': null,
              'unlimited': false,
              'windowMinutes': null,
              'resetsAt': null,
              'status': 'rateLimited',
            },
            {
              'id': 'cursor-plan-other',
              'source': 'plan',
              'label': 'Other Models',
              'usedPercent': 40.0,
              'used': null,
              'limit': null,
              'remaining': null,
              'unlimited': false,
              'windowMinutes': null,
              'resetsAt': null,
              'status': 'ok',
            },
          ]
          ..['buckets'] = <Object>[]
          ..['modelBreakdown'] = <Object>[];
    final withCursor = DashboardSnapshot.fromJson({
      ...snapshot.toJson(),
      'accounts': [cursor],
      'todayTotal': {
        'period': 'today',
        'spent': null,
        'limit': null,
        'remaining': null,
        'usedPercent': null,
        'projectedTotal': null,
        'status': 'unknown',
        'statusExplanation': null,
      },
      'weekTotal': {
        'period': 'week',
        'spent': null,
        'limit': null,
        'remaining': null,
        'usedPercent': null,
        'projectedTotal': null,
        'status': 'unknown',
        'statusExplanation': null,
      },
      'monthTotal': {
        'period': 'month',
        'spent': null,
        'limit': null,
        'remaining': null,
        'usedPercent': null,
        'projectedTotal': null,
        'status': 'unknown',
        'statusExplanation': null,
      },
    });

    final payload = buildPhoneWidgetPayload(
      withCursor,
      const PhoneWidgetPreferences(),
    );
    expect(
      payload.rows.map((row) => row.label),
      containsAll(['Cursor Models', 'Cursor · Other Models']),
    );
    final models = payload.rows.firstWhere(
      (row) => row.label == 'Cursor Models',
    );
    expect(models.remainingPercent, 0);
    expect(models.familyLabel, 'Cursor');
    expect(models.poolLabel, 'Models');
    final otherModels = payload.rows.firstWhere(
      (row) => row.label == 'Cursor · Other Models',
    );
    expect(otherModels.familyLabel, 'Cursor');
    expect(otherModels.poolLabel, 'Other Models');
  });

  test('appends per-provider purchased credits like Wear Glance', () {
    final account = Map<String, Object?>.from(
      snapshot.primaryAccount!.toJson(),
    );
    final claude = {
      ...account,
      'accountId': 'claude-1',
      'provider': 'claude',
      'allowances': [
        {
          'id': 'claude-five-hour',
          'source': 'plan',
          'label': '5h',
          'usedPercent': 40.0,
          'used': null,
          'limit': null,
          'remaining': null,
          'unlimited': false,
          'windowMinutes': 300,
          'resetsAt': null,
          'status': 'ok',
        },
        {
          'id': 'claude-extra-usage',
          'source': 'purchased',
          'label': 'Extra usage',
          'usedPercent': 20.0,
          'used': {'value': '80', 'unit': 'credits'},
          'limit': {'value': '100', 'unit': 'credits'},
          'remaining': {'value': '320', 'unit': 'credits'},
          'unlimited': false,
          'windowMinutes': null,
          'resetsAt': null,
          'status': 'ok',
        },
      ],
      'buckets': <Object?>[],
      'modelBreakdown': <Object?>[],
      'credits': <Object?>[],
    };
    final withCredits = DashboardSnapshot.fromJson({
      ...snapshot.toJson(),
      'accounts': [claude],
      'todayTotal': {
        'period': 'today',
        'spent': null,
        'limit': null,
        'remaining': null,
        'usedPercent': null,
        'projectedTotal': null,
        'status': 'unknown',
        'statusExplanation': null,
      },
      'weekTotal': {
        'period': 'week',
        'spent': null,
        'limit': null,
        'remaining': null,
        'usedPercent': null,
        'projectedTotal': null,
        'status': 'unknown',
        'statusExplanation': null,
      },
      'monthTotal': {
        'period': 'month',
        'spent': null,
        'limit': null,
        'remaining': null,
        'usedPercent': null,
        'projectedTotal': null,
        'status': 'unknown',
        'statusExplanation': null,
      },
    });

    final payload = buildPhoneWidgetPayload(
      withCredits,
      const PhoneWidgetPreferences(
        selectedIds: ['allowance.claude.claude-five-hour'],
      ),
    );
    expect(payload.rows, hasLength(1));
    expect(payload.rows.single.creditsSuffix, '320 credits');
    expect(payload.rows.single.percentText, '60% left');
    expect(payload.rows.single.label, 'Claude · 5h');
    expect(payload.rows.single.line, '60% left · Claude · 5h · 320 credits');
    expect(
      phoneWidgetCreditsSuffix(withCredits, 'budget.anthropic.platform.today'),
      isNull,
      reason: 'budget rings track spend, not a credit pool',
    );
    expect(
      phoneWidgetCreditsSuffix(
        withCredits,
        'allowance.claude.claude-extra-usage',
      ),
      isNull,
      reason: 'purchased-meter rows are the credit pool; do not repeat credits',
    );
  });
}

Map<String, Object?> _allowance(
  String id,
  String label,
  double usedPercent, {
  DateTime? resetsAt,
}) => {
  'id': id,
  'source': 'plan',
  'label': label,
  'usedPercent': usedPercent,
  'windowMinutes': 300,
  'resetsAt': resetsAt?.toUtc().toIso8601String(),
  'status': 'ok',
};

/// Mock fixture as a real connection: mock accounts hold no metric slots.
DashboardSnapshot _asConnection(DashboardSnapshot snapshot) {
  final account =
      Map<String, Object?>.from(snapshot.primaryAccount!.toJson())
        ..['accountId'] = 'anthropic-platform'
        ..['provider'] = 'claude'
        ..['connection'] = 'anthropic.platform';
  return DashboardSnapshot.fromJson({
    ...snapshot.toJson(),
    'accounts': [account],
  });
}
