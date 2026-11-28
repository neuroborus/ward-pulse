package app.wardpulse.wear.sync

import android.content.Context
import android.util.Log
import app.wardpulse.wear.data.SummaryBinding
import app.wardpulse.wear.data.SummaryOwner
import com.google.android.gms.wearable.Wearable
import org.json.JSONObject

/**
 * Ask the phone to run a provider sync. Wear never talks to providers itself.
 *
 * Allowance is phone-owned (`manualRefreshAllowed` / `manualRefreshAvailableAt`).
 * A short send debounce only prevents duplicate messages from double-taps.
 *
 * A v10 binding asks only its bound phone, naming the accepted summary's install and
 * generation; the phone refreshes that source or, once retired, resends its current
 * summary. A v9-only binding sends the legacy empty message to its phone, and an unbound
 * watch to every connected phone. The binding is the one the rendered summary was read with
 * ([app.wardpulse.wear.data.WatchSummaryStore.loadBound]), so a tap on a summary a newer one
 * already replaced in the store still names the tapped summary's owner.
 */
class PhoneRefreshRequester(context: Context) {
    private val appContext = context.applicationContext
    private var lastSendAtMs = 0L

    fun requestRefresh(binding: SummaryBinding?) {
        val now = System.currentTimeMillis()
        if (now - lastSendAtMs < SEND_DEBOUNCE_MS) {
            return
        }
        lastSendAtMs = now
        val body = binding?.owner?.let(::refreshBody) ?: ByteArray(0)
        val nodeClient = Wearable.getNodeClient(appContext)
        val messageClient = Wearable.getMessageClient(appContext)
        nodeClient.connectedNodes
            .addOnSuccessListener { nodes ->
                val targets = nodes.filter { binding == null || it.id == binding.host }
                if (targets.isEmpty()) {
                    Log.i(TAG, "Refresh requested; no target phone connected.")
                    return@addOnSuccessListener
                }
                targets.forEach { node ->
                    messageClient
                        .sendMessage(node.id, WatchDataContract.REFRESH_PATH, body)
                        .addOnSuccessListener {
                            Log.i(TAG, "Refresh request sent.")
                        }
                        .addOnFailureListener {
                            Log.w(TAG, "Failed to send refresh request.")
                        }
                }
            }
            .addOnFailureListener {
                Log.w(TAG, "Connected node lookup failed.")
            }
    }

    companion object {
        private const val TAG = "WardPulseRefresh"
        private const val SEND_DEBOUNCE_MS = 2_000L

        /** The v10 refresh body: the accepted summary's owner, never a credential. */
        internal fun refreshBody(owner: SummaryOwner): ByteArray =
            JSONObject()
                .put("installId", owner.installId)
                .put("generation", owner.generation)
                .toString()
                .toByteArray(Charsets.UTF_8)
    }
}
