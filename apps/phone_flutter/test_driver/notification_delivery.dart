import 'package:integration_test/integration_test_driver.dart';

Future<void> main() => integrationDriver(
  writeResponseOnFailure: true,
  responseDataCallback: (data) async {
    await writeResponseData(data);
    validateNotificationDeliveryReport(data);
  },
);

/// Requires the terminal report shape of either notification case.
void validateNotificationDeliveryReport(Map<String, dynamic>? report) {
  if (report == null) {
    throw const FormatException('Missing notification delivery report.');
  }
  switch (report['scope']) {
    case 'first foreground / real Android request; HOST dialog observation required':
      if (report['requests'] is! int ||
          report['requests'] != 1 ||
          report['channelsBeforeCasePost'] != true ||
          report['refreshRemountNoSecondRequest'] != true) {
        throw const FormatException('Incomplete first-foreground report.');
      }
      return;
    case 'injected pipeline / real FFI and Android adapters':
      break;
    default:
      throw const FormatException('Unknown notification report scope.');
  }

  final alert = report['alert'];
  final recovery = report['recovery'];
  if (alert is! Map<String, dynamic> || recovery is! Map<String, dynamic>) {
    throw const FormatException('Missing notification delivery identities.');
  }
  for (final (identity, channel, attempts) in [
    (alert, 'wardpulse.alerts', 3),
    (recovery, 'wardpulse.plan_recovery', 2),
  ]) {
    final id = identity['id'];
    final completions = identity['pluginCompletions'];
    if (identity['channel'] != channel ||
        id is! int ||
        id < 0 ||
        id > 0x7fffffff ||
        identity['adapterAttempts'] is! int ||
        identity['adapterAttempts'] != attempts ||
        completions is! int ||
        completions < 0 ||
        completions > attempts) {
      throw FormatException('Invalid $channel identity or completion counts.');
    }
  }
  final tag = alert['tag'];
  if (alert['id'] != 0 ||
      tag is! String ||
      !RegExp(r'^wardpulse\.alert\.[0-9a-f]{64}$').hasMatch(tag) ||
      !recovery.containsKey('tag') ||
      recovery['tag'] != null) {
    throw const FormatException('Invalid notification tags or alert ID.');
  }

  const labels = [
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
  final barriers = report['barriers'];
  if (barriers is! List || barriers.length != labels.length) {
    throw const FormatException('Incomplete notification delivery barriers.');
  }
  for (var index = 0; index < labels.length; index++) {
    final barrier = barriers[index];
    if (barrier is! String || !barrier.startsWith('${labels[index]}: ')) {
      throw const FormatException('Invalid notification barrier order.');
    }
  }
}
