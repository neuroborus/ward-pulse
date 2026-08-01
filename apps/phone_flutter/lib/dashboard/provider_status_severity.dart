import 'dashboard_models.dart';

/// Most severe status, or `unknown` when there is nothing to judge.
///
/// Mirrors `ProviderStatus::worst` in `core/ward-pulse-core/src/model/mod.rs`.
/// `provider_status_severity_test.dart` reads that source and fails if the two
/// orders drift apart.
ProviderStatus worstProviderStatus(Iterable<ProviderStatus> statuses) {
  if (statuses.isEmpty) {
    return ProviderStatus.unknown;
  }
  return statuses.reduce(
    (worst, status) => _severity(status) > _severity(worst) ? status : worst,
  );
}

/// Aggregation rank. Ranks are distinct, so [worstProviderStatus] never depends
/// on input order. `unknown` outranks `ok`: a surface that reported nothing must
/// not read as healthy.
int _severity(ProviderStatus status) {
  return switch (status) {
    ProviderStatus.ok => 1,
    ProviderStatus.unknown => 2,
    ProviderStatus.stale => 3,
    ProviderStatus.warning => 4,
    ProviderStatus.rateLimited => 5,
    ProviderStatus.authRequired => 6,
    ProviderStatus.error => 7,
  };
}
