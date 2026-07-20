package app.wardpulse.wear.complication

import android.app.PendingIntent
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import androidx.wear.watchface.complications.data.ComplicationData
import androidx.wear.watchface.complications.data.ComplicationType
import androidx.wear.watchface.complications.data.PlainComplicationText
import androidx.wear.watchface.complications.data.ShortTextComplicationData
import androidx.wear.watchface.complications.datasource.ComplicationDataSourceUpdateRequester
import androidx.wear.watchface.complications.datasource.ComplicationRequest
import androidx.wear.watchface.complications.datasource.SuspendingComplicationDataSourceService
import app.wardpulse.wear.MainActivity
import app.wardpulse.wear.data.WatchSummaryStore
import app.wardpulse.wear.model.WatchDashboardSummary
import java.util.Locale
import kotlin.math.roundToInt

abstract class WatchSummaryComplicationDataSourceService :
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

    private fun shortText(value: String) =
        ShortTextComplicationData.Builder(
            text = PlainComplicationText.Builder(value).build(),
            contentDescription = PlainComplicationText.Builder(value).build(),
        ).setTapAction(
            PendingIntent.getActivity(
                this,
                0,
                Intent(this, MainActivity::class.java),
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
            ),
        ).build()

    private companion object {
        const val NO_DATA = "—"
    }
}

class TodayComplicationDataSourceService : WatchSummaryComplicationDataSourceService() {
    override val previewText = "—"

    override fun text(summary: WatchDashboardSummary) =
        WatchComplicationText.today(summary)
}

class WeekComplicationDataSourceService : WatchSummaryComplicationDataSourceService() {
    override val previewText = "—"

    override fun text(summary: WatchDashboardSummary) =
        WatchComplicationText.week(summary)
}

class StatusComplicationDataSourceService : WatchSummaryComplicationDataSourceService() {
    override val previewText = "SYNC"

    override fun text(summary: WatchDashboardSummary) =
        WatchComplicationText.status(summary)
}

object WatchComplicationText {
    fun today(summary: WatchDashboardSummary): String = summary.today.usedPercent.percentLabel()

    fun week(summary: WatchDashboardSummary): String = summary.week.usedPercent.percentLabel()

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

    private fun Double?.percentLabel(): String = this?.roundToInt()?.let { "$it%" } ?: "—"
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
