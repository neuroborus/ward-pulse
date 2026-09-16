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
    fun legendRows_omitExhaustedAndPrefixFamily() {
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
                            // One band, two pools: the exhausted one drops out alone.
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
        assertEquals("Codex · Weekly plan", rows[0].title)
        assertEquals("8% left · 320 credits", rows[0].subtitle)
        // The pool name already opens with its family — do not name it twice.
        assertEquals("Cursor Models", rows[1].title)
        assertEquals("24% left", rows[1].subtitle)
        assertNull(rows[1].secondaryArc)
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
        val single = RingSummary("allowance.claude.plan", "Weekly", 10.0, PulseStatus.OK)
        val credits = cursorCredits().copy(label = "Codex · Purchased credits")
        val rows = glanceLegendRows(baseSummary(
            rings = listOf(cursorPair(), codex, single),
            allowances = listOf(credits),
        ))
        assertEquals(listOf("Cursor plan", "Codex plan", "Claude · Weekly"), rows.map { it.title })
        assertEquals("82% · 41% left", rows[0].subtitle)
        assertEquals("82% · 41% left · 320 credits", rows[1].subtitle)
        assertEquals(RingFamily.CODEX, rows[1].colorArgb)
        assertEquals(RingFamily.CODEX_SPARK, requireNotNull(rows[1].secondaryArc).colorArgb)
        assertNull(rows[2].secondaryArc)
        val switched = codex.copy(split = codex.split!!.copy(label = "Spark Weekly"))
        assertEquals("Codex plan", glanceLegendRows(baseSummary(rings = listOf(switched))).single().title)
        val remainingSpark = glanceLegendRows(baseSummary(rings = listOf(codex.copy(usedPercent = 100.0)))).single()
        assertEquals("Codex · Spark 5h", remainingSpark.title)
        assertNull(remainingSpark.secondaryArc)
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
    fun legendRows_exhaustedHalfLeavesAnOrdinaryPoolRow() {
        for ((innerUsed, outerUsed) in listOf(100.0 to 59.0, 18.0 to 100.0)) {
            val pair = cursorPair(innerUsed, outerUsed)
            val survivor = if (innerUsed >= 100.0) {
                val outer = requireNotNull(pair.split)
                RingSummary(outer.id, outer.label, outer.usedPercent, outer.status)
            } else {
                pair.copy(split = null)
            }
            val allowances = listOf(cursorCredits())
            val actual = glanceLegendRows(baseSummary(rings = listOf(pair), allowances = allowances))
            val ordinary = glanceLegendRows(baseSummary(rings = listOf(survivor), allowances = allowances))
            assertEquals(ordinary, actual)
            assertNull(actual.single().secondaryArc)
            assertEquals(
                if (innerUsed >= 100.0) "Cursor · Other Models" else "Cursor Models",
                actual.single().title,
            )
            assertEquals(
                if (innerUsed >= 100.0) "41% left · 320 credits" else "82% left · 320 credits",
                actual.single().subtitle,
            )
        }
    }

    @Test
    fun legendRows_exhaustedPairDisappears() {
        assertTrue(glanceLegendRows(baseSummary(rings = listOf(cursorPair(100.0, 120.0)))).isEmpty())
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
                "Codex · Weekly plan",
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
    fun legendRows_keepPhoneComposedBudgetLabel() {
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
    }

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
