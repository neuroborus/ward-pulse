package app.wardpulse.wear.ui

import app.wardpulse.wear.model.AllowanceSummary
import app.wardpulse.wear.model.CreditsGlance
import app.wardpulse.wear.model.PeriodSummary
import app.wardpulse.wear.model.PulseStatus
import app.wardpulse.wear.model.Quantity
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
                            RingSummary(
                                "allowance.cursor.cursor-plan-models",
                                "Cursor Models",
                                76.0,
                                PulseStatus.OK,
                            ),
                            RingSummary(
                                "allowance.cursor.cursor-plan-other",
                                "Other Models",
                                100.0,
                                PulseStatus.OK,
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
        assertEquals("Budget · Today", rows[2].title)
        assertEquals("60% left", rows[2].subtitle)
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
            schemaVersion = 7,
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
