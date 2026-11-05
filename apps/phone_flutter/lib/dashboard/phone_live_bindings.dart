import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../providers/connection_lifecycle.dart';
import '../providers/provider_connection.dart';
import '../providers/connection_rejection_notice.dart';
import '../sync/claude_account_client.dart';
import '../sync/codex_account_client.dart';
import '../sync/openai_reporting_client.dart';
import '../sync/provider_reporting_clients.dart';
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
    this.rejectionNotices = const NativeConnectionRejectionNoticeStore(),
  });

  final ProviderCredentialStore credentialStore;
  final CodexAccountService codexAccountService;
  final ClaudeAccountService claudeAccountService;
  final DashboardRepository repository;
  final ConnectionRejectionNoticeStore rejectionNotices;

  factory PhoneLiveBindings.create({
    FlutterSecureStorage? secureStorage,
    ConnectionCachePlatform? cachePlatform,
    CodexAccountClient? codexClient,
    ClaudeAccountClient? claudeClient,
    OpenAiReportingClient? openAiClient,
    AnthropicReportingClient? anthropicClient,
    CursorPlanClient? cursorClient,
    CursorPlatformClient? cursorReportingClient,
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
    final codexAccountService = MobileCodexAccountService(
      store: codexStore,
      client: codexClient,
    );
    final claudeAccountService = MobileClaudeAccountService(
      store: claudeStore,
      client: claudeClient,
    );
    final openAiAndCodex = codexDashboardRepository(
      accountService: codexAccountService,
      cache: caches[ProviderConnections.codexPlan.storageKey],
      fallback: openAiDashboardRepository(
        credentialStore: credentialStore,
        client: openAiClient,
        cache: caches[ProviderConnections.openAiPlatform.storageKey],
      ),
    );
    return PhoneLiveBindings(
      rejectionNotices: NativeConnectionRejectionNoticeStore(
        platform: platform,
      ),
      credentialStore: credentialStore,
      codexAccountService: codexAccountService,
      claudeAccountService: claudeAccountService,
      repository: buildLiveProviderStack(
        caches: caches,
        anthropicReportingClient: anthropicClient,
        cursorSessionClient: cursorClient,
        cursorReportingClient: cursorReportingClient,
        credentialStore: credentialStore,
        claudeAccountService: claudeAccountService,
        openAiAndCodex: openAiAndCodex,
      ),
    );
  }
}
