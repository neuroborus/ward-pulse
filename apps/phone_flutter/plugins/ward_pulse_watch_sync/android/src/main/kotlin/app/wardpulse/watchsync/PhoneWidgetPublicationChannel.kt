package app.wardpulse.watchsync

import android.content.Context
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.UUID
import java.util.concurrent.Executors

internal class PhoneWidgetPublicationChannel(context: Context, messenger: BinaryMessenger) : MethodChannel.MethodCallHandler {
    // home_widget 0.9.3 HomeWidgetPlugin.getData uses this same flat-cache file.
    private val store = PhoneWidgetPublicationStore(
        context.applicationContext.getSharedPreferences("HomeWidgetPreferences", Context.MODE_PRIVATE))
    private val engine = ConnectionCacheChannel.engine(context.applicationContext)
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
                val arguments = call.arguments as? Map<*, *>
                val generation = (arguments?.get("generation") as? Number)?.toLong()
                val owner = UUID.randomUUID().toString()
                val lease = generation?.let { engine.enterEffect(owner, it) }
                if (generation != null && lease == null) {
                    main.post { if (attached) result.error("widget_publication_retired", "Data mode changed.", null) }
                    return@execute
                }
                val saved = try {
                    val mode = lease?.let { PhoneWidgetPublicationStore.modeFrom(engine.readMode()) }
                    if (call.method == "publish") {
                        store.publish(arguments ?: throw IllegalArgumentException(), mode)
                    } else store.markStale(mode)
                } finally {
                    if (lease != null) engine.exitEffect(owner, lease, false)
                }
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
