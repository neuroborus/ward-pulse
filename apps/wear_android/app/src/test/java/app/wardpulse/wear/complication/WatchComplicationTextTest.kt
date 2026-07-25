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

        // today/week helpers expose ring slots 0/1 (surface order), not budget periods.
        assertEquals("29%", WatchComplicationText.today(summary))
        assertEquals("27%", WatchComplicationText.week(summary))
        assertEquals("—", WatchComplicationText.percentLabel(null))
        assertEquals("0%", WatchComplicationText.percentLabel(0f))
        assertEquals("25", WatchComplicationText.percentAmount(24.8f))
        assertEquals("—", WatchComplicationText.percentAmount(null))
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

    @Test
    fun shortensRateLimitedStatusForRoundChin() {
        val summary = PreviewWatchDashboardSummary.value.copy(
            providers = listOf(
                ProviderSummary(
                    provider = "codex",
                    status = PulseStatus.RATE_LIMITED,
                    todaySpent = null,
                ),
            ),
            isStale = false,
        )

        assertEquals("CODEX · LIMIT", WatchComplicationText.status(summary))
        assertEquals("LIMIT", WatchComplicationText.shortStatus(PulseStatus.RATE_LIMITED))
    }
}
