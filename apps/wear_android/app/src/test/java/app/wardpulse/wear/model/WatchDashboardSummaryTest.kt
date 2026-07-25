package app.wardpulse.wear.model

import java.time.Instant
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class WatchDashboardSummaryTest {
    @Test
    fun formatsLastSyncInLocalAndUtc() {
        val summary = PreviewWatchDashboardSummary.value

        assertEquals("Jun 27, 18:42 UTC", summary.lastSyncUtcLabel)
        assertFalse(summary.lastSyncLabel.contains("UTC"))
        assertTrue(
            summary.lastSyncLabel.matches(Regex("""[A-Z][a-z]{2} \d{1,2}, \d{2}:\d{2}""")),
        )
    }

    @Test
    fun handlesInvalidTimestamp() {
        val summary = PreviewWatchDashboardSummary.value.copy(generatedAt = "invalid")

        assertEquals("Unknown", summary.lastSyncLabel)
        assertEquals("Unknown", summary.lastSyncUtcLabel)
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

    @Test
    fun trimsTrailingZerosFromQuantityLabels() {
        assertEquals("500 credits", Quantity("500.0000000000", "credits").label)
        assertEquals("12.5 credits", Quantity("12.50", "credits").label)
        assertEquals("12.5 credits", Quantity("12.5", "credits").label)
    }
}
