package app.wardpulse.wear.sync

import android.content.Context
import android.util.Log
import com.google.android.gms.wearable.Wearable

/**
 * Ask the phone to run a provider sync. Wear never talks to providers itself.
 *
 * Allowance is phone-owned (`manualRefreshAllowed` / `manualRefreshAvailableAt`).
 * A short send debounce only prevents duplicate messages from double-taps.
 */
class PhoneRefreshRequester(context: Context) {
    private val appContext = context.applicationContext
    private var lastSendAtMs = 0L

    fun requestRefresh() {
        val now = System.currentTimeMillis()
        if (now - lastSendAtMs < SEND_DEBOUNCE_MS) {
            return
        }
        lastSendAtMs = now
        val nodeClient = Wearable.getNodeClient(appContext)
        val messageClient = Wearable.getMessageClient(appContext)
        nodeClient.connectedNodes
            .addOnSuccessListener { nodes ->
                if (nodes.isEmpty()) {
                    Log.i(TAG, "Refresh requested; no phone nodes connected.")
                    return@addOnSuccessListener
                }
                nodes.forEach { node ->
                    messageClient
                        .sendMessage(node.id, WatchDataContract.REFRESH_PATH, ByteArray(0))
                        .addOnSuccessListener {
                            Log.i(TAG, "Refresh request sent to ${node.displayName}.")
                        }
                        .addOnFailureListener { error ->
                            Log.w(TAG, "Refresh request failed: ${error.message}")
                        }
                }
            }
            .addOnFailureListener { error ->
                Log.w(TAG, "Node lookup failed: ${error.message}")
            }
    }

    companion object {
        private const val TAG = "WardPulseRefresh"
        private const val SEND_DEBOUNCE_MS = 2_000L
    }
}
