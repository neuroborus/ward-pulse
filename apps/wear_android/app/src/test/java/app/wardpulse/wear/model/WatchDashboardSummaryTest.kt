package app.wardpulse.wear.model

import java.time.Instant
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class WatchDashboardSummaryTest {
    @Test
    fun treatsAnUnreadableTimestampAsStale() {
        val summary = PreviewWatchDashboardSummary.value.copy(generatedAt = "invalid")

        // A timestamp that cannot be read is treated as too old to trust.
        assertTrue(summary.isStaleAt(Instant.EPOCH))
    }

    @Test
    fun marksOldSummaryAsStale() {
        val summary = PreviewWatchDashboardSummary.value.copy(
            generatedAt = "2026-06-27T18:42:00Z",
            isStale = false,
        )

        assertFalse(summary.isStaleAt(Instant.parse("2026-06-27T20:41:59Z")))
        assertTrue(summary.isStaleAt(Instant.parse("2026-06-27T20:42:00Z")))
    }

    @Test
    fun manualRefreshHonorsPhoneFlagsAndWallClock() {
        val blocked =
            PreviewWatchDashboardSummary.value.copy(
                manualRefreshAllowed = false,
                manualRefreshAvailableAt = "2026-06-27T18:47:00Z",
            )
        assertFalse(blocked.isManualRefreshAllowed(Instant.parse("2026-06-27T18:46:59Z")))
        assertTrue(blocked.isManualRefreshAllowed(Instant.parse("2026-06-27T18:47:00Z")))

        val allowed =
            blocked.copy(manualRefreshAllowed = true, manualRefreshAvailableAt = null)
        assertTrue(allowed.isManualRefreshAllowed(Instant.parse("2026-06-27T18:42:00Z")))
    }

    @Test
    fun formatsMoneyFromMinorUnits() {
        assertEquals("USD 12.40", Money(1_240, "USD").label)
        assertEquals("-USD 0.05", Money(-5, "USD").label)
    }

    @Test
    fun trimsTrailingZerosFromQuantityLabels() {
        assertEquals("500 credits", Quantity("500.0000000000", "credits").label)
        assertEquals("12.5 credits", Quantity("12.50", "credits").label)
        assertEquals("12.5 credits", Quantity("12.5", "credits").label)
    }
}
