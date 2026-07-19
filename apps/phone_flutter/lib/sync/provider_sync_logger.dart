import 'dart:developer' as developer;

enum ProviderSyncEvent {
  skippedNoCredential,
  succeeded,
  authenticationRequired,
  rateLimited,
  unavailable,
  invalidResponse,
  usingCachedSnapshot,
}

abstract interface class ProviderSyncLogger {
  void record(ProviderSyncEvent event);
}

final class DeveloperProviderSyncLogger implements ProviderSyncLogger {
  const DeveloperProviderSyncLogger();

  @override
  void record(ProviderSyncEvent event) {
    developer.log(event.name, name: 'WardPulse.ProviderSync');
  }
}

final class NullProviderSyncLogger implements ProviderSyncLogger {
  const NullProviderSyncLogger();

  @override
  void record(ProviderSyncEvent event) {}
}
