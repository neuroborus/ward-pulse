package app.wardpulse.wear.nativeintegration

import android.app.Instrumentation
import android.content.Context
import android.content.pm.PackageInfo
import android.content.pm.PackageManager
import android.os.Build
import android.os.ParcelFileDescriptor
import android.os.Process
import java.io.File
import java.io.InputStream
import java.util.concurrent.TimeoutException
import kotlinx.coroutines.TimeoutCancellationException
import org.json.JSONArray
import org.json.JSONObject

internal enum class NativeReadOutcome(val value: String) {
    NOT_INVOKED("not-invoked"), UNSUPPORTED("unsupported"), EMPTY("null/empty"),
    INACCESSIBLE("denied/inaccessible"), TIMEOUT("timeout"),
    UNRESOLVED("ambiguous/domain-unresolved"), ACQUIRED("successful-acquisition"),
}

internal class NativeReadEmpty : IllegalStateException()

internal enum class NativeReadSubstage {
    OPERATION, INVOCATION_RECORDING, RESULT_RECORDING,
    RUNTIME_DISCOVERY, RUNTIME_BYTES, RUNTIME_ARCHIVE, RUNTIME_IDENTITY,
}

/** A stack-free diagnostic tag preserves the original throwable and its outcome classification. */
private class NativeReadFailureSite(val substage: NativeReadSubstage) : Throwable(null, null, false, false)

internal fun <T> nativeReadAt(substage: NativeReadSubstage, action: () -> T): T = try {
    action()
} catch (failure: Throwable) {
    if (failure.suppressed.none { it is NativeReadFailureSite }) failure.addSuppressed(NativeReadFailureSite(substage))
    throw failure
}

internal fun nativeReadExceptionType(name: String): String = if (name.length in 1..192 &&
    name.matches(Regex("[A-Za-z_$][A-Za-z0-9_$]*(?:\\.[A-Za-z_$][A-Za-z0-9_$]*)*"))) name else "Unknown"

private fun recordNativeReadFailure(operation: JSONObject, failure: Throwable, fallback: NativeReadSubstage) {
    // Recording and cleanup failures cannot replace an already recorded failing substage/type.
    if (operation.has("failureType")) return
    val site = failure.suppressed.filterIsInstance<NativeReadFailureSite>().firstOrNull()?.substage ?: fallback
    operation.put("failureType", nativeReadExceptionType(failure.javaClass.name))
        .put("failureSubstage", site.name.lowercase())
}

internal fun nativeReadFailure(failure: Throwable) = when (failure) {
    is NativeReadEmpty -> NativeReadOutcome.EMPTY
    is SecurityException, is java.io.IOException, is android.os.RemoteException -> NativeReadOutcome.INACCESSIBLE
    is UnsupportedOperationException, is LinkageError -> NativeReadOutcome.UNSUPPORTED
    is TimeoutCancellationException, is TimeoutException -> NativeReadOutcome.TIMEOUT
    is NativePending -> when (failure.identity) {
        "client-existing-instance-unavailable" -> NativeReadOutcome.EMPTY
        "client-service-access", "client-permission-denied" -> NativeReadOutcome.INACCESSIBLE
        else -> NativeReadOutcome.UNRESOLVED
    }
    else -> NativeReadOutcome.UNRESOLVED
}

internal fun nativeReadOperation(target: String, domain: String) = JSONObject()
    .put("invoked", false).put("target", target).put("returnedDomain", domain)
    .put("outcome", NativeReadOutcome.NOT_INVOKED.value)

/** Persist invocation before a call; failure evidence never includes remote exception text. */
internal fun <T> nativeClientOperation(receipt: JSONObject, persist: () -> Unit,
    name: String, target: String, domain: String, action: () -> T): T {
    val operations = receipt.optJSONObject("operations") ?: JSONObject().also { receipt.put("operations", it) }
    val operation = operations.optJSONObject(name) ?: nativeReadOperation(target, domain).also { operations.put(name, it) }
    operation.put("invoked", true).put("target", target).put("returnedDomain", domain)
        .put("outcome", NativeReadOutcome.UNRESOLVED.value)
    try { persist() } catch (failure: Throwable) {
        operation.put("invoked", false).put("outcome", NativeReadOutcome.NOT_INVOKED.value)
        recordNativeReadFailure(operation, failure, NativeReadSubstage.INVOCATION_RECORDING)
        throw failure
    }
    val result = try {
        action()
    } catch (failure: Throwable) {
        operation.put("outcome", nativeReadFailure(failure).value)
        recordNativeReadFailure(operation, failure, NativeReadSubstage.OPERATION)
        try { persist() } catch (recording: Throwable) { failure.addSuppressed(recording) }
        throw failure
    }
    operation.put("outcome", NativeReadOutcome.ACQUIRED.value)
    try { persist() } catch (failure: Throwable) {
        recordNativeReadFailure(operation, failure, NativeReadSubstage.RESULT_RECORDING)
        throw failure // Recording failure cannot turn a successful API return into a denial.
    }
    return result
}

internal const val INSTALLED_RUNTIME_PATH_END = "NATIVE_RUNTIME_PATHS_COMPLETE"
// As in the historical Push locator, UiAutomation must receive one whitespace-free -c script.
internal const val INSTALLED_RUNTIME_PATH_COMMAND =
    "/system/bin/sh -c /system/bin/pm\${IFS}path\${IFS}$RUNTIME_PACKAGE&&echo\${IFS}$INSTALLED_RUNTIME_PATH_END"

/** Accept a complete single-APK enumeration only; no metadata is inferred from the path. */
internal fun readInstalledRuntimePath(input: InputStream): File = input.use {
    val bytes = it.readNBytes(4097)
    nativeGuard(bytes.size <= 4096, "bounded-runtime-paths")
    val match = Regex("package:(/(?:[A-Za-z0-9_+=.@~-]+/)*[A-Za-z0-9_+=.@~-]+\\.apk)\n$INSTALLED_RUNTIME_PATH_END\n")
        .matchEntire(bytes.toString(Charsets.US_ASCII))
        ?: throw NativePending("single-complete-runtime-path")
    val path = match.groupValues[1]
    nativeGuard(path.split('/').none { part -> part == "." || part == ".." }, "runtime-path-components")
    File(path)
}

/** Only observed archive and application metadata; sourceDir is neither required nor repaired. */
internal data class NativeRuntimeArchive(val archive: NativeArchive, val applicationPackage: String?) {
    companion object {
        fun fromInfo(info: PackageInfo) = NativeRuntimeArchive(NativeArchive.fromInfo(info), info.applicationInfo?.packageName)
    }
}

internal fun readNativeRuntimePackage(context: Context, locate: () -> File, expected: NativePushExpectations,
    archive: (File) -> NativeRuntimeArchive? = { file ->
        context.packageManager.getPackageArchiveInfo(file.path, PackageManager.GET_SIGNING_CERTIFICATES)
            ?.let { NativeRuntimeArchive.fromInfo(it) }
    }, open: (File) -> InputStream = { it.inputStream() }): NativePackage {
    val file = nativeReadAt(NativeReadSubstage.RUNTIME_DISCOVERY, locate)
    val apk = nativeReadAt(NativeReadSubstage.RUNTIME_BYTES) { open(file).sha256() }
    val observed = nativeReadAt(NativeReadSubstage.RUNTIME_ARCHIVE) {
        archive(file) ?: throw NativePending("runtime-archive-unavailable")
    }
    val signer = nativeReadAt(NativeReadSubstage.RUNTIME_IDENTITY) {
        nativeGuard(observed.applicationPackage == RUNTIME_PACKAGE, "runtime-application-metadata")
        observed.archive.requireIdentity(RUNTIME_PACKAGE)
    }
    nativeReadAt(NativeReadSubstage.RUNTIME_BYTES) {
        nativeGuard(open(file).sha256() == apk, "runtime-file-changed")
    }
    nativeReadAt(NativeReadSubstage.RUNTIME_DISCOVERY) {
        nativeGuard(locate() == file, "runtime-path-changed")
    }
    return nativeReadAt(NativeReadSubstage.RUNTIME_IDENTITY) {
        nativeGuard(apk == expected.hash("expectedRuntimeApkSha256") &&
            signer == expected.hash("expectedRuntimeSignerSha256"), "read-runtime-apk")
        NativePackage(observed.archive.code, apk, signer)
    }
}

/** Current caller authority, deliberately independent of update journals and requester mappings. */
internal fun requireNativeReadCaller(uid: Int, applicationUid: Int, packages: Set<String>,
    host: NativePackage, expected: NativePushExpectations) {
    nativeGuard(uid == applicationUid && uid.toString() == expected.required("expectedCallerUid") &&
        packages == setOf(HOST_PACKAGE), "read-caller-uid-package")
    nativeGuard(host.code.toString() == expected.required("expectedHostVersionCode") &&
        host.apk == expected.hash("expectedHostApkSha256") &&
        host.signer == expected.hash("expectedHostSignerSha256"), "read-current-target")
}

internal class NativeReadAdmission(private val instrumentation: Instrumentation,
    private val expected: NativePushExpectations) {
    private val context = instrumentation.targetContext
    private val device = NativePushDevice(instrumentation)

    fun admit(method: String, testClass: String, optIn: String): JSONObject {
        val avd = device.shell("getprop ro.boot.qemu.avd_name").ifBlank {
            device.shell("getprop ro.kernel.qemu.avd_name")
        }
        // Do not call NativePushDevice.admit: its historical SDK update-method resolution is unchanged.
        expected.admit(method, instrumentation.javaClass.name, avd, device.shell("getprop ro.kernel.qemu"),
            context.packageManager.hasSystemFeature(PackageManager.FEATURE_WATCH), testClass, optIn)
        nativeGuard(Build.VERSION.SDK_INT == 36 && Build.FINGERPRINT.sha256() ==
            expected.hash("expectedFingerprintSha256"), "read-system-image")
        val dimensions = if (avd.contains("square")) "360x360" else "384x384"
        nativeGuard(device.shell("wm size") == "Physical size: $dimensions", "read-canonical-display")
        nativeGuard(context.packageName == HOST_PACKAGE && context.applicationContext.javaClass.name ==
            "android.app.Application", "read-target-context-application")
        return currentIdentity()
    }

    fun currentIdentity(): JSONObject {
        val host = NativePackage.read(context, HOST_PACKAGE)
        val uid = Process.myUid()
        val packages = context.packageManager.getPackagesForUid(uid)?.toSet().orEmpty()
        requireNativeReadCaller(uid, context.applicationInfo.uid, packages, host, expected)
        return JSONObject().put("callerUid", uid).put("callerPackage", context.packageName)
            .put("callerPackages", JSONArray(packages.sorted())).put("target", host.json())
    }

    fun resourceIdentity(resourcePackage: String,
        observe: (String, () -> NativePackage) -> NativePackage = { _, read -> read() }): JSONObject {
        nativeGuard(resourcePackage == expected.required("expectedResourcePackage"), "read-resource-package")
        val resource = observe("ResourcePackage") {
            NativePackage.read(context, resourcePackage).also {
                nativeGuard(it.apk == expected.hash("expectedResourceApkSha256") &&
                    it.signer == expected.hash("expectedResourceSignerSha256"), "read-resource-apk")
            }
        }
        val runtime = observe("RuntimePackage") {
            readNativeRuntimePackage(context, locate = {
                // Existing UiAutomation only discovers paths; bytes and parsing retain the target UID/context.
                ParcelFileDescriptor.AutoCloseInputStream(instrumentation.uiAutomation.executeShellCommand(
                    INSTALLED_RUNTIME_PATH_COMMAND,
                )).let { readInstalledRuntimePath(it) }
            }, expected = expected)
        }
        return JSONObject().put("resourcePackage", resourcePackage).put("resource", resource.json())
            .put("runtimePackage", RUNTIME_PACKAGE).put("runtime", runtime.json())
    }
}

internal data class NativeReadFace(val system: NativeSystem, val renderer: NativeRenderer,
    val configurationSha256: String?) {
    fun json() = JSONObject().put("systemScopeSha256", system.toString().sha256())
        .put("runtime", renderer.runtime).put("nativeScope", JSONArray(renderer.nativeScope))
        .put("resourcePackage", renderer.resourcePackage).put("instance", renderer.instance)
        .put("userStyleSha256", renderer.userStyle.sha256())
        .put("nativeSlots", JSONObject(renderer.enabled.mapKeys { it.key.toString() }))
        .put("configurationDumpSha256", configurationSha256 ?: JSONObject.NULL)

    fun sameScope(other: NativeReadFace): Boolean = system == other.system &&
        renderer.resourcePackage == other.renderer.resourcePackage && renderer.instance == other.renderer.instance &&
        renderer.runtime == other.renderer.runtime && renderer.nativeScope == other.renderer.nativeScope &&
        renderer.userStyle == other.renderer.userStyle && renderer.enabled == other.renderer.enabled &&
        configurationSha256 != null && configurationSha256 == other.configurationSha256
}

/** Configuration is independent diagnostic evidence; its absence must not hide client metadata. */
internal fun readNativeClientFace(device: NativePushDevice, expected: NativePushExpectations,
    receipt: JSONObject, persist: () -> Unit, name: String): NativeReadFace {
    fun system() = NativeSystem.parse(device.shell("am get-current-user"), device.shell("dumpsys wallpaper"))
    val beforeSystem = system()
    val before = beforeSystem.renderer(device.shell("dumpsys activity service ${beforeSystem.component.flattenToString()}"))
    var configuration: String? = null
    try {
        configuration = nativeClientOperation(receipt, persist, "${name}Configuration", "wear_service",
            "raw configuration dump SHA-256; no slot-domain join") {
            device.shell("dumpsys wear_service").also {
                if (it.isBlank()) throw NativeReadEmpty()
                nativeGuard(it.contains("Wear Service API: complications") && it.contains("Wear Service API: watch_faces"),
                    "read-configuration-unresolved")
            }.sha256()
        }
    } catch (_: Exception) {
        // Outcome is retained independently. No synthetic configuration or requester mapping is supplied.
    }
    val after = beforeSystem.renderer(device.shell("dumpsys activity service ${beforeSystem.component.flattenToString()}"))
    nativeGuard(beforeSystem == system() && before.resourcePackage == after.resourcePackage &&
        before.instance == after.instance && before.runtime == after.runtime && before.nativeScope == after.nativeScope &&
        before.userStyle == after.userStyle && before.enabled == after.enabled, "read-face-changed")
    nativeGuard(after.runtime == expected.required("expectedRuntime") &&
        after.resourcePackage == expected.required("expectedResourcePackage") &&
        after.instance.sha256() == expected.hash("expectedInstanceSha256"), "read-current-instance")
    return NativeReadFace(beforeSystem, after, configuration)
}
