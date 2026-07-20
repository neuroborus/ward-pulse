package app.wardpulse.wear

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.runtime.mutableStateOf
import app.wardpulse.wear.data.WatchSummaryStore
import app.wardpulse.wear.model.WatchDashboardSummary
import app.wardpulse.wear.ui.WardPulseApp
import app.wardpulse.wear.ui.theme.WardPulseTheme
import java.time.Instant

class MainActivity : ComponentActivity() {
    private lateinit var store: WatchSummaryStore
    private val summary = mutableStateOf<WatchDashboardSummary?>(null)
    private var storeObserver: AutoCloseable? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        store = WatchSummaryStore(this)
        summary.value = currentSummary()

        setContent {
            WardPulseTheme {
                WardPulseApp(summary.value)
            }
        }
    }

    override fun onStart() {
        super.onStart()
        storeObserver = store.observe(::reloadSummary)
        reloadSummary()
    }

    override fun onStop() {
        storeObserver?.close()
        storeObserver = null
        super.onStop()
    }

    private fun reloadSummary() {
        summary.value = currentSummary()
    }

    private fun currentSummary() = store.load()?.let { saved ->
        saved.copy(isStale = saved.isStaleAt(Instant.now()))
    }
}
