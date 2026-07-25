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

internal fun formatPercentUsedLabel(percent: Double?): String =
    "${formatPercentLabel(percent)} used"
