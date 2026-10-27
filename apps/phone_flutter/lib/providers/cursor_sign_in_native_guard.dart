import 'package:flutter/services.dart';

/// Binds the Android request guard to one WebView and its existing delegate.
/// Events contain only a view identifier and a fixed failure category.
class CursorSignInNativeGuard {
  CursorSignInNativeGuard({
    required this.view,
    required this.client,
    required this.onFailure,
  });

  static const channelName = 'app.wardpulse/cursor_sign_in';
  static const _channel = MethodChannel(channelName);
  static final _guards = <int, CursorSignInNativeGuard>{};
  final int view;
  final int client;
  final void Function(String) onFailure;
  String? _failure;

  Future<void> attach() async {
    _channel.setMethodCallHandler((call) async {
      if (call.method != 'failure') return;
      final arguments = Map<Object?, Object?>.from(call.arguments as Map);
      _guards[arguments['view']]?._report(arguments['category'] as String);
    });
    _guards[view] = this;
    await _channel.invokeMethod<void>('attach', {'view': view, 'client': client});
  }

  void _report(String category) {
    if (category != 'googleAuthorization' &&
        category != 'mainFrameHttpError' &&
        category != 'navigationRejected') {
      throw StateError('Unknown sign-in failure category');
    }
    if (_failure != null) return;
    _failure = category;
    onFailure(category);
  }

  /// A native failure is sticky, even if its asynchronous event is still queued.
  Future<bool> check() async {
    if (_failure != null) return false;
    final category = await _channel.invokeMethod<String>('failure', {
      'view': view,
    });
    if (category != null) _report(category);
    return _failure == null;
  }

  Future<void> beginRetirement() =>
      _channel.invokeMethod<void>('retire', {'view': view});

  Future<void> detach() async {
    await _channel.invokeMethod<void>('detach', {'view': view});
    if (identical(_guards[view], this)) _guards.remove(view);
    if (_guards.isEmpty) _channel.setMethodCallHandler(null);
  }
}
