package app.wardpulse.wear.data

import android.content.Context
import android.content.SharedPreferences
import androidx.core.content.edit
import app.wardpulse.wear.model.AlertSummary
import app.wardpulse.wear.model.Money
import app.wardpulse.wear.model.PeriodSummary
import app.wardpulse.wear.model.ProviderSummary
import app.wardpulse.wear.model.PulseStatus
import app.wardpulse.wear.model.WatchDashboardSummary
import java.time.Instant
import org.json.JSONArray
import org.json.JSONException
import org.json.JSONObject

class WatchSummaryStore(private val preferences: SharedPreferences) {
    constructor(context: Context) : this(
        context.getSharedPreferences(PREFERENCES_NAME, Context.MODE_PRIVATE),
    )

    fun load(): WatchDashboardSummary? =
        preferences.getString(SUMMARY_KEY, null)?.let(WatchDashboardSummaryCodec::decode)

    fun save(summary: WatchDashboardSummary) {
        preferences.edit {
            putString(SUMMARY_KEY, WatchDashboardSummaryCodec.encode(summary))
        }
    }

    fun saveEncoded(encoded: String): Boolean {
        if (WatchDashboardSummaryCodec.decode(encoded) == null) {
            return false
        }

        preferences.edit {
            putString(SUMMARY_KEY, encoded)
        }
        return true
    }

    fun observe(onChanged: () -> Unit): AutoCloseable {
        val listener = SharedPreferences.OnSharedPreferenceChangeListener { _, key ->
            if (key == SUMMARY_KEY) {
                onChanged()
            }
        }
        preferences.registerOnSharedPreferenceChangeListener(listener)
        return AutoCloseable {
            preferences.unregisterOnSharedPreferenceChangeListener(listener)
        }
    }

    private companion object {
        const val PREFERENCES_NAME = "watch_summary"
        const val SUMMARY_KEY = "latest"
    }
}

private object WatchDashboardSummaryCodec {
    fun encode(summary: WatchDashboardSummary): String = summary.toJson().toString()

    fun decode(encoded: String): WatchDashboardSummary? = try {
        JSONObject(encoded).toWatchDashboardSummary()
    } catch (_: JSONException) {
        null
    } catch (_: RuntimeException) {
        null
    }
}

private fun WatchDashboardSummary.toJson() = JSONObject().apply {
    put("schemaVersion", schemaVersion)
    put("generatedAt", generatedAt)
    put("overallStatus", overallStatus.wireName)
    put("today", today.toJson())
    put("week", week.toJson())
    put("providers", JSONArray().apply { providers.forEach { put(it.toJson()) } })
    put("alerts", JSONArray().apply { alerts.forEach { put(it.toJson()) } })
    put("isStale", isStale)
}

private fun PeriodSummary.toJson() = JSONObject().apply {
    put("period", period)
    put("spent", spent?.toJson() ?: JSONObject.NULL)
    put("limit", limit?.toJson() ?: JSONObject.NULL)
    put("remaining", remaining?.toJson() ?: JSONObject.NULL)
    put("usedPercent", usedPercent ?: JSONObject.NULL)
    put("projectedTotal", projectedTotal?.toJson() ?: JSONObject.NULL)
    put("status", status.wireName)
}

private fun Money.toJson() = JSONObject().apply {
    put("minorUnits", minorUnits)
    put("currency", currency)
}

private fun ProviderSummary.toJson() = JSONObject().apply {
    put("provider", provider)
    put("status", status.wireName)
    put("todaySpent", todaySpent?.toJson() ?: JSONObject.NULL)
}

private fun AlertSummary.toJson() = JSONObject().apply {
    put("severity", severity)
    put("message", message)
}

private fun JSONObject.toWatchDashboardSummary(): WatchDashboardSummary {
    require(getInt("schemaVersion") == SCHEMA_VERSION)
    val generatedAt = getString("generatedAt").also(Instant::parse)
    val today = getJSONObject("today").toPeriodSummary()
    val week = getJSONObject("week").toPeriodSummary()
    require(today.period == "today")
    require(week.period == "week")

    return WatchDashboardSummary(
        schemaVersion = SCHEMA_VERSION,
        generatedAt = generatedAt,
        overallStatus = getString("overallStatus").toPulseStatus(),
        today = today,
        week = week,
        providers = getJSONArray("providers").mapObjects { it.toProviderSummary() },
        alerts = getJSONArray("alerts").mapObjects { it.toAlertSummary() },
        isStale = getBoolean("isStale"),
    )
}

private fun JSONObject.toPeriodSummary() = PeriodSummary(
    period = getString("period"),
    spent = nullableObject("spent")?.toMoney(),
    limit = nullableObject("limit")?.toMoney(),
    remaining = nullableObject("remaining")?.toMoney(),
    usedPercent = nullableDouble("usedPercent"),
    projectedTotal = nullableObject("projectedTotal")?.toMoney(),
    status = getString("status").toPulseStatus(),
)

private fun JSONObject.toMoney(): Money {
    val currency = getString("currency")
    require(CURRENCY_PATTERN.matches(currency))
    return Money(
        minorUnits = getLong("minorUnits"),
        currency = currency,
    )
}

private fun JSONObject.toProviderSummary(): ProviderSummary {
    val provider = getString("provider")
    require(provider in PROVIDERS)
    return ProviderSummary(
        provider = provider,
        status = getString("status").toPulseStatus(),
        todaySpent = nullableObject("todaySpent")?.toMoney(),
    )
}

private fun JSONObject.toAlertSummary(): AlertSummary {
    val severity = getString("severity")
    require(severity in ALERT_SEVERITIES)
    return AlertSummary(
        severity = severity,
        message = getString("message"),
    )
}

private fun JSONObject.nullableObject(key: String): JSONObject? =
    if (isNull(key)) null else getJSONObject(key)

private fun JSONObject.nullableDouble(key: String): Double? =
    if (isNull(key)) null else getDouble(key)

private inline fun <T> JSONArray.mapObjects(transform: (JSONObject) -> T): List<T> =
    List(length()) { index -> transform(getJSONObject(index)) }

private fun String.toPulseStatus(): PulseStatus = requireNotNull(PulseStatus.fromWireName(this))

private const val SCHEMA_VERSION = 1
private val CURRENCY_PATTERN = Regex("^[A-Z]{3}$")
private val PROVIDERS = setOf("openai", "claude", "cursor", "mock")
private val ALERT_SEVERITIES = setOf("info", "warning", "error")
