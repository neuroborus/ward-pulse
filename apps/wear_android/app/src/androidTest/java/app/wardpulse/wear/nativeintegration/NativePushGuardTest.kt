package app.wardpulse.wear.nativeintegration

import android.content.ComponentName
import android.os.Bundle
import android.os.ParcelFileDescriptor
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.io.File
import kotlinx.coroutines.runBlocking
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertThrows
import org.junit.Test
import org.junit.runner.RunWith

/** Pure guard decisions and test-private recovery files; no SDK calls or normal preferences. */
@ManualNativeIntegration
@RunWith(AndroidJUnit4::class)
class NativePushGuardTest {
    @Test
    fun admissionRejectsMissingOptInWrongRouteAndNonCanonicalDevices() {
        fun arguments() = Bundle().apply {
            putString("class", "$UPDATE_CLASS#updateOwnedPush3To4")
            putString("wardpulseNativeIntegration", "push-3-to-4")
            putString("expectedAvd", "wardpulse_wear_square_api36_1")
        }
        fun admit(arguments: Bundle, runner: String = "androidx.test.runner.AndroidJUnitRunner",
            avd: String = "wardpulse_wear_square_api36_1", qemu: String = "1", watch: Boolean = true) =
            NativePushExpectations(arguments).admit("updateOwnedPush3To4", runner, avd, qemu, watch)
        admit(arguments())
        assertThrows(NativePending::class.java) { admit(arguments().apply { remove("wardpulseNativeIntegration") }) }
        assertThrows(NativePending::class.java) { admit(arguments().apply { putString("class", UPDATE_CLASS) }) }
        assertThrows(NativePending::class.java) { admit(arguments(), runner = "isolated") }
        assertThrows(NativePending::class.java) { admit(arguments(), avd = "other") }
        assertThrows(NativePending::class.java) { admit(arguments(), qemu = "0") }
        assertThrows(NativePending::class.java) { admit(arguments(), watch = false) }
    }

    @Test
    fun selectionRetentionCannotUseCachedDeliveryOrLegacyOnlyEvidence() {
        val dump = rendererRecord()
        val observed = NativeRenderer.parse(dump, CANDIDATE_PACKAGE)
        // Independent synthetic selection records; the runtime reader must never infer these from data.
        val selections = NativeSelections(CANDIDATE_PACKAGE, "existing", fixtureProviders())
        val before = observed.copy(selections = selections)
        val changed = observed.copy(selections = selections.copy(
            providers = selections.providers + (16 to "provider.test/Changed16"),
        ))
        assertEquals(before.deliveryProvenance, changed.deliveryProvenance)
        assertNotEquals(before.configuration, changed.configuration)
        assertThrows(NativePending::class.java) { changed.requireRetainedFrom(before) }
        // Conversely, older delivered provenance must not override the actual selected provider.
        val olderDelivery = NativeRenderer.parse(dump.replace("Chosen16", "Earlier16"), CANDIDATE_PACKAGE)
            .copy(selections = selections)
        assertNotEquals(before.deliveryProvenance, olderDelivery.deliveryProvenance)
        olderDelivery.requireRetainedFrom(before)
        assertThrows(NativePending::class.java) { observed.requirePushConfiguration() }
        val legacyPackage = "app.wardpulse.watchface"
        val legacy = NativeRenderer.parse(dump.replace(CANDIDATE_PACKAGE, legacyPackage), legacyPackage)
            .copy(selections = selections.copy(resourcePackage = legacyPackage))
        assertThrows(NativePending::class.java) { legacy.requirePushConfiguration() }
        assertThrows(NativePending::class.java) {
            NativeRenderer.parse(dump.replace("dataSource=ComponentInfo{provider.test/Chosen16}", ""), CANDIDATE_PACKAGE)
                .requirePushConfiguration()
        }
        assertThrows(NativePending::class.java) {
            NativeRenderer.parse(dump.replace("interactiveInstanceId=existing", "interactiveInstanceId=other"), CANDIDATE_PACKAGE)
        }
        assertThrows(NativePending::class.java) {
            NativeRenderer.parse(dump.replace("isAmbient=false", "isAmbient=true"), CANDIDATE_PACKAGE)
        }
    }

    @Test
    fun dispatchedAttemptCannotRunAgainAfterFailureOrSuccess() = runBlocking {
        val component = ComponentName(RUNTIME_PACKAGE, "$RUNTIME_PACKAGE.DeclarativeWatchFaceRuntime0")
        val observed = NativeRenderer.parse(rendererRecord(), CANDIDATE_PACKAGE)
        val selectedProviders = fixtureProviders() + mapOf(17 to null, 18 to null)
        var observations = 0
        val renderer = readNativeSelections(component, observe = { observations++; observed }) { face, slots ->
            assertEquals(component, face)
            assertEquals(observed.enabled.keys, slots.toSet())
            selectedProviders.map { (id, provider) -> NativeSelectionRecord(id, provider) }
        }
        assertEquals(2, observations)
        assertEquals(selectedProviders, renderer.selections!!.providers)
        // Service unavailability or a face transition cannot produce a dispatchable snapshot.
        try {
            readNativeSelections(component, observe = { observed }) { _, _ -> null }
            error("Unavailable selections were accepted")
        } catch (failure: NativePending) {
            assertEquals("selected-provider-records-unavailable", failure.identity)
        }
        try {
            readNativeSelections(component, observe = { observed }) { _, _ ->
                selectedProviders.map { (id, provider) -> NativeSelectionRecord(id, provider) }.dropLast(1)
            }
            error("Incomplete selections were accepted")
        } catch (failure: NativePending) {
            assertEquals("complete-selection-records", failure.identity)
        }
        assertThrows(NativePending::class.java) {
            NativeRenderer.parse(rendererRecord() + "\nimpl.instanceId=another", CANDIDATE_PACKAGE)
        }
        var transitionObservation = 0
        try {
            readNativeSelections(component, observe = {
                if (transitionObservation++ == 0) observed else observed.copy(instance = "changed")
            }) { _, _ -> selectedProviders.map { (id, provider) -> NativeSelectionRecord(id, provider) } }
            error("Changed instance was accepted")
        } catch (failure: NativePending) {
            assertEquals("selection-instance-changed", failure.identity)
        }
        val root = File.createTempFile("native-journal-", ".tmp",
            InstrumentationRegistry.getInstrumentation().context.cacheDir)
        check(root.delete() && root.mkdir())
        try {
            for (fail in listOf(false, true)) {
                val journal = AttemptJournal(File(root, "$fail/attempt.json"))
                val apk = File(root, "candidate-$fail.apk").apply { writeText("private resource-lifetime fixture") }
                val receipt = JSONObject().put("configurationSha256", renderer.configuration.sha256())
                val descriptor = ParcelFileDescriptor.open(apk, ParcelFileDescriptor.MODE_READ_ONLY)
                var calls = 0
                try {
                    Candidate(apk, descriptor, "", "", "", "", "").use {
                        journal.dispatch(receipt, renderer) {
                            calls++
                            if (fail) throw NativePending("synthetic-sdk-failure")
                        }
                    }
                } catch (_: NativePending) {
                    check(fail)
                }
                assertFalse("Private candidate must be deleted after either callback outcome", apk.exists())
                assertFalse("Candidate descriptor must close after either callback outcome", descriptor.fileDescriptor.valid())
                assertEquals(if (fail) "dispatched; advancement uncertain" else "result-verified",
                    journal.read().getString("state"))
                try {
                    journal.dispatch(receipt, renderer) { calls++ }
                    error("Second SDK dispatch was admitted")
                } catch (_: NativePending) {
                    assertEquals(1, calls)
                }
            }
        } finally {
            check(root.deleteRecursively())
        }
    }

    private fun rendererRecord() = buildString {
        appendLine("Resource only package name $CANDIDATE_PACKAGE")
        appendLine("impl.instanceId=existing")
        appendLine("interactiveInstanceId=existing")
        appendLine("watchFaceInstanceId=existing")
        appendLine("currentUserStyleRepository.userStyle=UserStyle[]")
        listOf("mVisible=true mReportedVisible=true", "destroyed=false", "surfaceDestroyed=false",
            "editorObscuresWatchFace=false", "isVisible=true", "isAmbient=false", "overriddenComplications=null")
            .forEach { appendLine(it) }
        for ((id, source) in fixtureProviders()) {
            appendLine("ComplicationSlot $id:")
            appendLine("enabled=true")
            appendLine("defaultDataSourcePolicy.primaryDataSource=ComponentInfo{provider.test/Unselected}")
            appendLine("data=ShortText(dataSource=ComponentInfo{$source})")
        }
    }

    private fun fixtureProviders(): Map<Int, String?> {
        val lower = listOf("Today", "Week", "Ring3", "RingSplit", "StripSplit")
        return (11..18).associateWith { id ->
            if (id <= 15) "$HOST_PACKAGE/app.wardpulse.wear.complication.${lower[id - 11]}ComplicationDataSourceService"
                else "provider.test/Chosen$id"
        }
    }
}
