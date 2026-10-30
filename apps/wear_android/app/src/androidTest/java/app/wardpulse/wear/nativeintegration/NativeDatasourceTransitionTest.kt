package app.wardpulse.wear.nativeintegration

import android.content.Context
import android.graphics.Bitmap
import android.os.Bundle
import android.view.accessibility.AccessibilityEvent
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import androidx.wear.watchface.complications.datasource.ComplicationDataSourceUpdateRequester
import java.io.File
import java.time.Instant
import java.util.concurrent.TimeoutException
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Test
import org.junit.runner.RunWith

/** Current-target observations. No Activity, choice edit, receiver disable or renderer override. */
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
        val mapping = mappings(renderer)
        val targets = mapping.targets
        nativeGuard(probe.mkdirs(), "fresh-delivery-probe")
        val receipt = JSONObject().put("configurationSha256", renderer.configuration.sha256())
            .put("mappingSha256", targets.fingerprint()).put("instanceSha256", renderer.instance.sha256())
            .put("scopeSha256", mapping.scopeSha256)
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
            expected.required("firstFrameReview") == "complete-unobscured", "host-delivery-preconditions")
        val scenario = expected.required("deliveryScenario")
        nativeGuard(scenario in setOf("normal", "delayed", "obsolete", "recovery"), "delivery-scenario")
        requireNativeDatasourceMutation(expected, "observeDelivery:$scenario")
        val before = renderer()
        val mapping = mappings(before)
        val targets = mapping.targets
        val preflight = AttemptJournal(File(probe, "receipt.json")).read()
        nativeGuard(preflight.getString("frameSha256") == expected.hash("expectedReviewedFrameSha256") &&
            File(probe, "first.png").inputStream().sha256() == expected.hash("expectedReviewedFrameSha256") &&
            preflight.getString("hostApkSha256") == NativePackage.read(target, HOST_PACKAGE).apk &&
            preflight.getString("configurationSha256") == before.configuration.sha256() &&
            preflight.getString("instanceSha256") == before.instance.sha256() &&
            preflight.getString("scopeSha256") == mapping.scopeSha256 &&
            preflight.getString("mappingSha256") == targets.fingerprint(), "reviewed-first-original")
        quietBridge()
        requirePriorRecovery()
        val directory = File(root, scenario)
        val receipt = JSONObject().put("scenario", scenario).put("bridge", "unchanged by instrumentation")
            .put("reviewedFirstFrameSha256", expected.hash("expectedReviewedFrameSha256"))
            .put("mappingSha256", targets.fingerprint()).put("scopeSha256", mapping.scopeSha256)
            .put("authorizedOperation", "observeDelivery:$scenario").put("responseProvenance", "Pending")
            .put("effectiveRendering", "Pending").put("events", JSONArray())
        var lease: NativeSummaryLease? = null
        try {
            AttemptJournal(File(root, "latest.json")).persist(JSONObject().put("case", scenario))
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
                        requestNativeDelivery(targets, selected, entry.getJSONArray("calls"),
                            persist = { AttemptJournal(File(directory, "receipt.json")).persist(receipt) },
                            validate = {
                                val fresh = mappings(before).targets
                                quietBridge()
                                instrumentation.runOnMainSync { checkNotNull(lease).requireOwned() }
                                fresh
                            }) { provider, ids ->
                            ComplicationDataSourceUpdateRequester.create(target, provider).requestUpdate(*ids)
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
                    // Independent normal-data recovery uses only freshly revalidated intended targets.
                    // An unresolved mapping or dispatch stays Pending; no stale IDs or blanket requests.
                    val summary = target.getSharedPreferences("watch_summary", Context.MODE_PRIVATE).getString("latest", null)
                    val calls = JSONArray()
                    receipt.put("cleanupSummaryPresent", summary != null)
                        .put("cleanupSummarySha256", summary?.sha256() ?: JSONObject.NULL)
                        .put("cleanupRequest", "normal targeted recovery Pending").put("cleanupCalls", calls)
                    requestNativeDelivery(targets, targets, calls,
                        persist = { AttemptJournal(File(directory, "receipt.json")).persist(receipt) },
                        validate = { quietBridge(); mappings(before).targets }, recovery = true) { provider, ids ->
                        ComplicationDataSourceUpdateRequester.create(target, provider).requestUpdate(*ids)
                    }
                    receipt.put("cleanupRequest", "normal requestUpdate returned; effective restoration Pending")
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
            "normal requestUpdate returned; effective restoration Pending", "single-later-restoration")
        receipt.put("laterRestoration", "armed; native observation Pending")
        journal.persist(receipt)
        val current = renderer()
        val mapping = mappings(current)
        nativeGuard(mapping.targets.fingerprint() == receipt.getString("mappingSha256") &&
            mapping.scopeSha256 == receipt.getString("scopeSha256"), "restoration-mapping")
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
        NativeReadAdmission(instrumentation, expected).admit(method, DELIVERY_CLASS, "normal-delivery")
    }

    private fun requirePriorRecovery() {
        val latest = AttemptJournal(File(root, "latest.json"))
        if (!latest.exists()) return
        val scenario = latest.read().getString("case")
        nativeGuard(scenario in setOf("normal", "delayed", "obsolete", "recovery"), "prior-delivery-case")
        val file = File(root, "$scenario/receipt.json")
        val receipt = AttemptJournal(file).read()
        nativeGuard(receipt.optString("cleanupRequest") == "normal requestUpdate returned; effective restoration Pending" &&
            receipt.optString("laterRestoration") == "recorded; original-frame inspection and response provenance Pending" &&
            expected.required("priorDeliveryRestorationReview") == "complete" &&
            file.inputStream().sha256() == expected.hash("expectedPriorDeliveryRestorationSha256"),
            "prior-delivery-recovery-unresolved")
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

    private fun mappings(before: NativeRenderer): NativeDeliveryMapping {
        return readNativeDeliveryTargets(instrumentation, expected, before).also { mapping ->
            val services = mapping.targets.map { it.provider.className.substringAfterLast('.') }.toSet()
            nativeGuard(listOf("Today", "Week", "Ring3", "RingSplit", "StripSplit").all {
                "${it}ComplicationDataSourceService" in services
            }, "enabled-lower-delivery-targets")
        }
    }

    private fun retained(before: NativeRenderer, targets: List<NativeDeliveryTarget>): NativeRenderer {
        val current = renderer()
        requireRetained(current, before)
        nativeGuard(mappings(current).targets == targets, "retained-runtime-mapping")
        return current
    }

    private fun renderer() = device.readRenderer(expected).also {
        nativeGuard(it.instance.sha256() == expected.hash("expectedInstanceSha256") &&
            it.configuration.sha256() == expected.hash("expectedConfigurationSha256"), "delivery-renderer-identity")
    }

    private fun requireRetained(after: NativeRenderer, before: NativeRenderer) =
        requireNativeDeliveryScope(after, before)

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
