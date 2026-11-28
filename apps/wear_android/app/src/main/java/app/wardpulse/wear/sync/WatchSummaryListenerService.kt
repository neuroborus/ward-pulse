package app.wardpulse.wear.sync

import app.wardpulse.wear.data.WatchSummaryStore
import com.google.android.gms.wearable.CapabilityInfo
import com.google.android.gms.wearable.DataEvent
import com.google.android.gms.wearable.DataEventBuffer
import com.google.android.gms.wearable.WearableListenerService

class WatchSummaryListenerService : WearableListenerService() {
    override fun onDataChanged(dataEvents: DataEventBuffer) {
        // An event only signals that the route may have changed; reconciliation rereads it.
        val signalled = dataEvents.any {
            it.type == DataEvent.TYPE_CHANGED && it.dataItem.uri.path == WatchDataContract.PATH
        }
        if (signalled) reconcile(revalidate = false)
    }

    /**
     * An observed phone reconnect asks the bound owner again, even for an unchanged item; a
     * disconnect resolves the route afresh, which retires a proof still pending for it.
     */
    override fun onCapabilityChanged(capabilityInfo: CapabilityInfo) {
        if (capabilityInfo.name == WatchDataContract.PHONE_CAPABILITY) {
            reconcile(revalidate = capabilityInfo.nodes.isNotEmpty())
        }
    }

    // Listener callbacks run off the main thread, so the route proof may block here.
    private fun reconcile(revalidate: Boolean) {
        val reconciler = WatchSummaryReconciler(WatchSummaryStore(this), WearableSummaryRoute(this))
        WatchSummaryReconciler.report(this, reconciler.reconcile(revalidate))
    }
}
