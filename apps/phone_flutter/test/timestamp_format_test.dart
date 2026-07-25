import 'package:flutter_test/flutter_test.dart';
import 'package:ward_pulse_phone/dashboard/dashboard_models.dart';

void main() {
  test('formatLocal uses the device timezone without a UTC suffix', () {
    final value = DateTime.utc(2026, 7, 25, 18, 42, 0);

    expect(formatLocal(value), isNot(contains('UTC')));
    expect(formatLocal(value), matches(RegExp(r'^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$')));
  });

  test('formatUtc keeps an explicit UTC label for disclosure', () {
    final value = DateTime.utc(2026, 7, 25, 18, 42, 0);

    expect(formatUtc(value), '2026-07-25 18:42:00 UTC');
  });
}
