import 'package:flutter/services.dart';

/// Sends WardPulse summaries through the Android Wear Data Layer.
abstract final class WardPulseWatchSync {
  static const _channel = MethodChannel('app.wardpulse/watch_sync');
  static const _confirmMethod = 'confirmWatchSummary';
  static final _confirmations = <int, Future<bool> Function()>{};
  static var _nextConfirmation = 0;

  /// Queues [payload], the v9 projection, for Wear. [summary] is the v10 body
  /// of a scoped publication; Android derives it from [payload] otherwise and
  /// adds its owner and order. With [isCurrent], the native sender asks again
  /// once Google Play services is ready, just before submission, and fails a
  /// summary whose owner no longer holds it with `watch_summary_superseded`.
  /// With [load], a newer accepted
  /// load or a settings save after [settingsRevision] fails it with
  /// `watch_summary_superseded` before it is persisted, and keeps any later
  /// put of it from being sent.
  static Future<void> syncSummary(
    String payload, {
    String? summary,
    int? generation,
    Future<bool> Function()? isCurrent,
    Map<String, Object>? selection,
    int? load,
    int? settingsRevision,
  }) async {
    if (summary == null &&
        generation == null &&
        isCurrent == null &&
        selection == null &&
        load == null) {
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
        if (summary != null) 'summary': summary,
        if (generation != null) 'generation': generation,
        if (confirmation != null) 'confirmation': confirmation,
        // Android proves this selection with the send claim, after
        // [isCurrent].
        if (selection != null) 'selection': selection,
        // The accepted load and settled settings revision the summary was
        // built from; Android refuses it once either is replaced.
        if (load != null) ...{
          'load': load,
          'settingsRevision': settingsRevision ?? -1,
        },
      });
    } finally {
      _confirmations.remove(confirmation);
    }
  }

  /// Whether the desired Data Item is a v10 summary of the current data-mode
  /// generation, rather than absent or the empty summary a transition left.
  /// Asking resumes a pending or retrying native send.
  static Future<bool> isSummaryEstablished() async =>
      await _channel.invokeMethod<bool>('watchSummaryEstablished') ?? true;

  /// Replaces a summary the data-mode record owes Wear, or resumes a pending
  /// or retrying native send, for warm resume and explicit sync.
  static Future<void> resumeSummary() =>
      _channel.invokeMethod<void>('resumeWatchSummary');

  static Future<Object?> _confirm(MethodCall call) async {
    if (call.method != _confirmMethod) throw MissingPluginException();
    final isCurrent = _confirmations[call.arguments];
    return isCurrent != null && await isCurrent();
  }
}
