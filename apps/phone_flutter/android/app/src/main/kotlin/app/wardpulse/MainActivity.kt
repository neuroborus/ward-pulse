package app.wardpulse

import android.content.Intent
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var watchRefreshChannel: MethodChannel? = null
    private var pendingWatchRefresh: PendingWatchRefresh? = null
    private var watchRefreshReady = false
    private var navigationChannel: MethodChannel? = null
    private val dashboardLaunch = DashboardLaunchRequest()

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        if (!flutterEngine.plugins.has(CursorSignInPlugin::class.java)) {
            flutterEngine.plugins.add(CursorSignInPlugin(flutterEngine))
        }

        recordWatchRefresh(intent)
        watchRefreshChannel =
            MethodChannel(
                flutterEngine.dartExecutor.binaryMessenger,
                WATCH_REFRESH_CHANNEL_NAME,
            ).also { channel ->
                channel.setMethodCallHandler { call, result ->
                    when (call.method) {
                        WATCH_REFRESH_READY_METHOD -> {
                            // Dart decides whether startup can poll before creating its first load.
                            watchRefreshReady = true
                            result.success(takeWatchRefresh()?.arguments())
                        }
                        else -> result.notImplemented()
                    }
                }
            }

        navigationChannel =
            MethodChannel(flutterEngine.dartExecutor.binaryMessenger, NAVIGATION_CHANNEL_NAME)
                .also { channel ->
                    channel.setMethodCallHandler { call, result ->
                        when (call.method) {
                            NAVIGATION_READY_METHOD -> {
                                dashboardLaunch.markReady()
                                flushPendingDashboardLaunch()
                                result.success(null)
                            }
                            else -> result.notImplemented()
                        }
                    }
                }
        markPendingDashboardLaunch(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        recordWatchRefresh(intent)
        flushPendingWatchRefresh()
        if (markPendingDashboardLaunch(intent)) {
            flushPendingDashboardLaunch()
        }
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        watchRefreshChannel?.setMethodCallHandler(null)
        watchRefreshChannel = null
        watchRefreshReady = false
        navigationChannel?.setMethodCallHandler(null)
        navigationChannel = null
        dashboardLaunch.reset()
        super.cleanUpFlutterEngine(flutterEngine)
    }

    private fun markPendingDashboardLaunch(intent: Intent?): Boolean {
        if (!dashboardLaunch.record(intent?.action)) return false
        // Consume before dispatch so activity recreation cannot replay this intent.
        intent?.action = null
        return true
    }

    private fun flushPendingDashboardLaunch() {
        val channel = navigationChannel ?: return
        if (dashboardLaunch.takeReadyRequest()) {
            channel.invokeMethod(OPEN_DASHBOARD_METHOD, null)
        }
    }

    private fun flushPendingWatchRefresh() {
        if (!watchRefreshReady) return
        val channel = watchRefreshChannel ?: return
        val pending = takeWatchRefresh() ?: return
        Log.i(TAG, "Forwarding watch refresh request to Flutter.")
        channel.invokeMethod(WATCH_REFRESH_METHOD, pending.arguments())
    }

    private fun recordWatchRefresh(intent: Intent?) {
        if (intent == null) return
        val request = WatchRefreshListenerService.read(intent) ?: return
        pendingWatchRefresh?.let { WatchRefreshListenerService.consume(it.source) }
        pendingWatchRefresh = PendingWatchRefresh(intent, request)
    }

    private fun takeWatchRefresh(): WatchRefreshIntent? {
        val pending = pendingWatchRefresh ?: return null
        pendingWatchRefresh = null
        WatchRefreshListenerService.consume(pending.source)
        return pending.request
    }

    private data class PendingWatchRefresh(val source: Intent, val request: WatchRefreshIntent)

    private companion object {
        const val TAG = "WardPulseRefresh"
        const val WATCH_REFRESH_CHANNEL_NAME = "app.wardpulse/watch_refresh"
        const val WATCH_REFRESH_METHOD = "watchRefreshRequested"
        const val WATCH_REFRESH_READY_METHOD = "watchRefreshChannelReady"
        const val NAVIGATION_CHANNEL_NAME = "app.wardpulse/app_navigation"
        const val NAVIGATION_READY_METHOD = "navigationChannelReady"
        const val OPEN_DASHBOARD_METHOD = "openDashboard"
    }
}
