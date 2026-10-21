package app.wardpulse.wear.ui

import app.wardpulse.wear.model.AllowanceSummary
import app.wardpulse.wear.model.CreditsGlance
import app.wardpulse.wear.model.PeriodSummary
import app.wardpulse.wear.model.PulseStatus
import app.wardpulse.wear.model.Quantity
import app.wardpulse.wear.model.RingHalf
import app.wardpulse.wear.model.RingSummary
import app.wardpulse.wear.model.WatchDashboardSummary
import app.wardpulse.wear.model.WatchDataMode
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class GlanceModelsTest {
    @Test
    fun refreshChrome_healthyEnabled() {
        val chrome = glanceRefreshChrome(baseSummary(), refreshAllowed = true)
        assertTrue(chrome.ok)
        assertTrue(chrome.enabled)
        assertNull(chrome.detail)
    }

    @Test
    fun refreshChrome_cadenceCooldownKeepsOkWithoutDetail() {
        val chrome = glanceRefreshChrome(baseSummary(), refreshAllowed = false)
        assertTrue(chrome.ok)
        assertFalse(chrome.enabled)
        assertNull(chrome.detail)
    }

    @Test
    fun refreshChrome_staleShowsDetailAndStaysEnabled() {
        val chrome =
            glanceRefreshChrome(
                baseSummary(isStale = true, overall = PulseStatus.OK),
                refreshAllowed = true,
            )
        assertFalse(chrome.ok)
        assertTrue(chrome.enabled)
        assertEquals("Stale", chrome.detail)
    }

    @Test
    fun refreshChrome_rateLimitedDisablesWithDetail() {
        val chrome =
            glanceRefreshChrome(
                baseSummary(overall = PulseStatus.RATE_LIMITED),
                refreshAllowed = true,
            )
        assertFalse(chrome.ok)
        assertFalse(chrome.enabled)
        assertEquals("Rate limited", chrome.detail)
    }

    @Test
    fun refreshChrome_staleOutranksRateLimited() {
        val chrome =
            glanceRefreshChrome(
                baseSummary(overall = PulseStatus.RATE_LIMITED, isStale = true),
                refreshAllowed = true,
            )
        assertEquals("Stale", chrome.detail)
        // The rate limit still blocks the tap; only the detail line changes.
        assertFalse(chrome.enabled)
    }

    @Test
    fun refreshChrome_mockOutranksRateLimited() {
        val chrome =
            glanceRefreshChrome(
                baseSummary(
                    overall = PulseStatus.RATE_LIMITED,
                    dataMode = WatchDataMode.MOCK,
                ),
                refreshAllowed = true,
            )
        assertEquals("Mock data", chrome.detail)
        assertFalse(chrome.enabled)
    }

    @Test
    fun refreshChrome_unknownShowsDetail() {
        val chrome =
            glanceRefreshChrome(
                baseSummary(overall = PulseStatus.UNKNOWN),
                refreshAllowed = true,
            )
        assertFalse(chrome.ok)
        assertTrue(chrome.enabled)
        assertEquals("Unknown", chrome.detail)
    }

    @Test
    fun legendRows_keepExhaustedHalvesAndPrefixFamily() {
        val rows =
            glanceLegendRows(
                baseSummary(
                    rings =
                        listOf(
                            RingSummary(
                                "allowance.codex.week",
                                "Weekly plan",
                                92.0,
                                PulseStatus.OK,
                            ),
                            // One band, two pools: a zero half remains visible.
                            RingSummary(
                                "allowance.cursor.cursor-plan-models",
                                "Cursor Models",
                                76.0,
                                PulseStatus.OK,
                                split =
                                    RingHalf(
                                        "allowance.cursor.cursor-plan-other",
                                        "Other Models",
                                        100.0,
                                        PulseStatus.OK,
                                    ),
                            ),
                            RingSummary(
                                "budget.today",
                                "Today",
                                40.0,
                                PulseStatus.OK,
                            ),
                        ),
                    allowances =
                        listOf(
                            AllowanceSummary(
                                source = "purchased",
                                label = "Codex · Credits",
                                usedPercent = null,
                                remaining = Quantity("320", "credits"),
                                unlimited = false,
                                resetsAt = null,
                                status = PulseStatus.OK,
                            ),
                        ),
                ),
            )
        assertEquals(3, rows.size)
        assertEquals("Codex plan · Weekly", rows[0].title)
        assertEquals("8% left · 320 credits", rows[0].subtitle)
        assertEquals("Cursor plan", rows[1].title)
        assertEquals("24% · 0% left", rows[1].subtitle)
        assertEquals(0f, requireNotNull(rows[1].secondaryArc).remainingFraction)
        assertEquals(listOf(6 until 8), rows[1].exhaustedPercentRanges)
        assertEquals("Budget · Today", rows[2].title)
        assertEquals("60% left", rows[2].subtitle)
    }

    @Test
    fun legendRows_pairHasTwoArcsAndOneCreditsSuffix() {
        val row = glanceLegendRows(
            baseSummary(
                rings = listOf(cursorPair()),
                allowances = listOf(cursorCredits()),
            ),
        ).single()
        assertEquals("Cursor plan", row.title)
        assertEquals("82% · 41% left · 320 credits", row.subtitle)
        assertEquals(0.82f, row.remainingFraction, 0.0001f)
        assertEquals(RingFamily.CURSOR_OWN, row.colorArgb)
        val outer = requireNotNull(row.secondaryArc)
        assertEquals(0.41f, outer.remainingFraction, 0.0001f)
        assertEquals(RingFamily.CURSOR, outer.colorArgb)
    }

    @Test
    fun legendRows_twoPairsKeepBandNamesInnerFirstAndCreditsOnce() {
        val codex = RingSummary(
            "allowance.codex.plan", "Weekly plan", 18.0, PulseStatus.OK,
            split = RingHalf("allowance.codex.spark", "Spark 5h", 59.0, PulseStatus.OK),
        )
        val single = RingSummary("allowance.claude.plan", "Sonnet weekly", 10.0, PulseStatus.OK)
        val credits = cursorCredits().copy(label = "Codex · Purchased credits")
        val rows = glanceLegendRows(baseSummary(
            rings = listOf(cursorPair(), codex, single),
            allowances = listOf(credits),
        ))
        assertEquals(listOf("Cursor plan", "Codex plan", "Claude plan · Sonnet weekly"), rows.map { it.title })
        assertEquals("82% · 41% left", rows[0].subtitle)
        assertEquals("82% · 41% left · 320 credits", rows[1].subtitle)
        assertEquals(RingFamily.CODEX, rows[1].colorArgb)
        assertEquals(RingFamily.CODEX_SPARK, requireNotNull(rows[1].secondaryArc).colorArgb)
        assertNull(rows[2].secondaryArc)
        val switched = codex.copy(split = codex.split!!.copy(label = "Spark Weekly"))
        assertEquals("Codex plan", glanceLegendRows(baseSummary(rings = listOf(switched))).single().title)
        val remainingSpark = glanceLegendRows(baseSummary(rings = listOf(codex.copy(usedPercent = 100.0)))).single()
        assertEquals("Codex plan", remainingSpark.title)
        assertEquals("0% · 41% left", remainingSpark.subtitle)
        assertEquals(0f, remainingSpark.remainingFraction)
        assertEquals(0.41f, requireNotNull(remainingSpark.secondaryArc).remainingFraction, 0.0001f)

        val sparkOnly = glanceLegendRows(baseSummary(
            rings = listOf(switched.copy(usedPercent = Double.NaN)),
            allowances = listOf(credits),
        )).single()
        assertEquals("Codex plan · Spark Weekly", sparkOnly.title)
        assertEquals("41% left · 320 credits", sparkOnly.subtitle)
        assertEquals(RingFamily.CODEX_SPARK, sparkOnly.colorArgb)
        assertNull(sparkOnly.secondaryArc)
        val mainOnly = glanceLegendRows(baseSummary(rings = listOf(
            codex.copy(label = "5h", split = requireNotNull(codex.split).copy(usedPercent = Double.NaN)),
        ))).single()
        assertEquals("Codex plan · 5h", mainOnly.title)
        assertEquals("82% left", mainOnly.subtitle)
        assertEquals(RingFamily.CODEX, mainOnly.colorArgb)
        assertNull(mainOnly.secondaryArc)
    }

    @Test
    fun legendRows_pairWithoutCreditsKeepsInnerFirstRegardlessOfPercent() {
        for ((innerUsed, outerUsed, subtitle) in listOf(
            Triple(18.0, 59.0, "82% · 41% left"),
            Triple(59.0, 18.0, "41% · 82% left"),
        )) {
            val row = glanceLegendRows(
                baseSummary(rings = listOf(cursorPair(innerUsed, outerUsed))),
            ).single()
            assertEquals("Cursor plan", row.title)
            assertEquals(subtitle, row.subtitle)
            assertEquals(RingFamily.CURSOR_OWN, row.colorArgb)
            assertEquals(RingFamily.CURSOR, requireNotNull(row.secondaryArc).colorArgb)
        }
    }

    @Test
    fun legendRows_exhaustedHalfKeepsBothPoolsAndOnlyItsPercentTinted() {
        for ((innerUsed, outerUsed) in listOf(100.0 to 59.0, 18.0 to 100.0)) {
            val pair = cursorPair(innerUsed, outerUsed)
            val allowances = listOf(cursorCredits())
            val actual = glanceLegendRows(baseSummary(rings = listOf(pair), allowances = allowances))
            assertEquals("Cursor plan", actual.single().title)
            assertEquals(RingFamily.CURSOR_OWN, actual.single().colorArgb)
            assertEquals(RingFamily.CURSOR, requireNotNull(actual.single().secondaryArc).colorArgb)
            assertEquals(
                if (innerUsed >= 100.0) "0% · 41% left · 320 credits" else "82% · 0% left · 320 credits",
                actual.single().subtitle,
            )
            assertEquals(
                if (innerUsed >= 100.0) listOf(0 until 2) else listOf(6 until 8),
                actual.single().exhaustedPercentRanges,
            )
        }
    }

    @Test
    fun legendRows_exhaustedPairKeepsTwoTracksAndTwoPercentTokens() {
        val row = glanceLegendRows(baseSummary(rings = listOf(cursorPair(100.0, 120.0)))).single()
        assertEquals("0% · 0% left", row.subtitle)
        assertEquals(0f, row.remainingFraction)
        assertEquals(0f, requireNotNull(row.secondaryArc).remainingFraction)
        assertEquals(listOf(0 until 2, 5 until 7), row.exhaustedPercentRanges)
    }

    @Test
    fun legendRows_roundingToZeroDoesNotMarkPositiveCapacityExhausted() {
        val row = glanceLegendRows(baseSummary(rings = listOf(cursorPair(99.96, 100.0)))).single()
        assertEquals("0% · 0% left", row.subtitle)
        assertTrue(row.remainingFraction > 0f)
        assertEquals(listOf(5 until 7), row.exhaustedPercentRanges)
        val styled = glanceSubtitleText(row)
        assertEquals(row.subtitle, styled.text)
        assertEquals(1, styled.spanStyles.size)
        assertEquals(5, styled.spanStyles.single().start)
        assertEquals(7, styled.spanStyles.single().end)
        assertEquals(androidx.compose.ui.graphics.Color(0xFFFFB4AB), styled.spanStyles.single().item.color)
    }

    @Test
    fun legendRows_invalidValuesAreNotInventedZeroes() {
        for (used in listOf(Double.NaN, Double.POSITIVE_INFINITY, -1.0)) {
            val row = cursorPair(used, 100.0).copy(split = null)
            assertTrue(glanceLegendRows(baseSummary(rings = listOf(row))).isEmpty())
            val outerOnly = glanceLegendRows(baseSummary(rings = listOf(cursorPair(used, 100.0)))).single()
            assertEquals("Cursor · Other Models", outerOnly.title)
            assertEquals("0% left", outerOnly.subtitle)
            assertEquals(listOf(0 until 2), outerOnly.exhaustedPercentRanges)
            assertNull(outerOnly.secondaryArc)
            val innerOnly = glanceLegendRows(baseSummary(rings = listOf(cursorPair(100.0, used)))).single()
            assertEquals("Cursor Models", innerOnly.title)
            assertEquals("0% left", innerOnly.subtitle)
            assertEquals(listOf(0 until 2), innerOnly.exhaustedPercentRanges)
            assertNull(innerOnly.secondaryArc)
        }
    }

    @Test
    fun invalidOnlyDataDoesNotClaimThatKnownCapacityIsExhausted() {
        val unavailable = baseSummary(rings = listOf(cursorPair(Double.NaN, Double.NaN)))
        assertTrue(glanceLegendRows(unavailable).isEmpty())
        assertEquals(listOf("Ring data unavailable"), glanceEmptyLines(unavailable))
        val selectedEmpty = unavailable.copy(
            rings = emptyList(),
            providers = listOf(app.wardpulse.wear.model.ProviderSummary("claude", PulseStatus.OK, null)),
        )
        assertEquals(listOf("Choose percent rings", "in the phone app"), glanceEmptyLines(selectedEmpty))
        assertEquals(listOf("Connect a provider", "on your phone"), glanceEmptyLines(selectedEmpty.copy(providers = emptyList())))
    }

    @Test
    fun legendRows_zeroPurchasedCreditsNeverReceivePercentTint() {
        val allowance = cursorCredits().copy(remaining = Quantity("0", "credits"))
        val row = glanceLegendRows(baseSummary(
            rings = listOf(cursorPair(100.0, 100.0)), allowances = listOf(allowance),
        )).single()
        assertEquals("0% · 0% left · 0 credits", row.subtitle)
        val styled = glanceSubtitleText(row)
        assertEquals(listOf("0%", "0%"), styled.spanStyles.map { styled.text.substring(it.start, it.end) })
        assertTrue(styled.spanStyles.all { it.end <= "0% · 0%".length })
    }

    /** A pair is one row at the band's position supplied by the phone. */
    @Test
    fun legendRows_keepAPairTogetherWhereItsBandLands() {
        val rows =
            glanceLegendRows(
                baseSummary(
                    rings =
                        listOf(
                            RingSummary(
                                "allowance.codex.week",
                                "Weekly plan",
                                92.0,
                                PulseStatus.OK,
                            ),
                            RingSummary(
                                "allowance.cursor.cursor-plan-models",
                                "Cursor Models",
                                53.0,
                                PulseStatus.OK,
                                // Loosest metric on the watch: sorted on its own
                                // percent it would come last, not in the second band.
                                split =
                                    RingHalf(
                                        "allowance.cursor.cursor-plan-other",
                                        "Other Models",
                                        20.0,
                                        PulseStatus.OK,
                                    ),
                            ),
                            RingSummary(
                                "budget.today",
                                "Today",
                                40.0,
                                PulseStatus.OK,
                            ),
                        ),
                ),
            )
        assertEquals(
            listOf(
                "Codex plan · Weekly",
                "Cursor plan",
                "Budget · Today",
            ),
            rows.map { it.title },
        )
        assertEquals(
            listOf("8% left", "47% · 80% left", "60% left"),
            rows.map { it.subtitle },
        )
    }

    @Test
    fun legendRows_keepBudgetUnknownAndComposedLabels() {
        val rows =
            glanceLegendRows(
                baseSummary(
                    rings =
                        listOf(
                            RingSummary(
                                "budget.anthropic.platform.month",
                                "Anthropic platform · Month",
                                40.0,
                                PulseStatus.OK,
                            ),
                        ),
                    allowances =
                        listOf(
                            AllowanceSummary(
                                source = "purchased",
                                label = "Claude · Extra usage",
                                usedPercent = null,
                                remaining = Quantity("320", "credits"),
                                unlimited = false,
                                resetsAt = null,
                                status = PulseStatus.OK,
                            ),
                        ),
                ),
            )
        // The phone names a budget ring by its connection — do not prefix again.
        assertEquals("Anthropic platform · Month", rows.single().title)
        // Credits belong to the plan pool, not to a spend ceiling.
        assertEquals("60% left", rows.single().subtitle)
        assertEquals(RingFamily.CLAUDE, rows.single().colorArgb)
        assertEquals("External · Weekly plan", glancePrimaryLabel("allowance.codex.plan", "External · Weekly plan"))
        assertEquals("Codex · Monthly plan", glancePrimaryLabel("allowance.codex.plan", "Monthly plan"))
        assertEquals("Weekly plan", glancePrimaryLabel("external.plan", "Weekly plan"))
        assertEquals("Claude plan · Weekly", glancePrimaryLabel("allowance.claude.plan", "Claude plan · Weekly"))
    }

    @Test
    fun legendRows_creditBalanceIsCompact() {
        // The face strip draws this balance from the same payload as `62.5K`; a
        // Glance that disagreed would make the wearer pick a screen to believe
        // (`WEAR_GLANCE_DESIGN.md`, revision 2026-10-11).
        assertEquals("8% left · 62.5K credits", codexSubtitleForCredits("62479.294375"))
        assertEquals("8% left · 1K credits", codexSubtitleForCredits("1000"))
        assertEquals("8% left · 320 credits", codexSubtitleForCredits("320"))
        assertEquals("8% left · 0 credits", codexSubtitleForCredits("0"))
        // Trailing-zero noise was already trimmed and still is.
        assertEquals("8% left · 12.5 credits", codexSubtitleForCredits("12.50"))
    }

    @Test
    fun purchasedBalance_inAnyUnitButCreditsIsNotShown() {
        // The contract allows `tokens`, the watch does not carry them: the strip,
        // the complication and this row are the credits channel, and each of
        // their baselines refuses token counts by name (`PROVIDER_NOTES.md`,
        // Consumption display, 2026-10-11).
        val tokens = codexSummaryForBalance("62479.294375", unit = "tokens")
        assertEquals("8% left", glanceLegendRows(tokens).single().subtitle)
        // The strip and the complication read the same lookup, so they drop it too.
        assertNull(purchasedCreditsCompact(tokens, "allowance.codex.week"))
        assertNull(purchasedCreditsSuffix(tokens, "allowance.codex.week"))

        // The same balance in credits is still shown, so this omits rather than breaks.
        val credits = codexSummaryForBalance("62479.294375", unit = "credits")
        assertEquals("8% left · 62.5K credits", glanceLegendRows(credits).single().subtitle)
        assertEquals("62.5K", purchasedCreditsCompact(credits, "allowance.codex.week"))
    }

    private fun codexSubtitleForCredits(credits: String): String =
        glanceLegendRows(codexSummaryForBalance(credits, unit = "credits")).single().subtitle

    private fun codexSummaryForBalance(
        value: String,
        unit: String,
    ): WatchDashboardSummary =
        baseSummary(
            rings =
                listOf(
                    RingSummary("allowance.codex.week", "Weekly plan", 92.0, PulseStatus.OK),
                ),
            allowances =
                listOf(
                    AllowanceSummary(
                        source = "purchased",
                        label = "Codex · Credits",
                        usedPercent = null,
                        remaining = Quantity(value, unit),
                        unlimited = false,
                        resetsAt = null,
                        status = PulseStatus.OK,
                    ),
                ),
        )

    private fun cursorPair(innerUsed: Double = 18.0, outerUsed: Double = 59.0) = RingSummary(
        "allowance.cursor.cursor-plan-models",
        "Cursor Models",
        innerUsed,
        PulseStatus.OK,
        split = RingHalf("allowance.cursor.cursor-plan-other", "Other Models", outerUsed, PulseStatus.OK),
    )

    private fun cursorCredits() = AllowanceSummary(
        source = "purchased",
        label = "Cursor · Credits",
        usedPercent = null,
        remaining = Quantity("320", "credits"),
        unlimited = false,
        resetsAt = null,
        status = PulseStatus.OK,
    )

    private fun baseSummary(
        overall: PulseStatus = PulseStatus.OK,
        isStale: Boolean = false,
        dataMode: WatchDataMode = WatchDataMode.LIVE,
        rings: List<RingSummary> =
            listOf(
                RingSummary("budget.today", "Today", 24.8, PulseStatus.OK),
            ),
        allowances: List<AllowanceSummary> = emptyList(),
    ): WatchDashboardSummary {
        val period =
            PeriodSummary(
                period = "today",
                spent = null,
                limit = null,
                remaining = null,
                usedPercent = 24.8,
                projectedTotal = null,
                status = PulseStatus.OK,
            )
        return WatchDashboardSummary(
            schemaVersion = 9,
            dataMode = dataMode,
            generatedAt = "2026-07-26T10:00:00Z",
            overallStatus = overall,
            rings = rings,
            creditsGlance = CreditsGlance("500", "Credits left", null),
            today = period,
            week = period.copy(period = "week"),
            allowances = allowances,
            providers = emptyList(),
            alerts = emptyList(),
            isStale = isStale,
            manualRefreshAllowed = true,
            manualRefreshAvailableAt = null,
        )
    }
}
