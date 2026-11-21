package app.wardpulse.wear.nativeintegration

import android.os.Bundle
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.io.File
import java.util.UUID
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Test
import org.junit.runner.RunWith

internal const val CLIENT_METADATA_CLASS = "app.wardpulse.wear.nativeintegration.NativeClientMetadataTest"

internal data class NativeClientSlotMetadata(val key: Int, val enabled: Boolean, val supportedTypes: List<String>) {
    fun json() = JSONObject().put("clientSlotKey", key).put("enabled", enabled)
        .put("supportedTypes", JSONArray(supportedTypes))
}

internal fun nativeClientMetadataReceipt() = JSONObject().put("kind", "read-only-client-metadata")
    .put("metadataOutcome", NativeReadOutcome.NOT_INVOKED.value)
    .put("stableBracket", JSONObject.NULL).put("returnedInstanceMatches", JSONObject.NULL)
    .put("slotAssociation", NativeReadOutcome.UNRESOLVED.value).put("operations", JSONObject().apply {
        listOf("admission", "beforeFace", "beforeResource", "serviceResolution", "controlAcquisition",
            "interactiveAcquisition", "clientInstance", "clientSlots", "afterFace", "afterIdentity", "afterResource",
            "beforeConfiguration", "afterConfiguration")
            .forEach { put(it, nativeReadOperation("not yet resolved", "not yet observed")) }
    })

/** Public client slot keys stay in their own domain even when their numbers differ from native slots. */
internal fun recordNativeClientSlots(receipt: JSONObject, slots: List<NativeClientSlotMetadata>) {
    receipt.put("clientSlotDomain", "watchface-client 1.2.1 complicationSlotsState keys")
        .put("clientSlots", JSONArray(slots.sortedBy { it.key }.map { it.json() }))
        .put("metadataOutcome", if (slots.isEmpty()) NativeReadOutcome.EMPTY.value else NativeReadOutcome.ACQUIRED.value)
}

/** Individually selected existing-instance metadata only; no rendering, updates or recovery transport. */
@ManualNativeIntegration
@RunWith(AndroidJUnit4::class)
class NativeClientMetadataTest {
    @Test
    fun observeClientMetadata() {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val context = instrumentation.targetContext
        val expected = NativePushExpectations(InstrumentationRegistry.getArguments())
        val admission = NativeReadAdmission(instrumentation, expected)
        val device = NativePushDevice(instrumentation)
        val directory = File(context.filesDir, "native_read/client-${UUID.randomUUID()}")
        nativeGuard(directory.mkdirs(), "fresh-read-only-client-receipt")
        val receipt = nativeClientMetadataReceipt()
        val journal = AttemptJournal(File(directory, "receipt.json"))
        val persist = { journal.persist(receipt) }
        fun <T> operation(name: String, target: String, domain: String, action: () -> T) =
            nativeClientOperation(receipt, persist, name, target, domain, action)
        fun <T> optionalOperation(name: String, target: String, domain: String, action: () -> T): T? =
            try { operation(name, target, domain, action) } catch (_: Throwable) { null }
        var before: NativeReadFace? = null
        var identity: JSONObject? = null
        var resources: JSONObject? = null
        var failure: Throwable? = null
        persist()
        try {
            identity = operation("admission", HOST_PACKAGE, "current caller UID/package/APK/signer") {
                admission.admit("observeClientMetadata", CLIENT_METADATA_CLASS, "client-metadata").also {
                    nativeGuard(expected.required("clientArtifactReview") == "resolved-1.2.1", "read-client-artifact-review")
                    receipt.put("clientArtifactSha256", expected.hash("expectedClientArtifactSha256"))
                        .put("clientGraphSha256", expected.hash("expectedClientGraphSha256"))
                        .put("identity", it)
                }
            }
            val face = operation("beforeFace", "active system/native instance", "system/native/resource/instance scope") {
                readNativeClientFace(device, expected, receipt, persist, "before").also {
                    receipt.put("beforeFace", it.json())
                }
            }
            before = face
            resources = operation("beforeResource", face.renderer.resourcePackage, "installed resource/runtime APK identities") {
                admission.resourceIdentity(face.renderer.resourcePackage).also { receipt.put("beforeResource", it) }
            }
            withNativeClientAcquisition(context, face.renderer.resourcePackage, face.renderer.instance, receipt, persist) { client ->
                optionalOperation("clientInstance", face.renderer.instance, "client opaque instance ID") {
                    client.instanceId.also { receipt.put("returnedClientInstance", it) }
                }
                operation("clientSlots", face.renderer.instance, "client slot keys/enabled/supported types") {
                    val slots = client.complicationSlotsState.map { (key, state) ->
                        NativeClientSlotMetadata(key, state.isEnabled, state.supportedTypes.map { it.name }.sorted())
                    }
                    recordNativeClientSlots(receipt, slots)
                    if (slots.isEmpty()) throw NativeReadEmpty()
                }
                // Metadata has been persisted before any identity comparison. No slot-number equality is imposed.
            }
        } catch (caught: Throwable) {
            failure = caught
            receipt.put("observationOutcome", nativeReadFailure(caught).value)
            if (!receipt.has("clientSlots")) receipt.put("metadataOutcome",
                receipt.getJSONObject("operations").getJSONObject("clientSlots").getString("outcome"))
        } finally {
            // Retain useful metadata even when the after-observation fails or the face changes.
            before?.let { original ->
                val after = optionalOperation("afterFace", "active system/native instance", "system/native/resource/instance scope") {
                    readNativeClientFace(device, expected, receipt, persist, "after").also { receipt.put("afterFace", it.json()) }
                }
                val current = optionalOperation("afterIdentity", HOST_PACKAGE, "current caller UID/package/APK/signer") {
                    admission.currentIdentity().also { receipt.put("afterIdentity", it) }
                }
                val currentResources = optionalOperation("afterResource", original.renderer.resourcePackage,
                    "installed resource/runtime APK identities") {
                    admission.resourceIdentity(original.renderer.resourcePackage).also { receipt.put("afterResource", it) }
                }
                receipt.put("stableBracket", after != null && current != null && currentResources != null &&
                    original.sameScope(after) && identity.toString() == current.toString() &&
                    resources.toString() == currentResources.toString())
                if (receipt.has("returnedClientInstance")) receipt.put("returnedInstanceMatches",
                    receipt.getString("returnedClientInstance") == original.renderer.instance)
                // Stable instants and an instance match do not establish a cross-domain slot mapping.
            }
            persist()
        }
        if (failure != null) throw AssertionError("Pending: client metadata acquisition or custody; retain private receipts for HOST review.")
        instrumentation.sendStatus(0, Bundle().apply {
            putString("stream", "\nClient metadata recorded privately; slot-domain association and runtime acceptance remain Pending.\n")
        })
    }
}
