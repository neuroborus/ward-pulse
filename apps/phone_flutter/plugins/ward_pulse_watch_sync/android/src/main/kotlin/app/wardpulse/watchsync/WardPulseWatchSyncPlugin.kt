package app.wardpulse.watchsync

import android.content.Context
import android.util.Log
import com.google.android.gms.common.GoogleApiAvailability
import com.google.android.gms.wearable.Wearable
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.UUID
import org.json.JSONObject

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
        // Every engine, a WorkManager engine included, reasserts a summary that process death
        // left unacknowledged, or replaces one a mode commit retired.
        WatchPublisher.process.reconcile(applicationContext)
    }

    override fun onMethodCall(
        call: MethodCall,
        result: MethodChannel.Result,
    ) {
        if (call.method == RESUME_METHOD) {
            // Warm resume and explicit sync: replace an owed summary or resume a pending put.
            WatchPublisher.process.reconcile(applicationContext)
            result.success(null)
            return
        }
        if (call.method == ESTABLISHED_METHOD) {
            try {
                result.success(WatchPublisher.process.established(applicationContext))
            } catch (error: RuntimeException) {
                reportFailure(error, result)
            }
            return
        }
        if (call.method != SYNC_METHOD) {
            result.notImplemented()
            return
        }

        val arguments = call.arguments as? Map<*, *>
        val payload = (arguments?.get("payload") ?: call.arguments) as? String
        val summary = arguments?.get("summary") as? String
        val generation = (arguments?.get("generation") as? Number)?.toLong()
        val load = (arguments?.get("load") as? Number)?.toLong()
        val settingsRevision = (arguments?.get("settingsRevision") as? Number)?.toLong()
        val confirmation = (arguments?.get("confirmation") as? Number)?.toLong()
        val selectionArgument = arguments?.get("selection") as? Map<*, *>
        val selection = selectionArgument?.let(::SelectionProof)
        val selectionJson =
            try {
                selectionArgument?.let { JSONObject(it).toString() }
            } catch (error: RuntimeException) {
                reportFailure(error, result)
                return
            }
        if (payload.isNullOrBlank()) {
            result.error(
                "invalid_watch_summary",
                "Watch summary is missing.",
                null,
            )
            return
        }

        // The order is allocated on arrival, before the asynchronous send, above any order
        // this install published before process death, for the accepted load and settings
        // revision the summary was built from.
        val ticket =
            try {
                ConnectionCacheChannel.engine(applicationContext).issueWatchSummary(
                    WatchPublicationStore(applicationContext).lastSequence(), load, generation, settingsRevision)
            } catch (error: RuntimeException) {
                reportFailure(error, result)
                return
            }
        if (ticket == null) {
            superseded(result)
            return
        }
        val request = SummaryRequest(payload, summary, generation, confirmation, selection, selectionJson, ticket)
        queueWatchSummary(request, result)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        connectionCache?.detach()
        connectionCache = null
        widgetPublication?.detach()
        widgetPublication = null
    }

    private class SummaryRequest(
        val payload: String,
        val summary: String?,
        val generation: Long?,
        val confirmation: Long?,
        val selection: SelectionProof?,
        val selectionJson: String?,
        val ticket: Long,
    )

    private fun queueWatchSummary(request: SummaryRequest, result: MethodChannel.Result) {
        // Readiness only gates the put: a failure still reaches the durable desired publication,
        // whose put then fails, retries and resumes.
        val ready =
            try {
                GoogleApiAvailability.getInstance()
                    .checkApiAvailability(Wearable.getDataClient(applicationContext))
            } catch (_: RuntimeException) {
                null
            }
        if (ready == null) {
            confirmAndSubmit(request, result)
        } else {
            ready.addOnCompleteListener { confirmAndSubmit(request, result) }
        }
    }

    /**
     * Ownership can retire within one mode generation while readiness is pending, so it is
     * confirmed once readiness settles. The replacement is then persisted at once, even while an
     * earlier put settles; its own put proves the load, settings and selection again.
     */
    private fun confirmAndSubmit(request: SummaryRequest, result: MethodChannel.Result) {
        confirmOwnership(request.confirmation, result) { submitWatchSummary(request, result) }
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
                        // A retired summary never reaches the transport; its newer owner replies.
                        if (value == true) submit() else superseded(result)
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

    private fun submitWatchSummary(request: SummaryRequest, result: MethodChannel.Result) {
        val generation = request.generation
        val selection = request.selection
        val ticket = request.ticket
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
            val admission =
                admitWatchSend(
                    engine,
                    ticket,
                    selection?.versions,
                    selection?.attemptClockEras.orEmpty(),
                    selection?.payloadOrders.orEmpty(),
                    selection?.emptyCacheOrders.orEmpty(),
                )
            if (admission != WatchAdmission.ADMITTED) {
                if (lease != null) ConnectionCacheChannel.finishPublication(engine, owner, lease)
                if (admission == WatchAdmission.SUPERSEDED) {
                    superseded(result)
                } else {
                    result.error("watch_summary_retired", "Credentials changed.", null)
                }
                return
            }
            val publication = publication(engine, request.payload, request.summary, ticket)
                ?.copy(selection = request.selectionJson)
            if (publication == null) {
                // An unscoped summary of another mode is never sent; the current mode answers.
                if (lease != null) ConnectionCacheChannel.finishPublication(engine, owner, lease)
                superseded(result)
                return
            }
            // The lease orders the write against mode commits; the put, once an earlier one
            // settles, takes its own.
            try {
                WatchPublisher.process.submit(applicationContext, publication) { error ->
                    when (error) {
                        null -> result.success(null)
                        is WatchSummarySupersededException -> superseded(result)
                        else -> reportFailure(error, result)
                    }
                }
            } finally {
                if (lease != null) ConnectionCacheChannel.finishPublication(engine, owner, lease)
            }
        } catch (error: RuntimeException) {
            reportFailure(error, result)
        }
    }

    /** A newer accepted load or a settings save retired the summary's input; a fresh read answers. */
    private fun superseded(result: MethodChannel.Result) =
        result.error("watch_summary_superseded", "Watch summary input changed.", null)

    /**
     * Composes the desired item under the send claim: the v10 summary takes the current install,
     * generation and claimed order. Before the data-mode record exists only the v9 projection is
     * published. Null when the summary's provenance is not the current mode.
     */
    private fun publication(
        engine: ConnectionCacheEngine,
        payload: String,
        summary: String?,
        ticket: Long,
    ): WatchPublication? {
        val mode = engine.readMode()
        val installId = mode["installId"] as? String
            ?: return WatchPublication(ticket, null, null, payload, null)
        val generation = (mode["generation"] as Number).toLong()
        val body = try {
            // An unscoped Live or Mock publication carries only its projection.
            summary?.let(::JSONObject) ?: JSONObject(payload).put("schemaVersion", SCHEMA_VERSION)
        } catch (_: org.json.JSONException) {
            return null
        }
        if (body.opt("schemaVersion") != SCHEMA_VERSION || body.opt("dataMode") != mode["mode"]) return null
        return WatchPublication(ticket, installId, generation, payload, orderedSummary(body, installId, generation, ticket))
    }

    private fun reportFailure(
        error: Exception,
        result: MethodChannel.Result,
    ) {
        // A diagnostic, not a paired-gate marker: `WardPulseSync` carries only publications.
        Log.w(WatchPublisher.DIAGNOSTIC_TAG, "Watch sync unavailable (${error.javaClass.simpleName}).")
        result.error(
            "watch_sync_unavailable",
            "Watch sync unavailable. Pair a Wear OS device (or emulator) with this phone first.",
            null,
        )
    }

    companion object {
        /** Captures a v10 tap for its current owner, or a v9 empty tap by the legacy rule. */
        fun captureWatchRefresh(context: Context, payload: ByteArray?, captured: (Map<String, Any>?) -> Unit) =
            ConnectionCacheChannel.captureWatchRefresh(context, payload, captured)

        /** Wear's route proof on `/wardpulse/summary-owner`; null without a v10 publication. */
        fun watchSummaryOwner(context: Context, request: ByteArray?): ByteArray? =
            runCatching { WatchPublisher.process.ownerReply(context, request) }.getOrNull()

        private const val CHANNEL_NAME = "app.wardpulse/watch_sync"
        private const val SYNC_METHOD = "syncWatchSummary"
        private const val CONFIRM_METHOD = "confirmWatchSummary"
        private const val ESTABLISHED_METHOD = "watchSummaryEstablished"
        private const val RESUME_METHOD = "resumeWatchSummary"
    }
}

/** A report or failure's native selection proof, in `validAll` argument form. */
@Suppress("UNCHECKED_CAST")
internal class SelectionProof(selection: Map<*, *>) {
    val versions = selection["versions"] as? Map<String, Map<String, String>> ?: emptyMap()
    val attemptClockEras =
        (selection["attemptClockEras"] as? Map<String, Number>)?.mapValues { it.value.toLong() }.orEmpty()
    val payloadOrders = (selection["payloadOrders"] as? Map<String, Map<String, Any>>).orEmpty()
    val emptyCacheOrders = (selection["emptyCacheOrders"] as? Map<String, String>).orEmpty()
}
