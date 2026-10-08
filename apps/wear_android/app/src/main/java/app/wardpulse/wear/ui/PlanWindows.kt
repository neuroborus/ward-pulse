package app.wardpulse.wear.ui

import app.wardpulse.wear.model.AllowanceSummary
import app.wardpulse.wear.model.PulseStatus
import app.wardpulse.wear.model.WatchDashboardSummary
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.format.DateTimeParseException
import java.util.Locale

/**
 * One plan window on the second page: what is left of it, and when it returns
 * (`apps/wear_android/README.md`, Plan windows).
 */
data class PlanWindowRow(
    val title: String,
    val detail: String,
    val status: PulseStatus,
)

/**
 * Plan windows, the ones waited on first.
 *
 * The Glance answers how much is left; this list answers when a window comes
 * back, which is why it keeps the exhausted ones the Glance omits and the
 * untouched ones nobody is waiting for: it is also the inventory of what the
 * watch knows, and a list that changed shape with every poll would leave "not
 * spent" indistinguishable from "not reported".
 */
fun planWindowRows(
    summary: WatchDashboardSummary,
    now: Instant,
    zone: ZoneId = ZoneId.systemDefault(),
): List<PlanWindowRow> =
    summary.allowances
        // Purchased meters do not come back, they are bought again.
        .filter { it.source == "plan" }
        .sortedWith(planWindowOrder(now))
        .map { allowance ->
            PlanWindowRow(
                title = allowance.label,
                detail = detailOf(allowance, now, zone),
                status = allowance.status,
            )
        }

/**
 * Exhausted first — the screen is read when something has run out — then by the
 * soonest return. A window that cannot name a future moment sorts last inside
 * its group: it has nothing to compete with.
 */
private fun planWindowOrder(now: Instant): Comparator<AllowanceSummary> =
    compareByDescending<AllowanceSummary> { it.isExhausted }
        .thenBy { it.returnsAt(now) ?: Instant.MAX }
        .thenBy { it.label }

/**
 * A window without a share has run out when what it does report has: a plan with
 * no published ceiling counts down a remainder instead, and a line reading
 * `0 credits left` belongs at the top like any other empty window.
 */
private val AllowanceSummary.isExhausted: Boolean
    get() = when {
        unlimited -> false
        usedPercent != null -> usedPercent >= 100.0
        else -> remaining?.value?.toDoubleOrNull()?.let { it <= 0.0 } == true
    }

/**
 * The moment this window is next expected to roll, or `null` when it cannot say.
 *
 * A reset already behind counts as none: the provider has not caught up with
 * its own clock — Cursor aggregates about hourly — and a moment that has passed
 * would say the window is late rather than that the number is.
 */
private fun AllowanceSummary.returnsAt(now: Instant): Instant? {
    val resetsAt = resetsAt ?: return null
    return try {
        Instant.parse(resetsAt).takeIf { it.isAfter(now) }
    } catch (_: DateTimeParseException) {
        null
    }
}

/**
 * `6% left · back at 19:00`, with either half dropped when it cannot be said: a
 * window reporting no percentage is not a full one, and one that cannot name a
 * future moment says nothing about time.
 *
 * The share falls back to the bare remainder, as the Usage screen does: a plan
 * with no published limit — Cursor's, when the team ceiling is unknown — knows
 * how much is left without knowing the share it makes up.
 *
 * A window that can say neither reads `Unavailable`, the same word the rest of
 * the watch uses for a meter that reported nothing — an empty line under a
 * label would look like a rendering fault instead.
 */
private fun detailOf(
    allowance: AllowanceSummary,
    now: Instant,
    zone: ZoneId,
): String {
    val left = when {
        allowance.unlimited -> "Unlimited"
        allowance.usedPercent != null -> "${formatPercentRemainingLabel(allowance.usedPercent)} left"
        allowance.remaining != null -> "${allowance.remaining.label} left"
        else -> null
    }
    val back = allowance.returnsAt(now)?.let { backLabel(it, now, zone) }
    return listOfNotNull(left, back).joinToString(" · ").ifEmpty { "Unavailable" }
}

/**
 * Today keeps the clock alone; any other day carries its date, so tomorrow
 * evening never reads like tonight.
 */
private fun backLabel(returnsAt: Instant, now: Instant, zone: ZoneId): String {
    // `atZone().toLocalDate()`, not `LocalDate.ofInstant`: the latter is API 34
    // and this app runs from 30.
    val sameDay = returnsAt.atZone(zone).toLocalDate() == now.atZone(zone).toLocalDate()
    val format = if (sameDay) BACK_TODAY_FORMAT else BACK_DATED_FORMAT
    return "back ${format.withZone(zone).format(returnsAt)}"
}

private val BACK_TODAY_FORMAT: DateTimeFormatter =
    DateTimeFormatter.ofPattern("'at' HH:mm", Locale.US)

private val BACK_DATED_FORMAT: DateTimeFormatter =
    DateTimeFormatter.ofPattern("MMM d, HH:mm", Locale.US)
