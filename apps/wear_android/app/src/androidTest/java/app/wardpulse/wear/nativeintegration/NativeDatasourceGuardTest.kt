package app.wardpulse.wear.nativeintegration

import android.content.ComponentName
import android.content.Context
import android.content.SharedPreferences
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import androidx.wear.watchface.complications.data.NoDataComplicationData
import androidx.wear.watchface.complications.data.RangedValueComplicationData
import app.wardpulse.wear.complication.WatchComplicationText
import app.wardpulse.wear.complication.outerHalfComplicationData
import app.wardpulse.wear.complication.rangedComplicationBuilder
import app.wardpulse.wear.complication.ringComplicationData
import app.wardpulse.wear.data.WatchSummaryStore
import app.wardpulse.wear.ui.RingFamily
import java.io.File
import java.time.Instant
import java.util.UUID
import java.util.concurrent.FutureTask
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertSame
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
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
                val original = checkedDeliverySummary(false, "2026-01-01T00:00:00Z", preferences)
                val own = checkedDeliverySummary(true, "2026-01-01T00:01:00Z", preferences)
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
            // Flush private test writes and attempt both deletions even after a cleanup failure.
            val flushed = runCatching { preferences.edit().clear().commit() }
            val deleted = runCatching { context.deleteSharedPreferences(name) }
            val removed = runCatching { directory.deleteRecursively() }
            check(listOf(flushed, deleted, removed).all { it.getOrDefault(false) }) {
                "Private delivery-test resources must be deleted"
            }
        }
    }

    /** Inspect actual helper output: the decoder intentionally tolerates absent nullable keys. */
    private fun checkedDeliverySummary(pair: Boolean, generatedAt: String, preferences: SharedPreferences): String {
        val encoded = deliverySummary(pair, generatedAt)
        val summary = JSONObject(encoded)
        fun keys(value: JSONObject, vararg expected: String) =
            assertEquals(expected.toSet(), value.keys().asSequence().toSet())
        fun explicitNulls(value: JSONObject, vararg names: String) {
            names.forEach { assertSame("Explicit null required for $it", JSONObject.NULL, value.get(it)) }
        }
        fun half(value: JSONObject, id: String, used: Int) {
            assertEquals(id, value.get("id"))
            assertEquals("Plan", value.get("label"))
            assertEquals("ok", value.get("status"))
            assertTrue("usedPercent must be a JSON number", value.get("usedPercent") is Number)
            assertEquals(used.toDouble(), value.getDouble("usedPercent"), 0.0)
        }
        keys(summary, "schemaVersion", "dataMode", "generatedAt", "overallStatus", "rings", "creditsGlance",
            "today", "week", "allowances", "providers", "alerts", "isStale", "manualRefreshAllowed",
            "manualRefreshAvailableAt")
        assertEquals(9, summary.get("schemaVersion"))
        assertEquals("live", summary.get("dataMode"))
        assertEquals(generatedAt, summary.get("generatedAt"))
        Instant.parse(summary.getString("generatedAt"))
        assertEquals("ok", summary.get("overallStatus"))
        assertEquals(false, summary.get("isStale"))
        assertEquals(false, summary.get("manualRefreshAllowed"))
        explicitNulls(summary, "creditsGlance", "manualRefreshAvailableAt")
        for (name in listOf("allowances", "providers", "alerts")) {
            assertEquals(0, summary.getJSONArray(name).length())
        }
        for (name in listOf("today", "week")) {
            val period = summary.getJSONObject(name)
            keys(period, "period", "status", "spent", "limit", "remaining", "usedPercent", "projectedTotal")
            assertEquals(name, period.get("period"))
            assertEquals("unknown", period.get("status"))
            explicitNulls(period, "spent", "limit", "remaining", "usedPercent", "projectedTotal")
        }
        val rings = summary.getJSONArray("rings")
        assertEquals(if (pair) 2 else 1, rings.length())
        for (index in 0 until rings.length()) {
            val ring = rings.getJSONObject(index)
            keys(ring, "id", "label", "usedPercent", "status", "spent", "limit", "split")
            half(ring, if (index == 0) "allowance.codex.week" else "allowance.cursor.cursor-plan-models",
                if (index == 0) (if (pair) 63 else 20) else 30)
            explicitNulls(ring, "spent", "limit")
            if (index == 0) explicitNulls(ring, "split") else {
                val split = ring.getJSONObject("split")
                // A half has four properties; full-ring money/split fields must not leak into it.
                keys(split, "id", "label", "usedPercent", "status")
                half(split, "allowance.cursor.cursor-plan-other", 50)
            }
        }

        val store = WatchSummaryStore(preferences)
        assertTrue(store.saveEncoded(encoded))
        val decoded = checkNotNull(store.load())
        // Use normal selection and AndroidX data construction, rather than a token-only assertion.
        val main = ringComplicationData(decoded.rings, 0) { ring, remaining, title, count ->
            rangedComplicationBuilder(remaining, title, RingFamily.colorArgb(ring.id),
                contentDescription = ring.label, ringCount = count).build()
        } as RangedValueComplicationData
        main.validate()
        val resources = InstrumentationRegistry.getInstrumentation().targetContext.resources
        assertEquals(if (pair) "split:cursor-other" else "", main.title!!.getTextAt(resources, Instant.EPOCH).toString())
        assertEquals(if (pair) 280f else 160f, main.value, 0f)
        assertEquals(if (pair) 400f else 200f, main.max, 0f)
        val extra = outerHalfComplicationData(decoded.rings, 0) { half, slot, count ->
            rangedComplicationBuilder(WatchComplicationText.remainingPercent(half.usedPercent), slot.toString(),
                RingFamily.colorArgb(half.id), contentDescription = half.label, ringCount = count).build()
        }
        if (pair) {
            extra as RangedValueComplicationData
            extra.validate()
            assertEquals("0", extra.title!!.getTextAt(resources, Instant.EPOCH).toString())
            assertEquals(200f, extra.value, 0f)
            assertEquals(400f, extra.max, 0f)
            assertEquals(RingFamily.CURSOR, extra.colorRamp!!.colors.single())
        } else assertTrue(extra is NoDataComplicationData)
        return encoded
    }
}
