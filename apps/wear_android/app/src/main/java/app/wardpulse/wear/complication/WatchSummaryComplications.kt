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
import app.wardpulse.wear.model.WatchDataMode
import app.wardpulse.wear.ui.RingFamily
import app.wardpulse.wear.ui.formatPercentAmount
import app.wardpulse.wear.ui.formatPercentLabel
import app.wardpulse.wear.ui.purchasedCreditsCompact
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
                val labelText =
                    if (summary != null && dataIndex != null) {
                        WatchComplicationText.stripLabel(summary, dataIndex)
                    } else {
                        null
                    }
                if (labelText == null) {
                    NoDataComplicationData()
                } else {
                    ComplicationBuilders.shortText(
                        this,
                        value = labelText,
                        contentDescription = label ?: labelText,
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

    /** Strip row: full label in TEXT + family ColorRamp for the accent (no face arc). */
    fun strip(
        context: Context,
        label: String,
        remainingPercent: Float,
        colorArgb: Int,
    ): ComplicationData {
        val value = remainingPercent.coerceIn(0.1f, 100f)
        return RangedValueComplicationData.Builder(
            value = value,
            min = 0f,
            max = 100f,
            contentDescription = PlainComplicationText.Builder(label).build(),
        ).setText(PlainComplicationText.Builder(label).build())
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
 * Payload-index strip provider (0 = tightest / nearest center).
 *
 * Emits [RANGED_VALUE] so WFF can paint the family accent from
 * `[COMPLICATION.RANGED_VALUE_COLORS]` — same ColorRamp path as the arcs.
 * TEXT is the full strip label (`46%`, `100% · 500`); the ranged value is unused for an arc.
 *
 * Class name kept for WFF primaryProvider continuity.
 */
class TokensComplicationDataSourceService : RingStripComplicationDataSourceService() {
    override val ringIndex = 0
    override val previewText = "8% · 500"
    override val previewColorArgb = RingFamily.CODEX
}

abstract class RingStripComplicationDataSourceService : SuspendingComplicationDataSourceService() {
    protected abstract val ringIndex: Int
    protected abstract val previewText: String
    protected open val previewColorArgb: Int = RingFamily.FALLBACK

    override suspend fun onComplicationRequest(request: ComplicationRequest): ComplicationData? {
        if (request.complicationType != ComplicationType.RANGED_VALUE) {
            return null
        }
        val summary = WatchSummaryStore(this).load() ?: return NoDataComplicationData()
        val label = WatchComplicationText.stripLabel(summary, ringIndex)
            ?: return NoDataComplicationData()
        val ring = summary.rings.getOrNull(ringIndex)
        val colorArgb =
            when {
                ring != null -> RingFamily.colorArgb(ring.id)
                else ->
                    summary.creditsGlance?.provider?.let { provider ->
                        RingFamily.colorArgb("allowance.$provider.credits")
                    } ?: RingFamily.FALLBACK
            }
        val remaining =
            ring?.let { WatchComplicationText.remainingPercent(it.usedPercent) } ?: 100f
        return ComplicationBuilders.strip(
            this,
            label = label,
            remainingPercent = remaining,
            colorArgb = colorArgb,
        )
    }

    override fun getPreviewData(type: ComplicationType): ComplicationData? =
        if (type == ComplicationType.RANGED_VALUE) {
            ComplicationBuilders.strip(
                this,
                label = previewText,
                remainingPercent = 100f,
                colorArgb = previewColorArgb,
            )
        } else {
            null
        }
}

class Strip2ComplicationDataSourceService : RingStripComplicationDataSourceService() {
    override val ringIndex = 1
    override val previewText = "39%"
    override val previewColorArgb = RingFamily.CLAUDE
}

class Strip3ComplicationDataSourceService : RingStripComplicationDataSourceService() {
    override val ringIndex = 2
    override val previewText = "72%"
    override val previewColorArgb = RingFamily.CURSOR
}

class Strip4ComplicationDataSourceService : RingStripComplicationDataSourceService() {
    override val ringIndex = 3
    override val previewText = "75%"
    override val previewColorArgb = RingFamily.BUDGET
}

object WatchComplicationText {
    /** Remaining capacity 0–100 for RANGED_VALUE / strip-style labels. */
    fun remainingPercent(usedPercent: Double): Float =
        (100.0 - usedPercent.coerceIn(0.0, 100.0)).toFloat().coerceIn(0f, 100f)

    data class StripPayload(
        /** Full strip label for WFF Template `%s` (`46%`, `100% · 500`). */
        val text: String,
    )

    /** Full label for WFF SHORT_TEXT strip slots. */
    fun stripPayload(summary: WatchDashboardSummary, index: Int): StripPayload? {
        val label = stripLabel(summary, index) ?: return null
        return StripPayload(text = label)
    }

    /**
     * Human strip label for surface ring [index] (`WATCH_RING_DESIGN.md`):
     * `8%`, or `8% · 500` when that ring's provider reports purchased credits
     * (same per-family source as Glance). Credits-only on strip 0 when there is
     * no plan ring.
     */
    fun stripLabel(summary: WatchDashboardSummary?, index: Int): String? {
        if (summary == null) {
            return null
        }
        val ring = summary.rings.getOrNull(index)
        if (ring != null) {
            val remaining = remainingPercent(ring.usedPercent)
            if (remaining <= 0f) {
                return null
            }
            val percent = percentAmount(remaining)
            val credits = purchasedCreditsCompact(summary, ring.id)
            return if (credits != null) {
                "$percent% · $credits"
            } else {
                "$percent%"
            }
        }
        if (index == 0) {
            return summary.creditsGlance?.text?.takeIf { it.isNotBlank() }
        }
        return null
    }

    /** `allowance.<provider>.…` → provider id; budgets / unknown → null. */
    fun providerFromRingId(ringId: String): String? {
        if (!ringId.startsWith("allowance.")) {
            return null
        }
        return ringId.split('.').getOrNull(1)?.takeIf { it.isNotBlank() }
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
        val source = when {
            // Mock outranks the provider names, matching the Glance detail order
            // (`WEAR_GLANCE_DESIGN.md`): the demo impersonates real families, so
            // nothing else here would say the numbers are not real.
            summary.dataMode == WatchDataMode.MOCK -> "MOCK"
            summary.providers.isEmpty() -> "NO DATA"
            summary.providers.size == 1 ->
                summary.providers.single().providerLabel.uppercase(Locale.US)
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
