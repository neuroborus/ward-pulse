package app.wardpulse.wear.nativeintegration

import android.app.Instrumentation
import android.content.pm.PackageManager
import android.os.Build
import android.os.Process
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
        throw failure
    }
    val result = try {
        action()
    } catch (failure: Throwable) {
        operation.put("outcome", nativeReadFailure(failure).value)
        try { persist() } catch (recording: Throwable) { failure.addSuppressed(recording) }
        throw failure
    }
    operation.put("outcome", NativeReadOutcome.ACQUIRED.value)
    persist() // Recording failure cannot turn a successful API return into a denial.
    return result
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
            NativePackage.read(context, RUNTIME_PACKAGE).also {
                nativeGuard(it.apk == expected.hash("expectedRuntimeApkSha256") &&
                    it.signer == expected.hash("expectedRuntimeSignerSha256"), "read-runtime-apk")
            }
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
