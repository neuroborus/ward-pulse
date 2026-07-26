import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ward_pulse_phone/providers/claude_account_service.dart';
import 'package:ward_pulse_phone/providers/codex_account_service.dart';
import 'package:ward_pulse_phone/providers/provider_connection.dart';
import 'package:ward_pulse_phone/providers/provider_credential_store.dart';
import 'package:ward_pulse_phone/settings/consumption_display_preferences.dart';
import 'package:ward_pulse_phone/settings/refresh_interval_preferences.dart';
import 'package:ward_pulse_phone/settings/settings_screen.dart';
import 'package:ward_pulse_phone/settings/watch_ring_preferences.dart';

void main() {
  testWidgets('Cursor plan row shows Not connected and help Advanced paste', (
    tester,
  ) async {
    final store = _MemoryCredentialStore();
    var credentialsChanged = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SettingsScreen(
            snapshot: null,
            credentialStore: store,
            codexAccountService: const EmptyCodexAccountService(),
            claudeAccountService: const EmptyClaudeAccountService(),
            displayPreferences: const ConsumptionDisplayPreferences(),
            onDisplayPreferencesChanged: (_) async {},
            refreshInterval: const RefreshIntervalPreference(),
            onRefreshIntervalChanged: (_) async {},
            ringPreferences: const WatchRingPreferences(),
            onRingPreferencesChanged: (_) async {},
            onSyncWatch: () async {},
            debugDataAvailable: false,
            mockDataEnabled: false,
            onMockDataEnabledChanged: (_) async {},
            onCredentialsChanged: () => credentialsChanged++,
            cursorPlanSignIn: (_) async => null,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('Cursor plan'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    expect(find.text('Cursor plan'), findsOneWidget);
    expect(find.text('Experimental · dashboard sign-in'), findsOneWidget);
    expect(find.text('Not connected'), findsWidgets);

    await tester.tap(find.byTooltip('About Cursor sign-in'));
    await tester.pumpAndSettle();

    expect(find.text('Cursor sign-in'), findsOneWidget);
    expect(find.text('Advanced paste'), findsOneWidget);
    await tester.tap(find.text('Advanced paste'));
    await tester.pumpAndSettle();

    expect(find.text('Cursor plan · Paste token'), findsOneWidget);
    const pasted =
        'user_01TEST::eyJhbGciOiJSUzI1NiJ9.payload.signature_padding==';
    await tester.enterText(find.byType(TextFormField).first, pasted);
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(await store.readSecret(ProviderConnections.cursorPlan), pasted);
    expect(credentialsChanged, 1);
    expect(find.text('Connected'), findsWidgets);
  });

  testWidgets('Cursor plan Sign in uses injected port and marks Connected', (
    tester,
  ) async {
    final store = _MemoryCredentialStore();
    var signInCalls = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SettingsScreen(
            snapshot: null,
            credentialStore: store,
            codexAccountService: const EmptyCodexAccountService(),
            claudeAccountService: const EmptyClaudeAccountService(),
            displayPreferences: const ConsumptionDisplayPreferences(),
            onDisplayPreferencesChanged: (_) async {},
            refreshInterval: const RefreshIntervalPreference(),
            onRefreshIntervalChanged: (_) async {},
            ringPreferences: const WatchRingPreferences(),
            onRingPreferencesChanged: (_) async {},
            onSyncWatch: () async {},
            debugDataAvailable: false,
            mockDataEnabled: false,
            onMockDataEnabledChanged: (_) async {},
            onCredentialsChanged: () {},
            cursorPlanSignIn: (_) async {
              signInCalls++;
              return 'user_01WEB::eyJhbGciOiJSUzI1NiJ9.payload.signature_padding==';
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('Cursor plan'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cursor plan'));
    await tester.pumpAndSettle();

    expect(signInCalls, 1);
    expect(
      await store.readSecret(ProviderConnections.cursorPlan),
      'user_01WEB::eyJhbGciOiJSUzI1NiJ9.payload.signature_padding==',
    );
    expect(find.text('Connected'), findsWidgets);
  });
}

class _MemoryCredentialStore implements ProviderCredentialStore {
  final _secrets = <ProviderConnectionId, String>{};
  final _labels = <ProviderConnectionId, String>{};

  @override
  Future<String?> readSecret(ProviderConnectionId id) async => _secrets[id];

  @override
  Future<void> writeSecret(ProviderConnectionId id, String value) async {
    _secrets[id] = value;
  }

  @override
  Future<void> deleteSecret(ProviderConnectionId id) async {
    _secrets.remove(id);
    _labels.remove(id);
  }

  @override
  Future<String?> readLabel(ProviderConnectionId id) async => _labels[id];

  @override
  Future<void> writeLabel(ProviderConnectionId id, String? value) async {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      _labels.remove(id);
      return;
    }
    _labels[id] = trimmed;
  }
}
