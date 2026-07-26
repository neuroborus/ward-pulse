import '../providers/claude_account_service.dart';
import '../providers/claude_account_store.dart';
import '../providers/codex_account_service.dart';
import '../providers/codex_account_store.dart';
import '../providers/provider_credential_store.dart';
import 'codex_dashboard_repository.dart';
import 'dashboard_repository.dart';
import 'live_provider_stack.dart';
import 'openai_dashboard_repository.dart';

/// Shared live credential + repository wiring for UI and headless sync.
final class PhoneLiveBindings {
  const PhoneLiveBindings({
    required this.credentialStore,
    required this.codexAccountService,
    required this.claudeAccountService,
    required this.repository,
  });

  final ProviderCredentialStore credentialStore;
  final CodexAccountService codexAccountService;
  final ClaudeAccountService claudeAccountService;
  final DashboardRepository repository;

  factory PhoneLiveBindings.create() {
    final credentialStore = SecureProviderCredentialStore();
    final codexAccountService = MobileCodexAccountService(
      store: SecureCodexAccountStore(),
    );
    final claudeAccountService = MobileClaudeAccountService(
      store: SecureClaudeAccountStore(),
    );
    final openAiAndCodex = codexDashboardRepository(
      accountService: codexAccountService,
      fallback: openAiDashboardRepository(credentialStore: credentialStore),
    );
    return PhoneLiveBindings(
      credentialStore: credentialStore,
      codexAccountService: codexAccountService,
      claudeAccountService: claudeAccountService,
      repository: buildLiveProviderStack(
        credentialStore: credentialStore,
        claudeAccountService: claudeAccountService,
        openAiAndCodex: openAiAndCodex,
      ),
    );
  }
}
