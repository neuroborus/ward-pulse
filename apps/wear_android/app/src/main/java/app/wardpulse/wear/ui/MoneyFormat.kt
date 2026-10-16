package app.wardpulse.wear.ui

import app.wardpulse.wear.model.Money
import java.util.Locale
import kotlin.math.abs
import kotlin.math.roundToLong

/**
 * Budget strip label — `$12.34/100`.
 *
 * The one strip that does not speak remaining-% (`WATCH_RING_DESIGN.md`): a budget ceiling is
 * a number the wearer typed, and spent-of-limit is how the product already names it. Null
 * unless both halves are present in one currency — a strip must not invent a ceiling.
 */
internal fun formatBudgetStripLabel(spent: Money?, limit: Money?): String? {
    if (spent == null || limit == null || spent.currency != limit.currency) {
        return null
    }
    val symbol = currencySymbol(spent.currency) ?: return null
    return "$symbol${spentAmount(spent)}/${limitAmount(limit)}"
}

/**
 * One glyph, or no money at all. Strip width is locked to `100% · 10.0M`, and a spelled-out
 * code (`EUR 999.99/999`) runs 18 % past it — wider even than the cents-on-both-halves form
 * the geometry rule already rejects. A currency we cannot spell short keeps its percent.
 */
private fun currencySymbol(currency: String): String? = if (currency == "USD") "$" else null

/** Cents matter while spend is small; past 1000 the compact form buys the width back. */
private fun spentAmount(money: Money): String {
    val major = money.minorUnits / 100.0
    if (abs(major) >= 1000) {
        return compactCreditCount(major)
    }
    return String.format(Locale.US, "%.2f", major)
}

/** Limits stay whole: cents on both halves (`$999.99/999.99`) overflow the strip. */
private fun limitAmount(money: Money): String =
    compactCreditCount((money.minorUnits / 100.0).roundToLong().toDouble())
