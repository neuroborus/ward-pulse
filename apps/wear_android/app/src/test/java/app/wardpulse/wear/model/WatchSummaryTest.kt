package app.wardpulse.wear.model

import org.junit.Assert.assertEquals
import org.junit.Test

class WatchSummaryTest {
    @Test
    fun formatsLastSyncInUtc() {
        assertEquals("Jun 27, 18:42 UTC", MockWatchSummary.value.lastSyncLabel)
    }

    @Test
    fun handlesInvalidTimestamp() {
        val summary = MockWatchSummary.value.copy(generatedAt = "invalid")

        assertEquals("Unknown", summary.lastSyncLabel)
    }
}
