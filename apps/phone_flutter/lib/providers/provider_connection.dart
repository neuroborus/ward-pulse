import '../sync/poll_cadence.dart';

/// Homogeneous phone-side connection identity for Settings and display metadata.
///
/// Each provider exposes up to two connection kinds (`plan` and `platform`). The
/// optional [ProviderConnection.displayName] is plain metadata for API-key
/// connections and feeds the product `ProviderAccount.display_name` concept
/// without traveling to the watch or into secure credential values.
enum ProviderFamily { openai, anthropic, cursor }

enum ConnectionKind { plan, platform }

final class ProviderConnectionId {
  const ProviderConnectionId({required this.provider, required this.kind});

  final ProviderFamily provider;
  final ConnectionKind kind;

  String get storageKey => '${provider.name}.${kind.name}';

  /// Inverse of [storageKey]; null when the key names no known connection.
  static ProviderConnectionId? fromStorageKey(String key) {
    final parts = key.split('.');
    if (parts.length != 2) {
      return null;
    }
    final provider = ProviderFamily.values.asNameMap()[parts.first];
    final kind = ConnectionKind.values.asNameMap()[parts.last];
    if (provider == null || kind == null) {
      return null;
    }
    return ProviderConnectionId(provider: provider, kind: kind);
  }

  @override
  bool operator ==(Object other) =>
      other is ProviderConnectionId &&
      other.provider == provider &&
      other.kind == kind;

  @override
  int get hashCode => Object.hash(provider, kind);
}

/// Canonical connection identities shared by Settings, storage, and sync.
abstract final class ProviderConnections {
  static const codexPlan = ProviderConnectionId(
    provider: ProviderFamily.openai,
    kind: ConnectionKind.plan,
  );
  static const openAiPlatform = ProviderConnectionId(
    provider: ProviderFamily.openai,
    kind: ConnectionKind.platform,
  );
  static const claudePlan = ProviderConnectionId(
    provider: ProviderFamily.anthropic,
    kind: ConnectionKind.plan,
  );
  static const anthropicPlatform = ProviderConnectionId(
    provider: ProviderFamily.anthropic,
    kind: ConnectionKind.platform,
  );
  static const cursorPlan = ProviderConnectionId(
    provider: ProviderFamily.cursor,
    kind: ConnectionKind.plan,
  );
  static const cursorPlatform = ProviderConnectionId(
    provider: ProviderFamily.cursor,
    kind: ConnectionKind.platform,
  );
}

final class ProviderConnection {
  const ProviderConnection({
    required this.id,
    required this.title,
    required this.subtitle,
    this.secretHint,
    this.displayName,
    this.freshnessNote,
  });

  final ProviderConnectionId id;
  final String title;
  final String subtitle;

  /// Input hint for connections authorized by a pasted secret.
  ///
  /// `null` marks a connection that WardPulse authorizes another way, such as
  /// the Codex subscription sign-in.
  final String? secretHint;

  /// Optional user-defined label for platform API-key connections.
  final String? displayName;

  /// Non-clamping provider freshness guidance shown on the Settings row.
  final String? freshnessNote;

  String get listTitle {
    final label = displayName?.trim();
    if (label != null && label.isNotEmpty) {
      return label;
    }
    return title;
  }

  String get listSubtitle {
    final note = freshnessNote?.trim();
    if (note == null || note.isEmpty) {
      return subtitle;
    }
    return '$subtitle\n$note';
  }
}

/// Canonical connection catalog shown on the Providers tab.
///
/// [platformLabels] holds stored labels keyed by
/// [ProviderConnectionId.storageKey].
List<ProviderConnection> providerConnectionCatalog({
  Map<String, String?> platformLabels = const {},
}) {
  return [
    const ProviderConnection(
      id: ProviderConnections.codexPlan,
      title: 'Codex subscription',
      subtitle: 'Experimental · plan limits and token activity',
    ),
    ProviderConnection(
      id: ProviderConnections.openAiPlatform,
      title: 'Platform reporting',
      subtitle: 'Admin API key · stored on this phone',
      secretHint: 'sk-admin-…',
      displayName:
          platformLabels[ProviderConnections.openAiPlatform.storageKey],
    ),
    const ProviderConnection(
      id: ProviderConnections.claudePlan,
      title: 'Claude subscription',
      subtitle: 'Experimental · Claude Code OAuth sign-in',
    ),
    ProviderConnection(
      id: ProviderConnections.anthropicPlatform,
      title: 'Organization reporting',
      subtitle: 'Admin API key · stored on this phone',
      secretHint: 'API key',
      displayName:
          platformLabels[ProviderConnections.anthropicPlatform.storageKey],
    ),
    const ProviderConnection(
      id: ProviderConnections.cursorPlan,
      title: 'Cursor plan',
      subtitle: 'Experimental · dashboard sign-in',
    ),
    ProviderConnection(
      id: ProviderConnections.cursorPlatform,
      title: 'Team Admin API',
      subtitle: 'Admin API key · teams and enterprise',
      secretHint: 'API key',
      displayName:
          platformLabels[ProviderConnections.cursorPlatform.storageKey],
      freshnessNote: PollCadence.cursorFreshnessNote,
    ),
  ];
}

String providerFamilyLabel(ProviderFamily provider) {
  return switch (provider) {
    ProviderFamily.openai => 'OpenAI',
    ProviderFamily.anthropic => 'Anthropic',
    ProviderFamily.cursor => 'Cursor',
  };
}

/// Sentence case, to follow a family label (`Anthropic platform`, `Cursor plan`).
String connectionKindLabel(ConnectionKind kind) {
  return switch (kind) {
    ConnectionKind.plan => 'plan',
    ConnectionKind.platform => 'platform',
  };
}
