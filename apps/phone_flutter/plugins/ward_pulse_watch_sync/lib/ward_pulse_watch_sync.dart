import 'package:flutter/services.dart';

/// Sends WardPulse summaries through the Android Wear Data Layer.
abstract final class WardPulseWatchSync {
  static const _channel = MethodChannel('app.wardpulse/watch_sync');

  static Future<void> syncSummary(String payload) {
    return _channel.invokeMethod<void>('syncWatchSummary', payload);
  }
}
