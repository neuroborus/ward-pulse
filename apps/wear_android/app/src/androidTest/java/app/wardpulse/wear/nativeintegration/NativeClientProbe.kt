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
import java.util.concurrent.Executor
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import org.json.JSONObject

internal const val CLIENT_CLASS = "app.wardpulse.wear.nativeintegration.NativeComplicationOverrideTest"

internal fun JSONObject.sameClientIdentity(other: JSONObject): Boolean = length() == other.length() &&
    keys().asSequence().all { key -> get(key) == other.opt(key) }

/** Recovery attempts every affected provider even if an earlier request fails. */
internal fun requestNormalClientData(providers: List<ComponentName>, request: (ComponentName) -> Unit) {
    var unavailable = false
    providers.distinct().forEach {
        try { request(it) } catch (_: Throwable) { unavailable = true }
    }
    nativeGuard(!unavailable, "client-normal-recovery-request-unavailable")
}

/** Tracks both public bind overloads, including the executor overload used by client 1.2.1. */
internal class NativeClientBinding(context: Context, private val verifyService: (Intent) -> Unit) :
    ContextWrapper(context), AutoCloseable {
    private val connections = linkedSetOf<ServiceConnection>()

    @Synchronized
    private fun bind(service: Intent, connection: ServiceConnection, action: () -> Boolean): Boolean {
        nativeGuard(connections.isEmpty(), "single-client-binding")
        verifyService(service)
        // Register before calling Android: denied/failed/partial construction also needs cleanup.
        connections += connection
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

/** No create-instance fallback, UI state setter, style change or permission adoption. */
internal fun withExistingNativeClient(context: Context, renderer: NativeRenderer, receipt: JSONObject,
    persist: () -> Unit, action: (InteractiveWatchFaceClient) -> Unit) {
    NativeClientBinding(context) { intent ->
        // Resolve the public factory's actual intent, before delegating its bind to Android.
        nativeGuard(intent.`package` == RUNTIME_PACKAGE, "client-runtime-package")
        val service = context.packageManager.queryIntentServices(intent, 0).singleOrNull()?.serviceInfo
            ?: throw NativePending("client-service-unresolved")
        nativeGuard(service.packageName == RUNTIME_PACKAGE && service.exported && service.enabled &&
            service.applicationInfo.enabled, "client-service-access")
        receipt.put("serviceSha256", ComponentName(service.packageName, service.name).flattenToString().sha256())
            .put("servicePermission", if (service.permission.isNullOrEmpty()) "none declared" else "required")
        persist()
        nativeGuard(service.permission.isNullOrEmpty() ||
            context.checkSelfPermission(service.permission) == PackageManager.PERMISSION_GRANTED, "client-permission-denied")
    }.use { binding ->
        var control: WatchFaceControlClient? = null
        var client: InteractiveWatchFaceClient? = null
        try {
            runBlocking(Dispatchers.IO) {
                withTimeout(5_000) {
                    // Assign inside the timeout so a returned object is owned even at cancellation.
                    control = WatchFaceControlClient.createWatchFaceRuntimeControlClient(
                        binding, RUNTIME_PACKAGE, renderer.resourcePackage,
                    )
                }
            }
            receipt.put("existingInstanceAcquisition", "armed; returned client Pending")
            persist()
            client = checkNotNull(control).getInteractiveWatchFaceClientInstance(renderer.instance)
            receipt.put("existingInstanceAcquisition", if (client == null) "no existing instance" else "returned")
            persist()
            val existing = client ?: throw NativePending("client-existing-instance-unavailable")
            nativeGuard(existing.instanceId == renderer.instance, "client-instance-mismatch")
            val slots = existing.complicationSlotsState
            nativeGuard(slots.keys == renderer.enabled.keys &&
                slots.all { (id, state) -> state.isEnabled == renderer.enabled[id] }, "client-slot-mapping")
            // Default datasource policies are deliberately not consulted for selected-provider proof.
            receipt.put("client", "existing instance and enabled slots verified; overrides unproven")
            persist()
            action(existing)
        } finally {
            try {
                client?.close()
                receipt.put("interactiveCleanup", if (client != null) "close returned" else
                    if (receipt.optString("existingInstanceAcquisition") == "armed; returned client Pending")
                        "unreturned acquisition; remote ownership Pending" else "no client returned")
            } finally {
                try {
                    control?.close()
                    receipt.put("controlCleanup", if (control == null) "no control returned" else "close returned")
                } finally {
                    // The public suspend factory does not release a pre-return bind on timeout.
                    binding.close()
                    receipt.put("controlBindingCleanup", "tracked connections released")
                    persist()
                }
            }
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
