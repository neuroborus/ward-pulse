package app.wardpulse.watchsync

import android.content.Context
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

internal class PhoneWidgetPublicationChannel(context: Context, messenger: BinaryMessenger) : MethodChannel.MethodCallHandler {
    // home_widget 0.9.3 HomeWidgetPlugin.getData uses this same flat-cache file.
    private val store = PhoneWidgetPublicationStore(
        context.applicationContext.getSharedPreferences("HomeWidgetPreferences", Context.MODE_PRIVATE))
    private val main = Handler(Looper.getMainLooper())
    private val channel = MethodChannel(messenger, "app.wardpulse/widget_publication")
    private var attached = true
    init { channel.setMethodCallHandler(this) }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method != "publish" && call.method != "markStale") {
            result.notImplemented()
            return
        }
        executor.execute {
            try {
                val saved = if (call.method == "publish") {
                    store.publish(call.arguments as? Map<*, *> ?: throw IllegalArgumentException())
                } else store.markStale()
                main.post { if (attached) result.success(saved) }
            } catch (_: IllegalArgumentException) {
                main.post { if (attached) result.error("invalid_widget_publication", "Invalid widget publication.", null) }
            } catch (_: Exception) {
                main.post { if (attached) result.error("widget_storage_unavailable", "Widget storage unavailable.", null) }
            }
        }
    }

    fun detach() {
        attached = false
        channel.setMethodCallHandler(null)
    }

    private companion object { val executor = Executors.newSingleThreadExecutor() }
}
