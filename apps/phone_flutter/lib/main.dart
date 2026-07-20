import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'app/ward_pulse_app.dart';
import 'dashboard/codex_dashboard_repository.dart';
import 'dashboard/dashboard_repository.dart';
import 'dashboard/openai_dashboard_repository.dart';
import 'providers/codex_account_service.dart';
import 'providers/codex_account_store.dart';
import 'providers/provider_credential_store.dart';
import 'settings/consumption_display_preferences.dart';
import 'settings/debug_data_preferences.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final credentialStore = SecureProviderCredentialStore();
  final codexAccountService = MobileCodexAccountService(
    store: SecureCodexAccountStore(),
  );
  final platformRepository = OpenAiDashboardRepository(
    credentialStore: credentialStore,
  );
  final liveRepository = CodexDashboardRepository(
    accountService: codexAccountService,
    fallback: platformRepository,
  );
  final debugDataPreferenceStore = SecureDebugDataPreferenceStore();

  runApp(
    WardPulseApp(
      credentialStore: credentialStore,
      codexAccountService: codexAccountService,
      displayPreferenceStore: SecureConsumptionDisplayPreferenceStore(),
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
