package app.wardpulse.wear.nativeintegration

import android.content.ComponentName
import android.content.Context
import android.os.OutcomeReceiver
import android.support.wearable.complications.ComplicationData as WireComplicationData
import com.google.wear.Sdk
import com.google.wear.services.complications.ComplicationData
import com.google.wear.services.complications.ComplicationsManager
import com.google.wear.services.complications.PlainComplicationText
import java.io.File
import java.util.concurrent.CompletableFuture
import java.util.concurrent.ExecutionException
import java.util.concurrent.Executor
import java.util.concurrent.TimeUnit
import java.util.concurrent.TimeoutException
import org.json.JSONArray
import org.json.JSONObject

internal val nativeSdkDirectScenarios = setOf("unsupported-range", "malformed-title",
    "partial-no-data-main", "no-data-main-valid-extra")

internal fun requireNativeSdkDirectAuthorization(expected: NativePushExpectations, scenario: String) {
    nativeGuard(scenario in nativeSdkDirectScenarios, "sdk-direct-scenario")
    nativeGuard(expected.required("quietWriters") == "confirmed-unpaired" &&
        expected.required("firstFrameReview") == "complete-unobscured", "sdk-direct-host-review")
    requireNativeDatasourceMutation(expected, "observeDirectData:$scenario")
}

internal fun nativeSdkDirectCapabilityReceipt(scope: NativeDatasourceProbeScope,
    selection: NativeDatasourceProbeSelection) = scope.json()
    .put("deliveryProbeId", selection.id).put("reviewedProbeSha256", selection.receiptSha256)
    .put("reviewedFirstFrameSha256", selection.frameSha256).put("api36Available", JSONObject.NULL)
    .put("managerAcquisition", "not invoked").put("stableScope", false)
    .put("updateCapability", "Pending; acquisition is not an update result")

internal fun requireNativeSdkDirectCapability(file: File, hash: String, scope: NativeDatasourceProbeScope,
    selection: NativeDatasourceProbeSelection) {
    nativeGuard(hash.matches(Regex("[a-f0-9]{64}")) && file.isFile && file.length() > 0 &&
        file.canonicalFile == File(file.parentFile!!.canonicalFile, file.name) &&
        !File("${file.path}.bak").exists() && !File("${file.path}.new").exists(), "reviewed-sdk-direct-capability")
    val bytes = file.readBytes()
    nativeGuard(bytes.isNotEmpty() && bytes.inputStream().sha256() == hash, "reviewed-sdk-direct-capability")
    val receipt = JSONObject(bytes.toString(Charsets.UTF_8))
    val identity = nativeSdkDirectCapabilityReceipt(scope, selection)
    (scope.json().keys().asSequence().toList() + listOf("deliveryProbeId", "reviewedProbeSha256",
        "reviewedFirstFrameSha256")).forEach { key ->
        nativeGuard(receipt.opt(key) == identity.get(key), "sdk-direct-capability-scope")
    }
    nativeGuard(receipt.opt("api36Available") == true && receipt.optString("managerAcquisition") ==
        "acquired under ordinary target UID" && receipt.opt("stableScope") == true, "sdk-direct-capability-unavailable")
}

internal fun interface NativeSdkDirectUpdater {
    fun update(id: Int, data: ComplicationData, receiver: OutcomeReceiver<Void, Throwable>)
}

internal fun readNativeSdkDirectManager(context: Context, receipt: JSONObject, persist: () -> Unit) =
    readNativeSdkDirectManager(receipt, persist, supported = {
        Sdk.isApiVersionAtLeast(Sdk.VERSION_CODES.WEAR_BAKLAVA_0)
    }, acquire = {
        Sdk.getWearManager(context, ComplicationsManager::class.java)?.let { manager ->
            NativeSdkDirectUpdater { id, data, receiver ->
                manager.updateComplication(id, data, Executor { it.run() }, receiver)
            }
        }
    })

/** API35.1 typed reads do not establish this API36 route. No shell/context/permission fallback. */
internal fun readNativeSdkDirectManager(receipt: JSONObject, persist: () -> Unit, supported: () -> Boolean,
    acquire: () -> NativeSdkDirectUpdater?): NativeSdkDirectUpdater {
    try {
        val available = supported()
        receipt.put("api36Available", available)
        persist()
        nativeGuard(available, "sdk-direct-api36-unavailable")
        receipt.put("managerAcquisition", "invoked under ordinary target UID; outcome Pending")
        persist()
        val updater = acquire() ?: throw NativeReadEmpty()
        receipt.put("managerAcquisition", "acquired under ordinary target UID")
        persist()
        return updater
    } catch (failure: Throwable) {
        receipt.put("capabilityFailure", nativeReadFailure(failure).value)
        try { persist() } catch (recording: Throwable) { failure.addSuppressed(recording) }
        throw failure
    }
}

internal data class NativeSdkDirectUpdate(val target: NativeDeliveryTarget, val data: ComplicationData)

/** Public typed builders only; no raw fields, reflection, normalization or validation bypass. */
internal fun nativeSdkDirectData(scenario: String, targets: List<NativeDeliveryTarget>): List<NativeSdkDirectUpdate> {
    nativeGuard(scenario in nativeSdkDirectScenarios, "sdk-direct-scenario")
    fun target(service: String) = targets.singleOrNull {
        it.provider == ComponentName(HOST_PACKAGE, "app.wardpulse.wear.complication.${service}ComplicationDataSourceService")
    } ?: throw NativePending("sdk-direct-selected-target-unmapped")
    val main = target("Today")
    fun ranged(value: Float = 148f, max: Float = 400f, title: String = "") =
        ComplicationData.Builder(WireComplicationData.TYPE_RANGED_VALUE)
            .setRangedMinValue(0f).setRangedMaxValue(max).setRangedValue(value)
            .setShortText(PlainComplicationText("37%"))
            .setShortTitle(PlainComplicationText(title))
            .setContentDescription(PlainComplicationText("Test percentage"))
            .build().also {
                nativeGuard(it.type == WireComplicationData.TYPE_RANGED_VALUE && it.rangedMinValue == 0f &&
                    it.rangedMaxValue == max && it.rangedValue == value &&
                    (it.shortTitle as? PlainComplicationText)?.text?.toString() == title, "sdk-direct-object-normalized")
            }
    fun noData() = ComplicationData.Builder(WireComplicationData.TYPE_NO_DATA).build().also {
        nativeGuard(it.type == WireComplicationData.TYPE_NO_DATA, "sdk-direct-object-normalized")
    }
    return when (scenario) {
        "unsupported-range" -> listOf(NativeSdkDirectUpdate(main, ranged(111f, 300f)))
        "malformed-title" -> listOf(NativeSdkDirectUpdate(main, ranged(title = "invalid")))
        "partial-no-data-main" -> listOf(NativeSdkDirectUpdate(main, noData()))
        else -> listOf(NativeSdkDirectUpdate(main, noData()), NativeSdkDirectUpdate(target("RingSplit"), ranged(title = "0")))
    }
}

internal fun constructNativeSdkDirectData(scenario: String, targets: List<NativeDeliveryTarget>,
    receipt: JSONObject, persist: () -> Unit,
    construct: () -> List<NativeSdkDirectUpdate> = { nativeSdkDirectData(scenario, targets) }): List<NativeSdkDirectUpdate> {
    nativeGuard(scenario in nativeSdkDirectScenarios, "sdk-direct-scenario")
    receipt.put("construction", "invoked; no dispatch")
    persist()
    val updates = try { construct() } catch (failure: IllegalArgumentException) {
        receipt.put("construction", "SDK rejected; no dispatch or renderer effect established")
        persist()
        throw failure
    }
    receipt.put("construction", "constructed; no dispatch").put("requestedSlots", JSONArray(updates.map { it.target.slot }))
    persist()
    return updates
}

/** Only the waiting owner mutates evidence. Every possibly affected target is armed before any call. */
internal fun dispatchNativeSdkDirectData(updates: List<NativeSdkDirectUpdate>, receipt: JSONObject,
    persist: () -> Unit, validate: (NativeDeliveryTarget) -> Unit, updater: NativeSdkDirectUpdater,
    recover: (List<NativeDeliveryTarget>) -> Unit, observe: (Int) -> Unit = {},
    await: (CompletableFuture<Void?>) -> Unit = { it.get(5, TimeUnit.SECONDS); Unit }) {
    nativeGuard(updates.isNotEmpty() && updates.map { it.target.systemId }.distinct().size == updates.size,
        "sdk-direct-distinct-targets")
    val calls = JSONArray(updates.map { update -> JSONObject().put("slot", update.target.slot)
        .put("systemId", update.target.systemId).put("providerSha256", update.target.provider.flattenToString().sha256())
        .put("dispatch", "not invoked").put("callback", "not invoked") })
    nativeGuard(!receipt.optBoolean("directArmed"), "single-sdk-direct-dispatch")
    receipt.put("directArmed", true).put("calls", calls).put("effect", "uncertain; recovery required")
    persist() // Failure here forbids every update. A persisted arm is never retried.
    var failure: Throwable? = null
    try {
        updates.forEachIndexed { index, update ->
            val call = calls.getJSONObject(index)
            val result = CompletableFuture<Void?>()
            try {
                validate(update.target)
                call.put("dispatch", "armed; invocation/effect uncertain").put("callback", "Pending")
                persist()
                // Revalidate after durable per-ID arming, immediately before this individual call.
                validate(update.target)
                updater.update(update.target.systemId, update.data, object : OutcomeReceiver<Void, Throwable> {
                    override fun onResult(value: Void?) { result.complete(value) }
                    override fun onError(error: Throwable) { result.completeExceptionally(error) }
                })
                call.put("dispatch", "returned; native effect Pending")
                persist()
                try { await(result) } catch (caught: ExecutionException) {
                    call.put("callback", "onError; processing/forwarding not established; effect uncertain")
                    throw caught.cause ?: caught
                } catch (caught: TimeoutException) {
                    call.put("callback", "unavailable within bound; effect uncertain")
                    throw caught
                }
                call.put("callback", "onResult; processing/forwarding reported; effective data and paint Pending")
                persist()
            } catch (caught: Throwable) {
                call.put("failure", nativeReadFailure(caught).value)
                if (call.optString("callback") == "Pending") {
                    call.put("callback", "outcome unrecorded; effect uncertain")
                }
                try { persist() } catch (recording: Throwable) { caught.addSuppressed(recording) }
                try { observe(index) } catch (observation: Throwable) { caught.addSuppressed(observation) }
                throw caught
            } finally {
                result.cancel(false) // Late/duplicate callbacks cannot change terminal receipt bytes.
            }
            observe(index)
        }
    } catch (caught: Throwable) {
        failure = caught
        throw caught
    } finally {
        // Includes all armed rows, even an uncalled second row after a first-call failure/timeout.
        try { recover(updates.map { it.target }) } catch (cleanup: Throwable) {
            if (failure == null) throw cleanup else failure.addSuppressed(cleanup)
        }
    }
}
