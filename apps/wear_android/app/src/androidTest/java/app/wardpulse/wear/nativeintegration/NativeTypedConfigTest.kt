package app.wardpulse.wear.nativeintegration

import android.content.ComponentName
import android.os.Bundle
import android.os.OutcomeReceiver
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.google.wear.Sdk
import com.google.wear.services.complications.ActiveComplicationConfig
import com.google.wear.services.complications.ComplicationsManager
import java.io.File
import java.util.UUID
import java.util.concurrent.CompletableFuture
import java.util.concurrent.ExecutionException
import java.util.concurrent.Executor
import java.util.concurrent.TimeUnit
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Test
import org.junit.runner.RunWith

internal const val TYPED_CONFIG_CLASS = "app.wardpulse.wear.nativeintegration.NativeTypedConfigTest"

internal data class NativeTypedConfig(val id: Int, val watchFaceSlotId: Int, val provider: ComponentName?,
    val watchFacePackage: String?, val watchFaceClass: String?, val dataType: Int) {
    fun json() = JSONObject().put("id", id).put("watchFaceSlotId", watchFaceSlotId)
        .put("providerComponent", provider?.flattenToString() ?: JSONObject.NULL)
        .put("watchFaceId", if (watchFacePackage == null) JSONObject.NULL else JSONObject()
            .put("packageName", watchFacePackage).put("className", watchFaceClass ?: JSONObject.NULL))
        .put("dataType", dataType)
}

internal fun nativeTypedConfigReceipt() = JSONObject().put("kind", "read-only-typed-configs")
    .put("metadataOutcome", NativeReadOutcome.NOT_INVOKED.value)
    .put("stableBracket", JSONObject.NULL)
    .put("activeFaceAssociation", NativeReadOutcome.UNRESOLVED.value)
    .put("idDomain", "Wear SDK provider/system complication id")
    .put("watchFaceSlotIdDomain", "Wear SDK watchFaceSlotId; no native/client/generator join")
    .put("watchFaceIdDomain", "resource package/class identity; no opaque instance identity")
    .put("operations", JSONObject().apply {
        listOf("admission", "beforeFace", "beforeResource", "sdkAvailability", "managerAcquisition",
            "activeConfigs", "afterFace", "afterIdentity", "afterResource", "beforeConfiguration", "afterConfiguration")
            .forEach { put(it, nativeReadOperation("not yet resolved", "not yet observed")) }
    })

internal fun interface NativeTypedConfigReader {
    fun read(receiver: OutcomeReceiver<List<NativeTypedConfig>, Throwable>)
}

/** Only the waiting owner changes receipts. Late callbacks cannot overwrite a terminal outcome. */
internal fun awaitNativeTypedConfigs(reader: NativeTypedConfigReader,
    await: (CompletableFuture<List<NativeTypedConfig>?>) -> List<NativeTypedConfig>? = {
        it.get(5, TimeUnit.SECONDS)
    }): List<NativeTypedConfig>? {
    val result = CompletableFuture<List<NativeTypedConfig>?>()
    try {
        reader.read(object : OutcomeReceiver<List<NativeTypedConfig>, Throwable> {
            override fun onResult(value: List<NativeTypedConfig>?) { result.complete(value) }
            override fun onError(error: Throwable) { result.completeExceptionally(error) }
        })
        return try {
            await(result)
        } catch (failure: ExecutionException) {
            throw failure.cause ?: failure
        }
    } finally {
        // No remote client/control reference is acquired by this one-shot callback read.
        result.cancel(false)
    }
}

internal fun readNativeTypedConfigs(receipt: JSONObject, persist: () -> Unit, supported: () -> Boolean,
    acquire: () -> NativeTypedConfigReader?,
    await: (CompletableFuture<List<NativeTypedConfig>?>) -> List<NativeTypedConfig>? = {
        it.get(5, TimeUnit.SECONDS)
    }) {
    try {
        nativeClientOperation(receipt, persist, "sdkAvailability", "Sdk", "Wear SDK 35.1 availability") {
            supported().also {
                receipt.put("sdk35_1Available", it)
                if (!it) throw UnsupportedOperationException()
            }
        }
        val reader = nativeClientOperation(receipt, persist, "managerAcquisition", HOST_PACKAGE,
            "ComplicationsManager under actual provider-app UID") { acquire() ?: throw NativeReadEmpty() }
        nativeClientOperation(receipt, persist, "activeConfigs", HOST_PACKAGE,
            "own-provider typed configs: system id, watchFaceSlotId, provider, WatchFaceId, type") {
            val configs = awaitNativeTypedConfigs(reader, await)
            receipt.put("configs", configs?.let { JSONArray(it.map { config -> config.json() }) } ?: JSONObject.NULL)
                .put("metadataOutcome", if (configs.isNullOrEmpty()) NativeReadOutcome.EMPTY.value else NativeReadOutcome.ACQUIRED.value)
            if (configs.isNullOrEmpty()) throw NativeReadEmpty()
        }
    } catch (failure: Throwable) {
        if (receipt.getString("metadataOutcome") == NativeReadOutcome.NOT_INVOKED.value) {
            receipt.put("metadataOutcome", nativeReadFailure(failure).value)
        }
        throw failure
    }
}

internal fun recordNativeTypedBracket(receipt: JSONObject, before: NativeReadFace?, after: NativeReadFace?,
    identityMatches: Boolean, resourcesMatch: Boolean) {
    receipt.put("stableBracket", before != null && after != null && before.sameScope(after) &&
        identityMatches && resourcesMatch)
    // WatchFaceId supplies no WFF instance. Even stable resource evidence cannot join these ID domains.
    receipt.put("activeFaceAssociation", NativeReadOutcome.UNRESOLVED.value)
}

/** Own-provider metadata only; no update, client acquisition, rendering or message transport. */
@ManualNativeIntegration
@RunWith(AndroidJUnit4::class)
class NativeTypedConfigTest {
    @Test
    fun observeActiveComplicationConfigs() {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val context = instrumentation.targetContext
        val expected = NativePushExpectations(InstrumentationRegistry.getArguments())
        val admission = NativeReadAdmission(instrumentation, expected)
        val device = NativePushDevice(instrumentation)
        val directory = File(context.filesDir, "native_read/typed-${UUID.randomUUID()}")
        nativeGuard(directory.mkdirs(), "fresh-read-only-typed-receipt")
        val receipt = nativeTypedConfigReceipt()
        val journal = AttemptJournal(File(directory, "receipt.json"))
        val persist = { journal.persist(receipt) }
        fun <T> operation(name: String, target: String, domain: String, action: () -> T) =
            nativeClientOperation(receipt, persist, name, target, domain, action)
        fun <T> optionalOperation(name: String, target: String, domain: String, action: () -> T): T? =
            try { operation(name, target, domain, action) } catch (_: Throwable) { null }
        var identity: JSONObject? = null
        var resources: JSONObject? = null
        var before: NativeReadFace? = null
        var failure: Throwable? = null
        persist()
        try {
            identity = operation("admission", HOST_PACKAGE, "current caller UID/package/APK/signer") {
                admission.admit("observeActiveComplicationConfigs", TYPED_CONFIG_CLASS, "typed-configs").also {
                    receipt.put("identity", it)
                }
            }
            // The own-provider API needs no active-face join. Missing brackets must not suppress raw configs.
            before = optionalOperation("beforeFace", "active system/native instance", "system/native/resource/instance scope") {
                readNativeClientFace(device, expected, receipt, persist, "before").also { receipt.put("beforeFace", it.json()) }
            }
            before?.let { face ->
                resources = optionalOperation("beforeResource", face.renderer.resourcePackage, "installed resource/runtime APK identities") {
                    admission.resourceIdentity(face.renderer.resourcePackage).also { receipt.put("beforeResource", it) }
                }
            }
            readNativeTypedConfigs(receipt, persist, supported = {
                Sdk.isApiVersionAtLeast(Sdk.VERSION_CODES.WEAR_VIC_1)
            }, acquire = {
                Sdk.getWearManager(context, ComplicationsManager::class.java)?.let { manager ->
                    NativeTypedConfigReader { receiver ->
                        manager.getActiveComplicationConfigsAsync(Executor { it.run() },
                            object : OutcomeReceiver<List<ActiveComplicationConfig>, Throwable> {
                                override fun onResult(result: List<ActiveComplicationConfig>?) {
                                    val configs = try {
                                        result?.map { active ->
                                            val config = active.config
                                            NativeTypedConfig(config.id, config.watchFaceSlotId, config.providerComponent,
                                                config.watchFaceId?.packageName, config.watchFaceId?.className, config.dataType)
                                        }
                                    } catch (caught: Throwable) {
                                        receiver.onError(caught)
                                        return
                                    }
                                    receiver.onResult(configs)
                                }
                                override fun onError(error: Throwable) { receiver.onError(error) }
                            })
                    }
                }
            })
        } catch (caught: Throwable) {
            failure = caught
            receipt.put("observationOutcome", nativeReadFailure(caught).value)
        } finally {
            // Current caller identity is repeated even when the optional active-face bracket was unavailable.
            if (identity != null) {
                val after = optionalOperation("afterFace", "active system/native instance", "system/native/resource/instance scope") {
                    readNativeClientFace(device, expected, receipt, persist, "after").also { receipt.put("afterFace", it.json()) }
                }
                val current = optionalOperation("afterIdentity", HOST_PACKAGE, "current caller UID/package/APK/signer") {
                    admission.currentIdentity().also { receipt.put("afterIdentity", it) }
                }
                val currentResources = before?.let { face ->
                    optionalOperation("afterResource", face.renderer.resourcePackage, "installed resource/runtime APK identities") {
                        admission.resourceIdentity(face.renderer.resourcePackage).also { receipt.put("afterResource", it) }
                    }
                }
                recordNativeTypedBracket(receipt, before, after, current != null && identity.toString() == current.toString(),
                    resources != null && currentResources != null && resources.toString() == currentResources.toString())
            }
            persist()
        }
        if (failure != null) throw AssertionError("Pending: typed-config observation; retain private receipts for HOST review.")
        instrumentation.sendStatus(0, Bundle().apply {
            putString("stream", "\nTyped configs recorded privately; active-face association and runtime acceptance remain Pending.\n")
        })
    }
}
