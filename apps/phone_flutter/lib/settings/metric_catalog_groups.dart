import '../dashboard/dashboard_models.dart';
import '../providers/provider_connection.dart';
import 'watch_ring_preferences.dart';

/// One connection's rows under a heading: `Codex`, `Anthropic`.
typedef MetricConnectionGroup = ({String title, List<WatchRingMetric> metrics});

/// The picker read as an outline: a kind of connection, its connections, and
/// their metrics in catalog order.
typedef MetricGroup = ({String title, List<MetricConnectionGroup> connections});

/// What kind of connection a row belongs to, in the order the pickers show —
/// declared here, not inherited from whatever order the catalog was built in. A
/// subscription is what a reader came to check, a billing key is what they came
/// to watch, and an unknown provider is neither.
enum MetricKind {
  plan('Plan'),
  platform('Platform'),
  other('Other');

  const MetricKind(this.title);

  /// Heading text for this kind.
  final String title;
}

/// Groups a metric catalog for the pickers.
///
/// A flat list of `Family · Metric` rows reads as noise once a few providers
/// are connected: the family repeats on every line and the eye has to find the
/// boundaries itself. The rows already carry them — an allowance belongs to a
/// plan connection, a budget names its own — so the pickers just show them.
List<MetricGroup> groupMetricCatalog(List<WatchRingMetric> catalog) {
  final order = <MetricKind, Map<String, List<WatchRingMetric>>>{};
  for (final metric in catalog) {
    final connection = metricConnectionOf(metric.id);
    order
        .putIfAbsent(connection.kind, () => {})
        .putIfAbsent(connection.title, () => [])
        .add(metric);
  }
  return [
    for (final kind in MetricKind.values)
      if (order[kind] case final connections?)
        (
          title: kind.title,
          connections: [
            for (final connection in connections.entries)
              (title: connection.key, metrics: connection.value),
          ],
        ),
  ];
}

/// Which heading and sub-heading a metric belongs under.
///
/// Both kinds of row resolve to the same connection: an allowance names its
/// provider (`allowance.codex.…`), a budget names the connection itself
/// (`budget.openai.plan.…`), and those are one and the same subscription. They
/// are listed together, or a reader sees one connection twice under two names.
({MetricKind kind, String title}) metricConnectionOf(String metricId) {
  final provider = providerFromRingId(metricId);
  final connection =
      connectionFromBudgetRingId(metricId) ??
      _connectionOfAllowanceProvider(provider);
  if (connection == null) {
    // A provider this build does not know yet: name it, and do not file it
    // under a kind of connection nobody established it has.
    return (
      kind: MetricKind.other,
      title: provider == null ? 'Other' : providerDisplayLabel(provider),
    );
  }
  return (
    kind: switch (connection.kind) {
      ConnectionKind.plan => MetricKind.plan,
      ConnectionKind.platform => MetricKind.platform,
    },
    title: _connectionHeading(connection),
  );
}

/// The connection an allowance belongs to, read off the provider its account
/// speaks for: `codex` is the OpenAI subscription, `openai` the reporting key
/// beside it. Today only subscriptions report allowances, but the id is built
/// from whatever provider the account carries, so both are mapped.
ProviderConnectionId? _connectionOfAllowanceProvider(String? provider) {
  return switch (provider) {
    'codex' => ProviderConnections.codexPlan,
    'openai' => ProviderConnections.openAiPlatform,
    'claude' => ProviderConnections.claudePlan,
    'anthropic' => ProviderConnections.anthropicPlatform,
    'cursor' => ProviderConnections.cursorPlan,
    _ => null,
  };
}

/// The heading above already says plan or platform, so the connection keeps the
/// name the product uses for it: the subscription by its product name (`Codex`,
/// not `OpenAI plan`), the reporting key by its family.
String _connectionHeading(ProviderConnectionId connection) {
  return switch (connection.kind) {
    ConnectionKind.platform => providerFamilyLabel(connection.provider),
    ConnectionKind.plan => switch (connection.provider) {
      ProviderFamily.openai => 'Codex',
      ProviderFamily.anthropic => 'Claude',
      ProviderFamily.cursor => 'Cursor',
    },
  };
}

/// What a row is called under its connection heading.
///
/// The heading names the connection, so the row keeps only what tells it from
/// its siblings: `Anthropic platform · Today` becomes `Today`, `Codex · Weekly
/// plan` becomes `Weekly plan`. A title with no separator stays whole — the
/// collapsed Claude slot reads `Claude plan`, and shortening it to its current
/// window would name a window the slot does not promise to keep.
String metricRowTitle(WatchRingMetric metric) {
  const separator = ' · ';
  final title = metric.catalogTitle;
  final cut = title.lastIndexOf(separator);
  return cut < 0 ? title : title.substring(cut + separator.length);
}
