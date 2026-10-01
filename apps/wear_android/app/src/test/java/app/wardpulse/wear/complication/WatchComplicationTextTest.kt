package app.wardpulse.wear.complication

import androidx.wear.watchface.complications.data.NoDataComplicationData
import app.wardpulse.wear.model.AllowanceSummary
import app.wardpulse.wear.model.CreditsGlance
import app.wardpulse.wear.model.PreviewWatchDashboardSummary
import app.wardpulse.wear.model.ProviderSummary
import app.wardpulse.wear.model.PulseStatus
import app.wardpulse.wear.model.Quantity
import app.wardpulse.wear.model.RingHalf
import app.wardpulse.wear.model.RingSummary
import app.wardpulse.wear.model.WatchDataMode
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Test

class WatchComplicationTextTest {
    private val cursorPair =
        RingSummary(
            "allowance.cursor.cursor-plan-models",
            "Cursor Models",
            18.0,
            PulseStatus.OK,
            split = RingHalf("allowance.cursor.cursor-plan-other", "Other Models", 59.0, PulseStatus.OK),
        )

    private val codexPair = RingSummary(
        "allowance.codex.plan", "Weekly plan", 18.0, PulseStatus.OK,
        split = RingHalf("allowance.codex.spark", "Spark 5h", 59.0, PulseStatus.OK),
    )

    @Test
    fun outerHalfServicesSelectTheirSplitOrdinalAndMirrorTheBandIndex() {
        val single = RingSummary("allowance.claude.plan", "Weekly", 30.0, PulseStatus.OK)
        val secondPair = codexPair
        val first = RingSplitComplicationDataSourceService.SPLIT_INDEX
        val second = StripSplitComplicationDataSourceService.SPLIT_INDEX
        assertEquals(0, first)
        assertEquals(1, second)

        fun selected(rings: List<RingSummary>, ordinal: Int, half: RingHalf?, outsideIndex: Int) {
            // Capture routing without creating Android tap actions in a host-side test.
            val built = NoDataComplicationData()
            var called = false
            val result =
                outerHalfComplicationData(rings, ordinal) { actualHalf, actualIndex ->
                    called = true
                    assertEquals(half, actualHalf)
                    assertEquals(outsideIndex, actualIndex)
                    built
                }
            assertTrue(called)
            assertSame(built, result)
        }

        selected(listOf(cursorPair), first, cursorPair.split, 0)
        selected(listOf(single, cursorPair), first, cursorPair.split, 0)
        selected(listOf(cursorPair, single), first, cursorPair.split, 1)
        val twoPairs = listOf(cursorPair, single, secondPair)
        selected(twoPairs, first, cursorPair.split, 2)
        selected(twoPairs, second, secondPair.split, 0)
        selected(listOf(single, cursorPair, secondPair), first, cursorPair.split, 1)
        val exhausted = cursorPair.copy(split = cursorPair.split!!.copy(usedPercent = 100.0))
        selected(listOf(exhausted, single, secondPair), second, secondPair.split, 0)
    }

    @Test
    fun absentOrExhaustedSplitsReturnNoDataWithoutBuildingAnArc() {
        val single = cursorPair.copy(split = null)
        val exhausted = cursorPair.copy(split = cursorPair.split!!.copy(usedPercent = 100.0))
        val first = RingSplitComplicationDataSourceService.SPLIT_INDEX
        val second = StripSplitComplicationDataSourceService.SPLIT_INDEX
        val cases =
            listOf(
                emptyList<RingSummary>() to first,
                emptyList<RingSummary>() to second,
                listOf(single) to first,
                listOf(single) to second,
                listOf(cursorPair) to second,
                listOf(exhausted, cursorPair) to first,
                listOf(cursorPair, exhausted) to second,
            )
        for ((rings, ordinal) in cases) {
            val result =
                outerHalfComplicationData(rings, ordinal) { _, _ ->
                    error("Missing or exhausted split must clear the arc")
                }
            assertTrue(result is NoDataComplicationData)
        }
    }

    @Test
    fun loneSplitCapablePoolUsesAFullBandWhileAPairUsesTwoHalves() {
        val single = cursorPair.copy(split = null)

        fun normalTitle(ring: RingSummary): String {
            val built = NoDataComplicationData()
            var captured: String? = null
            val result =
                ringComplicationData(listOf(ring), 0) { actualRing, remaining, title ->
                    assertEquals(ring, actualRing)
                    assertEquals(82f, remaining)
                    captured = title
                    built
                }
            assertSame(built, result)
            return requireNotNull(captured)
        }

        assertEquals("", normalTitle(single))
        val loneOuter =
            outerHalfComplicationData(listOf(single), 0) { _, _ ->
                error("A lone pool must not publish outer-half data")
            }
        assertTrue(loneOuter is NoDataComplicationData)

        assertEquals(WatchComplicationText.SPLIT_TOKEN, normalTitle(cursorPair))
        val builtOuter = NoDataComplicationData()
        var outerBuilt = false
        val pairedOuter =
            outerHalfComplicationData(listOf(cursorPair), 0) { half, outerSlot ->
                outerBuilt = true
                assertEquals(cursorPair.split, half)
                assertEquals(0, outerSlot)
                builtOuter
            }
        assertTrue(outerBuilt)
        assertSame(builtOuter, pairedOuter)
    }

    @Test
    fun stripTitleUsesOnlyTheKnownActiveOuterPool() {
        assertEquals(
            "cursor-other",
            WatchComplicationText.splitPoolToken("allowance.cursor.cursor-plan-other"),
        )
        assertEquals("spark", WatchComplicationText.splitPoolToken("allowance.codex.spark"))
        assertEquals("spark", WatchComplicationText.stripTitleToken(codexPair))
        assertNull(WatchComplicationText.splitPoolToken("allowance.codex.plan"))
        assertNull(WatchComplicationText.stripTitleToken(codexPair.copy(split = null)))
        assertNull(WatchComplicationText.stripTitleToken(codexPair.copy(usedPercent = 100.0)))
        assertNull(WatchComplicationText.stripTitleToken(
            codexPair.copy(split = codexPair.split!!.copy(usedPercent = 100.0)),
        ))
        assertNull(WatchComplicationText.splitPoolToken("allowance.cursor.cursor-plan-models"))
        assertNull(WatchComplicationText.splitPoolToken("allowance.test.outer"))
        assertNull(WatchComplicationText.splitPoolToken(""))
        assertEquals("cursor-other", WatchComplicationText.stripTitleToken(cursorPair))
        assertNull(WatchComplicationText.stripTitleToken(cursorPair.copy(split = null)))
        assertNull(WatchComplicationText.stripTitleToken(cursorPair.copy(usedPercent = 100.0)))
        assertNull(
            WatchComplicationText.stripTitleToken(
                cursorPair.copy(split = cursorPair.split!!.copy(usedPercent = 100.0)),
            ),
        )
        assertNull(
            WatchComplicationText.stripTitleToken(
                cursorPair.copy(split = cursorPair.split!!.copy(id = "allowance.test.outer")),
            ),
        )
    }

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
    fun budgetStripsReadMoneyInsteadOfPercent() {
        // Preview rings are one connection's budget periods: week / month / today.
        val summary = PreviewWatchDashboardSummary.value

        assertEquals("\$71.30/250", WatchComplicationText.stripLabel(summary, 0))
        assertEquals("\$212.10/800", WatchComplicationText.stripLabel(summary, 1))
        assertEquals("\$12.40/50", WatchComplicationText.stripLabel(summary, 2))
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

    /**
     * The demo impersonates real families, so the provider name cannot reveal
     * that the numbers are fake — only `dataMode` can.
     */
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

    @Test
    fun readsThePeriodTokenOffBudgetRingIdsOnly() {
        assertEquals("D", WatchComplicationText.ringPeriodToken("budget.anthropic.today"))
        assertEquals("7D", WatchComplicationText.ringPeriodToken("budget.openai.week"))
        assertEquals("M", WatchComplicationText.ringPeriodToken("budget.cursor.month"))

        // A window is not a calendar period, so the face draws no texture for it.
        assertNull(WatchComplicationText.ringPeriodToken("allowance.claude.plan"))
        // A connection named after a period must not be mistaken for one.
        assertNull(WatchComplicationText.ringPeriodToken("allowance.codex.week"))
        assertNull(WatchComplicationText.ringPeriodToken("budget.anthropic.quarter"))
    }

    @Test
    fun aSharedBandTellsTheFaceSoInsteadOfAPeriod() {
        val pool =
            RingSummary(
                "allowance.cursor.cursor-plan-models",
                "Cursor Models",
                47.0,
                PulseStatus.OK,
            )
        assertEquals("", WatchComplicationText.ringTitleToken(pool))
        assertEquals(
            "split",
            WatchComplicationText.ringTitleToken(
                pool.copy(
                    split =
                        RingHalf(
                            "allowance.cursor.cursor-plan-other",
                            "Other Models",
                            38.0,
                            PulseStatus.OK,
                        ),
                ),
            ),
        )
        // A budget ring keeps its period: it can never be half a band.
        assertEquals(
            "M",
            WatchComplicationText.ringTitleToken(
                RingSummary("budget.cursor.month", "Month", 12.0, PulseStatus.OK),
            ),
        )
    }

    @Test
    fun aSplitStripSpendsItsWellOnTheSecondPercentNotCredits() {
        val summary =
            PreviewWatchDashboardSummary.value.copy(
                rings =
                    listOf(
                        RingSummary(
                            "allowance.cursor.cursor-plan-models",
                            "Cursor Models",
                            53.0,
                            PulseStatus.OK,
                            split =
                                RingHalf(
                                    "allowance.cursor.cursor-plan-other",
                                    "Other Models",
                                    38.0,
                                    PulseStatus.OK,
                                ),
                        ),
                    ),
                allowances =
                    listOf(
                        AllowanceSummary(
                            source = "purchased",
                            label = "Cursor · Purchased credits",
                            usedPercent = null,
                            remaining = Quantity("2100", "credits"),
                            unlimited = false,
                            resetsAt = null,
                            status = PulseStatus.OK,
                        ),
                    ),
            )

        assertEquals("47% · 62%", WatchComplicationText.stripLabel(summary, 0))
    }
}
