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
import app.wardpulse.wear.model.RingHalf
import app.wardpulse.wear.model.RingSummary
import app.wardpulse.wear.model.RingSurfaceOrder
import app.wardpulse.wear.model.WatchDashboardSummary
import app.wardpulse.wear.model.WatchDataMode
import app.wardpulse.wear.ui.RingFamily
import app.wardpulse.wear.ui.formatPercentAmount
import app.wardpulse.wear.ui.formatPercentLabel
import app.wardpulse.wear.ui.formatBudgetStripLabel
import app.wardpulse.wear.ui.purchasedCreditsCompact
import java.time.Instant
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

/**
 * The outer half of a split band: the other pool of a plan that shares one band
 * (`WATCH_RING_DESIGN.md`, Split band).
 *
 * Split ordinal 0 uses slot 106. Class name kept for installed faces.
 *
 * On an old face, one pair loses its far marker. With two pairs, the first keeps
 * both arcs without its marker; the second loses its outer arc, and old slot 109
 * treats that arc's data as a marker, possibly on another row. Update the face
 * together with the app to restore the matching layout.
 */
class RingSplitComplicationDataSourceService : SplitBandComplicationDataSourceService(SPLIT_INDEX) {
    internal companion object {
        const val SPLIT_INDEX = 0
    }
}

/** Two outer-half services share selection by split ordinal and outside-counted TITLE. */
abstract class SplitBandComplicationDataSourceService(private val splitIndex: Int) :
    SuspendingComplicationDataSourceService() {
    override suspend fun onComplicationRequest(request: ComplicationRequest): ComplicationData? {
        if (request.complicationType != ComplicationType.RANGED_VALUE) {
            return null
        }
        val rings = WatchSummaryStore(this).load()?.rings.orEmpty()
        return outerHalfComplicationData(rings, splitIndex) { half, outerSlot ->
            ComplicationBuilders.ranged(
                this,
                WatchComplicationText.remainingPercent(half.usedPercent),
                title = outerSlot.toString(),
                colorArgb = RingFamily.colorArgb(half.id),
                contentDescription = half.label,
            )
        }
    }

    override fun getPreviewData(type: ComplicationType): ComplicationData? =
        if (type == ComplicationType.RANGED_VALUE) {
            ComplicationBuilders.ranged(
                this,
                62f,
                title = "0",
                colorArgb = RingFamily.CURSOR,
                contentDescription = "Other Models",
            )
        } else {
            null
        }
}

/** Missing/invalid splits clear stale data; exhausted halves retain their tracks. */
internal fun outerHalfComplicationData(
    rings: List<RingSummary>,
    splitIndex: Int,
    build: (RingHalf, Int) -> ComplicationData,
): ComplicationData {
    val payloadIndex = rings.indices.filter { rings[it].split != null }.getOrNull(splitIndex)
        ?: return NoDataComplicationData()
    val half = rings[payloadIndex].split ?: return NoDataComplicationData()
    val outerSlot = RingSurfaceOrder.outerSlotForPayloadIndex(rings.size, payloadIndex)
        ?: return NoDataComplicationData()
    if (!half.usedPercent.isFinite() || half.usedPercent < 0.0) {
        return NoDataComplicationData()
    }
    return build(half, outerSlot)
}

/**
 * The legend row a face draws when the payload carries credits but no plan ring.
 * It is a ring slot's data because the row is a ring slot's to paint now, and it
 * names [WatchComplicationText.CREDITS_TOKEN] so the face knows to leave the
 * band out. The colour follows the credits provider's own family, as the strip
 * slot's did before the fold.
 */
internal fun creditsOnlyComplicationData(
    summary: WatchDashboardSummary,
    build: (String, Int) -> ComplicationData,
): ComplicationData {
    val label = WatchComplicationText.stripLabel(summary, 0) ?: return NoDataComplicationData()
    val colorArgb =
        summary.creditsGlance?.provider?.let { provider ->
            RingFamily.colorArgb("allowance.$provider.credits")
        } ?: RingFamily.FALLBACK
    return build(label, colorArgb)
}

/** Selects the ring for one fixed face slot before Android complication construction. */
internal fun ringComplicationData(
    rings: List<RingSummary>,
    ringIndex: Int,
    build: (RingSummary, Float, String) -> ComplicationData,
): ComplicationData {
    val dataIndex =
        RingSurfaceOrder.payloadIndexForOuterSlot(rings.size, ringIndex)
            ?: return NoDataComplicationData()
    val ring = rings[dataIndex]
    if (!ring.usedPercent.isFinite() || ring.usedPercent < 0.0) {
        return NoDataComplicationData()
    }
    val remaining = WatchComplicationText.remainingPercent(ring.usedPercent)
    return build(ring, remaining, WatchComplicationText.ringTitleToken(ring))
}

/**
 * The row index whose slot carries the lone credits reading when no plan ring
 * exists. The stack anchors to its bottom row, so a single row belongs on the
 * lowest one, and that row is painted by the outermost slot
 * (`WATCH_RING_DESIGN.md`, Upper cells, rule 3).
 */
internal const val CREDITS_RING_INDEX = 0

/**
 * The ranged value a credits-only row carries. Nothing draws an arc from it —
 * the face branches the band away on the title — but a `RANGED_VALUE` must
 * still carry one, and a full bar is the honest reading of a row that is not
 * reporting a remaining share of anything.
 */
private const val CREDITS_ONLY_PERCENT = 100f

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
        val label = ring?.label
        return when (request.complicationType) {
            // NoData clears a previous arc; null would leave stale complication data.
            ComplicationType.RANGED_VALUE ->
                if (summary != null && dataIndex == null && ringIndex == CREDITS_RING_INDEX) {
                    // No plan ring at all: this slot still owes the face a
                    // legend row, and the face draws it without a band because
                    // the title says there is none.
                    creditsOnlyComplicationData(summary) { creditsLabel, colorArgb ->
                        ComplicationBuilders.ranged(
                            this,
                            CREDITS_ONLY_PERCENT,
                            title = WatchComplicationText.CREDITS_TOKEN,
                            colorArgb = colorArgb,
                            contentDescription = creditsLabel,
                            text = creditsLabel,
                        )
                    }
                } else {
                    ringComplicationData(rings, ringIndex) { selectedRing, remaining, title ->
                        // One slot, two jobs: TEXT carries the strip label the
                        // folded row prints, TITLE what the face branches on —
                        // the budget period, a shared band and its outer pool,
                        // or the explicit empty full-band state.
                        ComplicationBuilders.ranged(
                            this,
                            remaining,
                            title = title,
                            colorArgb = RingFamily.colorArgb(selectedRing.id),
                            contentDescription = selectedRing.label,
                            text = dataIndex?.let {
                                WatchComplicationText.stripLabel(summary, it)
                            },
                        )
                    }
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

    /**
     * A ring slot's data. [text] is the legend row this slot now paints below
     * the wordmark — the band itself never reads TEXT, which is what left the
     * channel free when the strips folded in. Without one the row falls back to
     * the bare percentage it printed before.
     */
    fun ranged(
        context: Context,
        percent: Float,
        title: String,
        colorArgb: Int = RingFamily.FALLBACK,
        contentDescription: String? = null,
        text: String? = null,
    ): ComplicationData =
        rangedComplicationBuilder(percent, title, colorArgb, contentDescription, text)
            .setTapAction(tapAction(context))
            .build()

    private fun tapAction(context: Context): PendingIntent =
        PendingIntent.getActivity(
            context,
            0,
            Intent(context, MainActivity::class.java),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
}

/** AndroidX ranged data construction, separated from Android tap-action setup. */
internal fun rangedComplicationBuilder(
    percent: Float,
    title: String,
    colorArgb: Int = RingFamily.FALLBACK,
    contentDescription: String? = null,
    text: String? = null,
): RangedValueComplicationData.Builder {
    val value = percent.coerceIn(0f, 100f)
    val amount = WatchComplicationText.percentAmount(value)
    val label = text?.takeIf { it.isNotBlank() } ?: amount
    val description = contentDescription?.let { "$it $amount%" }
        ?: title.takeIf { it.isNotEmpty() }?.let { "$amount% · $it" }
        ?: WatchComplicationText.percentLabel(value)
    return RangedValueComplicationData.Builder(
        value = value,
        min = 0f,
        max = 100f,
        contentDescription = PlainComplicationText.Builder(description).build(),
    ).setText(PlainComplicationText.Builder(label).build())
        .setTitle(PlainComplicationText.Builder(title).build())
        .setColorRamp(ColorRamp(intArrayOf(colorArgb), /* interpolated = */ false))
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

class StatusComplicationDataSourceService : ShortTextComplicationDataSourceService() {
    override val previewText = "SYNC"

    override fun text(summary: WatchDashboardSummary) =
        WatchComplicationText.status(summary)
}

/**
 * Split ordinal 1 in slot 109, formerly the far strip marker. Class name kept
 * for installed faces; the updater still requests both outer-half services.
 *
 * On an old face, one pair loses its far marker because this service returns
 * NoData. With two pairs, the first keeps both arcs without its marker; the
 * second has no outer arc, and slot 109 interprets its outside-counted TITLE
 * as a strip row, possibly marking another row. Updating the face fixes both.
 */
class StripSplitComplicationDataSourceService : SplitBandComplicationDataSourceService(SPLIT_INDEX) {
    internal companion object {
        const val SPLIT_INDEX = 1
    }
}

object WatchComplicationText {
    /**
     * What a band's own slot puts in TITLE when it draws only its inner half.
     * The face branches on this string; keep it in step with
     * `tools/render-watchface.mjs`.
     */
    const val SPLIT_TOKEN = "split"
    const val ZERO_TOKEN = "zero"
    const val ZERO_INNER_TOKEN = "zero-inner"
    const val ZERO_OUTER_TOKEN = "zero-outer"
    const val ZERO_BOTH_TOKEN = "zero-both"

    /**
     * Closed outer-pool vocabulary. A new pool color needs a matching static
     * branch in tools/render-watchface.mjs and an entry in the design palette.
     */
    fun splitPoolToken(ringId: String): String? =
        when (ringId) {
            "allowance.cursor.cursor-plan-other" -> "cursor-other"
            "allowance.codex.spark" -> "spark"
            else -> null
        }

    /** Known outer-pool identity stays visible even when its track is empty. */
    fun stripTitleToken(ring: RingSummary): String? {
        val half = ring.split ?: return null
        if (!half.usedPercent.isFinite() || half.usedPercent < 0.0) {
            return null
        }
        return splitPoolToken(half.id)
    }

    /** Remaining capacity 0–100 for RANGED_VALUE / strip-style labels. */
    fun remainingPercent(usedPercent: Double): Float =
        (100.0 - usedPercent.coerceIn(0.0, 100.0)).toFloat().coerceIn(0f, 100f)

    /** The lone legend row when there is no ring at all — a reading with no band. */
    const val CREDITS_TOKEN = "credits"

    /** Joins a band's own token to the outer-pool token of the strip it carries. */
    const val TOKEN_SEPARATOR = ":"

    /**
     * Everything a ring slot tells the face about itself, in the one string a
     * complication may carry: [SPLIT_TOKEN] when the band is shared with a
     * second pool, otherwise its budget period or an explicit empty value for
     * an unpaired plan.
     *
     * Since the strips folded into the ring slots, that one string also has to
     * name the outer pool the row marks, so a shared band suffixes its pool
     * token after [TOKEN_SEPARATOR]. The vocabulary stays closed and short: only
     * a split band carries a pool, and a budget ring is never shared, so no
     * period token ever gains a suffix (`WATCH_RING_DESIGN.md`, Upper cells,
     * rule 4). Keep every spelling in step with `tools/render-watchface.mjs`,
     * which matches each one whole.
     */
    fun ringTitleToken(ring: RingSummary): String {
        val split = ring.split?.takeIf { it.usedPercent.isFinite() && it.usedPercent >= 0.0 }
        if (split == null) {
            return ringPeriodToken(ring.id)
                ?: if (ring.usedPercent >= 100.0) ZERO_TOKEN else ""
        }
        val pool = stripTitleToken(ring)
        val base = if (pool == null) SPLIT_TOKEN else "$SPLIT_TOKEN$TOKEN_SEPARATOR$pool"
        val innerZero = ring.usedPercent >= 100.0
        val outerZero = split.usedPercent >= 100.0
        val zero = when {
            innerZero && outerZero -> ZERO_BOTH_TOKEN
            innerZero -> ZERO_INNER_TOKEN
            outerZero -> ZERO_OUTER_TOKEN
            else -> null
        }
        return if (zero == null) base else "$base$TOKEN_SEPARATOR$zero"
    }

    /**
     * The period token the watch face repeats around a ring, read off the ring
     * id the way [RingFamily.colorArgb] reads the family. Null for a ring that
     * has no period — a plan window or an allowance is a moving window, not a
     * calendar period — and the face draws no texture for a slot that names
     * none.
     *
     * `7D` rather than `W`: at ring scale `W` and `M` are near-mirror shapes,
     * and the watch already labels the Claude window `5h`, so duration tokens
     * are the house vocabulary (`docs/product/WATCH_RING_DESIGN.md`).
     */
    fun ringPeriodToken(ringId: String): String? =
        when {
            !ringId.startsWith("budget.") -> null
            ringId.endsWith(".today") -> "D"
            ringId.endsWith(".week") -> "7D"
            ringId.endsWith(".month") -> "M"
            else -> null
        }

    /**
     * Human strip label for surface ring [index] (`WATCH_RING_DESIGN.md`):
     * `8%`, or `8% · 500` when that ring's provider reports purchased credits
     * (same per-family source as Glance). Credits-only on strip 0 when there is
     * no plan ring. A budget ring reads its money instead — `$12.34/100`.
     */
    fun stripLabel(summary: WatchDashboardSummary?, index: Int): String? {
        if (summary == null) {
            return null
        }
        val ring = summary.rings.getOrNull(index)
        if (ring != null) {
            if (!ring.usedPercent.isFinite() || ring.usedPercent < 0.0) {
                return null
            }
            val remaining = remainingPercent(ring.usedPercent)
            formatBudgetStripLabel(ring.spent, ring.limit)?.let { return it }
            val percent = percentAmount(remaining)
            // A split band spends the well on its second percent instead of
            // credits (`WATCH_RING_DESIGN.md`, Split band, rules 4 and 5).
            val half = ring.split?.takeIf { it.usedPercent.isFinite() && it.usedPercent >= 0.0 }
                ?.let { remainingPercent(it.usedPercent) }
            if (half != null) {
                return "$percent% · ${percentAmount(half)}%"
            }
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

    fun status(summary: WatchDashboardSummary, now: Instant = Instant.now()): String {
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
            summary.isStaleAt(now) -> PulseStatus.STALE
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
        RingSplitComplicationDataSourceService::class.java,
        StatusComplicationDataSourceService::class.java,
        StripSplitComplicationDataSourceService::class.java,
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
