package app.wardpulse.wear.nativeintegration

import android.content.ComponentName
import android.content.SharedPreferences
import app.wardpulse.wear.data.WatchSummaryStore
import java.io.File
import org.json.JSONObject

internal const val DELIVERY_CLASS = "app.wardpulse.wear.nativeintegration.NativeDatasourceTransitionTest"

internal data class NativeDeliveryTarget(val slot: Int, val systemId: Int, val provider: ComponentName)

/** Requires explicit system-manager mappings; renderer slot IDs alone cannot authorize a request. */
internal fun discoverDeliveryTargets(record: String, component: ComponentName,
    renderer: NativeRenderer): List<NativeDeliveryTarget> {
    val selections = checkNotNull(renderer.selections)
    val selected = selections.providers.filter { (slot, provider) ->
        renderer.enabled[slot] == true && provider?.startsWith("$HOST_PACKAGE/") == true
    }
    nativeGuard(selected.isNotEmpty(), "selected-own-providers")
    // Accept only explicit, co-located fields in an applicable system record. No canonical-ID,
    // list-position, cached-dataSource or default-policy fallback exists. Unexposed fields stay Pending.
    val rows = record.lineSequence().mapNotNull { line ->
        fun field(name: String) = Regex("(?:^|[\\s,{])$name=(ComponentInfo\\{[^}]+\\}|[^,\\s}]+)")
            .findAll(line).toList().singleOrNull()?.groupValues?.get(1)
        fun source(name: String) = field(name)?.removePrefix("ComponentInfo{")?.removeSuffix("}")
            ?.let(ComponentName::unflattenFromString)
        if (source("watchFaceComponent") != component ||
            field("watchFaceInstanceId") != renderer.instance) return@mapNotNull null
        val slot = field("watchFaceComplicationId")?.toIntOrNull() ?: return@mapNotNull null
        if (slot !in selected) return@mapNotNull null
        val systemId = field("complicationInstanceId")?.toIntOrNull()
            ?: throw NativePending("system-instance-id-unavailable")
        nativeGuard(systemId >= 0 && source("providerComponent") ==
            ComponentName.unflattenFromString(selected.getValue(slot)!!), "system-provider-mapping")
        NativeDeliveryTarget(slot, systemId, checkNotNull(ComponentName.unflattenFromString(selected.getValue(slot)!!)))
    }.toList()
    nativeGuard(rows.size == selected.size && rows.map { it.slot }.toSet() == selected.keys &&
        rows.map { it.systemId }.distinct().size == rows.size, "complete-system-instance-mapping")
    return rows.sortedBy { it.slot }
}

internal fun List<NativeDeliveryTarget>.fingerprint() = joinToString("\n") {
    "${it.slot}|${it.systemId}|${it.provider.flattenToString()}"
}.sha256()

/** Raw originals and reconciliation bytes never leave this app-private directory. */
internal class NativeSummaryLease(
    private val preferences: SharedPreferences,
    private val directory: File,
    private val receipt: JSONObject,
    private val persistReceipt: (JSONObject) -> Unit =
        AttemptJournal(File(directory, "receipt.json"))::persist,
) {
    private val store = WatchSummaryStore(preferences)
    private val original = preferences.getString("latest", null)
    private var owned: String? = null
    private val issued = linkedSetOf<String>()
    private var foreignWrite = false
    private var foreignValue: String? = null
    private var restoring = false
    private var closed = false
    private val listener = SharedPreferences.OnSharedPreferenceChangeListener { _, key ->
        if (!closed && key == "latest") {
            val current = preferences.getString("latest", null)
            if (current != (owned ?: original) && !(restoring && current == original)) {
                foreignWrite = true
                foreignValue = current
            }
        }
    }

    init {
        nativeGuard(directory.mkdir(), "fresh-private-recovery-directory")
        privateValue("original", original)
        receipt.put("originalPresent", original != null).put("restoration", "Pending")
        persistReceipt(receipt)
        preferences.registerOnSharedPreferenceChangeListener(listener)
    }

    // All lease operations and preference callbacks use the main thread. Production writers are
    // not locked by this test: HOST must establish quiet writers, and every changed value stops it.
    fun publish(encoded: String) {
        nativeGuard(!foreignWrite && preferences.getString("latest", null) == (owned ?: original),
            "quiet-summary-writer")
        nativeGuard(store.load() != null || original == null, "restorable-original-summary")
        val publication = JSONObject().put("sha256", encoded.sha256()).put("state", "armed; acceptance Pending")
        privateValue("owned-${issued.size}", encoded)
        val publications = receipt.optJSONArray("publications") ?: org.json.JSONArray().also {
            receipt.put("publications", it)
        }
        publications.put(publication)
        receipt.put("publication", "armed; acceptance Pending").put("ownedSha256", encoded.sha256())
        persistReceipt(receipt)
        // A background publication during persistence can precede its queued main-thread notification.
        nativeGuard(!foreignWrite && preferences.getString("latest", null) == (owned ?: original),
            "quiet-summary-writer")
        issued += encoded
        owned = encoded
        nativeGuard(store.saveEncoded(encoded), "normal-store-acceptance")
        nativeGuard(preferences.edit().commit() && preferences.getString("latest", null) == encoded &&
            store.load() != null && !foreignWrite, "accepted-summary-persistence")
        receipt.put("publication", "accepted by normal store; delivery Pending")
        publication.put("state", "accepted by normal store; delivery Pending")
        persistReceipt(receipt)
    }

    fun requireOwned() = nativeGuard(!foreignWrite &&
        preferences.getString("latest", null) == (owned ?: original), "summary-producer-interference")

    fun close(quietWriter: Boolean) {
        if (closed) return
        try {
            if (foreignWrite) privateValue("concurrent", foreignValue)
            val current = preferences.getString("latest", null)
            when {
                current == original -> receipt.put("restoration", "original bytes observed")
                current == null || current !in issued -> {
                    privateValue("newer", current)
                    receipt.put("restoration", "newer producer value preserved; reconciliation Pending")
                }
                foreignWrite || !quietWriter -> receipt.put("restoration", "writers unresolved; private reconciliation Pending")
                else -> {
                    // Compare immediately before restoration; never restore a snapshot over a newer value.
                    nativeGuard(preferences.getString("latest", null) == current, "restore-summary-changed")
                    restoring = true
                    val accepted = if (original == null) preferences.edit().remove("latest").commit()
                        else store.saveEncoded(original) && preferences.edit().commit()
                    nativeGuard(accepted, "restore-normal-summary")
                    val restored = preferences.getString("latest", null)
                    if (restored == original) receipt.put("restoration", "original bytes restored")
                    else {
                        privateValue("newer", restored)
                        receipt.put("restoration", "producer changed during cleanup; reconciliation Pending")
                    }
                }
            }
        } finally {
            closed = true
            preferences.unregisterOnSharedPreferenceChangeListener(listener)
            persistReceipt(receipt)
        }
    }

    private fun privateValue(name: String, value: String?) {
        // A marker distinguishes an absent key from a present empty string without decoding originals.
        val file = File(directory, "$name.bin")
        file.outputStream().use { output ->
            output.write(if (value == null) 0 else 1)
            if (value != null) output.write(value.toByteArray(Charsets.UTF_8))
            output.flush()
            output.fd.sync()
        }
    }
}

/** Minimal sanitized summaries, passed through the production decoder without changing its rules. */
internal fun deliverySummary(pair: Boolean, generatedAt: String): String {
    fun half(id: String, used: Int) = JSONObject().put("id", id).put("label", "Plan")
        .put("usedPercent", used).put("status", "ok")
    fun ring(id: String, used: Int) = half(id, used).put("spent", JSONObject.NULL)
        .put("limit", JSONObject.NULL).put("split", JSONObject.NULL)
    fun period(name: String) = JSONObject().put("period", name).put("status", "unknown")
        .put("spent", JSONObject.NULL).put("limit", JSONObject.NULL).put("remaining", JSONObject.NULL)
        .put("usedPercent", JSONObject.NULL).put("projectedTotal", JSONObject.NULL)
    val rings = org.json.JSONArray().put(ring("allowance.codex.week", if (pair) 63 else 20))
    if (pair) rings.put(ring("allowance.cursor.cursor-plan-models", 30)
        .put("split", half("allowance.cursor.cursor-plan-other", 50)))
    return JSONObject().put("schemaVersion", 9).put("dataMode", "live").put("generatedAt", generatedAt)
        .put("overallStatus", "ok").put("rings", rings).put("creditsGlance", JSONObject.NULL)
        .put("today", period("today"))
        .put("week", period("week")).put("allowances", org.json.JSONArray())
        .put("providers", org.json.JSONArray()).put("alerts", org.json.JSONArray())
        .put("isStale", false).put("manualRefreshAllowed", false)
        .put("manualRefreshAvailableAt", JSONObject.NULL).toString()
}
