package app.wardpulse

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetPlugin

/**
 * Home-screen remaining summary. Payload keys are written from Flutter via
 * `HomeWidgetPhoneWidgetSyncService`.
 */
class WardPulseAppWidget : AppWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
    ) {
        val data = HomeWidgetPlugin.getData(context)
        for (appWidgetId in appWidgetIds) {
            val maxRows = maxRowsForSize(appWidgetManager, appWidgetId)
            appWidgetManager.updateAppWidget(
                appWidgetId,
                buildViews(context, data, maxRows),
            )
        }
    }

    override fun onAppWidgetOptionsChanged(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int,
        newOptions: android.os.Bundle?,
    ) {
        val data = HomeWidgetPlugin.getData(context)
        val maxRows = maxRowsForSize(appWidgetManager, appWidgetId)
        appWidgetManager.updateAppWidget(
            appWidgetId,
            buildViews(context, data, maxRows),
        )
    }

    private fun maxRowsForSize(
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int,
    ): Int {
        val options = appWidgetManager.getAppWidgetOptions(appWidgetId)
        val minHeight = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT, 110)
        // Small ≈ 2 cells. Otherwise show the prefs cap — no medium-4 cutoff that
        // left empty chrome while hiding Claude/Cursor rows.
        return if (minHeight < 100) 2 else maxRowCount
    }

    private fun buildViews(
        context: Context,
        data: SharedPreferences,
        maxRows: Int,
    ): RemoteViews {
        val views = RemoteViews(context.packageName, R.layout.ward_pulse_app_widget)
        val title = data.getString("title", context.getString(R.string.ward_pulse_widget_title))
        views.setTextViewText(R.id.widget_title, title)

        val stale = data.getString("stale", "0") == "1"
        views.setViewVisibility(
            R.id.widget_stale,
            if (stale) View.VISIBLE else View.GONE,
        )

        val storedCount = data.getInt("row_count", 0).coerceIn(0, maxRowCount)
        val rowCount = storedCount.coerceAtMost(maxRows)
        val empty = data.getString("empty", if (storedCount == 0) "1" else "0") == "1" ||
            rowCount == 0
        views.setViewVisibility(
            R.id.widget_empty,
            if (empty) View.VISIBLE else View.GONE,
        )

        val rowIds =
            intArrayOf(
                R.id.widget_row_0,
                R.id.widget_row_1,
                R.id.widget_row_2,
                R.id.widget_row_3,
                R.id.widget_row_4,
                R.id.widget_row_5,
            )
        val textIds =
            intArrayOf(
                R.id.widget_row_0_text,
                R.id.widget_row_1_text,
                R.id.widget_row_2_text,
                R.id.widget_row_3_text,
                R.id.widget_row_4_text,
                R.id.widget_row_5_text,
            )
        val accentIds =
            intArrayOf(
                R.id.widget_row_0_accent,
                R.id.widget_row_1_accent,
                R.id.widget_row_2_accent,
                R.id.widget_row_3_accent,
                R.id.widget_row_4_accent,
                R.id.widget_row_5_accent,
            )

        for (i in 0 until maxRowCount) {
            if (!empty && i < rowCount) {
                val text = data.getString("row_${i}_text", "") ?: ""
                val colorHex = data.getString("row_${i}_color", "ff8ab4f8") ?: "ff8ab4f8"
                val color = colorHex.toLongOrNull(16)?.toInt() ?: 0xFF8AB4F8.toInt()
                views.setViewVisibility(rowIds[i], View.VISIBLE)
                views.setTextViewText(textIds[i], text)
                views.setInt(accentIds[i], "setBackgroundColor", color)
            } else {
                views.setViewVisibility(rowIds[i], View.GONE)
            }
        }

        val launchIntent =
            Intent(context, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            }
        val pending =
            PendingIntent.getActivity(
                context,
                0,
                launchIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
        views.setOnClickPendingIntent(R.id.widget_root, pending)
        return views
    }

    private companion object {
        const val maxRowCount = 6
    }
}
