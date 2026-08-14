package app.wardpulse.wear.model

import java.time.Duration
import java.time.Instant
import java.time.ZoneId
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

enum class WatchDataMode(val wireName: String) {
    LIVE("live"),
    MOCK("mock"),
    ;

    companion object {
        fun fromWireName(value: String): WatchDataMode? = entries.firstOrNull { it.wireName == value }
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
    /** Display form — strip provider float noise like `500.0000000000`. */
    val label: String
        get() = "${formatQuantityValue(value)} $unit"
}

/** `500.0000000000` → `500`, `12.50` → `12.5`. */
internal fun formatQuantityValue(value: String): String {
    if (!value.contains('.')) {
        return value
    }
    val trimmed = value.trimEnd('0')
    return if (trimmed.endsWith('.')) trimmed.dropLast(1) else trimmed
}

data class RingSummary(
    val id: String,
    val label: String,
    val usedPercent: Double,
    val status: PulseStatus,
    /** Budget rings carry their money; a plan window has none, so both stay null. */
    val spent: Money? = null,
    val limit: Money? = null,
    /**
     * The other pool of the same plan, drawn as the outer half of this one band
     * (`WATCH_RING_DESIGN.md`, Split band). One entry is one band, so a pair
     * costs one of the three.
     */
    val split: RingHalf? = null,
)

/** The outer half of a split band: a pool, without money it never has. */
data class RingHalf(
    val id: String,
    val label: String,
    val usedPercent: Double,
    val status: PulseStatus,
)

/** Compact remaining purchased credits for the watch-face SHORT_TEXT slot. */
data class CreditsGlance(
    val text: String,
    val label: String,
    val provider: String?,
)

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
    val dataMode: WatchDataMode,
    val generatedAt: String,
    val overallStatus: PulseStatus,
    val rings: List<RingSummary>,
    val creditsGlance: CreditsGlance?,
    val today: PeriodSummary,
    val week: PeriodSummary,
    val allowances: List<AllowanceSummary>,
    val providers: List<ProviderSummary>,
    val alerts: List<AlertSummary>,
    val isStale: Boolean,
    /** Phone PollCadence floor — Wear must not invent its own cooldown. */
    val manualRefreshAllowed: Boolean,
    /** ISO-8601 instant when refresh becomes allowed; null when already allowed. */
    val manualRefreshAvailableAt: String?,
) {
    /** Phone flags plus local wall clock (re-enable when [manualRefreshAvailableAt] passes). */
    fun isManualRefreshAllowed(now: Instant = Instant.now()): Boolean {
        if (manualRefreshAllowed) {
            return true
        }
        val availableAt = manualRefreshAvailableAt ?: return false
        return try {
            !now.isBefore(Instant.parse(availableAt))
        } catch (_: DateTimeParseException) {
            false
        }
    }

    /** Device-local wall clock for the Last sync screen. */
    val lastSyncLabel: String
        get() = try {
            LAST_SYNC_LOCAL_FORMAT.format(Instant.parse(generatedAt))
        } catch (_: DateTimeParseException) {
            "Unknown"
        }

    /** UTC disclosure shown alongside [lastSyncLabel]. */
    val lastSyncUtcLabel: String
        get() = try {
            LAST_SYNC_UTC_FORMAT.format(Instant.parse(generatedAt))
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
        val LAST_SYNC_LOCAL_FORMAT: DateTimeFormatter =
            DateTimeFormatter.ofPattern("MMM d, HH:mm", Locale.US)
                .withZone(ZoneId.systemDefault())
        val LAST_SYNC_UTC_FORMAT: DateTimeFormatter =
            DateTimeFormatter.ofPattern("MMM d, HH:mm 'UTC'", Locale.US)
                .withZone(ZoneOffset.UTC)
        val STALE_AFTER: Duration = Duration.ofHours(2)
    }
}

object PreviewWatchDashboardSummary {
    val value = WatchDashboardSummary(
        schemaVersion = 9,
        dataMode = WatchDataMode.MOCK,
        generatedAt = "2026-06-27T18:42:00Z",
        overallStatus = PulseStatus.OK,
        rings = listOf(
            // Surface order: tightest remaining first (center/inner on face; top on Glance).
            RingSummary(
                "budget.anthropic.platform.week",
                "Week",
                28.5,
                PulseStatus.OK,
                spent = Money(7_130, "USD"),
                limit = Money(25_000, "USD"),
            ),
            RingSummary(
                "budget.anthropic.platform.month",
                "Month",
                26.5,
                PulseStatus.OK,
                spent = Money(21_210, "USD"),
                limit = Money(80_000, "USD"),
            ),
            RingSummary(
                "budget.anthropic.platform.today",
                "Today",
                24.8,
                PulseStatus.OK,
                spent = Money(1_240, "USD"),
                limit = Money(5_000, "USD"),
            ),
        ),
        creditsGlance = CreditsGlance(text = "500", label = "Credits left", provider = "mock"),
        // Period totals carry money only: limits are per connection, so the sum
        // across connections has no ceiling, percentage, or status of its own.
        today = PeriodSummary(
            period = "today",
            spent = Money(1_240, "USD"),
            limit = null,
            remaining = null,
            usedPercent = null,
            projectedTotal = null,
            status = PulseStatus.UNKNOWN,
        ),
        week = PeriodSummary(
            period = "week",
            spent = Money(7_130, "USD"),
            limit = null,
            remaining = null,
            usedPercent = null,
            projectedTotal = Money(22_800, "USD"),
            status = PulseStatus.UNKNOWN,
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
        manualRefreshAllowed = true,
        manualRefreshAvailableAt = null,
    )

    /** Glance legend preview — live providers + per-provider credits. */
    val glanceLegend = value.copy(
        dataMode = WatchDataMode.LIVE,
        generatedAt = "2026-07-26T08:06:00Z",
        isStale = false,
        rings = listOf(
            RingSummary("allowance.codex.week", "Weekly plan", 92.0, PulseStatus.OK),
            RingSummary("allowance.claude.plan", "5h", 61.0, PulseStatus.OK),
            // Matches fixtures/providers/cursor/usage_summary.json autoPercentUsed.
            RingSummary(
                "allowance.cursor.cursor-plan-models",
                "Cursor Models",
                47.0,
                PulseStatus.OK,
            ),
        ),
        creditsGlance = CreditsGlance(text = "400", label = "Credits left", provider = "codex"),
        allowances = listOf(
            AllowanceSummary(
                source = "purchased",
                label = "Codex · Credits",
                usedPercent = null,
                remaining = Quantity("320", "credits"),
                unlimited = false,
                resetsAt = null,
                status = PulseStatus.OK,
            ),
            AllowanceSummary(
                source = "purchased",
                label = "Claude · Credits",
                usedPercent = null,
                remaining = Quantity("80", "credits"),
                unlimited = false,
                resetsAt = null,
                status = PulseStatus.OK,
            ),
        ),
        providers = listOf(
            ProviderSummary(
                provider = "codex",
                status = PulseStatus.OK,
                todaySpent = Money(1_240, "USD"),
            ),
        ),
    )
}
