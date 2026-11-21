package app.wardpulse.wear.nativeintegration

import android.content.ComponentName
import android.content.Context
import android.content.ContextWrapper
import android.content.Intent
import android.content.ServiceConnection
import android.content.pm.PackageManager
import androidx.wear.watchface.client.InteractiveWatchFaceClient
import androidx.wear.watchface.client.WatchFaceControlClient
import androidx.wear.watchface.complications.data.ColorRamp
import androidx.wear.watchface.complications.data.ComplicationData
import androidx.wear.watchface.complications.data.NoDataComplicationData
import androidx.wear.watchface.complications.data.PlainComplicationText
import androidx.wear.watchface.complications.data.RangedValueComplicationData
import java.io.File
import java.util.concurrent.Executor
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import org.json.JSONObject

internal const val CLIENT_CLASS = "app.wardpulse.wear.nativeintegration.NativeComplicationOverrideTest"

internal fun JSONObject.sameClientIdentity(other: JSONObject): Boolean = length() == other.length() &&
    keys().asSequence().all { key -> get(key) == other.opt(key) }

internal fun requireGuardedNativeClientProbe(probed: JSONObject, identity: JSONObject) {
    nativeGuard(!probed.has("kind") &&
        probed.optString("state") == "probe returned; first-frame and restoration review Pending" &&
        !probed.has("outcome") && probed.optString("controlCleanup") == "close returned" &&
        probed.optString("interactiveCleanup") == "close returned" &&
        probed.optString("controlBindingCleanup") == "tracked connections released" &&
        identity.sameClientIdentity(probed.getJSONObject("identity")), "retained-client-probe-identity")
}

/** Tracks both public bind overloads, including the executor overload used by client 1.2.1. */
internal class NativeClientBinding(context: Context, private val verifyService: (Intent) -> Unit) :
    ContextWrapper(context), AutoCloseable {
    private val connections = linkedSetOf<ServiceConnection>()
    var bindAttempted = false
        private set

    @Synchronized
    private fun bind(service: Intent, connection: ServiceConnection, action: () -> Boolean): Boolean {
        nativeGuard(connections.isEmpty(), "single-client-binding")
        verifyService(service)
        // Register before calling Android: denied/failed/partial construction also needs cleanup.
        connections += connection
        bindAttempted = true
        return action()
    }

    override fun bindService(service: Intent, connection: ServiceConnection, flags: Int) =
        bind(service, connection) { super.bindService(service, connection, flags) }

    override fun bindService(service: Intent, flags: Int, executor: Executor, connection: ServiceConnection) =
        bind(service, connection) { super.bindService(service, flags, executor, connection) }

    @Synchronized
    override fun unbindService(connection: ServiceConnection) {
        if (connection !in connections) return
        try {
            super.unbindService(connection)
        } catch (_: IllegalArgumentException) {
            // Android confirms there is no registered connection, including a rejected bind.
        }
        connections -= connection
    }

    @Synchronized
    override fun close() {
        connections.toList().forEach { unbindService(it) }
    }
}

/** The original guarded route retains its instance and cross-domain slot requirements. */
internal fun withExistingNativeClient(context: Context, renderer: NativeRenderer, receipt: JSONObject,
    persist: () -> Unit, action: (InteractiveWatchFaceClient) -> Unit) {
    withNativeClientAcquisition(context, renderer.resourcePackage, renderer.instance, receipt, persist) { existing ->
        nativeGuard(existing.instanceId == renderer.instance, "client-instance-mismatch")
        val slots = existing.complicationSlotsState
        nativeGuard(slots.keys == renderer.enabled.keys &&
            slots.all { (id, state) -> state.isEnabled == renderer.enabled[id] }, "client-slot-mapping")
        // Default datasource policies are deliberately not consulted for selected-provider proof.
        receipt.put("client", "existing instance and enabled slots verified; overrides unproven")
        persist()
        action(existing)
    }
}

/** A durable acquisition fence, shared by metadata and the original guarded wrapper. */
internal class NativeClientCustody(private val directory: File) {
    private val lock = File(directory, "owner.lock")
    private val journal = AttemptJournal(File(directory, "custody.json"))
    private val record = JSONObject()

    fun acquire(resourcePackage: String, instance: String) {
        nativeGuard(directory.isDirectory || directory.mkdirs(), "private-client-custody")
        nativeGuard(!journal.exists() || journal.read().optString("state") == "released", "client-custody-unresolved")
        nativeGuard(lock.createNewFile(), "single-client-owner")
        record.put("state", "armed; acquisition custody unresolved").put("pid", android.os.Process.myPid())
            .put("resourcePackage", resourcePackage).put("instanceSha256", instance.sha256())
        journal.persist(record)
    }

    fun finish(resolved: Boolean) {
        journal.persist(record.put("state", if (resolved) "released" else "remote ownership or cleanup unresolved"))
        if (resolved) nativeGuard(lock.delete(), "client-owner-lock-cleanup")
    }
}

/** Attempt every close, preserving separate failure evidence even if receipt persistence fails. */
internal fun cleanupNativeClient(receipt: JSONObject, persist: () -> Unit,
    interactive: (() -> Unit)?, control: (() -> Unit)?, binding: () -> Unit,
    interactiveUnreturned: Boolean, controlUnreturned: Boolean): Boolean {
    var resolved = !interactiveUnreturned && !controlUnreturned
    fun close(key: String, action: (() -> Unit)?, absent: String, success: String = "close returned") {
        try {
            action?.invoke()
            receipt.put(key, if (action == null) absent else success)
        } catch (_: Throwable) {
            resolved = false
            receipt.put(key, "cleanup failed; ownership Pending")
        }
        try { persist() } catch (_: Throwable) { resolved = false }
    }
    close("interactiveCleanup", interactive, if (interactiveUnreturned)
        "unreturned acquisition; remote ownership Pending" else "no client returned")
    close("controlCleanup", control, if (controlUnreturned)
        "unreturned acquisition; remote ownership Pending" else "no control returned")
    close("controlBindingCleanup", binding, "", "tracked connections released")
    return resolved
}

/** Acquisition has no slot-domain join, data transport, rendering, creation or permission adoption. */
internal fun withNativeClientAcquisition(context: Context, resourcePackage: String, instance: String,
    receipt: JSONObject, persist: () -> Unit, action: (InteractiveWatchFaceClient) -> Unit) {
    val custody = NativeClientCustody(File(context.filesDir, "native_client/acquisition"))
    custody.acquire(resourcePackage, instance)
    val binding = NativeClientBinding(context) { intent ->
        nativeClientOperation(receipt, persist, "serviceResolution", RUNTIME_PACKAGE,
            "resolved runtime service component and declared permission") {
            // Resolve the public factory's actual intent, before delegating its bind to Android.
            nativeGuard(intent.`package` == RUNTIME_PACKAGE, "client-runtime-package")
            val candidates = context.packageManager.queryIntentServices(intent, 0)
            val operation = receipt.getJSONObject("operations").getJSONObject("serviceResolution")
            operation.put("resolvedServiceCount", candidates.size)
            val service = candidates.singleOrNull()?.serviceInfo
                ?: throw NativePending("client-service-unresolved")
            receipt.put("serviceSha256", ComponentName(service.packageName, service.name).flattenToString().sha256())
                .put("servicePermission", if (service.permission.isNullOrEmpty()) "none declared" else "required")
            operation.put("target", ComponentName(service.packageName, service.name).flattenToString())
                .put("component", ComponentName(service.packageName, service.name).flattenToString())
                .put("exported", service.exported).put("enabled", service.enabled)
                .put("applicationEnabled", service.applicationInfo.enabled)
                .put("permission", service.permission ?: JSONObject.NULL)
                .put("permissionHeld", service.permission.isNullOrEmpty() ||
                    context.checkSelfPermission(service.permission) == PackageManager.PERMISSION_GRANTED)
            persist()
            nativeGuard(service.packageName == RUNTIME_PACKAGE && service.exported && service.enabled &&
                service.applicationInfo.enabled, "client-service-access")
            nativeGuard(service.permission.isNullOrEmpty() ||
                context.checkSelfPermission(service.permission) == PackageManager.PERMISSION_GRANTED, "client-permission-denied")
        }
    }
    var control: WatchFaceControlClient? = null
    var client: InteractiveWatchFaceClient? = null
    var controlInvoked = false
    var controlReturned = false
    var interactiveInvoked = false
    var interactiveReturned = false
    var failure: Throwable? = null
    try {
        nativeClientOperation(receipt, persist, "controlAcquisition", RUNTIME_PACKAGE,
            "watchface-client control reference") {
            controlInvoked = true
            runBlocking(Dispatchers.IO) {
                withTimeout(5_000) {
                    // Assign inside the timeout so a returned object is owned even at cancellation.
                    control = WatchFaceControlClient.createWatchFaceRuntimeControlClient(
                        binding, RUNTIME_PACKAGE, resourcePackage,
                    )
                    controlReturned = true
                }
            }
        }
        receipt.put("existingInstanceAcquisition", "armed; returned client Pending")
        nativeClientOperation(receipt, persist, "interactiveAcquisition", instance,
            "watchface-client existing instance reference") {
            interactiveInvoked = true
            client = checkNotNull(control).getInteractiveWatchFaceClientInstance(instance)
            interactiveReturned = true
            receipt.put("existingInstanceAcquisition", if (client == null) "no existing instance" else "returned")
            if (client == null) throw NativePending("client-existing-instance-unavailable")
        }
        action(checkNotNull(client))
    } catch (caught: Throwable) {
        failure = caught
        throw caught
    } finally {
        val resolved = cleanupNativeClient(receipt, persist, client?.let { { it.close() } },
            control?.let { { it.close() } }, { binding.close() },
            interactiveInvoked && !interactiveReturned,
            controlInvoked && !controlReturned && binding.bindAttempted)
        try {
            receipt.put("acquisitionCustody", if (resolved) "cleanup verified; consult custody journal for release" else "unresolved")
            persist()
            custody.finish(resolved)
            nativeGuard(resolved, "client-custody-unresolved")
        } catch (cleanup: Throwable) {
            receipt.put("acquisitionCustody", "unresolved; reconciliation required")
            try { persist() } catch (recording: Throwable) { cleanup.addSuppressed(recording) }
            if (failure == null) throw cleanup else failure.addSuppressed(cleanup)
        }
    }
}

/** Narrow cases use discovered selected-provider slots, never scene IDs or guessed system IDs. */
internal fun nativeOverrideData(scenario: String, targets: List<NativeDeliveryTarget>): Map<Int, ComplicationData> {
    fun slot(service: String) = targets.singleOrNull {
        it.provider == ComponentName(HOST_PACKAGE, "app.wardpulse.wear.complication.${service}ComplicationDataSourceService")
    }?.slot ?: throw NativePending("override-selected-slot-unmapped")
    val main = slot("Today")
    fun ranged(value: Float = 148f, max: Float = 400f, title: String = "") =
        RangedValueComplicationData.Builder(value, 0f, max, PlainComplicationText.Builder("Test percentage").build())
            .setValueType(RangedValueComplicationData.TYPE_UNDEFINED)
            .setText(PlainComplicationText.Builder("37%").build())
            .setTitle(PlainComplicationText.Builder(title).build())
            .setColorRamp(ColorRamp(intArrayOf(0xff14b8a6.toInt()), false)).build().also {
                nativeGuard(it.value.toBits() == value.toBits() && it.min == 0f && it.max == max &&
                    it.valueType == RangedValueComplicationData.TYPE_UNDEFINED, "client-object-normalized")
            }
    return when (scenario) {
        // A valid generic ranged object whose envelope is unsupported by the WFF contract.
        "unsupported-range" -> mapOf(main to ranged(value = 111f, max = 300f))
        "malformed-title" -> mapOf(main to ranged(title = "invalid"))
        // The SDK may reject this object before any transport: that is not WFF suppression.
        "nonfinite-value" -> mapOf(main to ranged(value = Float.NaN))
        "out-of-range" -> mapOf(main to ranged(value = 401f))
        "partial-no-data-main" -> mapOf(main to NoDataComplicationData())
        "no-data-main-valid-extra" -> mapOf(main to NoDataComplicationData(),
            slot("RingSplit") to ranged(title = "0"))
        else -> throw NativePending("override-scenario")
    }
}
