package app.wardpulse

import android.webkit.WebView
import android.webkit.WebViewClient
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugins.webviewflutter.WebViewFlutterPlugin

/** Owns only guards for explicitly attached Cursor sign-in WebViews. */
class CursorSignInPlugin(private val engine: FlutterEngine) : FlutterPlugin {
    private data class Guard(
        val view: WebView,
        val delegate: WebViewClient,
        val client: CursorSignInWebViewClient,
    )

    private val guards = mutableMapOf<Long, Guard>()
    private var channel: MethodChannel? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(binding.binaryMessenger, "app.wardpulse/cursor_sign_in").also {
            it.setMethodCallHandler { call, result ->
                val id = call.argument<Number>("view")?.toLong()
                if (id == null) {
                    result.error("invalidView", "Sign-in view unavailable", null)
                    return@setMethodCallHandler
                }
                try {
                    when (call.method) {
                        "attach" -> {
                            check(!guards.containsKey(id))
                            val plugin = engine.plugins.get(WebViewFlutterPlugin::class.java)
                                as? WebViewFlutterPlugin
                            val manager = checkNotNull(plugin?.instanceManager)
                            val view = checkNotNull(manager.getInstance<WebView>(id))
                            val clientId = checkNotNull(call.argument<Number>("client")).toLong()
                            val delegate = checkNotNull(manager.getInstance<WebViewClient>(clientId))
                            val client = CursorSignInWebViewClient(delegate) { failure ->
                                // Interception runs off the UI thread. Cross only fixed
                                // categories; never forward a request URI/header/body.
                                view.post {
                                    if (guards[id]?.client?.failure() == failure) {
                                        channel?.invokeMethod("failure", mapOf(
                                            "view" to id,
                                            "category" to category(failure),
                                        ))
                                    }
                                }
                            }
                            view.webViewClient = client
                            guards[id] = Guard(view, delegate, client)
                            result.success(null)
                        }
                        "failure" -> {
                            val guard = checkNotNull(guards[id])
                            result.success(guard.client.failure()?.let(::category))
                        }
                        "retire" -> {
                            checkNotNull(guards[id]).client.beginRetirement()
                            result.success(null)
                        }
                        "detach" -> {
                            val guard = guards[id]
                            if (guard != null) {
                                guard.view.webViewClient = guard.delegate
                                guards.remove(id)
                            }
                            result.success(null)
                        }
                        else -> result.notImplemented()
                    }
                } catch (_: RuntimeException) {
                    result.error("guardUnavailable", "Sign-in request guard unavailable", null)
                }
            }
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel?.setMethodCallHandler(null)
        channel = null
        for (guard in guards.values) {
            try {
                guard.client.beginRetirement()
                guard.view.stopLoading()
                guard.view.loadUrl("about:blank")
                guard.view.webViewClient = guard.delegate
            } catch (_: RuntimeException) {
                // The engine may already have disposed this platform view.
            }
        }
        guards.clear()
    }

    private fun category(failure: CursorSignInWebViewClient.Failure): String = when (failure) {
        CursorSignInWebViewClient.Failure.GOOGLE_AUTHORIZATION -> "googleAuthorization"
        CursorSignInWebViewClient.Failure.MAIN_FRAME_HTTP_ERROR -> "mainFrameHttpError"
        CursorSignInWebViewClient.Failure.NAVIGATION_REJECTED -> "navigationRejected"
    }
}
