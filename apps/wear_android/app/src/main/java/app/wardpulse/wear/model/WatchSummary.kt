package app.wardpulse.wear.model

import java.time.Instant
import java.time.ZoneOffset
import java.time.format.DateTimeFormatter
import java.time.format.DateTimeParseException
import java.util.Locale

enum class PulseStatus(val label: String) {
    OK("OK"),
    WARNING("Warning"),
    ERROR("Error"),
    UNKNOWN("Unknown"),
}

data class PeriodSummary(
    val spent: String,
    val limit: String,
    val remaining: String,
    val usedPercent: Double,
    val projectedTotal: String? = null,
)

data class ProviderSummary(
    val name: String,
    val main: String,
    val status: PulseStatus,
)

data class AlertSummary(
    val title: String,
    val message: String,
)

data class WatchSummary(
    val generatedAt: String,
    val overallStatus: PulseStatus,
    val today: PeriodSummary,
    val week: PeriodSummary,
    val providers: List<ProviderSummary>,
    val alerts: List<AlertSummary>,
    val isStale: Boolean,
) {
    val lastSyncLabel: String
        get() = try {
            LAST_SYNC_FORMAT.format(Instant.parse(generatedAt))
        } catch (_: DateTimeParseException) {
            "Unknown"
        }

    private companion object {
        val LAST_SYNC_FORMAT: DateTimeFormatter =
            DateTimeFormatter.ofPattern("MMM d, HH:mm 'UTC'", Locale.US)
                .withZone(ZoneOffset.UTC)
    }
}

object MockWatchSummary {
    val value = WatchSummary(
        generatedAt = "2026-06-27T18:42:00Z",
        overallStatus = PulseStatus.OK,
        today = PeriodSummary(
            spent = "12.40",
            limit = "50.00",
            remaining = "37.60",
            usedPercent = 24.8,
        ),
        week = PeriodSummary(
            spent = "71.30",
            limit = "250.00",
            remaining = "178.70",
            usedPercent = 28.5,
            projectedTotal = "228.00",
        ),
        providers = listOf(
            ProviderSummary(
                name = "Mock provider",
                main = "\$12.40",
                status = PulseStatus.OK,
            ),
        ),
        alerts = emptyList(),
        isStale = true,
    )
}
