import 'package:flutter_test/flutter_test.dart';

import '../test_driver/notification_delivery.dart'
    show validateNotificationDeliveryReport;

const _labels = [
  'READY',
  'DENIED ALERT',
  'DENIED RECOVERY',
  'GRANT',
  'NO BACKLOG',
  'CROSSED',
  'UNCHANGED',
  'CLEAR',
  'REARMED',
  'MUTED ALERT',
  'MUTED RECOVERY',
  'EXHAUSTED',
  'RECOVERED',
];

Map<String, dynamic> _defaultReport() => {
  'scope': 'injected pipeline / real FFI and Android adapters',
  'alert': <String, dynamic>{
    'channel': 'wardpulse.alerts',
    'id': 0,
    'tag':
        'wardpulse.alert.'
        '0123456789abcdef0123456789abcdef'
        '0123456789abcdef0123456789abcdef',
    'adapterAttempts': 3,
    'pluginCompletions': 3,
  },
  'recovery': <String, dynamic>{
    'channel': 'wardpulse.plan_recovery',
    'id': 42,
    'tag': null,
    'adapterAttempts': 2,
    'pluginCompletions': 1,
  },
  'barriers': [for (final label in _labels) '$label: completed.'],
};

Map<String, dynamic> _focusedReport() => {
  'scope':
      'first foreground / real Android request; HOST dialog observation required',
  'requests': 1,
  'channelsBeforeCasePost': true,
  'refreshRemountNoSecondRequest': true,
};

Map<String, dynamic> _grantedReport() => {
  'scope': 'granted baseline / real FFI and Android adapters',
  'completed': true,
  'alert': <String, dynamic>{
    'channel': 'wardpulse.alerts',
    'id': 0,
    'tag':
        'wardpulse.alert.'
        '0123456789abcdef0123456789abcdef'
        '0123456789abcdef0123456789abcdef',
    'adapterAttempts': 1,
    'pluginCompletions': 1,
  },
  'recovery': <String, dynamic>{
    'channel': 'wardpulse.plan_recovery',
    'id': 42,
    'tag': null,
    'adapterAttempts': 1,
    'pluginCompletions': 1,
  },
  'barriers': [
    'GRANTED READY',
    'ALERT POSTED',
    'RECOVERY READY',
    'RECOVERY POSTED',
    'COMPLETE',
  ],
};

void main() {
  test('accepts a complete default report with bounded completions', () {
    final report = _defaultReport();
    expect(() => validateNotificationDeliveryReport(report), returnsNormally);
    report['alert']['pluginCompletions'] = 0;
    report['recovery']['pluginCompletions'] = 2;
    expect(() => validateNotificationDeliveryReport(report), returnsNormally);
  });

  test('accepts focused completion without default identities or stages', () {
    expect(
      () => validateNotificationDeliveryReport(_focusedReport()),
      returnsNormally,
    );
  });

  test(
    'accepts granted completion with one completed attempt per identity',
    () {
      expect(
        () => validateNotificationDeliveryReport(_grantedReport()),
        returnsNormally,
      );
    },
  );

  test('rejects incomplete granted terminal state and nonexact stages', () {
    for (final completed in <Object?>[null, false, 'true', 1]) {
      expect(
        () => validateNotificationDeliveryReport(
          _grantedReport()..['completed'] = completed,
        ),
        throwsFormatException,
      );
    }
    final stages = _grantedReport()['barriers'] as List<String>;
    for (final barriers in <Object?>[
      null,
      'COMPLETE',
      stages.take(4).toList(),
      stages.reversed.toList(),
      [...stages, 'COMPLETE'],
      [...stages]..[0] = 'GRANTED READY: completed.',
      <Object?>[...stages]..[4] = null,
    ]) {
      expect(
        () => validateNotificationDeliveryReport(
          _grantedReport()..['barriers'] = barriers,
        ),
        throwsFormatException,
      );
    }
  });

  test('rejects invalid granted identities and absent recovery tag', () {
    for (final (name, field, value) in <(String, String, Object?)>[
      ('alert', 'channel', 'wrong'),
      ('recovery', 'channel', 'wrong'),
      ('alert', 'id', 1),
      ('alert', 'id', 0.0),
      ('recovery', 'id', -1),
      ('recovery', 'id', 0x80000000),
      ('alert', 'tag', 'wardpulse.alert.short'),
      ('recovery', 'tag', 'unexpected'),
    ]) {
      final report = _grantedReport();
      report[name][field] = value;
      expect(
        () => validateNotificationDeliveryReport(report),
        throwsFormatException,
        reason: '$name.$field',
      );
    }
    final report = _grantedReport();
    (report['recovery'] as Map<String, dynamic>).remove('tag');
    expect(
      () => validateNotificationDeliveryReport(report),
      throwsFormatException,
    );
  });

  test(
    'rejects granted attempt/completion mismatches and noninteger counts',
    () {
      for (final name in ['alert', 'recovery']) {
        for (final field in ['adapterAttempts', 'pluginCompletions']) {
          for (final value in <Object?>[null, 0, 2, 1.0]) {
            final report = _grantedReport();
            report[name][field] = value;
            expect(
              () => validateNotificationDeliveryReport(report),
              throwsFormatException,
              reason: '$name.$field=$value',
            );
          }
        }
      }
    },
  );

  test('rejects null, missing scope and unknown scope', () {
    for (final report in [
      null,
      _defaultReport()..remove('scope'),
      _defaultReport()..['scope'] = 'unknown',
    ]) {
      expect(
        () => validateNotificationDeliveryReport(report),
        throwsFormatException,
      );
    }
  });

  test('rejects incomplete, unordered or malformed default barriers', () {
    for (final barriers in <Object?>[
      null,
      'RECOVERED: completed.',
      ['RECOVERED: completed.'],
      [for (final label in _labels.take(12)) '$label: completed.'],
      [for (final label in _labels.reversed) '$label: completed.'],
      [..._defaultReport()['barriers'], 'RECOVERED: completed.'],
      [..._defaultReport()['barriers']]..[12] = 'RECOVERED',
      [..._defaultReport()['barriers']]..[12] = null,
    ]) {
      final report = _defaultReport()..['barriers'] = barriers;
      expect(
        () => validateNotificationDeliveryReport(report),
        throwsFormatException,
      );
    }
  });

  test('rejects missing or malformed nested identities', () {
    for (final name in ['alert', 'recovery']) {
      for (final identity in [null, <Object>[], <String, dynamic>{}]) {
        final report = _defaultReport()..[name] = identity;
        expect(
          () => validateNotificationDeliveryReport(report),
          throwsFormatException,
          reason: name,
        );
      }
    }
    final report = _defaultReport();
    (report['recovery'] as Map<String, dynamic>).remove('tag');
    expect(
      () => validateNotificationDeliveryReport(report),
      throwsFormatException,
    );
  });

  test('rejects invalid identity fields and completion counts', () {
    for (final (name, field, value) in <(String, String, Object?)>[
      ('alert', 'channel', 'wrong'),
      ('recovery', 'channel', 'wrong'),
      ('alert', 'id', 1),
      ('alert', 'id', 0.0),
      ('recovery', 'id', -1),
      ('recovery', 'id', 0x80000000),
      ('alert', 'tag', 'wardpulse.alert.short'),
      ('alert', 'tag', 42),
      ('recovery', 'tag', 'unexpected'),
      ('alert', 'adapterAttempts', 2),
      ('recovery', 'adapterAttempts', 1),
      ('alert', 'adapterAttempts', 3.0),
      ('alert', 'pluginCompletions', -1),
      ('recovery', 'pluginCompletions', 3),
      ('alert', 'pluginCompletions', 1.0),
      ('alert', 'pluginCompletions', null),
    ]) {
      final report = _defaultReport();
      report[name][field] = value;
      expect(
        () => validateNotificationDeliveryReport(report),
        throwsFormatException,
        reason: '$name.$field',
      );
    }
  });

  test('rejects incomplete or malformed focused completion', () {
    for (final (field, value) in <(String, Object?)>[
      ('requests', null),
      ('requests', 0),
      ('requests', 2),
      ('requests', 1.0),
      ('channelsBeforeCasePost', null),
      ('channelsBeforeCasePost', false),
      ('refreshRemountNoSecondRequest', false),
      ('refreshRemountNoSecondRequest', 'true'),
    ]) {
      final report = _focusedReport()..[field] = value;
      expect(
        () => validateNotificationDeliveryReport(report),
        throwsFormatException,
        reason: field,
      );
    }
  });
}
