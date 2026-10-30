package app.wardpulse.wear.nativeintegration

import android.app.Instrumentation
import android.app.WallpaperManager
import android.content.ComponentName
import android.content.Context
import android.content.pm.PackageInfo
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.os.ParcelFileDescriptor
import androidx.test.platform.app.InstrumentationRegistry
import androidx.wear.watchfacepush.WatchFacePushManager
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.IOException
import java.io.InputStream
import java.security.MessageDigest
import java.util.zip.ZipFile
import org.json.JSONObject

internal const val HOST_PACKAGE = "app.wardpulse"
internal const val CANDIDATE_PACKAGE = "app.wardpulse.watchfacepush.main"
internal const val UPDATE_CLASS = "app.wardpulse.wear.nativeintegration.NativePushUpdateTest"
internal const val RUNTIME_PACKAGE = "com.google.wear.watchface.runtime"
internal const val INSTALLED_PUSH_PATH_END = "NATIVE_PUSH_PATHS_COMPLETE"
// UiAutomation uses Runtime.exec(String): the -c script must be a single whitespace-free token.
// Expand argument separators inside the shell, which also owns the conditional completion marker.
internal const val INSTALLED_PUSH_PATH_COMMAND =
    "/system/bin/sh -c /system/bin/pm\${IFS}path\${IFS}$CANDIDATE_PACKAGE&&echo\${IFS}$INSTALLED_PUSH_PATH_END"

internal class NativePending(val identity: String) : IllegalStateException("Pending: native guard $identity")

internal fun nativeGuard(condition: Boolean, identity: String) {
    if (!condition) throw NativePending(identity)
}

internal fun InputStream.sha256(): String = use { input ->
    val digest = MessageDigest.getInstance("SHA-256")
    val buffer = ByteArray(8192)
    while (true) {
        val count = input.read(buffer)
        if (count < 0) break
        digest.update(buffer, 0, count)
    }
    digest.digest().joinToString("") { "%02x".format(it) }
}

internal fun String.sha256() = byteInputStream().sha256()

internal enum class NativePhase {
    ADMISSION, HOST_IDENTITY, INSTALLED_PATH, INSTALLED_BYTES, INSTALLED_ARCHIVE, INSTALLED_IDENTITY,
    INSTALLED_RESOURCES, ASSET_ARCHIVE, BASELINE_CLEANUP, SDK_SUPPORT, SDK_MANAGER,
    SDK_INVENTORY, SDK_ACTIVE, SDK_UPDATE, SELECTION_OBSERVATION, SYSTEM_BEFORE, NATIVE_BEFORE,
    ACTIVE_CONFIGURATION, NATIVE_AFTER, SYSTEM_AFTER, SELECTION_MATCH, CANDIDATE_ARCHIVE,
    CANDIDATE_CLEANUP, JOURNAL, SCREENSHOT,
}

internal enum class NativeFailureCategory { GUARD_REJECTED, ACCESS_DENIED, IO_UNAVAILABLE, CAPABILITY_UNAVAILABLE }

/** Only closed vocabulary is emitted; even guard identities and exception causes are private. */
internal class NativeDiagnostics(private val emit: (String) -> Unit = { message ->
    InstrumentationRegistry.getInstrumentation().sendStatus(0, Bundle().apply {
        putString("stream", "\nNative Push: $message\n")
    })
}) {
    private var current = NativePhase.ADMISSION
    private var firstFailure: String? = null

    private fun report(message: String) {
        try {
            emit(message)
        } catch (_: Throwable) {
            // A status-transport failure must never prevent resource cleanup.
        }
    }

    fun enter(phase: NativePhase) {
        current = phase
        report("phase=${phase.name.lowercase()}")
    }

    fun failure(failure: Throwable): String {
        val category = when (failure) {
            is NativePending -> NativeFailureCategory.GUARD_REJECTED
            is SecurityException -> NativeFailureCategory.ACCESS_DENIED
            is IOException -> NativeFailureCategory.IO_UNAVAILABLE
            else -> NativeFailureCategory.CAPABILITY_UNAVAILABLE
        }
        return firstFailure ?: "phase=${current.name.lowercase()}; category=${category.name.lowercase()}"
            .also { firstFailure = it; report(it) }
    }

    fun observation(kind: NativeObservation, bytes: ByteArray, complete: Boolean) {
        report("record=${kind.name.lowercase()}; bytes=${bytes.size}; sha256=${bytes.inputStream().sha256()}; complete=$complete")
    }

    fun caller(read: () -> ComponentName?, authority: ComponentName) {
        val result = try {
            when (read()) { null -> "null"; authority -> "match"; else -> "mismatch" }
        } catch (_: Throwable) { "error" }
        report("caller_wallpaper=$result")
    }

    fun inventory(declared: Int, actual: Int, unique: Int, complete: Boolean) {
        report("inventory_declared=${declared.coerceIn(0, 2097153)}; actual=$actual; unique=$unique; complete=$complete")
    }

    fun semanticMatch(matches: Boolean) = report("semantic_match=$matches")

    fun <T> at(phase: NativePhase, action: () -> T): T {
        enter(phase)
        return recordFailure(action)
    }

    inline fun <T> recordFailure(action: () -> T): T {
        try {
            return action()
        } catch (failure: Throwable) {
            this.failure(failure)
            throw failure
        }
    }
}

/** EOF-bounded complete enumeration, not an archive's potentially absent split metadata. */
internal fun readInstalledPushPath(input: InputStream): File = input.use {
    val bytes = it.readNBytes(4097)
    nativeGuard(bytes.size <= 4096, "bounded-installed-paths")
    val match = Regex("package:(/data/app/(?:[A-Za-z0-9_+=.~-]+/){1,2}base\\.apk)\n$INSTALLED_PUSH_PATH_END\n")
        .matchEntire(bytes.toString(Charsets.US_ASCII))
        ?: throw NativePending("single-complete-installed-path")
    val path = match.groupValues[1]
    nativeGuard(path.split('/').none { part -> part == "." || part == ".." }, "installed-path-components")
    File(path)
}

/** A projection of real archive metadata; expected values never fill missing observations. */
internal data class NativeArchive(
    val name: String?, val code: Long, val signers: List<String>?, val hasSplits: Boolean,
) {
    fun requireIdentity(name: String): String {
        nativeGuard(this.name == name && code > 0 && !hasSplits, "archive-package-code-splits")
        val signer = signers?.singleOrNull() ?: throw NativePending("archive-single-signer-unavailable")
        nativeGuard(signer.matches(Regex("[a-f0-9]{64}")), "archive-signer-identity")
        return signer
    }

    companion object {
        fun fromInfo(info: PackageInfo): NativeArchive = NativeArchive(
            info.packageName, info.longVersionCode,
            info.signingInfo?.apkContentsSigners?.map { it.toByteArray().inputStream().sha256() },
            !info.splitNames.isNullOrEmpty() || !info.applicationInfo?.splitSourceDirs.isNullOrEmpty(),
        )
    }
}

internal fun readNativeResources(zip: ZipFile): String = zip.use {
    val entries = it.entries().asSequence().filter { entry -> entry.name == "resources.arsc" }.take(2).toList()
    nativeGuard(entries.size == 1 && !entries.single().isDirectory, "single-resource-table")
    it.getInputStream(entries.single()).sha256()
}

/** Expectations come from HOST's independent observation before test-APK provisioning. */
internal class NativePushExpectations(private val arguments: Bundle) {
    fun required(name: String): String = arguments.getString(name).orEmpty().also {
        nativeGuard(it.isNotBlank() && it.length <= 512, name)
    }

    fun hash(name: String) = required(name).also {
        nativeGuard(it.matches(Regex("[a-f0-9]{64}")), name)
    }

    fun admit(method: String, runnerName: String, avd: String, qemu: String, watch: Boolean,
        testClass: String = UPDATE_CLASS, optIn: String = "push-3-to-4") {
        nativeGuard(runnerName == "androidx.test.runner.AndroidJUnitRunner", "stock-runner")
        nativeGuard(arguments.getString("class") == "$testClass#$method", "explicit-method")
        nativeGuard(arguments.getString("wardpulseNativeIntegration") == optIn, "opt-in")
        nativeGuard(watch && qemu == "1" && avd in setOf(
            "wardpulse_wear_round_api36_1", "wardpulse_wear_square_api36_1",
        ) && avd == required("expectedAvd"), "canonical-emulator")
    }
}

internal data class NativePackage(val code: Long, val apk: String, val signer: String,
    val resources: String? = null) {
    fun json() = JSONObject().put("code", code).put("apk", apk).put("signer", signer)

    companion object {
        fun read(context: Context, name: String, diagnostics: NativeDiagnostics = NativeDiagnostics()): NativePackage {
            if (name == CANDIDATE_PACKAGE) {
                val instrumentation = InstrumentationRegistry.getInstrumentation()
                nativeGuard(context === instrumentation.targetContext, "installed-target-context")
                return readInstalled(locate = {
                    // Existing UiAutomation only locates paths. APK bytes never cross this shell pipe.
                    instrumentation.uiAutomation.executeShellCommand(
                        INSTALLED_PUSH_PATH_COMMAND,
                    ).use { descriptor ->
                        readInstalledPushPath(ParcelFileDescriptor.AutoCloseInputStream(descriptor))
                    }
                }, archive = { file ->
                    context.packageManager.getPackageArchiveInfo(file.path, PackageManager.GET_SIGNING_CERTIFICATES)
                        ?.let { NativeArchive.fromInfo(it) }
                }, diagnostics = diagnostics)
            }
            val info = context.packageManager.getPackageInfo(name, PackageManager.GET_SIGNING_CERTIFICATES)
            nativeGuard(info.packageName == name, "installed-package")
            return fromInfo(info)
        }

        internal fun readInstalled(locate: () -> File, archive: (File) -> NativeArchive?,
            diagnostics: NativeDiagnostics): NativePackage {
            val file = diagnostics.at(NativePhase.INSTALLED_PATH, locate)
            val apk = diagnostics.at(NativePhase.INSTALLED_BYTES) { file.inputStream().sha256() }
            val identity = diagnostics.at(NativePhase.INSTALLED_ARCHIVE) {
                val info = archive(file) ?: throw NativePending("installed-archive-unavailable")
                info to info.requireIdentity(CANDIDATE_PACKAGE)
            }
            val resources = diagnostics.at(NativePhase.INSTALLED_RESOURCES) { readNativeResources(ZipFile(file)) }
            diagnostics.at(NativePhase.INSTALLED_BYTES) {
                nativeGuard(file.inputStream().sha256() == apk, "installed-file-changed")
            }
            diagnostics.at(NativePhase.INSTALLED_PATH) {
                nativeGuard(locate() == file, "installed-path-changed")
            }
            // Bracketed observations detect changes; they do not claim atomic package observation.
            return NativePackage(identity.first.code, apk, identity.second, resources)
        }

        fun fromInfo(info: PackageInfo): NativePackage {
            val signer = NativeArchive.fromInfo(info).requireIdentity(info.packageName)
            return NativePackage(
                info.longVersionCode,
                File(checkNotNull(info.applicationInfo).sourceDir).inputStream().sha256(),
                signer,
            )
        }
    }
}

/** Read-only shell calls through the instrumentation's existing UiAutomation owner. */
internal class NativePushDevice(private val instrumentation: Instrumentation,
    private val diagnostics: NativeDiagnostics = NativeDiagnostics()) {
    private val context = instrumentation.targetContext

    fun shell(command: String): String = ParcelFileDescriptor.AutoCloseInputStream(
        instrumentation.uiAutomation.executeShellCommand(command),
    ).use { input ->
        val bytes = input.readNBytes(2 * 1024 * 1024 + 1)
        nativeGuard(bytes.size <= 2 * 1024 * 1024, "bounded-native-record")
        bytes.toString(Charsets.UTF_8).trim()
    }

    fun admit(expected: NativePushExpectations, method: String,
        testClass: String = UPDATE_CLASS, optIn: String = "push-3-to-4") {
        diagnostics.enter(NativePhase.ADMISSION)
        val avd = shell("getprop ro.boot.qemu.avd_name").ifBlank {
            shell("getprop ro.kernel.qemu.avd_name")
        }
        expected.admit(
            method, instrumentation.javaClass.name, avd, shell("getprop ro.kernel.qemu"),
            context.packageManager.hasSystemFeature(PackageManager.FEATURE_WATCH),
            testClass, optIn,
        )
        nativeGuard(Build.VERSION.SDK_INT == 36 &&
            Build.FINGERPRINT.sha256() == expected.hash("expectedFingerprintSha256"), "system-image")
        val dimensions = if (avd.contains("square")) "360x360" else "384x384"
        nativeGuard(shell("wm size") == "Physical size: $dimensions", "canonical-display")
        nativeGuard(context.packageName == HOST_PACKAGE, "target-context")
        nativeGuard(instrumentation.targetContext.applicationContext.javaClass.name == "android.app.Application",
            "baseline-application")
        // Resolve the exact baseline SDK entry before any manager-changing operation.
        diagnostics.enter(NativePhase.SDK_SUPPORT)
        WatchFacePushManager::class.java.getMethod("updateWatchFace", String::class.java,
            ParcelFileDescriptor::class.java, String::class.java, kotlin.coroutines.Continuation::class.java)
    }

    fun baseline(expected: NativePushExpectations): JSONObject {
        diagnostics.enter(NativePhase.HOST_IDENTITY)
        val host = NativePackage.read(context, HOST_PACKAGE, diagnostics)
        nativeGuard(host.code == 4L && host.apk == expected.hash("expectedHostApkSha256") &&
            host.signer == expected.hash("expectedHostSignerSha256"), "original-host")
        val asset = context.assets.open("default_watchface.apk").sha256()
        nativeGuard(asset == expected.hash("expectedAsset3Sha256"), "original-asset-3")
        val installed = NativePackage.read(context, CANDIDATE_PACKAGE, diagnostics)
        diagnostics.enter(NativePhase.INSTALLED_IDENTITY)
        nativeGuard(installed.code == 3L && installed.apk == expected.hash("expectedPush3ApkSha256") &&
            installed.signer == expected.hash("expectedPushSignerSha256"), "installed-push-3")
        diagnostics.enter(NativePhase.ASSET_ARCHIVE)
        val file = File.createTempFile("native-baseline-", ".apk", context.cacheDir)
        try {
            context.assets.open("default_watchface.apk").use { input ->
                file.outputStream().use { input.copyTo(it) }
            }
            val info = checkNotNull(context.packageManager.getPackageArchiveInfo(file.path,
                PackageManager.GET_SIGNING_CERTIFICATES))
            nativeGuard(info.packageName == CANDIDATE_PACKAGE && info.longVersionCode == 3L &&
                info.signingInfo?.apkContentsSigners?.singleOrNull()?.toByteArray()?.inputStream()?.sha256() ==
                installed.signer, "asset-3-archive")
        } catch (failure: Throwable) {
            diagnostics.failure(failure)
            throw failure
        } finally {
            diagnostics.at(NativePhase.BASELINE_CLEANUP) {
                nativeGuard(file.delete(), "baseline-file-cleanup")
            }
        }
        return JSONObject().put("host", host.json()).put("asset", asset)
    }

    fun unchangedHost(before: JSONObject) {
        diagnostics.enter(NativePhase.HOST_IDENTITY)
        val original = before.getJSONObject("host")
        val current = NativePackage.read(context, HOST_PACKAGE)
        nativeGuard(current.code == original.getLong("code") && current.apk == original.getString("apk") &&
            current.signer == original.getString("signer"), "retained-host")
        nativeGuard(context.assets.open("default_watchface.apk").sha256() == before.getString("asset"),
            "retained-asset-3")
    }

    fun renderer(expected: NativePushExpectations): NativeRenderer {
        return readRenderer(expected).also {
            nativeGuard(it.instance.sha256() == expected.hash("expectedInstanceSha256"), "renderer-instance")
            nativeGuard(it.requirePushConfiguration().sha256() == expected.hash("expectedConfigurationSha256"),
                "bindings-and-choices")
        }
    }

    fun readRenderer(expected: NativePushExpectations): NativeRenderer {
        fun observation(command: String, kind: NativeObservation): String =
            instrumentation.uiAutomation.executeShellCommand(command).use { descriptor ->
                readNativeObservation(ParcelFileDescriptor.AutoCloseInputStream(descriptor), kind, diagnostics)
            }
        val renderer = readNativeSelections(system = {
            val user = observation("am get-current-user", NativeObservation.CURRENT_USER).trim()
            NativeSystem.parse(user, observation("dumpsys wallpaper", NativeObservation.SYSTEM))
        }, native = { system ->
            val component = system.component.flattenToString()
            val dump = observation("dumpsys activity service $component", NativeObservation.NATIVE)
            system.renderer(dump)
        }, configuration = {
            observation("dumpsys wear_service", NativeObservation.CONFIGURATION)
        }, caller = { authority ->
            diagnostics.caller({ WallpaperManager.getInstance(context).wallpaperInfo?.component }, authority)
        }, diagnostics = diagnostics)
        diagnostics.at(NativePhase.SELECTION_OBSERVATION) {
            nativeGuard(renderer.resourcePackage == expected.required("expectedResourcePackage"), "expected-resource-package")
            nativeGuard(renderer.runtime == expected.required("expectedRuntime"), "expected-runtime")
        }
        return renderer
    }
}

internal enum class NativeObservation { CURRENT_USER, SYSTEM, NATIVE, CONFIGURATION }

/** EOF-bounded observations own their streams even on partial reads, overflow or close failure. */
internal fun readNativeObservation(input: InputStream, kind: NativeObservation,
    diagnostics: NativeDiagnostics): String = input.use {
    val output = ByteArrayOutputStream()
    var complete = false
    try {
        val buffer = ByteArray(8192)
        while (output.size() <= 2 * 1024 * 1024) {
            val count = it.read(buffer, 0, minOf(buffer.size, 2 * 1024 * 1024 + 1 - output.size()))
            if (count < 0) { complete = true; break }
            output.write(buffer, 0, count)
        }
        nativeGuard(complete, "bounded-complete-observation")
        output.toString(Charsets.UTF_8.name())
    } catch (failure: Throwable) {
        diagnostics.failure(failure)
        throw failure
    } finally {
        diagnostics.observation(kind, output.toByteArray(), complete)
    }
}

/** Exact section boundaries and unique fields: no cache/history search or duplicate reduction. */
private class NativeRecord(dump: String) {
    val lines = dump.lineSequence().map { it.trim() }.toList()
    fun one(prefix: String) = lines.filter { it.startsWith(prefix) }.singleOrNull()?.removePrefix(prefix)
        ?: throw NativePending("unique-native-field")
    fun section(start: String, end: String): NativeRecord {
        nativeGuard(lines.count { it == start } == 1 && lines.count { it == end } == 1, "unique-native-section")
        val first = lines.indexOf(start)
        val last = lines.indexOf(end)
        nativeGuard(first < last, "ordered-native-section")
        return NativeRecord(lines.subList(first + 1, last).joinToString("\n"))
    }
    fun after(start: String): NativeRecord {
        requireLine(start)
        return NativeRecord(lines.drop(lines.indexOf(start) + 1).joinToString("\n"))
    }
    fun requireLine(value: String) {
        val matches = if ('=' in value) one(value.substringBefore('=') + "=") == value.substringAfter('=')
            else lines.count { it == value } == 1
        nativeGuard(matches, "unique-native-state")
    }
}

private fun nativeComponent(value: String): ComponentName {
    nativeGuard(value.matches(Regex("[A-Za-z][A-Za-z0-9_.]*/[A-Za-z_.$][A-Za-z0-9_.$]*")), "component-record")
    return ComponentName.unflattenFromString(value) ?: throw NativePending("component-record")
}

/** The outer wallpaper Engine owns these fields; the later AndroidX registry does not. */
private data class NativeEngineScope(val component: ComponentName, val user: Int, val display: Int,
    val identity: List<String>) {
    companion object {
        fun parse(dump: String): NativeEngineScope {
            val lines = dump.lineSequence().filter { it.isNotBlank() }.toList()
            val text = lines.map { it.trim() }
            fun index(prefix: String) = text.indices.filter { text[it].startsWith(prefix) }.singleOrNull()
                ?: throw NativePending("native-owner-scope")
            fun indent(index: Int) = lines[index].indexOfFirst { !it.isWhitespace() }
            val serviceIndex = index("SERVICE ")
            val clientIndex = index("Client:")
            val stateIndex = index("State of wallpaper ")
            val engineIndex = index("Engine ")
            val managerIndex = index("InteractiveInstanceManager instances:")
            val engineIndent = indent(engineIndex)
            // Only measured framework continuations may cross the Engine's indentation boundary.
            val continuations = mutableSetOf<Int>()
            val layoutFields = listOf("fl=", "pfl=", "bhv=", "frameRateBoostOnTouch=", "dvrrWindowFrameRateHint=")
            for (line in engineIndex + 1 until managerIndex) {
                if (indent(line) == engineIndent - 1 && text[line].matches(Regex("mIsScreenTurningOn=(true|false)")) &&
                    text[line - 1] == "mVisible=true mReportedVisible=true" && indent(line - 1) == engineIndent + 2) {
                    continuations += line
                }
                if (indent(line) == engineIndent - 2 && text[line].startsWith("ClientWindowFrames{frame=") &&
                    text[line].endsWith('}') && text[line - 1] == "mWinFrames=" && indent(line - 1) == engineIndent + 2) {
                    continuations += line
                }
                if (indent(line) == engineIndent + 2 && text[line].startsWith("mLayout={") && !text[line].endsWith('}') &&
                    layoutFields.indices.all { offset ->
                        val next = line + offset + 1
                        next < managerIndex && indent(next) == engineIndent && text[next].startsWith(layoutFields[offset]) &&
                            text[next].endsWith('}') == (offset == layoutFields.lastIndex)
                    }) {
                    continuations.addAll(line + 1..line + layoutFields.size)
                }
            }
            fun end(index: Int) = (index + 1 until lines.size).firstOrNull {
                indent(it) <= indent(index) && it !in continuations
            } ?: lines.size
            fun child(parent: Int, child: Int) {
                nativeGuard(child in (parent + 1 until end(parent)) && indent(child) == indent(parent) + 2,
                    "native-owner-scope")
            }
            nativeGuard(indent(serviceIndex) == 0 && text[clientIndex] == "Client:" &&
                text[managerIndex] == "InteractiveInstanceManager instances:", "native-owner-scope")
            child(serviceIndex, clientIndex)
            child(clientIndex, stateIndex)
            child(stateIndex, engineIndex)
            child(clientIndex, managerIndex)
            nativeGuard(end(engineIndex) == managerIndex, "native-owner-scope")
            val engineLines = engineIndex + 1 until managerIndex
            nativeGuard(engineLines.all { indent(it) >= engineIndent + 2 || it in continuations }, "native-owner-scope")
            val header = Regex("([^ ]+) [a-f0-9]+ pid=[0-9]+ user=([0-9]+)")
                .matchEntire(text[serviceIndex].removePrefix("SERVICE ")) ?: throw NativePending("native-service-scope")
            val component = nativeComponent(header.groupValues[1])
            val user = header.groupValues[2].toIntOrNull() ?: throw NativePending("native-user-component")
            nativeGuard(component.packageName == RUNTIME_PACKAGE && component.className in setOf(
                "$RUNTIME_PACKAGE.DeclarativeWatchFaceRuntime0", "$RUNTIME_PACKAGE.DeclarativeWatchFaceRuntime1"),
                "native-user-component")
            val state = text[stateIndex].removePrefix("State of wallpaper ")
            nativeGuard(state.matches(Regex("${Regex.escape(component.className)}@[a-f0-9]+:")), "native-wallpaper-scope")
            val engine = text[engineIndex].removePrefix("Engine ")
            nativeGuard(engine.matches(Regex("[^ ]+@[a-f0-9]+:")), "single-native-engine")
            val body = NativeRecord(engineLines
                .filter { indent(it) == engineIndent + 2 }.joinToString("\n") { text[it] })
            body.requireLine("mInitializing=false mDestroyed=false")
            body.requireLine("mVisible=true mReportedVisible=true")
            val nativeDisplay = body.one("mDisplay=Display id ")
            val display = Regex("([0-9]+): DisplayInfo\\{.*").matchEntire(nativeDisplay)?.groupValues?.get(1)?.toIntOrNull()
                ?: throw NativePending("native-display")
            val displayInfo = Regex("displayId ([0-9]+),").findAll(nativeDisplay).toList().singleOrNull()
            nativeGuard(displayInfo?.groupValues?.get(1)?.toIntOrNull() == display, "native-display")
            return NativeEngineScope(component, user, display, listOf(header.value, state, engine))
        }
    }
}

/** Current-user System authority, including the live display's matching connection. */
internal data class NativeSystem(val user: Int, val display: Int, val component: ComponentName,
    val userRecord: String, val connection: String, val engine: String, val service: String, val token: String) {
    fun renderer(dump: String): NativeRenderer {
        val owner = NativeEngineScope.parse(dump)
        nativeGuard(owner.component == component && owner.user == user, "native-user-component")
        nativeGuard(owner.display == display, "native-display")
        return NativeRenderer.parse(dump).copy(runtime = component.className.substringAfterLast('.'),
            nativeScope = owner.identity)
    }

    companion object {
        fun parse(currentUser: String, dump: String): NativeSystem {
            nativeGuard(currentUser.matches(Regex("[0-9]+")), "current-user")
            val user = currentUser.toIntOrNull() ?: throw NativePending("current-user")
            val record = NativeRecord(dump).section("System wallpaper state:", "Lock wallpaper state:")
            record.requireLine("Display state:")
            val userRecord = record.one("User ")
            val identity = Regex("([0-9]+): id=[0-9]+: mWhich=([13]): mSystemWasBoth=(true|false): mBindSource=SET_LIVE")
                .matchEntire(userRecord) ?: throw NativePending("system-wallpaper-identity")
            nativeGuard(identity.groupValues[1].toIntOrNull() == user && record.one("displayId=") == "0" &&
                record.one("mDisplayId=") == "0", "system-user-display")
            fun readComponent(prefix: String): ComponentName {
                val value = record.one(prefix)
                val match = Regex("ComponentInfo\\{([^}]+)\\}").matchEntire(value)
                    ?: throw NativePending("system-component")
                return nativeComponent(match.groupValues[1])
            }
            val component = readComponent("mWallpaperComponent=")
            nativeGuard(component.packageName == RUNTIME_PACKAGE && component.className in setOf(
                "$RUNTIME_PACKAGE.DeclarativeWatchFaceRuntime0", "$RUNTIME_PACKAGE.DeclarativeWatchFaceRuntime1"),
                "system-runtime")
            nativeGuard(readComponent("mInfo.component=") == component, "system-connection-component")
            val connection = record.one("Wallpaper connection ")
            val engine = record.one("mEngine=")
            val service = record.one("mService=")
            val token = record.one("mToken=")
            nativeGuard(connection.matches(Regex("com\\.android\\.server\\.wallpaper\\.WallpaperManagerService[$]WallpaperConnection@[a-f0-9]+:")) &&
                engine.matches(Regex("android[.]service[.]wallpaper[.]IWallpaperEngine(?:[$][A-Za-z]+)*@[a-f0-9]+")) &&
                service.matches(Regex("android[.]service[.]wallpaper[.]IWallpaperService(?:[$][A-Za-z]+)*@[a-f0-9]+")) &&
                token.matches(Regex("android[.]os[.]Binder@[a-f0-9]+")),
                "live-system-connection")
            return NativeSystem(user, 0, component, userRecord, connection, engine, service, token)
        }
    }
}

/** Favorite and native instance are independently observed opaque identities, never converted. */
internal fun readNativeSelections(system: () -> NativeSystem, native: (NativeSystem) -> NativeRenderer,
    configuration: () -> String, caller: (ComponentName) -> Unit = {},
    diagnostics: NativeDiagnostics = NativeDiagnostics()): NativeRenderer {
    val beforeSystem = diagnostics.at(NativePhase.SYSTEM_BEFORE, system)
    caller(beforeSystem.component)
    val before = diagnostics.at(NativePhase.NATIVE_BEFORE) { native(beforeSystem) }
    val selected = diagnostics.at(NativePhase.ACTIVE_CONFIGURATION) {
        readActiveSelections(configuration(), beforeSystem, before, diagnostics)
    }
    val after = diagnostics.at(NativePhase.NATIVE_AFTER) { native(beforeSystem) }
    val afterSystem = diagnostics.at(NativePhase.SYSTEM_AFTER, system)
    diagnostics.at(NativePhase.SELECTION_MATCH) {
        val matches = beforeSystem == afterSystem && before.resourcePackage == after.resourcePackage &&
            before.instance == after.instance && before.userStyle == after.userStyle && before.enabled == after.enabled &&
            before.runtime == after.runtime && before.nativeScope == after.nativeScope
        diagnostics.semanticMatch(matches)
        nativeGuard(matches, "selection-instance-changed")
    }
    return after.copy(selections = selected)
}

private fun readActiveSelections(dump: String, system: NativeSystem, renderer: NativeRenderer,
    diagnostics: NativeDiagnostics): NativeSelections {
    val record = NativeRecord(dump)
    val complications = record.section("Wear Service API: complications", "Wear Service API: watch_faces")
    val sendingController = complications.section("ComplicationManager", "DeviceLockStateReceiver")
        .section("ComplicationDataSendingController", "ComplicationUpdateController")
    val controller = sendingController.section("ComplicationsConfigController",
        "PreviewComplicationDataCache=${sendingController.one("PreviewComplicationDataCache=")}")
    val favorite = Regex("WatchFaceFavoriteId\\{mWatchFaceId=(WatchFaceId\\[([^,]+),null\\]), mFavoriteId=([^, ]+), mType=AndroidxWatchFace\\}")
        .matchEntire(controller.one("activeWatchFaceFavoriteId=")) ?: throw NativePending("active-favorite")
    val family = favorite.groupValues[1]
    val resource = favorite.groupValues[2]
    val favoriteId = favorite.groupValues[3]
    val watchFaces = record.section("Wear Service API: watch_faces", "Watch Face Favorite Repository (DB)")
    val facade = watchFaces.section("Active Watch Face Facade:", "Current Active Engine:")
    for (value in listOf("threadState=IDLE", "isFallbackWatchFace=false", "runningFlow=ANDROIDX")) facade.requireLine(value)
    nativeGuard(facade.one("activeWatchFaceComponent=") == family && facade.one("favoriteId=") == favoriteId,
        "active-facade-favorite")
    val engine = watchFaces.after("Current Active Engine:")
    for (value in listOf("Engine Type=AndroidX", "Resource Only WatchFace=true", "Runtime Package=$RUNTIME_PACKAGE",
        "WearServices WatchFace Client=Binder Alive")) engine.requireLine(value)
    nativeGuard(engine.one("Current Active Watch Face=") == "favId: $favoriteId, family: $family" &&
        engine.one("Current Wallpaper Component=") == "ComponentInfo{${system.component.flattenToString()}}" &&
        resource == renderer.resourcePackage, "active-engine-native-chain")
    val configs = controller.after("activeConfigs: size=${controller.one("activeConfigs: size=")}")
    val declared = controller.one("activeConfigs: size=").toIntOrNull() ?: throw NativePending("declared-config-size")
    val rows = configs.lines.filter { it.isNotEmpty() }.map { line ->
        Regex("id=([0-9]+) slot=([0-9]+) type=([0-9]+) configActionPending=(true|false) provider=(null|ComponentInfo\\{([^}]+)\\}) isEnabled=(true|false)")
            .matchEntire(line) ?: throw NativePending("complete-active-config-row")
    }
    val slots = rows.map { it.groupValues[2].toIntOrNull() ?: throw NativePending("config-slot") }
    val rowIds = rows.map { it.value.substringBefore(' ') }
    val complete = declared == rows.size && rows.size == renderer.enabled.size &&
        slots.toSet() == renderer.enabled.keys && slots.toSet().size == slots.size && rowIds.toSet().size == rows.size
    diagnostics.inventory(declared, rows.size, slots.toSet().size, complete)
    nativeGuard(complete, "complete-selection-records")
    val types = mutableMapOf<Int, Int>()
    val providers = mutableMapOf<Int, String?>()
    rows.forEachIndexed { index, row ->
        val slot = slots[index]
        nativeGuard(row.groupValues[4] == "false" && (row.groupValues[7] == "true") == renderer.enabled[slot],
            "settled-enabled-config")
        types[slot] = row.groupValues[3].toIntOrNull() ?: throw NativePending("configured-type")
        providers[slot] = if (row.groupValues[5] == "null") null else row.groupValues[6].also { nativeComponent(it) }
    }
    // Types describe configuration, not delivered/overridden data or requester IDs.
    return NativeSelections(resource, renderer.instance, providers, types, slots.zip(rows.map { it.groupValues[1] }).toMap())
}

/** Authoritative selections must identify the resource package, instance and every slot. */
internal data class NativeSelections(
    val resourcePackage: String,
    val instance: String,
    // An explicit null means no selected provider; a missing key means unavailable evidence.
    val providers: Map<Int, String?>,
    val configuredTypes: Map<Int, Int> = emptyMap(),
    // Raw controller row IDs remain separate from slots and from historical configuration fingerprints.
    val rowIds: Map<Int, String> = emptyMap(),
)

internal data class NativeRenderer(
    val resourcePackage: String,
    val instance: String,
    val userStyle: String,
    val enabled: Map<Int, Boolean>,
    val deliveredSources: Map<Int, String?>,
    val selections: NativeSelections? = null,
    // Kept private by callers: native data may include sensitive producer content.
    val effectiveData: Map<Int, String> = emptyMap(),
    val runtime: String = "",
    val nativeScope: List<String> = emptyList(),
) {
    val deliveryProvenance: String
        get() = deliveredSources.toSortedMap().entries.joinToString("\n") { (id, source) ->
            "$id|${source ?: "<unavailable>"}"
        }

    val configuration: String
        get() {
            val selected = selections ?: throw NativePending("selected-provider-records-unavailable")
            nativeGuard(selected.resourcePackage == resourcePackage && selected.instance == instance,
                "selection-instance-mapping")
            nativeGuard(selected.providers.keys == enabled.keys, "complete-selection-records")
            val lower = listOf("Today", "Week", "Ring3", "RingSplit", "StripSplit")
            lower.forEachIndexed { index, service ->
                nativeGuard(selected.providers[index + 11] ==
                    "$HOST_PACKAGE/app.wardpulse.wear.complication.${service}ComplicationDataSourceService", "lower-binding")
            }
            return (listOf(userStyle) + enabled.toSortedMap().map { (id, active) ->
                "$id|enabled=$active|${selected.providers[id] ?: "<none>"}"
            }).joinToString("\n")
        }

    fun requirePushConfiguration(): String {
        nativeGuard(resourcePackage == CANDIDATE_PACKAGE, "push-instance-configuration-unavailable")
        return configuration
    }

    fun requireRetainedFrom(before: NativeRenderer) {
        nativeGuard(resourcePackage == before.resourcePackage && instance == before.instance &&
            requirePushConfiguration() == before.requirePushConfiguration(), "retained-push-configuration")
    }

    companion object {
        fun parse(dump: String): NativeRenderer {
            NativeEngineScope.parse(dump)
            val record = NativeRecord(dump)
            nativeGuard(record.lines.lastOrNull { it.isNotEmpty() } == "HeadlessWatchFace instances:", "no-headless-instances")
            val manager = record.section("InteractiveInstanceManager instances:", "EditorService:")
            val registered = manager.section("InteractiveInstanceManager:", "WatchFaceEngine:")
            val registry = manager.after("WatchFaceEngine:")
            val lines = registry.lines
            fun single(prefix: String) = lines.filter { it.startsWith(prefix) }.singleOrNull()
                ?.removePrefix(prefix) ?: throw NativePending("native-record-unavailable")
            val resourcePackage = single("Resource only package name ")
            nativeGuard(resourcePackage in setOf(CANDIDATE_PACKAGE, "app.wardpulse.watchface"), "renderer-package")
            nativeGuard(registry.one("WatchFaceImpl ") == "(ComponentInfo{$resourcePackage/null}):", "native-implementation-package")
            val instance = single("interactiveInstanceId=")
            nativeGuard(instance == single("watchFaceInstanceId=") && instance == registered.one("impl.instanceId=") &&
                instance.isNotBlank(), "instance-record")
            for (value in listOf("destroyed=false", "surfaceDestroyed=false",
                "editorObscuresWatchFace=false", "isVisible=true", "isAmbient=false", "isHeadless=false",
                "asyncWatchFaceConstructionPending=false", "overriddenComplications=null")) {
                registry.requireLine(value)
            }
            val style = single("currentUserStyleRepository.userStyle=")
            nativeGuard(style.isNotBlank(), "native-style")
            val scopedDump = registry.after("ComplicationSlotsManager:").lines.joinToString("\n")
            val slots = Regex("(?m)^\\s*ComplicationSlot (\\d+):").findAll(scopedDump).toList()
            nativeGuard(slots.map { it.groupValues[1].toIntOrNull() }.toSet() == (11..18).toSet() && slots.size == 8,
                "native-slot-inventory")
            val enabled = mutableMapOf<Int, Boolean>()
            val deliveredSources = mutableMapOf<Int, String?>()
            val effectiveData = mutableMapOf<Int, String>()
            slots.forEachIndexed { index, match ->
                val id = match.groupValues[1].toInt()
                val block = scopedDump.substring(match.range.last + 1, slots.getOrNull(index + 1)?.range?.first ?: scopedDump.length)
                val data = block.lineSequence().map { it.trim() }.filter { it.startsWith("data=") }.singleOrNull()
                    ?: throw NativePending("effective-data-unavailable")
                effectiveData[id] = data.removePrefix("data=")
                val sources = Regex("dataSource=ComponentInfo\\{([^}]+)\\}").findAll(data).toList()
                nativeGuard(sources.size <= 1, "ambiguous-delivery-provenance")
                // Cached provenance is diagnostic only, even when a source is present.
                deliveredSources[id] = if (data.startsWith("data=NoDataComplicationData") ||
                    data.startsWith("data=EmptyComplicationData")) null else sources.singleOrNull()?.groupValues?.get(1)
                val active = block.lineSequence().map { it.trim() }.filter { it.startsWith("enabled=") }.singleOrNull()
                    ?: throw NativePending("unique-enabled-record")
                nativeGuard(active == "enabled=true" || active == "enabled=false", "enabled-record")
                enabled[id] = active == "enabled=true"
            }
            // Selections come from scoped controller activeConfigs, never cached native delivery/defaults.
            return NativeRenderer(resourcePackage, instance, style, enabled, deliveredSources, effectiveData = effectiveData)
        }
    }
}
