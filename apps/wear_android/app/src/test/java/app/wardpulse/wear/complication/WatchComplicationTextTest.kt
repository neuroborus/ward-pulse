package app.wardpulse.wear.complication

import app.wardpulse.wear.model.AllowanceSummary
import app.wardpulse.wear.model.CreditsGlance
import app.wardpulse.wear.model.PreviewWatchDashboardSummary
import app.wardpulse.wear.model.ProviderSummary
import app.wardpulse.wear.model.PulseStatus
import app.wardpulse.wear.model.Quantity
import app.wardpulse.wear.model.RingSummary
import app.wardpulse.wear.model.WatchDataMode
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
    fun buildsSunkStripLabelsWithPerProviderCreditsLikeGlance() {
        val multi =
            PreviewWatchDashboardSummary.value.copy(
                rings =
                    listOf(
                        RingSummary(
                            "allowance.cursor.cursor-plan-models",
                            "Cursor Models",
                            53.9,
                            PulseStatus.OK,
                        ),
                        RingSummary("allowance.claude.plan", "Weekly", 61.0, PulseStatus.OK),
                        RingSummary("allowance.codex.codex-primary", "Weekly plan", 92.0, PulseStatus.OK),
                    ),
                // Aggregate glance must not gate per-ring credits.
                creditsGlance =
                    CreditsGlance(text = "900", label = "Credits left", provider = null),
                allowances =
                    listOf(
                        AllowanceSummary(
                            source = "purchased",
                            label = "Codex · Purchased credits",
                            usedPercent = null,
                            remaining = Quantity("320", "credits"),
                            unlimited = false,
                            resetsAt = null,
                            status = PulseStatus.OK,
                        ),
                        AllowanceSummary(
                            source = "purchased",
                            label = "Claude · Extra usage",
                            usedPercent = null,
                            remaining = Quantity("80", "credits"),
                            unlimited = false,
                            resetsAt = null,
                            status = PulseStatus.OK,
                        ),
                    ),
            )
        // Cursor has no purchased meter — percent only.
        assertEquals("46%", WatchComplicationText.stripLabel(multi, 0))
        assertEquals("39% · 80", WatchComplicationText.stripLabel(multi, 1))
        assertEquals("8% · 320", WatchComplicationText.stripLabel(multi, 2))

        val planOnly = multi.copy(allowances = emptyList(), creditsGlance = null)
        assertEquals("46%", WatchComplicationText.stripLabel(planOnly, 0))

        val creditsOnly =
            planOnly.copy(
                rings = emptyList(),
                creditsGlance = CreditsGlance(text = "500", label = "Credits left", provider = "codex"),
            )
        assertEquals(
            WatchComplicationText.StripPayload(text = "500"),
            WatchComplicationText.stripPayload(creditsOnly, 0),
        )
        assertEquals("500", WatchComplicationText.stripLabel(creditsOnly, 0))
        assertNull(WatchComplicationText.stripLabel(creditsOnly, 1))
    }

    @Test
    fun identifiesTheLiveProviderAndStatus() {
        val summary =
            PreviewWatchDashboardSummary.value.copy(
                dataMode = WatchDataMode.LIVE,
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

    /// The demo impersonates real families, so the provider name cannot reveal
    /// that the numbers are fake — only `dataMode` can.
    @Test
    fun marksMockDataEvenWhenItWearsAProviderName() {
        val summary =
            PreviewWatchDashboardSummary.value.copy(
                dataMode = WatchDataMode.MOCK,
                providers =
                    listOf(
                        ProviderSummary(
                            provider = "claude",
                            status = PulseStatus.OK,
                            todaySpent = null,
                        ),
                    ),
                isStale = false,
            )

        assertEquals("MOCK · OK", WatchComplicationText.status(summary))
    }

    @Test
    fun shortensRateLimitedStatusForRoundChin() {
        val summary =
            PreviewWatchDashboardSummary.value.copy(
                dataMode = WatchDataMode.LIVE,
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
