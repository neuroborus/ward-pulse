/// Homogeneous phone-side connection identity for Settings and display metadata.
///
/// Each provider exposes up to two connection kinds (`plan` and `platform`). The
/// optional [displayName] is plain metadata for API-key connections and feeds
/// the product `ProviderAccount.display_name` concept without traveling to the
/// watch or into secure credential values.
enum ProviderFamily { openai, anthropic, cursor }

enum ConnectionKind { plan, platform }

final class ProviderConnectionId {
  const ProviderConnectionId({required this.provider, required this.kind});

  final ProviderFamily provider;
  final ConnectionKind kind;

  String get storageKey => '${provider.name}.${kind.name}';
}

final class ProviderConnection {
  const ProviderConnection({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.supported,
    this.displayName,
  });

  final ProviderConnectionId id;
  final String title;
  final String subtitle;
  final bool supported;

  /// Optional user-defined label for platform API-key connections.
  final String? displayName;

  String get listTitle {
    final label = displayName?.trim();
    if (label != null && label.isNotEmpty) {
      return label;
    }
    return title;
  }
}

/// Canonical connection catalog shown in Settings.
List<ProviderConnection> providerConnectionCatalog({
  String? openAiPlatformLabel,
}) {
  return [
    const ProviderConnection(
      id: ProviderConnectionId(
        provider: ProviderFamily.openai,
        kind: ConnectionKind.plan,
      ),
      title: 'Codex subscription',
      subtitle: 'Experimental · plan limits and token activity',
      supported: true,
    ),
    ProviderConnection(
      id: const ProviderConnectionId(
        provider: ProviderFamily.openai,
        kind: ConnectionKind.platform,
      ),
      title: 'Platform reporting',
      subtitle: 'Admin API key · stored on this phone',
      supported: true,
      displayName: openAiPlatformLabel,
    ),
    const ProviderConnection(
      id: ProviderConnectionId(
        provider: ProviderFamily.anthropic,
        kind: ConnectionKind.plan,
      ),
      title: 'Claude subscription',
      subtitle: 'Not yet supported',
      supported: false,
    ),
    const ProviderConnection(
      id: ProviderConnectionId(
        provider: ProviderFamily.anthropic,
        kind: ConnectionKind.platform,
      ),
      title: 'Organization reporting',
      subtitle: 'Not yet supported',
      supported: false,
    ),
    const ProviderConnection(
      id: ProviderConnectionId(
        provider: ProviderFamily.cursor,
        kind: ConnectionKind.plan,
      ),
      title: 'Cursor plan',
      subtitle: 'Not yet supported',
      supported: false,
    ),
    const ProviderConnection(
      id: ProviderConnectionId(
        provider: ProviderFamily.cursor,
        kind: ConnectionKind.platform,
      ),
      title: 'Team Admin API',
      subtitle: 'Not yet supported',
      supported: false,
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
