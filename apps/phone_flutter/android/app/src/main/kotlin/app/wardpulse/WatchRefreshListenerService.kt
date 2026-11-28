package app.wardpulse

import android.content.Intent
import android.util.Log
import app.wardpulse.watchsync.WardPulseWatchSyncPlugin
import com.google.android.gms.tasks.Task
import com.google.android.gms.tasks.Tasks
import com.google.android.gms.wearable.MessageEvent
import com.google.android.gms.wearable.WearableListenerService

/**
 * Receives Wear Glance refresh taps and wakes [MainActivity] so Flutter can sync, and answers
 * Wear's summary route proofs.
 */
class WatchRefreshListenerService : WearableListenerService() {
    override fun onRequest(nodeId: String, path: String, request: ByteArray): Task<ByteArray> {
        val reply = if (path == OWNER_PATH) WardPulseWatchSyncPlugin.watchSummaryOwner(this, request) else null
        return if (reply == null) {
            Tasks.forException(IllegalStateException("No current watch summary."))
        } else {
            Tasks.forResult(reply)
        }
    }

    override fun onMessageReceived(messageEvent: MessageEvent) {
        if (messageEvent.path != REFRESH_PATH) {
            return
        }
        Log.i(TAG, "Watch refresh request received.")
        // A tap from a retired owner, cold start included, captures nothing and resends.
        WardPulseWatchSyncPlugin.captureWatchRefresh(this, messageEvent.data) { operation ->
            val intent = Intent(this, MainActivity::class.java).apply {
                action = ACTION_WATCH_REFRESH
                addFlags(
                    Intent.FLAG_ACTIVITY_NEW_TASK or
                        Intent.FLAG_ACTIVITY_SINGLE_TOP or
                        Intent.FLAG_ACTIVITY_REORDER_TO_FRONT,
                )
                putExtra(EXTRA_REQUEST, remember(operation))
            }
            startActivity(intent)
        }
    }

    companion object {
        const val ACTION_WATCH_REFRESH = "app.wardpulse.action.WATCH_REFRESH"
        const val REFRESH_PATH = "/wardpulse/refresh-request"
        const val OWNER_PATH = "/wardpulse/summary-owner"
        private const val EXTRA_REQUEST = "watchRefreshRequest"
        private const val TAG = "WardPulseRefresh"
        private val pending = LinkedHashMap<String, WatchRefreshIntent.Refresh>()

        @Synchronized
        private fun remember(operation: Map<String, Any>?): String? {
            if (operation == null) return null
            val token = operation["requestId"] as? String ?: return null
            if (pending.size == 16) pending.remove(pending.keys.first())
            pending[token] = WatchRefreshIntent.Refresh(operation)
            return token
        }

        @Synchronized
        internal fun read(intent: Intent?): WatchRefreshIntent? {
            if (intent?.action != ACTION_WATCH_REFRESH) return null
            return intent.getStringExtra(EXTRA_REQUEST)?.let { pending[it] } ?: WatchRefreshIntent.Resend
        }

        @Synchronized
        internal fun consume(intent: Intent) {
            intent.getStringExtra(EXTRA_REQUEST)?.let { pending.remove(it) }
            intent.action = null
        }
    }
}

internal sealed interface WatchRefreshIntent {
    fun arguments(): Map<String, Any>

    data class Refresh(private val operation: Map<String, Any>) : WatchRefreshIntent {
        override fun arguments() = operation + ("kind" to "refresh")
    }

    object Resend : WatchRefreshIntent {
        override fun arguments() = mapOf("kind" to "resend")
    }
}
