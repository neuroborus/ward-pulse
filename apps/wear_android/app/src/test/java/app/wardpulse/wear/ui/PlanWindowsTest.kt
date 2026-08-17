package app.wardpulse.wear.ui

import app.wardpulse.wear.model.AllowanceSummary
import app.wardpulse.wear.model.PreviewWatchDashboardSummary
import app.wardpulse.wear.model.PulseStatus
import app.wardpulse.wear.model.Quantity
import java.time.Instant
import java.time.ZoneId
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class PlanWindowsTest {
    private val now: Instant = Instant.parse("2026-08-17T12:00:00Z")
    private val utc: ZoneId = ZoneId.of("UTC")

    @Test
    fun rows_putExhaustedFirstThenSoonestReturn() {
        val rows = planWindowRows(
            summaryOf(
                allowance("Claude · Weekly Opus", used = 94.0, resetsAt = "2026-08-25T12:00:00Z"),
                allowance("Cursor · Cursor Models", used = 0.0, resetsAt = "2026-09-01T00:00:00Z"),
                allowance("Claude · 5-hour session", used = 100.0, resetsAt = "2026-08-17T19:00:00Z"),
            ),
            now = now,
            zone = utc,
        )

        assertEquals(
            listOf(
                "Claude · 5-hour session",
                "Claude · Weekly Opus",
                "Cursor · Cursor Models",
            ),
            rows.map { it.title },
        )
    }

    @Test
    fun rows_dropPurchasedMeters() {
        val rows = planWindowRows(
            summaryOf(
                allowance("Claude · Extra usage", used = 84.5, resetsAt = null, source = "purchased"),
                allowance("Claude · Weekly plan", used = 40.0, resetsAt = "2026-08-25T12:00:00Z"),
            ),
            now = now,
            zone = utc,
        )

        // A purchased meter does not come back; it is bought again.
        assertEquals(listOf("Claude · Weekly plan"), rows.map { it.title })
    }

    @Test
    fun detail_saysWhenTodayWithoutADate() {
        val rows = planWindowRows(
            summaryOf(
                allowance("Claude · 5-hour session", used = 100.0, resetsAt = "2026-08-17T19:00:00Z"),
            ),
            now = now,
            zone = utc,
        )

        assertEquals("0% left · back at 19:00", rows.single().detail)
    }

    @Test
    fun detail_carriesTheDateBeyondToday() {
        val rows = planWindowRows(
            summaryOf(
                allowance("Claude · Weekly Opus", used = 94.0, resetsAt = "2026-08-25T12:00:00Z"),
            ),
            now = now,
            zone = utc,
        )

        // Tomorrow evening must not read like tonight.
        assertEquals("6% left · back Aug 25, 12:00", rows.single().detail)
    }

    @Test
    fun detail_endsAfterThePercentWhenNoFutureMomentIsKnown() {
        val rows = planWindowRows(
            summaryOf(
                allowance("Codex · Weekly plan", used = 91.0, resetsAt = null),
                // Behind the clock: the provider has not caught up, as Cursor's
                // hourly aggregation does. Not "late" — just unsaid.
                allowance("Cursor · Other Models", used = 25.0, resetsAt = "2026-08-17T09:00:00Z"),
                allowance("Cursor · nonsense", used = 25.0, resetsAt = "whenever"),
            ),
            now = now,
            zone = utc,
        )

        assertTrue(rows.map { it.detail }.toString(), rows.none { it.detail.contains("back") })
        assertEquals(listOf("9% left", "75% left", "75% left"), rows.map { it.detail })
    }

    @Test
    fun detail_saysOnlyTheTimeWhenNoPercentageIsReported() {
        val rows = planWindowRows(
            summaryOf(
                allowance("Claude · Weekly plan", used = null, resetsAt = "2026-08-17T19:00:00Z"),
            ),
            now = now,
            zone = utc,
        )

        // A window without a percentage is not a full one; saying "100% left"
        // would invent the number the provider withheld.
        assertEquals("back at 19:00", rows.single().detail)
    }

    @Test
    fun detail_fallsBackToTheRemainderWhenNoShareIsReported() {
        val rows = planWindowRows(
            summaryOf(
                allowance("Cursor · Plan usage", used = null, resetsAt = null).copy(
                    remaining = Quantity(value = "1716.0000", unit = "credits"),
                ),
            ),
            now = now,
            zone = utc,
        )

        // A plan with no published limit knows what is left without knowing the
        // share it makes up; the Usage screen says the same.
        assertEquals("1716 credits left", rows.single().detail)
    }

    @Test
    fun rows_countAnEmptyRemainderAsExhausted() {
        val rows = planWindowRows(
            summaryOf(
                allowance("Claude · Weekly plan", used = 40.0, resetsAt = "2026-08-18T12:00:00Z"),
                allowance("Cursor · Plan usage", used = null, resetsAt = "2026-09-01T00:00:00Z").copy(
                    remaining = Quantity(value = "0", unit = "credits"),
                ),
            ),
            now = now,
            zone = utc,
        )

        // Nothing left is nothing left, whether the provider counts it in
        // percent or in credits.
        assertEquals(listOf("Cursor · Plan usage", "Claude · Weekly plan"), rows.map { it.title })
    }

    @Test
    fun detail_namesAnUnlimitedWindowRatherThanAPercentage() {
        val rows = planWindowRows(
            summaryOf(
                allowance("Codex · Weekly plan", used = null, resetsAt = null).copy(
                    unlimited = true,
                ),
            ),
            now = now,
            zone = utc,
        )

        assertEquals("Unlimited", rows.single().detail)
    }

    @Test
    fun detail_fallsBackToUnavailableRatherThanAnEmptyLine() {
        val rows = planWindowRows(
            summaryOf(allowance("Codex · Weekly plan", used = null, resetsAt = null)),
            now = now,
            zone = utc,
        )

        // An empty second line would read as a rendering fault, not as silence.
        assertEquals("Unavailable", rows.single().detail)
    }

    @Test
    fun rows_sortWindowsWithoutAFutureMomentLast() {
        val rows = planWindowRows(
            summaryOf(
                allowance("Codex · Weekly plan", used = 91.0, resetsAt = null),
                allowance("Cursor · Cursor Models", used = 0.0, resetsAt = "2026-09-01T00:00:00Z"),
            ),
            now = now,
            zone = utc,
        )

        assertEquals(
            listOf("Cursor · Cursor Models", "Codex · Weekly plan"),
            rows.map { it.title },
        )
    }

    private fun summaryOf(vararg allowances: AllowanceSummary) =
        PreviewWatchDashboardSummary.value.copy(allowances = allowances.toList())

    private fun allowance(
        label: String,
        used: Double?,
        resetsAt: String?,
        source: String = "plan",
    ) = AllowanceSummary(
        source = source,
        label = label,
        usedPercent = used,
        remaining = null,
        resetsAt = resetsAt,
        status = PulseStatus.OK,
    )
}
