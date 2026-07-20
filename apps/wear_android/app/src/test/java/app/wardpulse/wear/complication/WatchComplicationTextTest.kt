package app.wardpulse.wear.complication

import app.wardpulse.wear.model.PreviewWatchDashboardSummary
import app.wardpulse.wear.model.ProviderSummary
import app.wardpulse.wear.model.PulseStatus
import org.junit.Assert.assertEquals
import org.junit.Test

class WatchComplicationTextTest {
    @Test
    fun formatsUsagePercentages() {
        val summary = PreviewWatchDashboardSummary.value

        assertEquals("25%", WatchComplicationText.today(summary))
        assertEquals("29%", WatchComplicationText.week(summary))
    }

    @Test
    fun identifiesTheLiveProviderAndStatus() {
        val summary = PreviewWatchDashboardSummary.value.copy(
            overallStatus = PulseStatus.UNKNOWN,
            providers = listOf(
                ProviderSummary(
                    provider = "openai",
                    status = PulseStatus.OK,
                    todaySpent = null,
                ),
            ),
            isStale = false,
        )

        assertEquals("OPENAI · OK", WatchComplicationText.status(summary))
    }

    @Test
    fun marksStaleData() {
        assertEquals(
            "MOCK · STALE",
            WatchComplicationText.status(PreviewWatchDashboardSummary.value),
        )
    }
}
