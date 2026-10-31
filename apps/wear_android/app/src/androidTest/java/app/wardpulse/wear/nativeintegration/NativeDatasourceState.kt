package app.wardpulse.wear.nativeintegration

import android.app.Instrumentation
import android.content.ComponentName
import android.content.Context
import android.content.SharedPreferences
import android.graphics.BitmapFactory
import app.wardpulse.wear.data.WatchSummaryStore
import app.wardpulse.wear.watchface.AndroidWatchFacePushClient
import java.io.File
import java.util.UUID
import java.util.concurrent.TimeoutException
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

/** A reviewed production-XML change, never a fresh probe or APK, qualifies this separate case. */
internal fun readNativeRetainedExtraAdmission(root: File, expected: NativePushExpectations,
    renderer: NativeRenderer, mapping: NativeDeliveryMapping,
    installed: () -> Pair<NativePackage, String>): JSONObject {
    val file = File(root, "retained-extra-admission.json")
    val admission = readNativeReviewedRecord(file, expected.hash("expectedRetainedExtraAdmissionSha256"))
    nativeGuard(admission.getString("kind") == "retained-extra-production-payload" &&
        admission.getString("scenario") == "delayed", "retained-extra-admission-kind")
    val baseline = admission.getJSONObject("baseline")
    val candidate = admission.getJSONObject("candidate")
    fun hash(record: JSONObject, key: String) = record.optString(key).also {
        nativeGuard(it.matches(Regex("[a-f0-9]{64}")), "retained-extra-provenance-hash")
    }
    for (artifact in listOf(baseline, candidate)) {
        hash(artifact, "sourceSha256")
        val payload = hash(artifact, "generatedXmlSha256")
        nativeGuard(hash(artifact, "builtXmlSha256") == payload &&
            hash(artifact, "installedXmlSha256") == payload &&
            hash(artifact, "builtApkSha256") == hash(artifact, "resourceApkSha256"),
            "retained-extra-artifact-join")
        listOf("instanceSha256", "configurationSha256", "scopeSha256").forEach { hash(artifact, it) }
    }
    val original = readNativeReviewedRecord(File(root, "delayed/receipt.json"), hash(baseline, "receiptSha256"))
    nativeGuard(original.getString("scenario") == "delayed" &&
        original.getString("scopeSha256") == baseline.getString("scopeSha256") &&
        original.optString("cleanupRequest") == "normal requestUpdate returned; effective restoration Pending" &&
        original.optString("laterRestoration") == "recorded; original-frame inspection and response provenance Pending",
        "retained-extra-baseline-recovery")
    nativeGuard(candidate.getString("generatedXmlSha256") != baseline.getString("generatedXmlSha256") &&
        candidate.getString("sourceSha256") != baseline.getString("sourceSha256"),
        "retained-extra-production-change")
    nativeGuard(candidate.getString("resourcePackage") == renderer.resourcePackage &&
        baseline.getString("resourcePackage") in setOf(CANDIDATE_PACKAGE, "app.wardpulse.watchface") &&
        candidate.getString("instanceSha256") == renderer.instance.sha256() &&
        candidate.getString("configurationSha256") == renderer.configuration.sha256() &&
        candidate.getString("scopeSha256") == mapping.scopeSha256, "retained-extra-active-join")
    val (resource, payload) = installed()
    nativeGuard(resource.apk == candidate.getString("resourceApkSha256") &&
        resource.apk == expected.hash("expectedResourceApkSha256") &&
        resource.signer == expected.hash("expectedResourceSignerSha256") &&
        payload == candidate.getString("generatedXmlSha256"), "retained-extra-installed-join")
    return admission
}

/** No AtomicFile recovery may silently alter owner-reviewed immutable provenance. */
private fun readNativeReviewedRecord(file: File, sha256: String): JSONObject {
    nativeGuard(file.isFile && listOf(".bak", ".new").none { File("${file.path}$it").exists() },
        "retained-extra-record-unavailable")
    val bytes = file.readBytes()
    nativeGuard(bytes.inputStream().sha256() == sha256, "retained-extra-reviewed-record")
    return JSONObject(bytes.toString(Charsets.UTF_8))
}

internal fun nativeRetainedExtraCase(admission: JSONObject): String =
    "delayed-payload-${admission.getJSONObject("candidate").getString("generatedXmlSha256")}".also {
        nativeGuard(it.matches(Regex("delayed-payload-[a-f0-9]{64}")), "retained-extra-case")
    }

/** Resolve original recovery paths unchanged; candidate paths must carry their real payload identity. */
internal fun nativeDeliveryReceipt(root: File, name: String): File {
    if (name.matches(Regex("delayed-payload-[a-f0-9]{64}"))) {
        val file = File(root, "$name/receipt.json")
        nativeGuard(AttemptJournal(file).exists(), "retained-extra-reservation-unresolved")
        val receipt = AttemptJournal(file).read()
        nativeGuard(receipt.optString("scenario") == "delayed" &&
            receipt.optString("productionXmlSha256") == name.removePrefix("delayed-payload-") &&
            receipt.optString("candidateAdmissionSha256").matches(Regex("[a-f0-9]{64}")),
            "retained-extra-receipt-identity")
        return file
    }
    if (name !in nativeSdkDirectScenarios.map { "sdk-$it" }) nativeDeliveryAssets(name)
    return File(root, "$name/receipt.json")
}

/** Arm global recovery first: a partial reservation blocks subsequent effects, even for another payload. */
internal fun reserveNativeRetainedExtraCase(root: File, name: String, receipt: JSONObject): File {
    nativeGuard(name == "delayed-payload-${receipt.getString("productionXmlSha256")}" &&
        name.matches(Regex("delayed-payload-[a-f0-9]{64}")), "retained-extra-reservation-identity")
    val directory = File(root, name)
    nativeGuard(!directory.exists(), "single-retained-extra-payload")
    AttemptJournal(File(root, "latest.json")).persist(JSONObject().put("case", name))
    nativeGuard(directory.mkdir(), "fresh-retained-extra-reservation")
    receipt.put("reservation", "armed; acceptance Pending")
    AttemptJournal(File(directory, "receipt.json")).persist(receipt)
    return directory
}

/** Global case history is independent of the selected first-read probe. */
internal fun requireNativePriorDeliveryRecovery(root: File, expected: NativePushExpectations) {
    val latest = AttemptJournal(File(root, "latest.json"))
    if (!latest.exists()) return
    val scenario = latest.read().getString("case")
    val sdk = scenario in nativeSdkDirectScenarios.map { "sdk-$it" }
    val file = nativeDeliveryReceipt(root, scenario)
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
    val root = File(context.filesDir, "native_datasource")
    val latest = AttemptJournal(File(root, "latest.json"))
    if (latest.exists() && latest.read().optString("case").startsWith("delayed-payload-")) {
        // A client/direct route must not bypass an unresolved candidate using an older normal receipt.
        requireNativePriorDeliveryRecovery(root, expected)
    }
    nativeGuard(expected.required("normalRestorationReview") == "complete", "normal-restoration-review")
    val scenario = expected.required("normalRestorationScenario")
    nativeGuard(scenario in setOf("normal", "delayed", "obsolete", "recovery") ||
        scenario.matches(Regex("delayed-payload-[a-f0-9]{64}")), "normal-restoration-scenario")
    val file = nativeDeliveryReceipt(root, scenario)
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

/** Selected events and independently acquired originals are separate evidence, never a paint ACK. */
internal fun observeNativeDeliveryStage(directory: File, name: String, intended: List<NativeDeliveryTarget>,
    selected: List<NativeDeliveryTarget>, scope: NativeDatasourceProbeScope, receipt: JSONObject,
    fixture: NativeDeliveryFixture? = null, persist: () -> Unit, validate: () -> NativeDatasourceProbeScope,
    awaitEvent: (() -> Unit) -> Unit, request: (ComponentName, IntArray) -> Unit,
    capture: (String, Boolean) -> Unit): JSONObject {
    val entry = scope.json().put("stage", name).put("request", "armed; dispatch Pending")
        .put("acceptedSummarySha256", receipt.getString("ownedSha256")).put("calls", JSONArray())
        .put("targets", JSONArray(selected.map { row -> JSONObject().put("slot", row.slot)
            .put("systemId", row.systemId).put("providerSha256", row.provider.flattenToString().sha256()) }))
        .put("eventWaitMillis", 5_000).put("event", "Pending; selected runtime content event unrecorded")
        .put("observation", "Pending").put("responseProvenance", "Pending").put("visualAcceptance", "Pending")
    fixture?.let { entry.put("asset", it.asset).put("fixtureSha256", it.sha256) }
    receipt.getJSONArray("events").put(entry)
    var substage = "scope"
    fun current() = nativeGuard(validate() == scope, "delivery-stage-current-scope")
    fun original(label: String, order: String): JSONObject {
        fun file(suffix: String) = File(directory, "$label.$suffix").also {
            nativeGuard(it.isFile && it.length() > 0 &&
                it.canonicalFile == File(directory.canonicalFile, "$label.$suffix") &&
                !File("${it.path}.bak").exists() && !File("${it.path}.new").exists(),
                "complete-delivery-stage-original")
        }
        val frame = file("png")
        val dimensions = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeFile(frame.path, dimensions)
        nativeGuard(dimensions.outWidth > 0 && dimensions.outHeight > 0 && dimensions.outMimeType == "image/png",
            "delivery-stage-original-png")
        val record = file("json")
        val bytes = record.readBytes()
        val metadata = JSONObject(bytes.toString(Charsets.UTF_8))
        nativeGuard(metadata.opt("instanceSha256") == scope.instanceSha256 &&
            metadata.opt("configurationSha256") == scope.configurationSha256 &&
            metadata.opt("nativeRecordAcquired") == order && metadata.optJSONObject("effectiveData") != null &&
            metadata.opt("responseProvenance") == "Pending" && metadata.opt("visualAcceptance") == "Pending",
            "delivery-stage-native-record-scope")
        entry.put(if (order == "after frame") "requestedOriginal" else "boundedOriginal", JSONObject()
            .put("frame", frame.name).put("frameSha256", frame.inputStream().sha256())
            .put("nativeRecord", record.name).put("nativeRecordSha256", bytes.inputStream().sha256()))
        return metadata
    }
    try {
        nativeGuard(receipt.optString("publication") == "accepted by normal store; delivery Pending" &&
            (fixture == null || fixture.sha256 == fixture.encoded.sha256() &&
                fixture.sha256 == entry.getString("acceptedSummarySha256")), "delivery-stage-accepted-input")
        current()
        persist()
        var actionFailure: Throwable? = null
        var actionCompleted = false
        try {
            awaitEvent {
                try {
                    substage = "request"
                    requestNativeDelivery(intended, selected, entry.getJSONArray("calls"), persist, {
                        current()
                        intended
                    }, request = request)
                    entry.put("request", "requestUpdate returned; response Pending")
                    persist()
                    substage = "requested-original"
                    capture("$name-requested", false)
                    current()
                    actionCompleted = true
                    substage = "event-wait"
                } catch (caught: Throwable) {
                    actionFailure = caught
                    throw caught
                }
            }
            actionFailure?.let { throw it }
            entry.put("event", "runtime content event observed; provenance Pending")
            nativeGuard(actionCompleted, "delivery-stage-command-unobserved")
        } catch (caught: Throwable) {
            // A timeout from request, capture or persistence is an action failure, not wait expiry.
            actionFailure?.let { throw it }
            if (caught !is TimeoutException) throw caught
            nativeGuard(actionCompleted, "delivery-stage-command-unobserved")
            entry.put("event", "unavailable within bound; transition Pending")
        }
        persist()
        substage = "requested-original"
        original("$name-requested", "after frame")
        substage = "bounded-original"
        current()
        capture("$name-bounded", true)
        val data = original("$name-bounded", "before frame").getJSONObject("effectiveData")
        entry.put("noDataSlotsObserved", JSONArray(intended.filter { row ->
            data.optString(row.slot.toString()).startsWith("NoDataComplicationData(")
        }.map { it.slot })).put("effectiveDataSha256", data.toString().sha256())
        substage = "persistence"
        persist()
        substage = "final-scope"
        current()
        substage = "persistence"
        entry.put("observation", "requested and bounded originals recorded; response provenance and paint Pending")
        persist()
        return entry
    } catch (failure: Throwable) {
        entry.put("observation", "Pending").put("failureOutcome", nativeReadFailure(failure).value)
            .put("failureType", nativeReadExceptionType(failure.javaClass.name)).put("failureSubstage", substage)
        (failure as? NativePending)?.let { entry.put("failureGuard", it.identity) }
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
    reserved: Boolean = false,
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
        if (reserved) {
            val armed = AttemptJournal(File(directory, "receipt.json")).read()
            nativeGuard(directory.isDirectory && armed.toString() == receipt.toString() &&
                armed.optString("reservation") == "armed; acceptance Pending" &&
                !File(directory, "original.bin").exists(), "reserved-private-recovery-directory")
        } else nativeGuard(directory.mkdir(), "fresh-private-recovery-directory")
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
