package app.wardpulse.wear.nativeintegration

import android.app.Instrumentation
import android.app.WallpaperManager
import android.content.ComponentName
import android.content.Context
import android.content.ContextWrapper
import android.content.Intent
import android.content.ServiceConnection
import android.content.pm.PackageInfo
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.os.ParcelFileDescriptor
import androidx.wear.watchface.complications.ComplicationDataSourceInfoRetriever
import androidx.wear.watchfacepush.WatchFacePushManager
import java.io.File
import java.io.InputStream
import java.security.MessageDigest
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import org.json.JSONObject

internal const val HOST_PACKAGE = "app.wardpulse"
internal const val CANDIDATE_PACKAGE = "app.wardpulse.watchfacepush.main"
internal const val UPDATE_CLASS = "app.wardpulse.wear.nativeintegration.NativePushUpdateTest"
internal const val RUNTIME_PACKAGE = "com.google.wear.watchface.runtime"

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

internal data class NativePackage(val code: Long, val apk: String, val signer: String) {
    fun json() = JSONObject().put("code", code).put("apk", apk).put("signer", signer)

    companion object {
        fun read(context: Context, name: String): NativePackage {
            val info = context.packageManager.getPackageInfo(name, PackageManager.GET_SIGNING_CERTIFICATES)
            return fromInfo(info)
        }

        fun fromInfo(info: PackageInfo): NativePackage {
            nativeGuard(info.applicationInfo?.splitSourceDirs.isNullOrEmpty(), "single-apk")
            val certificates = info.signingInfo?.apkContentsSigners
            nativeGuard(certificates?.size == 1, "single-signer")
            return NativePackage(
                info.longVersionCode,
                File(checkNotNull(info.applicationInfo).sourceDir).inputStream().sha256(),
                checkNotNull(certificates).single().toByteArray().inputStream().sha256(),
            )
        }
    }
}

/** Read-only shell calls through the instrumentation's existing UiAutomation owner. */
internal class NativePushDevice(private val instrumentation: Instrumentation) {
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
        WatchFacePushManager::class.java.getMethod("updateWatchFace", String::class.java,
            ParcelFileDescriptor::class.java, String::class.java, kotlin.coroutines.Continuation::class.java)
    }

    fun baseline(expected: NativePushExpectations): JSONObject {
        val host = NativePackage.read(context, HOST_PACKAGE)
        nativeGuard(host.code == 4L && host.apk == expected.hash("expectedHostApkSha256") &&
            host.signer == expected.hash("expectedHostSignerSha256"), "original-host")
        val asset = context.assets.open("default_watchface.apk").sha256()
        nativeGuard(asset == expected.hash("expectedAsset3Sha256"), "original-asset-3")
        val installed = NativePackage.read(context, CANDIDATE_PACKAGE)
        nativeGuard(installed.code == 3L && installed.apk == expected.hash("expectedPush3ApkSha256") &&
            installed.signer == expected.hash("expectedPushSignerSha256"), "installed-push-3")
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
        } finally {
            nativeGuard(file.delete(), "baseline-file-cleanup")
        }
        return JSONObject().put("host", host.json()).put("asset", asset)
    }

    fun unchangedHost(before: JSONObject) {
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
        val runtime = expected.required("expectedRuntime")
        nativeGuard(runtime in setOf("DeclarativeWatchFaceRuntime0", "DeclarativeWatchFaceRuntime1"), "runtime")
        val component = ComponentName(RUNTIME_PACKAGE, "$RUNTIME_PACKAGE.$runtime")
        return runBlocking(Dispatchers.IO) {
            readNativeSelections(component, observe = {
                nativeGuard(WallpaperManager.getInstance(context).wallpaperInfo?.component == component,
                    "active-wallpaper")
                NativeRenderer.parse(shell("dumpsys activity service $RUNTIME_PACKAGE/.$runtime"),
                    expected.required("expectedResourcePackage"))
            }, query = { face, slots ->
                SelectionQueryContext(context).use { binding ->
                    // The baseline dependency binds in its constructor, without awaiting a result.
                    // Track the connection before construction so partial failures also unbind.
                    ComplicationDataSourceInfoRetriever(binding).use { retriever ->
                        nativeGuard(binding.bound, "selection-service-unavailable")
                        withTimeout(5_000) {
                            retriever.retrieveComplicationDataSourceInfo(face, slots)?.map { result ->
                                val info = result.info
                                val provider = if (info == null) null else {
                                    val name = info.componentName
                                        ?: throw NativePending("selection-component-unavailable")
                                    name.flattenToString()
                                }
                                NativeSelectionRecord(result.slotId, provider)
                            }
                        }
                    }
                }
            })
        }
    }
}

/** The public selection service is component-scoped; only a sole stable active instance maps it. */
internal suspend fun readNativeSelections(
    component: ComponentName,
    observe: () -> NativeRenderer,
    query: suspend (ComponentName, IntArray) -> List<NativeSelectionRecord>?,
): NativeRenderer {
    val before = observe()
    val slots = before.enabled.keys.sorted().toIntArray()
    val records = query(component, slots) ?: throw NativePending("selected-provider-records-unavailable")
    nativeGuard(records.size == slots.size && records.map { it.slotId }.toSet() == slots.toSet(),
        "complete-selection-records")
    val after = observe()
    nativeGuard(after.resourcePackage == before.resourcePackage && after.instance == before.instance &&
        after.userStyle == before.userStyle && after.enabled == before.enabled, "selection-instance-changed")
    return after.copy(selections = NativeSelections(after.resourcePackage, after.instance,
        records.associate { it.slotId to it.provider }))
}

internal data class NativeSelectionRecord(val slotId: Int, val provider: String?)

/** Owns even a constructor's attempted bind, before a retriever has been returned. */
private class SelectionQueryContext(context: Context) : ContextWrapper(context), AutoCloseable {
    private val connections = linkedSetOf<ServiceConnection>()
    var bound = false
        private set

    override fun bindService(service: Intent, connection: ServiceConnection, flags: Int): Boolean {
        nativeGuard(connections.isEmpty(), "single-selection-binding")
        connections += connection
        return super.bindService(service, connection, flags).also { bound = it }
    }

    override fun unbindService(connection: ServiceConnection) {
        if (connection !in connections) return
        try {
            super.unbindService(connection)
        } catch (_: IllegalArgumentException) {
            // Android reports no registered connection, including a denied/failed bind.
        }
        connections -= connection
    }

    override fun close() {
        connections.toList().forEach { unbindService(it) }
    }
}

/** Authoritative selections must identify the resource package, instance and every slot. */
internal data class NativeSelections(
    val resourcePackage: String,
    val instance: String,
    // An explicit null means no selected provider; a missing key means unavailable evidence.
    val providers: Map<Int, String?>,
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
        fun parse(dump: String, resourcePackage: String): NativeRenderer {
            val lines = dump.lineSequence().map { it.trim() }.toList()
            fun single(prefix: String) = lines.filter { it.startsWith(prefix) }.singleOrNull()
                ?.removePrefix(prefix) ?: throw NativePending("native-record-unavailable")
            nativeGuard(resourcePackage in setOf(CANDIDATE_PACKAGE, "app.wardpulse.watchface") &&
                single("Resource only package name ") == resourcePackage, "renderer-package")
            val instance = single("interactiveInstanceId=")
            nativeGuard(instance == single("watchFaceInstanceId=") && instance == single("impl.instanceId=") &&
                instance.isNotBlank(), "instance-record")
            for (value in listOf("mVisible=true mReportedVisible=true", "destroyed=false", "surfaceDestroyed=false",
                "editorObscuresWatchFace=false", "isVisible=true", "isAmbient=false", "overriddenComplications=null")) {
                nativeGuard(value in lines, "interactive-native-state")
            }
            val slots = Regex("(?m)^\\s*ComplicationSlot (\\d+):").findAll(dump).toList()
            nativeGuard(slots.map { it.groupValues[1].toInt() }.toSet() == (11..18).toSet() && slots.size == 8,
                "native-slot-inventory")
            val enabled = mutableMapOf<Int, Boolean>()
            val deliveredSources = mutableMapOf<Int, String?>()
            val effectiveData = mutableMapOf<Int, String>()
            slots.forEachIndexed { index, match ->
                val id = match.groupValues[1].toInt()
                val block = dump.substring(match.range.last + 1, slots.getOrNull(index + 1)?.range?.first ?: dump.length)
                val data = block.lineSequence().map { it.trim() }.filter { it.startsWith("data=") }.singleOrNull()
                    ?: throw NativePending("effective-data-unavailable")
                effectiveData[id] = data.removePrefix("data=")
                val sources = Regex("dataSource=ComponentInfo\\{([^}]+)}").findAll(data).toList()
                nativeGuard(sources.size <= 1, "ambiguous-delivery-provenance")
                // Cached provenance is diagnostic only, even when a source is present.
                deliveredSources[id] = if (data.startsWith("data=NoDataComplicationData") ||
                    data.startsWith("data=EmptyComplicationData")) null else sources.singleOrNull()?.groupValues?.get(1)
                val active = block.lineSequence().map { it.trim() }.filter { it.startsWith("enabled=") }.single()
                nativeGuard(active == "enabled=true" || active == "enabled=false", "enabled-record")
                enabled[id] = active == "enabled=true"
            }
            // Selections come from the independent service query in readNativeSelections,
            // never cached dataSource or defaultDataSourcePolicy from this dump.
            return NativeRenderer(resourcePackage, instance, single("currentUserStyleRepository.userStyle="),
                enabled, deliveredSources, effectiveData = effectiveData)
        }
    }
}
