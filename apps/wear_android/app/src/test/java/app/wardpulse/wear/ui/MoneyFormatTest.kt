package app.wardpulse.wear.ui

import app.wardpulse.wear.model.Money
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class MoneyFormatTest {
    private fun usd(minorUnits: Long) = Money(minorUnits, "USD")

    @Test
    fun keepsCentsOnSpendAndRoundsTheLimit() {
        assertEquals("\$12.34/100", formatBudgetStripLabel(usd(1_234), usd(10_000)))
        // Widest budget label measured against the locked strip width.
        assertEquals("\$999.99/999", formatBudgetStripLabel(usd(99_999), usd(99_949)))
        assertEquals("\$5.2K/1M", formatBudgetStripLabel(usd(520_000), usd(100_000_000)))
    }

    @Test
    fun leavesCurrenciesItCannotSpellShortToThePercentLabel() {
        // `EUR 999.99/999` would be 18 % past the locked strip width.
        assertNull(formatBudgetStripLabel(Money(1_234, "EUR"), Money(10_000, "EUR")))
    }

    @Test
    fun refusesHalfKnownBudgets() {
        assertNull(formatBudgetStripLabel(null, usd(10_000)))
        assertNull(formatBudgetStripLabel(usd(1_234), null))
        // A ratio across currencies would be a made-up number.
        assertNull(formatBudgetStripLabel(usd(1_234), Money(10_000, "EUR")))
    }
}
