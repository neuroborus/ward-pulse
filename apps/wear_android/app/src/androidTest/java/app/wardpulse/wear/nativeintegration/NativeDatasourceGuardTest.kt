package app.wardpulse.wear.nativeintegration

import android.content.ComponentName
import android.content.Context
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import app.wardpulse.wear.data.WatchSummaryStore
import java.io.File
import java.util.UUID
import java.util.concurrent.FutureTask
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertThrows
import org.junit.Test
import org.junit.runner.RunWith

/** Private preferences and synthetic records only; excluded from the original default 40. */
@ManualNativeIntegration
@RunWith(AndroidJUnit4::class)
class NativeDatasourceGuardTest {
    @Test
    fun targetedRequestsNeedActualInstanceMappingsRatherThanCanonicalOrCachedIds() {
        val component = ComponentName(RUNTIME_PACKAGE, "$RUNTIME_PACKAGE.DeclarativeWatchFaceRuntime0")
        val provider = "$HOST_PACKAGE/app.wardpulse.wear.complication.TodayComplicationDataSourceService"
        val selected = NativeSelections(CANDIDATE_PACKAGE, "existing", mapOf(11 to provider))
        val renderer = NativeRenderer(CANDIDATE_PACKAGE, "existing", "style", mapOf(11 to true),
            mapOf(11 to provider), selections = selected)
        val record = "watchFaceComponent=ComponentInfo{${component.flattenToString()}}, " +
            "watchFaceInstanceId=existing, watchFaceComplicationId=11, " +
            "complicationInstanceId=407, providerComponent=ComponentInfo{$provider}"
        assertEquals(407, discoverDeliveryTargets(record, component, renderer).single().systemId)
        for (unavailable in listOf("", "dataSource=ComponentInfo{$provider}",
            record.replace("watchFaceInstanceId=existing", "watchFaceInstanceId=other"),
            record.replace("complicationInstanceId=407, ", ""), "$record\n$record",
            record.replace("providerComponent=ComponentInfo{$provider}", "providerComponent=ComponentInfo{other/Provider}"))) {
            assertThrows(NativePending::class.java) { discoverDeliveryTargets(unavailable, component, renderer) }
        }
        val args = android.os.Bundle().apply {
            putString("class", "$DELIVERY_CLASS#observeDelivery")
            putString("wardpulseNativeIntegration", "normal-delivery")
            putString("expectedAvd", "wardpulse_wear_square_api36_1")
        }
        fun admit() = NativePushExpectations(args).admit("observeDelivery",
            "androidx.test.runner.AndroidJUnitRunner", "wardpulse_wear_square_api36_1", "1", true,
            DELIVERY_CLASS, "normal-delivery")
        admit()
        args.putString("wardpulseNativeIntegration", "push-3-to-4")
        assertThrows(NativePending::class.java) { admit() }
    }

    @Test
    fun failedPublicationRestoresOnlyOwnedDataAndRetainsUnresolvedRecovery() {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val context = instrumentation.targetContext
        val name = "native_delivery_cleanup_${UUID.randomUUID()}"
        val preferences = context.getSharedPreferences(name, Context.MODE_PRIVATE)
        val directory = File(context.cacheDir, name)
        check(directory.mkdir())
        try {
            instrumentation.runOnMainSync {
                val original = deliverySummary(false, "2026-01-01T00:00:00Z")
                val own = deliverySummary(true, "2026-01-01T00:01:00Z")
                val newer = deliverySummary(false, "2026-01-01T00:02:00Z")
                for (outcome in listOf("failure", "rejected", "newer", "during-persistence", "writers-unresolved", "absent")) {
                    check(preferences.edit().clear().commit())
                    if (outcome != "absent") check(WatchSummaryStore(preferences).saveEncoded(original))
                    val receipt = JSONObject()
                    val recovery = File(directory, outcome)
                    val journal = AttemptJournal(File(recovery, "receipt.json"))
                    var producerStarted = false
                    val lease = NativeSummaryLease(preferences, recovery, receipt) { persisted ->
                        journal.persist(persisted)
                        if (outcome == "during-persistence" && !producerStarted &&
                            persisted.optString("publication") == "armed; acceptance Pending") {
                            producerStarted = true
                            val write = FutureTask<Unit> {
                                check(WatchSummaryStore(preferences).saveEncoded(newer))
                                check(preferences.edit().commit())
                            }
                            val producer = Thread(write, "native-summary-producer")
                            producer.start()
                            try {
                                // The main-thread preference listener cannot run until this returns.
                                write.get()
                            } finally {
                                producer.join()
                            }
                        }
                    }
                    try {
                        lease.publish(own)
                        assertEquals(2, WatchSummaryStore(preferences).load()!!.rings.size)
                        if (outcome == "newer") check(WatchSummaryStore(preferences).saveEncoded(newer))
                        if (outcome == "rejected") lease.publish("{}")
                        throw NativePending("synthetic-observation-failure")
                    } catch (failure: NativePending) {
                        assertEquals(when (outcome) {
                            "rejected" -> "normal-store-acceptance"
                            "during-persistence" -> "quiet-summary-writer"
                            else -> "synthetic-observation-failure"
                        }, failure.identity)
                    } finally {
                        lease.close(quietWriter = outcome != "writers-unresolved")
                    }
                    assertEquals(when (outcome) {
                        "newer", "during-persistence" -> newer
                        "writers-unresolved" -> own
                        "absent" -> null
                        else -> original
                    }, preferences.getString("latest", null))
                    assertEquals(if (outcome == "absent") 0 else 1, File(recovery, "original.bin").readBytes()[0].toInt())
                    assertEquals(if (outcome == "absent") "" else original,
                        File(recovery, "original.bin").readBytes().drop(1).toByteArray().toString(Charsets.UTF_8))
                    check(File(recovery, "original.bin").isFile && File(recovery, "receipt.json").isFile)
                    if (outcome in setOf("newer", "during-persistence", "writers-unresolved")) {
                        check(receipt.getString("restoration").contains("Pending"))
                    } else assertFalse(receipt.getString("restoration").contains("Pending"))
                    if (outcome == "during-persistence") {
                        check(producerStarted)
                        assertEquals(newer,
                            File(recovery, "newer.bin").readBytes().drop(1).toByteArray().toString(Charsets.UTF_8))
                    }
                }
            }
        } finally {
            check(context.deleteSharedPreferences(name))
            check(directory.deleteRecursively())
        }
    }
}
