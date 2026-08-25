import 'package:home_widget/home_widget.dart';

import '../dashboard/dashboard_models.dart';
import 'phone_widget_payload.dart';
import 'phone_widget_preferences.dart';

/// Android AppWidgetProvider simple class name (see `WardPulseAppWidget`).
const phoneWidgetProviderName = 'WardPulseAppWidget';

/// Fully-qualified Android provider for [HomeWidget.updateWidget].
const phoneWidgetQualifiedAndroidName = 'app.wardpulse.WardPulseAppWidget';

/// `developer.log` channel for launcher-widget failures.
const phoneWidgetLogName = 'WardPulse.PhoneWidget';

/// Pushes [snapshot] metrics onto the Android home-screen widget.
///
/// Throws when the write fails. Callers decide what a stale launcher tile is
/// worth to them: the foreground app keeps rendering, the headless worker keeps
/// its run green.
abstract interface class PhoneWidgetSyncService {
  Future<void> sync(
    DashboardSnapshot snapshot,
    PhoneWidgetPreferences preferences,
  );
}

/// No-op for widget tests and hosts without a launcher surface.
final class DisabledPhoneWidgetSyncService implements PhoneWidgetSyncService {
  const DisabledPhoneWidgetSyncService();

  @override
  Future<void> sync(
    DashboardSnapshot snapshot,
    PhoneWidgetPreferences preferences,
  ) async {}
}

typedef PhoneWidgetPayloadWriter =
    Future<void> Function(PhoneWidgetPayload payload);

/// Serializes overlapping syncs in one Flutter isolate (latest wins).
///
/// Foreground UI and headless WorkManager each get their own isolate, so this
/// does not cross-engine-lock SharedPreferences writes — only coalesces callers
/// that share the same engine.
final class PhoneWidgetSyncCoordinator {
  PhoneWidgetSyncCoordinator({required PhoneWidgetPayloadWriter write})
    : _write = write;

  final PhoneWidgetPayloadWriter _write;

  int _epoch = 0;
  DashboardSnapshot? _latestSnapshot;
  PhoneWidgetPreferences? _latestPreferences;
  Future<void> _chain = Future<void>.value();

  /// Queues a write. Overlapping callers coalesce to the newest args.
  ///
  /// A failure reaches the caller but must not poison the queue, so the chain
  /// continues from a settled future while the returned one still throws.
  Future<void> sync(
    DashboardSnapshot snapshot,
    PhoneWidgetPreferences preferences,
  ) {
    _latestSnapshot = snapshot;
    _latestPreferences = preferences;
    final epoch = ++_epoch;
    final run = _chain.then((_) => _runIfCurrent(epoch));
    _chain = run.catchError((_) {});
    return run;
  }

  Future<void> _runIfCurrent(int epoch) async {
    if (epoch != _epoch) {
      return;
    }
    final snapshot = _latestSnapshot;
    final preferences = _latestPreferences;
    if (snapshot == null || preferences == null) {
      return;
    }
    await _write(buildPhoneWidgetPayload(snapshot, preferences));
  }
}

/// Writes payload keys for [WardPulseAppWidget] via `home_widget`.
final class HomeWidgetPhoneWidgetSyncService implements PhoneWidgetSyncService {
  HomeWidgetPhoneWidgetSyncService({PhoneWidgetSyncCoordinator? coordinator})
    : _coordinator = coordinator ?? _sharedCoordinator;

  static final PhoneWidgetSyncCoordinator _sharedCoordinator =
      PhoneWidgetSyncCoordinator(write: writeHomeWidgetPayload);

  final PhoneWidgetSyncCoordinator _coordinator;

  static const _maxRows = phoneWidgetSlotCount;

  @override
  Future<void> sync(
    DashboardSnapshot snapshot,
    PhoneWidgetPreferences preferences,
  ) {
    return _coordinator.sync(snapshot, preferences);
  }

  /// Persists [payload] and asks the launcher to redraw.
  static Future<void> writeHomeWidgetPayload(PhoneWidgetPayload payload) async {
    await HomeWidget.saveWidgetData<String>('stale', payload.stale ? '1' : '0');
    await HomeWidget.saveWidgetData<String>(
      'empty',
      payload.isEmpty ? '1' : '0',
    );
    final rows = payload.rows.take(_maxRows).toList(growable: false);
    await HomeWidget.saveWidgetData<int>('row_count', rows.length);
    for (var i = 0; i < _maxRows; i++) {
      if (i < rows.length) {
        final row = rows[i];
        await HomeWidget.saveWidgetData<String>(
          'row_${i}_percent',
          row.percentText,
        );
        await HomeWidget.saveWidgetData<String>(
          'row_${i}_credits',
          row.creditsSuffix ?? '',
        );
        await HomeWidget.saveWidgetData<String>('row_${i}_label', row.label);
        // Hex string — ARGB ints with the high bit set arrive as Long on Android
        // and ClassCastException SharedPreferences.getInt.
        await HomeWidget.saveWidgetData<String>(
          'row_${i}_color',
          row.accentArgb.toRadixString(16).padLeft(8, '0'),
        );
      } else {
        await HomeWidget.saveWidgetData<String>('row_${i}_percent', '');
        await HomeWidget.saveWidgetData<String>('row_${i}_credits', '');
        await HomeWidget.saveWidgetData<String>('row_${i}_label', '');
        await HomeWidget.saveWidgetData<String>('row_${i}_color', '');
      }
    }
    await HomeWidget.updateWidget(
      name: phoneWidgetProviderName,
      androidName: phoneWidgetProviderName,
      qualifiedAndroidName: phoneWidgetQualifiedAndroidName,
    );
  }
}
