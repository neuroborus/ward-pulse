package app.wardpulse.watchsync

import android.content.Context
import android.util.Log
import com.google.android.gms.common.GoogleApiAvailability
import com.google.android.gms.wearable.DataClient
import com.google.android.gms.wearable.PutDataMapRequest
import com.google.android.gms.wearable.PutDataRequest
import com.google.android.gms.wearable.Wearable
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.UUID

/** Engine-owned sender for WardPulse watch summaries. */
class WardPulseWatchSyncPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
    private lateinit var applicationContext: Context
    private lateinit var channel: MethodChannel
    private var connectionCache: ConnectionCacheChannel? = null
    private var widgetPublication: PhoneWidgetPublicationChannel? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        applicationContext = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, CHANNEL_NAME)
        channel.setMethodCallHandler(this)
        connectionCache = ConnectionCacheChannel(applicationContext, binding.binaryMessenger)
        widgetPublication = PhoneWidgetPublicationChannel(applicationContext, binding.binaryMessenger)
    }

    override fun onMethodCall(
        call: MethodCall,
        result: MethodChannel.Result,
    ) {
        if (call.method != SYNC_METHOD) {
            result.notImplemented()
            return
        }

        val arguments = call.arguments as? Map<*, *>
        val payload = (arguments?.get("payload") ?: call.arguments) as? String
        val generation = (arguments?.get("generation") as? Number)?.toLong()
        val confirmation = (arguments?.get("confirmation") as? Number)?.toLong()
        val selection = (arguments?.get("selection") as? Map<*, *>)?.let(::SelectionProof)
        if (payload.isNullOrBlank()) {
            result.error(
                "invalid_watch_summary",
                "Watch summary is missing.",
                null,
            )
            return
        }

        val request =
            PutDataMapRequest.create(DATA_PATH).apply {
                dataMap.putString(PAYLOAD_KEY, payload)
                dataMap.putLong(REVISION_KEY, System.currentTimeMillis())
            }.asPutDataRequest().setUrgent()
        val ticket =
            try {
                ConnectionCacheChannel.engine(applicationContext).reserveWatchSummary()
            } catch (error: RuntimeException) {
                reportFailure(error, result)
                return
            }
        queueWatchSummary(request, generation, confirmation, selection, ticket, result)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        connectionCache?.detach()
        connectionCache = null
        widgetPublication?.detach()
        widgetPublication = null
    }

    private fun queueWatchSummary(
        request: PutDataRequest,
        generation: Long?,
        confirmation: Long?,
        selection: SelectionProof?,
        ticket: Long,
        result: MethodChannel.Result,
    ) {
        try {
            val dataClient = Wearable.getDataClient(applicationContext)
            GoogleApiAvailability.getInstance()
                .checkApiAvailability(dataClient)
                .addOnSuccessListener {
                    // Load and credential ownership can retire within one mode
                    // generation while readiness is pending.
                    confirmOwnership(confirmation, result) {
                        submitWatchSummary(dataClient, request, generation, selection, ticket, result)
                    }
                }
                .addOnFailureListener { error -> reportFailure(error, result) }
        } catch (error: RuntimeException) {
            reportFailure(error, result)
        }
    }

    /** Asks the sending engine whether its summary still owns its load and credentials. */
    private fun confirmOwnership(
        confirmation: Long?,
        result: MethodChannel.Result,
        submit: () -> Unit,
    ) {
        if (confirmation == null) {
            submit()
            return
        }
        try {
            channel.invokeMethod(
                CONFIRM_METHOD,
                confirmation,
                object : MethodChannel.Result {
                    override fun success(value: Any?) {
                        // A retired summary is dropped; its newer owner replies.
                        if (value == true) submit() else result.success(null)
                    }

                    override fun error(
                        code: String,
                        message: String?,
                        details: Any?,
                    ) = reportFailure(IllegalStateException(code), result)

                    override fun notImplemented() =
                        reportFailure(IllegalStateException("Ownership unavailable."), result)
                },
            )
        } catch (error: RuntimeException) {
            reportFailure(error, result)
        }
    }

    private fun submitWatchSummary(
        dataClient: DataClient,
        request: PutDataRequest,
        generation: Long?,
        selection: SelectionProof?,
        ticket: Long,
        result: MethodChannel.Result,
    ) {
        // Own the submitted put independently of Flutter engine lifetime.
        val owner = UUID.randomUUID().toString()
        try {
            val engine = ConnectionCacheChannel.engine(applicationContext)
            val lease = generation?.let { engine.enterEffect(owner, it) }
            if (generation != null && lease == null) {
                result.error("watch_summary_retired", "Data mode changed.", null)
                return
            }
            // Dart confirms load ownership; a same-generation credential retirement or
            // cache write can still commit after it, so the selection is proved with
            // the send claim.
            val admitted =
                engine.admitWatchSummary(
                    ticket,
                    selection?.versions,
                    selection?.attemptClockEras.orEmpty(),
                    selection?.payloadOrders.orEmpty(),
                    selection?.emptyCacheOrders.orEmpty(),
                )
            if (admitted != true) {
                if (lease != null) ConnectionCacheChannel.finishPublication(engine, owner, lease)
                // Readiness can release an older summary after a newer one was sent.
                if (admitted == false) {
                    result.success(null)
                } else {
                    result.error("watch_summary_retired", "Credentials changed.", null)
                }
                return
            }
            try {
                dataClient.putDataItem(request).addOnCompleteListener { task ->
                    if (lease != null) ConnectionCacheChannel.finishPublication(engine, owner, lease)
                    if (task.isSuccessful) {
                        Log.i(TAG, "Watch summary queued.")
                        result.success(null)
                    } else {
                        reportFailure(task.exception ?: IllegalStateException(), result)
                    }
                }
            } catch (error: RuntimeException) {
                if (lease != null) ConnectionCacheChannel.finishPublication(engine, owner, lease)
                throw error
            }
        } catch (error: RuntimeException) {
            reportFailure(error, result)
        }
    }

    private fun reportFailure(
        error: Exception,
        result: MethodChannel.Result,
    ) {
        Log.w(TAG, "Watch sync unavailable (${error.javaClass.simpleName}).")
        result.error(
            "watch_sync_unavailable",
            "Watch sync unavailable. Pair a Wear OS device (or emulator) with this phone first.",
            null,
        )
    }

    companion object {
        fun captureLegacyWatchRefresh(context: Context, payload: ByteArray?, captured: (Map<String, Any>?) -> Unit) =
            ConnectionCacheChannel.captureLegacyWatchRefresh(context, payload, captured)

        private const val TAG = "WardPulseSync"
        private const val CHANNEL_NAME = "app.wardpulse/watch_sync"
        private const val SYNC_METHOD = "syncWatchSummary"
        private const val CONFIRM_METHOD = "confirmWatchSummary"
        private const val DATA_PATH = "/wardpulse/watch-summary"
        private const val PAYLOAD_KEY = "payload"
        private const val REVISION_KEY = "revision"
    }
}

/** A report or failure's native selection proof, in `validAll` argument form. */
@Suppress("UNCHECKED_CAST")
private class SelectionProof(selection: Map<*, *>) {
    val versions = selection["versions"] as? Map<String, Map<String, String>> ?: emptyMap()
    val attemptClockEras =
        (selection["attemptClockEras"] as? Map<String, Number>)?.mapValues { it.value.toLong() }.orEmpty()
    val payloadOrders = (selection["payloadOrders"] as? Map<String, Map<String, Any>>).orEmpty()
    val emptyCacheOrders = (selection["emptyCacheOrders"] as? Map<String, String>).orEmpty()
}
