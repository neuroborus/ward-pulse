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

        // Preview rings: used 28.5 / 26.5 → remaining 71.5 / 73.5.
        assertEquals("72%", WatchComplicationText.ringRemainingPercent(summary, 0))
        assertEquals("74%", WatchComplicationText.ringRemainingPercent(summary, 1))
        assertEquals(71.5f, WatchComplicationText.remainingPercent(28.5), 0.001f)
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
