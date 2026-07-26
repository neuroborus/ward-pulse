package app.wardpulse.wear

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import app.wardpulse.wear.complication.WatchComplicationUpdater
import app.wardpulse.wear.data.WatchSummaryStore
import app.wardpulse.wear.model.WatchDashboardSummary
import app.wardpulse.wear.ui.WardPulseApp
import app.wardpulse.wear.ui.theme.WardPulseTheme
import java.time.Instant

class MainActivity : ComponentActivity() {
    private lateinit var store: WatchSummaryStore
    private var summary by mutableStateOf<WatchDashboardSummary?>(null)
    private var storeObserver: AutoCloseable? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        store = WatchSummaryStore(this)
        summary = currentSummary()

        setContent {
            WardPulseTheme {
                WardPulseApp(summary)
            }
        }
    }

    override fun onStart() {
        super.onStart()
        storeObserver = store.observe(::reloadSummary)
        reloadSummary()
        WatchComplicationUpdater.requestUpdate(this)
    }

    override fun onStop() {
        storeObserver?.close()
        storeObserver = null
        super.onStop()
    }

    private fun reloadSummary() {
        // Prefs listeners can run off the main thread; Compose state must not.
        runOnUiThread {
            summary = currentSummary()
        }
    }

    private fun currentSummary() = store.load()?.let { saved ->
        saved.copy(isStale = saved.isStaleAt(Instant.now()))
    }
}
