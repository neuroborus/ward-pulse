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
import '../providers/claude_plan_pause.dart';
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
    this.claudePlanPaused = claudePlanPausedInBuild,
    Future<void> Function()? retireClaudePlan,
  }) : _retireClaudePlan = retireClaudePlan;

  final ProviderCredentialStore credentialStore;
  final CodexAccountService codexAccountService;
  final ClaudeAccountService claudeAccountService;
  final DashboardRepository repository;
  final ConnectionRejectionNoticeStore rejectionNotices;

  /// Whether this build pauses Claude plan; see [claudePlanPausedInBuild].
  final bool claudePlanPaused;
  final Future<void> Function()? _retireClaudePlan;

  /// Locally retires a saved Claude plan credential while the build pauses it.
  ///
  /// The foreground app and headless sync share this one path. A failure never
  /// reaches startup or other sources; a later run retries.
  Future<void> retirePausedClaudePlan() async {
    try {
      await _retireClaudePlan?.call();
    } catch (_) {
      // Durable native cleanup state stays queued for the next run.
    }
  }

  /// [claudePlanPaused] defaults to the build policy; tests pass it explicitly.
  factory PhoneLiveBindings.create({
    bool claudePlanPaused = claudePlanPausedInBuild,
    FlutterSecureStorage? secureStorage,
    ConnectionCachePlatform? cachePlatform,
    CodexAccountClient? codexClient,
    ClaudeAccountClient? claudeClient,
    OpenAiReportingClient? openAiClient,
    AnthropicReportingClient? anthropicClient,
    CursorPlanClient? cursorClient,
    CursorPlatformClient? cursorReportingClient,
    DateTime Function()? clock,
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
      if (!claudePlanPaused) ProviderConnections.claudePlan,
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
    // Paused builds keep the no-network service and register no Claude source.
    final ClaudeAccountService claudeAccountService =
        claudePlanPaused
            ? const EmptyClaudeAccountService()
            : MobileClaudeAccountService(
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
        hidden: {if (claudePlanPaused) ProviderConnections.claudePlan},
      ),
      credentialStore: credentialStore,
      codexAccountService: codexAccountService,
      claudeAccountService: claudeAccountService,
      claudePlanPaused: claudePlanPaused,
      retireClaudePlan: claudePlanPaused ? claudeStore.retire : null,
      repository: buildLiveProviderStack(
        clock: clock,
        caches: caches,
        anthropicReportingClient: anthropicClient,
        cursorSessionClient: cursorClient,
        cursorReportingClient: cursorReportingClient,
        credentialStore: credentialStore,
        claudeAccountService: claudePlanPaused ? null : claudeAccountService,
        openAiAndCodex: openAiAndCodex,
      ),
    );
  }
}
