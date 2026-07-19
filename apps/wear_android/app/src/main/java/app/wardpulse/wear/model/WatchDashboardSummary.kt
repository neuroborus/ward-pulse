package app.wardpulse.wear.model

import java.time.Duration
import java.time.Instant
import java.time.ZoneOffset
import java.time.format.DateTimeFormatter
import java.time.format.DateTimeParseException
import java.util.Locale

enum class PulseStatus(
    val wireName: String,
    val label: String,
) {
    OK("ok", "OK"),
    WARNING("warning", "Warning"),
    ERROR("error", "Error"),
    RATE_LIMITED("rateLimited", "Rate limited"),
    AUTH_REQUIRED("authRequired", "Auth required"),
    STALE("stale", "Stale"),
    UNKNOWN("unknown", "Unknown"),
    ;

    companion object {
        fun fromWireName(value: String): PulseStatus? = entries.firstOrNull { it.wireName == value }
    }
}

data class Money(
    val minorUnits: Long,
    val currency: String,
) {
    val label: String
        get() {
            val encoded = minorUnits.toString()
            val sign = if (encoded.startsWith('-')) "-" else ""
            val absolute = encoded.removePrefix("-").padStart(3, '0')
            val major = absolute.dropLast(2)
            val minor = absolute.takeLast(2)
            return "$sign$currency $major.$minor"
        }
}

data class PeriodSummary(
    val period: String,
    val spent: Money?,
    val limit: Money?,
    val remaining: Money?,
    val usedPercent: Double?,
    val projectedTotal: Money?,
    val status: PulseStatus,
)

data class Quantity(
    val value: String,
    val unit: String,
) {
    val label: String
        get() = "$value $unit"
}

data class AllowanceSummary(
    val source: String,
    val label: String,
    val usedPercent: Double?,
    val remaining: Quantity?,
    val unlimited: Boolean = false,
    val resetsAt: String?,
    val status: PulseStatus,
)

data class ProviderSummary(
    val provider: String,
    val status: PulseStatus,
    val todaySpent: Money?,
) {
    val providerLabel: String
        get() = when (provider) {
            "openai" -> "OpenAI"
            "codex" -> "Codex"
            "claude" -> "Claude"
            "cursor" -> "Cursor"
            "mock" -> "Mock"
            else -> provider
        }
}

data class AlertSummary(
    val severity: String,
    val message: String,
)

data class WatchDashboardSummary(
    val schemaVersion: Int,
    val generatedAt: String,
    val overallStatus: PulseStatus,
    val today: PeriodSummary,
    val week: PeriodSummary,
    val allowances: List<AllowanceSummary>,
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

    fun isStaleAt(now: Instant): Boolean {
        if (isStale) {
            return true
        }

        return try {
            Duration.between(Instant.parse(generatedAt), now) >= STALE_AFTER
        } catch (_: DateTimeParseException) {
            true
        }
    }

    private companion object {
        val LAST_SYNC_FORMAT: DateTimeFormatter =
            DateTimeFormatter.ofPattern("MMM d, HH:mm 'UTC'", Locale.US)
                .withZone(ZoneOffset.UTC)
        val STALE_AFTER: Duration = Duration.ofHours(2)
    }
}

object MockWatchDashboardSummary {
    val value = WatchDashboardSummary(
        schemaVersion = 2,
        generatedAt = "2026-06-27T18:42:00Z",
        overallStatus = PulseStatus.OK,
        today = PeriodSummary(
            period = "today",
            spent = Money(1_240, "USD"),
            limit = Money(5_000, "USD"),
            remaining = Money(3_760, "USD"),
            usedPercent = 24.8,
            projectedTotal = null,
            status = PulseStatus.OK,
        ),
        week = PeriodSummary(
            period = "week",
            spent = Money(7_130, "USD"),
            limit = Money(25_000, "USD"),
            remaining = Money(17_870, "USD"),
            usedPercent = 28.52,
            projectedTotal = Money(22_800, "USD"),
            status = PulseStatus.OK,
        ),
        allowances = emptyList(),
        providers = listOf(
            ProviderSummary(
                provider = "mock",
                status = PulseStatus.OK,
                todaySpent = Money(1_240, "USD"),
            ),
        ),
        alerts = emptyList(),
        isStale = true,
    )
}
