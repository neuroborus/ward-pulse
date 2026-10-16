package app.wardpulse.wear.ui

import app.wardpulse.wear.model.AlertSummary
import app.wardpulse.wear.model.PreviewWatchDashboardSummary
import app.wardpulse.wear.model.ProviderSummary
import app.wardpulse.wear.model.PulseStatus
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class AlertRowsTest {
    @Test
    fun clearingLastAlertDoesNotClaimAnUnhealthyProviderIsNormal() {
        for (status in listOf(
            PulseStatus.STALE,
            PulseStatus.AUTH_REQUIRED,
            PulseStatus.ERROR,
            PulseStatus.RATE_LIMITED,
            PulseStatus.WARNING,
            PulseStatus.UNKNOWN,
        )) {
            val withAlert = PreviewWatchDashboardSummary.value.copy(
                overallStatus = status,
                providers = listOf(ProviderSummary("openai", status, null)),
                alerts = listOf(AlertSummary("warning", "Audit alert")),
                isStale = status == PulseStatus.STALE,
            )
            assertEquals("Audit alert", withAlert.alertRows().single().detail)

            val cleared = withAlert.copy(alerts = emptyList())
            val row = cleared.alertRows().single()
            assertEquals(status.name, "No active alerts", row.title)
            assertEquals(status.name, "No alerts in the latest summary", row.detail)
            assertNull(status.name, row.status)
        }
    }

    @Test
    fun activeAlertRowsKeepOrderMessagesAndSeverityMappings() {
        val summary = PreviewWatchDashboardSummary.value.copy(
            alerts = listOf(
                AlertSummary("info", "Informational audit alert"),
                AlertSummary("warning", "Warning audit alert"),
                AlertSummary("error", "Error audit alert"),
            ),
        )
        val rows = summary.alertRows()
        assertEquals(listOf("Info", "Warning", "Error"), rows.map { it.title })
        assertEquals(summary.alerts.map { it.message }, rows.map { it.detail })
        assertEquals(
            listOf(PulseStatus.UNKNOWN, PulseStatus.WARNING, PulseStatus.ERROR),
            rows.map { it.status },
        )
    }
}
