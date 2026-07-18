package app.wardpulse

import android.util.Log
import com.google.android.gms.common.GoogleApiAvailability
import com.google.android.gms.wearable.PutDataMapRequest
import com.google.android.gms.wearable.PutDataRequest
import com.google.android.gms.wearable.Wearable
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL_NAME)
            .setMethodCallHandler { call, result ->
                if (call.method != SYNC_METHOD) {
                    result.notImplemented()
                    return@setMethodCallHandler
                }

                val payload = call.arguments as? String
                if (payload.isNullOrBlank()) {
                    result.error("invalid_watch_summary", "Watch summary is missing.", null)
                    return@setMethodCallHandler
                }

                val request = PutDataMapRequest.create(DATA_PATH).apply {
                    dataMap.putString(PAYLOAD_KEY, payload)
                    dataMap.putLong(REVISION_KEY, System.currentTimeMillis())
                }.asPutDataRequest().setUrgent()

                queueWatchSummary(request, result)
            }
    }

    private fun queueWatchSummary(
        request: PutDataRequest,
        result: MethodChannel.Result,
    ) {
        try {
            val dataClient = Wearable.getDataClient(this)
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

    private fun reportFailure(error: Exception, result: MethodChannel.Result) {
        Log.w(TAG, "Watch sync unavailable (${error.javaClass.simpleName}).")
        result.error("watch_sync_unavailable", "Watch sync unavailable.", null)
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
