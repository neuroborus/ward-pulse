package app.wardpulse.wear.nativeintegration

import android.content.ComponentName
import android.content.ContextWrapper
import android.content.Intent
import android.content.ServiceConnection
import android.os.Bundle
import android.os.IBinder
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import androidx.wear.watchface.complications.data.NoDataComplicationData
import androidx.wear.watchface.complications.data.RangedValueComplicationData
import java.io.File
import java.time.Instant
import java.util.UUID
import java.util.concurrent.Executor
import java.util.concurrent.TimeoutException
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

/** Synthetic bindings and objects only. These cases cannot authorize a native override. */
@ManualNativeIntegration
@RunWith(AndroidJUnit4::class)
class NativeClientGuardTest {
    @Test
    fun currentReadAdmissionNeedsCallerAuthorityWithoutHistoricalUpdateInputs() {
        val arguments = Bundle().apply {
            putString("class", "$CLIENT_METADATA_CLASS#observeClientMetadata")
            putString("wardpulseNativeIntegration", "client-metadata")
            putString("expectedAvd", "wardpulse_wear_round_api36_1")
            putString("expectedCallerUid", "10021")
            putString("expectedHostVersionCode", "17")
            putString("expectedHostApkSha256", "a".repeat(64))
            putString("expectedHostSignerSha256", "b".repeat(64))
        }
        val expected = NativePushExpectations(arguments)
        fun admit(runner: String = "androidx.test.runner.AndroidJUnitRunner", method: String = "observeClientMetadata",
            avd: String = "wardpulse_wear_round_api36_1") =
            expected.admit(method, runner, avd, "1", true, CLIENT_METADATA_CLASS, "client-metadata")
        val host = NativePackage(17L, "a".repeat(64), "b".repeat(64))
        fun caller(uid: Int = 10021, packages: Set<String> = setOf(HOST_PACKAGE), current: NativePackage = host) =
            requireNativeReadCaller(uid, 10021, packages, current, expected)
        admit()
        caller() // No asset-3, installed Push, manager witness, requester IDs or quiet bridge input exists.
        assertThrows(NativePending::class.java) { admit(runner = "app.wardpulse.wear.IsolatedWearRunner") }
        assertThrows(NativePending::class.java) { admit(method = "observeOverride") }
        assertThrows(NativePending::class.java) { admit(avd = "other") }
        arguments.putString("wardpulseNativeIntegration", "client-probe")
        assertThrows(NativePending::class.java) { admit() }
        assertThrows(NativePending::class.java) { caller(uid = 10022) }
        assertThrows(NativePending::class.java) { caller(packages = setOf(HOST_PACKAGE, "other.package")) }
        assertThrows(NativePending::class.java) { caller(current = host.copy(apk = "c".repeat(64))) }
        assertThrows(NativePending::class.java) { caller(current = host.copy(signer = "c".repeat(64))) }
    }

    @Test
    fun metadataRetainsDifferentClientSlotDomainsButCannotAuthorizeAnOverride() {
        val receipt = nativeClientMetadataReceipt()
        recordNativeClientSlots(receipt, listOf(
            NativeClientSlotMetadata(105, false, listOf("SHORT_TEXT")),
            NativeClientSlotMetadata(101, true, listOf("RANGED_VALUE")),
        ))
        val slots = receipt.getJSONArray("clientSlots")
        assertEquals(101, slots.getJSONObject(0).getInt("clientSlotKey"))
        assertTrue(slots.getJSONObject(0).getBoolean("enabled"))
        assertEquals("RANGED_VALUE", slots.getJSONObject(0).getJSONArray("supportedTypes").getString(0))
        assertEquals(105, slots.getJSONObject(1).getInt("clientSlotKey"))
        assertFalse(slots.getJSONObject(1).getBoolean("enabled"))
        assertEquals(NativeReadOutcome.ACQUIRED.value, receipt.getString("metadataOutcome"))
        assertEquals(NativeReadOutcome.UNRESOLVED.value, receipt.getString("slotAssociation"))
        // Even matching identity and successful cleanup do not make a metadata receipt a guarded probe.
        val identity = JSONObject().put("instance", "synthetic-instance")
        receipt.put("identity", identity).put("interactiveCleanup", "close returned")
            .put("controlCleanup", "close returned").put("controlBindingCleanup", "tracked connections released")
        assertThrows(NativePending::class.java) { requireGuardedNativeClientProbe(receipt, identity) }
        val misleading = JSONObject(receipt.toString()).put("state", "probe returned; first-frame and restoration review Pending")
        assertThrows(NativePending::class.java) { requireGuardedNativeClientProbe(misleading, identity) }
        val guarded = JSONObject().put("identity", identity)
            .put("state", "probe returned; first-frame and restoration review Pending")
            .put("interactiveCleanup", "close returned").put("controlCleanup", "close returned")
            .put("controlBindingCleanup", "tracked connections released")
        requireGuardedNativeClientProbe(guarded, identity)
        guarded.put("outcome", "Pending")
        assertThrows(NativePending::class.java) { requireGuardedNativeClientProbe(guarded, identity) }
        recordNativeClientSlots(receipt, emptyList())
        assertEquals(NativeReadOutcome.EMPTY.value, receipt.getString("metadataOutcome"))
    }

    @Test
    fun operationReceiptsDistinguishUninvokedEmptyDeniedTimeoutAndUnresolvedCalls() {
        val failures = listOf(
            UnsupportedOperationException() to NativeReadOutcome.UNSUPPORTED,
            NativeReadEmpty() to NativeReadOutcome.EMPTY,
            SecurityException() to NativeReadOutcome.INACCESSIBLE,
            TimeoutException() to NativeReadOutcome.TIMEOUT,
            IllegalArgumentException() to NativeReadOutcome.UNRESOLVED,
            NativePending("synthetic-domain-unresolved") to NativeReadOutcome.UNRESOLVED,
        )
        for ((failure, outcome) in failures) {
            val receipt = nativeClientMetadataReceipt()
            val slots = receipt.getJSONObject("operations").getJSONObject("clientSlots")
            assertFalse(slots.getBoolean("invoked"))
            assertEquals(NativeReadOutcome.NOT_INVOKED.value, slots.getString("outcome"))
            var writes = 0
            val persist = { writes++; Unit }
            nativeClientOperation(receipt, persist, "controlAcquisition", "runtime", "control reference") { Unit }
            assertThrows(failure.javaClass) {
                nativeClientOperation(receipt, persist, "interactiveAcquisition", "instance", "interactive reference") {
                    assertEquals(3, writes) // The second invocation is durably recorded before its effect.
                    throw failure
                }
            }
            val operations = receipt.getJSONObject("operations")
            assertEquals(NativeReadOutcome.ACQUIRED.value, operations.getJSONObject("controlAcquisition").getString("outcome"))
            assertEquals(outcome.value, operations.getJSONObject("interactiveAcquisition").getString("outcome"))
            assertEquals("instance", operations.getJSONObject("interactiveAcquisition").getString("target"))
            assertFalse(slots.getBoolean("invoked"))
        }
        for (failAt in listOf(1, 2)) {
            val receipt = nativeClientMetadataReceipt()
            var writes = 0
            var calls = 0
            assertThrows(IllegalStateException::class.java) {
                nativeClientOperation(receipt, {
                    if (++writes == failAt) throw IllegalStateException("Synthetic recording failure")
                }, "clientSlots", "instance", "client slots") { calls++ }
            }
            val operation = receipt.getJSONObject("operations").getJSONObject("clientSlots")
            assertEquals(if (failAt == 1) 0 else 1, calls)
            assertEquals(failAt == 2, operation.getBoolean("invoked"))
            assertEquals(if (failAt == 1) NativeReadOutcome.NOT_INVOKED.value else NativeReadOutcome.ACQUIRED.value,
                operation.getString("outcome"))
        }
    }

    @Test
    fun cleanupAttemptsEveryResourceAndUnreturnedOrFailedOwnershipBlocksAnotherOwner() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        for (scenario in listOf("partial-control", "partial-interactive", "interactive-close", "control-close",
            "binding-close", "persist", "success")) {
            val directory = File(context.cacheDir, "synthetic-client-custody-${UUID.randomUUID()}")
            try {
                val custody = NativeClientCustody(directory)
                custody.acquire("synthetic.resource", "synthetic-instance")
                assertThrows(NativePending::class.java) {
                    NativeClientCustody(directory).acquire("synthetic.resource", "synthetic-instance")
                }
                val receipt = JSONObject()
                val closed = mutableListOf<String>()
                fun close(resource: String) {
                    closed += resource
                    if (scenario == "$resource-close") throw IllegalStateException("Synthetic close failure")
                }
                val interactive: (() -> Unit)? = if (scenario.startsWith("partial-")) null else { { close("interactive") } }
                val control: (() -> Unit)? = if (scenario == "partial-control") null else { { close("control") } }
                val resolved = cleanupNativeClient(receipt, {
                    if (scenario == "persist") throw IllegalStateException("Synthetic persistence failure")
                }, interactive, control, { close("binding") }, scenario == "partial-interactive", scenario == "partial-control")
                assertEquals(scenario == "success", resolved)
                assertEquals(listOfNotNull(if (interactive != null) "interactive" else null,
                    if (control != null) "control" else null, "binding"), closed)
                custody.finish(resolved)
                if (resolved) {
                    val next = NativeClientCustody(directory)
                    next.acquire("synthetic.resource", "synthetic-instance")
                    next.finish(true)
                } else {
                    assertThrows(NativePending::class.java) {
                        NativeClientCustody(directory).acquire("synthetic.resource", "synthetic-instance")
                    }
                    if (scenario.endsWith("-close")) assertEquals("cleanup failed; ownership Pending",
                        receipt.getString(when (scenario) {
                            "interactive-close" -> "interactiveCleanup"
                            "control-close" -> "controlCleanup"
                            else -> "controlBindingCleanup"
                        }))
                }
            } finally {
                // These are synthetic resources only; no remote reference exists to reconcile.
                assertTrue(directory.deleteRecursively())
            }
        }
    }

    @Test
    fun activeFaceBracketsRejectChangedSystemInstanceConfigurationAndNativeScope() {
        val system = NativeSystem(0, 0, ComponentName("synthetic.runtime", "SyntheticRuntime"),
            "user", "connection", "engine", "service", "token")
        val renderer = NativeRenderer("synthetic.resource", "instance", "style", mapOf(11 to true), emptyMap(),
            runtime = "SyntheticRuntime", nativeScope = listOf("native-engine"))
        val before = NativeReadFace(system, renderer, "configuration-hash")
        assertTrue(before.sameScope(before.copy()))
        for (after in listOf(before.copy(system = system.copy(connection = "changed")),
            before.copy(renderer = renderer.copy(instance = "changed")),
            before.copy(renderer = renderer.copy(enabled = mapOf(11 to false))),
            before.copy(renderer = renderer.copy(nativeScope = listOf("changed"))),
            before.copy(configurationSha256 = "changed"), before.copy(configurationSha256 = null))) {
            assertFalse(before.sameScope(after))
        }
    }

    @Test
    fun executorAndPartialFactoryBindingsAreReleasedEvenWithoutAReturnedClient() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val connection = object : ServiceConnection {
            override fun onServiceConnected(name: ComponentName, service: IBinder) = Unit
            override fun onServiceDisconnected(name: ComponentName) = Unit
        }
        for (executor in listOf(false, true)) {
            for (failure in listOf("await", "denied", "guard", "returned")) {
                var binds = 0
                var unbinds = 0
                val base = object : ContextWrapper(context) {
                    private fun bind(): Boolean {
                        binds++
                        if (failure == "denied") throw SecurityException("Synthetic bind denial")
                        return true
                    }
                    override fun bindService(service: Intent, connection: ServiceConnection, flags: Int) = bind()
                    override fun bindService(service: Intent, flags: Int, executor: Executor,
                        connection: ServiceConnection) = bind()
                    override fun unbindService(connection: ServiceConnection) {
                        unbinds++
                        if (failure == "denied") throw IllegalArgumentException("No registered connection")
                    }
                }
                val binding = NativeClientBinding(base) {
                    nativeGuard(failure != "guard", "synthetic-client-service-guard")
                }
                try {
                    binding.use {
                        if (executor) it.bindService(Intent(), 0, Executor { task -> task.run() }, connection)
                        else it.bindService(Intent(), connection, 0)
                        if (failure == "returned") it.unbindService(connection)
                        throw NativePending("synthetic-pre-return-failure")
                    }
                } catch (_: NativePending) {
                    check(failure != "denied")
                } catch (_: SecurityException) {
                    assertEquals("denied", failure)
                }
                binding.close()
                assertEquals(failure != "guard", binding.bindAttempted)
                assertEquals(if (failure == "guard") 0 else 1, binds)
                assertEquals(if (failure == "guard") 0 else 1, unbinds)
            }
        }
    }

    @Test
    fun unsupportedGenericEnvelopeIsDistinctFromMalformedContractAndPartialNoData() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        fun target(slot: Int, systemId: Int, service: String) = NativeDeliveryTarget(slot, systemId,
            ComponentName(HOST_PACKAGE, "app.wardpulse.wear.complication.${service}ComplicationDataSourceService"))
        val targets = listOf(target(47, 901, "Today"), target(64, 902, "RingSplit"))
        val unsupported = nativeOverrideData("unsupported-range", targets)
        assertEquals(setOf(47), unsupported.keys)
        val ranged = unsupported.getValue(47) as RangedValueComplicationData
        assertEquals(0f, ranged.min, 0f)
        assertEquals(300f, ranged.max, 0f)
        assertEquals(111f, ranged.value, 0f)
        assertEquals(RangedValueComplicationData.TYPE_UNDEFINED, ranged.valueType)
        val malformed = nativeOverrideData("malformed-title", targets).getValue(47) as RangedValueComplicationData
        assertEquals(400f, malformed.max, 0f)
        assertEquals("invalid", malformed.title!!.getTextAt(context.resources, Instant.EPOCH).toString())
        assertEquals(setOf(47), nativeOverrideData("partial-no-data-main", targets).keys)
        val pair = nativeOverrideData("no-data-main-valid-extra", targets)
        assertEquals(setOf(47, 64), pair.keys)
        check(pair.getValue(47) is NoDataComplicationData)
        val extra = pair.getValue(64) as RangedValueComplicationData
        assertEquals("0", extra.title!!.getTextAt(context.resources, Instant.EPOCH).toString())
        assertEquals(400f, extra.max, 0f)
        assertThrows(NativePending::class.java) {
            nativeOverrideData("no-data-main-valid-extra", targets.take(1))
        }
        assertThrows(NativePending::class.java) { nativeOverrideData("unsupported-range", targets + targets.first()) }
        assertThrows(NativePending::class.java) { nativeOverrideData("unknown", targets) }
        val recovered = mutableListOf<ComponentName>()
        assertThrows(NativePending::class.java) {
            requestNormalClientData(targets.map { it.provider }) {
                recovered += it
                if (it == targets.first().provider) throw IllegalStateException("Synthetic first-request failure")
            }
        }
        assertEquals(targets.map { it.provider }, recovered)
    }
}
