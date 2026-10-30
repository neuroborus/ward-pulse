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
        val observed = NativeRenderer.parse(dump)
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
        val olderDelivery = NativeRenderer.parse(dump.replace("Chosen16", "Earlier16"))
            .copy(selections = selections)
        assertNotEquals(before.deliveryProvenance, olderDelivery.deliveryProvenance)
        olderDelivery.requireRetainedFrom(before)
        assertThrows(NativePending::class.java) { observed.requirePushConfiguration() }
        val legacyPackage = "app.wardpulse.watchface"
        val legacy = NativeRenderer.parse(dump.replace(CANDIDATE_PACKAGE, legacyPackage))
            .copy(selections = selections.copy(resourcePackage = legacyPackage))
        assertThrows(NativePending::class.java) { legacy.requirePushConfiguration() }
        assertThrows(NativePending::class.java) {
            NativeRenderer.parse(dump.replace("dataSource=ComponentInfo{provider.test/Chosen16}", ""))
                .requirePushConfiguration()
        }
        assertThrows(NativePending::class.java) {
            NativeRenderer.parse(dump.replace("interactiveInstanceId=existing", "interactiveInstanceId=other"))
        }
        assertThrows(NativePending::class.java) {
            NativeRenderer.parse(dump.replace("isAmbient=false", "isAmbient=true"))
        }
    }

    @Test
    fun dispatchedAttemptCannotRunAgainAfterFailureOrSuccess() = runBlocking {
        val system = NativeSystem.parse("0", systemRecord())
        val selectedProviders = fixtureProviders() + mapOf(17 to null, 18 to null)
        var observations = 0
        val renderer = readNativeSelections(system = { system }, native = {
            observations++; it.renderer(rendererRecord())
        }, configuration = { activeConfigurationRecord(selectedProviders) }, diagnostics = NativeDiagnostics { })
        assertEquals(2, observations)
        assertEquals(selectedProviders, renderer.selections!!.providers)
        assertEquals(2, renderer.selections!!.configuredTypes.getValue(17).toInt())
        authorityGuards()
        val cacheDir = checkNotNull(InstrumentationRegistry.getInstrumentation().targetContext.cacheDir) {
            "Target app cache directory must be available"
        }
        check(cacheDir.isDirectory && cacheDir.canWrite()) { "Target app cache directory must be writable" }
        val root = File.createTempFile("native-journal-", ".tmp", cacheDir)
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

    private fun authorityGuards() {
        val messages = mutableListOf<String>()
        val diagnostics = NativeDiagnostics { messages += it }
        fun read(systemDump: String = systemRecord(), nativeDump: String = rendererRecord(),
            config: String = activeConfigurationRecord()) = readNativeSelections(
            { NativeSystem.parse("0", systemDump) }, { it.renderer(nativeDump) }, { config }, diagnostics = diagnostics)
        val good = read()
        val configuration = good.configuration
        // Favorite and row IDs stay outside historical configuration fingerprints.
        val changedRows = read(config = activeConfigurationRecord().replace("favorite-a", "unrelated-b")
            .replace("id=811", "id=9021"))
        assertEquals("811", good.selections!!.rowIds.getValue(11))
        assertEquals("9021", changedRows.selections!!.rowIds.getValue(11))
        assertEquals(configuration, changedRows.configuration)
        assertEquals(configuration, read(config = activeConfigurationRecord().replace("PreviewComplicationDataCache=",
            "PreviewComplicationDataCache=cached-unselected-provider")).configuration)
        assertEquals(configuration, read(config = activeConfigurationRecord().replace("type=5", "type=10")).configuration)
        assertEquals(10, read(config = activeConfigurationRecord().replace("type=5", "type=10"))
            .selections!!.configuredTypes.getValue(11).toInt())
        val empty = read(config = activeConfigurationRecord(fixtureProviders() + mapOf(17 to null, 18 to null)))
        assertEquals(null, empty.selections!!.providers[17])
        assertNotEquals(configuration, empty.configuration)
        for (dump in listOf("", systemRecord().replace("System wallpaper state:", "Other wallpaper state:"),
            systemRecord().replace("User 0:", "User 1:"), systemRecord().replace("mWhich=3", "mWhich=2"),
            systemRecord().replace("SET_LIVE", "INITIALIZE_FALLBACK"), systemRecord().replace("displayId=0", "displayId=1"),
            systemRecord().replace("mDisplayId=0", "mDisplayId=1"),
            systemRecord().replace("mInfo.component=ComponentInfo{$RUNTIME_PACKAGE/$RUNTIME_PACKAGE.DeclarativeWatchFaceRuntime0}",
                "mInfo.component=ComponentInfo{$RUNTIME_PACKAGE/$RUNTIME_PACKAGE.DeclarativeWatchFaceRuntime1}"),
            systemRecord().replace("mEngine=android.service.wallpaper.IWallpaperEngine@ab", "mEngine=null"),
            systemRecord().replace("Lock wallpaper state:", "mDisplayId=0\nLock wallpaper state:"))) {
            assertThrows(NativePending::class.java) { read(systemDump = dump) }
        }
        for (dump in listOf("", rendererRecord().replace("userStyle=UserStyle[]", "userStyle="),
            rendererRecord().replace("WatchFaceEngine:", "WatchFaceEngine:\nWatchFaceEngine:"),
            rendererRecord().replace("asyncWatchFaceConstructionPending=false", "asyncWatchFaceConstructionPending=true"),
            rendererRecord().replace("ComplicationSlot 18:", "ComplicationSlot 17:"),
            rendererRecord().replace("enabled=true", "enabled=true\nenabled=false"),
            rendererRecord().replace("impl.instanceId=existing", "impl.instanceId=existing\nimpl.instanceId=other"),
            rendererRecord().replace("impl.instanceId=existing", "impl.instanceId=other"))) {
            assertThrows(NativePending::class.java) { read(nativeDump = dump) }
        }
        val ownerDump = rendererRecord()
        val manager = "    InteractiveInstanceManager instances:\n"
        val registry = "    \t\tWatchFaceEngine:\n"
        fun rejectSystemOwner(dump: String) {
            assertThrows(NativePending::class.java) { read(nativeDump = dump) }
            var frame = 0
            assertThrows(NativePending::class.java) {
                readNativeSelections({ NativeSystem.parse("0", systemRecord()) },
                    { it.renderer(if (frame++ == 0) ownerDump else dump) }, { activeConfigurationRecord() },
                    diagnostics = NativeDiagnostics { })
            }
            assertEquals("Owner evidence must also be checked in the second native frame", 2, frame)
        }
        fun rejectOwner(dump: String) {
            assertThrows(NativePending::class.java) { NativeRenderer.parse(dump) }
            rejectSystemOwner(dump)
        }
        val fields = listOf(
            "mInitializing=false mDestroyed=false" to "mInitializing=false mDestroyed=true",
            "mVisible=true mReportedVisible=true" to "mVisible=false mReportedVisible=false",
            "mDisplay=Display id 0: DisplayInfo{displayId 0, state ON}" to
                "mDisplay=Display id 0: DisplayInfo{displayId 1, state ON}",
        )
        for ((field, conflict) in fields) {
            val line = "        $field\n"
            val missing = ownerDump.replace(line, "")
            for (dump in listOf(missing, ownerDump.replace(line, line + line),
                ownerDump.replace(line, "        $conflict\n"),
                ownerDump.replace(line, line + "        $conflict\n"),
                // A unique valid-looking value in the later registry cannot replace an outer field.
                missing.replace(registry, registry + "    \t\t\t$field\n"),
                // Nor can an Engine child registry, sibling scope, or unrelated client record supply it.
                missing.replace("      Engine test@ab:\n", "      Engine test@ab:\n        Registry:\n          $field\n"),
                missing.replace(manager, "       Registry:\n        $field\n$manager"),
                missing.replace(manager, "      Sibling:\n        $field\n$manager"),
                missing.replace(manager, "      Sibling record\n        $field\n$manager"),
                missing.replace(manager, "      Sibling=value\n        $field\n$manager"),
                missing.replace(manager, "    Sibling=value\n        $field\n$manager"),
                missing.replace(manager, " Sibling=value\n        $field\n$manager"),
                // Framework-looking continuations outside their measured context are ambiguous too.
                missing.replace(manager, "     mIsScreenTurningOn=false\n        $field\n$manager"),
                missing.replace(manager, "    ClientWindowFrames{frame=[0,0][1,1]}\n        $field\n$manager"),
                missing.replace(manager, "      fl=NOT_FOCUSABLE\n        $field\n$manager"),
                missing.replace(manager, "    Unrelated record:\n        $field\n$manager"),
                missing.replace("      Engine test@ab:\n", "$line      Engine test@ab:\n"))) {
                rejectOwner(dump)
            }
            // Unrelated nested copies must not conflict with complete evidence on the actual owner.
            assertEquals(NativeRenderer.parse(ownerDump), NativeRenderer.parse(ownerDump.replace(registry,
                registry + "    \t\t\t$field\n    \t\t\t$conflict\n")))
            assertEquals(configuration, read(nativeDump = ownerDump.replace(registry,
                registry + "    \t\t\t$field\n    \t\t\t$conflict\n")).configuration)
        }
        val service = ownerDump.lineSequence().first() + "\n"
        val state = "    State of wallpaper $RUNTIME_PACKAGE.DeclarativeWatchFaceRuntime0@ab:\n"
        val engine = "      Engine test@ab:\n"
        for (line in listOf(service, "  Client:\n", state, engine)) {
            val missing = ownerDump.replace(line, "")
            rejectOwner(missing)
            rejectOwner(ownerDump.replace(line, line + line))
            rejectOwner(missing.replace(registry, registry + "    \t\t\t${line.trim()}\n"))
        }
        for (dump in listOf(ownerDump.replace(engine, engine + "      Engine other@cd:\n"),
            ownerDump.replace(engine, "        Engine test@ab:\n"),
            ownerDump.replace(engine, "    Engine test@ab:\n"),
            ownerDump.replace(state, "      ${state.trim()}\n"),
            ownerDump.replace(state, state.replace("Runtime0@", "Runtime1@")),
            ownerDump.replace(service, service.replace("Runtime0 ab", "Runtime1 ab")),
            ownerDump.replace(service, service.replace(RUNTIME_PACKAGE, "unrelated.runtime")),
            ownerDump.replace(service, service.replace("user=0", "user=unavailable")),
            ownerDump.replace(service, service.replace("user=0", "user=0 user=1")),
            ownerDump.replace("    InteractiveInstanceManager instances:", "      InteractiveInstanceManager instances:"),
            ownerDump.replace("mDisplay=Display id 0:", "mDisplay=Display id 1:"))) {
            rejectOwner(dump)
        }
        // A self-consistent alternate owner still has to match the independent System authority.
        for (dump in listOf(ownerDump.replace("user=0", "user=1"), ownerDump.replace("Runtime0", "Runtime1"),
            ownerDump.replace("Display id 0:", "Display id 1:").replace("displayId 0,", "displayId 1,"))) {
            NativeRenderer.parse(dump)
            rejectSystemOwner(dump)
        }
        val config = activeConfigurationRecord()
        val row = config.lineSequence().first { it.startsWith("id=") }
        val favorite = config.lineSequence().single { it.startsWith("activeWatchFaceFavoriteId=") }
        val cachedFavorite = config.replace("$favorite\n", "").replace("PreviewComplicationDataCache=",
            "PreviewComplicationDataCache=\n  $favorite")
        assertEquals(configuration, read(config = config.replace("PreviewComplicationDataCache=",
            "PreviewComplicationDataCache=\n  activeWatchFaceFavoriteId=unavailable")).configuration)
        for (dump in listOf("", cachedFavorite, config.replace("activeConfigs:", "cacheEntries:"), config.replace("size=8", "size=7"),
            config.replace(row + "\n", ""), config.replace(row, "$row\n$row"), config.replace("slot=18", "slot=17"),
            config.replace("slot=18", "slot=19"), config.replace("id=818", "id=817"),
            config.replace("configActionPending=false", "configActionPending=true"),
            config.replace("isEnabled=true", "isEnabled=false"), config.replace("type=5 ", ""),
            config.replace("provider=ComponentInfo{provider.test/Chosen18}", "provider=nullish"),
            config.replace("provider=ComponentInfo{provider.test/Chosen18}", "provider=ComponentInfo{invalid}"),
            config.replace("provider=ComponentInfo{provider.test/Chosen18} ", ""),
            config.replace("threadState=IDLE", "threadState=BUSY"),
            config.replace("threadState=IDLE", "threadState=IDLE\nthreadState=BUSY"),
            config.replace("isFallbackWatchFace=false", "isFallbackWatchFace=true"),
            config.replace("favoriteId=favorite-a", "favoriteId=other"),
            config.replace("favId: favorite-a", "favId: other"),
            config.replace("Current Wallpaper Component=", "Previous Wallpaper Component="),
            config.replace("Current Wallpaper Component=ComponentInfo{$RUNTIME_PACKAGE/$RUNTIME_PACKAGE.DeclarativeWatchFaceRuntime0}",
                "Current Wallpaper Component=ComponentInfo{$RUNTIME_PACKAGE/$RUNTIME_PACKAGE.DeclarativeWatchFaceRuntime1}"),
            config.replace("Active Watch Face Facade:", "Active Watch Face Facade:\nActive Watch Face Facade:"),
            config.replace("mWatchFaceId=WatchFaceId[$CANDIDATE_PACKAGE,null]", "mWatchFaceId=WatchFaceId[other.package,null]"))) {
            assertThrows(NativePending::class.java) { read(config = dump) }
        }
        // Independent frames detect changes in each identity/style/enabled/connection domain.
        val system = NativeSystem.parse("0", systemRecord())
        val native = system.renderer(rendererRecord())
        for (changed in listOf(native.copy(instance = "other"), native.copy(resourcePackage = "app.wardpulse.watchface"),
            native.copy(userStyle = "changed"), native.copy(enabled = native.enabled + (18 to false)),
            native.copy(nativeScope = listOf("other-engine")))) {
            var count = 0
            assertThrows(NativePending::class.java) {
                readNativeSelections({ system }, { if (count++ == 0) native else changed }, { config }, diagnostics = diagnostics)
            }
        }
        var count = 0
        assertThrows(NativePending::class.java) {
            readNativeSelections({ if (count++ == 0) system else system.copy(connection = "other") },
                { native }, { config }, diagnostics = diagnostics)
        }
        assertTrue(messages.contains("semantic_match=false"))
        assertTrue(messages.any { it.startsWith("inventory_declared=") && it.endsWith("complete=false") })
        // Relative dump counters and cached delivery are outside the semantic identity comparison.
        count = 0
        var deliveries = 0
        readNativeSelections({ NativeSystem.parse("0", systemRecord().replace("mLastDiedTime=-1", "mLastDiedTime=${count++}")) },
            { if (deliveries++ == 0) native else native.copy(deliveredSources = mapOf(16 to "provider.test/Older")) },
            { config }, diagnostics = diagnostics)
        selectionDiagnosticGuards(system, native, config)
    }

    private fun selectionDiagnosticGuards(system: NativeSystem, native: NativeRenderer, config: String) {
        for (outcome in listOf("null", "match", "mismatch", "error")) {
            val messages = mutableListOf<String>()
            val diagnostic = NativeDiagnostics { messages += it }
            val caller: (ComponentName) -> Unit = { authority -> diagnostic.caller({
                when (outcome) {
                    "null" -> null
                    "match" -> system.component
                    "mismatch" -> ComponentName("provider.test", "Other")
                    else -> throw SecurityException("private caller payload")
                }
            }, authority) }
            readNativeSelections({ system }, { native }, { config }, caller, diagnostic)
            assertTrue(messages.contains("caller_wallpaper=$outcome"))
            assertThrows(NativePending::class.java) {
                readNativeSelections({ system }, { throw NativePending("private real failure") }, { config }, caller, diagnostic)
            }
            diagnostic.at(NativePhase.CANDIDATE_CLEANUP) { Unit }
            assertEquals("phase=native_before; category=guard_rejected", diagnostic.failure(IOException("private cleanup")))
            assertTrue(messages.contains("semantic_match=true"))
            assertTrue(messages.contains("inventory_declared=8; actual=8; unique=8; complete=true"))
            assertTrue(messages.all { it.length < 160 && it.matches(Regex(
                "phase=[a-z_]+(; category=[a-z_]+)?|caller_wallpaper=(null|match|mismatch|error)|" +
                    "semantic_match=(true|false)|inventory_declared=[0-9]+; actual=[0-9]+; unique=[0-9]+; complete=(true|false)",
            )) })
            assertFalse(messages.any { "private" in it })
        }
    }

    private fun systemRecord() = """
        System wallpaper state:
        User 0: id=321: mWhich=3: mSystemWasBoth=true: mBindSource=SET_LIVE
        Display state:
        displayId=0
        mWallpaperComponent=ComponentInfo{$RUNTIME_PACKAGE/$RUNTIME_PACKAGE.DeclarativeWatchFaceRuntime0}
        Wallpaper connection com.android.server.wallpaper.WallpaperManagerService${'$'}WallpaperConnection@ab:
        mInfo.component=ComponentInfo{$RUNTIME_PACKAGE/$RUNTIME_PACKAGE.DeclarativeWatchFaceRuntime0}
        mDisplayId=0
        mEngine=android.service.wallpaper.IWallpaperEngine@ab
        mService=android.service.wallpaper.IWallpaperService@ab
        mToken=android.os.Binder@ab
        mLastDiedTime=-1
        Lock wallpaper state:
        Fallback wallpaper state:
        mWallpaperComponent=ComponentInfo{fallback.test/Default}
    """.trimIndent() + "\n"

    private fun activeConfigurationRecord(providers: Map<Int, String?> = fixtureProviders()) = buildString {
        appendLine("Wear Service API: complications")
        appendLine("ComplicationManager")
        appendLine("ComplicationDataSendingController")
        appendLine("ComplicationsConfigController")
        appendLine("activeWatchFaceFavoriteId=WatchFaceFavoriteId{mWatchFaceId=WatchFaceId[$CANDIDATE_PACKAGE,null], mFavoriteId=favorite-a, mType=AndroidxWatchFace}")
        appendLine("activeConfigs: size=8")
        providers.forEach { (slot, provider) ->
            appendLine("id=${800 + slot} slot=$slot type=${if (provider == null) 2 else 5} configActionPending=false " +
                "provider=${provider?.let { "ComponentInfo{$it}" } ?: "null"} isEnabled=true")
        }
        appendLine("PreviewComplicationDataCache=")
        appendLine("ComplicationUpdateController")
        appendLine("DeviceLockStateReceiver")
        appendLine("Wear Service API: watch_faces")
        appendLine("Active Watch Face Facade:")
        appendLine("threadState=IDLE")
        appendLine("isFallbackWatchFace=false")
        appendLine("runningFlow=ANDROIDX")
        appendLine("activeWatchFaceComponent=WatchFaceId[$CANDIDATE_PACKAGE,null]")
        appendLine("favoriteId=favorite-a")
        appendLine("Current Active Engine:")
        appendLine("Engine Type=AndroidX")
        appendLine("Current Active Watch Face=favId: favorite-a, family: WatchFaceId[$CANDIDATE_PACKAGE,null]")
        appendLine("Current Wallpaper Component=ComponentInfo{$RUNTIME_PACKAGE/$RUNTIME_PACKAGE.DeclarativeWatchFaceRuntime0}")
        appendLine("Resource Only WatchFace=true")
        appendLine("Runtime Package=$RUNTIME_PACKAGE")
        appendLine("WearServices WatchFace Client=Binder Alive")
        appendLine("Watch Face Favorite Repository (DB)")
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
        for (output in listOf(rendererRecord(), "incomplete private record")) {
            locator.writeText(output)
            val descriptor = ParcelFileDescriptor.open(locator, ParcelFileDescriptor.MODE_READ_ONLY)
            val observed = readNativeObservation(ParcelFileDescriptor.AutoCloseInputStream(descriptor),
                NativeObservation.NATIVE, NativeDiagnostics { })
            if (output == rendererRecord()) NativeRenderer.parse(observed) else {
                assertThrows(NativePending::class.java) { NativeRenderer.parse(observed) }
            }
            assertFalse("Observer FD must close before either parse outcome", descriptor.fileDescriptor.valid())
        }
        for (overflow in listOf(false, true)) {
            val messages = mutableListOf<String>()
            val diagnostic = NativeDiagnostics { messages += it }
            var closed = false
            val input = object : InputStream() {
                var remaining = if (overflow) 2 * 1024 * 1024 + 1 else 1
                override fun read(): Int = error("Use bounded buffer reads")
                override fun read(bytes: ByteArray, offset: Int, length: Int): Int {
                    if (remaining == 0) throw IOException("private partial read")
                    val count = minOf(remaining, length)
                    bytes.fill('x'.code.toByte(), offset, offset + count)
                    remaining -= count
                    return count
                }
                override fun close() { closed = true; throw SecurityException("private close") }
            }
            assertThrows(if (overflow) NativePending::class.java else IOException::class.java) {
                diagnostic.at(NativePhase.NATIVE_BEFORE) { readNativeObservation(input, NativeObservation.NATIVE, diagnostic) }
            }
            assertTrue(closed)
            assertEquals("phase=native_before; category=${if (overflow) "guard_rejected" else "io_unavailable"}",
                diagnostic.failure(SecurityException("private cleanup")))
            assertTrue(messages.any { it.matches(Regex("record=native; bytes=[0-9]+; sha256=[a-f0-9]{64}; complete=false")) })
            assertFalse(messages.any { "private" in it })
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
        appendLine("SERVICE $RUNTIME_PACKAGE/.DeclarativeWatchFaceRuntime0 ab pid=123 user=0")
        appendLine("  Client:")
        appendLine("    State of wallpaper $RUNTIME_PACKAGE.DeclarativeWatchFaceRuntime0@ab:")
        appendLine("      Engine test@ab:")
        appendLine("        mInitializing=false mDestroyed=false")
        appendLine("        mVisible=true mReportedVisible=true")
        appendLine("     mIsScreenTurningOn=false")
        appendLine("        mDisplay=Display id 0: DisplayInfo{displayId 0, state ON}")
        appendLine("        mWinFrames=")
        appendLine("    ClientWindowFrames{frame=[0,0][384,384]}")
        appendLine("        mLayout={(0,0)(fillxfill) gr=TOP START CENTER ty=WALLPAPER fmt=RGBX_8888")
        appendLine("      fl=NOT_FOCUSABLE NOT_TOUCHABLE LAYOUT_IN_SCREEN LAYOUT_NO_LIMITS LAYOUT_INSET_DECOR")
        appendLine("      pfl=WANTS_OFFSET_NOTIFICATIONS")
        appendLine("      bhv=DEFAULT")
        appendLine("      frameRateBoostOnTouch=true")
        appendLine("      dvrrWindowFrameRateHint=true}")
        appendLine("        mOffsetMessageEnqueued=falseAndroidX WatchFaceService $RUNTIME_PACKAGE")
        appendLine("    InteractiveInstanceManager instances:")
        appendLine("    \tInteractiveInstanceManager:")
        appendLine("    \t\timpl.instanceId=existing")
        appendLine("    \t\tWatchFaceEngine:")
        listOf("destroyed=false", "surfaceDestroyed=false", "asyncWatchFaceConstructionPending=false",
            "overriddenComplications=null").forEach { appendLine("    \t\t\t$it") }
        appendLine("    \t\t\tResource only package name $CANDIDATE_PACKAGE")
        appendLine("    \t\t\tinteractiveInstanceId=existing")
        appendLine("    \t\t\tWatchFaceImpl (ComponentInfo{$CANDIDATE_PACKAGE/null}):")
        appendLine("    \t\t\t\tcurrentUserStyleRepository.userStyle=UserStyle[]")
        appendLine("    \t\t\t\teditorObscuresWatchFace=false")
        appendLine("    \t\t\t\tWatchState:")
        listOf("isVisible=true", "isAmbient=false", "isHeadless=false", "watchFaceInstanceId=existing")
            .forEach { appendLine("    \t\t\t\t\t$it") }
        appendLine("    \t\t\t\tComplicationSlotsManager:")
        for ((id, source) in fixtureProviders()) {
            appendLine("    \t\t\t\t\tComplicationSlot $id:")
            appendLine("    \t\t\t\t\t\tenabled=true")
            appendLine("    \t\t\t\t\t\tsupportedTypes=RANGED_VALUE, EMPTY")
            appendLine("    \t\t\t\t\t\tdefaultDataSourcePolicy.primaryDataSource=ComponentInfo{provider.test/Unselected}")
            appendLine("    \t\t\t\t\t\tdata=ShortText(dataSource=ComponentInfo{$source})")
        }
        appendLine("    EditorService:")
        appendLine("    HeadlessWatchFace instances:")
    }

    private fun fixtureProviders(): Map<Int, String?> {
        val lower = listOf("Today", "Week", "Ring3", "RingSplit", "StripSplit")
        return (11..18).associateWith { id ->
            if (id <= 15) "$HOST_PACKAGE/app.wardpulse.wear.complication.${lower[id - 11]}ComplicationDataSourceService"
                else "provider.test/Chosen$id"
        }
    }
}
