import 'package:flutter_test/flutter_test.dart';
import 'package:ward_pulse_phone/app/surface_order.dart';
import 'package:ward_pulse_phone/dashboard/dashboard_models.dart';

void main() {
  Money usd(int minorUnits) => Money(minorUnits: minorUnits, currency: 'USD');

  group('status', () {
    test('the worse status comes first', () {
      expect(
        compareByStatus(ProviderStatus.error, ProviderStatus.ok),
        lessThan(0),
      );
      expect(
        compareByStatus(ProviderStatus.ok, ProviderStatus.error),
        greaterThan(0),
      );
    });

    test('a status reported by nobody still outranks a healthy one', () {
      expect(
        compareByStatus(ProviderStatus.unknown, ProviderStatus.ok),
        lessThan(0),
      );
    });

    test('the same status ties, leaving the next key to decide', () {
      expect(
        compareByStatus(ProviderStatus.warning, ProviderStatus.warning),
        0,
      );
    });
  });

  group('spend', () {
    test('the larger amount comes first', () {
      expect(compareBySpend(usd(100), usd(900)), greaterThan(0));
      expect(compareBySpend(usd(900), usd(100)), lessThan(0));
    });

    test('nothing spent reads as zero rather than as missing', () {
      expect(compareBySpend(null, usd(1)), greaterThan(0));
      expect(compareBySpend(null, null), 0);
      expect(compareBySpend(null, usd(0)), 0);
    });

    test('two currencies tie: the device has no exchange rate', () {
      expect(
        compareBySpend(Money(minorUnits: 100000, currency: 'JPY'), usd(5000)),
        0,
      );
    });
  });

  group('frozen order', () {
    test('holds its order while the same keys come back reranked', () {
      final order = FrozenOrder();

      expect(order.hold(['codex', 'claude', 'cursor']), [
        'codex',
        'claude',
        'cursor',
      ]);
      // Spend moved and the ranking flipped; the reader's list must not.
      expect(order.hold(['cursor', 'claude', 'codex']), [
        'codex',
        'claude',
        'cursor',
      ]);
    });

    test('does not move when the caller reorders the list it handed in', () {
      final order = FrozenOrder();
      final ranked = ['codex', 'claude'];

      order.hold(ranked);
      ranked.sort();

      expect(order.hold(['claude', 'codex']), ['codex', 'claude']);
    });

    test('takes the new order once a key joins or leaves', () {
      final order = FrozenOrder();
      order.hold(['codex', 'claude']);

      expect(order.hold(['cursor', 'codex', 'claude']), [
        'cursor',
        'codex',
        'claude',
      ]);
      // And keeps the fresh one from then on.
      expect(order.hold(['claude', 'codex', 'cursor']), [
        'cursor',
        'codex',
        'claude',
      ]);
      expect(order.hold(['codex']), ['codex']);
    });
  });
}
