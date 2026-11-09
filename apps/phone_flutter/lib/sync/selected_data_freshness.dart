import '../dashboard/dashboard_models.dart';

/// Phone-local provenance for a value actually displayed by a surface.
typedef SurfaceDataContributor =
    ({ProviderSnapshot account, ProviderStatus status});

/// Retained accounts can be stale while their last successful metrics stay OK.
/// Aggregate status is useful only when there are no displayed contributors.
bool selectedDataIsStale(
  DashboardSnapshot snapshot,
  Iterable<SurfaceDataContributor> contributors,
) {
  var hasContributors = false;
  for (final contributor in contributors) {
    hasContributors = true;
    if (contributor.account.status == ProviderStatus.stale ||
        contributor.status == ProviderStatus.stale) {
      return true;
    }
  }
  return !hasContributors && snapshot.overallStatus == ProviderStatus.stale;
}
