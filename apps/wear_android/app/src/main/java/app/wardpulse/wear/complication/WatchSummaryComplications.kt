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
import app.wardpulse.wear.model.PulseStatus
import app.wardpulse.wear.model.WatchDashboardSummary
import app.wardpulse.wear.ui.formatPercentAmount
import app.wardpulse.wear.ui.formatPercentLabel
import java.util.Locale

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

    protected open val previewLabel: String = "Ring"

    override suspend fun onComplicationRequest(request: ComplicationRequest): ComplicationData? {
        val ring = WatchSummaryStore(this).load()?.rings?.getOrNull(ringIndex)
        val percent = ring?.usedPercent?.toFloat()
        val label = ring?.label
        return when (request.complicationType) {
            // NoData clears a previous arc; null would leave stale complication data.
            ComplicationType.RANGED_VALUE ->
                if (percent == null) {
                    NoDataComplicationData()
                } else {
                    ComplicationBuilders.ranged(this, percent, title = label)
                }
            // Match RANGED_VALUE: NoData hides the slot. Avoid "—%" under WFF `%s%%`.
            ComplicationType.SHORT_TEXT ->
                if (percent == null) {
                    NoDataComplicationData()
                } else {
                    ComplicationBuilders.shortText(
                        this,
                        value = WatchComplicationText.percentAmount(percent),
                        contentDescription = label ?: WatchComplicationText.percentLabel(percent),
                    )
                }
            else -> null
        }
    }

    override fun getPreviewData(type: ComplicationType): ComplicationData? =
        when (type) {
            ComplicationType.RANGED_VALUE ->
                ComplicationBuilders.ranged(this, previewPercent, title = previewLabel)
            ComplicationType.SHORT_TEXT ->
                ComplicationBuilders.shortText(
                    this,
                    WatchComplicationText.percentAmount(previewPercent),
                )
            else -> null
        }
}

private object ComplicationBuilders {
    fun shortText(
        context: Context,
        value: String,
        contentDescription: String = value,
    ): ComplicationData =
        ShortTextComplicationData.Builder(
            text = PlainComplicationText.Builder(value).build(),
            contentDescription = PlainComplicationText.Builder(contentDescription).build(),
        ).setTapAction(tapAction(context)).build()

    fun ranged(
        context: Context,
        percent: Float,
        title: String? = null,
    ): ComplicationData {
        val value = percent.coerceIn(0f, 100f)
        val amount = WatchComplicationText.percentAmount(value)
        val description = title?.let { "$it $amount%" } ?: WatchComplicationText.percentLabel(value)
        return RangedValueComplicationData.Builder(
            value = value,
            min = 0f,
            max = 100f,
            contentDescription = PlainComplicationText.Builder(description).build(),
        ).setText(PlainComplicationText.Builder(amount).build())
            .apply {
                if (!title.isNullOrBlank()) {
                    setTitle(PlainComplicationText.Builder(title).build())
                }
            }
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
    override val previewLabel = "Today"
}

class WeekComplicationDataSourceService : RingComplicationDataSourceService() {
    override val ringIndex = 1
    override val previewPercent = 49f
    override val previewLabel = "Week"
}

class StatusComplicationDataSourceService : ShortTextComplicationDataSourceService() {
    override val previewText = "SYNC"

    override fun text(summary: WatchDashboardSummary) =
        WatchComplicationText.status(summary)
}

class TokensComplicationDataSourceService : SuspendingComplicationDataSourceService() {
    override suspend fun onComplicationRequest(request: ComplicationRequest): ComplicationData? {
        if (request.complicationType != ComplicationType.SHORT_TEXT) {
            return null
        }
        val glance = WatchSummaryStore(this).load()?.tokenGlance
        return if (glance == null) {
            NoDataComplicationData()
        } else {
            ComplicationBuilders.shortText(
                this,
                value = glance.text,
                contentDescription = glance.label,
            )
        }
    }

    override fun getPreviewData(type: ComplicationType): ComplicationData? =
        if (type == ComplicationType.SHORT_TEXT) {
            ComplicationBuilders.shortText(
                this,
                value = "67K TOK",
                contentDescription = "Today tokens",
            )
        } else {
            null
        }
}

object WatchComplicationText {
    fun today(summary: WatchDashboardSummary): String =
        percentLabel(summary.rings.getOrNull(0)?.usedPercent?.toFloat())

    fun week(summary: WatchDashboardSummary): String =
        percentLabel(summary.rings.getOrNull(1)?.usedPercent?.toFloat())

    fun percentLabel(percent: Float?): String =
        formatPercentLabel(percent?.toDouble())

    /** WFF templates treat '%' specially; send digits only for RANGED_VALUE text. */
    fun percentAmount(percent: Float?): String =
        formatPercentAmount(percent?.toDouble()) ?: "—"

    fun status(summary: WatchDashboardSummary): String {
        val source = when (summary.providers.size) {
            0 -> "NO DATA"
            1 -> summary.providers.single().providerLabel.uppercase(Locale.US)
            else -> "${summary.providers.size} PRV"
        }
        val pulse = when {
            summary.isStale -> PulseStatus.STALE
            summary.providers.size == 1 -> summary.providers.single().status
            else -> summary.overallStatus
        }
        return "$source · ${shortStatus(pulse)}"
    }

    /** Short labels so the round chin does not clip the status line. */
    fun shortStatus(status: PulseStatus): String = when (status) {
        PulseStatus.OK -> "OK"
        PulseStatus.WARNING -> "WARN"
        PulseStatus.ERROR -> "ERR"
        PulseStatus.RATE_LIMITED -> "LIMIT"
        PulseStatus.AUTH_REQUIRED -> "AUTH"
        PulseStatus.STALE -> "STALE"
        PulseStatus.UNKNOWN -> "—"
    }
}

object WatchComplicationUpdater {
    private val services = listOf(
        TodayComplicationDataSourceService::class.java,
        WeekComplicationDataSourceService::class.java,
        StatusComplicationDataSourceService::class.java,
        TokensComplicationDataSourceService::class.java,
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
