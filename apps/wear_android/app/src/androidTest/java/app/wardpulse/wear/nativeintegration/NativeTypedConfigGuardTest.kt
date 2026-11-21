package app.wardpulse.wear.nativeintegration

import android.content.ComponentName
import android.os.Bundle
import android.os.OutcomeReceiver
import androidx.test.ext.junit.runners.AndroidJUnit4
import java.util.concurrent.CompletableFuture
import java.util.concurrent.TimeoutException
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

/** Synthetic callback/config records only; no OS producer, SDK access or mutation is exercised. */
@ManualNativeIntegration
@RunWith(AndroidJUnit4::class)
class NativeTypedConfigGuardTest {
    private val config = NativeTypedConfig(407, 903, ComponentName(HOST_PACKAGE, "SyntheticProvider"),
        "synthetic.resource", null, 5)

    private fun completedConfigs(result: CompletableFuture<List<NativeTypedConfig>?>): List<NativeTypedConfig>? {
        assertTrue("Synthetic callback must complete before awaiting", result.isDone)
        return result.get()
    }

    @Test
    fun ownProviderAdmissionNeedsNoPushHistoryRequesterOrBridgeInputs() {
        val arguments = Bundle().apply {
            putString("class", "$TYPED_CONFIG_CLASS#observeActiveComplicationConfigs")
            putString("wardpulseNativeIntegration", "typed-configs")
            putString("expectedAvd", "wardpulse_wear_square_api36_1")
            putString("expectedCallerUid", "10021")
            putString("expectedHostVersionCode", "17")
            putString("expectedHostApkSha256", "a".repeat(64))
            putString("expectedHostSignerSha256", "b".repeat(64))
        }
        val expected = NativePushExpectations(arguments)
        fun admit(runner: String = "androidx.test.runner.AndroidJUnitRunner") = expected.admit(
            "observeActiveComplicationConfigs", runner, "wardpulse_wear_square_api36_1", "1", true,
            TYPED_CONFIG_CLASS, "typed-configs")
        admit()
        val host = NativePackage(17L, "a".repeat(64), "b".repeat(64))
        requireNativeReadCaller(10021, 10021, setOf(HOST_PACKAGE), host, expected)
        assertThrows(NativePending::class.java) {
            requireNativeReadCaller(10022, 10021, setOf(HOST_PACKAGE), host, expected)
        }
        assertThrows(NativePending::class.java) { admit("app.wardpulse.wear.IsolatedWearRunner") }
        arguments.putString("wardpulseNativeIntegration", "client-metadata")
        assertThrows(NativePending::class.java) { admit() }
    }

    @Test
    fun unavailableNullDeniedAndEmptyResultsRetainInvocationBoundaries() {
        for ((scenario, outcome) in listOf("unavailable" to NativeReadOutcome.UNSUPPORTED,
            "missing-class" to NativeReadOutcome.UNSUPPORTED, "manager-null" to NativeReadOutcome.EMPTY,
            "acquire-denied" to NativeReadOutcome.INACCESSIBLE, "callback-denied" to NativeReadOutcome.INACCESSIBLE,
            "empty" to NativeReadOutcome.EMPTY, "null" to NativeReadOutcome.EMPTY)) {
            val receipt = nativeTypedConfigReceipt()
            val failure = when (scenario) {
                "unavailable" -> UnsupportedOperationException::class.java
                "missing-class" -> NoClassDefFoundError::class.java
                "acquire-denied", "callback-denied" -> SecurityException::class.java
                else -> NativeReadEmpty::class.java
            }
            assertThrows(failure) {
                readNativeTypedConfigs(receipt, {}, supported = {
                    if (scenario == "missing-class") throw NoClassDefFoundError()
                    scenario != "unavailable"
                }, acquire = {
                    if (scenario == "manager-null") null else {
                        if (scenario == "acquire-denied") throw SecurityException()
                        NativeTypedConfigReader { receiver ->
                            when (scenario) {
                                "callback-denied" -> receiver.onError(SecurityException())
                                "null" -> receiver.onResult(null)
                                else -> receiver.onResult(emptyList())
                            }
                        }
                    }
                }, await = ::completedConfigs)
            }
            assertEquals(outcome.value, receipt.getString("metadataOutcome"))
            val operations = receipt.getJSONObject("operations")
            val available = scenario !in setOf("unavailable", "missing-class")
            val readInvoked = scenario in setOf("callback-denied", "empty", "null")
            assertEquals(available, operations.getJSONObject("managerAcquisition").getBoolean("invoked"))
            val read = operations.getJSONObject("activeConfigs")
            assertEquals(readInvoked, read.getBoolean("invoked"))
            assertEquals(if (readInvoked) outcome.value else NativeReadOutcome.NOT_INVOKED.value, read.getString("outcome"))
            if (scenario == "empty") assertEquals(0, receipt.getJSONArray("configs").length())
            else if (scenario == "null") assertTrue(receipt.has("configs") && receipt.isNull("configs"))
            else assertFalse(receipt.has("configs"))
        }
    }

    @Test
    fun returnedDomainsAndWffNullClassStayRawAndCannotAuthorizeMutation() {
        val receipt = nativeTypedConfigReceipt()
        readNativeTypedConfigs(receipt, {}, { true }, {
            NativeTypedConfigReader { it.onResult(listOf(config, config.copy(id = 408, watchFaceSlotId = 11,
                watchFaceClass = "SyntheticFace", dataType = 3))) }
        }, await = ::completedConfigs)
        val rows = receipt.getJSONArray("configs")
        assertEquals(407, rows.getJSONObject(0).getInt("id"))
        assertEquals(903, rows.getJSONObject(0).getInt("watchFaceSlotId"))
        assertEquals(config.provider!!.flattenToString(), rows.getJSONObject(0).getString("providerComponent"))
        assertEquals("synthetic.resource", rows.getJSONObject(0).getJSONObject("watchFaceId").getString("packageName"))
        assertTrue(rows.getJSONObject(0).getJSONObject("watchFaceId").isNull("className"))
        assertEquals(5, rows.getJSONObject(0).getInt("dataType"))
        assertEquals("SyntheticFace", rows.getJSONObject(1).getJSONObject("watchFaceId").getString("className"))
        assertEquals(11, rows.getJSONObject(1).getInt("watchFaceSlotId"))
        assertFalse(rows.getJSONObject(0).has("instance"))
        assertEquals(NativeReadOutcome.ACQUIRED.value, receipt.getString("metadataOutcome"))
        assertEquals(NativeReadOutcome.UNRESOLVED.value, receipt.getString("activeFaceAssociation"))
        val identity = JSONObject().put("instance", "synthetic-instance")
        receipt.put("identity", identity).put("state", "probe returned; first-frame and restoration review Pending")
            .put("interactiveCleanup", "close returned").put("controlCleanup", "close returned")
            .put("controlBindingCleanup", "tracked connections released")
        assertThrows(NativePending::class.java) { requireGuardedNativeClientProbe(receipt, identity) }
    }

    @Test
    fun callbackDeadlineAndDuplicateOrLateCompletionCannotRewriteTheReceipt() {
        val receipt = nativeTypedConfigReceipt()
        lateinit var callback: OutcomeReceiver<List<NativeTypedConfig>, Throwable>
        lateinit var pending: CompletableFuture<List<NativeTypedConfig>?>
        assertThrows(TimeoutException::class.java) {
            readNativeTypedConfigs(receipt, {}, { true }, { NativeTypedConfigReader { callback = it } }, await = {
                pending = it
                assertFalse(it.isDone)
                throw TimeoutException()
            })
        }
        assertTrue(pending.isCancelled)
        assertEquals(NativeReadOutcome.TIMEOUT.value, receipt.getString("metadataOutcome"))
        assertEquals(NativeReadOutcome.TIMEOUT.value,
            receipt.getJSONObject("operations").getJSONObject("activeConfigs").getString("outcome"))
        val terminal = receipt.toString()
        callback.onResult(listOf(config))
        callback.onError(SecurityException())
        assertEquals(terminal, receipt.toString())
        assertFalse(receipt.has("configs"))

        val acquired = nativeTypedConfigReceipt()
        readNativeTypedConfigs(acquired, {}, { true }, {
            NativeTypedConfigReader {
                it.onResult(listOf(config))
                it.onResult(emptyList())
                it.onError(SecurityException())
            }
        }, await = ::completedConfigs)
        assertEquals(407, acquired.getJSONArray("configs").getJSONObject(0).getInt("id"))
        assertEquals(NativeReadOutcome.ACQUIRED.value, acquired.getString("metadataOutcome"))
    }

    @Test
    fun changedOrMissingFaceBracketsKeepConfigsButLeaveAssociationUnresolved() {
        val system = NativeSystem(0, 0, ComponentName("synthetic.runtime", "SyntheticRuntime"),
            "user", "connection", "engine", "service", "token")
        val renderer = NativeRenderer("synthetic.resource", "instance", "style", mapOf(11 to true), emptyMap(),
            runtime = "SyntheticRuntime", nativeScope = listOf("native-engine"))
        val before = NativeReadFace(system, renderer, "configuration-hash")
        val receipt = nativeTypedConfigReceipt()
        readNativeTypedConfigs(receipt, {}, { true }, { NativeTypedConfigReader { it.onResult(listOf(config)) } },
            await = ::completedConfigs)
        val raw = receipt.getJSONArray("configs").toString()
        recordNativeTypedBracket(receipt, before, before.copy(), true, true)
        assertTrue(receipt.getBoolean("stableBracket"))
        assertEquals(NativeReadOutcome.UNRESOLVED.value, receipt.getString("activeFaceAssociation"))
        for (after in listOf(null, before.copy(system = system.copy(connection = "changed")),
            before.copy(renderer = renderer.copy(instance = "changed")),
            before.copy(renderer = renderer.copy(resourcePackage = "other.resource")),
            before.copy(renderer = renderer.copy(nativeScope = listOf("changed"))),
            before.copy(configurationSha256 = "changed"), before.copy(configurationSha256 = null))) {
            recordNativeTypedBracket(receipt, before, after, true, true)
            assertFalse(receipt.getBoolean("stableBracket"))
            assertEquals(raw, receipt.getJSONArray("configs").toString())
            assertEquals(NativeReadOutcome.ACQUIRED.value, receipt.getString("metadataOutcome"))
            assertEquals(NativeReadOutcome.UNRESOLVED.value, receipt.getString("activeFaceAssociation"))
        }
        recordNativeTypedBracket(receipt, before, before, false, true)
        assertFalse(receipt.getBoolean("stableBracket"))
        recordNativeTypedBracket(receipt, before, before, true, false)
        assertFalse(receipt.getBoolean("stableBracket"))
    }
}
