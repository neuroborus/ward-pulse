import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../providers/connection_lifecycle.dart';
import '../providers/provider_connection.dart';
import 'connection_snapshot_cache.dart';
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

  factory PhoneLiveBindings.create({
    FlutterSecureStorage? secureStorage,
    ConnectionCachePlatform? cachePlatform,
  }) {
    final platform =
        cachePlatform ?? const MethodChannelConnectionCachePlatform();
    final credentialStore = SecureProviderCredentialStore(
      storage: secureStorage,
      platform: platform,
    );
    final codexStore = SecureCodexAccountStore(
      storage: secureStorage,
      platform: platform,
    );
    final claudeStore = SecureClaudeAccountStore(
      storage: secureStorage,
      platform: platform,
    );
    final caches = <String, ConnectionSnapshotCache>{};
    for (final id in [
      ProviderConnections.codexPlan,
      ProviderConnections.openAiPlatform,
      ProviderConnections.claudePlan,
      ProviderConnections.anthropicPlatform,
      ProviderConnections.cursorPlan,
      ProviderConnections.cursorPlatform,
    ]) {
      caches[id.storageKey] = ConnectionSnapshotCache(
        connection: id.storageKey,
        platform: platform,
        readCredentialVersion: () async {
          if (id == ProviderConnections.codexPlan)
            return (await codexStore.readVersioned())?.version;
          if (id == ProviderConnections.claudePlan)
            return (await claudeStore.readVersioned())?.version;
          return credentialStore.readVersion(id);
        },
      );
    }
    final codexAccountService = MobileCodexAccountService(store: codexStore);
    final claudeAccountService = MobileClaudeAccountService(store: claudeStore);
    final openAiAndCodex = codexDashboardRepository(
      accountService: codexAccountService,
      cache: caches[ProviderConnections.codexPlan.storageKey],
      fallback: openAiDashboardRepository(
        credentialStore: credentialStore,
        cache: caches[ProviderConnections.openAiPlatform.storageKey],
      ),
    );
    return PhoneLiveBindings(
      credentialStore: credentialStore,
      codexAccountService: codexAccountService,
      claudeAccountService: claudeAccountService,
      repository: buildLiveProviderStack(
        caches: caches,
        credentialStore: credentialStore,
        claudeAccountService: claudeAccountService,
        openAiAndCodex: openAiAndCodex,
      ),
    );
  }
}
