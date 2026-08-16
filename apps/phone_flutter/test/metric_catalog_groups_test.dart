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
      title: 'Codex',
    ));
    expect(metricConnectionOf('budget.openai.plan.today'), (
      kind: MetricKind.plan,
      title: 'Codex',
    ));
    expect(metricConnectionOf('budget.openai.platform.today'), (
      kind: MetricKind.platform,
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
}
