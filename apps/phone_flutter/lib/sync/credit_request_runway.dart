import '../dashboard/dashboard_models.dart';

/// Internal credits-per-typical-request estimates for watch-ring **sort only**.
///
/// Not billing accuracy. UI must never show request counts — strips and glance
/// show purchased credits only. Applies when remaining unit is `credits`.
const Map<String, double> _creditsPerTypicalRequest = {
  // Balance is already in "credits"; 1.0 keeps runway ≈ remaining balance.
  'codex': 1.0,
  'claude': 1.0,
};

/// Estimated remaining request-equivalents from purchased credits for [provider].
///
/// Sort-only. Null means no secondary tightness (missing, unlimited, unknown
/// cost, or non-credits units) — the sorter treats that as +∞ versus a finite
/// runway.
double? creditRequestRunwayForProvider(
  DashboardSnapshot snapshot,
  String provider,
) {
  final cost = _creditsPerTypicalRequest[provider];
  if (cost == null || !cost.isFinite || cost <= 0) {
    return null;
  }

  final remaining = purchasedCreditsRemainingForProvider(snapshot, provider);
  if (remaining == null) {
    return null;
  }
  return remaining / cost;
}

/// Finite purchased `credits` remaining for one provider, or null.
///
/// Shared by watch-ring sort and phone home-widget Glance-style suffixes.
/// Unlimited purchased balances return null (no numeric credits line).
double? purchasedCreditsRemainingForProvider(
  DashboardSnapshot snapshot,
  String provider,
) {
  double total = 0;
  var sawFinite = false;

  for (final account in snapshot.accounts) {
    if (account.provider != provider) {
      continue;
    }
    for (final allowance in account.allowances) {
      if (allowance.source != AllowanceSource.purchased) {
        continue;
      }
      if (allowance.unlimited) {
        return null;
      }
      final remaining = allowance.remaining;
      if (remaining == null || remaining.unit != 'credits') {
        continue;
      }
      final value = double.tryParse(remaining.value);
      if (value == null || !value.isFinite || value < 0) {
        continue;
      }
      total += value;
      sawFinite = true;
    }
  }

  if (!sawFinite) {
    return null;
  }
  return total;
}
