import '../dashboard/dashboard_models.dart';
import '../dashboard/provider_status_severity.dart';

/// Worst status first: a provider asking for attention outranks a healthy one.
///
/// Ranked by the one scale the product has — [providerStatusSeverity], mirrored
/// from the Rust core. Naming "the bad ones" here instead is how five
/// disagreeing status scales appeared once already.
int compareByStatus(ProviderStatus left, ProviderStatus right) {
  return providerStatusSeverity(right).compareTo(providerStatusSeverity(left));
}

/// Larger spend first, reading `null` as nothing spent.
///
/// Amounts compare only inside one currency: the core refuses to add across
/// them (`MoneyTotal::add` in `core/ward-pulse-core/src/dashboard/mod.rs`) and
/// the device carries no exchange rate, so two currencies tie here and the next
/// key decides. Nothing spent has no currency of its own and compares against
/// any amount.
int compareBySpend(Money? left, Money? right) {
  if (left != null && right != null && left.currency != right.currency) {
    return 0;
  }
  return (right?.minorUnits ?? 0).compareTo(left?.minorUnits ?? 0);
}

/// An order that moves only when the rows themselves change.
///
/// A key that shifts on every poll — spend on the Dashboard — would slide a
/// card out from under the reader's finger. So a ranking is computed once for a
/// given set of keys and held, and a new ranking is taken only when that set
/// differs.
///
/// What counts as a change is therefore the caller's to state: it writes into
/// each key exactly what must rerank the list — the row's identity, plus the
/// state it reports — and leaves out the figures this class exists to absorb.
///
/// Keys, not rows: a tab can hold an order without handing over the private
/// widgets it builds from it.
class FrozenOrder {
  List<String>? _held;

  /// The order to render — the held one for as long as [ranked] names the same
  /// keys, whatever their new positions are.
  ///
  /// [ranked] carries one key per row: a repeated key would be a row counted
  /// twice by the caller rather than an order to hold.
  List<String> hold(List<String> ranked) {
    final held = _held;
    if (held != null &&
        held.length == ranked.length &&
        held.toSet().containsAll(ranked)) {
      return held;
    }
    // Copied, and unmodifiable on the way out: an order this class exists to
    // keep still must not be sortable through the list it was handed.
    return _held = List.unmodifiable(ranked);
  }
}
