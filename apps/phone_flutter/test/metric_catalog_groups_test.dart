import 'package:flutter_test/flutter_test.dart';
import 'package:ward_pulse_phone/dashboard/dashboard_models.dart';
import 'package:ward_pulse_phone/settings/metric_catalog_groups.dart';
import 'package:ward_pulse_phone/settings/watch_ring_preferences.dart';

void main() {
  test('a picker heading names the connection, not the id it came from', () {
    // An allowance names its provider and a budget names its connection; both
    // are the same subscription, so both land under one heading.
    expect(metricConnectionOf('allowance.codex.codex-weekly'), (
      kind: MetricKind.plan,
      id: 'openai.plan',
      title: 'Codex',
    ));
    expect(metricConnectionOf('budget.openai.plan.today'), (
      kind: MetricKind.plan,
      id: 'openai.plan',
      title: 'Codex',
    ));
    expect(metricConnectionOf('budget.openai.platform.today'), (
      kind: MetricKind.platform,
      id: 'openai.platform',
      title: 'OpenAI',
    ));
  });

  test('a row under its heading keeps only what tells it apart', () {
    WatchRingMetric metric(String id, String label) => WatchRingMetric(
      id: id,
      label: label,
      usedPercent: 10,
      status: ProviderStatus.ok,
    );

    expect(
      metricRowTitle(metric('budget.anthropic.platform.today', 'Today')),
      'Today',
    );
    expect(
      metricRowTitle(metric('allowance.codex.codex-weekly', 'Weekly plan')),
      'Weekly plan',
    );
    // No separator to cut: the collapsed slot must not be renamed after the
    // window it happens to resolve to today.
    expect(metricRowTitle(metric(claudePlanRingId, 'Weekly')), 'Claude plan');
  });

  group('the declared connection order', () {
    WatchRingMetric metric(String id, {bool available = true}) =>
        WatchRingMetric(
          id: id,
          label: id,
          usedPercent: available ? 10 : null,
          status: ProviderStatus.ok,
          unavailableReason: available ? null : 'Nothing to show.',
        );

    List<String> connectionsUnder(
      MetricKind kind,
      List<WatchRingMetric> catalog,
    ) {
      final group = groupMetricCatalog(
        catalog,
      ).firstWhere((group) => group.title == kind.title);
      return [for (final connection in group.connections) connection.title];
    }

    test('connections sort by their id, not by the heading a reader sees', () {
      // Built Codex-first, and Claude still leads: `anthropic.plan` precedes
      // `openai.plan`, which is not the order the two headings read in.
      expect(
        connectionsUnder(MetricKind.plan, [
          metric('budget.openai.plan.today'),
          metric('budget.cursor.plan.today'),
          metric('budget.anthropic.plan.today'),
        ]),
        ['Claude', 'Cursor', 'Codex'],
      );
    });

    test('a connection with nothing to select sinks below one that has', () {
      expect(
        connectionsUnder(MetricKind.plan, [
          metric('budget.anthropic.plan.today', available: false),
          metric('budget.openai.plan.today'),
        ]),
        ['Codex', 'Claude'],
      );
    });

    test('one selectable row is enough to keep a connection up', () {
      expect(
        connectionsUnder(MetricKind.plan, [
          metric('budget.anthropic.plan.today', available: false),
          metric('budget.anthropic.plan.week'),
          metric('budget.openai.plan.today', available: false),
        ]),
        ['Claude', 'Codex'],
      );
    });

    test('a poll that only moves percentages leaves the order alone', () {
      WatchRingMetric at(String id, double percent) => WatchRingMetric(
        id: id,
        label: id,
        usedPercent: percent,
        status: ProviderStatus.ok,
      );

      final before = connectionsUnder(MetricKind.plan, [
        at('budget.openai.plan.today', 5),
        at('budget.anthropic.plan.today', 90),
      ]);
      // The two swap on every measure a reader can see, and the picker holds:
      // percentages are not one of its keys.
      final after = connectionsUnder(MetricKind.plan, [
        at('budget.openai.plan.today', 90),
        at('budget.anthropic.plan.today', 5),
      ]);

      expect(after, before);
    });

    test(
      'a provider this build does not know sorts on the provider itself',
      () {
        expect(
          connectionsUnder(MetricKind.other, [
            metric('allowance.zeta.some-window'),
            metric('allowance.alpha.some-window'),
          ]),
          ['alpha', 'zeta'],
        );
      },
    );
  });
}
