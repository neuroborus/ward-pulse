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

  /// Marks retained launcher rows after a failed poll, without inventing data.
  ///
  /// Only the status flag changes; an empty or cleared payload stays empty.
  static Future<void> markExistingRowsStale() async {
    final count =
        await HomeWidget.getWidgetData<int>('row_count', defaultValue: 0) ?? 0;
    if (count <= 0) {
      return;
    }
    final empty = await HomeWidget.getWidgetData<String>(
      'empty',
      defaultValue: '0',
    );
    if (empty == '1') {
      return;
    }
    final saved = await HomeWidget.saveWidgetData<String>('stale', '1');
    if (saved != true) {
      throw StateError('Could not save widget stale status.');
    }
    final updated = await HomeWidget.updateWidget(
      name: phoneWidgetProviderName,
      androidName: phoneWidgetProviderName,
      qualifiedAndroidName: phoneWidgetQualifiedAndroidName,
    );
    if (updated != true) {
      throw StateError('Could not redraw the stale widget.');
    }
  }

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
        final fields = <String, String>{
          'kind': row.kind.name,
          'spent_minor': row.spent?.minorUnits.toString() ?? '',
          'spent_currency': row.spent?.currency ?? '',
          'cap_minor': row.cap?.minorUnits.toString() ?? '',
          'cap_currency': row.cap?.currency ?? '',
          'extra_used_value': row.extraUsed?.value ?? '',
          'extra_used_unit': row.extraUsed?.unit ?? '',
          'extra_cap_value': row.extraCap?.value ?? '',
          'extra_cap_unit': row.extraCap?.unit ?? '',
        };
        for (final entry in fields.entries) {
          await HomeWidget.saveWidgetData<String>(
            'row_${i}_${entry.key}',
            entry.value,
          );
        }
        await HomeWidget.saveWidgetData<String>(
          'row_${i}_percent',
          row.percentText,
        );
        await HomeWidget.saveWidgetData<String>(
          'row_${i}_credits',
          row.creditsSuffix ?? '',
        );
        await HomeWidget.saveWidgetData<String>('row_${i}_label', row.label);
        await HomeWidget.saveWidgetData<String>(
          'row_${i}_family',
          row.familyLabel ?? '',
        );
        await HomeWidget.saveWidgetData<String>(
          'row_${i}_pool',
          row.poolLabel ?? '',
        );
        await HomeWidget.saveWidgetData<String>(
          'row_${i}_resets_at',
          row.resetsAt?.toUtc().toIso8601String() ?? '',
        );
        // Hex string — ARGB ints with the high bit set arrive as Long on Android
        // and ClassCastException SharedPreferences.getInt.
        await HomeWidget.saveWidgetData<String>(
          'row_${i}_color',
          row.accentArgb.toRadixString(16).padLeft(8, '0'),
        );
      } else {
        for (final field in [
          'kind',
          'spent_minor',
          'spent_currency',
          'cap_minor',
          'cap_currency',
          'extra_used_value',
          'extra_used_unit',
          'extra_cap_value',
          'extra_cap_unit',
        ]) {
          await HomeWidget.saveWidgetData<String>('row_${i}_$field', '');
        }
        await HomeWidget.saveWidgetData<String>('row_${i}_percent', '');
        await HomeWidget.saveWidgetData<String>('row_${i}_credits', '');
        await HomeWidget.saveWidgetData<String>('row_${i}_label', '');
        await HomeWidget.saveWidgetData<String>('row_${i}_family', '');
        await HomeWidget.saveWidgetData<String>('row_${i}_pool', '');
        await HomeWidget.saveWidgetData<String>('row_${i}_resets_at', '');
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
