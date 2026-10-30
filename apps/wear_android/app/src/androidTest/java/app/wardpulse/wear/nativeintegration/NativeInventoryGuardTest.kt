package app.wardpulse.wear.nativeintegration

import android.os.Bundle
import androidx.test.ext.junit.runners.AndroidJUnit4
import app.wardpulse.wear.watchface.InstalledWatchFace
import app.wardpulse.wear.watchface.WatchFaceBundle
import app.wardpulse.wear.watchface.WatchFaceInventory
import app.wardpulse.wear.watchface.WatchFacePushClient
import java.util.concurrent.ExecutionException
import java.util.concurrent.TimeoutException
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

/** Synthetic read results only; no Push manager, NodeClient, message transport or live state. */
@ManualNativeIntegration
@RunWith(AndroidJUnit4::class)
class NativeInventoryGuardTest {
    private val owned = InstalledWatchFace("opaque-manager-slot", CANDIDATE_PACKAGE, 4L)

    @Test
    fun independentReadsRequireTheirOwnMethodOptInAndCurrentCallerWithoutHistory() {
        for (read in NativeInventoryRead.entries) {
            val arguments = Bundle().apply {
                putString("class", "$INVENTORY_READ_CLASS#${read.method}")
                putString("wardpulseNativeIntegration", read.optIn)
                putString("expectedAvd", "wardpulse_wear_square_api36_1")
                putString("expectedCallerUid", "10021")
                putString("expectedHostVersionCode", "17")
                putString("expectedHostApkSha256", "a".repeat(64))
                putString("expectedHostSignerSha256", "b".repeat(64))
            }
            val expected = NativePushExpectations(arguments)
            fun admit(runner: String = "androidx.test.runner.AndroidJUnitRunner") = expected.admit(
                read.method, runner, "wardpulse_wear_square_api36_1", "1", true, INVENTORY_READ_CLASS, read.optIn)
            admit()
            val host = NativePackage(17L, "a".repeat(64), "b".repeat(64))
            requireNativeReadCaller(10021, 10021, setOf(HOST_PACKAGE), host, expected)
            assertThrows(NativePending::class.java) {
                requireNativeReadCaller(10021, 10021, setOf(HOST_PACKAGE), host.copy(apk = "c".repeat(64)), expected)
            }
            assertThrows(NativePending::class.java) {
                requireNativeReadCaller(10022, 10021, setOf(HOST_PACKAGE), host, expected)
            }
            assertThrows(NativePending::class.java) { admit("app.wardpulse.wear.IsolatedWearRunner") }
            arguments.putString("class", INVENTORY_READ_CLASS)
            assertThrows(NativePending::class.java) { admit() }
            arguments.putString("class", "$INVENTORY_READ_CLASS#${read.method}")
            arguments.putString("wardpulseNativeIntegration", "push-3-to-4")
            assertThrows(NativePending::class.java) { admit() }
            val receipt = nativeInventoryReceipt(read)
            val identity = JSONObject().put("instance", "synthetic-instance")
            receipt.put("identity", identity).put("state", "probe returned; first-frame and restoration review Pending")
                .put("interactiveCleanup", "close returned").put("controlCleanup", "close returned")
                .put("controlBindingCleanup", "tracked connections released")
            assertThrows(NativePending::class.java) { requireGuardedNativeClientProbe(receipt, identity) }
        }
    }

    @Test
    fun ownedPackageVersionAndManagerSlotRemainSeparateFromActiveStatus() {
        val other = InstalledWatchFace("another-manager-slot", "synthetic.other.face", 23L)
        val client = ReadOnlyPush(WatchFaceInventory(listOf(owned, other), 0)).apply {
            after = WatchFaceInventory(listOf(other, owned), 0)
        }
        val receipt = nativeInventoryReceipt(NativeInventoryRead.PUSH)
        readNativeOwnedPush(receipt, {}, client)
        val row = receipt.getJSONObject("ownedPush")
        assertEquals(CANDIDATE_PACKAGE, row.getString("packageName"))
        assertEquals(4L, row.getLong("versionCode"))
        assertEquals("opaque-manager-slot", row.getString("managerSlotId"))
        assertEquals(2, receipt.getJSONObject("inventory").getJSONArray("faces").length())
        assertFalse(receipt.getBoolean("active"))
        assertEquals(CANDIDATE_PACKAGE, client.activePackage)
        assertTrue(receipt.getBoolean("inventoryStable"))
        assertEquals(NativeReadOutcome.ACQUIRED.value, receipt.getString("metadataOutcome"))
        assertEquals(listOf("support", "inventory", "active", "afterInventory"), client.calls)
    }

    @Test
    fun emptyOrUnownedInventoryNeverInvokesActiveOrOpensABundle() {
        for (faces in listOf(emptyList(), listOf(owned.copy(packageName = "synthetic.other.face")))) {
            val receipt = nativeInventoryReceipt(NativeInventoryRead.PUSH)
            val client = ReadOnlyPush(WatchFaceInventory(faces, 1))
            readNativeOwnedPush(receipt, {}, client)
            assertTrue(receipt.isNull("ownedPush"))
            assertEquals(NativeReadOutcome.EMPTY.value, receipt.getString("ownedPushOutcome"))
            assertFalse(receipt.has("active"))
            val operation = receipt.getJSONObject("operations").getJSONObject("active")
            assertFalse(operation.getBoolean("invoked"))
            assertEquals(NativeReadOutcome.NOT_INVOKED.value, operation.getString("outcome"))
            assertEquals(listOf("support", "inventory", "afterInventory"), client.calls)
            assertEquals(if (faces.isEmpty()) NativeReadOutcome.EMPTY.value else NativeReadOutcome.ACQUIRED.value,
                receipt.getString("metadataOutcome"))
        }
    }

    @Test
    fun unsupportedDeniedAndTimedOutPushReadsRetainUninvokedBoundaries() {
        for ((step, error, outcome) in listOf(
            Triple("support", UnsupportedOperationException(), NativeReadOutcome.UNSUPPORTED),
            Triple("inventory", SecurityException(), NativeReadOutcome.INACCESSIBLE),
            Triple("inventory", TimeoutException(), NativeReadOutcome.TIMEOUT),
            Triple("active", SecurityException(), NativeReadOutcome.INACCESSIBLE),
            Triple("afterInventory", SecurityException(), NativeReadOutcome.INACCESSIBLE))) {
            val receipt = nativeInventoryReceipt(NativeInventoryRead.PUSH)
            val client = ReadOnlyPush(WatchFaceInventory(listOf(owned), 1)).apply {
                supported = step != "support"
                if (step != "support") { failAt = step; failure = error }
            }
            assertThrows(error.javaClass) { readNativeOwnedPush(receipt, {}, client) }
            assertEquals(outcome.value, receipt.getString("metadataOutcome"))
            val operations = receipt.getJSONObject("operations")
            val name = if (step == "support") "pushSupport" else step
            assertEquals(outcome.value, operations.getJSONObject(name).getString("outcome"))
            assertEquals(step == "afterInventory", operations.getJSONObject("afterInventory").getBoolean("invoked"))
            if (step !in setOf("active", "afterInventory")) assertFalse(operations.getJSONObject("active").getBoolean("invoked"))
            else assertEquals(4L, receipt.getJSONObject("ownedPush").getLong("versionCode"))
        }
    }

    @Test
    fun invalidOrChangedInventoryRetainsRawReturnsWithoutClaimingConsistency() {
        for (result in listOf(WatchFaceInventory(listOf(owned, owned), 1),
            WatchFaceInventory(listOf(owned), -1), WatchFaceInventory(listOf(owned.copy(versionCode = 0)), 1))) {
            val receipt = nativeInventoryReceipt(NativeInventoryRead.PUSH)
            val client = ReadOnlyPush(result)
            assertThrows(NativePending::class.java) { readNativeOwnedPush(receipt, {}, client) }
            assertEquals(result.faces.size, receipt.getJSONObject("inventory").getJSONArray("faces").length())
            assertEquals(listOf("support", "inventory"), client.calls)
        }
        val receipt = nativeInventoryReceipt(NativeInventoryRead.PUSH)
        val client = ReadOnlyPush(WatchFaceInventory(listOf(owned), 1)).apply {
            after = WatchFaceInventory(listOf(owned.copy(slotId = "changed-manager-slot")), 1)
        }
        assertThrows(NativePending::class.java) { readNativeOwnedPush(receipt, {}, client) }
        assertFalse(receipt.getBoolean("inventoryStable"))
        assertTrue(receipt.has("afterInventory"))
        assertEquals(NativeReadOutcome.UNRESOLVED.value, receipt.getString("metadataOutcome"))
    }

    @Test
    fun peerResultsKeepNullEmptyRemoteIdentityAndFailureOutcomesWithoutMessages() {
        val peer = NativeConnectedPeer("remote-node", "Synthetic peer", false)
        for (peers in listOf(null, emptyList(), listOf(peer))) {
            val receipt = nativeInventoryReceipt(NativeInventoryRead.PEERS)
            var calls = 0
            readNativeConnectedPeers(receipt, {}) { calls++; peers }
            assertEquals(1, calls)
            assertEquals(if (peers.isNullOrEmpty()) NativeReadOutcome.EMPTY.value else NativeReadOutcome.ACQUIRED.value,
                receipt.getString("metadataOutcome"))
            if (peers == null) assertTrue(receipt.isNull("peers"))
            else assertEquals(peers.size, receipt.getJSONArray("peers").length())
            if (!peers.isNullOrEmpty()) {
                val row = receipt.getJSONArray("peers").getJSONObject(0)
                assertEquals(peer.id, row.getString("id"))
                assertEquals(peer.displayName, row.getString("displayName"))
                assertFalse(row.getBoolean("isNearby"))
            }
            assertFalse(receipt.has("quietWriters"))
        }
        for ((error, outcome) in listOf(ExecutionException(SecurityException()) to NativeReadOutcome.INACCESSIBLE,
            TimeoutException() to NativeReadOutcome.TIMEOUT, UnsupportedOperationException() to NativeReadOutcome.UNSUPPORTED)) {
            val receipt = nativeInventoryReceipt(NativeInventoryRead.PEERS)
            assertThrows(Exception::class.java) { readNativeConnectedPeers(receipt, {}) { throw error } }
            assertFalse(receipt.has("peers"))
            assertEquals(outcome.value, receipt.getString("metadataOutcome"))
            val operation = receipt.getJSONObject("operations").getJSONObject("connectedPeers")
            assertTrue(operation.getBoolean("invoked"))
            assertEquals(outcome.value, operation.getString("outcome"))
        }
    }

    private class ReadOnlyPush(val inventory: WatchFaceInventory) : WatchFacePushClient {
        val calls = mutableListOf<String>()
        var supported = true
        var after = inventory
        var failAt: String? = null
        var failure: Throwable = SecurityException()
        var activePackage: String? = null
        private fun call(name: String) { calls += name; if (failAt == name) throw failure }
        private fun unexpected(name: String): Nothing { call(name); error("Unexpected effect: $name") }
        override val sdkInt: Int get() = unexpected("sdkInt")
        override fun isSupported(): Boolean { call("support"); return supported }
        override suspend fun list(): WatchFaceInventory {
            val first = "inventory" !in calls
            call(if (first) "inventory" else "afterInventory")
            return if (first) inventory else after
        }
        override suspend fun isActive(packageName: String): Boolean {
            call("active"); activePackage = packageName; return false
        }
        override fun isSeparateFaceInstalled(): Boolean = unexpected("separate-package")
        override fun openBundle(): WatchFaceBundle = unexpected("open-bundle")
        override suspend fun install(bundle: WatchFaceBundle): InstalledWatchFace = unexpected("install")
        override suspend fun update(slotId: String, bundle: WatchFaceBundle): InstalledWatchFace = unexpected("update")
        override fun hasActivationPermission(): Boolean = unexpected("permission")
        override suspend fun activate(slotId: String): Unit = unexpected("activate")
    }
}
