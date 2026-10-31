package app.wardpulse.wear.nativeintegration

import android.content.ComponentName
import android.os.Bundle
import android.os.OutcomeReceiver
import android.support.wearable.complications.ComplicationData as WireComplicationData
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import androidx.wear.watchface.complications.data.RangedValueComplicationData
import app.wardpulse.wear.ui.RingFamily
import com.google.wear.services.complications.PlainComplicationText
import java.io.File
import java.util.UUID
import java.util.concurrent.TimeoutException
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

/** Private synthetic evidence/dispatch only. Public builders are exercised without a live manager. */
@ManualNativeIntegration
@RunWith(AndroidJUnit4::class)
class NativeSdkDirectDataGuardTest {
    private val targets = listOf("Today", "RingSplit").mapIndexed { index, service ->
        NativeDeliveryTarget(903 + index, 407 + index,
            ComponentName(HOST_PACKAGE, "app.wardpulse.wear.complication.${service}ComplicationDataSourceService"))
    }

    @Test
    fun api36AndExactManualAuthorizationCannotBeReplacedByTypedReads() {
        val arguments = Bundle().apply {
            putString("expectedAvd", "wardpulse_wear_square_api36_1")
            putString("quietWriters", "confirmed-unpaired")
            putString("firstFrameReview", "complete-unobscured")
            putString("authorizedOperation", "observeDirectData:unsupported-range")
        }
        val expected = NativePushExpectations(arguments)
        for (method in listOf("probeDirectCapability", "observeDirectData", "observeDirectRestoration")) {
            arguments.putString("class", "$DELIVERY_CLASS#$method")
            arguments.putString("wardpulseNativeIntegration", "sdk-direct-data")
            fun admit(runner: String = "androidx.test.runner.AndroidJUnitRunner") = expected.admit(method,
                runner, "wardpulse_wear_square_api36_1", "1", true, DELIVERY_CLASS, "sdk-direct-data")
            admit()
            assertThrows(NativePending::class.java) { admit("app.wardpulse.wear.IsolatedWearRunner") }
            arguments.putString("class", DELIVERY_CLASS)
            assertThrows(NativePending::class.java) { admit() }
            arguments.putString("class", "$DELIVERY_CLASS#$method")
            arguments.putString("wardpulseNativeIntegration", "normal-delivery")
            assertThrows(NativePending::class.java) { admit() }
        }
        requireNativeSdkDirectAuthorization(expected, "unsupported-range")
        assertThrows(NativePending::class.java) { requireNativeSdkDirectAuthorization(expected, "malformed-title") }
        assertThrows(NativePending::class.java) { requireNativeSdkDirectAuthorization(expected, "nonfinite-value") }
        arguments.putString("quietWriters", "unknown")
        assertThrows(NativePending::class.java) { requireNativeSdkDirectAuthorization(expected, "unsupported-range") }
        arguments.putString("quietWriters", "confirmed-unpaired")
        arguments.putString("firstFrameReview", "Pending")
        assertThrows(NativePending::class.java) { requireNativeSdkDirectAuthorization(expected, "unsupported-range") }

        var acquired = false
        val unavailable = JSONObject().put("sdk35_1Available", true)
        assertThrows(NativePending::class.java) {
            readNativeSdkDirectManager(unavailable, {}, { false }, { acquired = true; null })
        }
        assertFalse(acquired)
        assertEquals("not invoked", unavailable.optString("managerAcquisition", "not invoked"))
        assertThrows(NativeReadEmpty::class.java) { readNativeSdkDirectManager(JSONObject(), {}, { true }, { null }) }
        val denied = JSONObject()
        assertThrows(SecurityException::class.java) {
            readNativeSdkDirectManager(denied, {}, { true }, { throw SecurityException() })
        }
        assertEquals("invoked under ordinary target UID; outcome Pending", denied.getString("managerAcquisition"))

        val root = File(InstrumentationRegistry.getInstrumentation().targetContext.cacheDir, "sdk_guard_${UUID.randomUUID()}")
        check(root.mkdir())
        try {
            val scope = NativeDatasourceProbeScope("a".repeat(64), "b".repeat(64), "c".repeat(64), "d".repeat(64), "e".repeat(64))
            val selected = NativeDatasourceProbeSelection("selected", "f".repeat(64), "0".repeat(64))
            val file = File(root, "receipt.json")
            val receipt = nativeSdkDirectCapabilityReceipt(scope, selected)
            val persist = { AttemptJournal(file).persist(receipt) }
            readNativeSdkDirectManager(receipt, persist, { true }, { NativeSdkDirectUpdater { _, _, _ -> error("no dispatch") } })
            receipt.put("stableScope", true)
            persist()
            val hash = file.inputStream().sha256()
            requireNativeSdkDirectCapability(file, hash, scope, selected)
            assertThrows(NativePending::class.java) {
                requireNativeSdkDirectCapability(file, hash, scope.copy(scopeSha256 = "1".repeat(64)), selected)
            }
            assertThrows(NativePending::class.java) {
                requireNativeSdkDirectCapability(file, hash, scope, selected.copy(id = "another"))
            }
            File(root, "receipt.json.new").writeText("ambiguous")
            assertThrows(NativePending::class.java) { requireNativeSdkDirectCapability(file, hash, scope, selected) }
            check(File(root, "receipt.json.new").delete())
            receipt.put("api36Available", false)
            persist()
            assertThrows(NativePending::class.java) { requireNativeSdkDirectCapability(file, hash, scope, selected) }
            assertThrows(NativePending::class.java) {
                requireNativeSdkDirectCapability(file, file.inputStream().sha256(), scope, selected)
            }
        } finally { check(root.deleteRecursively()) }
    }

    @Test
    fun finitePublicBuildersRetainRangesTitlesAndSequentialPartialTargets() {
        assertEquals(4, nativeSdkDirectScenarios.size)
        for (scenario in nativeSdkDirectScenarios) {
            val receipt = JSONObject()
            val updates = constructNativeSdkDirectData(scenario, targets, receipt, {})
            assertEquals("constructed; no dispatch", receipt.getString("construction"))
            assertFalse(receipt.optBoolean("directArmed"))
            assertEquals(targets.first(), updates.first().target)
            assertEquals(if (scenario == "no-data-main-valid-extra") targets else targets.take(1), updates.map { it.target })
            updates.forEachIndexed { index, update ->
                val data = update.data
                if (scenario in setOf("partial-no-data-main", "no-data-main-valid-extra") && index == 0) {
                    assertEquals(WireComplicationData.TYPE_NO_DATA, data.type)
                } else {
                    assertEquals(WireComplicationData.TYPE_RANGED_VALUE, data.type)
                    assertEquals(0f, data.rangedMinValue, 0f)
                    assertEquals(if (scenario == "unsupported-range") 300f else 400f, data.rangedMaxValue, 0f)
                    assertEquals(if (scenario == "unsupported-range") 111f else 148f, data.rangedValue, 0f)
                    assertTrue(data.hasRangedValueType())
                    assertEquals(RangedValueComplicationData.TYPE_UNDEFINED, data.rangedValueType)
                    assertTrue(data.hasColorRamp())
                    assertArrayEquals(intArrayOf(if (index == 1) RingFamily.CODEX_SPARK else RingFamily.CODEX), data.colorRamp)
                    assertTrue(data.hasIsColorRampInterpolated())
                    assertFalse(data.isColorRampInterpolated)
                    assertTrue(data.hasShortTitle())
                    assertEquals(when { index == 1 -> "0"; scenario == "malformed-title" -> "invalid"; else -> "" },
                        (data.shortTitle as PlainComplicationText).text.toString())
                    assertTrue(data.hasContentDescription())
                    assertEquals("Test percentage", (data.contentDescription as PlainComplicationText).text.toString())
                    assertTrue(data.hasShortText())
                    assertEquals("37%", (data.shortText as PlainComplicationText).text.toString())
                }
            }
        }
        val mainOnly = nativeSdkDirectData("partial-no-data-main", targets.take(1)).single()
        assertEquals(targets.first(), mainOnly.target)
        assertEquals(WireComplicationData.TYPE_NO_DATA, mainOnly.data.type)
        assertThrows(NativePending::class.java) { nativeSdkDirectData("out-of-range", targets) }
        assertThrows(NativePending::class.java) { nativeSdkDirectData("no-data-main-valid-extra", targets.take(1)) }
        assertThrows(NativePending::class.java) { nativeSdkDirectData("unsupported-range", targets + targets.first()) }
        val rejected = JSONObject()
        assertThrows(IllegalArgumentException::class.java) {
            constructNativeSdkDirectData("unsupported-range", targets, rejected, {},
                construct = { throw IllegalArgumentException() })
        }
        assertEquals("SDK rejected; no dispatch or renderer effect established", rejected.getString("construction"))
        assertFalse(rejected.optBoolean("directArmed"))
    }

    @Test
    fun durableArmingUncertainCallbacksAndIndependentRecoveryCannotBeSkipped() {
        val updates = nativeSdkDirectData("no-data-main-valid-extra", targets)
        val receipt = JSONObject()
        var dispatches = 0
        var recoveries = 0
        assertThrows(IllegalStateException::class.java) {
            dispatchNativeSdkDirectData(updates, receipt, { error("durable arm failed") }, {},
                NativeSdkDirectUpdater { _, _, _ -> dispatches++ }, { recoveries++ })
        }
        assertEquals(0, dispatches)
        assertEquals(0, recoveries)
        for (mode in listOf("returned", "throw", "error", "timeout", "validation", "recording")) {
            val record = JSONObject()
            val snapshots = mutableListOf<String>()
            var late: OutcomeReceiver<Void, Throwable>? = null
            var calls = 0
            var validations = 0
            var recovered: List<NativeDeliveryTarget>? = null
            val action = {
                dispatchNativeSdkDirectData(updates, record, {
                    if (mode == "recording" && calls > 0) error("post-dispatch persistence failed")
                    snapshots += record.toString()
                }, validate = {
                    validations++
                    if (mode == "validation") throw NativePending("fresh-mapping-changed")
                }, updater = NativeSdkDirectUpdater { id, _, receiver ->
                    calls++
                    assertTrue(JSONObject(snapshots.last()).getBoolean("directArmed"))
                    assertEquals(2, JSONObject(snapshots.last()).getJSONArray("calls").length())
                    assertEquals(targets[calls - 1].systemId, id)
                    when (mode) {
                        "throw" -> throw SecurityException()
                        "error" -> receiver.onError(SecurityException())
                        "timeout" -> late = receiver
                        else -> receiver.onResult(null)
                    }
                }, recover = { recovered = it }, await = { future ->
                    if (mode == "timeout") throw TimeoutException()
                    assertTrue(future.isDone)
                    future.get()
                    Unit
                })
            }
            val failureType = when (mode) {
                "throw", "error" -> SecurityException::class.java
                "timeout" -> TimeoutException::class.java
                "validation" -> NativePending::class.java
                else -> IllegalStateException::class.java
            }
            if (mode == "returned") action() else assertThrows(failureType) { action() }
            assertEquals(targets, recovered)
            assertEquals(if (mode == "returned") 2 else if (mode == "validation") 0 else 1, calls)
            assertTrue(validations >= 1)
            val terminal = record.toString()
            late?.onResult(null)
            late?.onError(SecurityException())
            assertEquals(terminal, record.toString())
            assertEquals("uncertain; recovery required", record.getString("effect"))
            val callback = record.getJSONArray("calls").getJSONObject(0).getString("callback")
            assertEquals(when (mode) {
                "returned" -> "onResult; processing/forwarding reported; effective data and paint Pending"
                "error" -> "onError; processing/forwarding not established; effect uncertain"
                "timeout" -> "unavailable within bound; effect uncertain"
                "validation" -> "not invoked"
                else -> "outcome unrecorded; effect uncertain"
            }, callback)
            assertThrows(NativePending::class.java) { action() } // No reuse after an uncertain or completed attempt.
        }

        // Exercise actual independent normal-request grouping after a provider failure.
        val calls = JSONArray()
        val requested = mutableListOf<Int>()
        assertThrows(SecurityException::class.java) {
            requestNativeDelivery(targets, targets, calls, {}, validate = { targets }, recovery = true) { _, ids ->
                requested += ids.toList()
                if (ids.single() == targets.first().systemId) throw SecurityException()
            }
        }
        assertEquals(targets.map { it.systemId }, requested)
        assertEquals(2, calls.length())
    }
}
