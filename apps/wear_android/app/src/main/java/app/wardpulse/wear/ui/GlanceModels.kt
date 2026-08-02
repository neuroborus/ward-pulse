package app.wardpulse.wear.ui

import app.wardpulse.wear.model.PulseStatus
import app.wardpulse.wear.model.Quantity
import app.wardpulse.wear.model.RingSummary
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

/** Active (non-exhausted) rings already ordered tightest-remaining first by the phone. */
fun glanceLegendRows(summary: WatchDashboardSummary): List<GlanceLegendRowModel> {
    return summary.rings
        .filter { it.usedPercent < 100.0 }
        .map { ring ->
            val remaining =
                (100.0 - ring.usedPercent.coerceIn(0.0, 100.0)).coerceAtLeast(0.0)
            GlanceLegendRowModel(
                title = glancePrimaryLabel(ring),
                subtitle = glanceSubtitle(summary, ring, remaining),
                remainingFraction = (remaining / 100.0).toFloat(),
                colorArgb = RingFamily.colorArgb(ring.id),
            )
        }
}

internal fun glancePrimaryLabel(ring: RingSummary): String {
    if (ring.label.contains(" · ")) {
        return ring.label
    }
    val family = glanceFamilyName(ring.id) ?: return ring.label
    return "$family · ${ring.label}"
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
    ring: RingSummary,
    remaining: Double,
): String {
    val left = "${remaining.roundToInt()}% left"
    val credits = purchasedCreditsSuffix(summary, ring.id) ?: return left
    return "$left · $credits"
}

/** Purchased credits for a ring family (`320 credits`), or null. Shared with the face. */
internal fun purchasedCreditsSuffix(
    summary: WatchDashboardSummary,
    ringId: String,
): String? {
    val remaining = purchasedRemainingForRing(summary, ringId) ?: return null
    return "${formatQuantityValue(remaining.value)} ${remaining.unit}"
}

/** Compact face strip credits (`320`, `1.2K`) — same family rule as Glance. */
internal fun purchasedCreditsCompact(
    summary: WatchDashboardSummary,
    ringId: String,
): String? {
    val remaining = purchasedRemainingForRing(summary, ringId) ?: return null
    val value = remaining.value.toDoubleOrNull() ?: return formatQuantityValue(remaining.value)
    return compactCreditCount(value)
}

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
                allowance.remaining != null &&
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
