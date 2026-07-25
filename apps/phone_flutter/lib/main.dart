import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'app/ward_pulse_app.dart';
import 'dashboard/codex_dashboard_repository.dart';
import 'dashboard/dashboard_repository.dart';
import 'dashboard/live_provider_stack.dart';
import 'dashboard/openai_dashboard_repository.dart';
import 'providers/codex_account_service.dart';
import 'providers/codex_account_store.dart';
import 'providers/provider_credential_store.dart';
import 'settings/consumption_display_preferences.dart';
import 'settings/debug_data_preferences.dart';
import 'settings/refresh_interval_preferences.dart';
import 'settings/watch_ring_preferences.dart';
import 'sync/provider_sync_scheduler.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final credentialStore = SecureProviderCredentialStore();
  final codexAccountService = MobileCodexAccountService(
    store: SecureCodexAccountStore(),
  );
  final openAiAndCodex = codexDashboardRepository(
    accountService: codexAccountService,
    fallback: openAiDashboardRepository(credentialStore: credentialStore),
  );
  final liveRepository = buildLiveProviderStack(
    credentialStore: credentialStore,
    openAiAndCodex: openAiAndCodex,
  );
  final debugDataPreferenceStore = SecureDebugDataPreferenceStore();

  runApp(
    WardPulseApp(
      credentialStore: credentialStore,
      codexAccountService: codexAccountService,
      displayPreferenceStore: SecureConsumptionDisplayPreferenceStore(),
      refreshIntervalStore: SecureRefreshIntervalPreferenceStore(),
      watchRingPreferenceStore: SecureWatchRingPreferenceStore(),
      syncScheduler: TimerProviderSyncScheduler(),
      debugDataAvailable: kDebugMode,
      debugDataPreferenceStore: debugDataPreferenceStore,
      repository:
          kDebugMode
              ? DebugDashboardRepository(
                live: liveRepository,
                preferences: debugDataPreferenceStore,
              )
              : liveRepository,
    ),
  );
}
