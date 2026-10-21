package app.wardpulse.wear.watchface

import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.os.ParcelFileDescriptor
import androidx.wear.watchfacepush.WatchFacePushManager
import androidx.wear.watchfacepush.WatchFacePushManagerFactory
import app.wardpulse.wear.R
import java.io.File

internal const val PUSH_FACE_PACKAGE = "app.wardpulse.watchfacepush.main"
internal const val WATCH_FACE_ACTIVATION_PERMISSION =
    "com.google.wear.permission.SET_PUSHED_WATCH_FACE_AS_ACTIVE"

interface WatchFaceBundle : AutoCloseable {
    val packageName: String
    val versionCode: Long
}

data class InstalledWatchFace(val slotId: String, val packageName: String, val versionCode: Long)

data class WatchFaceInventory(val faces: List<InstalledWatchFace>, val remainingSlots: Int)

interface WatchFacePushClient {
    val sdkInt: Int
    fun isSupported(): Boolean
    fun openBundle(): WatchFaceBundle
    suspend fun list(): WatchFaceInventory
    suspend fun isActive(packageName: String): Boolean
    suspend fun install(bundle: WatchFaceBundle): InstalledWatchFace
    suspend fun update(slotId: String, bundle: WatchFaceBundle): InstalledWatchFace
    fun hasActivationPermission(): Boolean
    suspend fun activate(slotId: String)
}

class AndroidWatchFacePushClient(context: Context) : WatchFacePushClient {
    private val context = context.applicationContext
    override val sdkInt: Int get() = Build.VERSION.SDK_INT

    override fun isSupported(): Boolean = WatchFacePushManagerFactory.isSupported()

    private fun manager(): WatchFacePushManager {
        check(isSupported())
        return WatchFacePushManagerFactory.createWatchFacePushManager(context)
    }

    // The controller calls this on its IO dispatcher and owns the returned descriptor.
    override fun openBundle(): WatchFaceBundle {
        val file = File.createTempFile("watch-face-", ".apk", context.cacheDir)
        try {
            context.assets.open("default_watchface.apk").use { source ->
                file.outputStream().use { source.copyTo(it) }
            }
            val info = requireNotNull(context.packageManager.getPackageArchiveInfo(file.path, 0))
            require(info.packageName == PUSH_FACE_PACKAGE && info.longVersionCode > 0)
            val token = context.getString(R.string.default_wf_token)
            require(token.isNotBlank())
            return ApkBundle(
                info.packageName,
                info.longVersionCode,
                file,
                token,
                ParcelFileDescriptor.open(file, ParcelFileDescriptor.MODE_READ_ONLY),
            )
        } catch (failure: Throwable) {
            file.delete()
            throw failure
        }
    }

    override suspend fun list(): WatchFaceInventory = manager().listWatchFaces().let { result ->
        WatchFaceInventory(result.installedWatchFaceDetails.map { it.toInstalled() }, result.remainingSlotCount)
    }

    override suspend fun isActive(packageName: String): Boolean = manager().isWatchFaceActive(packageName)

    override suspend fun install(bundle: WatchFaceBundle): InstalledWatchFace {
        val apk = bundle as ApkBundle
        return manager().addWatchFace(apk.descriptor, apk.token).toInstalled()
    }

    override suspend fun update(slotId: String, bundle: WatchFaceBundle): InstalledWatchFace {
        val apk = bundle as ApkBundle
        return manager().updateWatchFace(slotId, apk.descriptor, apk.token).toInstalled()
    }

    override fun hasActivationPermission(): Boolean =
        context.checkSelfPermission(WATCH_FACE_ACTIVATION_PERMISSION) == PackageManager.PERMISSION_GRANTED

    override suspend fun activate(slotId: String) = manager().setWatchFaceAsActive(slotId)

    private class ApkBundle(
        override val packageName: String,
        override val versionCode: Long,
        private val file: File,
        val token: String,
        val descriptor: ParcelFileDescriptor,
    ) : WatchFaceBundle {
        override fun close() {
            try {
                descriptor.close()
            } finally {
                file.delete()
            }
        }
    }
}

private fun WatchFacePushManager.WatchFaceDetails.toInstalled() =
    InstalledWatchFace(slotId, packageName, versionCode)
