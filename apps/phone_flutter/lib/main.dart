import 'package:flutter/widgets.dart';

import 'app/ward_pulse_app.dart';
import 'dashboard/openai_dashboard_repository.dart';
import 'providers/provider_credential_store.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final credentialStore = SecureProviderCredentialStore();

  runApp(
    WardPulseApp(
      credentialStore: credentialStore,
      repository: OpenAiDashboardRepository(credentialStore: credentialStore),
    ),
  );
}
