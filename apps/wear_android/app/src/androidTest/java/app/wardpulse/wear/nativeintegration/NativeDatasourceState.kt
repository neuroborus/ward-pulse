package app.wardpulse.wear.nativeintegration

import android.app.Instrumentation
import android.content.ComponentName
import android.content.Context
import android.content.SharedPreferences
import app.wardpulse.wear.data.WatchSummaryStore
import app.wardpulse.wear.watchface.AndroidWatchFacePushClient
import java.io.File
import java.util.UUID
import org.json.JSONArray
import org.json.JSONObject

internal const val DELIVERY_CLASS = "app.wardpulse.wear.nativeintegration.NativeDatasourceTransitionTest"

internal data class NativeDeliveryTarget(val slot: Int, val systemId: Int, val provider: ComponentName)

internal data class NativeDeliveryMapping(val targets: List<NativeDeliveryTarget>, val scopeSha256: String)

/** Only existing packaged inputs reviewed for normal-service observation; never caller-supplied paths. */
internal val nativeDeliveryFixtureAssets = listOf(
    "n1_pair_zero_full", "n1_pair_full_zero", "n1_pair_both_zero", "n1_pair_tiny_near_full",
    "n1_pair_near_full_tiny", "n1_pair_below_above", "n1_pair_above_below",
    "n2_pairs_zero_tiny", "n2_pairs_tiny_zero", "n3_pairs_near_full", "n3_pairs_full_near",
    "n3_zero_tracks", "credits_only", "plan_credits", "n1_week_near_full", "n2_week_day", "n2_month_month",
).associate { "fixture-$it" to listOf("watch_dashboard_summary_$it.json") } + mapOf(
    "fixture-n3_reorder" to listOf("watch_dashboard_summary_n3_reorder_before.json",
        "watch_dashboard_summary_n3_reorder_after.json"),
)

internal fun nativeDeliveryAssets(scenario: String): List<String> {
    nativeDeliveryFixtureAssets[scenario]?.let { return it }
    nativeGuard(scenario in setOf("normal", "delayed", "obsolete", "recovery"), "delivery-scenario")
    return emptyList()
}

internal data class NativeDeliveryFixture(val asset: String, val sha256: String, val encoded: String)

/** Validate every selected byte/hash before any case, lease, publication or provider effect. */
internal fun readNativeDeliveryFixtures(scenario: String, expected: NativePushExpectations, debug: Boolean,
    read: (String) -> ByteArray): List<NativeDeliveryFixture> {
    val assets = nativeDeliveryAssets(scenario)
    requireNativeDatasourceMutation(expected, "observeDelivery:$scenario")
    if (assets.isEmpty()) return emptyList()
    nativeGuard(debug, "debug-fixture-delivery")
    val hashes = listOf(expected.hash("expectedFixtureSha256")) +
        if (assets.size == 2) listOf(expected.hash("expectedReorderAfterSha256")) else emptyList()
    return assets.zip(hashes).map { (asset, hash) ->
        val bytes = read(asset)
        nativeGuard(bytes.inputStream().sha256() == hash, "delivery-fixture-sha256")
        val encoded = bytes.toString(Charsets.UTF_8)
        nativeGuard(encoded.toByteArray(Charsets.UTF_8).contentEquals(bytes), "delivery-fixture-utf8")
        NativeDeliveryFixture(asset, hash, encoded)
    }
}

internal fun requireNativeDeliveryCase(root: File, scenario: String): File {
    nativeDeliveryAssets(scenario)
    return File(root, scenario).also { nativeGuard(!it.exists(), "single-delivery-case") }
}

/** Global case history is independent of the selected first-read probe. */
internal fun requireNativePriorDeliveryRecovery(root: File, expected: NativePushExpectations) {
    val latest = AttemptJournal(File(root, "latest.json"))
    if (!latest.exists()) return
    val scenario = latest.read().getString("case")
    val sdk = scenario in nativeSdkDirectScenarios.map { "sdk-$it" }
    if (!sdk) nativeDeliveryAssets(scenario)
    val file = File(root, "$scenario/receipt.json")
    val receipt = AttemptJournal(file).read()
    if (sdk) {
        nativeGuard(receipt.optString("kind") == "sdk-direct-data", "prior-sdk-direct-case")
        // Constructor rejection still needs exact review, but has no dispatch/recovery to observe.
        if (!receipt.optBoolean("directArmed") && receipt.optString("construction") ==
            "SDK rejected; no dispatch or renderer effect established") {
            nativeGuard(expected.required("priorDeliveryRestorationReview") == "complete" &&
                file.inputStream().sha256() == expected.hash("expectedPriorDeliveryRestorationSha256"),
                "prior-sdk-direct-rejection-unreviewed")
            return
        }
        nativeGuard(receipt.optBoolean("directArmed"), "prior-sdk-direct-arm-unresolved")
    }
    nativeGuard(receipt.optString("cleanupRequest") == "normal requestUpdate returned; effective restoration Pending" &&
        receipt.optString("laterRestoration") == "recorded; original-frame inspection and response provenance Pending" &&
        expected.required("priorDeliveryRestorationReview") == "complete" &&
        file.inputStream().sha256() == expected.hash("expectedPriorDeliveryRestorationSha256"),
        "prior-delivery-recovery-unresolved")
}

/** Shared client/direct-data fence: requests and immediate cleanup are not reviewed recovery. */
internal fun requireNativeNormalRecovery(context: Context, expected: NativePushExpectations,
    mapping: NativeDeliveryMapping) {
    nativeGuard(expected.required("normalRestorationReview") == "complete", "normal-restoration-review")
    val scenario = expected.required("normalRestorationScenario")
    nativeGuard(scenario in setOf("normal", "delayed", "obsolete", "recovery"), "normal-restoration-scenario")
    val file = File(context.filesDir, "native_datasource/$scenario/receipt.json")
    nativeGuard(file.inputStream().sha256() == expected.hash("expectedNormalRestorationReceiptSha256"),
        "reviewed-normal-restoration")
    val receipt = AttemptJournal(file).read()
    nativeGuard(receipt.optString("laterRestoration") ==
        "recorded; original-frame inspection and response provenance Pending" &&
        receipt.optString("mappingSha256") == mapping.targets.fingerprint() &&
        receipt.optString("scopeSha256") == mapping.scopeSha256 &&
        receipt.optString("cleanupRequest") == "normal requestUpdate returned; effective restoration Pending" &&
        receipt.optString("restoration") in setOf("original bytes observed", "original bytes restored"),
        "normal-restoration-support")
    nativeGuard(WatchSummaryStore(context).load() != null, "restorable-normal-data")
}

/** Current owned-Push scope is relevant only when that package is the active resource. */
internal fun readNativeDatasourcePushScope(renderer: NativeRenderer, resourceVersion: Long,
    expected: NativePushExpectations, observe: () -> JSONObject): JSONObject? {
    if (renderer.resourcePackage != CANDIDATE_PACKAGE) return null
    val receipt = observe()
    nativeGuard(receipt.optString("metadataOutcome") == NativeReadOutcome.ACQUIRED.value &&
        receipt.optBoolean("inventoryStable"), "datasource-owned-push-inventory")
    val owned = receipt.optJSONObject("ownedPush") ?: throw NativePending("datasource-push-ownership-unavailable")
    nativeGuard(owned.getString("packageName") == renderer.resourcePackage &&
        owned.getLong("versionCode") == resourceVersion &&
        owned.getString("managerSlotId").sha256() == expected.hash("expectedSlotSha256") &&
        receipt.optBoolean("active"), "datasource-current-owned-push")
    return JSONObject().put("ownedPush", owned).put("active", true)
        .put("configurationSha256", renderer.configuration.sha256())
}

/** Read receipts, manager inventory and peer observations cannot supply this authorization. */
internal fun requireNativeDatasourceMutation(expected: NativePushExpectations, operation: String) {
    nativeGuard(expected.required("authorizedOperation") == operation, "datasource-exact-operation-authorization")
}

/** Compare the entire selected scope, including explicit nulls, types and controller row IDs. */
internal fun requireNativeDeliveryScope(current: NativeRenderer, before: NativeRenderer) {
    for (renderer in listOf(before, current)) {
        val selected = renderer.selections ?: throw NativePending("requester-selections-unavailable")
        val slots = (11..18).toSet()
        nativeGuard(renderer.enabled.keys == slots && selected.providers.keys == slots &&
            selected.configuredTypes.keys == slots && selected.rowIds.keys == slots &&
            selected.rowIds.values.all { it.toIntOrNull()?.let { id -> id >= 0 } == true } &&
            selected.rowIds.values.map { it.toIntOrNull() }.toSet().size == slots.size && renderer.runtime.isNotBlank() &&
            renderer.nativeScope.isNotEmpty() &&
            selected.resourcePackage == renderer.resourcePackage && selected.instance == renderer.instance,
            "requester-complete-eight-scope")
    }
    nativeGuard(current.resourcePackage == before.resourcePackage && current.instance == before.instance &&
        current.runtime == before.runtime && current.nativeScope == before.nativeScope &&
        current.userStyle == before.userStyle && current.enabled == before.enabled &&
        current.selections == before.selections, "requester-scope-changed")
}

/** Typed system/slot/resource domains must all join the actual complete controller/native chain. */
internal fun discoverDeliveryTargets(configs: List<NativeTypedConfig>, before: NativeRenderer,
    after: NativeRenderer): List<NativeDeliveryTarget> {
    requireNativeDeliveryScope(after, before)
    val selections = checkNotNull(after.selections)
    val selected = selections.providers.filter { (slot, provider) ->
        after.enabled[slot] == true && provider?.let(ComponentName::unflattenFromString)?.packageName == HOST_PACKAGE
    }
    nativeGuard(selected.isNotEmpty(), "selected-own-providers")
    nativeGuard(configs.size == selected.size && configs.map { it.id }.toSet().size == configs.size &&
        configs.map { it.watchFaceSlotId }.toSet() == selected.keys, "complete-typed-requester-mapping")
    return configs.map { config ->
        val slot = config.watchFaceSlotId
        val provider = config.provider ?: throw NativePending("typed-provider-unresolved")
        nativeGuard(provider.packageName == HOST_PACKAGE &&
            provider == selected[slot]?.let(ComponentName::unflattenFromString) &&
            config.id >= 0 && config.id.toString() == selections.rowIds[slot] &&
            config.dataType == selections.configuredTypes[slot] &&
            config.watchFacePackage == after.resourcePackage && config.watchFaceClass == null,
            "typed-requester-domain-association")
        NativeDeliveryTarget(slot, config.id, provider)
    }.sortedBy { it.slot }
}

/** Fresh read evidence only. Callers retain separate operation authorization and dispatch custody. */
internal fun readNativeDeliveryTargets(instrumentation: Instrumentation, expected: NativePushExpectations,
    intended: NativeRenderer): NativeDeliveryMapping {
    val context = instrumentation.targetContext
    val device = NativePushDevice(instrumentation)
    val admission = NativeReadAdmission(instrumentation, expected)
    val directory = File(context.filesDir, "native_read/requester-${UUID.randomUUID()}")
    nativeGuard(directory.mkdirs(), "fresh-private-requester-receipt")
    val receipt = nativeTypedConfigReceipt().put("kind", "requester-mapping-evidence")
    val journal = AttemptJournal(File(directory, "receipt.json"))
    val persist = { journal.persist(receipt) }
    fun <T> operation(name: String, domain: String, action: () -> T) =
        nativeClientOperation(receipt, persist, name, "current target UID/native scope", domain, action)
    fun system() = NativeSystem.parse(device.shell("am get-current-user"), device.shell("dumpsys wallpaper"))
    fun resource(name: String) = operation(name, "resource/runtime APK and signer identities") {
        admission.resourceIdentity(intended.resourcePackage) { part, read ->
            operation("$name$part", "installed package identity", read)
        }.also { receipt.put(name, it) }
    }
    fun ownedPush(name: String, renderer: NativeRenderer, resources: JSONObject): JSONObject? {
        if (renderer.resourcePackage != CANDIDATE_PACKAGE) {
            receipt.put("${name}Scope", JSONObject.NULL)
            return null
        }
        return operation(name, "current caller-owned Push package/version/manager-slot/active/configuration scope") {
            readNativeDatasourcePushScope(renderer, resources.getJSONObject("resource").getLong("code"), expected) {
                val inventory = nativeInventoryReceipt(NativeInventoryRead.PUSH)
                receipt.put(name, inventory)
                readNativeOwnedPush(inventory, persist, AndroidWatchFacePushClient(context))
                inventory
            }.also { receipt.put("${name}Scope", it ?: JSONObject.NULL) }
        }
    }
    fun face(name: String) = operation(name, "full-eight controller/favorite/facade/native chain") {
        device.readRenderer(expected).also { renderer ->
            val selections = renderer.selections ?: throw NativePending("requester-selections-unavailable")
            receipt.put(name, JSONObject().put("resourcePackage", renderer.resourcePackage)
                .put("instance", renderer.instance).put("runtime", renderer.runtime)
                .put("nativeScope", JSONArray(renderer.nativeScope)).put("userStyleSha256", renderer.userStyle.sha256())
                .put("selections", JSONArray(renderer.enabled.toSortedMap().map { (slot, enabled) ->
                    JSONObject().put("slot", slot).put("enabled", enabled).put("rowId", selections.rowIds[slot])
                        .put("provider", selections.providers[slot] ?: JSONObject.NULL)
                        .put("configuredType", selections.configuredTypes[slot])
                })))
        }
    }
    try {
        val identity = operation("beforeIdentity", "caller UID/package/APK/signer") {
            admission.currentIdentity().also { receipt.put("beforeIdentity", it) }
        }
        val beforeSystem = operation("beforeSystem", "current user/display/runtime connection") {
            system().also { receipt.put("beforeSystemSha256", it.toString().sha256()) }
        }
        val before = face("beforeFace")
        requireNativeDeliveryScope(before, intended)
        val resources = resource("beforeResource")
        val pushScope = ownedPush("beforeOwnedPush", before, resources)
        var configs: List<NativeTypedConfig>? = null
        var failure: Throwable? = null
        try { configs = readNativeTypedConfigs(context, receipt, persist) }
        catch (caught: Throwable) { failure = caught }
        // Preserve raw producer outcomes even when a later bracket fails; attempt each independent read.
        fun <T> afterRead(action: () -> T): T? = try { action() } catch (caught: Throwable) {
            if (failure == null) failure = caught else failure!!.addSuppressed(caught)
            null
        }
        val after = afterRead { face("afterFace") }
        val afterSystem = afterRead { operation("afterSystem", "current user/display/runtime connection") {
            system().also { receipt.put("afterSystemSha256", it.toString().sha256()) }
        } }
        val afterIdentity = afterRead { operation("afterIdentity", "caller UID/package/APK/signer") {
            admission.currentIdentity().also { receipt.put("afterIdentity", it) }
        } }
        val afterResources = afterRead { resource("afterResource") }
        val afterPushScope = afterRead {
            ownedPush("afterOwnedPush", after ?: throw NativePending("requester-after-face-unavailable"),
                afterResources ?: throw NativePending("requester-after-resource-unavailable"))
        }
        return operation("association", "fresh typed/controller/native join; no mutation authority") {
            receipt.put("stableBracket", false)
            failure?.let { throw it }
            val current = after ?: throw NativePending("requester-after-face-unavailable")
            requireNativeDeliveryScope(current, before)
            nativeGuard(afterSystem == beforeSystem && afterIdentity?.toString() == identity.toString() &&
                afterResources?.toString() == resources.toString() && afterPushScope?.toString() == pushScope?.toString(),
                "requester-identity-bracket-changed")
            receipt.put("stableBracket", true)
            val targets = discoverDeliveryTargets(checkNotNull(configs), before, current)
            val scope = JSONObject().put("identity", identity).put("resources", resources)
                .put("face", receipt.getJSONObject("beforeFace")).put("push", pushScope ?: JSONObject.NULL)
                .put("systemScopeSha256", beforeSystem.toString().sha256())
            val mapping = NativeDeliveryMapping(targets, scope.toString().sha256())
            receipt.put("activeFaceAssociation", "validated typed/controller/native scope; no mutation authority")
                .put("scopeSha256", mapping.scopeSha256)
            persist()
            mapping
        }
    } catch (failure: Throwable) {
        receipt.put("mappingOutcome", nativeReadFailure(failure).value)
        try { persist() } catch (recording: Throwable) { failure.addSuppressed(recording) }
        throw failure
    }
}

/** One dispatch per provider, durably armed and freshly validated. Recovery attempts independent groups. */
internal fun requestNativeDelivery(intended: List<NativeDeliveryTarget>, selected: List<NativeDeliveryTarget>,
    calls: JSONArray, persist: () -> Unit, validate: () -> List<NativeDeliveryTarget>,
    recovery: Boolean = false, request: (ComponentName, IntArray) -> Unit) {
    nativeGuard(selected.isNotEmpty() && selected.distinct().size == selected.size &&
        selected.all { it in intended } && intended.map { it.systemId }.distinct().size == intended.size,
        "bounded-request-targets")
    var failure: Throwable? = null
    selected.groupBy { it.provider }.forEach { (provider, rows) ->
        val call = JSONObject().put("providerSha256", provider.flattenToString().sha256())
            .put("systemIds", JSONArray(rows.map { it.systemId })).put("state", "validation Pending; no dispatch")
        try {
            nativeGuard((0 until calls.length()).none {
                calls.getJSONObject(it).getString("providerSha256") == provider.flattenToString().sha256()
            }, "single-provider-dispatch")
            calls.put(call)
            call.put("state", "armed; dispatch uncertain")
            persist() // Never dispatch from finally: failed durable arming forbids this call.
            nativeGuard(validate() == intended, "fresh-intended-request-targets")
            request(provider, rows.map { it.systemId }.toIntArray())
            call.put("state", "requestUpdate returned; delivery Pending")
            persist()
        } catch (caught: Throwable) {
            call.put("failureOutcome", nativeReadFailure(caught).value)
            try { persist() } catch (recording: Throwable) { caught.addSuppressed(recording) }
            if (!recovery) throw caught
            if (failure == null) failure = caught else failure!!.addSuppressed(caught)
        }
    }
    failure?.let { throw it }
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
    private var armedPublication: JSONObject? = null
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
    fun armPublication(encoded: String) {
        nativeGuard(!closed && armedPublication == null, "single-armed-publication")
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
        armedPublication = publication
    }

    fun publish(encoded: String) {
        nativeGuard(!closed, "open-summary-lease")
        if (armedPublication == null) armPublication(encoded)
        val publication = checkNotNull(armedPublication)
        nativeGuard(publication.getString("sha256") == encoded.sha256(), "armed-publication-bytes")
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
        armedPublication = null
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
