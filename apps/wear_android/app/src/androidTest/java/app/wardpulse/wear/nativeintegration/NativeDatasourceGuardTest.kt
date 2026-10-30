package app.wardpulse.wear.nativeintegration

import android.content.ComponentName
import android.content.Context
import android.content.SharedPreferences
import android.os.Bundle
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
import org.json.JSONArray
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
    fun currentDatasourceMethodsNeedCurrentCallerAndSeparateExactWriteAuthorization() {
        val arguments = Bundle().apply {
            putString("expectedAvd", "wardpulse_wear_square_api36_1")
            putString("expectedCallerUid", "10021")
            putString("expectedHostVersionCode", "17")
            putString("expectedHostApkSha256", "a".repeat(64))
            putString("expectedHostSignerSha256", "b".repeat(64))
        }
        val expected = NativePushExpectations(arguments)
        val operations = listOf("observeDelivery:normal", "observeDelivery:delayed",
            "observeOverride:active:malformed-title", "observeOverride:supplied-bitmap:malformed-title")
        for ((testClass, optIn, methods) in listOf(
            Triple(DELIVERY_CLASS, "normal-delivery", listOf("probeDelivery", "observeDelivery", "observeRestoration")),
            Triple(CLIENT_CLASS, "client-probe", listOf("probeClient", "observeOverride", "observeRestoration")))) {
            for (method in methods) {
                arguments.putString("class", "$testClass#$method")
                arguments.putString("wardpulseNativeIntegration", optIn)
                fun admit() = expected.admit(method, "androidx.test.runner.AndroidJUnitRunner",
                    "wardpulse_wear_square_api36_1", "1", true, testClass, optIn)
                admit()
                requireNativeReadCaller(10021, 10021, setOf(HOST_PACKAGE),
                    NativePackage(17L, "a".repeat(64), "b".repeat(64)), expected)
                // No historical asset/package/journal/quiet-writer inputs or write authorization exist.
                operations.forEach { operation ->
                    assertThrows(NativePending::class.java) { requireNativeDatasourceMutation(expected, operation) }
                }
                arguments.putString("class", testClass)
                assertThrows(NativePending::class.java) { admit() }
                arguments.putString("class", "$testClass#$method")
                arguments.putString("wardpulseNativeIntegration", "push-3-to-4")
                assertThrows(NativePending::class.java) { admit() }
            }
        }
        for (authorized in operations) {
            arguments.putString("authorizedOperation", authorized)
            requireNativeDatasourceMutation(expected, authorized)
            operations.filterNot { it == authorized }.forEach { other ->
                assertThrows(NativePending::class.java) { requireNativeDatasourceMutation(expected, other) }
            }
        }
    }

    @Test
    fun targetedRequestsNeedActualInstanceMappingsRatherThanCanonicalOrCachedIds() {
        val slots = (11..18).toList()
        val providers = slots.associateWith { slot -> if (slot <= 15)
            "$HOST_PACKAGE/app.wardpulse.wear.complication.SyntheticProvider$slot" else null }
        val rows = slots.zip(listOf(407, 912, 219, 601, 307, 811, 509, 1100).map { it.toString() }).toMap()
        val types = slots.associateWith { if (it <= 15) 5 else 0 }
        val selections = NativeSelections(CANDIDATE_PACKAGE, "existing", providers, types, rows)
        val renderer = NativeRenderer(CANDIDATE_PACKAGE, "existing", "style", slots.associateWith { true },
            emptyMap(), selections = selections, runtime = "SyntheticRuntime", nativeScope = listOf("engine"))
        val configs = slots.take(5).map { slot -> NativeTypedConfig(rows.getValue(slot).toInt(), slot,
            ComponentName.unflattenFromString(providers.getValue(slot)!!), CANDIDATE_PACKAGE, null, 5) }
        val targets = discoverDeliveryTargets(configs.reversed(), renderer, renderer)
        assertEquals(listOf(407, 912, 219, 601, 307), targets.map { it.systemId })
        val legacy = renderer.copy(resourcePackage = "app.wardpulse.watchface",
            selections = selections.copy(resourcePackage = "app.wardpulse.watchface"))
        assertEquals(targets, discoverDeliveryTargets(configs.map { it.copy(watchFacePackage = legacy.resourcePackage) },
            legacy, legacy))
        val first = configs.first()
        val badConfigs = listOf(emptyList(), configs.drop(1), configs + first, configs.drop(1) + configs[1],
            configs.drop(1) + first.copy(id = first.watchFaceSlotId),
            configs.drop(1) + first.copy(id = configs[1].id), configs.drop(1) + first.copy(id = -1),
            configs.drop(1) + first.copy(watchFaceSlotId = 101),
            configs.drop(1) + first.copy(provider = null),
            configs.drop(1) + first.copy(provider = ComponentName("other", "SyntheticProvider")),
            configs.drop(1) + first.copy(watchFacePackage = null),
            configs.drop(1) + first.copy(watchFacePackage = "other.resource"),
            configs.drop(1) + first.copy(watchFaceClass = "SyntheticFace"),
            configs.drop(1) + first.copy(dataType = 3))
        badConfigs.forEach { unavailable ->
            assertThrows(NativePending::class.java) { discoverDeliveryTargets(unavailable, renderer, renderer) }
        }
        for (changed in listOf(renderer.copy(instance = "other"), renderer.copy(runtime = "OtherRuntime"),
            renderer.copy(nativeScope = listOf("other")), renderer.copy(userStyle = "changed"), legacy,
            renderer.copy(enabled = renderer.enabled + (18 to false)),
            renderer.copy(selections = selections.copy(providers = providers - 18)),
            renderer.copy(selections = selections.copy(providers = providers + (18 to providers[11]))),
            renderer.copy(selections = selections.copy(configuredTypes = types + (18 to 5))),
            renderer.copy(selections = selections.copy(rowIds = rows + (18 to "1101"))),
            renderer.copy(selections = selections.copy(rowIds = rows - 18)),
            renderer.copy(selections = selections.copy(rowIds = rows + (18 to rows.getValue(11)))),
            renderer.copy(selections = selections.copy(rowIds = rows + (18 to "0407"))),
            renderer.copy(selections = selections.copy(rowIds = rows + (18 to "unresolved"))))) {
            assertThrows(NativePending::class.java) { discoverDeliveryTargets(configs, renderer, changed) }
        }
        // Persistence failure prevents the request; a durable uncertain arm prevents a retry.
        var dispatched = 0
        val calls = JSONArray()
        assertThrows(java.io.IOException::class.java) {
            requestNativeDelivery(targets, targets.take(1), calls, { throw java.io.IOException() }, { targets }) { _, _ ->
                dispatched++
            }
        }
        assertEquals(0, dispatched)
        assertThrows(NativePending::class.java) {
            requestNativeDelivery(targets, targets.take(1), calls, {}, { targets }) { _, _ -> dispatched++ }
        }
        assertEquals(0, dispatched)
        for (afterReturn in listOf(false, true)) {
            val uncertain = JSONArray()
            var durable = ""
            val failure = if (afterReturn) java.io.IOException::class.java else IllegalStateException::class.java
            assertThrows(failure) {
                requestNativeDelivery(targets, targets.take(1), uncertain, {
                    if (afterReturn && durable.isNotEmpty()) throw java.io.IOException()
                    durable = uncertain.toString()
                }, { targets }) { _, _ ->
                    dispatched++
                    if (!afterReturn) throw IllegalStateException("Synthetic transport failure")
                }
            }
            assertEquals("armed; dispatch uncertain", JSONArray(durable).getJSONObject(0).getString("state"))
            assertThrows(NativePending::class.java) {
                requestNativeDelivery(targets, targets.take(1), JSONArray(durable), {}, { targets }) { _, _ -> dispatched++ }
            }
        }
        assertEquals(2, dispatched)
        // Changes during arming never use old IDs; recovery still tries independent intended groups.
        var validations = 0
        var mappingChanged = false
        val recovered = mutableListOf<Int>()
        assertThrows(NativePending::class.java) {
            requestNativeDelivery(targets, targets.take(2), JSONArray(), { mappingChanged = true }, {
                assertTrue(mappingChanged)
                if (validations++ == 0) targets.drop(1) else targets
            }, recovery = true) { _, ids -> recovered += ids.toList() }
        }
        assertEquals(2, validations)
        assertEquals(listOf(912), recovered)
        recovered.clear()
        val recoveryCalls = JSONArray()
        assertThrows(java.io.IOException::class.java) {
            requestNativeDelivery(targets, targets.take(2), recoveryCalls, {
                if (recoveryCalls.length() == 1) throw java.io.IOException()
            }, { targets }, recovery = true) { _, ids -> recovered += ids.toList() }
        }
        assertEquals(listOf(912), recovered)
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
