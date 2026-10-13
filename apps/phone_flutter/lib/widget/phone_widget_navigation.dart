import 'dart:async';

import 'package:flutter/services.dart';

/// Launcher navigation has its own channel and never requests a provider poll.
abstract interface class PhoneWidgetNavigationService {
  void bind(void Function() openDashboard);
  void unbind();
}

final class MethodChannelPhoneWidgetNavigationService
    implements PhoneWidgetNavigationService {
  const MethodChannelPhoneWidgetNavigationService();

  static const channel = MethodChannel('app.wardpulse/app_navigation');

  @override
  void bind(void Function() openDashboard) {
    channel.setMethodCallHandler((call) async {
      if (call.method == 'openDashboard') {
        openDashboard();
      }
    });
    // Native code retains cold/early-warm intents until this handler is installed.
    unawaited(
      channel.invokeMethod<void>('navigationChannelReady').catchError((_) {}),
    );
  }

  @override
  void unbind() {
    channel.setMethodCallHandler(null);
  }
}
