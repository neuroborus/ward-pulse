package app.wardpulse.wear.model

import java.time.Instant
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class WatchDashboardSummaryTest {
    @Test
    fun formatsLastSyncInUtc() {
        assertEquals("Jun 27, 18:42 UTC", PreviewWatchDashboardSummary.value.lastSyncLabel)
    }

    @Test
    fun handlesInvalidTimestamp() {
        val summary = PreviewWatchDashboardSummary.value.copy(generatedAt = "invalid")

        assertEquals("Unknown", summary.lastSyncLabel)
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
    fun formatsMoneyFromMinorUnits() {
        assertEquals("USD 12.40", Money(1_240, "USD").label)
        assertEquals("-USD 0.05", Money(-5, "USD").label)
    }
}
