package app.wardpulse.wear

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import app.wardpulse.wear.data.WatchSummaryStore
import app.wardpulse.wear.model.MockWatchSummary
import app.wardpulse.wear.ui.WardPulseApp
import app.wardpulse.wear.ui.theme.WardPulseTheme

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        val store = WatchSummaryStore(this)
        val summary = store.load() ?: MockWatchSummary.value.also(store::save)

        setContent {
            WardPulseTheme {
                WardPulseApp(summary)
            }
        }
    }
}
