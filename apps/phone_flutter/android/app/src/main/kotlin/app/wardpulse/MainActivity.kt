package app.wardpulse

import android.content.Intent
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var watchRefreshChannel: MethodChannel? = null
    private var pendingWatchRefresh = false
    private var navigationChannel: MethodChannel? = null
    private val dashboardLaunch = DashboardLaunchRequest()

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        watchRefreshChannel =
            MethodChannel(
                flutterEngine.dartExecutor.binaryMessenger,
                WATCH_REFRESH_CHANNEL_NAME,
            ).also { channel ->
                channel.setMethodCallHandler { call, result ->
                    when (call.method) {
                        WATCH_REFRESH_READY_METHOD -> {
                            // Dart handler is bound; deliver any cold-start refresh tap.
                            flushPendingWatchRefresh()
                            result.success(null)
                        }
                        else -> result.notImplemented()
                    }
                }
            }

        // Cold start: stash only. Dart calls watchRefreshChannelReady after binding.
        markPendingWatchRefresh(intent)
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
        // Warm start: Dart handler is already bound.
        if (markPendingWatchRefresh(intent)) {
            flushPendingWatchRefresh()
        }
        if (markPendingDashboardLaunch(intent)) {
            flushPendingDashboardLaunch()
        }
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
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

    private fun markPendingWatchRefresh(intent: Intent?): Boolean {
        if (intent?.action != WatchRefreshListenerService.ACTION_WATCH_REFRESH) {
            return false
        }
        pendingWatchRefresh = true
        // Avoid re-delivery after rotation / recreate.
        intent.action = null
        return true
    }

    private fun flushPendingWatchRefresh() {
        if (!pendingWatchRefresh) {
            return
        }
        val channel = watchRefreshChannel ?: return
        pendingWatchRefresh = false
        Log.i(TAG, "Forwarding watch refresh request to Flutter.")
        channel.invokeMethod(WATCH_REFRESH_METHOD, null)
    }

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
