package app.wardpulse.wear.ui

import org.junit.Assert.assertEquals
import org.junit.Test

class PercentFormatTest {
    @Test
    fun roundsWithoutFloatNoise() {
        assertEquals("100%", formatPercentLabel(100.0))
        assertEquals("25%", formatPercentLabel(24.8))
        assertEquals("25%", formatPercentLabel(24.800000000000004))
        assertEquals("—", formatPercentLabel(null))
        assertEquals("—", formatPercentLabel(Double.NaN))
        assertEquals("100% used", formatPercentUsedLabel(100.0))
        assertEquals("0%", formatPercentRemainingLabel(100.0))
        assertEquals("75%", formatPercentRemainingLabel(24.8))
    }
}
