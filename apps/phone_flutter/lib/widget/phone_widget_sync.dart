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

/// Whether a request still owns the widget; checked before each plugin call.
typedef PhoneWidgetSyncGuard = Future<bool> Function();

Future<bool> _alwaysCurrent() async => true;

typedef PhoneWidgetPayloadWriter =
    Future<void> Function(
      PhoneWidgetPayload payload, {
      required PhoneWidgetSyncGuard isCurrent,
    });

/// Serializes overlapping syncs in one Flutter isolate (latest wins).
///
/// Foreground UI and headless WorkManager each get their own isolate, so this
/// does not cross-engine-lock SharedPreferences writes — only coalesces callers
/// that share the same engine. Each request keeps its own guard; once that
/// expires, its remaining writes stop. A plugin call that was already
/// dispatched cannot be retracted.
final class PhoneWidgetSyncCoordinator {
  PhoneWidgetSyncCoordinator({required PhoneWidgetPayloadWriter write})
    : _write = write;

  final PhoneWidgetPayloadWriter _write;

  int _epoch = 0;
  DashboardSnapshot? _latestSnapshot;
  PhoneWidgetPreferences? _latestPreferences;
  PhoneWidgetSyncGuard _latestIsCurrent = _alwaysCurrent;
  Future<void> _chain = Future<void>.value();

  /// Queues a write. Overlapping callers coalesce to the newest args.
  ///
  /// A failure reaches the caller but must not poison the queue, so the chain
  /// continues from a settled future while the returned one still throws.
  Future<void> sync(
    DashboardSnapshot snapshot,
    PhoneWidgetPreferences preferences, {
    PhoneWidgetSyncGuard isCurrent = _alwaysCurrent,
  }) {
    _latestSnapshot = snapshot;
    _latestPreferences = preferences;
    _latestIsCurrent = isCurrent;
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
    final isCurrent = _latestIsCurrent;
    if (snapshot == null || preferences == null) {
      return;
    }
    // Ownership can expire while the request waits in the queue.
    if (!await isCurrent() || epoch != _epoch) {
      return;
    }
    await _write(
      buildPhoneWidgetPayload(snapshot, preferences),
      isCurrent: isCurrent,
    );
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
  /// [isCurrent] is checked again after the awaited reads and before redraw.
  static Future<void> markExistingRowsStale({
    PhoneWidgetSyncGuard isCurrent = _alwaysCurrent,
  }) async {
    final count =
        await HomeWidget.getWidgetData<int>('row_count', defaultValue: 0) ?? 0;
    if (count <= 0) {
      return;
    }
    final empty = await HomeWidget.getWidgetData<String>(
      'empty',
      defaultValue: '0',
    );
    if (empty == '1' || !await isCurrent()) {
      return;
    }
    final saved = await HomeWidget.saveWidgetData<String>('stale', '1');
    if (saved != true) {
      throw StateError('Could not save widget stale status.');
    }
    if (!await isCurrent()) {
      return;
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

  /// Headless callers pass [isCurrent]; foreground requests stay current.
  @override
  Future<void> sync(
    DashboardSnapshot snapshot,
    PhoneWidgetPreferences preferences, {
    PhoneWidgetSyncGuard isCurrent = _alwaysCurrent,
  }) {
    return _coordinator.sync(snapshot, preferences, isCurrent: isCurrent);
  }

  /// Persists [payload] and asks the launcher to redraw.
  ///
  /// Stops before the next write or redraw once [isCurrent] fails.
  static Future<void> writeHomeWidgetPayload(
    PhoneWidgetPayload payload, {
    PhoneWidgetSyncGuard isCurrent = _alwaysCurrent,
  }) async {
    Future<bool> save<T>(String id, T value) async {
      if (!await isCurrent()) {
        return false;
      }
      await HomeWidget.saveWidgetData<T>(id, value);
      return true;
    }

    final rows = payload.rows.take(_maxRows).toList(growable: false);
    if (!await save<String>('stale', payload.stale ? '1' : '0') ||
        !await save<String>('empty', payload.isEmpty ? '1' : '0') ||
        !await save<int>('row_count', rows.length)) {
      return;
    }
    for (var i = 0; i < _maxRows; i++) {
      final row = i < rows.length ? rows[i] : null;
      final fields = <String, String>{
        'kind': row?.kind.name ?? '',
        'spent_minor': row?.spent?.minorUnits.toString() ?? '',
        'spent_currency': row?.spent?.currency ?? '',
        'cap_minor': row?.cap?.minorUnits.toString() ?? '',
        'cap_currency': row?.cap?.currency ?? '',
        'extra_used_value': row?.extraUsed?.value ?? '',
        'extra_used_unit': row?.extraUsed?.unit ?? '',
        'extra_cap_value': row?.extraCap?.value ?? '',
        'extra_cap_unit': row?.extraCap?.unit ?? '',
        'percent': row?.percentText ?? '',
        'credits': row?.creditsSuffix ?? '',
        'label': row?.label ?? '',
        'family': row?.familyLabel ?? '',
        'pool': row?.poolLabel ?? '',
        'resets_at': row?.resetsAt?.toUtc().toIso8601String() ?? '',
        // Hex string — ARGB ints with the high bit set arrive as Long on
        // Android and ClassCastException SharedPreferences.getInt.
        'color': row?.accentArgb.toRadixString(16).padLeft(8, '0') ?? '',
      };
      for (final entry in fields.entries) {
        if (!await save<String>('row_${i}_${entry.key}', entry.value)) {
          return;
        }
      }
    }
    if (!await isCurrent()) {
      return;
    }
    await HomeWidget.updateWidget(
      name: phoneWidgetProviderName,
      androidName: phoneWidgetProviderName,
      qualifiedAndroidName: phoneWidgetQualifiedAndroidName,
    );
  }
}
