package app.wardpulse.wear.nativeintegration

import android.content.Context
import android.graphics.Bitmap
import android.os.Bundle
import android.support.wearable.complications.ComplicationData as WireComplicationData
import android.view.accessibility.AccessibilityEvent
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import androidx.wear.watchface.complications.datasource.ComplicationDataSourceUpdateRequester
import app.wardpulse.wear.BuildConfig
import app.wardpulse.wear.data.WatchSummaryStore
import java.io.File
import java.time.Instant
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

    /** Exactly one first original. HOST must inspect it before authorizing a bounded scenario. */
    @Test
    fun probeDelivery() = sanitized {
        admit("probeDelivery")
        val probe = NativeDatasourceProbe(root, expected.required("deliveryProbeId"))
        val before = renderer()
        val mapping = mappings(before)
        probe.create(probeScope(before, mapping), capture = { observe(it, "first", before) }, currentScope = {
            val current = renderer()
            requireRetained(current, before)
            probeScope(current, mappings(current))
        })
        report("Read-only mapping probe recorded; first original-frame inspection and delivery remain Pending.")
    }

    /** One finite scenario per explicit invocation; every publication is enclosed by recovery. */
    @Test
    fun observeDelivery() = sanitized {
        admit("observeDelivery")
        val probe = NativeDatasourceProbe(root, expected.required("deliveryProbeId"))
        nativeGuard(expected.required("quietWriters") == "confirmed-unpaired" &&
            expected.required("firstFrameReview") == "complete-unobscured", "host-delivery-preconditions")
        val scenario = expected.required("deliveryScenario")
        val fixtures = readNativeDeliveryFixtures(scenario, expected, BuildConfig.DEBUG) { asset ->
            instrumentation.context.assets.open(asset).use { it.readBytes() }
        }
        val before = renderer()
        val mapping = mappings(before)
        val targets = mapping.targets
        val selected = probe.reviewed(probeScope(before, mapping), expected.hash("expectedDeliveryProbeSha256"),
            expected.hash("expectedReviewedFrameSha256"))
        quietBridge()
        requireNativePriorDeliveryRecovery(root, expected)
        val directory = requireNativeDeliveryCase(root, scenario)
        val receipt = JSONObject().put("scenario", scenario).put("bridge", "unchanged by instrumentation")
            .put("deliveryProbeId", selected.id).put("reviewedProbeSha256", selected.receiptSha256)
            .put("reviewedFirstFrameSha256", selected.frameSha256)
            .put("mappingSha256", targets.fingerprint()).put("scopeSha256", mapping.scopeSha256)
            .put("authorizedOperation", "observeDelivery:$scenario").put("responseProvenance", "Pending")
            .put("effectiveRendering", "Pending").put("events", JSONArray())
            .put("fixtureInputs", JSONArray(fixtures.mapIndexed { index, fixture ->
                JSONObject().put("asset", fixture.asset).put("sha256", fixture.sha256)
                    .put("stage", if (fixtures.size == 1) "fixture" else if (index == 0) "reorder-before" else "reorder-after")
                    .put("publication", "Pending").put("observation", "Pending")
            }))
        var lease: NativeSummaryLease? = null
        var failure: Throwable? = null
        try {
            AttemptJournal(File(root, "latest.json")).persist(JSONObject().put("case", scenario))
            instrumentation.runOnMainSync {
                lease = NativeSummaryLease(target.getSharedPreferences("watch_summary", Context.MODE_PRIVATE),
                    directory, receipt)
            }
            observe(directory, "before", before)
            fun publish(encoded: String) {
                quietBridge()
                retained(before, targets)
                instrumentation.runOnMainSync { checkNotNull(lease).armPublication(encoded) }
                // Slow current-scope reads stay off the main thread between durable arm and save.
                quietBridge()
                val fresh = mappings(before)
                nativeGuard(fresh.targets == targets && fresh.scopeSha256 == mapping.scopeSha256,
                    "fresh-publication-scope")
                instrumentation.runOnMainSync { checkNotNull(lease).publish(encoded) }
            }
            fun stage(name: String, selected: List<NativeDeliveryTarget>, fixture: NativeDeliveryFixture? = null) =
                observeNativeDeliveryStage(directory, name, targets, selected, probeScope(before, mapping), receipt,
                    fixture, persist = { AttemptJournal(File(directory, "receipt.json")).persist(receipt) },
                    validate = {
                        quietBridge()
                        val current = renderer()
                        requireRetained(current, before)
                        val fresh = mappings(current)
                        nativeGuard(fresh.targets == targets, "retained-runtime-mapping")
                        instrumentation.runOnMainSync { checkNotNull(lease).requireOwned() }
                        probeScope(current, fresh)
                    }, awaitEvent = { action ->
                        val event = instrumentation.uiAutomation.executeAndWaitForEvent({ action() },
                            { event -> event.packageName?.toString() == RUNTIME_PACKAGE &&
                                event.eventType == AccessibilityEvent.TYPE_WINDOW_CONTENT_CHANGED }, 5_000)
                        // Availability only; this event has no input-specific provenance.
                        event.recycle()
                    }, request = { provider, ids ->
                        ComplicationDataSourceUpdateRequester.create(target, provider).requestUpdate(*ids)
                    }, capture = { original, bounded ->
                        observe(directory, original, if (bounded) retained(before, targets) else null)
                    })
            if (fixtures.isNotEmpty()) {
                fixtures.forEachIndexed { index, fixture ->
                    val input = receipt.getJSONArray("fixtureInputs").getJSONObject(index)
                    publish(fixture.encoded)
                    input.put("publication", "accepted by normal store; delivery Pending")
                    AttemptJournal(File(directory, "receipt.json")).persist(receipt)
                    val name = input.getString("stage")
                    val observation = stage(name, targets, fixture)
                    input.put("observation", observation.getString("observation"))
                    AttemptJournal(File(directory, "receipt.json")).persist(receipt)
                }
            } else {
                publish(deliverySummary(true, Instant.now().toString()))
                stage("normal-pair", targets)
                if (scenario != "normal") {
                    publish(deliverySummary(false, Instant.now().toString()))
                    if (scenario == "delayed") {
                        val mains = targets.filterNot { it.provider.className.endsWith("SplitComplicationDataSourceService") }
                        stage("main-only", mains)
                        stage("delayed-extra", targets - mains.toSet())
                    } else stage("obsolete-selection", targets)
                    if (scenario == "recovery") {
                        publish(deliverySummary(true, Instant.now().toString()))
                        stage("pair-recovery", targets)
                    }
                }
            }
        } catch (caught: Throwable) {
            failure = caught
            receipt.put("failureOutcome", nativeReadFailure(caught).value)
                .put("failureType", nativeReadExceptionType(caught.javaClass.name))
            (caught as? NativePending)?.let { receipt.put("failureGuard", it.identity) }
            try { AttemptJournal(File(directory, "receipt.json")).persist(receipt) }
            catch (recording: Throwable) { caught.addSuppressed(recording) }
            throw caught
        } finally {
            // No failing observation, timeout or requester can bypass normal-data recovery.
            val primary = failure
            fun cleanup(action: () -> Unit) {
                try { action() } catch (caught: Throwable) {
                    if (failure == null) {
                        failure = caught
                        receipt.put("failureOutcome", nativeReadFailure(caught).value)
                            .put("failureType", nativeReadExceptionType(caught.javaClass.name))
                            .put("failureSubstage", "cleanup")
                        (caught as? NativePending)?.let { receipt.put("failureGuard", it.identity) }
                        try { AttemptJournal(File(directory, "receipt.json")).persist(receipt) }
                        catch (recording: Throwable) { caught.addSuppressed(recording) }
                    } else failure!!.addSuppressed(caught)
                }
            }
            if (lease != null) {
                var quiet = false
                cleanup { quietBridge(); quiet = true }
                cleanup { instrumentation.runOnMainSync { lease?.close(quiet) } }
                cleanup {
                    // Independent normal-data recovery uses only freshly revalidated intended targets.
                    // An unresolved mapping or dispatch stays Pending; no stale IDs or blanket requests.
                    val summary = target.getSharedPreferences("watch_summary", Context.MODE_PRIVATE).getString("latest", null)
                    val calls = JSONArray()
                    receipt.put("cleanupSummaryPresent", summary != null)
                        .put("cleanupSummarySha256", summary?.sha256() ?: JSONObject.NULL)
                        .put("cleanupRequest", "normal targeted recovery Pending").put("cleanupCalls", calls)
                    requestNativeDelivery(targets, targets, calls,
                        persist = { AttemptJournal(File(directory, "receipt.json")).persist(receipt) },
                        validate = {
                            quietBridge()
                            mappings(before).also {
                                nativeGuard(it.scopeSha256 == mapping.scopeSha256, "fresh-recovery-scope")
                            }.targets
                        }, recovery = true) { provider, ids ->
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
            if (primary == null) failure?.let { throw it }
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
        nativeDeliveryAssets(scenario)
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

    /** Separate once-only API36 capability evidence; no update is attempted here. */
    @Test
    fun probeDirectCapability() = sanitized {
        admitDirect("probeDirectCapability")
        nativeGuard(expected.required("firstFrameReview") == "complete-unobscured", "sdk-direct-first-review")
        val probe = NativeDatasourceProbe(root, expected.required("deliveryProbeId"))
        val before = renderer()
        val mapping = mappings(before)
        val scope = probeScope(before, mapping)
        val selected = probe.reviewed(scope, expected.hash("expectedDeliveryProbeSha256"),
            expected.hash("expectedReviewedFrameSha256"))
        val directory = File(probe.directory, "sdk-direct-capability")
        nativeGuard(directory.mkdir(), "single-sdk-direct-capability")
        val receipt = nativeSdkDirectCapabilityReceipt(scope, selected)
        val persist = { AttemptJournal(File(directory, "receipt.json")).persist(receipt) }
        persist()
        readNativeSdkDirectManager(target, receipt, persist)
        val current = renderer()
        requireRetained(current, before)
        nativeGuard(probeScope(current, mappings(current)) == scope, "sdk-direct-capability-scope-changed")
        receipt.put("stableScope", true)
        persist()
        report("API36 availability/acquisition recorded separately; update, effective data and paint remain Pending.")
    }

    /** Exactly one authorized finite SDK scenario; no summary writes, client or renderer replacement. */
    @Test
    fun observeDirectData() = sanitized {
        admitDirect("observeDirectData")
        val scenario = expected.required("directScenario")
        requireNativeSdkDirectAuthorization(expected, scenario)
        val probe = NativeDatasourceProbe(root, expected.required("deliveryProbeId"))
        val before = renderer()
        val mapping = mappings(before)
        val scope = probeScope(before, mapping)
        val selected = probe.reviewed(scope, expected.hash("expectedDeliveryProbeSha256"),
            expected.hash("expectedReviewedFrameSha256"))
        val capabilityHash = expected.hash("expectedDirectCapabilitySha256")
        requireNativeSdkDirectCapability(File(probe.directory, "sdk-direct-capability/receipt.json"),
            capabilityHash, scope, selected)
        quietBridge()
        requireNativeNormalRecovery(target, expected, mapping)
        requireNativePriorDeliveryRecovery(root, expected)
        val directory = File(root, "sdk-$scenario")
        nativeGuard(directory.mkdir(), "single-sdk-direct-case")
        val receipt = scope.json().put("kind", "sdk-direct-data").put("scenario", scenario)
            .put("deliveryProbeId", selected.id).put("reviewedProbeSha256", selected.receiptSha256)
            .put("reviewedFirstFrameSha256", selected.frameSha256).put("capabilitySha256", capabilityHash)
            .put("authorizedOperation", "observeDirectData:$scenario").put("directArmed", false)
            .put("effectiveData", "Pending").put("nativePaint", "Pending; independent original-frame review required")
        val persist = { AttemptJournal(File(directory, "receipt.json")).persist(receipt) }
        persist()
        AttemptJournal(File(root, "latest.json")).persist(JSONObject().put("case", directory.name))
        try {
            val summary = checkNotNull(normalSummary())
            File(directory, "summary.bin").outputStream().use {
                it.write(summary.toByteArray(Charsets.UTF_8)); it.flush(); it.fd.sync()
            }
            receipt.put("referenceSummarySha256", summary.sha256())
            persist()
            val updates = constructNativeSdkDirectData(scenario, mapping.targets, receipt, persist)
            nativeGuard(updates.all { before.selections?.configuredTypes?.get(it.target.slot) ==
                WireComplicationData.TYPE_RANGED_VALUE }, "sdk-direct-ranged-configured-targets")
            val updater = readNativeSdkDirectManager(target, receipt, persist)
            observe(directory, "before", before)
            dispatchNativeSdkDirectData(updates, receipt, persist, validate = { row ->
                quietBridge()
                val current = renderer()
                requireRetained(current, before)
                val fresh = mappings(current)
                nativeGuard(row in fresh.targets && probeScope(current, fresh) == scope, "sdk-direct-fresh-full-scope")
                nativeGuard(normalSummary() == summary, "sdk-direct-producer-changed-before-call")
            }, updater = updater, recover = { armed ->
                val calls = JSONArray()
                receipt.put("cleanupRequest", "normal targeted recovery Pending").put("cleanupCalls", calls)
                // requestNativeDelivery attempts remaining independent provider groups after a failure.
                requestNativeDelivery(mapping.targets, armed, calls, persist, validate = {
                    quietBridge()
                    val current = renderer()
                    requireRetained(current, before)
                    val fresh = mappings(current)
                    nativeGuard(probeScope(current, fresh) == scope, "sdk-direct-recovery-scope")
                    val live = checkNotNull(normalSummary())
                    receipt.put("cleanupSummaryPresent", true).put("cleanupSummarySha256", live.sha256())
                        .put("newerProducerObserved", receipt.optBoolean("newerProducerObserved") || live != summary)
                    persist()
                    fresh.targets
                }, recovery = true) { provider, ids ->
                    ComplicationDataSourceUpdateRequester.create(target, provider).requestUpdate(*ids)
                }
                receipt.put("cleanupRequest", "normal requestUpdate returned; effective restoration Pending")
                persist()
                observe(directory, "restoration-immediate", retained(before, mapping.targets))
            }, observe = { index ->
                observe(directory, "direct-$index-bounded", retained(before, mapping.targets))
                receipt.put("effectiveData", "private bounded native records; causality and semantic review Pending")
                persist()
            })
        } catch (failure: Throwable) {
            receipt.put("outcome", "Pending").put("failure", nativeReadFailure(failure).value)
            try { persist() } catch (recording: Throwable) { failure.addSuppressed(recording) }
            throw failure
        }
        report("Finite SDK observation recorded; sequential calls provide no pair atomicity. Later normal restoration and HOST review Pending.")
    }

    /** Separate later observation, after independent normal recovery; never replays a direct call. */
    @Test
    fun observeDirectRestoration() = sanitized {
        admitDirect("observeDirectRestoration")
        val scenario = expected.required("directScenario")
        nativeGuard(scenario in nativeSdkDirectScenarios, "sdk-direct-scenario")
        val directory = File(root, "sdk-$scenario")
        val journal = AttemptJournal(File(directory, "receipt.json"))
        val receipt = journal.read()
        nativeGuard(receipt.optBoolean("directArmed") && !receipt.has("laterRestoration") &&
            receipt.optString("cleanupRequest") == "normal requestUpdate returned; effective restoration Pending",
            "single-sdk-direct-later-restoration")
        receipt.put("laterRestoration", "armed; native observation Pending")
        journal.persist(receipt)
        val current = renderer()
        val mapping = mappings(current)
        val scope = probeScope(current, mapping).json()
        scope.keys().forEach { key ->
            nativeGuard(receipt.opt(key) == scope.get(key), "sdk-direct-restoration-scope")
        }
        val live = checkNotNull(normalSummary())
        observe(directory, "restoration-later", current)
        receipt.put("laterRestoration", "recorded; original-frame inspection and response provenance Pending")
            .put("cleanupSummaryStillCurrent", live.sha256() == receipt.getString("cleanupSummarySha256"))
            .put("restorationComparison", "reconcile current normal data and newer publications; HOST review Pending")
        journal.persist(receipt)
        report("Separate later original recorded; effective normal restoration, retained state and visual acceptance Pending.")
    }

    private fun admitDirect(method: String) {
        NativeReadAdmission(instrumentation, expected).admit(method, DELIVERY_CLASS, "sdk-direct-data")
    }

    private fun normalSummary(): String? {
        val preferences = target.getSharedPreferences("watch_summary", Context.MODE_PRIVATE)
        val encoded = preferences.getString("latest", null)
        nativeGuard(encoded != null && WatchSummaryStore(target).load() != null &&
            preferences.getString("latest", null) == encoded, "sdk-direct-current-normal-data")
        return encoded
    }

    private fun admit(method: String) {
        NativeReadAdmission(instrumentation, expected).admit(method, DELIVERY_CLASS, "normal-delivery")
    }

    private fun probeScope(renderer: NativeRenderer, mapping: NativeDeliveryMapping) = NativeDatasourceProbeScope(
        NativePackage.read(target, HOST_PACKAGE).apk, renderer.instance.sha256(), renderer.configuration.sha256(),
        mapping.targets.fingerprint(), mapping.scopeSha256,
    )

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
