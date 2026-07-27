import 'package:home_widget/home_widget.dart';

import '../dashboard/dashboard_models.dart';
import 'phone_widget_payload.dart';
import 'phone_widget_preferences.dart';

/// Android AppWidgetProvider simple class name (see `WardPulseAppWidget`).
const phoneWidgetProviderName = 'WardPulseAppWidget';

/// Fully-qualified Android provider for [HomeWidget.updateWidget].
const phoneWidgetQualifiedAndroidName = 'app.wardpulse.WardPulseAppWidget';

/// Pushes [snapshot] metrics onto the Android home-screen widget.
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

/// Writes payload keys for [WardPulseAppWidget] via `home_widget`.
final class HomeWidgetPhoneWidgetSyncService implements PhoneWidgetSyncService {
  const HomeWidgetPhoneWidgetSyncService();

  static const _maxRows = phoneWidgetSlotCount;

  @override
  Future<void> sync(
    DashboardSnapshot snapshot,
    PhoneWidgetPreferences preferences,
  ) async {
    final payload = buildPhoneWidgetPayload(snapshot, preferences);
    await HomeWidget.saveWidgetData<String>('title', 'WardPulse');
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
        await HomeWidget.saveWidgetData<String>('row_${i}_text', row.line);
        // Hex string — ARGB ints with the high bit set arrive as Long on Android
        // and ClassCastException SharedPreferences.getInt.
        await HomeWidget.saveWidgetData<String>(
          'row_${i}_color',
          row.accentArgb.toRadixString(16).padLeft(8, '0'),
        );
      } else {
        await HomeWidget.saveWidgetData<String>('row_${i}_text', '');
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
