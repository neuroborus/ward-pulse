package app.wardpulse.wear.complication

import app.wardpulse.wear.model.CreditsGlance
import app.wardpulse.wear.model.PreviewWatchDashboardSummary
import app.wardpulse.wear.model.ProviderSummary
import app.wardpulse.wear.model.PulseStatus
import app.wardpulse.wear.model.RingSummary
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
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
    fun buildsSunkStripLabelsWithCreditsOnMatchingProviderOnly() {
        val cursorTightest =
            PreviewWatchDashboardSummary.value.copy(
                rings =
                    listOf(
                        RingSummary("allowance.cursor.plan", "Plan usage", 53.9, PulseStatus.OK),
                        RingSummary("allowance.claude.plan", "Weekly plan", 0.0, PulseStatus.OK),
                        RingSummary("allowance.codex.codex-primary", "Weekly plan", 0.0, PulseStatus.OK),
                    ),
                creditsGlance =
                    CreditsGlance(text = "500", label = "Credits left", provider = "codex"),
            )
        // Tightest is Cursor — do not glue Codex credits onto it.
        assertEquals("46%", WatchComplicationText.stripLabel(cursorTightest, 0))
        assertEquals("100%", WatchComplicationText.stripLabel(cursorTightest, 1))
        assertEquals("100% · 500", WatchComplicationText.stripLabel(cursorTightest, 2))

        val codexTightest =
            cursorTightest.copy(
                rings =
                    listOf(
                        RingSummary("allowance.codex.codex-primary", "Weekly plan", 92.0, PulseStatus.OK),
                        RingSummary("allowance.cursor.plan", "Plan usage", 28.0, PulseStatus.OK),
                    ),
            )
        assertEquals("8% · 500", WatchComplicationText.stripLabel(codexTightest, 0))
        assertEquals("72%", WatchComplicationText.stripLabel(codexTightest, 1))

        val planOnly = cursorTightest.copy(creditsGlance = null)
        assertEquals("46%", WatchComplicationText.stripLabel(planOnly, 0))

        val creditsOnly =
            planOnly.copy(rings = emptyList(), creditsGlance = cursorTightest.creditsGlance)
        assertEquals(
            WatchComplicationText.StripPayload(text = "500"),
            WatchComplicationText.stripPayload(creditsOnly, 0),
        )
        assertEquals("500", WatchComplicationText.stripLabel(creditsOnly, 0))
        assertNull(WatchComplicationText.stripLabel(creditsOnly, 1))

        // Multi-provider aggregate (provider null) never glues onto a single % strip.
        val aggregate =
            cursorTightest.copy(
                creditsGlance = CreditsGlance(text = "900", label = "Credits left", provider = null),
            )
        assertEquals("46%", WatchComplicationText.stripLabel(aggregate, 0))
        assertEquals("100%", WatchComplicationText.stripLabel(aggregate, 2))
    }

    @Test
    fun identifiesTheLiveProviderAndStatus() {
        val summary =
            PreviewWatchDashboardSummary.value.copy(
                overallStatus = PulseStatus.UNKNOWN,
                providers =
                    listOf(
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
        val summary =
            PreviewWatchDashboardSummary.value.copy(
                providers =
                    listOf(
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
