import 'dart:developer' as developer;

enum ProviderSyncEvent {
  skippedNoCredential,
  succeeded,
  authenticationRequired,
  permissionDenied,
  rateLimited,
  unavailable,
  invalidResponse,
  usingCachedSnapshot,
}

abstract interface class ProviderSyncLogger {
  void record(ProviderSyncEvent event, {String? details});
}

final class DeveloperProviderSyncLogger implements ProviderSyncLogger {
  const DeveloperProviderSyncLogger();

  @override
  void record(ProviderSyncEvent event, {String? details}) {
    developer.log(
      details == null ? event.name : '${event.name}: $details',
      name: 'WardPulse.ProviderSync',
    );
  }
}

final class NullProviderSyncLogger implements ProviderSyncLogger {
  const NullProviderSyncLogger();

  @override
  void record(ProviderSyncEvent event, {String? details}) {}
}
