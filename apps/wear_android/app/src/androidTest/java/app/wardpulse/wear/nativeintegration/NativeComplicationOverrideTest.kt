package app.wardpulse.wear.nativeintegration

import android.content.Context
import android.graphics.Bitmap
import android.os.Bundle
import android.view.accessibility.AccessibilityEvent
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import androidx.wear.watchface.DrawMode
import androidx.wear.watchface.RenderParameters
import androidx.wear.watchface.complications.data.ComplicationType
import androidx.wear.watchface.complications.datasource.ComplicationDataSourceUpdateRequester
import androidx.wear.watchface.style.WatchFaceLayer
import app.wardpulse.wear.data.WatchSummaryStore
import java.io.File
import java.time.Instant
import java.util.concurrent.TimeoutException
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Test
import org.junit.runner.RunWith

/** Current-target capability probe. Public client access is not promised on the installed runtime. */
@ManualNativeIntegration
@RunWith(AndroidJUnit4::class)
class NativeComplicationOverrideTest {
    private val instrumentation = InstrumentationRegistry.getInstrumentation()
    private val target = instrumentation.targetContext
    private val expected = NativePushExpectations(InstrumentationRegistry.getArguments())
    private val device = NativePushDevice(instrumentation)
    private val root get() = File(target.filesDir, "native_client")

    @Test
    fun probeClient() = sanitized {
        admit("probeClient")
        val before = renderer()
        val mapping = mappings(before)
        val targets = mapping.targets
        val directory = fresh("probe")
        val receipt = JSONObject().put("identity", identity(before, mapping)).put("state", "capability Pending")
        recorded(directory, receipt) { persist ->
            withExistingNativeClient(target, before, receipt, persist) { client ->
                nativeGuard(targets.all {
                    ComplicationType.RANGED_VALUE in client.complicationSlotsState.getValue(it.slot).supportedTypes
                }, "client-ranged-slots-unavailable")
                retained(before, targets)
                original(directory, "first")
                receipt.put("firstFrameSha256", File(directory, "first.png").inputStream().sha256())
                    .put("state", "probe returned; first-frame and restoration review Pending")
                persist()
            }
        }
        report("Existing-instance probe recorded; access, first-frame review and restoration support require HOST review.")
    }

    /** One bounded object/partial-map observation, after a successful, independently reviewed probe. */
    @Test
    fun observeOverride() = sanitized {
        admit("observeOverride")
        nativeGuard(expected.required("clientProbeReview") == "complete" &&
            expected.required("firstFrameReview") == "complete-unobscured" &&
            expected.required("normalRestorationReview") == "complete", "client-host-review")
        quietBridge()
        val mode = expected.required("overrideMode")
        nativeGuard(mode in setOf("active", "supplied-bitmap"), "override-mode")
        val scenario = expected.required("overrideScenario")
        nativeGuard(scenario in scenarios, "override-scenario")
        requireNativeDatasourceMutation(expected, "observeOverride:$mode:$scenario")
        val before = renderer()
        val mapping = mappings(before)
        val targets = mapping.targets
        val probe = File(root, "probe")
        nativeGuard(File(probe, "receipt.json").inputStream().sha256() ==
            expected.hash("expectedClientProbeSha256"), "reviewed-client-probe")
        val probed = AttemptJournal(File(probe, "receipt.json")).read()
        requireGuardedNativeClientProbe(probed, identity(before, mapping))
        nativeGuard(File(probe, "first.png").inputStream().sha256() ==
            expected.hash("expectedReviewedFrameSha256") && probed.getString("firstFrameSha256") ==
            expected.hash("expectedReviewedFrameSha256"), "reviewed-client-first-frame")
        requireNormalRecovery(mapping)
        requirePriorClientRecovery()
        val directory = fresh("$mode-$scenario")
        val receipt = JSONObject().put("identity", identity(before, mapping))
            .put("authorizedOperation", "observeOverride:$mode:$scenario")
            .put("mode", mode).put("scenario", scenario).put("state", "object construction Pending")
            .put("effectiveRendering", "Pending").put("restoration", "not yet required")
        // No summary is written by this route. Keep opaque recovery/reference bytes private;
        // normal cleanup reads the current producer value, never overwrites it with this snapshot.
        val summary = checkNotNull(target.getSharedPreferences("watch_summary", Context.MODE_PRIVATE).getString("latest", null))
        File(directory, "summary.bin").outputStream().use {
            it.write(summary.toByteArray(Charsets.UTF_8)); it.flush(); it.fd.sync()
        }
        recorded(directory, receipt) { persist ->
            val data = try {
                nativeOverrideData(scenario, targets)
            } catch (_: IllegalArgumentException) {
                receipt.put("state", "SDK object rejected; renderer suppression unproven")
                persist()
                throw NativePending("client-object-rejected")
            }
            receipt.put("state", "object constructed; transport Pending")
                .put("requestedSlots", JSONArray(data.keys.sorted()))
            persist()
            // Persist ownership before any acquisition, including a factory that never returns.
            AttemptJournal(File(root, "latest.json")).persist(JSONObject().put("case", directory.name))
            withExistingNativeClient(target, before, receipt, persist) { client ->
                retained(before, targets)
                nativeGuard(targets.filter { it.slot in data }.all {
                    ComplicationType.RANGED_VALUE in client.complicationSlotsState.getValue(it.slot).supportedTypes
                }, "client-ranged-slots-unavailable")
                quietBridge()
                nativeGuard(target.getSharedPreferences("watch_summary", Context.MODE_PRIVATE)
                    .getString("latest", null) == summary, "producer-changed-before-override")
                original(directory, "before")
                // Arm before either public call. Recovery is mandatory even if transport throws.
                var armed = false
                try {
                    receipt.put("state", "transport armed; effect uncertain")
                        .put("transportArmed", true)
                        .put("restoration", "Pending")
                    persist()
                    armed = true
                    retained(before, targets)
                    quietBridge()
                    nativeGuard(target.getSharedPreferences("watch_summary", Context.MODE_PRIVATE)
                        .getString("latest", null) == summary, "producer-changed-before-transport")
                    if (mode == "supplied-bitmap") {
                        val bitmap = client.renderWatchFaceToBitmap(
                            RenderParameters(DrawMode.INTERACTIVE, WatchFaceLayer.ALL_WATCH_FACE_LAYERS, null),
                            Instant.now(), null, data,
                        )
                        saveBitmap(directory, "supplied", bitmap)
                        receipt.put("state", "supplied-data bitmap returned; ordinary active publication unproven")
                        persist()
                    } else {
                        try {
                            val event = instrumentation.uiAutomation.executeAndWaitForEvent({
                                client.updateComplicationData(data)
                                receipt.put("state", "updateComplicationData returned; application and rendering Pending")
                                persist()
                                original(directory, "requested")
                            }, { it.packageName?.toString() == RUNTIME_PACKAGE &&
                                it.eventType == AccessibilityEvent.TYPE_WINDOW_CONTENT_CHANGED }, 5_000)
                            try { receipt.put("boundary", "runtime event; no delivery ACK") }
                            finally { event.recycle() }
                        } catch (_: TimeoutException) {
                            receipt.put("boundary", "event unavailable within bound; transition Pending")
                        }
                        original(directory, "bounded")
                    }
                    val current = retained(before, targets)
                    privateData(directory, "observed", current)
                    receipt.put("effectiveRendering", "original observations recorded; semantic/visual review Pending")
                    persist()
                } finally {
                    if (armed) {
                        // Independent recovery must run before close, including transport failures.
                        val calls = JSONArray()
                        receipt.put("cleanupRequest", "normal targeted recovery Pending").put("cleanupCalls", calls)
                        requestNativeDelivery(targets, targets.filter { it.slot in data }, calls, persist,
                            validate = { quietBridge(); mappings(before).targets }, recovery = true) { provider, ids ->
                            ComplicationDataSourceUpdateRequester.create(target, provider).requestUpdate(*ids)
                        }
                        receipt.put("cleanupRequest", "normal requestUpdate returned; effective restoration Pending")
                        val current = target.getSharedPreferences("watch_summary", Context.MODE_PRIVATE).getString("latest", null)
                        receipt.put("cleanupSummaryPresent", current != null)
                            .put("cleanupSummarySha256", current?.sha256() ?: JSONObject.NULL)
                            .put("newerProducerObserved", current != summary)
                            .put("restoration", "normal current data requested; later effective observation Pending")
                        persist()
                    }
                }
            }
        }
        report("Bounded $mode/$scenario recorded. Object/transport acceptance, WFF suppression and restoration are separate; HOST review Pending.")
    }

    /** Later, separate original after normal delivery settles; no override and no stale-data restore. */
    @Test
    fun observeRestoration() = sanitized {
        admit("observeRestoration")
        val mode = expected.required("overrideMode")
        val scenario = expected.required("overrideScenario")
        nativeGuard(mode in setOf("active", "supplied-bitmap") && scenario in scenarios, "restoration-case")
        val directory = File(root, "$mode-$scenario")
        val receipt = AttemptJournal(File(directory, "receipt.json")).read()
        nativeGuard(!receipt.has("laterRestoration") && receipt.optString("cleanupRequest") ==
            "normal requestUpdate returned; effective restoration Pending" &&
            receipt.optString("interactiveCleanup") == "close returned" &&
            receipt.optString("controlCleanup") == "close returned" &&
            receipt.optString("controlBindingCleanup") == "tracked connections released", "client-retired-before-restoration")
        recorded(directory, receipt) { persist ->
            receipt.put("laterRestoration", "armed; observation Pending")
            persist()
            val current = renderer()
            val mapping = mappings(current)
            nativeGuard(identity(current, mapping).sameClientIdentity(receipt.getJSONObject("identity")), "restoration-identity")
            original(directory, "restoration-later")
            privateData(directory, "restoration-later", current)
            val summary = target.getSharedPreferences("watch_summary", Context.MODE_PRIVATE).getString("latest", null)
            receipt.put("laterRestoration", "recorded; normal effective data and visual review Pending")
                .put("cleanupSummaryStillCurrent", receipt.getBoolean("cleanupSummaryPresent") == (summary != null) &&
                    (summary == null || receipt.getString("cleanupSummarySha256") == summary.sha256()))
            persist()
        }
        report("Separate restoration original recorded; reconcile newer normal data, effective rendering and retained state on HOST.")
    }

    private fun admit(method: String) {
        NativeReadAdmission(instrumentation, expected).admit(method, CLIENT_CLASS, "client-probe")
        nativeGuard(expected.required("clientArtifactReview") == "resolved-1.2.1", "host-client-resolution-review")
        expected.hash("expectedClientArtifactSha256") // HOST receipt of the actual resolved AAR, not the source JAR.
    }

    private fun identity(renderer: NativeRenderer, mapping: NativeDeliveryMapping) = JSONObject()
        .put("hostApkSha256", NativePackage.read(target, HOST_PACKAGE).apk)
        .put("clientArtifactSha256", expected.hash("expectedClientArtifactSha256"))
        .put("instanceSha256", renderer.instance.sha256()).put("configurationSha256", renderer.configuration.sha256())
        .put("resourcePackage", renderer.resourcePackage).put("mappingSha256", mapping.targets.fingerprint())
        .put("scopeSha256", mapping.scopeSha256)

    private fun requireNormalRecovery(mapping: NativeDeliveryMapping) {
        val scenario = expected.required("normalRestorationScenario")
        nativeGuard(scenario in setOf("normal", "delayed", "obsolete", "recovery"), "normal-restoration-scenario")
        val file = File(target.filesDir, "native_datasource/$scenario/receipt.json")
        nativeGuard(file.inputStream().sha256() == expected.hash("expectedNormalRestorationReceiptSha256"),
            "reviewed-normal-restoration")
        val receipt = AttemptJournal(file).read()
        nativeGuard(receipt.optString("laterRestoration") ==
            "recorded; original-frame inspection and response provenance Pending" &&
            receipt.optString("mappingSha256") == mapping.targets.fingerprint() &&
            receipt.optString("scopeSha256") == mapping.scopeSha256 &&
            receipt.optString("cleanupRequest") == "normal requestUpdate returned; effective restoration Pending" &&
            receipt.optString("restoration") in setOf("original bytes observed", "original bytes restored"),
            "normal-restoration-support")
        nativeGuard(WatchSummaryStore(target).load() != null, "restorable-normal-data")
    }

    private fun requirePriorClientRecovery() {
        val latest = AttemptJournal(File(root, "latest.json"))
        if (!latest.exists()) return
        val name = latest.read().getString("case")
        nativeGuard(name in scenarios.flatMap { listOf("active-$it", "supplied-bitmap-$it") }, "prior-client-case")
        val file = File(root, "$name/receipt.json")
        val receipt = AttemptJournal(file).read()
        nativeGuard(receipt.optString("interactiveCleanup") in setOf("close returned", "no client returned") &&
            receipt.optString("controlCleanup") in setOf("close returned", "no control returned") &&
            receipt.optString("controlBindingCleanup") == "tracked connections released", "prior-client-ownership-unresolved")
        if (receipt.optBoolean("transportArmed")) {
            nativeGuard(receipt.optString("laterRestoration") ==
                "recorded; normal effective data and visual review Pending" &&
                expected.required("priorClientRestorationReview") == "complete" &&
                file.inputStream().sha256() == expected.hash("expectedPriorClientRestorationSha256"),
                "prior-client-effective-restoration-unreviewed")
        }
    }

    private fun quietBridge() {
        nativeGuard(expected.required("quietWriters") == "confirmed-unpaired", "client-quiet-writers")
        val services = device.shell("dumpsys activity services $HOST_PACKAGE")
        nativeGuard(services.startsWith("ACTIVITY MANAGER SERVICES (dumpsys activity services)") &&
            !services.contains("WatchSummaryListenerService"), "client-quiet-summary-owners")
    }

    private fun renderer() = device.readRenderer(expected).also {
        nativeGuard(it.instance.sha256() == expected.hash("expectedInstanceSha256") &&
            it.configuration.sha256() == expected.hash("expectedConfigurationSha256"), "client-renderer-identity")
    }

    private fun mappings(before: NativeRenderer) = readNativeDeliveryTargets(instrumentation, expected, before)

    private fun retained(before: NativeRenderer, targets: List<NativeDeliveryTarget>): NativeRenderer = renderer().also {
        requireNativeDeliveryScope(it, before)
        nativeGuard(mappings(it).targets == targets, "client-retained-state")
    }

    private fun fresh(name: String) = File(root, name).also {
        nativeGuard(root.isDirectory || root.mkdirs(), "private-client-root")
        nativeGuard(it.mkdir(), "single-client-case")
    }

    private fun original(directory: File, name: String) = saveBitmap(directory, name,
        checkNotNull(instrumentation.uiAutomation.takeScreenshot()))

    private fun saveBitmap(directory: File, name: String, bitmap: Bitmap) {
        try {
            val file = File(directory, "$name.png")
            nativeGuard(file.createNewFile(), "single-client-frame")
            file.outputStream().use { nativeGuard(bitmap.compress(Bitmap.CompressFormat.PNG, 100, it), "client-frame") }
        } finally { bitmap.recycle() }
    }

    private fun privateData(directory: File, name: String, renderer: NativeRenderer) {
        AttemptJournal(File(directory, "$name.json")).persist(JSONObject()
            .put("effectiveData", JSONObject(renderer.effectiveData.mapKeys { it.key.toString() }))
            .put("provenance", "native diagnostic; response causality and semantic review Pending"))
    }

    private fun recorded(directory: File, receipt: JSONObject, action: (() -> Unit) -> Unit) {
        val journal = AttemptJournal(File(directory, "receipt.json"))
        val persist = { journal.persist(receipt) }
        persist()
        try { action(persist) } catch (failure: Throwable) {
            receipt.put("outcome", "Pending").put("reason", (failure as? NativePending)?.identity ?: "client-access-or-transport-unavailable")
            persist()
            throw failure
        }
    }

    private fun sanitized(action: () -> Unit) {
        try { action() } catch (failure: Throwable) {
            throw AssertionError("Pending: native client (${(failure as? NativePending)?.identity ?: "access-or-transport-unavailable"}); " +
                "retain private recovery and receipts; no permission or instance workaround.")
        }
    }

    private fun report(message: String) = instrumentation.sendStatus(0, Bundle().apply {
        putString("stream", "\nNative client: $message\n")
    })

    private companion object {
        val scenarios = setOf("unsupported-range", "malformed-title", "nonfinite-value", "out-of-range",
            "partial-no-data-main", "no-data-main-valid-extra")
    }
}
