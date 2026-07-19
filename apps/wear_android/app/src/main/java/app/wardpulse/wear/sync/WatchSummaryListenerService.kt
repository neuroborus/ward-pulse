package app.wardpulse.wear.sync

import android.util.Log
import app.wardpulse.wear.data.WatchSummaryStore
import com.google.android.gms.wearable.DataEvent
import com.google.android.gms.wearable.DataEventBuffer
import com.google.android.gms.wearable.DataMapItem
import com.google.android.gms.wearable.WearableListenerService

class WatchSummaryListenerService : WearableListenerService() {
    override fun onDataChanged(dataEvents: DataEventBuffer) {
        val store = WatchSummaryStore(this)

        dataEvents
            .asSequence()
            .filter { it.type == DataEvent.TYPE_CHANGED }
            .filter { it.dataItem.uri.path == WatchDataContract.PATH }
            .forEach { event ->
                if (storeSummary(event, store)) {
                    Log.i(TAG, "Watch summary received.")
                } else {
                    Log.w(TAG, "Ignored invalid watch summary.")
                }
            }
    }

    private fun storeSummary(event: DataEvent, store: WatchSummaryStore): Boolean = try {
        val payload = DataMapItem.fromDataItem(event.dataItem)
            .dataMap
            .getString(WatchDataContract.PAYLOAD_KEY)
        payload != null && store.saveEncoded(payload)
    } catch (_: RuntimeException) {
        false
    }

    private companion object {
        const val TAG = "WardPulseSync"
    }
}
