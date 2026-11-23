import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:ward_pulse_phone/providers/claude_account_store.dart';
import 'package:ward_pulse_phone/settings/watch_ring_preferences.dart';
import 'package:ward_pulse_phone/widget/phone_widget_payload.dart';
import 'package:ward_pulse_phone/widget/phone_widget_preferences.dart';
import 'package:ward_pulse_phone/widget/phone_widget_sync.dart';

/// Test-only Debug seed for the Claude plan pause upgrade check.
///
/// Writes fake Claude plan credentials, saved Claude display choices and a
/// mixed or Claude-only widget cache through the ordinary `app.wardpulse`
/// stores. Provider clients, sync scheduling and the WardPulse UI never start.
/// `lib/main.dart` remains the Release entry point.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  const claudeOnly =
      String.fromEnvironment('WARD_PULSE_SEED_CACHE') == 'claude-only';
  String result;
  try {
    if (!kDebugMode) throw StateError('The upgrade seed is Debug-only.');
    await _seed(claudeOnly: claudeOnly);
    result = 'Upgrade seed complete (${claudeOnly ? 'Claude-only' : 'mixed'})';
  } catch (error) {
    result = 'Upgrade seed failed: ${error.runtimeType}';
  }
  debugPrint('WardPulse: $result');
  runApp(
    Directionality(
      textDirection: TextDirection.ltr,
      child: Center(child: Text(result)),
    ),
  );
}

Future<void> _seed({required bool claudeOnly}) async {
  await SecureClaudeAccountStore().write(
    ClaudeAccountSession(
      accessToken: 'fake-seed-access',
      refreshToken: 'fake-seed-refresh',
      expiresAt: DateTime.now().toUtc().add(const Duration(days: 1)),
      accountId: 'fake-seed-account',
    ),
  );
  // The pasted token form that preceded Claude plan sign-in.
  await const FlutterSecureStorage().write(
    key: 'wardpulse.anthropic.plan.secret',
    value: 'fake-seed-pasted-token',
  );
  const claudeWindow = 'allowance.claude.claude-five-hour';
  await SecureWatchRingPreferenceStore().write(
    WatchRingPreferences(
      selectedIds: [claudePlanRingId, if (!claudeOnly) cursorOwnPoolId],
    ),
  );
  await SecurePhoneWidgetPreferenceStore().write(
    PhoneWidgetPreferences(
      selectedIds: [claudeWindow, if (!claudeOnly) cursorOwnPoolId],
    ),
  );
  await HomeWidgetPhoneWidgetSyncService.writeHomeWidgetPayload(
    PhoneWidgetPayload(
      stale: false,
      rows: [
        PhoneWidgetRow(
          label: 'Claude · 5-hour session',
          familyLabel: 'Claude',
          poolLabel: '5-hour session',
          remainingPercent: 58,
          accentArgb: phoneWidgetAccentArgb(claudeWindow),
        ),
        if (!claudeOnly)
          PhoneWidgetRow(
            label: 'Cursor Models',
            familyLabel: 'Cursor',
            poolLabel: 'Models',
            remainingPercent: 73,
            accentArgb: phoneWidgetAccentArgb(cursorOwnPoolId),
          ),
      ],
    ),
  );
}
