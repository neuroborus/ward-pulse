package app.wardpulse.watchsync

import android.content.Context
import android.util.Log
import com.google.android.gms.common.GoogleApiAvailability
import com.google.android.gms.wearable.PutDataMapRequest
import com.google.android.gms.wearable.PutDataRequest
import com.google.android.gms.wearable.Wearable
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/** Engine-owned sender for WardPulse watch summaries. */
class WardPulseWatchSyncPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
    private lateinit var applicationContext: Context
    private lateinit var channel: MethodChannel

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        applicationContext = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, CHANNEL_NAME)
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(
        call: MethodCall,
        result: MethodChannel.Result,
    ) {
        if (call.method != SYNC_METHOD) {
            result.notImplemented()
            return
        }

        val payload = call.arguments as? String
        if (payload.isNullOrBlank()) {
            result.error(
                "invalid_watch_summary",
                "Watch summary is missing.",
                null,
            )
            return
        }

        val request =
            PutDataMapRequest.create(DATA_PATH).apply {
                dataMap.putString(PAYLOAD_KEY, payload)
                dataMap.putLong(REVISION_KEY, System.currentTimeMillis())
            }.asPutDataRequest().setUrgent()
        queueWatchSummary(request, result)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }

    private fun queueWatchSummary(
        request: PutDataRequest,
        result: MethodChannel.Result,
    ) {
        try {
            val dataClient = Wearable.getDataClient(applicationContext)
            GoogleApiAvailability.getInstance()
                .checkApiAvailability(dataClient)
                .addOnSuccessListener {
                    dataClient.putDataItem(request)
                        .addOnSuccessListener {
                            Log.i(TAG, "Watch summary queued.")
                            result.success(null)
                        }
                        .addOnFailureListener { error -> reportFailure(error, result) }
                }
                .addOnFailureListener { error -> reportFailure(error, result) }
        } catch (error: RuntimeException) {
            reportFailure(error, result)
        }
    }

    private fun reportFailure(
        error: Exception,
        result: MethodChannel.Result,
    ) {
        Log.w(TAG, "Watch sync unavailable (${error.javaClass.simpleName}).")
        result.error(
            "watch_sync_unavailable",
            "Watch sync unavailable. Pair a Wear OS device (or emulator) with this phone first.",
            null,
        )
    }

    private companion object {
        const val TAG = "WardPulseSync"
        const val CHANNEL_NAME = "app.wardpulse/watch_sync"
        const val SYNC_METHOD = "syncWatchSummary"
        const val DATA_PATH = "/wardpulse/watch-summary"
        const val PAYLOAD_KEY = "payload"
        const val REVISION_KEY = "revision"
    }
}
