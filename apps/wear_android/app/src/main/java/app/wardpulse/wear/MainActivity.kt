package app.wardpulse.wear

import android.annotation.SuppressLint
import android.app.Application
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.lifecycleScope
import androidx.lifecycle.repeatOnLifecycle
import androidx.lifecycle.viewModelScope
import app.wardpulse.wear.complication.WatchComplicationUpdater
import app.wardpulse.wear.data.WatchSummaryStore
import app.wardpulse.wear.model.WatchDashboardSummary
import app.wardpulse.wear.ui.WardPulseApp
import app.wardpulse.wear.ui.theme.WardPulseTheme
import app.wardpulse.wear.watchface.AndroidWatchFacePushClient
import app.wardpulse.wear.watchface.WATCH_FACE_ACTIVATION_PERMISSION
import app.wardpulse.wear.watchface.WatchFaceConsentStore
import app.wardpulse.wear.watchface.WatchFaceController
import java.time.Instant
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

class MainActivity : ComponentActivity() {
    private lateinit var store: WatchSummaryStore
    private var summary by mutableStateOf<WatchDashboardSummary?>(null)
    private var storeObserver: AutoCloseable? = null
    private val watchFace by lazy { ViewModelProvider(this)[WatchFaceViewModel::class.java] }
    // ComponentActivity owns this launcher; the diagnostic concerns transitive legacy Fragment handling.
    @SuppressLint("InvalidFragmentVersionForActivityResult")
    private val watchFacePermission = registerForActivityResult(ActivityResultContracts.RequestPermission()) {
        watchFace.onPermissionResult(it)
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        store = WatchSummaryStore(this)
        summary = currentSummary()

        // A request belongs to the retained explicit action, independent of summary/navigation.
        lifecycleScope.launch {
            repeatOnLifecycle(Lifecycle.State.RESUMED) {
                watchFace.permissionRequested.collect { requested ->
                    if (requested) {
                        watchFace.launchRequestedPermission {
                            watchFacePermission.launch(WATCH_FACE_ACTIVATION_PERMISSION)
                        }
                    }
                }
            }
        }

        setContent {
            val watchFaceState by watchFace.state.collectAsState()
            WardPulseTheme {
                WardPulseApp(
                    summary = summary,
                    watchFaceState = watchFaceState,
                    onCheckWatchFace = watchFace::check,
                    onInstallWatchFace = watchFace::install,
                    onUpdateWatchFace = watchFace::update,
                    onUseWatchFace = watchFace::useWatchFace,
                )
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

internal class WatchFaceViewModel(application: Application) : AndroidViewModel(application) {
    private val controller = WatchFaceController(
        AndroidWatchFacePushClient(application),
        WatchFaceConsentStore(application),
    )
    val state = controller.state
    private val mutablePermissionRequested = MutableStateFlow(false)
    val permissionRequested = mutablePermissionRequested.asStateFlow()

    fun check() {
        viewModelScope.launch { controller.check() }
    }

    fun install() {
        viewModelScope.launch { controller.install() }
    }

    fun update() {
        viewModelScope.launch { controller.update() }
    }

    fun useWatchFace() {
        viewModelScope.launch {
            controller.useWatchFace { mutablePermissionRequested.value = true }
        }
    }

    fun launchRequestedPermission(launch: () -> Unit) {
        if (!mutablePermissionRequested.value) return
        // Consume before launching; recreation must receive the result, never relaunch.
        mutablePermissionRequested.value = false
        try {
            launch()
        } catch (_: Exception) {
            onPermissionResult(false)
        }
    }

    fun onPermissionResult(granted: Boolean) {
        viewModelScope.launch { controller.onPermissionResult(granted) }
    }
}
