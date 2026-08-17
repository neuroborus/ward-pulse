import '../dashboard/plan_recoveries.dart';

/// Tells the reader a plan window is usable again.
///
/// An interface, not a channel call, for the same reason `WatchSyncService` is
/// one: host tests carry no Android to post to.
abstract interface class RecoveryNotifier {
  Future<void> notify(PlanRecovery recovery);
}

/// Says nothing, for hosts with nowhere to say it: tests, and any build without
/// the Android side wired up.
final class SilentRecoveryNotifier implements RecoveryNotifier {
  const SilentRecoveryNotifier();

  @override
  Future<void> notify(PlanRecovery recovery) async {}
}
