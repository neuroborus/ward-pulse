package app.wardpulse.wear.nativeintegration

import android.content.ComponentName
import android.content.pm.PackageInfo
import android.os.Bundle
import android.os.ParcelFileDescriptor
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.io.ByteArrayInputStream
import java.io.File
import java.io.FilterInputStream
import java.io.IOException
import java.io.InputStream
import java.util.concurrent.TimeUnit
import java.util.zip.ZipEntry
import java.util.zip.ZipFile
import java.util.zip.ZipOutputStream
import kotlinx.coroutines.runBlocking
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

/** Guard decisions and test-private resource/process fixtures; no SDK calls or normal preferences. */
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
        installedIdentityGuards()
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
            installedResourceCleanup(root)
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

    private fun installedIdentityGuards() {
        val path = "/data/app/~~test/app.wardpulse.watchfacepush.main-test/base.apk"
        val record = "package:$path\n$INSTALLED_PUSH_PATH_END\n"
        for (output in listOf(record, record.replace("~~test/", ""))) {
            var closed = false
            val input = object : ByteArrayInputStream(output.toByteArray()) {
                override fun close() { closed = true; super.close() }
            }
            assertEquals(output.substringAfter("package:").substringBefore('\n'), readInstalledPushPath(input).path)
            assertTrue(closed)
        }
        // One complete path is mandatory, including when an archive itself has no split metadata.
        for (output in listOf("", "package:$path\n", "$INSTALLED_PUSH_PATH_END\n", record.trimEnd(),
            record.dropLast(4), record + "\n", "package:$path\n$record",
            "package:$path\n" + record.replace("base.apk", "split_config.apk"),
            record.replace("base.apk", "split_config.apk"), record.replace("/data/app/", "/tmp/"),
            record.replace("~~test", ".."), record.replace("~~test", "test space"),
            record.replace("\n", "\r\n"), record + "error", record.replace("base", "ba\u0000se"),
            "package:" + "x".repeat(4097))) {
            var closed = false
            val input = object : ByteArrayInputStream(output.toByteArray()) {
                override fun close() { closed = true; super.close() }
            }
            assertThrows(NativePending::class.java) { readInstalledPushPath(input) }
            assertTrue("Locator stream must close for every rejected enumeration", closed)
        }
        val signer = "a".repeat(64)
        val valid = NativeArchive(CANDIDATE_PACKAGE, 3, listOf(signer), false)
        assertEquals(signer, valid.requireIdentity(CANDIDATE_PACKAGE))
        for (identity in listOf(valid.copy(name = null), valid.copy(name = HOST_PACKAGE),
            valid.copy(code = 0), valid.copy(code = -1), valid.copy(hasSplits = true),
            valid.copy(signers = null), valid.copy(signers = emptyList()),
            valid.copy(signers = listOf(signer, signer)), valid.copy(signers = listOf("incomplete")),
            NativeArchive.fromInfo(PackageInfo().apply { packageName = CANDIDATE_PACKAGE; longVersionCode = 3 }))) {
            assertThrows(NativePending::class.java) { identity.requireIdentity(CANDIDATE_PACKAGE) }
        }
        val messages = mutableListOf<String>()
        val diagnostics = NativeDiagnostics { messages += it }
        val secret = "/private/test token=private-payload runtime=test-instance"
        assertThrows(SecurityException::class.java) {
            diagnostics.at(NativePhase.INSTALLED_ARCHIVE) { throw SecurityException(secret) }
        }
        // Later cleanup must not replace the phase of the original failure.
        diagnostics.at(NativePhase.CANDIDATE_CLEANUP) { Unit }
        assertEquals("phase=installed_archive; category=access_denied", diagnostics.failure(IOException(secret)))
        for (failure in listOf(IOException(secret), NativePending(secret), IllegalStateException(secret))) {
            val diagnostic = NativeDiagnostics { messages += it }
            diagnostic.enter(NativePhase.SDK_UPDATE)
            val expectedCategory = when (failure) {
                is IOException -> "io_unavailable"
                is NativePending -> "guard_rejected"
                else -> "capability_unavailable"
            }
            assertEquals("phase=sdk_update; category=$expectedCategory", diagnostic.failure(failure))
        }
        assertTrue(messages.all { it.length < 100 && it.matches(Regex("phase=[a-z_]+(; category=[a-z_]+)?")) })
        assertFalse(messages.any { it.contains(secret) })
    }

    private fun installedResourceCleanup(root: File) {
        locatorCommandContract()
        val record = "package:/data/app/~~test/app.wardpulse.watchfacepush.main-test/base.apk\n$INSTALLED_PUSH_PATH_END\n"
        val locator = File(root, "locator.txt")
        for (output in listOf(record, record + record)) {
            locator.writeText(output)
            val descriptor = ParcelFileDescriptor.open(locator, ParcelFileDescriptor.MODE_READ_ONLY)
            val input = ParcelFileDescriptor.AutoCloseInputStream(descriptor)
            if (output == record) readInstalledPushPath(input) else {
                assertThrows(NativePending::class.java) { readInstalledPushPath(input) }
            }
            assertFalse("Locator FD must close on success and parse failure", descriptor.fileDescriptor.valid())
        }
        var locatorClosed = false
        val failingLocator = object : InputStream() {
            private var reads = 0
            override fun read(): Int {
                if (reads++ > 0) throw IOException("private read failure")
                return 'p'.code
            }
            override fun close() { locatorClosed = true }
        }
        assertThrows(IOException::class.java) { readInstalledPushPath(failingLocator) }
        assertTrue("A partial locator read must close its stream", locatorClosed)

        val apk = File(root, "installed.apk")
        val resources = byteArrayOf(0, 1, -1, 127, -128)
        fun writeArchive(withResources: Boolean = true, payload: ByteArray = resources) {
            ZipOutputStream(apk.outputStream()).use { zip ->
                zip.putNextEntry(ZipEntry(if (withResources) "resources.arsc" else "other"))
                zip.write(payload)
                zip.closeEntry()
            }
        }
        writeArchive()
        val signer = "a".repeat(64)
        val identity = NativeArchive(CANDIDATE_PACKAGE, 3, listOf(signer), false)
        fun diagnostics() = NativeDiagnostics { }
        var locations = 0
        val installed = NativePackage.readInstalled(locate = { locations++; apk }, archive = {
            assertEquals(apk, it)
            identity
        }, diagnostics = diagnostics())
        assertEquals(2, locations)
        assertEquals(3L, installed.code)
        assertEquals(signer, installed.signer)
        assertEquals(apk.inputStream().sha256(), installed.apk)
        assertEquals(resources.inputStream().sha256(), installed.resources)
        var inspected = false
        assertThrows(IOException::class.java) {
            NativePackage.readInstalled({ File(root, "absent.apk") }, { inspected = true; identity }, diagnostics())
        }
        assertFalse("Missing installed bytes must stop before archive inspection", inspected)
        assertThrows(NativePending::class.java) {
            NativePackage.readInstalled({ apk }, { null }, diagnostics())
        }
        assertThrows(SecurityException::class.java) {
            NativePackage.readInstalled({ apk }, { throw SecurityException("private archive failure") }, diagnostics())
        }
        assertThrows(NativePending::class.java) {
            NativePackage.readInstalled({ apk }, { identity.copy(signers = null) }, diagnostics())
        }
        locations = 0
        assertThrows(NativePending::class.java) {
            NativePackage.readInstalled({ if (locations++ == 0) apk else File(root, "different.apk") },
                { identity }, diagnostics())
        }
        assertThrows(NativePending::class.java) {
            NativePackage.readInstalled({ apk }, { writeArchive(payload = byteArrayOf(2)); identity }, diagnostics())
        }
        writeArchive()
        val zip = ZipFile(apk)
        assertEquals(installed.resources, readNativeResources(zip))
        assertThrows(IllegalStateException::class.java) { zip.entries() }
        var streamClosed = false
        val failingZip = object : ZipFile(apk) {
            override fun getInputStream(entry: ZipEntry): InputStream = object : FilterInputStream(super.getInputStream(entry)) {
                override fun read(buffer: ByteArray, offset: Int, length: Int): Int {
                    throw IOException("private resource read failure")
                }
                override fun close() { streamClosed = true; super.close() }
            }
        }
        assertThrows(IOException::class.java) { readNativeResources(failingZip) }
        assertTrue("Partially read resource streams must close", streamClosed)
        assertThrows(IllegalStateException::class.java) { failingZip.entries() }
        writeArchive(withResources = false)
        val missing = ZipFile(apk)
        assertThrows(NativePending::class.java) { readNativeResources(missing) }
        assertThrows(IllegalStateException::class.java) { missing.entries() }
        // Status transport must not interfere with ownership cleanup.
        val candidate = File(root, "cleanup.apk").apply { writeBytes(resources) }
        val descriptor = ParcelFileDescriptor.open(candidate, ParcelFileDescriptor.MODE_READ_ONLY)
        Candidate(candidate, descriptor, "", "", "", "", "", NativeDiagnostics { error("private status failure") }).close()
        assertFalse(candidate.exists())
        assertFalse(descriptor.fileDescriptor.valid())
    }

    private fun locatorCommandContract() {
        val path = "/data/app/~~test/app.wardpulse.watchfacepush.main-test/base.apk"
        val enumeration = "/system/bin/pm\${IFS}path\${IFS}$CANDIDATE_PACKAGE"
        assertTrue(INSTALLED_PUSH_PATH_COMMAND.contains(enumeration))
        val output = "echo\${IFS}package:$path"
        for ((fixture, exitCode) in listOf(output to 0, "false" to 1, "$output;$output" to 0)) {
            // Execute with UiAutomation's actual String-tokenization contract, under the normal UID.
            // Replace only package enumeration with fixed output; never query installed packages here.
            val process = Runtime.getRuntime().exec(INSTALLED_PUSH_PATH_COMMAND.replace(enumeration, fixture))
            try {
                process.inputStream.use { input ->
                    process.errorStream.use {
                        process.outputStream.use { }
                        assertTrue("Private locator command must finish", process.waitFor(5, TimeUnit.SECONDS))
                        assertEquals(exitCode, process.exitValue())
                        if (fixture == output) {
                            assertEquals(File(path), readInstalledPushPath(input))
                        } else {
                            assertThrows(NativePending::class.java) { readInstalledPushPath(input) }
                        }
                    }
                }
            } finally {
                if (process.isAlive) {
                    process.destroyForcibly()
                    assertTrue("Private locator process must retire", process.waitFor(5, TimeUnit.SECONDS))
                }
            }
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
