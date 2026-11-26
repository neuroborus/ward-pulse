import 'package:flutter/services.dart';

/// Sends WardPulse summaries through the Android Wear Data Layer.
abstract final class WardPulseWatchSync {
  static const _channel = MethodChannel('app.wardpulse/watch_sync');
  static const _confirmMethod = 'confirmWatchSummary';
  static final _confirmations = <int, Future<bool> Function()>{};
  static var _nextConfirmation = 0;

  /// Queues [payload] for Wear. With [isCurrent], the native sender asks again
  /// once Google Play services is ready, just before submission, and drops a
  /// summary whose owner no longer holds it.
  static Future<void> syncSummary(
    String payload, {
    int? generation,
    Future<bool> Function()? isCurrent,
    Map<String, Object>? selection,
  }) async {
    if (generation == null && isCurrent == null && selection == null) {
      return _channel.invokeMethod<void>('syncWatchSummary', payload);
    }
    final int? confirmation;
    if (isCurrent == null) {
      confirmation = null;
    } else {
      _channel.setMethodCallHandler(_confirm);
      confirmation = ++_nextConfirmation;
      _confirmations[confirmation] = isCurrent;
    }
    try {
      await _channel.invokeMethod<void>('syncWatchSummary', {
        'payload': payload,
        if (generation != null) 'generation': generation,
        if (confirmation != null) 'confirmation': confirmation,
        // Android proves this selection with the send claim, after
        // [isCurrent].
        if (selection != null) 'selection': selection,
      });
    } finally {
      _confirmations.remove(confirmation);
    }
  }

  static Future<Object?> _confirm(MethodCall call) async {
    if (call.method != _confirmMethod) throw MissingPluginException();
    final isCurrent = _confirmations[call.arguments];
    return isCurrent != null && await isCurrent();
  }
}
