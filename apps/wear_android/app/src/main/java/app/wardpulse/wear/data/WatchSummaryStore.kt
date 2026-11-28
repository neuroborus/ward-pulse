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

/** The phone install, data-mode generation and publication order of one v10 summary. */
data class SummaryOwner(
    val installId: String,
    val generation: Long,
    val sequence: Long,
)

/**
 * The phone route whose summary this watch accepted. [owner] is null for a v9-only binding,
 * which has no ownership fields; its refresh taps send the legacy empty message.
 */
data class SummaryBinding(
    val host: String,
    val owner: SummaryOwner?,
)

/**
 * A stored summary with the binding it was accepted under, read together, so a refresh from the
 * rendered summary names its own owner even after a newer summary is accepted.
 */
data class BoundSummary(
    val summary: WatchDashboardSummary,
    val binding: SummaryBinding?,
)

/** A decoded v10 Data Item value, with the exact encoded text that would be stored. */
class OrderedSummary internal constructor(
    val summary: WatchDashboardSummary,
    val owner: SummaryOwner,
    val encoded: String,
)

/**
 * The order of route resolutions ([WatchSummaryStore.beginAttempt]) and the deciding one, guarded
 * by the store monitor. The activity, listener and complication stores of one process share
 * [process].
 */
class SummaryAttempts {
    internal var started = 0L
    internal var claimed = 0L

    companion object {
        val process = SummaryAttempts()
    }
}

/**
 * Persisted summary, binding and order watermark.
 *
 * [debugBuild] supplies the build policy: production accepts Live and product Demo and rejects
 * Debug Mock on persisted reads and incoming writes alike. [attempts] orders route resolutions.
 */
class WatchSummaryStore(
    private val preferences: SharedPreferences,
    private val debugBuild: Boolean = BuildConfig.DEBUG,
    private val attempts: SummaryAttempts = SummaryAttempts.process,
) {
    constructor(context: Context) : this(
        // One process-wide prefs instance for Activity + WearableListenerService.
        context.applicationContext.getSharedPreferences(
            PREFERENCES_NAME,
            Context.MODE_PRIVATE,
        ),
    )

    /** Waits for an [accept] in progress, so a failed commit's candidate is never rendered. */
    fun load(): WatchDashboardSummary? = synchronized(monitor) {
        preferences.getString(SUMMARY_KEY, null)
            ?.let(WatchDashboardSummaryCodec::decode)
            ?.takeIf(::isAllowedForBuild)
    }

    /** [load] and [binding] in one step, ordered against [accept]. */
    fun loadBound(): BoundSummary? = synchronized(monitor) {
        load()?.let { BoundSummary(it, binding()) }
    }

    /** Stores a v9 summary; v10 ownership fields have no model value, so v10 arrives encoded. */
    fun save(summary: WatchDashboardSummary) {
        if (!isAllowedForBuild(summary) || summary.schemaVersion != LEGACY_SCHEMA_VERSION) {
            return
        }
        preferences.edit {
            putString(SUMMARY_KEY, WatchDashboardSummaryCodec.encode(summary))
        }
    }

    /** Stores an unbound summary of either version; incoming Data Items use [accept]. */
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

    /** Strictly decodes an incoming v10 value; null rejects it without a v9 fallback. */
    fun decodeOrdered(encoded: String): OrderedSummary? =
        WatchDashboardSummaryCodec.decodeOrdered(encoded)?.takeIf { isAllowedForBuild(it.summary) }

    /** Decodes an incoming v9 projection; a v10 value under the v9 key is rejected. */
    fun decodeLegacy(encoded: String): WatchDashboardSummary? =
        WatchDashboardSummaryCodec.decode(encoded)
            ?.takeIf { it.schemaVersion == LEGACY_SCHEMA_VERSION && isAllowedForBuild(it) }

    /**
     * Starts a route resolution before it reads the route; resolutions are ordered by this start,
     * not by when their reads return. Starting retires nothing.
     */
    fun beginAttempt(): Long = synchronized(monitor) { ++attempts.started }

    /**
     * Makes [attempt] the deciding resolution once its item needs a proof or its route was found
     * invalid, retiring every older one: their [accept] calls fail. False when a newer resolution
     * already decided, so an older read never retires a newer proof. An unchanged item decides
     * nothing.
     */
    fun claimAttempt(attempt: Long): Boolean = synchronized(monitor) {
        if (attempt < attempts.claimed) return false
        attempts.claimed = attempt
        true
    }

    fun attemptCurrent(attempt: Long): Boolean = synchronized(monitor) { attempts.claimed == attempt }

    fun binding(): SummaryBinding? = synchronized(monitor) {
        val host = preferences.getString(BOUND_HOST_KEY, null) ?: return null
        val installId = preferences.getString(BOUND_INSTALL_KEY, null)
        val owner = installId?.let {
            SummaryOwner(
                installId = it,
                generation = preferences.getLong(BOUND_GENERATION_KEY, -1L),
                sequence = preferences.getLong(BOUND_SEQUENCE_KEY, 0L),
            )
        }
        SummaryBinding(host, owner)
    }

    /** Whether [host] ever had a v10 summary accepted; its v9 projection is then never read. */
    fun orderedRoute(host: String): Boolean = synchronized(monitor) {
        preferences.getStringSet(ORDERED_HOSTS_KEY, emptySet())?.contains(host) == true
    }

    /**
     * The confirmed accepted item for the current binding: neither a phone request nor a write
     * follows. A failed commit is rolled back, so its item is not unchanged and can retry.
     */
    fun unchanged(host: String, encoded: String): Boolean = synchronized(monitor) {
        preferences.getString(BOUND_HOST_KEY, null) == host &&
            preferences.getString(SUMMARY_KEY, null) == encoded
    }

    /**
     * Stores the binding, watermark and summary in one commit while [attempt] is the deciding
     * resolution. False for an item already held, so each delivery is accepted once.
     *
     * Within one install an ordered summary below the watermark is refused; a verified new
     * install starts a fresh counter. Null [owner] stores a v9 binding, refused once the
     * route established v10 ownership. SharedPreferences keeps a failed commit in memory, so the
     * previous record is restored: rendering, the binding and [unchanged] follow confirmed writes.
     */
    fun accept(host: String, encoded: String, owner: SummaryOwner?, attempt: Long): Boolean =
        synchronized(monitor) {
            val summary = WatchDashboardSummaryCodec.decode(encoded) ?: return false
            if (!isAllowedForBuild(summary) || attempts.claimed != attempt || unchanged(host, encoded)) return false
            val bound = binding()
            if (owner == null) {
                if (orderedRoute(host)) return false
            } else if (bound?.host == host && bound.owner?.installId == owner.installId &&
                owner.sequence < bound.owner.sequence
            ) {
                return false
            }
            val ordered = preferences.getStringSet(ORDERED_HOSTS_KEY, emptySet()).orEmpty()
            val previous = RECORD_KEYS.associateWith { preferences.all[it] }
            val committed = preferences.edit().run {
                putString(SUMMARY_KEY, encoded)
                putString(BOUND_HOST_KEY, host)
                if (owner == null) {
                    remove(BOUND_INSTALL_KEY)
                    remove(BOUND_GENERATION_KEY)
                    remove(BOUND_SEQUENCE_KEY)
                } else {
                    putString(BOUND_INSTALL_KEY, owner.installId)
                    putLong(BOUND_GENERATION_KEY, owner.generation)
                    putLong(BOUND_SEQUENCE_KEY, owner.sequence)
                    putStringSet(ORDERED_HOSTS_KEY, ordered + host)
                }
                commit()
            }
            if (!committed) restore(previous)
            committed
        }

    /** Best effort on disk; memory takes the previous record even when this commit fails too. */
    @Suppress("UNCHECKED_CAST")
    private fun restore(previous: Map<String, Any?>) {
        preferences.edit().run {
            for ((key, value) in previous) {
                when (value) {
                    null -> remove(key)
                    is String -> putString(key, value)
                    is Long -> putLong(key, value)
                    is Set<*> -> putStringSet(key, value as Set<String>)
                }
            }
            commit()
        }
    }

    private fun isAllowedForBuild(summary: WatchDashboardSummary): Boolean =
        debugBuild || summary.dataMode != WatchDataMode.MOCK

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
        const val BOUND_HOST_KEY = "boundHost"
        const val BOUND_INSTALL_KEY = "boundInstallId"
        const val BOUND_GENERATION_KEY = "boundGeneration"
        const val BOUND_SEQUENCE_KEY = "boundSequence"
        const val ORDERED_HOSTS_KEY = "orderedHosts"
        val RECORD_KEYS = listOf(
            SUMMARY_KEY, BOUND_HOST_KEY, BOUND_INSTALL_KEY, BOUND_GENERATION_KEY, BOUND_SEQUENCE_KEY,
            ORDERED_HOSTS_KEY,
        )

        /** Activity, listener and complication stores share one process. */
        val monitor = Any()
    }
}

private object WatchDashboardSummaryCodec {
    fun encode(summary: WatchDashboardSummary): String = summary.toJson().toString()

    /** Persisted and incoming reads alike: a v10 value must meet the closed ordered contract. */
    fun decode(encoded: String): WatchDashboardSummary? = try {
        val json = JSONObject(encoded)
        if (json.opt("schemaVersion") == SCHEMA_VERSION) {
            decodeOrdered(encoded)?.summary
        } else {
            json.toWatchDashboardSummary().takeIf { it.schemaVersion == LEGACY_SCHEMA_VERSION }
        }
    } catch (_: JSONException) {
        null
    } catch (_: RuntimeException) {
        null
    }

    fun decodeOrdered(encoded: String): OrderedSummary? = try {
        // One complete strict document: trailing content after the summary is malformed.
        val json = strictJsonObject(encoded)
        require(json.get("schemaVersion") == SCHEMA_VERSION)
        json.requireOrderedShape()
        OrderedSummary(json.toWatchDashboardSummary(), json.toSummaryOwner(), encoded)
    } catch (_: JSONException) {
        null
    } catch (_: RuntimeException) {
        null
    }
}

private fun JSONObject.toSummaryOwner(): SummaryOwner {
    val installId = get("installId")
    require(installId is String && INSTALL_ID_PATTERN.matches(installId))
    return SummaryOwner(
        installId = installId,
        generation = strictLong("generation").also { require(it >= 0L) },
        sequence = strictLong("sequence").also { require(it >= 1L) },
    )
}

/** A JSON integer, never a coerced string, float or boolean. */
private fun JSONObject.strictLong(key: String): Long = when (val value = get(key)) {
    is Int -> value.toLong()
    is Long -> value
    else -> throw IllegalArgumentException("$key is not an integer")
}

/**
 * v10 is a closed contract: exactly its members, required nullable ones included, each of its
 * JSON type and never coerced. Value rules (enums, patterns, periods) follow in the decoder.
 */
private fun JSONObject.requireOrderedShape() {
    requireMembers(ORDERED_MEMBERS, setOf(SELECTED_RING_DATA_UNAVAILABLE))
    requireTyped<String>("dataMode", "installId", "generatedAt", "overallStatus")
    requireTyped<Boolean>("isStale", "manualRefreshAllowed")
    if (has(SELECTED_RING_DATA_UNAVAILABLE)) requireTyped<Boolean>(SELECTED_RING_DATA_UNAVAILABLE)
    requireNullable<String>("manualRefreshAvailableAt")
    nullableTimestamp("manualRefreshAvailableAt")
    val rings = get("rings") as JSONArray
    require(rings.length() <= MAX_RINGS)
    rings.forEachObject { ring ->
        ring.requireMembers(setOf("id", "label", "usedPercent", "status", "spent", "limit", "split"))
        ring.requireTyped<String>("id", "label", "status")
        ring.requireTyped<Number>("usedPercent")
        ring.nullableMember("spent")?.requireMoneyShape()
        ring.nullableMember("limit")?.requireMoneyShape()
        ring.nullableMember("split")?.run {
            requireMembers(setOf("id", "label", "usedPercent", "status"))
            requireTyped<String>("id", "label", "status")
            requireTyped<Number>("usedPercent")
        }
    }
    nullableMember("creditsGlance")?.run {
        requireMembers(setOf("text", "label"), setOf("provider"))
        requireTyped<String>("text", "label")
        if (has("provider")) requireNullable<String>("provider")
    }
    (get("today") as JSONObject).requireBudgetShape()
    (get("week") as JSONObject).requireBudgetShape()
    (get("allowances") as JSONArray).forEachObject { allowance ->
        allowance.requireMembers(
            setOf("source", "label", "usedPercent", "remaining", "resetsAt", "status"),
            setOf("unlimited"),
        )
        allowance.requireTyped<String>("source", "label", "status")
        allowance.requireNullable<Number>("usedPercent")
        allowance.nullableValue<Number>("usedPercent")?.toDouble()?.let { require(it.isFinite() && it >= 0.0) }
        allowance.requireNullable<String>("resetsAt")
        allowance.nullableTimestamp("resetsAt")
        if (allowance.has("unlimited")) allowance.requireTyped<Boolean>("unlimited")
        allowance.nullableMember("remaining")?.run {
            requireMembers(setOf("value", "unit"))
            requireTyped<String>("value", "unit")
            require(QUANTITY_PATTERN.matches(getString("value")))
        }
    }
    (get("providers") as JSONArray).forEachObject { provider ->
        provider.requireMembers(setOf("provider", "status", "todaySpent"))
        provider.requireTyped<String>("provider", "status")
        provider.nullableMember("todaySpent")?.requireMoneyShape()
    }
    (get("alerts") as JSONArray).forEachObject { alert ->
        alert.requireMembers(setOf("severity", "message"))
        alert.requireTyped<String>("severity", "message")
    }
}

private fun JSONObject.requireBudgetShape() {
    requireMembers(setOf("period", "spent", "limit", "remaining", "usedPercent", "projectedTotal", "status"))
    requireTyped<String>("period", "status")
    requireNullable<Number>("usedPercent")
    for (key in listOf("spent", "limit", "remaining", "projectedTotal")) nullableMember(key)?.requireMoneyShape()
}

private fun JSONObject.requireMoneyShape() {
    requireMembers(setOf("minorUnits", "currency"))
    val minorUnits = get("minorUnits")
    require(minorUnits is Int || minorUnits is Long)
    requireTyped<String>("currency")
}

private fun JSONObject.requireMembers(required: Set<String>, optional: Set<String> = emptySet()) {
    val members = keys().asSequence().toSet()
    require(members.containsAll(required) && (required + optional).containsAll(members))
}

private inline fun <reified T> JSONObject.requireTyped(vararg keys: String) {
    for (key in keys) require(get(key) is T)
}

/** Present, and either JSON null or [T]; absence is a missing required member. */
private inline fun <reified T> JSONObject.requireNullable(key: String) {
    val value = get(key)
    require(JSONObject.NULL == value || value is T)
}

/** A present member that is JSON null or [T]; anything else is malformed. */
private inline fun <reified T> JSONObject.nullableValue(key: String): T? {
    val value = get(key)
    return if (JSONObject.NULL == value) null else value as T
}

/** A present member that is JSON null or a `date-time` instant, as `generatedAt` is read. */
private fun JSONObject.nullableTimestamp(key: String) {
    nullableValue<String>(key)?.let(Instant::parse)
}

/** A present member that is JSON null or an object; anything else is malformed. */
private fun JSONObject.nullableMember(key: String): JSONObject? {
    val value = get(key)
    return if (JSONObject.NULL == value) null else value as JSONObject
}

private inline fun JSONArray.forEachObject(action: (JSONObject) -> Unit) {
    for (index in 0 until length()) action(get(index) as JSONObject)
}

private fun WatchDashboardSummary.toJson() = JSONObject().apply {
    put("schemaVersion", schemaVersion)
    put("dataMode", dataMode.wireName)
    put("generatedAt", generatedAt)
    put("overallStatus", overallStatus.wireName)
    put("rings", JSONArray().apply { rings.forEach { put(it.toJson()) } })
    if (selectedRingDataUnavailable) {
        put(SELECTED_RING_DATA_UNAVAILABLE, true)
    }
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
    val schemaVersion = getInt("schemaVersion")
    require(schemaVersion == SCHEMA_VERSION || schemaVersion == LEGACY_SCHEMA_VERSION)
    val dataMode = requireNotNull(WatchDataMode.fromWireName(getString("dataMode")))
    // v9 has no product Demo; its projection of Demo is an empty Live summary.
    require(schemaVersion == SCHEMA_VERSION || dataMode != WatchDataMode.DEMO)
    val generatedAt = getString("generatedAt").also(Instant::parse)
    val today = getJSONObject("today").toPeriodSummary()
    val week = getJSONObject("week").toPeriodSummary()
    require(today.period == "today")
    require(week.period == "week")

    return WatchDashboardSummary(
        schemaVersion = schemaVersion,
        dataMode = dataMode,
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
        selectedRingDataUnavailable = optionalBoolean(SELECTED_RING_DATA_UNAVAILABLE),
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
    require(usedPercent.isFinite() && usedPercent >= 0.0)
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
    require(usedPercent.isFinite() && usedPercent >= 0.0)
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

/** Absent reads as false; a present value must be a JSON boolean, never a coerced string. */
private fun JSONObject.optionalBoolean(key: String): Boolean {
    if (!has(key)) {
        return false
    }
    val value = get(key)
    require(value is Boolean)
    return value
}

private inline fun <T> JSONArray.mapObjects(transform: (JSONObject) -> T): List<T> =
    List(length()) { index -> transform(getJSONObject(index)) }

private fun String.toPulseStatus(): PulseStatus = requireNotNull(PulseStatus.fromWireName(this))

// The v9 projection older watches read, then the ordered summary (`SCHEMA_VERSION`). The fixture
// validator matches each against its schema.
private const val LEGACY_SCHEMA_VERSION = 9
private const val SCHEMA_VERSION = 10
private val INSTALL_ID_PATTERN = Regex("^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$")
private val ORDERED_MEMBERS = setOf(
    "schemaVersion", "dataMode", "installId", "generation", "sequence", "generatedAt",
    "overallStatus", "rings", "creditsGlance", "today", "week", "allowances", "providers",
    "alerts", "isStale", "manualRefreshAllowed", "manualRefreshAvailableAt",
)
private val QUANTITY_PATTERN = Regex("^[0-9]+(?:\\.[0-9]+)?$")
private const val MAX_RINGS = 3
private const val SELECTED_RING_DATA_UNAVAILABLE = "selectedRingDataUnavailable"
private val CURRENCY_PATTERN = Regex("^[A-Z]{3}$")
private val PROVIDERS = setOf("openai", "codex", "claude", "cursor", "mock")
private val ALLOWANCE_SOURCES = setOf("plan", "purchased")
private val QUANTITY_UNITS = setOf("tokens", "credits")
private val ALERT_SEVERITIES = setOf("info", "warning", "error")
