package app.wardpulse.wear.complication

import android.app.PendingIntent
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import androidx.wear.watchface.complications.data.ComplicationData
import androidx.wear.watchface.complications.data.ComplicationType
import androidx.wear.watchface.complications.data.NoDataComplicationData
import androidx.wear.watchface.complications.data.PlainComplicationText
import androidx.wear.watchface.complications.data.RangedValueComplicationData
import androidx.wear.watchface.complications.data.ShortTextComplicationData
import androidx.wear.watchface.complications.datasource.ComplicationDataSourceUpdateRequester
import androidx.wear.watchface.complications.datasource.ComplicationRequest
import androidx.wear.watchface.complications.datasource.SuspendingComplicationDataSourceService
import app.wardpulse.wear.MainActivity
import app.wardpulse.wear.data.WatchSummaryStore
import app.wardpulse.wear.model.WatchDashboardSummary
import java.util.Locale
import kotlin.math.roundToInt

abstract class ShortTextComplicationDataSourceService :
    SuspendingComplicationDataSourceService() {
    protected abstract val previewText: String

    protected abstract fun text(summary: WatchDashboardSummary): String

    override suspend fun onComplicationRequest(request: ComplicationRequest): ComplicationData? {
        if (request.complicationType != ComplicationType.SHORT_TEXT) {
            return null
        }
        val value = WatchSummaryStore(this).load()?.let(::text) ?: NO_DATA
        return shortText(value)
    }

    override fun getPreviewData(type: ComplicationType): ComplicationData? =
        if (type == ComplicationType.SHORT_TEXT) shortText(previewText) else null

    private fun shortText(value: String) = ComplicationBuilders.shortText(this, value)

    private companion object {
        const val NO_DATA = "—"
    }
}

abstract class RingComplicationDataSourceService :
    SuspendingComplicationDataSourceService() {
    protected abstract val ringIndex: Int
    protected abstract val previewPercent: Float

    override suspend fun onComplicationRequest(request: ComplicationRequest): ComplicationData? {
        val percent = WatchSummaryStore(this).load()
            ?.rings
            ?.getOrNull(ringIndex)
            ?.usedPercent
            ?.toFloat()
        return when (request.complicationType) {
            // NoData clears a previous arc; null would leave stale complication data.
            ComplicationType.RANGED_VALUE ->
                if (percent == null) {
                    NoDataComplicationData()
                } else {
                    ComplicationBuilders.ranged(this, percent)
                }
            ComplicationType.SHORT_TEXT ->
                ComplicationBuilders.shortText(this, WatchComplicationText.percentLabel(percent))
            else -> null
        }
    }

    override fun getPreviewData(type: ComplicationType): ComplicationData? =
        when (type) {
            ComplicationType.RANGED_VALUE ->
                ComplicationBuilders.ranged(this, previewPercent)
            ComplicationType.SHORT_TEXT ->
                ComplicationBuilders.shortText(
                    this,
                    WatchComplicationText.percentLabel(previewPercent),
                )
            else -> null
        }
}

private object ComplicationBuilders {
    fun shortText(context: Context, value: String): ComplicationData =
        ShortTextComplicationData.Builder(
            text = PlainComplicationText.Builder(value).build(),
            contentDescription = PlainComplicationText.Builder(value).build(),
        ).setTapAction(tapAction(context)).build()

    fun ranged(context: Context, percent: Float): ComplicationData {
        val value = percent.coerceIn(0f, 100f)
        val label = WatchComplicationText.percentLabel(value)
        return RangedValueComplicationData.Builder(
            value = value,
            min = 0f,
            max = 100f,
            contentDescription = PlainComplicationText.Builder(label).build(),
        ).setText(PlainComplicationText.Builder(label).build())
            .setTapAction(tapAction(context))
            .build()
    }

    private fun tapAction(context: Context): PendingIntent =
        PendingIntent.getActivity(
            context,
            0,
            Intent(context, MainActivity::class.java),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
}

class TodayComplicationDataSourceService : RingComplicationDataSourceService() {
    override val ringIndex = 0
    override val previewPercent = 25f
}

class WeekComplicationDataSourceService : RingComplicationDataSourceService() {
    override val ringIndex = 1
    override val previewPercent = 49f
}

class StatusComplicationDataSourceService : ShortTextComplicationDataSourceService() {
    override val previewText = "SYNC"

    override fun text(summary: WatchDashboardSummary) =
        WatchComplicationText.status(summary)
}

object WatchComplicationText {
    fun today(summary: WatchDashboardSummary): String =
        percentLabel(summary.rings.getOrNull(0)?.usedPercent?.toFloat())

    fun week(summary: WatchDashboardSummary): String =
        percentLabel(summary.rings.getOrNull(1)?.usedPercent?.toFloat())

    fun percentLabel(percent: Float?): String =
        percent?.roundToInt()?.let { "$it%" } ?: "—"

    fun status(summary: WatchDashboardSummary): String {
        val source = when (summary.providers.size) {
            0 -> "NO DATA"
            1 -> summary.providers.single().providerLabel.uppercase(Locale.US)
            else -> "${summary.providers.size} PROVIDERS"
        }
        val status = when {
            summary.isStale -> "STALE"
            summary.providers.size == 1 ->
                summary.providers.single().status.label.uppercase(Locale.US)
            else -> summary.overallStatus.label.uppercase(Locale.US)
        }
        return "$source · $status"
    }
}

object WatchComplicationUpdater {
    private val services = listOf(
        TodayComplicationDataSourceService::class.java,
        WeekComplicationDataSourceService::class.java,
        StatusComplicationDataSourceService::class.java,
    )

    fun requestUpdate(context: Context) {
        services.forEach { service ->
            ComplicationDataSourceUpdateRequester.create(
                context,
                ComponentName(context, service),
            ).requestUpdateAll()
        }
    }
}
