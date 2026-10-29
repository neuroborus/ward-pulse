package app.wardpulse.wear.nativeintegration

import android.graphics.Bitmap
import android.os.Bundle
import android.os.ParcelFileDescriptor
import android.util.AtomicFile
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import androidx.wear.watchfacepush.WatchFacePushManagerFactory
import java.io.File
import java.util.Properties
import java.util.zip.ZipFile
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.runBlocking
import org.json.JSONObject
import org.junit.Test
import org.junit.runner.RunWith

/** Baseline-compatible: no production classes, Activity, application substitution or client API. */
@ManualNativeIntegration
@RunWith(AndroidJUnit4::class)
class NativePushUpdateTest {
    private val instrumentation = InstrumentationRegistry.getInstrumentation()
    private val target = instrumentation.targetContext
    private val expected = NativePushExpectations(InstrumentationRegistry.getArguments())
    private val device = NativePushDevice(instrumentation)
    private val journal get() = File(target.filesDir, "native_push_update/attempt.json")

    @Test
    fun probeBaseline() = sanitized("baseline-probe") {
        device.admit(expected, "probeBaseline")
        nativeGuard(!AttemptJournal(journal).exists(), "no-previous-dispatch")
        nativeGuard(WatchFacePushManagerFactory.isSupported(), "push-sdk-support")
        device.baseline(expected)
        val renderer = device.readRenderer(expected)
        runBlocking(Dispatchers.IO) {
            val manager = WatchFacePushManagerFactory.createWatchFacePushManager(target)
            val owned = manager.listWatchFaces().installedWatchFaceDetails
                .single { it.packageName == CANDIDATE_PACKAGE }
            nativeGuard(owned.versionCode == 3L, "probe-push-3")
            nativeGuard(manager.isWatchFaceActive(CANDIDATE_PACKAGE) ==
                (expected.required("expectedResourcePackage") == CANDIDATE_PACKAGE), "probe-active-ownership")
            report("Preflight identities/provenance only: slotSha256=${owned.slotId.sha256()}, " +
                "instanceSha256=${renderer.instance.sha256()}, deliveryProvenanceSha256=${renderer.deliveryProvenance.sha256()}. " +
                "Delivery provenance alone does not prove selection retention or authorize target replacement.")
            val configuration = renderer.requirePushConfiguration()
            report("Push selection configurationSha256=${configuration.sha256()}; " +
                "no update performed; native witness and target replacement Pending.")
        }
    }

    @Test
    fun updateOwnedPush3To4() = sanitized("update") {
        device.admit(expected, "updateOwnedPush3To4")
        nativeGuard(!AttemptJournal(journal).exists(), "no-previous-dispatch")
        nativeGuard(WatchFacePushManagerFactory.isSupported(), "push-sdk-support")
        val baseline = device.baseline(expected)
        val renderer = device.renderer(expected)
        Candidate.open(instrumentation.context, target.cacheDir).use { candidate ->
            nativeGuard(candidate.signer == expected.hash("expectedPushSignerSha256") &&
                candidate.hostSigner == expected.hash("expectedHostSignerSha256"), "validated-signers")
            val manager = WatchFacePushManagerFactory.createWatchFacePushManager(target)
            // No cancellation timeout around a remote mutation: retain FD ownership until callback.
            runBlocking(Dispatchers.IO) {
                val inventory = manager.listWatchFaces()
                val owned = inventory.installedWatchFaceDetails.singleOrNull { it.packageName == CANDIDATE_PACKAGE }
                    ?: throw NativePending("owned-push-slot-unavailable")
                nativeGuard(owned.versionCode == 3L && owned.slotId.sha256() == expected.hash("expectedSlotSha256"),
                    "owned-push-3-slot")
                val wasActive = manager.isWatchFaceActive(CANDIDATE_PACKAGE)
                nativeGuard(wasActive == (expected.required("expectedResourcePackage") == CANDIDATE_PACKAGE),
                    "active-ownership")
                // Recheck immediately before arming; a concurrent change is a failed precondition.
                device.baseline(expected)
                val currentRenderer = device.renderer(expected)
                currentRenderer.requireRetainedFrom(renderer)
                val receipt = baseline.put("slotSha256", owned.slotId.sha256())
                    .put("instanceSha256", renderer.instance.sha256())
                    .put("configurationSha256", renderer.configuration.sha256())
                    .put("resourcePackage", expected.required("expectedResourcePackage"))
                    .put("runtime", expected.required("expectedRuntime"))
                    .put("pushConfigurationRetention", "Pending")
                    .put("targetReplacement", "Pending")
                    .put("wasActive", wasActive).put("candidateApkSha256", candidate.apkSha256)
                    .put("candidateResourcesSha256", candidate.resourcesSha256)
                    .put("candidateSignerSha256", candidate.signer)
                // Persist before dispatch. A crash or exception after this boundary forbids a retry.
                AttemptJournal(journal).dispatch(receipt, currentRenderer) {
                    val result = manager.updateWatchFace(owned.slotId, candidate.descriptor, candidate.token)
                    receipt.put("state", "result-received; advancement uncertain")
                        .put("resultCode", result.versionCode).put("resultSlotSha256", result.slotId.sha256())
                        .put("resultPackageSha256", result.packageName.sha256())
                    AttemptJournal(journal).persist(receipt)
                    nativeGuard(result.slotId == owned.slotId && result.packageName == CANDIDATE_PACKAGE &&
                        result.versionCode == 4L, "returned-identity")
                    verifyInstalled(candidate.apkSha256, candidate.resourcesSha256, candidate.signer)
                    val after = manager.listWatchFaces()
                    nativeGuard(after.remainingSlotCount == inventory.remainingSlotCount &&
                        after.installedWatchFaceDetails.size == inventory.installedWatchFaceDetails.size &&
                        after.installedWatchFaceDetails.map { Triple(it.slotId, it.packageName, it.versionCode) }
                            .toSet() == inventory.installedWatchFaceDetails.map {
                            Triple(it.slotId, it.packageName, if (it.slotId == owned.slotId) 4L else it.versionCode)
                        }.toSet(), "retained-owned-inventory")
                    device.unchangedHost(baseline)
                    // No post-update isWatchFaceActive call or immediate native-active oracle.
                }
            }
        }
        val completed = AttemptJournal(journal).read().put("resourceCleanup", "verified")
        AttemptJournal(journal).persist(completed)
        report("SDK result and installed candidate verified; settled native evidence Pending.")
    }

    /** HOST selects this separately, after inspecting later native settlement; never runs the update. */
    @Test
    fun observeSettledUpdate() = sanitized("settled-observation") {
        device.admit(expected, "observeSettledUpdate")
        val receipt = AttemptJournal(journal).read()
        nativeGuard(receipt.getString("state") == "result-verified", "verified-single-update")
        nativeGuard(receipt.optString("resourceCleanup") == "verified", "update-resources-retired")
        nativeGuard(receipt.getString("resourcePackage") == expected.required("expectedResourcePackage") &&
            receipt.getString("runtime") == expected.required("expectedRuntime"), "original-renderer-identity")
        nativeGuard(!receipt.has("nativeObservation"), "single-native-observation")
        receipt.put("nativeObservation", "started; native evidence Pending")
            .put("pushConfigurationRetention", "Pending").put("targetReplacement", "Pending")
        AttemptJournal(journal).persist(receipt)
        device.unchangedHost(receipt)
        verifyInstalled(receipt.getString("candidateApkSha256"), receipt.getString("candidateResourcesSha256"),
            receipt.getString("candidateSignerSha256"))
        val renderer = device.renderer(expected)
        nativeGuard(renderer.instance.sha256() == receipt.getString("instanceSha256") &&
            renderer.configuration.sha256() == receipt.getString("configurationSha256"), "settled-retention")
        runBlocking(Dispatchers.IO) {
            val owned = WatchFacePushManagerFactory.createWatchFacePushManager(target).listWatchFaces()
                .installedWatchFaceDetails.single { it.packageName == CANDIDATE_PACKAGE }
            nativeGuard(owned.versionCode == 4L && owned.slotId.sha256() == receipt.getString("slotSha256"),
                "settled-owned-slot")
        }
        val frame = checkNotNull(instrumentation.uiAutomation.takeScreenshot())
        try {
            File(journal.parentFile, "settled-original.png").outputStream().use {
                nativeGuard(frame.compress(Bitmap.CompressFormat.PNG, 100, it), "native-frame")
            }
        } finally {
            frame.recycle()
        }
        // This records the observation, not visual acceptance. HOST must inspect the original.
        receipt.put("nativeObservation", "recorded; original-frame inspection Pending")
            .put("pushConfigurationRetention", "verified from Push-owned selection records")
        AttemptJournal(journal).persist(receipt)
        device.unchangedHost(receipt)
        report("Separate native retention recorded; original-frame review and overall acceptance Pending.")
    }

    private fun verifyInstalled(apk: String, resources: String, signer: String) {
        val installed = NativePackage.read(target, CANDIDATE_PACKAGE)
        nativeGuard(installed.code == 4L && installed.apk == apk && installed.signer == signer,
            "installed-candidate-bytes")
        val info = target.packageManager.getApplicationInfo(CANDIDATE_PACKAGE, 0)
        val actualResources = ZipFile(info.sourceDir).use { zip ->
            zip.getInputStream(checkNotNull(zip.getEntry("resources.arsc"))).sha256()
        }
        nativeGuard(actualResources == resources, "installed-candidate-resources")
    }

    private fun sanitized(phase: String, action: () -> Unit) {
        try {
            action()
        } catch (failure: Throwable) {
            // SDK/platform exception text may include opaque tokens, payloads, paths or remote causes.
            val reason = (failure as? NativePending)?.identity ?: "capability-or-operation-unavailable"
            throw AssertionError("Pending: native Push $phase ($reason); preserve host and private attempt record; do not retry.")
        }
    }

    private fun report(message: String) = instrumentation.sendStatus(0, Bundle().apply {
        putString("stream", "\nNative Push: $message\n")
    })
}

/** Deliberately retained on success/failure: update version advancement is never rolled back. */
internal class AttemptJournal(private val file: File) {
    fun exists() = listOf(file, File("${file.path}.bak"), File("${file.path}.new")).any { it.exists() }

    fun read() = JSONObject(AtomicFile(file).openRead().bufferedReader().use { it.readText() })

    fun persist(receipt: JSONObject) {
        val atomic = AtomicFile(file)
        val stream = atomic.startWrite()
        try {
            stream.write(receipt.toString().toByteArray())
            atomic.finishWrite(stream)
        } catch (failure: Throwable) {
            atomic.failWrite(stream)
            throw failure
        }
    }

    suspend fun dispatch(receipt: JSONObject, renderer: NativeRenderer, update: suspend () -> Unit) {
        nativeGuard(renderer.requirePushConfiguration().sha256() == receipt.getString("configurationSha256"),
            "dispatch-selection-configuration")
        nativeGuard(file.parentFile!!.isDirectory || file.parentFile!!.mkdirs(), "private-receipt-directory")
        nativeGuard(!exists(), "single-dispatch")
        nativeGuard(file.createNewFile(), "single-dispatch")
        receipt.put("state", "dispatched; advancement uncertain")
        persist(receipt)
        update()
        receipt.put("state", "result-verified")
        persist(receipt)
    }
}

internal class Candidate(
    private val file: File,
    val descriptor: ParcelFileDescriptor,
    val token: String,
    val apkSha256: String,
    val resourcesSha256: String,
    val signer: String,
    val hostSigner: String,
) : AutoCloseable {
    override fun close() {
        try {
            descriptor.close()
        } finally {
            nativeGuard(file.delete(), "candidate-cleanup")
        }
    }

    companion object {
        fun open(context: android.content.Context, cache: File): Candidate {
            val directory = "native_push_candidate/"
            val receipt = Properties().apply {
                context.assets.open("${directory}identity.properties").use { load(it) }
            }
            fun hash(name: String) = checkNotNull(receipt.getProperty(name)).also {
                nativeGuard(it.matches(Regex("[a-f0-9]{64}")), "candidate-receipt")
            }
            nativeGuard(receipt.getProperty("packageName") == CANDIDATE_PACKAGE &&
                receipt.getProperty("versionCode") == "4" &&
                hash("validatorSha256") == "04dc20a0994df3eaebf025e107f7589c147b2ce8a2c628745e01a5c0a63fe4dd",
                "validated-candidate-identity")
            val token = context.assets.open("${directory}validation-token.txt").bufferedReader().use { it.readText() }
            nativeGuard(token.sha256() == hash("tokenSha256"), "validated-token-binding")
            val file = File.createTempFile("native-push-", ".apk", cache)
            try {
                context.assets.open("${directory}candidate.apk").use { source ->
                    file.outputStream().use { source.copyTo(it) }
                }
                nativeGuard(file.inputStream().sha256() == hash("apkSha256"), "validated-apk-binding")
                val info = checkNotNull(context.packageManager.getPackageArchiveInfo(file.path,
                    android.content.pm.PackageManager.GET_SIGNING_CERTIFICATES))
                nativeGuard(info.packageName == CANDIDATE_PACKAGE && info.longVersionCode == 4L &&
                    info.signingInfo?.apkContentsSigners?.singleOrNull()?.toByteArray()?.inputStream()?.sha256() ==
                    hash("signerSha256"), "candidate-archive-identity")
                val apkHash = hash("apkSha256")
                val resourcesHash = hash("resourcesSha256")
                val signerHash = hash("signerSha256")
                val hostSignerHash = hash("hostSignerSha256")
                return Candidate(file, ParcelFileDescriptor.open(file, ParcelFileDescriptor.MODE_READ_ONLY),
                    token, apkHash, resourcesHash, signerHash, hostSignerHash)
            } catch (failure: Throwable) {
                nativeGuard(file.delete(), "candidate-failure-cleanup")
                throw failure
            }
        }
    }
}
