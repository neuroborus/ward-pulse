package app.wardpulse.wear.ui

import app.wardpulse.wear.model.PulseStatus
import app.wardpulse.wear.model.Quantity
import app.wardpulse.wear.model.WatchDashboardSummary
import app.wardpulse.wear.model.WatchDataMode
import app.wardpulse.wear.model.formatQuantityValue
import kotlin.math.roundToInt

/** Refresh control chrome for the Glance legend (`WEAR_GLANCE_DESIGN.md`). */
data class GlanceRefreshChrome(
    val ok: Boolean,
    val enabled: Boolean,
    val detail: String?,
)

data class GlanceLegendRowModel(
    val title: String,
    val subtitle: String,
    val remainingFraction: Float,
    val colorArgb: Int,
    val secondaryArc: GlanceLegendArcModel? = null,
    val exhaustedPercentRanges: List<IntRange> = emptyList(),
)

data class GlanceLegendArcModel(
    val remainingFraction: Float,
    val colorArgb: Int,
)

/**
 * Pulse (`ok`) and interactivity (`enabled`) are independent.
 * PollCadence floor cooldown (phone `manualRefreshAllowed`) keeps `ok` while
 * disabling the control without a detail line.
 */
fun glanceRefreshChrome(
    summary: WatchDashboardSummary,
    refreshAllowed: Boolean,
): GlanceRefreshChrome {
    val rateLimited =
        summary.overallStatus == PulseStatus.RATE_LIMITED ||
            summary.providers.any { it.status == PulseStatus.RATE_LIMITED }

    // Precedence is load-bearing (`WEAR_GLANCE_DESIGN.md`): a rate limit already reads as a
    // gray, disabled control, while stale and mock data have no channel but this line.
    val detail = when {
        summary.dataMode == WatchDataMode.MOCK -> "Mock data"
        summary.isStale || summary.overallStatus == PulseStatus.STALE -> "Stale"
        rateLimited -> "Rate limited"
        summary.overallStatus == PulseStatus.AUTH_REQUIRED -> "Auth required"
        summary.overallStatus == PulseStatus.WARNING -> "Warning"
        summary.overallStatus == PulseStatus.ERROR -> "Error"
        summary.overallStatus == PulseStatus.UNKNOWN -> "Unknown"
        summary.overallStatus == PulseStatus.OK -> null
        else -> summary.overallStatus.label
    }

    // Rate-limit blocks taps; phone cadence also blocks while pulse may stay OK.
    return GlanceRefreshChrome(
        ok = detail == null,
        enabled = !rateLimited && refreshAllowed,
        detail = detail,
    )
}

/**
 * Known pools, including exhausted ones, ordered tightest-first by the phone.
 *
 * A pair travels as one entry with its second pool inside (`WATCH_RING_DESIGN.md`,
 * Split band). Glance keeps one row per band, with the inner pool first.
 */
fun glanceLegendRows(summary: WatchDashboardSummary): List<GlanceLegendRowModel> {
    return summary.rings.mapNotNull { ring ->
        val inner = glanceLegendRow(summary, ring.id, ring.label, ring.usedPercent)
        val split = ring.split ?: return@mapNotNull inner
        val outer = glanceLegendRow(summary, split.id, split.label, split.usedPercent)
        when {
            inner == null -> outer
            outer == null -> inner
            else -> {
                val firstPercent = "${remainingPercent(ring.usedPercent).roundToInt()}%"
                val secondPercent = "${remainingPercent(split.usedPercent).roundToInt()}%"
                val secondStart = firstPercent.length + " · ".length
                inner.copy(
                    title = "${glanceFamilyName(ring.id) ?: ring.label} plan",
                    subtitle = glanceSubtitle(
                        summary,
                        ring.id,
                        "$firstPercent · $secondPercent left",
                    ),
                    secondaryArc = GlanceLegendArcModel(outer.remainingFraction, outer.colorArgb),
                    exhaustedPercentRanges = buildList {
                        if (ring.usedPercent >= 100.0) add(0 until firstPercent.length)
                        if (split.usedPercent >= 100.0) add(secondStart until secondStart + secondPercent.length)
                    },
                )
            }
        }
    }
}

private fun glanceLegendRow(
    summary: WatchDashboardSummary,
    ringId: String,
    label: String,
    usedPercent: Double,
): GlanceLegendRowModel? {
    if (!usedPercent.isFinite() || usedPercent < 0.0) {
        return null
    }
    val remaining = remainingPercent(usedPercent)
    return GlanceLegendRowModel(
        title = glancePrimaryLabel(ringId, label),
        subtitle = glanceSubtitle(summary, ringId, "${remaining.roundToInt()}% left"),
        remainingFraction = (remaining / 100.0).toFloat(),
        colorArgb = RingFamily.colorArgb(ringId),
        exhaustedPercentRanges = if (usedPercent >= 100.0) listOf(0 until 2) else emptyList(),
    )
}

private fun remainingPercent(usedPercent: Double): Double =
    100.0 - usedPercent.coerceIn(0.0, 100.0)

internal fun glancePrimaryLabel(ringId: String, label: String): String {
    val family = glanceFamilyName(ringId) ?: return label
    // Already named: composed by the phone (`Family · Pool`), or a pool name that
    // opens with its own family (`Cursor Models`).
    if (label.contains(" · ") || label.substringBefore(' ') == family) {
        return label
    }
    return when {
        family == "Claude" && label in listOf("5h", "Weekly", "Opus weekly", "Sonnet weekly") ->
            "$family plan · $label"
        family == "Codex" && label == "Weekly plan" -> "$family plan · Weekly"
        family == "Codex" && label in listOf("5h", "Weekly", "Spark 5h", "Spark Weekly") ->
            "$family plan · $label"
        else -> "$family · $label"
    }
}

internal fun glanceFamilyName(ringId: String): String? = when {
    ringId.startsWith("budget.") -> "Budget"
    ringId.startsWith("allowance.codex.") || ringId.contains(".codex.") -> "Codex"
    ringId.startsWith("allowance.openai.") || ringId.contains(".openai.") -> "OpenAI"
    ringId.startsWith("allowance.claude.") || ringId.contains(".claude.") -> "Claude"
    ringId.startsWith("allowance.cursor.") || ringId.contains(".cursor.") -> "Cursor"
    ringId.startsWith("allowance.mock.") || ringId.contains(".mock.") -> "Mock"
    else -> null
}

private fun glanceSubtitle(
    summary: WatchDashboardSummary,
    ringId: String,
    left: String,
): String {
    val credits = purchasedCreditsSuffix(summary, ringId) ?: return left
    return "$left · $credits"
}

/**
 * A balance as every text surface of the watch renders it: compact, so the Glance,
 * the plan windows page and the face strips cannot disagree about one number the
 * wearer sees a swipe apart (`WEAR_GLANCE_DESIGN.md`, revision 2026-10-11).
 *
 * A value the provider did not send as a number keeps its own text with the float
 * noise trimmed: inventing a rounding for something unparsed would say more than
 * the payload does.
 */
internal fun compactQuantityValue(value: String): String =
    value.toDoubleOrNull()?.let { compactCreditCount(it) } ?: formatQuantityValue(value)

/** The same number with its unit word, which only the wider surfaces have room for. */
internal fun Quantity.compactLabel(): String = "${compactQuantityValue(value)} $unit"

/** Purchased credits for a Glance row (`62.5K credits`), or null. */
internal fun purchasedCreditsSuffix(
    summary: WatchDashboardSummary,
    ringId: String,
): String? = purchasedRemainingForRing(summary, ringId)?.compactLabel()

/** The same balance without the unit word, for a face strip that has no room for it. */
internal fun purchasedCreditsCompact(
    summary: WatchDashboardSummary,
    ringId: String,
): String? = purchasedRemainingForRing(summary, ringId)?.let { compactQuantityValue(it.value) }

/**
 * The unit this channel carries. The shared contract allows `tokens` as well
 * (`schemas/dashboard_snapshot.schema.json`), and a balance in tokens is a
 * legitimate thing for a provider to report — it just has no place on a watch:
 * the face strip, the complication and the Glance row are the *credits* channel
 * (`PROVIDER_NOTES.md`, Consumption display), and every document that owns one
 * of them refuses token counts by name. The phone has filtered on this unit
 * since `credit_request_runway.dart`, which is why its widget can hardcode the
 * word `credits`; this is the watch side of the same guard.
 */
private const val CREDITS_UNIT = "credits"

/**
 * The one lookup behind every purchased balance the watch shows — the Glance
 * row, the face strip and the complication — so the unit is checked once here
 * rather than at three call sites that could drift apart.
 *
 * A balance in any other unit is treated as absent, which is a state all three
 * surfaces already draw: the Glance omits the suffix
 * (`WEAR_GLANCE_DESIGN.md`, acceptance), and the strip and complication show
 * the percentage alone. Rendering it instead would either put a token count on
 * a surface whose baseline forbids one, or label it `credits` and be wrong.
 */
internal fun purchasedRemainingForRing(
    summary: WatchDashboardSummary,
    ringId: String,
): Quantity? {
    val family = glanceFamilyName(ringId) ?: return null
    if (family == "Budget") {
        return null
    }
    val prefix = "$family · "
    return summary.allowances
        .firstOrNull { allowance ->
            allowance.source == "purchased" &&
                !allowance.unlimited &&
                allowance.remaining?.unit == CREDITS_UNIT &&
                allowance.label.startsWith(prefix)
        }
        ?.remaining
}

/** Compact credit count for face strips (matches phone `compactCreditCount`). */
internal fun compactCreditCount(value: Double): String {
    val absolute = kotlin.math.abs(value)
    val sign = if (value < 0) "-" else ""
    if (absolute < 1000) {
        val body =
            if (absolute == kotlin.math.floor(absolute)) {
                absolute.toLong().toString()
            } else {
                String.format(java.util.Locale.US, "%.1f", absolute)
            }
        return "$sign$body"
    }
    var amount = absolute / 1000
    var unit = 0
    val suffixes = arrayOf("K", "M", "B", "T")
    while (unit < suffixes.lastIndex && roundOneDecimal(amount) >= 1000) {
        amount /= 1000
        unit += 1
    }
    val rounded = roundOneDecimal(amount)
    val body =
        if (rounded == kotlin.math.floor(rounded)) {
            rounded.toLong().toString()
        } else {
            String.format(java.util.Locale.US, "%.1f", rounded)
        }
    return "$sign$body${suffixes[unit]}"
}

private fun roundOneDecimal(value: Double): Double = kotlin.math.round(value * 10) / 10.0
