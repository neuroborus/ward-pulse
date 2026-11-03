package app.wardpulse

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.os.Build
import android.os.Bundle
import android.util.SizeF
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetPlugin
import java.time.ZoneId
import kotlin.math.ceil

/** Complete own-font content inside the actual host allocation; options remain host-owned. */
class WardPulseAppWidget : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        val data = HomeWidgetPlugin.getData(context)
        for (id in ids) refresh(context, manager, id, data)
    }

    override fun onAppWidgetOptionsChanged(
        context: Context, manager: AppWidgetManager, id: Int, newOptions: Bundle?,
    ) {
        refresh(context, manager, id, HomeWidgetPlugin.getData(context))
    }

    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        if (intent.action == Intent.ACTION_TIMEZONE_CHANGED) {
            val manager = AppWidgetManager.getInstance(context)
            onUpdate(context, manager, manager.getAppWidgetIds(ComponentName(context, javaClass)))
        }
    }

    private fun refresh(
        context: Context, manager: AppWidgetManager, id: Int, data: SharedPreferences,
    ) {
        val sizes = hostSizes(manager.getAppWidgetOptions(id))
        val display = context.resources.displayMetrics
        // The platform's bitmap allowance is 1.5 screen-sized ARGB images. Keep a lower hard cap.
        val bytes = minOf(
            PhoneWidgetLayout.MAX_BITMAP_BYTES,
            display.widthPixels.toLong() * display.heightPixels * 6L,
        ).coerceAtLeast(0)
        val cache = data.all
        val variants = linkedMapOf<SizeF, RemoteViews>()
        for (size in sizes) variants[size] = buildViews(context, id, cache, size, bytes / sizes.size)
        val views = if (Build.VERSION.SDK_INT >= 31 && variants.size > 1) {
            RemoteViews(variants)
        } else {
            variants.values.first()
        }
        // Fresh full updates replace the previous bitmap set; no accumulated partial updates/cache.
        manager.updateAppWidget(id, views)
    }

    @Suppress("DEPRECATION")
    private fun hostSizes(options: Bundle): List<SizeF> {
        if (Build.VERSION.SDK_INT >= 31) {
            val sizes = options.getParcelableArrayList<SizeF>(AppWidgetManager.OPTION_APPWIDGET_SIZES)
                .orEmpty().take(16).filter {
                    it.width.isFinite() && it.height.isFinite() && it.width > 0 && it.height > 0
                }.distinct()
            if (sizes.size in 1..2) return sizes
            if (sizes.isNotEmpty()) {
                // Unusual hosts get one conservative fit, never an unbounded responsive map.
                return listOf(SizeF(sizes.minOf { it.width }, sizes.minOf { it.height }))
            }
        }
        return listOf(SizeF(
            tighter(options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH),
                options.getInt(AppWidgetManager.OPTION_APPWIDGET_MAX_WIDTH), 180).toFloat(),
            tighter(options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT),
                options.getInt(AppWidgetManager.OPTION_APPWIDGET_MAX_HEIGHT), 110).toFloat(),
        ))
    }

    private fun tighter(minimum: Int, maximum: Int, fallback: Int): Int = when {
        minimum > 0 && maximum > 0 -> minOf(minimum, maximum)
        minimum > 0 -> minimum
        maximum > 0 -> maximum
        else -> fallback
    }

    private fun buildViews(
        context: Context, id: Int, cache: Map<String, *>, size: SizeF, byteBudget: Long,
    ): RemoteViews {
        val views = RemoteViews(context.packageName, R.layout.ward_pulse_app_widget)
        fun stored(key: String): String = cache[key] as? String ?: ""
        val stale = stored("stale") == "1"
        val count = (cache["row_count"] as? Number)?.toInt()?.coerceIn(0, PhoneWidgetLayout.MAX_ROWS) ?: 0
        val empty = stored("empty") == "1" || count == 0
        val zone = ZoneId.systemDefault()
        val rows = (0 until count).map { index ->
            PhoneWidgetLayout.Row.fromCache(
                stored("row_${index}_label"), stored("row_${index}_family"),
                stored("row_${index}_pool"), stored("row_${index}_percent"),
                stored("row_${index}_credits"), stored("row_${index}_resets_at"), zone,
                stored("row_${index}_color").toLongOrNull(16)?.toInt()
                    ?: context.getColor(R.color.ward_pulse_widget_fallback),
                stored("row_${index}_kind"),
                stored("row_${index}_spent_minor"), stored("row_${index}_spent_currency"),
                stored("row_${index}_cap_minor"), stored("row_${index}_cap_currency"),
                stored("row_${index}_extra_used_value"), stored("row_${index}_extra_used_unit"),
                stored("row_${index}_extra_cap_value"), stored("row_${index}_extra_cap_unit"),
            )
        }
        val density = context.resources.displayMetrics.density
        val renderer = PhoneWidgetRenderer(context, density)
        val mark = PhoneWidgetRenderer.mark(context)
        val width = ceil(size.width * density).toInt().coerceIn(1, 16384)
        val height = ceil(size.height * density).toInt().coerceIn(1, 16384)
        val plan = PhoneWidgetLayout.fit(
            width, height, density, rows, empty, stale, renderer, byteBudget, mark.allocationByteCount,
        )
        val images = renderer.render(plan)
        val card = plan.card
        views.setViewVisibility(R.id.widget_card, if (card == null) View.GONE else View.VISIBLE)
        views.setViewPadding(R.id.widget_root, card?.left ?: 0, card?.top ?: 0,
            if (card == null) 0 else width - card.right,
            if (card == null) 0 else height - card.bottom)
        val layerIds = mapOf(
            PhoneWidgetLayout.Layer.PRIMARY to R.id.widget_primary,
            PhoneWidgetLayout.Layer.MUTED to R.id.widget_muted,
            PhoneWidgetLayout.Layer.STALE to R.id.widget_stale,
            PhoneWidgetLayout.Layer.ACCENT to R.id.widget_accents,
        )
        for ((layer, viewId) in layerIds) {
            val image = images?.get(layer)
            views.setImageViewBitmap(viewId, image?.bitmap)
            views.setViewVisibility(viewId, if (image == null) View.GONE else View.VISIBLE)
            val bounds = image?.bounds
            views.setViewPadding(viewId,
                if (bounds == null || card == null) 0 else bounds.left - card.left,
                if (bounds == null || card == null) 0 else bounds.top - card.top,
                if (bounds == null || card == null) 0 else card.right - bounds.right,
                if (bounds == null || card == null) 0 else card.bottom - bounds.bottom)
        }
        val showMark = images != null && plan.mark
        views.setImageViewBitmap(R.id.widget_watermark, if (showMark) mark else null)
        views.setViewVisibility(R.id.widget_watermark, if (showMark) View.VISIBLE else View.GONE)
        val description = mutableListOf(context.getString(R.string.ward_pulse_widget_title))
        if (stale) description.add(context.getString(R.string.ward_pulse_widget_stale))
        if (images != null && plan.state == PhoneWidgetLayout.EmptyState.NONE) {
            for (row in plan.rows) description.add(PhoneWidgetLayout.rowDescription(row))
        } else {
            description.add(context.getString(if (empty) R.string.ward_pulse_widget_empty
                else R.string.ward_pulse_widget_resize))
        }
        views.setContentDescription(R.id.widget_root, description.joinToString(". "))
        val launch = Intent(context, MainActivity::class.java).apply {
            action = DashboardLaunchRequest.ACTION
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        views.setOnClickPendingIntent(R.id.widget_root, PendingIntent.getActivity(
            context, id, launch, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        ))
        return views
    }
}
