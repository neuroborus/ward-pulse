import 'package:flutter/widgets.dart';

import '../dashboard/phone_live_bindings.dart';
import '../settings/consumption_display_preferences.dart';
import '../settings/watch_ring_preferences.dart';
import 'watch_sync_service.dart';

/// One provider sync + watch push with no UI (headless WorkManager tick).
///
/// Failures are swallowed so a background tick never crashes the host.
Future<void> providerSyncOnce() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    final live = PhoneLiveBindings.create();
    final displayPreferences =
        await SecureConsumptionDisplayPreferenceStore().read();
    final ringPreferences = await SecureWatchRingPreferenceStore().read();
    final snapshot = await live.repository.load();
    await const MethodChannelWatchSyncService().sync(
      snapshot,
      displayPreferences,
      ringPreferences,
    );
  } catch (_) {
    // Automatic / headless sync keeps the last successful snapshot visible.
  }
}
