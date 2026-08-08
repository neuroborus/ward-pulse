package app.wardpulse.wear.ui

import org.junit.Assert.assertEquals
import org.junit.Test

class RingFamilyTest {
    @Test
    fun mapsProviderFamilies() {
        assertEquals(RingFamily.CODEX, RingFamily.colorArgb("allowance.codex.primary"))
        assertEquals(RingFamily.CLAUDE, RingFamily.colorArgb("allowance.claude.5h"))
        assertEquals(RingFamily.CURSOR, RingFamily.colorArgb("allowance.cursor.plan"))
        assertEquals(RingFamily.BUDGET, RingFamily.colorArgb("budget.week"))
        assertEquals(RingFamily.FALLBACK, RingFamily.colorArgb("unknown.metric"))
    }

    @Test
    fun budgetRingsFollowTheirConnection() {
        assertEquals(RingFamily.CODEX, RingFamily.colorArgb("budget.openai.platform.today"))
        assertEquals(RingFamily.CLAUDE, RingFamily.colorArgb("budget.anthropic.platform.month"))
        assertEquals(RingFamily.CURSOR, RingFamily.colorArgb("budget.cursor.platform.month"))
    }
}
