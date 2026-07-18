package app.wardpulse.wear.data

import android.content.Context
import android.content.SharedPreferences
import androidx.core.content.edit
import app.wardpulse.wear.model.AlertSummary
import app.wardpulse.wear.model.PeriodSummary
import app.wardpulse.wear.model.ProviderSummary
import app.wardpulse.wear.model.PulseStatus
import app.wardpulse.wear.model.WatchSummary
import org.json.JSONArray
import org.json.JSONException
import org.json.JSONObject

class WatchSummaryStore(private val preferences: SharedPreferences) {
    constructor(context: Context) : this(
        context.getSharedPreferences(PREFERENCES_NAME, Context.MODE_PRIVATE),
    )

    fun load(): WatchSummary? {
        val encoded = preferences.getString(SUMMARY_KEY, null) ?: return null

        return try {
            JSONObject(encoded).toWatchSummary()
        } catch (_: JSONException) {
            null
        }
    }

    fun save(summary: WatchSummary) {
        preferences.edit {
            putString(SUMMARY_KEY, summary.toJson().toString())
        }
    }

    private companion object {
        const val PREFERENCES_NAME = "watch_summary"
        const val SUMMARY_KEY = "latest"
    }
}

private fun WatchSummary.toJson() = JSONObject().apply {
    put("generatedAt", generatedAt)
    put("overallStatus", overallStatus.name)
    put("today", today.toJson())
    put("week", week.toJson())
    put("providers", JSONArray().apply { providers.forEach { put(it.toJson()) } })
    put("alerts", JSONArray().apply { alerts.forEach { put(it.toJson()) } })
    put("isStale", isStale)
}

private fun PeriodSummary.toJson() = JSONObject().apply {
    put("spent", spent)
    put("limit", limit)
    put("remaining", remaining)
    put("usedPercent", usedPercent)
    put("projectedTotal", projectedTotal)
}

private fun ProviderSummary.toJson() = JSONObject().apply {
    put("name", name)
    put("main", main)
    put("status", status.name)
}

private fun AlertSummary.toJson() = JSONObject().apply {
    put("title", title)
    put("message", message)
}

private fun JSONObject.toWatchSummary() = WatchSummary(
    generatedAt = getString("generatedAt"),
    overallStatus = getString("overallStatus").toPulseStatus(),
    today = getJSONObject("today").toPeriodSummary(),
    week = getJSONObject("week").toPeriodSummary(),
    providers = getJSONArray("providers").mapObjects { it.toProviderSummary() },
    alerts = getJSONArray("alerts").mapObjects { it.toAlertSummary() },
    isStale = getBoolean("isStale"),
)

private fun JSONObject.toPeriodSummary() = PeriodSummary(
    spent = getString("spent"),
    limit = getString("limit"),
    remaining = getString("remaining"),
    usedPercent = getDouble("usedPercent"),
    projectedTotal = optString("projectedTotal").takeIf { it.isNotEmpty() },
)

private fun JSONObject.toProviderSummary() = ProviderSummary(
    name = getString("name"),
    main = getString("main"),
    status = getString("status").toPulseStatus(),
)

private fun JSONObject.toAlertSummary() = AlertSummary(
    title = getString("title"),
    message = getString("message"),
)

private inline fun <T> JSONArray.mapObjects(transform: (JSONObject) -> T): List<T> =
    List(length()) { index -> transform(getJSONObject(index)) }

private fun String.toPulseStatus(): PulseStatus =
    PulseStatus.entries.firstOrNull { it.name == this } ?: PulseStatus.UNKNOWN
