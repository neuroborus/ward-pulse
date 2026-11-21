package app.wardpulse.wear.nativeintegration

import android.os.Bundle
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import app.wardpulse.wear.watchface.AndroidWatchFacePushClient
import app.wardpulse.wear.watchface.InstalledWatchFace
import app.wardpulse.wear.watchface.WatchFaceInventory
import app.wardpulse.wear.watchface.WatchFacePushClient
import com.google.android.gms.tasks.Tasks
import com.google.android.gms.wearable.Wearable
import java.io.File
import java.util.UUID
import java.util.concurrent.ExecutionException
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Test
import org.junit.runner.RunWith

internal const val INVENTORY_READ_CLASS = "app.wardpulse.wear.nativeintegration.NativeInventoryObservationTest"

internal enum class NativeInventoryRead(val method: String, val optIn: String, val operations: List<String>) {
    PUSH("observeOwnedPushInventory", "owned-push", listOf("pushSupport", "inventory", "active", "afterInventory")),
    PEERS("observeConnectedPeers", "connected-peers", listOf("connectedPeers")),
}

internal fun nativeInventoryReceipt(read: NativeInventoryRead) = JSONObject()
    .put("kind", "read-only-${read.optIn}")
    .put("metadataOutcome", NativeReadOutcome.NOT_INVOKED.value)
    .put("operations", JSONObject().apply {
        (listOf("admission", "afterIdentity") + read.operations).forEach {
            put(it, nativeReadOperation(HOST_PACKAGE, "not yet observed"))
        }
        if (read == NativeInventoryRead.PUSH) {
            put("active", nativeReadOperation(CANDIDATE_PACKAGE, "Push active status for caller-owned package"))
        }
    })

private fun InstalledWatchFace.json() = JSONObject().put("packageName", packageName)
    .put("versionCode", versionCode).put("managerSlotId", slotId)

private fun WatchFaceInventory.json() = JSONObject().put("remainingSlots", remainingSlots)
    .put("faces", JSONArray(faces.map { it.json() }))

/** No bundle, journal, active-face join or mutation authority is acquired by these reads. */
internal fun readNativeOwnedPush(receipt: JSONObject, persist: () -> Unit, client: WatchFacePushClient) {
    try {
        nativeClientOperation(receipt, persist, "pushSupport", HOST_PACKAGE, "Push SDK support") {
            client.isSupported().also {
                receipt.put("pushSupported", it)
                if (!it) throw UnsupportedOperationException()
            }
        }
        fun inventory(name: String) = nativeClientOperation(receipt, persist, name, HOST_PACKAGE,
            "caller-owned Push package/version/manager-slot inventory") {
            runBlocking { withTimeout(5_000) { client.list() } }.also { result ->
                // Keep actual returns even when consistency/ownership cannot be established.
                receipt.put(name, result.json())
                nativeGuard(result.remainingSlots >= 0 && result.faces.all {
                    it.packageName.isNotBlank() && it.slotId.isNotBlank() && it.versionCode > 0
                } && result.faces.map { it.slotId }.distinct().size == result.faces.size &&
                    result.faces.map { it.packageName }.distinct().size == result.faces.size, "read-push-inventory")
            }
        }.also { result ->
            if (result.faces.isEmpty()) {
                receipt.getJSONObject("operations").getJSONObject(name).put("outcome", NativeReadOutcome.EMPTY.value)
                persist()
            }
        }
        val before = inventory("inventory")
        val owned = before.faces.singleOrNull { it.packageName == CANDIDATE_PACKAGE }
        receipt.put("ownedPush", owned?.json() ?: JSONObject.NULL)
            .put("ownedPushOutcome", if (owned == null) NativeReadOutcome.EMPTY.value else NativeReadOutcome.ACQUIRED.value)
        persist()
        if (owned != null) {
            nativeClientOperation(receipt, persist, "active", owned.packageName, "Push active status for caller-owned package") {
                receipt.put("active", runBlocking { withTimeout(5_000) { client.isActive(owned.packageName) } })
            }
        }
        val after = inventory("afterInventory")
        val stable = before.remainingSlots == after.remainingSlots && before.faces.toSet() == after.faces.toSet()
        receipt.put("inventoryStable", stable)
        nativeGuard(stable, "read-push-inventory-changed")
        receipt.put("metadataOutcome", if (before.faces.isEmpty()) NativeReadOutcome.EMPTY.value else NativeReadOutcome.ACQUIRED.value)
        persist()
    } catch (failure: Throwable) {
        if (receipt.getString("metadataOutcome") == NativeReadOutcome.NOT_INVOKED.value) {
            receipt.put("metadataOutcome", nativeReadFailure(failure).value)
        }
        throw failure
    }
}

internal data class NativeConnectedPeer(val id: String, val displayName: String, val nearby: Boolean) {
    fun json() = JSONObject().put("id", id).put("displayName", displayName).put("isNearby", nearby)
}

internal fun readNativeConnectedPeers(receipt: JSONObject, persist: () -> Unit,
    acquire: () -> List<NativeConnectedPeer>?) {
    try {
        nativeClientOperation(receipt, persist, "connectedPeers", HOST_PACKAGE,
            "NodeClient connected remote nodes; not GMS connection-category flags") {
            val peers = try { acquire() } catch (failure: ExecutionException) { throw failure.cause ?: failure }
            receipt.put("peers", peers?.let { JSONArray(it.map { peer -> peer.json() }) } ?: JSONObject.NULL)
            receipt.put("metadataOutcome", if (peers.isNullOrEmpty()) NativeReadOutcome.EMPTY.value else NativeReadOutcome.ACQUIRED.value)
        }
        receipt.getJSONObject("operations").getJSONObject("connectedPeers")
            .put("outcome", receipt.getString("metadataOutcome"))
        persist()
    } catch (failure: Throwable) {
        if (receipt.getString("metadataOutcome") == NativeReadOutcome.NOT_INVOKED.value) {
            receipt.put("metadataOutcome", nativeReadFailure(failure).value)
        }
        throw failure
    }
}

/** Individually selected observations under the actual provider-app UID; no messages or mutations. */
@ManualNativeIntegration
@RunWith(AndroidJUnit4::class)
class NativeInventoryObservationTest {
    @Test
    fun observeOwnedPushInventory() { observe(NativeInventoryRead.PUSH) }

    @Test
    fun observeConnectedPeers() { observe(NativeInventoryRead.PEERS) }

    private fun observe(read: NativeInventoryRead) {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val context = instrumentation.targetContext
        val admission = NativeReadAdmission(instrumentation, NativePushExpectations(InstrumentationRegistry.getArguments()))
        val directory = File(context.filesDir, "native_read/${read.optIn}-${UUID.randomUUID()}")
        nativeGuard(directory.mkdirs(), "fresh-read-only-inventory-receipt")
        val receipt = nativeInventoryReceipt(read)
        val journal = AttemptJournal(File(directory, "receipt.json"))
        val persist = { journal.persist(receipt) }
        var identity: JSONObject? = null
        var failure: Throwable? = null
        persist()
        try {
            identity = nativeClientOperation(receipt, persist, "admission", HOST_PACKAGE, "current caller UID/package/APK/signer") {
                admission.admit(read.method, INVENTORY_READ_CLASS, read.optIn).also { receipt.put("identity", it) }
            }
            when (read) {
                NativeInventoryRead.PUSH -> readNativeOwnedPush(receipt, persist, AndroidWatchFacePushClient(context))
                NativeInventoryRead.PEERS -> readNativeConnectedPeers(receipt, persist) {
                    // Await only the read task. No refresh requester or MessageClient is involved.
                    Tasks.await(Wearable.getNodeClient(context).connectedNodes, 5, TimeUnit.SECONDS)
                        ?.map { NativeConnectedPeer(it.id, it.displayName, it.isNearby) }
                }
            }
        } catch (caught: Throwable) {
            failure = caught
        } finally {
            if (identity != null) {
                try {
                    nativeClientOperation(receipt, persist, "afterIdentity", HOST_PACKAGE, "current caller UID/package/APK/signer") {
                        val current = admission.currentIdentity()
                        receipt.put("afterIdentity", current)
                        nativeGuard(identity.toString() == current.toString(), "read-caller-changed")
                    }
                } catch (caught: Throwable) {
                    if (failure == null) failure = caught else failure.addSuppressed(caught)
                }
            }
            receipt.put("observationOutcome", failure?.let { nativeReadFailure(it).value } ?: receipt.getString("metadataOutcome"))
            persist()
        }
        if (failure != null) throw AssertionError("Pending: inventory observation; retain private receipts for HOST review.")
        instrumentation.sendStatus(0, Bundle().apply {
            putString("stream", "\nRead-only inventory recorded privately; runtime acceptance and producer quiescence remain Pending.\n")
        })
    }
}
