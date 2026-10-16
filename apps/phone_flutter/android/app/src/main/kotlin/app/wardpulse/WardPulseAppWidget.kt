package app.wardpulse

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.graphics.Paint
import android.graphics.Typeface
import android.os.Bundle
import android.util.TypedValue
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetPlugin
import kotlin.math.roundToInt

/**
 * Home-screen remaining summary. Payload keys are written from Flutter via
 * `HomeWidgetPhoneWidgetSyncService`.
 *
 * Shows only **complete** prefs rows and **complete** columns that fit the host
 * cell (card hugs). Columns drop from the right: credits → label → % left.
 * Do not write OPTION_APPWIDGET_SIZES — host-owned.
 */
class WardPulseAppWidget : AppWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
    ) {
        val data = HomeWidgetPlugin.getData(context)
        for (appWidgetId in appWidgetIds) {
            refresh(context, appWidgetManager, appWidgetId, data)
        }
    }

    override fun onAppWidgetOptionsChanged(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int,
        newOptions: Bundle?,
    ) {
        val data = HomeWidgetPlugin.getData(context)
        refresh(context, appWidgetManager, appWidgetId, data)
    }

    private fun refresh(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int,
        data: SharedPreferences,
    ) {
        val staleInsetPx = staleInsetPx(context, data.getString("stale", "0") == "1")
        val maxRows =
            PhoneWidgetLayout.completeRows(
                availableHeightDp(appWidgetManager, appWidgetId),
                context.resources.displayMetrics.density,
                staleInsetPx,
            )
        val columns = columnMode(appWidgetManager, appWidgetId)
        appWidgetManager.updateAppWidget(
            appWidgetId,
            buildViews(context, appWidgetId, data, maxRows, columns, staleInsetPx),
        )
    }

    /** Match the badge's 11sp bold line, including font padding, at the current font scale. */
    private fun staleInsetPx(context: Context, stale: Boolean): Int {
        if (!stale) return 0
        val display = context.resources.displayMetrics
        val paint = Paint().apply {
            typeface = Typeface.DEFAULT_BOLD
            textSize = TypedValue.applyDimension(TypedValue.COMPLEX_UNIT_SP, 11f, display)
        }
        val font = paint.fontMetricsInt
        val gapPx =
            TypedValue.applyDimension(TypedValue.COMPLEX_UNIT_DIP, 2f, display).roundToInt()
        return font.bottom - font.top + gapPx
    }

    private fun columnMode(
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int,
    ): ColumnMode {
        val available = availableWidthDp(appWidgetManager, appWidgetId)
        return when {
            available >= WIDTH_FULL_DP -> ColumnMode.Full
            available >= WIDTH_LABEL_DP -> ColumnMode.WithLabel
            else -> ColumnMode.PercentOnly
        }
    }

    private fun availableHeightDp(
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int,
    ): Int {
        val options = appWidgetManager.getAppWidgetOptions(appWidgetId)
        return tighterBound(
            options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT, 0),
            options.getInt(AppWidgetManager.OPTION_APPWIDGET_MAX_HEIGHT, 0),
            DEFAULT_HEIGHT_DP,
        )
    }

    private fun availableWidthDp(
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int,
    ): Int {
        val options = appWidgetManager.getAppWidgetOptions(appWidgetId)
        return tighterBound(
            options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH, 0),
            options.getInt(AppWidgetManager.OPTION_APPWIDGET_MAX_WIDTH, 0),
            DEFAULT_WIDTH_DP,
        )
    }

    private fun tighterBound(
        min: Int,
        max: Int,
        fallback: Int,
    ): Int =
        when {
            min > 0 && max > 0 -> minOf(min, max)
            min > 0 -> min
            max > 0 -> max
            else -> fallback
        }

    private fun buildViews(
        context: Context,
        appWidgetId: Int,
        data: SharedPreferences,
        maxRows: Int,
        columns: ColumnMode,
        staleInsetPx: Int,
    ): RemoteViews {
        val views = RemoteViews(context.packageName, R.layout.ward_pulse_app_widget)
        views.setViewPadding(R.id.widget_rows, 0, staleInsetPx, 0, 0)

        val stale = data.getString("stale", "0") == "1"
        views.setViewVisibility(
            R.id.widget_stale,
            if (stale) View.VISIBLE else View.GONE,
        )

        val storedCount = data.getInt("row_count", 0).coerceIn(0, MAX_ROW_COUNT)
        val rowCount = storedCount.coerceAtMost(maxRows)
        val emptyState =
            PhoneWidgetLayout.emptyState(
                storedCount,
                data.getString("empty", if (storedCount == 0) "1" else "0") == "1",
                rowCount,
            )
        val empty = emptyState != PhoneWidgetLayout.EmptyState.NONE
        views.setTextViewText(
            R.id.widget_empty,
            context.getString(
                if (emptyState == PhoneWidgetLayout.EmptyState.RESIZE)
                    R.string.ward_pulse_widget_resize
                else R.string.ward_pulse_widget_empty,
            ),
        )
        views.setViewVisibility(
            R.id.widget_empty,
            if (empty) View.VISIBLE else View.GONE,
        )

        val showLabel = columns != ColumnMode.PercentOnly
        val showCredits = columns == ColumnMode.Full

        val rowIds =
            intArrayOf(
                R.id.widget_row_0,
                R.id.widget_row_1,
                R.id.widget_row_2,
                R.id.widget_row_3,
                R.id.widget_row_4,
                R.id.widget_row_5,
            )
        val percentIds =
            intArrayOf(
                R.id.widget_row_0_percent,
                R.id.widget_row_1_percent,
                R.id.widget_row_2_percent,
                R.id.widget_row_3_percent,
                R.id.widget_row_4_percent,
                R.id.widget_row_5_percent,
            )
        val creditsIds =
            intArrayOf(
                R.id.widget_row_0_credits,
                R.id.widget_row_1_credits,
                R.id.widget_row_2_credits,
                R.id.widget_row_3_credits,
                R.id.widget_row_4_credits,
                R.id.widget_row_5_credits,
            )
        val labelIds =
            intArrayOf(
                R.id.widget_row_0_label,
                R.id.widget_row_1_label,
                R.id.widget_row_2_label,
                R.id.widget_row_3_label,
                R.id.widget_row_4_label,
                R.id.widget_row_5_label,
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

        for (i in 0 until MAX_ROW_COUNT) {
            if (!empty && i < rowCount) {
                val percent = data.getString("row_${i}_percent", "") ?: ""
                val credits = data.getString("row_${i}_credits", "") ?: ""
                val label = data.getString("row_${i}_label", "") ?: ""
                // Colourless on purpose: a row whose accent did not arrive names no
                // family, and blue is a product colour again since 2026-08-13.
                val colorHex = data.getString("row_${i}_color", "ff8a968f") ?: "ff8a968f"
                val color = colorHex.toLongOrNull(16)?.toInt() ?: 0xFF8A968F.toInt()
                views.setViewVisibility(rowIds[i], View.VISIBLE)
                views.setTextViewText(percentIds[i], percent)
                views.setTextViewText(creditsIds[i], credits)
                // The payload carries `Family · Pool`; the label column is two lines,
                // so the separator becomes the line break instead of eating width.
                views.setTextViewText(labelIds[i], label.replace(" · ", "\n"))
                views.setViewVisibility(
                    labelIds[i],
                    if (showLabel) View.VISIBLE else View.GONE,
                )
                views.setViewVisibility(
                    creditsIds[i],
                    if (showCredits) View.VISIBLE else View.GONE,
                )
                views.setInt(accentIds[i], "setBackgroundColor", color)
            } else {
                views.setViewVisibility(rowIds[i], View.GONE)
            }
        }

        val launchIntent =
            Intent(context, MainActivity::class.java).apply {
                action = DashboardLaunchRequest.ACTION
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            }
        val pending =
            PendingIntent.getActivity(
                context,
                appWidgetId,
                launchIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
        views.setOnClickPendingIntent(R.id.widget_root, pending)
        return views
    }

    private enum class ColumnMode {
        PercentOnly,
        WithLabel,
        Full,
    }

    private companion object {
        const val MAX_ROW_COUNT = PhoneWidgetLayout.MAX_ROWS
        const val DEFAULT_HEIGHT_DP = 110
        const val DEFAULT_WIDTH_DP = 180

        /** Card paddingStart + paddingEnd. */
        const val CHROME_PAD_H_DP = 20
        /** Accent bar + percent marginStart. */
        const val ACCENT_DP = 11
        const val PERCENT_COL_DP = 70
        const val LABEL_COL_DP = 100
        const val CREDITS_COL_DP = 88
        const val COL_GAP_DP = 6
        const val FIT_SLACK_DP = 6

        /** % left only. */
        const val WIDTH_PERCENT_DP =
            CHROME_PAD_H_DP + ACCENT_DP + PERCENT_COL_DP + FIT_SLACK_DP

        /** % left + label. */
        const val WIDTH_LABEL_DP = WIDTH_PERCENT_DP + COL_GAP_DP + LABEL_COL_DP

        /** % left + label + credits. */
        const val WIDTH_FULL_DP = WIDTH_LABEL_DP + COL_GAP_DP + CREDITS_COL_DP
    }
}
