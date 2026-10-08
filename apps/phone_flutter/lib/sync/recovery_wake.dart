import 'package:workmanager/workmanager.dart';

import 'headless_provider_sync.dart';

/// Wakes the phone when a spent plan window is due to roll.
///
/// One wake, not one per window: whatever poll runs on waking checks every
/// window at once, so the earliest reset is the only instant worth booking —
/// the rest book themselves on that same pass.
abstract interface class RecoveryWakeScheduler {
  Future<void> scheduleAt(DateTime resetsAt);

  Future<void> cancel();
}

/// Books the wake with WorkManager, which the headless poll already runs on.
///
/// An exact alarm would be the obvious tool and is not available to this app:
/// `SCHEDULE_EXACT_ALARM` is granted to alarms and calendars. A delayed task
/// fires inside the system's own window instead, which is what "scheduled from
/// the reset instant rather than found by polling" means here.
final class WorkmanagerRecoveryWakeScheduler implements RecoveryWakeScheduler {
  const WorkmanagerRecoveryWakeScheduler();

  static const uniqueName = 'wardpulse.recoveryWake';
  static const taskName = 'recoveryWake';

  @override
  Future<void> scheduleAt(DateTime resetsAt) async {
    if (!isAndroidHost) {
      return;
    }
    final delay = resetsAt.difference(DateTime.now());
    await Workmanager().registerOneOffTask(
      uniqueName,
      taskName,
      initialDelay: delay.isNegative ? Duration.zero : delay,
      // Replace, because the default for a one-off task is KEEP: a window whose
      // reset moved would otherwise keep the wake booked for the old instant.
      existingWorkPolicy: ExistingWorkPolicy.replace,
      constraints: Constraints(networkType: NetworkType.connected),
    );
  }

  @override
  Future<void> cancel() async {
    if (!isAndroidHost) {
      return;
    }
    await Workmanager().cancelByUniqueName(uniqueName);
  }
}

/// Books nothing, for hosts with no scheduler: tests, and any build where the
/// poll is driven by hand.
final class DisabledRecoveryWakeScheduler implements RecoveryWakeScheduler {
  const DisabledRecoveryWakeScheduler();

  @override
  Future<void> scheduleAt(DateTime resetsAt) async {}

  @override
  Future<void> cancel() async {}
}
