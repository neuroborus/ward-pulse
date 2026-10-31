package app.wardpulse.wear.nativeintegration

import android.content.ComponentName
import android.content.Context
import android.content.ContextWrapper
import android.content.SharedPreferences
import android.graphics.Bitmap
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
import app.wardpulse.wear.model.WatchDataMode
import app.wardpulse.wear.ui.RingFamily
import java.io.File
import java.time.Instant
import java.util.UUID
import java.util.concurrent.FutureTask
import java.util.concurrent.TimeoutException
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
    /** Only synthetic private files: this never captures a native frame or reviews real recovery. */
    @Test
    fun explicitProbeSelectionRetainsHistoryAndRejectsReusedOrChangedEvidence() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val root = File(context.cacheDir, "native_probe_guard_${UUID.randomUUID()}")
        check(root.mkdir())
        try {
            val historical = File(root, "probe").also { check(it.mkdir()) }
            val retained = listOf(File(historical, "first.png"), File(historical, "first.json"),
                File(historical, "receipt.json"), File(root, "latest.json"),
                File(root, "normal/receipt.json"))
            retained.forEachIndexed { index, file ->
                check(file.parentFile!!.isDirectory || file.parentFile!!.mkdirs())
                file.writeText("retained synthetic evidence $index")
            }
            val originals = retained.associateWith { it.readText() }
            val scope = NativeDatasourceProbeScope("a".repeat(64), "b".repeat(64), "c".repeat(64),
                "d".repeat(64), "e".repeat(64))
            var captures = 0
            fun capture(directory: File, selected: NativeDatasourceProbeScope = scope) {
                captures++
                val bitmap = Bitmap.createBitmap(1, 1, Bitmap.Config.ARGB_8888)
                try {
                    bitmap.eraseColor(android.graphics.Color.BLACK)
                    File(directory, "first.png").outputStream().use {
                        check(bitmap.compress(Bitmap.CompressFormat.PNG, 100, it))
                    }
                } finally { bitmap.recycle() }
                File(directory, "first.json").writeText(JSONObject()
                    .put("instanceSha256", selected.instanceSha256)
                    .put("configurationSha256", selected.configurationSha256)
                    .put("nativeRecordAcquired", "before frame").put("effectiveData", JSONObject())
                    .put("responseProvenance", "Pending").put("visualAcceptance", "Pending").toString())
            }
            fun hash(file: File) = file.inputStream().sha256()
            fun read(probe: NativeDatasourceProbe, selected: NativeDatasourceProbeScope = scope) =
                probe.reviewed(selected, hash(File(probe.directory, "receipt.json")),
                    hash(File(probe.directory, "first.png")))

            for (invalid in listOf("", ".", "..", "../probe", "nested/read", "nested\\read", "UPPER", " white",
                "trailing ", "a\nb", "é", "x".repeat(65))) {
                assertThrows(NativePending::class.java) { NativeDatasourceProbe(root, invalid) }
            }
            val first = NativeDatasourceProbe(root, "current-first")
            first.create(scope, { capture(it) }, { scope })
            val receiptFile = File(first.directory, "receipt.json")
            val frameFile = File(first.directory, "first.png")
            val recordFile = File(first.directory, "first.json")
            val receiptBytes = receiptFile.readBytes()
            val frameBytes = frameFile.readBytes()
            val recordBytes = recordFile.readBytes()
            val selected = read(first)
            assertEquals("current-first", selected.id)
            assertEquals(hash(receiptFile), selected.receiptSha256)
            assertEquals(hash(frameFile), selected.frameSha256)
            assertEquals("Pending", JSONObject(receiptFile.readText()).getString("frameReview"))
            assertThrows(NativePending::class.java) { first.create(scope, { capture(it) }, { scope }) }
            assertEquals(1, captures)
            assertEquals(selected, read(first))
            for ((receiptHash, frameHash) in listOf("" to selected.frameSha256,
                selected.receiptSha256 to "", "f".repeat(64) to selected.frameSha256,
                selected.receiptSha256 to "f".repeat(64))) {
                assertThrows(NativePending::class.java) { first.reviewed(scope, receiptHash, frameHash) }
            }

            // No preferred/latest/historical fallback, including when the explicitly selected ID is absent.
            val missing = NativeDatasourceProbe(root, "absent")
            assertThrows(NativePending::class.java) {
                missing.reviewed(scope, selected.receiptSha256, selected.frameSha256)
            }
            assertFalse(missing.directory.exists())
            val next = NativeDatasourceProbe(root, "next-first")
            next.create(scope, { capture(it) }, { scope })
            assertEquals("next-first", read(next).id)
            assertThrows(NativePending::class.java) {
                next.reviewed(scope, selected.receiptSha256, selected.frameSha256)
            }
            val newScope = scope.copy(hostApkSha256 = "f".repeat(64), scopeSha256 = "1".repeat(64))
            val currentHost = NativeDatasourceProbe(root, "current-host")
            currentHost.create(newScope, { capture(it, newScope) }, { newScope })
            assertEquals("current-host", read(currentHost, newScope).id)
            assertEquals(selected, read(first))
            for (changed in listOf(newScope, scope.copy(instanceSha256 = "f".repeat(64)),
                scope.copy(configurationSha256 = "f".repeat(64)), scope.copy(mappingSha256 = "f".repeat(64)),
                scope.copy(scopeSha256 = "f".repeat(64)), scope.copy(scopeSha256 = ""))) {
                assertThrows(NativePending::class.java) { read(first, changed) }
            }

            val copied = NativeDatasourceProbe(root, "copied")
            check(copied.directory.mkdir())
            File(copied.directory, "receipt.json").writeBytes(receiptBytes)
            File(copied.directory, "first.png").writeBytes(frameBytes)
            File(copied.directory, "first.json").writeBytes(recordBytes)
            assertThrows(NativePending::class.java) { read(copied) }
            for (file in listOf(receiptFile, frameFile, recordFile)) {
                val original = file.readBytes()
                file.appendText("changed")
                assertThrows(NativePending::class.java) {
                    first.reviewed(scope, selected.receiptSha256, selected.frameSha256)
                }
                file.writeBytes(original) // Restore only this synthetic negative-test input.
                for (suffix in listOf(".bak", ".new")) {
                    val ambiguous = File("${file.path}$suffix")
                    check(ambiguous.createNewFile())
                    assertThrows(NativePending::class.java) { read(first) }
                    check(ambiguous.delete())
                }
                val held = File(first.directory, "held")
                check(file.renameTo(held))
                assertThrows(NativePending::class.java) {
                    first.reviewed(scope, selected.receiptSha256, selected.frameSha256)
                }
                check(held.renameTo(file))
            }
            // Even newly supplied hashes cannot turn an incomplete or cross-scope record into a first read.
            receiptFile.writeText(JSONObject(receiptBytes.toString(Charsets.UTF_8)).put("state", "Pending").toString())
            assertThrows(NativePending::class.java) { read(first) }
            receiptFile.writeBytes(receiptBytes)
            recordFile.writeText(JSONObject(recordBytes.toString(Charsets.UTF_8))
                .put("instanceSha256", "f".repeat(64)).toString())
            receiptFile.writeText(JSONObject(receiptBytes.toString(Charsets.UTF_8))
                .put("nativeRecordSha256", hash(recordFile)).toString())
            assertThrows(NativePending::class.java) { read(first) }
            recordFile.writeBytes(recordBytes)
            receiptFile.writeBytes(receiptBytes)

            val partial = NativeDatasourceProbe(root, "partial")
            assertThrows(NativePending::class.java) {
                partial.create(scope, { File(it, "first.png").writeBytes(frameBytes) }, { scope })
            }
            assertFalse(File(partial.directory, "receipt.json").exists())
            assertThrows(NativePending::class.java) { partial.create(scope, { capture(it) }, { scope }) }
            val changedBracket = NativeDatasourceProbe(root, "changed-bracket")
            assertThrows(NativePending::class.java) {
                changedBracket.create(scope, { capture(it) }, { newScope })
            }
            assertFalse(File(changedBracket.directory, "receipt.json").exists())
            assertThrows(NativePending::class.java) { changedBracket.create(scope, { capture(it) }, { scope }) }
            assertEquals(selected, read(first))
            // Selecting/creating another first read cannot namespace, clear or rewrite global case/recovery state.
            assertEquals(originals, retained.associateWith { it.readText() })
            assertEquals(setOf("first.png", "first.json", "receipt.json"), historical.list()!!.toSet())

            val cases = File(root, "case-fence").also { check(it.mkdir()) }
            val scenario = "fixture-n3_reorder"
            val directory = requireNativeDeliveryCase(cases, scenario).also { check(it.mkdir()) }
            val latest = AttemptJournal(File(cases, "latest.json"))
            latest.persist(JSONObject().put("case", scenario))
            val file = File(directory, "receipt.json")
            val journal = AttemptJournal(file)
            val receipt = JSONObject().put("scenario", scenario).put("cleanupRequest", "Pending")
            journal.persist(receipt)
            val args = Bundle()
            val expected = NativePushExpectations(args)
            for (id in listOf("fresh-before-review", "another-first")) {
                val probe = NativeDatasourceProbe(cases, id)
                probe.create(scope, { capture(it) }, { scope })
                read(probe)
                assertThrows(NativePending::class.java) { requireNativePriorDeliveryRecovery(cases, expected) }
                assertThrows(NativePending::class.java) { requireNativeDeliveryCase(cases, scenario) }
            }
            receipt.put("cleanupRequest", "normal requestUpdate returned; effective restoration Pending")
            journal.persist(receipt)
            args.putString("priorDeliveryRestorationReview", "complete")
            args.putString("expectedPriorDeliveryRestorationSha256", hash(file))
            // Immediate cleanup, even explicitly reviewed, cannot stand in for the separate later read.
            assertThrows(NativePending::class.java) { requireNativePriorDeliveryRecovery(cases, expected) }
            receipt.put("laterRestoration", "recorded; original-frame inspection and response provenance Pending")
            journal.persist(receipt)
            assertThrows(NativePending::class.java) { requireNativePriorDeliveryRecovery(cases, expected) }
            args.putString("expectedPriorDeliveryRestorationSha256", hash(file))
            requireNativePriorDeliveryRecovery(cases, expected)
            assertThrows(NativePending::class.java) { requireNativeDeliveryCase(cases, scenario) }
            // Path/unknown cases cannot escape the catalog through the latest-case journal either.
            latest.persist(JSONObject().put("case", "../normal"))
            assertThrows(NativePending::class.java) { requireNativePriorDeliveryRecovery(cases, expected) }
            retainedExtraProductionAdmissionKeepsOriginalHistory(File(root, "artifact-fence"))
        } finally {
            check(root.deleteRecursively()) { "Private probe-test resources must be deleted" }
        }
    }

    /** Synthetic provenance only: this neither admits a real payload nor witnesses delayed paint. */
    private fun retainedExtraProductionAdmissionKeepsOriginalHistory(directory: File) {
        check(directory.mkdir())
        val root = File(directory, "native_datasource").also { check(it.mkdir()) }
        val providers = listOf("Today", "Week", "Ring3", "RingSplit", "StripSplit").mapIndexed { index, service ->
            index + 11 to "$HOST_PACKAGE/app.wardpulse.wear.complication.${service}ComplicationDataSourceService"
        }.toMap()
        val renderer = NativeRenderer("app.wardpulse.watchface", "existing", "style",
            providers.keys.associateWith { true }, emptyMap(),
            NativeSelections("app.wardpulse.watchface", "existing", providers,
                providers.keys.associateWith { 5 }, providers.keys.associateWith { it.toString() }))
        val mapping = NativeDeliveryMapping(emptyList(), "a".repeat(64))
        val originalFile = File(root, "delayed/receipt.json")
        check(originalFile.parentFile!!.mkdir())
        val original = JSONObject().put("scenario", "delayed").put("scopeSha256", "b".repeat(64))
            .put("cleanupRequest", "normal requestUpdate returned; effective restoration Pending")
            .put("laterRestoration", "recorded; original-frame inspection and response provenance Pending")
        originalFile.writeText(original.toString())
        val immutable = listOf(originalFile, File(root, "normal/receipt.json"),
            File(root, "fixture-n1_pair_zero_full/receipt.json"))
        immutable.drop(1).forEach { file ->
            check(file.parentFile!!.mkdir())
            file.writeText("synthetic immutable recovery")
        }
        val originals = immutable.associateWith { it.readText() }
        fun hash(file: File) = file.inputStream().sha256()
        fun artifact(payload: String, source: String, scope: String, apk: String) = JSONObject()
            .put("sourceSha256", source).put("generatedXmlSha256", payload)
            .put("builtXmlSha256", payload).put("installedXmlSha256", payload)
            .put("builtApkSha256", apk).put("resourceApkSha256", apk)
            .put("resourcePackage", renderer.resourcePackage).put("instanceSha256", renderer.instance.sha256())
            .put("configurationSha256", renderer.configuration.sha256()).put("scopeSha256", scope)
        val baseline = artifact("c".repeat(64), "d".repeat(64), "b".repeat(64), "e".repeat(64))
            .put("receiptSha256", hash(originalFile))
        val candidate = artifact("f".repeat(64), "1".repeat(64), mapping.scopeSha256, "2".repeat(64))
        val admission = JSONObject().put("kind", "retained-extra-production-payload").put("scenario", "delayed")
            .put("baseline", baseline).put("candidate", candidate)
        val file = File(root, "retained-extra-admission.json")
        val args = Bundle().apply {
            putString("expectedResourceApkSha256", "2".repeat(64))
            putString("expectedResourceSignerSha256", "3".repeat(64))
        }
        val expected = NativePushExpectations(args)
        val resource = NativePackage(2, "2".repeat(64), "3".repeat(64))
        AttemptJournal(File(root, "latest.json")).persist(JSONObject().put("case", "delayed"))
        args.putString("priorDeliveryRestorationReview", "complete")
        args.putString("expectedPriorDeliveryRestorationSha256", hash(originalFile))
        requireNativePriorDeliveryRecovery(root, expected)
        var reads = 0
        fun select(record: JSONObject = admission) {
            file.writeText(record.toString())
            args.putString("expectedRetainedExtraAdmissionSha256", hash(file))
        }
        fun read(current: NativeRenderer = renderer, installedXml: String = "f".repeat(64),
            installedApk: NativePackage = resource) =
            readNativeRetainedExtraAdmission(root, expected, current, mapping) {
                reads++
                installedApk to installedXml
            }
        select()
        read()
        val admittedReads = reads
        for (owner in listOf("baseline", "candidate")) {
            for (key in listOf("sourceSha256", "generatedXmlSha256", "builtXmlSha256", "installedXmlSha256",
                "builtApkSha256", "resourceApkSha256", "instanceSha256", "configurationSha256", "scopeSha256")) {
                val incomplete = JSONObject(admission.toString())
                incomplete.getJSONObject(owner).remove(key)
                select(incomplete)
                assertThrows(NativePending::class.java) { read() }
            }
        }
        // APK/test/probe/instance/config churn cannot qualify unchanged production XML.
        val samePayload = JSONObject(admission.toString())
        for (key in listOf("generatedXmlSha256", "builtXmlSha256", "installedXmlSha256")) {
            samePayload.getJSONObject("candidate").put(key, baseline.getString(key))
        }
        select(samePayload)
        assertThrows(NativePending::class.java) { read() }
        val wrongJoin = JSONObject(admission.toString())
        wrongJoin.getJSONObject("candidate").put("builtXmlSha256", "4".repeat(64))
        select(wrongJoin)
        assertThrows(NativePending::class.java) { read() }
        select()
        file.appendText(" ")
        assertThrows(NativePending::class.java) { read() }
        select()
        val held = File(root, "held-baseline")
        check(originalFile.renameTo(held))
        assertThrows(NativePending::class.java) { read() }
        check(held.renameTo(originalFile))
        assertEquals(admittedReads, reads)
        assertThrows(NativePending::class.java) { read(renderer.copy(instance = "changed")) }
        assertThrows(NativePending::class.java) { read(installedXml = "4".repeat(64)) }
        assertThrows(NativePending::class.java) { read(installedApk = resource.copy(apk = "4".repeat(64))) }
        assertThrows(NativePending::class.java) { read(installedApk = resource.copy(signer = "4".repeat(64))) }
        val selected = read()
        val case = nativeRetainedExtraCase(selected)
        val receipt = JSONObject().put("scenario", "delayed").put("productionXmlSha256", "f".repeat(64))
            .put("candidateAdmissionSha256", hash(file))
        val attemptDirectory = reserveNativeRetainedExtraCase(root, case, receipt)
        val reserved = File(attemptDirectory, "receipt.json").readText()
        assertEquals(case, AttemptJournal(File(root, "latest.json")).read().getString("case"))
        assertThrows(NativePending::class.java) { requireNativePriorDeliveryRecovery(root, expected) }
        assertThrows(NativePending::class.java) { reserveNativeRetainedExtraCase(root, case, receipt) }
        assertThrows(NativePending::class.java) {
            reserveNativeRetainedExtraCase(root, case, JSONObject(receipt.toString())
                .put("candidateAdmissionSha256", "6".repeat(64)))
        }
        assertEquals(reserved, File(attemptDirectory, "receipt.json").readText())
        val journal = AttemptJournal(nativeDeliveryReceipt(root, case))
        receipt.put("cleanupRequest", "normal requestUpdate returned; effective restoration Pending")
        journal.persist(receipt)
        args.putString("priorDeliveryRestorationReview", "complete")
        args.putString("expectedPriorDeliveryRestorationSha256", hash(File(attemptDirectory, "receipt.json")))
        assertThrows(NativePending::class.java) { requireNativePriorDeliveryRecovery(root, expected) }
        receipt.put("laterRestoration", "recorded; original-frame inspection and response provenance Pending")
        journal.persist(receipt)
        assertThrows(NativePending::class.java) { requireNativePriorDeliveryRecovery(root, expected) }
        args.putString("expectedPriorDeliveryRestorationSha256", hash(File(attemptDirectory, "receipt.json")))
        requireNativePriorDeliveryRecovery(root, expected)
        assertThrows(NativePending::class.java) { reserveNativeRetainedExtraCase(root, case, receipt) }
        assertThrows(NativePending::class.java) { requireNativeDeliveryCase(root, "delayed") }
        // A crash between global arming and the receipt consumes the payload and fences all later work.
        val partial = "delayed-payload-${"5".repeat(64)}"
        check(File(root, partial).mkdir())
        AttemptJournal(File(root, "latest.json")).persist(JSONObject().put("case", partial))
        assertThrows(NativePending::class.java) { requireNativePriorDeliveryRecovery(root, expected) }
        val privateContext = object : ContextWrapper(InstrumentationRegistry.getInstrumentation().targetContext) {
            override fun getFilesDir(): File = root.parentFile!!
        }
        assertEquals("retained-extra-reservation-unresolved", assertThrows(NativePending::class.java) {
            requireNativeNormalRecovery(privateContext, expected, mapping)
        }.identity)
        assertThrows(NativePending::class.java) {
            reserveNativeRetainedExtraCase(root, partial, JSONObject(receipt.toString())
                .put("productionXmlSha256", "5".repeat(64)))
        }
        assertEquals(originals, immutable.associateWith { it.readText() })
    }

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
            "observeDelivery:delayed-payload-${"f".repeat(64)}",
            "observeDelivery:fixture-n1_pair_zero_full", "observeDelivery:fixture-n3_reorder",
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

        val suffixes = listOf("n1_pair_zero_full", "n1_pair_full_zero", "n1_pair_both_zero",
            "n1_pair_tiny_near_full", "n1_pair_near_full_tiny", "n1_pair_below_above", "n1_pair_above_below",
            "n2_pairs_zero_tiny", "n2_pairs_tiny_zero", "n3_pairs_near_full", "n3_pairs_full_near",
            "n3_zero_tracks", "credits_only", "plan_credits", "n1_week_near_full", "n2_week_day", "n2_month_month")
        val catalog = suffixes.associate { "fixture-$it" to listOf("watch_dashboard_summary_$it.json") } +
            mapOf("fixture-n3_reorder" to listOf("watch_dashboard_summary_n3_reorder_before.json",
                "watch_dashboard_summary_n3_reorder_after.json"))
        assertEquals(catalog, nativeDeliveryFixtureAssets)
        assertEquals(18, catalog.size)
        val assets = catalog.values.flatten().associateWith { asset ->
            InstrumentationRegistry.getInstrumentation().context.assets.open(asset).use { it.readBytes() }
        }
        assertEquals(19, assets.size)
        val args = Bundle()
        val fixtureExpected = NativePushExpectations(args)
        var reads = 0
        var admittedPublications = 0
        fun read(scenario: String, debug: Boolean = true): List<NativeDeliveryFixture> =
            readNativeDeliveryFixtures(scenario, fixtureExpected, debug) { asset ->
                reads++
                assets.getValue(asset)
            }.also { admittedPublications += it.size }
        fun authorize(scenario: String) {
            args.clear()
            args.putString("authorizedOperation", "observeDelivery:$scenario")
            val selected = catalog.getValue(scenario)
            args.putString("expectedFixtureSha256", assets.getValue(selected.first()).inputStream().sha256())
            if (selected.size == 2) args.putString("expectedReorderAfterSha256",
                assets.getValue(selected.last()).inputStream().sha256())
        }
        for (invalid in listOf("", "../normal", "fixture-../n1_pair_zero_full", "fixture-n1_pair_zero_full/extra",
            "fixture-n1_pair_zero_full\\extra", "fixture-paired", "fixture-n2_inner_pair_below",
            "fixture-n3_reorder_before", "watch_dashboard_summary_credits_only.json", "Fixture-credits_only")) {
            assertThrows(NativePending::class.java) { read(invalid) }
        }
        val single = "fixture-n1_pair_zero_full"
        authorize(single)
        assertThrows(NativePending::class.java) { read(single, debug = false) }
        for (other in listOf("observeDelivery:normal", "observeDelivery:fixture-n1_pair_full_zero", "observeDelivery")) {
            args.putString("authorizedOperation", other)
            assertThrows(NativePending::class.java) { read(single) }
        }
        authorize(single)
        args.remove("expectedFixtureSha256")
        assertThrows(NativePending::class.java) { read(single) }
        for (malformed in listOf("abc", "A".repeat(64))) {
            args.putString("expectedFixtureSha256", malformed)
            assertThrows(NativePending::class.java) { read(single) }
        }
        assertEquals(0, reads)
        authorize(single)
        args.putString("expectedFixtureSha256", "f".repeat(64))
        assertThrows(NativePending::class.java) { read(single) }
        authorize("fixture-n3_reorder")
        args.remove("expectedReorderAfterSha256")
        val beforeMissingHash = reads
        assertThrows(NativePending::class.java) { read("fixture-n3_reorder") }
        assertEquals(beforeMissingHash, reads)
        authorize("fixture-n3_reorder")
        args.putString("expectedReorderAfterSha256", args.getString("expectedFixtureSha256"))
        assertThrows(NativePending::class.java) { read("fixture-n3_reorder") }
        assertEquals(0, admittedPublications) // Even a valid first input cannot escape a bad second hash.
        catalog.forEach { (scenario, names) ->
            authorize(scenario)
            val fixtures = read(scenario)
            assertEquals(names, fixtures.map { it.asset })
            fixtures.forEach { fixture ->
                assertTrue(assets.getValue(fixture.asset).contentEquals(fixture.encoded.toByteArray(Charsets.UTF_8)))
                assertEquals(assets.getValue(fixture.asset).inputStream().sha256(), fixture.sha256)
            }
        }
        assertEquals(19, admittedPublications)
        for (scenario in listOf("normal", "delayed", "obsolete", "recovery")) {
            args.putString("authorizedOperation", "observeDelivery:$scenario")
            val beforeNormal = reads
            assertTrue(read(scenario, debug = false).isEmpty())
            assertEquals(beforeNormal, reads)
        }
    }

    @Test
    fun targetedRequestsNeedActualInstanceMappingsRatherThanCanonicalOrCachedIds() {
        val slots = (11..18).toList()
        val roles = listOf("Today", "Week", "Ring3", "RingSplit", "StripSplit")
        val providers = slots.associateWith { slot -> if (slot <= 15)
            "$HOST_PACKAGE/app.wardpulse.wear.complication.${roles[slot - 11]}ComplicationDataSourceService" else null }
        val rows = slots.zip(listOf(407, 912, 219, 601, 307, 811, 509, 1100).map { it.toString() }).toMap()
        val types = slots.associateWith { if (it <= 15) 5 else 1 }
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
        val historicalConfiguration = """
            style
            11|enabled=true|app.wardpulse/app.wardpulse.wear.complication.TodayComplicationDataSourceService
            12|enabled=true|app.wardpulse/app.wardpulse.wear.complication.WeekComplicationDataSourceService
            13|enabled=true|app.wardpulse/app.wardpulse.wear.complication.Ring3ComplicationDataSourceService
            14|enabled=true|app.wardpulse/app.wardpulse.wear.complication.RingSplitComplicationDataSourceService
            15|enabled=true|app.wardpulse/app.wardpulse.wear.complication.StripSplitComplicationDataSourceService
            16|enabled=true|<none>
            17|enabled=true|<none>
            18|enabled=true|<none>
        """.trimIndent()
        assertEquals(historicalConfiguration, renderer.configuration)
        assertEquals(historicalConfiguration.sha256(), renderer.configuration.sha256())
        val reordered = providers + mapOf(11 to providers[14], 12 to providers[15], 13 to providers[11],
            14 to providers[12], 15 to providers[13])
        val layouts = listOf(
            providers to listOf(11 to 407, 12 to 912, 13 to 219, 14 to 601, 15 to 307),
            reordered to listOf(13 to 219, 14 to 601, 15 to 307, 11 to 407, 12 to 912),
        )
        for ((layout, expectedRoles) in layouts) {
            val order = listOf(15, 12, 18, 11, 16, 14, 17, 13)
            val currentSelections = selections.copy(providers = order.associateWith { layout.getValue(it) },
                configuredTypes = order.associateWith { types.getValue(it) },
                rowIds = order.associateWith { rows.getValue(it) })
            val current = renderer.copy(selections = currentSelections)
            val configuration = current.configuration
            assertEquals(9, configuration.lines().size)
            assertEquals(slots.toSet(), currentSelections.providers.keys)
            assertTrue((16..18).all { currentSelections.providers.containsKey(it) &&
                currentSelections.providers[it] == null })
            assertEquals(renderer.enabled, current.enabled)
            assertEquals(configuration, current.copy(selections = currentSelections.copy(providers = layout)).configuration)
            assertEquals(configuration, current.copy(selections = currentSelections.copy(
                rowIds = rows.mapValues { (_, id) -> (id.toInt() + 2000).toString() },
                configuredTypes = types.mapValues { 10 })).configuration)
            val disabled = current.copy(enabled = current.enabled + (18 to false))
            assertEquals(configuration.replace("18|enabled=true|<none>", "18|enabled=false|<none>"), disabled.configuration)
            if (layout == providers) {
                assertEquals(historicalConfiguration, configuration)
            } else {
                assertFalse(historicalConfiguration.sha256() == configuration.sha256())
            }
            val typed = configs.reversed().map { config -> config.copy(
                provider = ComponentName.unflattenFromString(layout.getValue(config.watchFaceSlotId)!!)) }
            if (layout != providers) {
                assertThrows(NativePending::class.java) { current.requireRetainedFrom(renderer) }
                assertThrows(NativePending::class.java) { discoverDeliveryTargets(typed, renderer, current) }
            }
            val joined = discoverDeliveryTargets(typed, current, current)
            assertEquals(expectedRoles, roles.map { service ->
                val component = ComponentName(HOST_PACKAGE,
                    "app.wardpulse.wear.complication.${service}ComplicationDataSourceService")
                joined.single { it.provider == component }.let { it.slot to it.systemId }
            })
            val (mainSlot, mainId) = expectedRoles[0]
            val (extraSlot, extraId) = expectedRoles[3]
            val client = nativeOverrideData("no-data-main-valid-extra", joined.reversed())
            assertEquals(setOf(mainSlot, extraSlot), client.keys)
            assertTrue(client.getValue(mainSlot) is NoDataComplicationData)
            assertTrue(client.getValue(extraSlot) is RangedValueComplicationData)
            val sdk = nativeSdkDirectData("no-data-main-valid-extra", joined.reversed())
            assertEquals(listOf(mainSlot to mainId, extraSlot to extraId), sdk.map { it.target.slot to it.target.systemId })
            assertEquals(android.support.wearable.complications.ComplicationData.TYPE_NO_DATA, sdk[0].data.type)
            assertEquals(android.support.wearable.complications.ComplicationData.TYPE_RANGED_VALUE, sdk[1].data.type)
        }
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
            val assets = nativeDeliveryAssets("fixture-n3_reorder").associateWith { asset ->
                instrumentation.context.assets.open(asset).use { it.readBytes() }
            }
            val args = Bundle().apply {
                putString("authorizedOperation", "observeDelivery:fixture-n3_reorder")
                putString("expectedFixtureSha256", assets.values.first().inputStream().sha256())
                putString("expectedReorderAfterSha256", assets.values.last().inputStream().sha256())
            }
            val fixtures = readNativeDeliveryFixtures("fixture-n3_reorder", NativePushExpectations(args), true,
                assets::getValue)
            instrumentation.runOnMainSync {
                val original = checkedDeliverySummary(false, "2026-01-01T00:00:00Z", preferences)
                val own = checkedDeliverySummary(true, "2026-01-01T00:01:00Z", preferences)
                val newer = deliverySummary(false, "2026-01-01T00:02:00Z")
                for (outcome in listOf("failure", "rejected", "newer", "during-persistence", "writers-unresolved", "absent")) {
                    check(preferences.edit().clear().commit())
                    if (outcome != "absent") check(WatchSummaryStore(preferences).saveEncoded(original))
                    val receipt = JSONObject()
                    val reserved = outcome in setOf("failure", "newer")
                    val recovery = if (reserved) {
                        receipt.put("scenario", "delayed").put("productionXmlSha256", outcome.sha256())
                            .put("candidateAdmissionSha256", "a".repeat(64))
                        reserveNativeRetainedExtraCase(directory, "delayed-payload-${outcome.sha256()}", receipt)
                    } else File(directory, outcome)
                    val journal = AttemptJournal(File(recovery, "receipt.json"))
                    var producerStarted = false
                    val lease = NativeSummaryLease(preferences, recovery, receipt, reserved = reserved) { persisted ->
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

                // One two-stage lease, with no conversion of packaged mock bytes or timestamps.
                val targets = listOf(NativeDeliveryTarget(11, 407, ComponentName(HOST_PACKAGE, "SyntheticMain")),
                    NativeDeliveryTarget(14, 601, ComponentName(HOST_PACKAGE, "SyntheticExtra")))
                val scope = NativeDatasourceProbeScope("a".repeat(64), "b".repeat(64), "c".repeat(64),
                    targets.fingerprint(), "e".repeat(64))
                for (outcome in listOf("reorder", "event-absent", "missing-requested", "invalid-bounded",
                    "unseen-before", "action-failure", "timeout", "persistence", "newer", "mapping-changed",
                    "wrong-armed-bytes")) {
                    check(WatchSummaryStore(preferences).saveEncoded(original))
                    val recovery = File(directory, "fixture-$outcome")
                    val receipt = JSONObject().put("events", JSONArray())
                    val lease = NativeSummaryLease(preferences, recovery, receipt)
                    val recovered = mutableListOf<Int>()
                    val actionFailure = if (outcome == "timeout") TimeoutException() else java.io.IOException()
                    val persistenceFailure = java.io.IOException()
                    val cleanupFailure = java.io.IOException()
                    var failedPersistence = false
                    var firstStageBeforeRecovery: String? = null
                    fun stage(fixture: NativeDeliveryFixture, stage: String) = observeNativeDeliveryStage(
                        recovery, stage, targets, targets, scope, receipt, fixture, persist = {
                            if (outcome == "persistence" && !failedPersistence &&
                                receipt.getJSONArray("events").getJSONObject(0).getString("observation") != "Pending") {
                                failedPersistence = true
                                throw persistenceFailure
                            }
                            AttemptJournal(File(recovery, "receipt.json")).persist(receipt)
                        }, validate = { lease.requireOwned(); scope }, awaitEvent = { action ->
                            // A generic event without the command cannot establish the before stage.
                            if (outcome != "unseen-before" || stage != "reorder-before") action()
                            if (outcome == "event-absent") throw TimeoutException()
                        }, request = { _, _ ->
                            if (outcome in setOf("timeout", "action-failure")) throw actionFailure
                        }, capture = { label, bounded ->
                            if (outcome != "missing-requested" || bounded) {
                                val bitmap = Bitmap.createBitmap(1, 1, Bitmap.Config.ARGB_8888)
                                try {
                                    bitmap.eraseColor(android.graphics.Color.BLACK)
                                    File(recovery, "$label.png").outputStream().use {
                                        check(bitmap.compress(Bitmap.CompressFormat.PNG, 100, it))
                                    }
                                } finally { bitmap.recycle() }
                                File(recovery, "$label.json").writeText(JSONObject()
                                    .put("instanceSha256", scope.instanceSha256)
                                    .put("configurationSha256", if (outcome == "invalid-bounded" && bounded)
                                        "f".repeat(64) else scope.configurationSha256)
                                    .put("nativeRecordAcquired", if (bounded) "before frame" else "after frame")
                                    .put("effectiveData", JSONObject().put("11", "NoDataComplicationData()"))
                                    .put("responseProvenance", "Pending").put("visualAcceptance", "Pending").toString())
                            }
                        })
                    val result = runCatching {
                        var primary: Throwable? = null
                        try {
                            val first = fixtures.first()
                            lease.armPublication(first.encoded)
                            assertEquals(original, preferences.getString("latest", null))
                            assertEquals("armed; acceptance Pending", AttemptJournal(File(recovery, "receipt.json"))
                                .read().getJSONArray("publications").getJSONObject(0).getString("state"))
                            if (outcome == "mapping-changed") throw NativePending("synthetic-mapping-changed")
                            if (outcome == "wrong-armed-bytes") lease.publish(fixtures.last().encoded)
                            lease.publish(first.encoded)
                            assertEquals(first.encoded, preferences.getString("latest", null))
                            assertEquals(WatchDataMode.MOCK, WatchSummaryStore(preferences).load()!!.dataMode)
                            assertEquals(JSONObject(first.encoded).getString("generatedAt"),
                                WatchSummaryStore(preferences).load()!!.generatedAt)
                            val unseen = if (outcome == "unseen-before") assertThrows(NativePending::class.java) {
                                stage(first, "reorder-before")
                            } else { stage(first, "reorder-before"); null }
                            if (outcome == "newer") check(WatchSummaryStore(preferences).saveEncoded(newer))
                            lease.armPublication(fixtures.last().encoded)
                            lease.publish(fixtures.last().encoded)
                            assertTrue(outcome in setOf("reorder", "event-absent", "unseen-before"))
                            assertEquals(fixtures.last().encoded, preferences.getString("latest", null))
                            assertEquals(WatchDataMode.MOCK, WatchSummaryStore(preferences).load()!!.dataMode)
                            assertEquals(JSONObject(fixtures.last().encoded).getString("generatedAt"),
                                WatchSummaryStore(preferences).load()!!.generatedAt)
                            stage(fixtures.last(), "reorder-after")
                            // Later valid evidence cannot backfill the deliberately unseen first stage.
                            unseen?.let { throw it }
                        } catch (caught: Throwable) {
                            primary = caught
                            throw caught
                        } finally {
                            firstStageBeforeRecovery = receipt.getJSONArray("events").optJSONObject(0)?.toString()
                            try {
                                try { lease.close(quietWriter = true) } finally {
                                    val calls = JSONArray()
                                    receipt.put("cleanupCalls", calls)
                                    requestNativeDelivery(targets, targets, calls,
                                        { AttemptJournal(File(recovery, "receipt.json")).persist(receipt) },
                                        { targets }, recovery = true) { _, ids ->
                                        recovered += ids.toList()
                                        if (outcome in setOf("timeout", "action-failure") && ids.single() == 407)
                                            throw cleanupFailure
                                    }
                                }
                            } catch (cleanup: Throwable) {
                                if (primary == null) throw cleanup else primary.addSuppressed(cleanup)
                            }
                        }
                    }
                    val failure = result.exceptionOrNull()
                    when (outcome) {
                        "reorder", "event-absent" -> assertTrue(result.isSuccess)
                        "timeout", "action-failure" -> {
                            assertSame(actionFailure, failure)
                            assertTrue(failure!!.suppressed.contains(cleanupFailure))
                        }
                        "persistence" -> { assertSame(persistenceFailure, failure); assertTrue(failedPersistence) }
                        else -> assertEquals(when (outcome) {
                            "missing-requested" -> "complete-delivery-stage-original"
                            "invalid-bounded" -> "delivery-stage-native-record-scope"
                            "unseen-before" -> "delivery-stage-command-unobserved"
                            "newer" -> "quiet-summary-writer"
                            "mapping-changed" -> "synthetic-mapping-changed"
                            "wrong-armed-bytes" -> "armed-publication-bytes"
                            else -> error("Unknown guard subcase")
                        }, (failure as? NativePending)?.identity)
                    }
                    val events = receipt.getJSONArray("events")
                    assertEquals(when (outcome) {
                        "mapping-changed", "wrong-armed-bytes" -> 0
                        "reorder", "event-absent", "unseen-before" -> 2
                        else -> 1
                    }, events.length())
                    assertEquals(firstStageBeforeRecovery, events.optJSONObject(0)?.toString())
                    if (events.length() > 0) {
                        val entry = events.getJSONObject(0)
                        assertEquals(fixtures.first().sha256, entry.getString("fixtureSha256"))
                        assertEquals(fixtures.first().sha256, entry.getString("acceptedSummarySha256"))
                        assertEquals(scope.scopeSha256, entry.getString("scopeSha256"))
                        assertEquals(scope.mappingSha256, entry.getString("mappingSha256"))
                        assertEquals(407, entry.getJSONArray("targets").getJSONObject(0).getInt("systemId"))
                        assertEquals("Pending", entry.getString("responseProvenance"))
                        assertEquals("Pending", entry.getString("visualAcceptance"))
                        assertEquals(5_000, entry.getInt("eventWaitMillis"))
                        if (outcome in setOf("missing-requested", "invalid-bounded", "unseen-before", "persistence")) {
                            assertEquals("Pending", entry.getString("observation"))
                            assertEquals("runtime content event observed; provenance Pending", entry.getString("event"))
                        }
                        if (outcome in setOf("timeout", "action-failure")) {
                            assertEquals("Pending", entry.getString("observation"))
                            assertEquals("request", entry.getString("failureSubstage"))
                            assertEquals(nativeReadFailure(actionFailure).value, entry.getString("failureOutcome"))
                            assertTrue(entry.getString("event").startsWith("Pending"))
                        }
                        for (index in 0 until events.length()) {
                            val reached = events.getJSONObject(index)
                            if (outcome in setOf("reorder", "event-absent", "newer") || index == 1) {
                                assertTrue(reached.getString("observation").startsWith("requested and bounded originals recorded"))
                                assertEquals(if (outcome == "event-absent") "unavailable within bound; transition Pending"
                                    else "runtime content event observed; provenance Pending", reached.getString("event"))
                                for (key in listOf("requestedOriginal", "boundedOriginal")) {
                                    val captured = reached.getJSONObject(key)
                                    assertEquals(File(recovery, captured.getString("frame")).inputStream().sha256(),
                                        captured.getString("frameSha256"))
                                    assertEquals(File(recovery, captured.getString("nativeRecord")).inputStream().sha256(),
                                        captured.getString("nativeRecordSha256"))
                                }
                                assertEquals(11, reached.getJSONArray("noDataSlotsObserved").getInt(0))
                                assertEquals(fixtures[index].sha256, reached.getString("fixtureSha256"))
                            }
                        }
                    }
                    assertEquals(firstStageBeforeRecovery, AttemptJournal(File(recovery, "receipt.json")).read()
                        .getJSONArray("events").optJSONObject(0)?.toString())
                    assertEquals(listOf(407, 601), recovered)
                    assertEquals(if (outcome == "newer") newer else original, preferences.getString("latest", null))
                    assertEquals(original, File(recovery, "original.bin").readBytes().drop(1).toByteArray()
                        .toString(Charsets.UTF_8))
                    assertTrue(assets.getValue(fixtures.first().asset).contentEquals(
                        File(recovery, "owned-0.bin").readBytes().drop(1).toByteArray()))
                    if (outcome in setOf("reorder", "event-absent", "unseen-before")) {
                        assertTrue(assets.getValue(fixtures.last().asset).contentEquals(
                            File(recovery, "owned-1.bin").readBytes().drop(1).toByteArray()))
                        assertEquals(2, receipt.getJSONArray("publications").length())
                    } else assertEquals(1, receipt.getJSONArray("publications").length())
                    if (outcome == "newer") {
                        assertEquals(newer, File(recovery, "newer.bin").readBytes().drop(1).toByteArray()
                            .toString(Charsets.UTF_8))
                        assertTrue(receipt.getString("restoration").contains("Pending"))
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
