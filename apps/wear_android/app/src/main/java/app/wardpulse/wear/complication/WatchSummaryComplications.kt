package app.wardpulse.wear.complication

import android.app.PendingIntent
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import androidx.wear.watchface.complications.data.ColorRamp
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
import app.wardpulse.wear.model.RingSurfaceOrder
import app.wardpulse.wear.model.WatchDashboardSummary
import app.wardpulse.wear.ui.RingFamily
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
    protected abstract val previewColorArgb: Int

    protected open val previewLabel: String = "Ring"

    override suspend fun onComplicationRequest(request: ComplicationRequest): ComplicationData? {
        val summary = WatchSummaryStore(this).load()
        val rings = summary?.rings.orEmpty()
        val dataIndex = RingSurfaceOrder.payloadIndexForOuterSlot(rings.size, ringIndex)
        val ring = dataIndex?.let { rings[it] }
        val remaining = ring?.let { WatchComplicationText.remainingPercent(it.usedPercent) }
        val label = ring?.label
        return when (request.complicationType) {
            // NoData clears a previous arc; null would leave stale complication data.
            ComplicationType.RANGED_VALUE ->
                if (ring == null || remaining == null || remaining <= 0f) {
                    NoDataComplicationData()
                } else {
                    // Credits live on the center strip; keep RANGED_VALUE TITLE empty.
                    ComplicationBuilders.ranged(
                        this,
                        remaining,
                        title = null,
                        colorArgb = RingFamily.colorArgb(ring.id),
                        contentDescription = label,
                    )
                }
            ComplicationType.SHORT_TEXT -> {
                // Dedicated strip slots own SHORT_TEXT; this path is rarely used.
                val payload =
                    if (summary != null && dataIndex != null) {
                        WatchComplicationText.stripPayload(summary, dataIndex)
                    } else {
                        null
                    }
                if (payload == null || summary == null || dataIndex == null) {
                    NoDataComplicationData()
                } else {
                    ComplicationBuilders.shortText(
                        this,
                        value = payload.text,
                        title = payload.title,
                        contentDescription = label
                            ?: WatchComplicationText.stripLabel(summary, dataIndex)
                            ?: payload.text,
                    )
                }
            }
            else -> null
        }
    }

    override fun getPreviewData(type: ComplicationType): ComplicationData? =
        when (type) {
            ComplicationType.RANGED_VALUE ->
                ComplicationBuilders.ranged(
                    this,
                    previewPercent,
                    title = previewLabel,
                    colorArgb = previewColorArgb,
                )
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
        title: String? = null,
    ): ComplicationData =
        ShortTextComplicationData.Builder(
            text = PlainComplicationText.Builder(value).build(),
            contentDescription = PlainComplicationText.Builder(contentDescription).build(),
        ).apply {
            if (!title.isNullOrBlank()) {
                setTitle(PlainComplicationText.Builder(title).build())
            }
        }.setTapAction(tapAction(context)).build()

    fun ranged(
        context: Context,
        percent: Float,
        title: String? = null,
        colorArgb: Int = RingFamily.FALLBACK,
        contentDescription: String? = null,
    ): ComplicationData {
        val value = percent.coerceIn(0f, 100f)
        val amount = WatchComplicationText.percentAmount(value)
        val description =
            contentDescription?.let { "$it $amount%" }
                ?: title?.let { "$amount% · $it" }
                ?: WatchComplicationText.percentLabel(value)
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
            // Drives WFF WeightedStroke via [COMPLICATION.RANGED_VALUE_COLORS].
            .setColorRamp(ColorRamp(intArrayOf(colorArgb), /* interpolated = */ false))
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

/**
 * Outermost WFF arc slot. Class name kept for installed faces.
 * Binds payload index (n-1) — loosest remaining when multiple rings are active.
 */
class TodayComplicationDataSourceService : RingComplicationDataSourceService() {
    override val ringIndex = 0
    override val previewPercent = 72f
    override val previewColorArgb = RingFamily.CURSOR
    override val previewLabel = "Ring 1"
}

/**
 * Second-from-outside WFF arc slot. Class name kept for installed faces.
 */
class WeekComplicationDataSourceService : RingComplicationDataSourceService() {
    override val ringIndex = 1
    override val previewPercent = 39f
    override val previewColorArgb = RingFamily.CLAUDE
    override val previewLabel = "Ring 2"
}

/** Third-from-outside WFF arc slot (toward center as count grows). */
class Ring3ComplicationDataSourceService : RingComplicationDataSourceService() {
    override val ringIndex = 2
    override val previewPercent = 8f
    override val previewColorArgb = RingFamily.CODEX
    override val previewLabel = "Ring 3"
}

class Ring4ComplicationDataSourceService : RingComplicationDataSourceService() {
    override val ringIndex = 3
    override val previewPercent = 75f
    override val previewColorArgb = RingFamily.BUDGET
    override val previewLabel = "Ring 4"
}

class StatusComplicationDataSourceService : ShortTextComplicationDataSourceService() {
    override val previewText = "SYNC"

    override fun text(summary: WatchDashboardSummary) =
        WatchComplicationText.status(summary)
}

/**
 * Center-most sunk strip SHORT_TEXT provider (payload index 0 / tightest).
 *
 * WFF `length([COMPLICATION.TITLE])` Conditions are unreliable, so TEXT carries the full
 * human label (`100%`, `100% · 500`, or credits-only `500`). Template is `%s` (no extra `%`).
 *
 * Class name kept for WFF primaryProvider continuity; payload field is creditsGlance.
 */
class TokensComplicationDataSourceService : SuspendingComplicationDataSourceService() {
    override suspend fun onComplicationRequest(request: ComplicationRequest): ComplicationData? {
        if (request.complicationType != ComplicationType.SHORT_TEXT) {
            return null
        }
        val summary = WatchSummaryStore(this).load() ?: return NoDataComplicationData()
        // Strip stack top (nearest center) = payload index 0 = tightest.
        val label = WatchComplicationText.stripLabel(summary, 0) ?: return NoDataComplicationData()
        return ComplicationBuilders.shortText(
            this,
            value = label,
            contentDescription = label,
        )
    }

    override fun getPreviewData(type: ComplicationType): ComplicationData? =
        if (type == ComplicationType.SHORT_TEXT) {
            ComplicationBuilders.shortText(
                this,
                value = "8% · 500",
                contentDescription = "8% · 500",
            )
        } else {
            null
        }
}

abstract class RingStripComplicationDataSourceService : SuspendingComplicationDataSourceService() {
    protected abstract val ringIndex: Int
    protected abstract val previewText: String
    protected open val previewTitle: String? = null

    override suspend fun onComplicationRequest(request: ComplicationRequest): ComplicationData? {
        if (request.complicationType != ComplicationType.SHORT_TEXT) {
            return null
        }
        val summary = WatchSummaryStore(this).load()
        val payload = summary?.let { WatchComplicationText.stripPayload(it, ringIndex) }
        return if (payload == null) {
            NoDataComplicationData()
        } else {
            ComplicationBuilders.shortText(
                this,
                value = payload.text,
                title = payload.title,
                contentDescription = WatchComplicationText.stripLabel(summary, ringIndex)
                    ?: payload.text,
            )
        }
    }

    override fun getPreviewData(type: ComplicationType): ComplicationData? =
        if (type == ComplicationType.SHORT_TEXT) {
            ComplicationBuilders.shortText(this, previewText, title = previewTitle)
        } else {
            null
        }
}

class Strip2ComplicationDataSourceService : RingStripComplicationDataSourceService() {
    override val ringIndex = 1
    override val previewText = "39"
}

class Strip3ComplicationDataSourceService : RingStripComplicationDataSourceService() {
    override val ringIndex = 2
    override val previewText = "72"
}

class Strip4ComplicationDataSourceService : RingStripComplicationDataSourceService() {
    override val ringIndex = 3
    override val previewText = "75"
}

object WatchComplicationText {
    /** Remaining capacity 0–100 for RANGED_VALUE / strip-style labels. */
    fun remainingPercent(usedPercent: Double): Float =
        (100.0 - usedPercent.coerceIn(0.0, 100.0)).toFloat().coerceIn(0f, 100f)

    data class StripPayload(
        /** Remaining digits only — WFF Template appends '%'. */
        val text: String,
        /** Optional remaining credits for the center (first) strip (`8% · 500`). */
        val title: String? = null,
    )

    /** Digits (+ optional title) for WFF SHORT_TEXT strip slots. */
    fun stripPayload(summary: WatchDashboardSummary, index: Int): StripPayload? {
        val ring = summary.rings.getOrNull(index) ?: return null
        val remaining = remainingPercent(ring.usedPercent)
        if (remaining <= 0f) {
            return null
        }
        val credits =
            if (index == 0) summary.creditsGlance?.text?.takeIf { it.isNotBlank() } else null
        return StripPayload(text = percentAmount(remaining), title = credits)
    }

    /**
     * Human strip label for surface ring [index] (`WATCH_RING_DESIGN.md`):
     * `8%`, `8% · 500`, or credits-only on strip 0 when there is no plan ring.
     */
    fun stripLabel(summary: WatchDashboardSummary?, index: Int): String? {
        if (summary == null) {
            return null
        }
        val payload = stripPayload(summary, index)
        if (payload != null) {
            return if (payload.title != null) {
                "${payload.text}% · ${payload.title}"
            } else {
                "${payload.text}%"
            }
        }
        if (index == 0) {
            return summary.creditsGlance?.text?.takeIf { it.isNotBlank() }
        }
        return null
    }

    /** Remaining-% label for surface ring [index] (payload order, not budget period). */
    fun ringRemainingPercent(summary: WatchDashboardSummary, index: Int): String {
        val used = summary.rings.getOrNull(index)?.usedPercent ?: return "—"
        return percentLabel(remainingPercent(used))
    }

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
        Ring3ComplicationDataSourceService::class.java,
        Ring4ComplicationDataSourceService::class.java,
        StatusComplicationDataSourceService::class.java,
        TokensComplicationDataSourceService::class.java,
        Strip2ComplicationDataSourceService::class.java,
        Strip3ComplicationDataSourceService::class.java,
        Strip4ComplicationDataSourceService::class.java,
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
