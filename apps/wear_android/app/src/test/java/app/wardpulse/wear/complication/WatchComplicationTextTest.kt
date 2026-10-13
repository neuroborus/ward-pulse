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
import app.wardpulse.wear.model.RingSurfaceOrder
import app.wardpulse.wear.model.WatchDataMode
import app.wardpulse.wear.ui.RingFamily
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Test

class WatchComplicationTextTest {
    @Test
    fun nativeRangedBuilderAcceptsZeroAndRetainsTheFamilyRamp() {
        val built = rangedComplicationBuilder(
            percent = 0f, title = "zero", colorArgb = RingFamily.CLAUDE,
            contentDescription = "Claude 5h", text = "0% · 500",
        ).build()
        assertEquals(0f, built.value)
        assertEquals(0f, built.min)
        assertEquals(100f, built.max)
        assertEquals(RingFamily.CLAUDE, requireNotNull(built.colorRamp).colors.single())
        assertTrue(built.text != null && built.title != null)
    }

    @Test
    fun zeroHalvesPublishZeroRangedValuesAtTheirExistingOrdinal() {
        val zero = cursorPair.copy(usedPercent = 100.0, split = cursorPair.split!!.copy(usedPercent = 100.0))
        var innerCalled = false
        val inner = ringComplicationData(listOf(zero), 0) { _, remaining, title ->
            innerCalled = true
            assertEquals(0f, remaining)
            assertEquals("split:cursor-other:zero-both", title)
            rangedComplicationBuilder(remaining, title, RingFamily.CURSOR_OWN, text = "0% · 0%").build()
        }
        assertTrue(innerCalled)
        assertTrue(inner is androidx.wear.watchface.complications.data.RangedValueComplicationData)
        var outerCalled = false
        outerHalfComplicationData(listOf(zero, codexPair), 0) { half, outside ->
            outerCalled = true
            assertEquals(1, outside)
            assertEquals(0f, WatchComplicationText.remainingPercent(half.usedPercent))
            NoDataComplicationData()
        }
        assertTrue(outerCalled)
    }

    @Test
    fun exactZeroTitlesPreservePoolsAndDoNotTreatRoundedPositiveAsEmpty() {
        for ((inner, outer, suffix) in listOf(
            Triple(100.0, 40.0, "zero-inner"),
            Triple(40.0, 100.0, "zero-outer"),
            Triple(100.0, 100.0, "zero-both"),
        )) {
            val pair = cursorPair.copy(usedPercent = inner, split = cursorPair.split!!.copy(usedPercent = outer))
            assertEquals("split:cursor-other:$suffix", WatchComplicationText.ringTitleToken(pair))
            assertEquals("cursor-other", WatchComplicationText.stripTitleToken(pair))
        }
        assertEquals("", WatchComplicationText.ringTitleToken(cursorPair.copy(usedPercent = 99.96, split = null)))
        assertEquals("zero", WatchComplicationText.ringTitleToken(cursorPair.copy(usedPercent = 100.0, split = null)))
    }

    @Test
    fun invalidOuterPercentCannotPublishAPairedZeroTitleForASingleLabel() {
        for (invalid in listOf(Double.NaN, Double.POSITIVE_INFINITY, -1.0)) {
            for ((used, title, label) in listOf(Triple(38.0, "", "62%"), Triple(100.0, "zero", "0%"))) {
                val ring = cursorPair.copy(usedPercent = used, split = cursorPair.split!!.copy(usedPercent = invalid))
                val summary = PreviewWatchDashboardSummary.value.copy(rings = listOf(ring), allowances = emptyList())
                assertEquals(title, WatchComplicationText.ringTitleToken(ring))
                assertNull(WatchComplicationText.stripTitleToken(ring))
                assertEquals(label, WatchComplicationText.stripLabel(summary, 0))
            }
        }
    }

    @Test
    fun zeroStripKeepsPurchasedCreditsAndBudgetMoneyLabels() {
        val zero = RingSummary("allowance.claude.plan", "5h", 100.0, PulseStatus.OK)
        for (credit in listOf("500", "0")) {
            val summary = PreviewWatchDashboardSummary.value.copy(
                rings = listOf(zero),
                allowances = listOf(AllowanceSummary("purchased", "Claude · Extra usage", null, Quantity(credit, "credits"), false, null, PulseStatus.OK)),
            )
            assertEquals("0% · $credit", WatchComplicationText.stripLabel(summary, 0))
        }
        val budget = PreviewWatchDashboardSummary.value.copy(
            rings = PreviewWatchDashboardSummary.value.rings.map { it.copy(usedPercent = 100.0) },
        )
        assertEquals("\$71.30/250", WatchComplicationText.stripLabel(budget, 0))
        assertEquals("7D", WatchComplicationText.ringTitleToken(budget.rings.first()))
    }
    /** Face arc slots, outermost first — the order `RingSurfaceOrder` mirrors. */
    private val RINGS_SLOT_ORDER = listOf(0, 1, 2)

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
    fun absentOrInvalidSplitsReturnNoDataWithoutBuildingAnArc() {
        val single = cursorPair.copy(split = null)
        val invalid = cursorPair.copy(split = cursorPair.split!!.copy(usedPercent = Double.NaN))
        val first = RingSplitComplicationDataSourceService.SPLIT_INDEX
        val second = StripSplitComplicationDataSourceService.SPLIT_INDEX
        val cases =
            listOf(
                emptyList<RingSummary>() to first,
                emptyList<RingSummary>() to second,
                listOf(single) to first,
                listOf(single) to second,
                listOf(cursorPair) to second,
                listOf(invalid, cursorPair) to first,
                listOf(cursorPair, invalid) to second,
            )
        for ((rings, ordinal) in cases) {
            val result =
                outerHalfComplicationData(rings, ordinal) { _, _ ->
                    error("Missing or invalid split must clear the arc")
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

        // The pair names its outer pool in the same string: one slot draws both
        // the band and the legend row that marks it.
        assertEquals("split:cursor-other", normalTitle(cursorPair))
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
    fun stripTitlePreservesKnownOuterIdentityAtZero() {
        assertEquals(
            "cursor-other",
            WatchComplicationText.splitPoolToken("allowance.cursor.cursor-plan-other"),
        )
        assertEquals("spark", WatchComplicationText.splitPoolToken("allowance.codex.spark"))
        assertEquals("spark", WatchComplicationText.stripTitleToken(codexPair))
        assertNull(WatchComplicationText.splitPoolToken("allowance.codex.plan"))
        assertNull(WatchComplicationText.stripTitleToken(codexPair.copy(split = null)))
        assertEquals("spark", WatchComplicationText.stripTitleToken(codexPair.copy(usedPercent = 100.0)))
        assertEquals("spark", WatchComplicationText.stripTitleToken(
            codexPair.copy(split = codexPair.split!!.copy(usedPercent = 100.0)),
        ))
        assertNull(WatchComplicationText.splitPoolToken("allowance.cursor.cursor-plan-models"))
        assertNull(WatchComplicationText.splitPoolToken("allowance.test.outer"))
        assertNull(WatchComplicationText.splitPoolToken(""))
        assertEquals("cursor-other", WatchComplicationText.stripTitleToken(cursorPair))
        assertNull(WatchComplicationText.stripTitleToken(cursorPair.copy(split = null)))
        assertEquals("cursor-other", WatchComplicationText.stripTitleToken(cursorPair.copy(usedPercent = 100.0)))
        assertEquals("cursor-other",
            WatchComplicationText.stripTitleToken(
                cursorPair.copy(split = cursorPair.split!!.copy(usedPercent = 100.0)),
            ),
        )
        assertNull(
            WatchComplicationText.stripTitleToken(
                cursorPair.copy(split = cursorPair.split.copy(id = "allowance.test.outer")),
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
        assertEquals("500", WatchComplicationText.stripLabel(creditsOnly, 0))
        assertNull(WatchComplicationText.stripLabel(creditsOnly, 1))
    }

    @Test
    fun theLoneCreditsRowCarriesItsLabelAndItsProvidersColour() {
        val creditsOnly =
            PreviewWatchDashboardSummary.value.copy(
                rings = emptyList(),
                allowances = emptyList(),
                creditsGlance =
                    CreditsGlance(text = "500", label = "Credits left", provider = "codex"),
            )

        var builtLabel: String? = null
        var builtColor: Int? = null
        val built = NoDataComplicationData()
        val result =
            creditsOnlyComplicationData(creditsOnly) { label, colorArgb ->
                builtLabel = label
                builtColor = colorArgb
                built
            }

        assertSame(built, result)
        assertEquals("500", builtLabel)
        assertEquals(RingFamily.colorArgb("allowance.codex.credits"), builtColor)

        // Nothing to say: the row is not drawn rather than drawn empty.
        val nothing = creditsOnly.copy(creditsGlance = null)
        assertTrue(
            creditsOnlyComplicationData(nothing) { _, _ ->
                error("A payload with no credits must not publish a row")
            } is NoDataComplicationData,
        )
    }

    @Test
    fun onlyTheBottomRowCarriesCreditsWhenNoRingExists() {
        // The stack anchors to its bottom row, and the outermost slot paints it.
        assertEquals(0, CREDITS_RING_INDEX)
        // With no rings, no slot resolves a payload index, so the fallback is the
        // only thing that can draw a row at all.
        RINGS_SLOT_ORDER.forEach { slot ->
            assertNull(RingSurfaceOrder.payloadIndexForOuterSlot(0, slot))
        }
    }

    @Test
    fun eachRingSlotPrintsTheRowItsPayloadIndexOwns() {
        val multi =
            PreviewWatchDashboardSummary.value.copy(
                rings =
                    listOf(
                        RingSummary("allowance.codex.plan", "Codex", 92.0, PulseStatus.OK),
                        RingSummary("allowance.claude.plan", "Claude", 61.0, PulseStatus.OK),
                        RingSummary("allowance.cursor.plan", "Cursor", 54.0, PulseStatus.OK),
                    ),
                allowances = emptyList(),
                creditsGlance = null,
            )

        // Tightest first in the payload; outermost slot binds the loosest, so the
        // row a slot prints is the row its own payload index owns.
        for (ringCount in 1..3) {
            val rings = multi.rings.take(ringCount)
            val summary = multi.copy(rings = rings)
            RINGS_SLOT_ORDER.take(ringCount).forEach { slot ->
                val dataIndex =
                    requireNotNull(RingSurfaceOrder.payloadIndexForOuterSlot(ringCount, slot))
                assertEquals(
                    WatchComplicationText.stripLabel(summary, dataIndex),
                    WatchComplicationText.stripLabel(summary, ringCount - 1 - slot),
                )
            }
            // Slots past the count draw neither band nor row.
            RINGS_SLOT_ORDER.drop(ringCount).forEach { slot ->
                assertNull(RingSurfaceOrder.payloadIndexForOuterSlot(ringCount, slot))
            }
        }
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
            "split:cursor-other",
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
        // A pool outside the closed vocabulary leaves the band token bare: the
        // face has no branch to paint a marker it does not know.
        assertEquals(
            WatchComplicationText.SPLIT_TOKEN,
            WatchComplicationText.ringTitleToken(
                pool.copy(
                    split = RingHalf("allowance.cursor.unknown", "Unknown", 38.0, PulseStatus.OK),
                ),
            ),
        )
        // An exhausted half keeps its family marker and explicit zero token.
        assertEquals(
            "split:cursor-other:zero-outer",
            WatchComplicationText.ringTitleToken(
                pool.copy(
                    split =
                        RingHalf(
                            "allowance.cursor.cursor-plan-other",
                            "Other Models",
                            100.0,
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
