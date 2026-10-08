package app.wardpulse.wear.ui

import kotlin.math.roundToInt

/** Compact percent labels for glanceable Wear surfaces — never raw Double.toString(). */
internal fun formatPercentLabel(percent: Double?): String {
    val amount = formatPercentAmount(percent) ?: return "—"
    return "$amount%"
}

/** Integer percent without a '%' suffix — safe for WFF printf-style templates. */
internal fun formatPercentAmount(percent: Double?): String? {
    if (percent == null || !percent.isFinite()) {
        return null
    }
    return percent.coerceIn(0.0, 100.0).roundToInt().toString()
}

/** Remaining capacity label — matches arc / strip semantics. */
internal fun formatPercentRemainingLabel(usedPercent: Double): String =
    formatPercentLabel((100.0 - usedPercent.coerceIn(0.0, 100.0)).coerceAtLeast(0.0))
