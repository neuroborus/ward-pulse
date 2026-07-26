package app.wardpulse

import android.content.Intent
import android.util.Log
import com.google.android.gms.common.GoogleApiAvailability
import com.google.android.gms.wearable.PutDataMapRequest
import com.google.android.gms.wearable.PutDataRequest
import com.google.android.gms.wearable.Wearable
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var watchChannel: MethodChannel? = null
    private var pendingWatchRefresh = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        watchChannel =
            MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL_NAME).also { channel ->
                channel.setMethodCallHandler { call, result ->
                    when (call.method) {
                        SYNC_METHOD -> {
                            val payload = call.arguments as? String
                            if (payload.isNullOrBlank()) {
                                result.error(
                                    "invalid_watch_summary",
                                    "Watch summary is missing.",
                                    null,
                                )
                                return@setMethodCallHandler
                            }
                            val request =
                                PutDataMapRequest.create(DATA_PATH).apply {
                                    dataMap.putString(PAYLOAD_KEY, payload)
                                    dataMap.putLong(REVISION_KEY, System.currentTimeMillis())
                                }.asPutDataRequest().setUrgent()
                            queueWatchSummary(request, result)
                        }
                        WATCH_REFRESH_READY_METHOD -> {
                            // Dart handler is bound; deliver any cold-start refresh tap.
                            flushPendingWatchRefresh()
                            result.success(null)
                        }
                        else -> result.notImplemented()
                    }
                }
            }

        // Cold start: stash only. Dart calls watchRefreshChannelReady after binding.
        markPendingWatchRefresh(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        // Warm start: Dart handler is already bound.
        if (markPendingWatchRefresh(intent)) {
            flushPendingWatchRefresh()
        }
    }

    private fun markPendingWatchRefresh(intent: Intent?): Boolean {
        if (intent?.action != WatchRefreshListenerService.ACTION_WATCH_REFRESH) {
            return false
        }
        pendingWatchRefresh = true
        // Avoid re-delivery after rotation / recreate.
        intent.action = null
        return true
    }

    private fun flushPendingWatchRefresh() {
        if (!pendingWatchRefresh) {
            return
        }
        val channel = watchChannel ?: return
        pendingWatchRefresh = false
        Log.i(TAG, "Forwarding watch refresh request to Flutter.")
        channel.invokeMethod(WATCH_REFRESH_METHOD, null)
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
        const val WATCH_REFRESH_METHOD = "watchRefreshRequested"
        const val WATCH_REFRESH_READY_METHOD = "watchRefreshChannelReady"
        const val DATA_PATH = "/wardpulse/watch-summary"
        const val PAYLOAD_KEY = "payload"
        const val REVISION_KEY = "revision"
    }
}
