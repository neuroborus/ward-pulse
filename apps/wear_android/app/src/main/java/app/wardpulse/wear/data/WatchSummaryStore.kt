package app.wardpulse.wear.data

import android.content.Context
import android.content.SharedPreferences
import androidx.core.content.edit
import app.wardpulse.wear.BuildConfig
import app.wardpulse.wear.model.AlertSummary
import app.wardpulse.wear.model.AllowanceSummary
import app.wardpulse.wear.model.Money
import app.wardpulse.wear.model.PeriodSummary
import app.wardpulse.wear.model.ProviderSummary
import app.wardpulse.wear.model.RingHalf
import app.wardpulse.wear.model.RingSummary
import app.wardpulse.wear.model.PulseStatus
import app.wardpulse.wear.model.Quantity
import app.wardpulse.wear.model.CreditsGlance
import app.wardpulse.wear.model.WatchDashboardSummary
import app.wardpulse.wear.model.WatchDataMode
import java.time.Instant
import org.json.JSONArray
import org.json.JSONException
import org.json.JSONObject

class WatchSummaryStore(private val preferences: SharedPreferences) {
    constructor(context: Context) : this(
        // One process-wide prefs instance for Activity + WearableListenerService.
        context.applicationContext.getSharedPreferences(
            PREFERENCES_NAME,
            Context.MODE_PRIVATE,
        ),
    )

    fun load(): WatchDashboardSummary? =
        preferences.getString(SUMMARY_KEY, null)
            ?.let(WatchDashboardSummaryCodec::decode)
            ?.takeIf(::isAllowedForBuild)

    fun save(summary: WatchDashboardSummary) {
        if (!isAllowedForBuild(summary)) {
            return
        }
        preferences.edit {
            putString(SUMMARY_KEY, WatchDashboardSummaryCodec.encode(summary))
        }
    }

    fun saveEncoded(encoded: String): Boolean {
        val summary = WatchDashboardSummaryCodec.decode(encoded)
        if (summary == null || !isAllowedForBuild(summary)) {
            return false
        }

        preferences.edit {
            putString(SUMMARY_KEY, encoded)
        }
        return true
    }

    private fun isAllowedForBuild(summary: WatchDashboardSummary): Boolean =
        BuildConfig.DEBUG || summary.dataMode == WatchDataMode.LIVE

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
    put("dataMode", dataMode.wireName)
    put("generatedAt", generatedAt)
    put("overallStatus", overallStatus.wireName)
    put("rings", JSONArray().apply { rings.forEach { put(it.toJson()) } })
    put("creditsGlance", creditsGlance?.toJson() ?: JSONObject.NULL)
    put("today", today.toJson())
    put("week", week.toJson())
    put("allowances", JSONArray().apply { allowances.forEach { put(it.toJson()) } })
    put("providers", JSONArray().apply { providers.forEach { put(it.toJson()) } })
    put("alerts", JSONArray().apply { alerts.forEach { put(it.toJson()) } })
    put("isStale", isStale)
    put("manualRefreshAllowed", manualRefreshAllowed)
    put(
        "manualRefreshAvailableAt",
        manualRefreshAvailableAt ?: JSONObject.NULL,
    )
}

private fun CreditsGlance.toJson() = JSONObject().apply {
    put("text", text)
    put("label", label)
    put("provider", provider ?: JSONObject.NULL)
}

private fun RingSummary.toJson() = JSONObject().apply {
    put("id", id)
    put("label", label)
    put("usedPercent", usedPercent)
    put("status", status.wireName)
    put("spent", spent?.toJson() ?: JSONObject.NULL)
    put("limit", limit?.toJson() ?: JSONObject.NULL)
    put("split", split?.toJson() ?: JSONObject.NULL)
}

private fun RingHalf.toJson() = JSONObject().apply {
    put("id", id)
    put("label", label)
    put("usedPercent", usedPercent)
    put("status", status.wireName)
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

private fun AllowanceSummary.toJson() = JSONObject().apply {
    put("source", source)
    put("label", label)
    put("usedPercent", usedPercent ?: JSONObject.NULL)
    put("remaining", remaining?.toJson() ?: JSONObject.NULL)
    put("unlimited", unlimited)
    put("resetsAt", resetsAt ?: JSONObject.NULL)
    put("status", status.wireName)
}

private fun Quantity.toJson() = JSONObject().apply {
    put("value", value)
    put("unit", unit)
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
        dataMode = requireNotNull(WatchDataMode.fromWireName(getString("dataMode"))),
        generatedAt = generatedAt,
        overallStatus = getString("overallStatus").toPulseStatus(),
        rings = getJSONArray("rings").mapObjects { it.toRingSummary() }
            .take(MAX_RINGS),
        creditsGlance = nullableObject("creditsGlance")?.toCreditsGlance(),
        today = today,
        week = week,
        allowances = getJSONArray("allowances").mapObjects { it.toAllowanceSummary() },
        providers = getJSONArray("providers").mapObjects { it.toProviderSummary() },
        alerts = getJSONArray("alerts").mapObjects { it.toAlertSummary() },
        isStale = getBoolean("isStale"),
        manualRefreshAllowed = getBoolean("manualRefreshAllowed"),
        manualRefreshAvailableAt = nullableString("manualRefreshAvailableAt"),
    )
}

private fun JSONObject.toCreditsGlance(): CreditsGlance {
    val text = getString("text")
    require(text.isNotEmpty() && text.length <= 12)
    val label = getString("label")
    require(label.isNotEmpty() && label.length <= 24)
    val provider = nullableString("provider")
    if (provider != null) {
        require(provider in PROVIDERS)
    }
    return CreditsGlance(text = text, label = label, provider = provider)
}

private fun JSONObject.toRingSummary(): RingSummary {
    val id = getString("id")
    require(id.isNotEmpty())
    val usedPercent = getDouble("usedPercent")
    require(usedPercent >= 0.0)
    return RingSummary(
        id = id,
        label = getString("label").also { require(it.isNotEmpty()) },
        usedPercent = usedPercent,
        status = getString("status").toPulseStatus(),
        spent = nullableObject("spent")?.toMoney(),
        limit = nullableObject("limit")?.toMoney(),
        split = nullableObject("split")?.toRingHalf(),
    )
}

private fun JSONObject.toRingHalf(): RingHalf {
    val usedPercent = getDouble("usedPercent")
    require(usedPercent >= 0.0)
    return RingHalf(
        id = getString("id").also { require(it.isNotEmpty()) },
        label = getString("label").also { require(it.isNotEmpty()) },
        usedPercent = usedPercent,
        status = getString("status").toPulseStatus(),
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

private fun JSONObject.toAllowanceSummary(): AllowanceSummary {
    val source = getString("source")
    require(source in ALLOWANCE_SOURCES)
    val resetsAt = nullableString("resetsAt")?.also(Instant::parse)
    return AllowanceSummary(
        source = source,
        label = getString("label"),
        usedPercent = nullableDouble("usedPercent"),
        remaining = nullableObject("remaining")?.toQuantity(),
        unlimited = optBoolean("unlimited", false),
        resetsAt = resetsAt,
        status = getString("status").toPulseStatus(),
    )
}

private fun JSONObject.toQuantity(): Quantity {
    val unit = getString("unit")
    require(unit in QUANTITY_UNITS)
    return Quantity(value = getString("value"), unit = unit)
}

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

private fun JSONObject.nullableString(key: String): String? =
    if (isNull(key)) null else getString(key)

private inline fun <T> JSONArray.mapObjects(transform: (JSONObject) -> T): List<T> =
    List(length()) { index -> transform(getJSONObject(index)) }

private fun String.toPulseStatus(): PulseStatus = requireNotNull(PulseStatus.fromWireName(this))

private const val SCHEMA_VERSION = 9
private const val MAX_RINGS = 3
private val CURRENCY_PATTERN = Regex("^[A-Z]{3}$")
private val PROVIDERS = setOf("openai", "codex", "claude", "cursor", "mock")
private val ALLOWANCE_SOURCES = setOf("plan", "purchased")
private val QUANTITY_UNITS = setOf("tokens", "credits")
private val ALERT_SEVERITIES = setOf("info", "warning", "error")
