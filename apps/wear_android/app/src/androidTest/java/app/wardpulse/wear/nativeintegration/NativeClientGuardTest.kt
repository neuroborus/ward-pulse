package app.wardpulse.wear.nativeintegration

import android.content.ComponentName
import android.content.ContextWrapper
import android.content.Intent
import android.content.ServiceConnection
import android.os.IBinder
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import androidx.wear.watchface.complications.data.NoDataComplicationData
import androidx.wear.watchface.complications.data.RangedValueComplicationData
import java.time.Instant
import java.util.concurrent.Executor
import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Test
import org.junit.runner.RunWith

/** Synthetic bindings and objects only. These cases cannot authorize a native override. */
@ManualNativeIntegration
@RunWith(AndroidJUnit4::class)
class NativeClientGuardTest {
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
