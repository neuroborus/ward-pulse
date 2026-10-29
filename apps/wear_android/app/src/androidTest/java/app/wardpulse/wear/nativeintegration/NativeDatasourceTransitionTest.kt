package app.wardpulse.wear.nativeintegration

import android.content.ComponentName
import android.content.Context
import android.graphics.Bitmap
import android.os.Bundle
import android.view.accessibility.AccessibilityEvent
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import androidx.wear.watchface.complications.datasource.ComplicationDataSourceUpdateRequester
import app.wardpulse.wear.complication.WatchComplicationUpdater
import java.io.File
import java.time.Instant
import java.util.concurrent.TimeoutException
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Test
import org.junit.runner.RunWith

/** Post-witness only. No Activity, binding/choice edit, receiver disable or renderer override. */
@ManualNativeIntegration
@RunWith(AndroidJUnit4::class)
class NativeDatasourceTransitionTest {
    private val instrumentation = InstrumentationRegistry.getInstrumentation()
    private val target = instrumentation.targetContext
    private val arguments = InstrumentationRegistry.getArguments()
    private val expected = NativePushExpectations(arguments)
    private val device = NativePushDevice(instrumentation)
    private val root get() = File(target.filesDir, "native_datasource")
    private val probe get() = File(root, "probe")

    /** Exactly one first original. HOST must inspect it before authorizing a bounded scenario. */
    @Test
    fun probeDelivery() = sanitized {
        admit("probeDelivery")
        val renderer = renderer()
        val targets = mappings(renderer)
        nativeGuard(probe.mkdirs(), "fresh-delivery-probe")
        val receipt = JSONObject().put("configurationSha256", renderer.configuration.sha256())
            .put("mappingSha256", targets.fingerprint()).put("instanceSha256", renderer.instance.sha256())
            .put("hostApkSha256", NativePackage.read(target, HOST_PACKAGE).apk)
            .put("frameReview", "Pending")
        AttemptJournal(File(probe, "receipt.json")).persist(receipt)
        observe(probe, "first", renderer)
        receipt.put("frameSha256", File(probe, "first.png").inputStream().sha256())
        AttemptJournal(File(probe, "receipt.json")).persist(receipt)
        report("Read-only mapping probe recorded; first original-frame inspection and delivery remain Pending.")
    }

    /** One finite scenario per explicit invocation; every publication is enclosed by recovery. */
    @Test
    fun observeDelivery() = sanitized {
        admit("observeDelivery")
        nativeGuard(expected.required("quietWriters") == "confirmed-unpaired" &&
            expected.required("firstFrameReview") == "complete-unobscured" &&
            expected.required("managerWitnessReview") == "complete", "host-delivery-preconditions")
        val scenario = expected.required("deliveryScenario")
        nativeGuard(scenario in setOf("normal", "delayed", "obsolete", "recovery"), "delivery-scenario")
        val before = renderer()
        val targets = mappings(before)
        val preflight = AttemptJournal(File(probe, "receipt.json")).read()
        nativeGuard(preflight.getString("frameSha256") == expected.hash("expectedReviewedFrameSha256") &&
            File(probe, "first.png").inputStream().sha256() == expected.hash("expectedReviewedFrameSha256") &&
            preflight.getString("hostApkSha256") == NativePackage.read(target, HOST_PACKAGE).apk &&
            preflight.getString("configurationSha256") == before.configuration.sha256() &&
            preflight.getString("instanceSha256") == before.instance.sha256() &&
            preflight.getString("mappingSha256") == targets.fingerprint(), "reviewed-first-original")
        quietBridge()
        val directory = File(root, scenario)
        val receipt = JSONObject().put("scenario", scenario).put("bridge", "unchanged by instrumentation")
            .put("reviewedFirstFrameSha256", expected.hash("expectedReviewedFrameSha256"))
            .put("mappingSha256", targets.fingerprint()).put("responseProvenance", "Pending")
            .put("effectiveRendering", "Pending").put("events", JSONArray())
        var lease: NativeSummaryLease? = null
        try {
            instrumentation.runOnMainSync {
                lease = NativeSummaryLease(target.getSharedPreferences("watch_summary", Context.MODE_PRIVATE),
                    directory, receipt)
            }
            observe(directory, "before", before)
            fun publish(pair: Boolean) {
                quietBridge()
                retained(before, targets)
                val encoded = deliverySummary(pair, Instant.now().toString())
                instrumentation.runOnMainSync { checkNotNull(lease).publish(encoded) }
            }
            fun stage(name: String, selected: List<NativeDeliveryTarget>) {
                retained(before, targets)
                instrumentation.runOnMainSync { checkNotNull(lease).requireOwned() }
                val entry = JSONObject().put("stage", name).put("request", "armed; dispatch Pending")
                    .put("acceptedSummarySha256", receipt.getString("ownedSha256")).put("calls", JSONArray())
                    .put("targets", JSONArray(selected.map { row -> JSONObject().put("slot", row.slot)
                        .put("systemId", row.systemId).put("providerSha256", row.provider.flattenToString().sha256()) }))
                receipt.getJSONArray("events").put(entry)
                AttemptJournal(File(directory, "receipt.json")).persist(receipt)
                // A matching accessibility event is only an observation boundary, never a delivery ACK.
                try {
                    val event = instrumentation.uiAutomation.executeAndWaitForEvent({
                        selected.groupBy { it.provider }.forEach { (provider, rows) ->
                            val call = JSONObject().put("providerSha256", provider.flattenToString().sha256())
                                .put("systemIds", JSONArray(rows.map { it.systemId })).put("state", "armed; dispatch uncertain")
                            entry.getJSONArray("calls").put(call)
                            AttemptJournal(File(directory, "receipt.json")).persist(receipt)
                            ComplicationDataSourceUpdateRequester.create(target, provider)
                                .requestUpdate(*rows.map { it.systemId }.toIntArray())
                            call.put("state", "requestUpdate returned; delivery Pending")
                            AttemptJournal(File(directory, "receipt.json")).persist(receipt)
                        }
                        entry.put("request", "requestUpdate returned; response Pending")
                        AttemptJournal(File(directory, "receipt.json")).persist(receipt)
                        observe(directory, "$name-requested")
                    }, { event -> event.packageName?.toString() == RUNTIME_PACKAGE &&
                        event.eventType == AccessibilityEvent.TYPE_WINDOW_CONTENT_CHANGED }, 5_000)
                    try { entry.put("event", "runtime content event observed; provenance Pending") }
                    finally { event.recycle() }
                } catch (_: TimeoutException) {
                    entry.put("event", "unavailable within bound; transition Pending")
                }
                val observed = retained(before, targets)
                instrumentation.runOnMainSync { checkNotNull(lease).requireOwned() }
                observe(directory, "$name-bounded", observed)
                entry.put("noDataSlotsObserved", JSONArray(targets.filter { row ->
                    observed.effectiveData[row.slot]?.startsWith("NoDataComplicationData(") == true
                }.map { it.slot })).put("effectiveDataSha256", JSONObject(observed.effectiveData.mapKeys { it.key.toString() })
                    .toString().sha256())
                AttemptJournal(File(directory, "receipt.json")).persist(receipt)
            }
            publish(pair = true)
            stage("normal-pair", targets)
            if (scenario != "normal") {
                publish(pair = false)
                if (scenario == "delayed") {
                    val mains = targets.filterNot { it.provider.className.endsWith("SplitComplicationDataSourceService") }
                    stage("main-only", mains)
                    stage("delayed-extra", targets - mains.toSet())
                } else stage("obsolete-selection", targets)
                if (scenario == "recovery") {
                    publish(pair = true)
                    stage("pair-recovery", targets)
                }
            }
        } finally {
            // No failing observation, timeout or requester can bypass normal-data recovery.
            try {
                var quiet = false
                try {
                    if (lease != null) {
                        quietBridge()
                        quiet = true
                    }
                } finally {
                    instrumentation.runOnMainSync { lease?.close(quiet) }
                }
            } finally {
                if (lease != null) {
                    // Requests are normal provider delivery, including a preserved newer publication.
                    // Do not reuse stale system IDs if a selection/instance changed during cleanup.
                    val summary = target.getSharedPreferences("watch_summary", Context.MODE_PRIVATE).getString("latest", null)
                    receipt.put("cleanupSummaryPresent", summary != null)
                        .put("cleanupSummarySha256", summary?.sha256() ?: JSONObject.NULL)
                        .put("cleanupRequest", "normal updateAll armed; dispatch uncertain")
                    try {
                        AttemptJournal(File(directory, "receipt.json")).persist(receipt)
                    } finally {
                        WatchComplicationUpdater.requestUpdate(target)
                    }
                    receipt.put("cleanupRequest", "normal updateAll returned; effective restoration Pending")
                    AttemptJournal(File(directory, "receipt.json")).persist(receipt)
                    val restored = retained(before, targets)
                    observe(directory, "restoration", restored)
                    receipt.put("effectiveDataEqualToBefore", restored.effectiveData == before.effectiveData)
                        .put("effectiveRestoration", "original captured; provenance and visual review Pending")
                    AttemptJournal(File(directory, "receipt.json")).persist(receipt)
                }
            }
        }
        nativeGuard(receipt.getString("restoration") in setOf("original bytes observed", "original bytes restored"),
            "summary-restoration-reconciliation")
        report("Bounded $scenario observations recorded separately from requests and accepted summaries. " +
            "Response provenance, transitions and effective restoration remain Pending HOST review; retain private recovery files.")
    }

    /** A separate later observation; cleanup's immediate frame cannot prove settled restoration. */
    @Test
    fun observeRestoration() = sanitized {
        admit("observeRestoration")
        val scenario = expected.required("deliveryScenario")
        nativeGuard(scenario in setOf("normal", "delayed", "obsolete", "recovery"), "delivery-scenario")
        val directory = File(root, scenario)
        val journal = AttemptJournal(File(directory, "receipt.json"))
        val receipt = journal.read()
        nativeGuard(!receipt.has("laterRestoration") && receipt.optString("cleanupRequest") ==
            "normal updateAll returned; effective restoration Pending", "single-later-restoration")
        receipt.put("laterRestoration", "armed; native observation Pending")
        journal.persist(receipt)
        val current = renderer()
        nativeGuard(mappings(current).fingerprint() == receipt.getString("mappingSha256"), "restoration-mapping")
        val summary = target.getSharedPreferences("watch_summary", Context.MODE_PRIVATE).getString("latest", null)
        val unchanged = (summary != null) == receipt.getBoolean("cleanupSummaryPresent") &&
            (summary == null || summary.sha256() == receipt.getString("cleanupSummarySha256"))
        observe(directory, "restoration-later", current)
        receipt.put("laterRestoration", "recorded; original-frame inspection and response provenance Pending")
            .put("cleanupSummaryStillCurrent", unchanged)
            .put("restorationComparison", if (unchanged) "compare private before/after records; semantic review Pending"
                else "newer live publication observed; reconcile current normal delivery, Pending")
        journal.persist(receipt)
        report("Separate restoration original recorded; data provenance, newer-write reconciliation and visual acceptance Pending.")
    }

    private fun admit(method: String) {
        device.admit(expected, method, DELIVERY_CLASS, "normal-delivery")
        val host = NativePackage.read(target, HOST_PACKAGE)
        nativeGuard(host.code == 4L && host.apk == expected.hash("expectedHostApkSha256") &&
            host.signer == expected.hash("expectedHostSignerSha256"), "delivery-host")
        nativeGuard(target.assets.open("default_watchface.apk").sha256() == expected.hash("expectedAsset3Sha256"),
            "delivery-asset-3")
        val push = NativePackage.read(target, CANDIDATE_PACKAGE)
        nativeGuard(push.code == 4L && push.apk == expected.hash("expectedPush4ApkSha256") &&
            push.signer == expected.hash("expectedPushSignerSha256"), "retained-push-4")
        val legacy = NativePackage.read(target, "app.wardpulse.watchface")
        nativeGuard(legacy.code == 2L && legacy.apk == expected.hash("expectedLegacyApkSha256") &&
            legacy.signer == expected.hash("expectedLegacySignerSha256"), "retained-legacy-2")
        // This route cannot be used to bypass the pre-replacement manager witness.
        val update = AttemptJournal(File(target.filesDir, "native_push_update/attempt.json")).read()
        nativeGuard(update.optString("state") == "result-verified" &&
            update.optString("resourceCleanup") == "verified" &&
            update.optString("pushConfigurationRetention") == "verified from Push-owned selection records" &&
            update.optString("nativeObservation") == "recorded; original-frame inspection Pending" &&
            update.optString("candidateApkSha256") == push.apk, "prior-manager-witness")
    }

    private fun quietBridge() {
        // Transport/producer quietness requires HOST ownership and independent peer/bridge checks.
        // This service observation cannot establish the absence of future publications.
        nativeGuard(expected.required("quietWriters") == "confirmed-unpaired", "host-quiet-bridge-precondition")
        val services = device.shell("dumpsys activity services $HOST_PACKAGE")
        nativeGuard(services.startsWith("ACTIVITY MANAGER SERVICES (dumpsys activity services)") &&
            !services.contains("WatchSummaryListenerService"),
            "quiet-summary-owners")
    }

    private fun mappings(before: NativeRenderer): List<NativeDeliveryTarget> {
        val component = ComponentName(RUNTIME_PACKAGE, "$RUNTIME_PACKAGE.${expected.required("expectedRuntime")}")
        val records = device.shell("dumpsys activity service com.google.android.wearable.app")
        val after = renderer()
        requireRetained(after, before)
        return discoverDeliveryTargets(records, component, after).also { targets ->
            val services = targets.map { it.provider.className.substringAfterLast('.') }.toSet()
            nativeGuard(listOf("Today", "Week", "Ring3", "RingSplit", "StripSplit").all {
                "${it}ComplicationDataSourceService" in services
            }, "enabled-lower-delivery-targets")
        }
    }

    private fun retained(before: NativeRenderer, targets: List<NativeDeliveryTarget>): NativeRenderer {
        val current = renderer()
        requireRetained(current, before)
        nativeGuard(mappings(current) == targets, "retained-runtime-mapping")
        return current
    }

    private fun renderer() = device.readRenderer(expected).also {
        nativeGuard(it.instance.sha256() == expected.hash("expectedInstanceSha256") &&
            it.configuration.sha256() == expected.hash("expectedConfigurationSha256"), "delivery-renderer-identity")
    }

    private fun requireRetained(after: NativeRenderer, before: NativeRenderer) = nativeGuard(
        after.resourcePackage == before.resourcePackage && after.instance == before.instance &&
            after.configuration == before.configuration, "retained-delivery-configuration")

    private fun observe(directory: File, name: String, renderer: NativeRenderer? = null) {
        val file = File(directory, "$name.png")
        nativeGuard(file.createNewFile(), "single-original-frame")
        // Capture the requested frame before the potentially slow native selection lookup.
        val bitmap = checkNotNull(instrumentation.uiAutomation.takeScreenshot())
        try {
            file.outputStream().use { nativeGuard(bitmap.compress(Bitmap.CompressFormat.PNG, 100, it), "delivery-frame") }
        } finally { bitmap.recycle() }
        val observed = renderer ?: device.readRenderer(expected)
        val record = JSONObject().put("instanceSha256", observed.instance.sha256())
            .put("configurationSha256", observed.configuration.sha256())
            .put("effectiveData", JSONObject(observed.effectiveData.mapKeys { it.key.toString() }))
            .put("nativeRecordAcquired", if (renderer == null) "after frame" else "before frame")
            .put("responseProvenance", "Pending").put("visualAcceptance", "Pending")
        AttemptJournal(File(directory, "$name.json")).persist(record)
    }

    private fun sanitized(action: () -> Unit) {
        try { action() } catch (failure: Throwable) {
            val reason = (failure as? NativePending)?.identity ?: "capability-or-observation-unavailable"
            throw AssertionError("Pending: normal datasource integration ($reason); retain private recovery and originals.")
        }
    }

    private fun report(message: String) = instrumentation.sendStatus(0, Bundle().apply {
        putString("stream", "\nNative datasource: $message\n")
    })
}
