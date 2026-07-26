package app.wardpulse

import android.content.Intent
import android.util.Log
import com.google.android.gms.wearable.MessageEvent
import com.google.android.gms.wearable.WearableListenerService

/**
 * Receives Wear Glance refresh taps and wakes [MainActivity] so Flutter can sync.
 */
class WatchRefreshListenerService : WearableListenerService() {
    override fun onMessageReceived(messageEvent: MessageEvent) {
        if (messageEvent.path != REFRESH_PATH) {
            return
        }
        Log.i(TAG, "Watch refresh request received.")
        val intent =
            Intent(this, MainActivity::class.java).apply {
                action = ACTION_WATCH_REFRESH
                addFlags(
                    Intent.FLAG_ACTIVITY_NEW_TASK or
                        Intent.FLAG_ACTIVITY_SINGLE_TOP or
                        Intent.FLAG_ACTIVITY_REORDER_TO_FRONT,
                )
            }
        startActivity(intent)
    }

    companion object {
        const val ACTION_WATCH_REFRESH = "app.wardpulse.action.WATCH_REFRESH"
        const val REFRESH_PATH = "/wardpulse/refresh-request"
        private const val TAG = "WardPulseRefresh"
    }
}
