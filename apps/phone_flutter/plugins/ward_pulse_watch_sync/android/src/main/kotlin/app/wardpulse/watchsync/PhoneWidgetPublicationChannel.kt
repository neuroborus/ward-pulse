package app.wardpulse.watchsync

import android.appwidget.AppWidgetManager
import android.content.Context
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.UUID
import java.util.concurrent.Executors

internal class PhoneWidgetPublicationChannel(context: Context, messenger: BinaryMessenger) : MethodChannel.MethodCallHandler {
    private val context = context.applicationContext
    // home_widget 0.9.3 HomeWidgetPlugin.getData uses this same flat-cache file.
    private val store = PhoneWidgetPublicationStore(
        context.applicationContext.getSharedPreferences("HomeWidgetPreferences", Context.MODE_PRIVATE))
    private val engine = ConnectionCacheChannel.engine(context.applicationContext)
    private val main = Handler(Looper.getMainLooper())
    private val channel = MethodChannel(messenger, "app.wardpulse/widget_publication")
    // Owns this engine's settings saves; a detached engine's save releases readers.
    private val owner = UUID.randomUUID().toString()
    private var attached = true
    init { channel.setMethodCallHandler(this) }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method !in METHODS) {
            result.notImplemented()
            return
        }
        executor.execute {
            try {
                val arguments = call.arguments as? Map<*, *>
                when (call.method) {
                    "beginLoad" -> {
                        val mode = PhoneWidgetPublicationStore.modeFrom(engine.readMode())
                        val load = engine.beginWidgetLoad { store.sequence() ?: 0L }
                        val widgets = installedWidgets()
                        load["established"] = store.established(mode, widgets)
                        load["awaitingDelivery"] = store.awaitingDelivery(mode, widgets)
                        reply(result, load)
                    }
                    // Rechecked after acceptance, which retires the first delivery of undelivered rows.
                    "established" -> reply(result,
                        store.established(PhoneWidgetPublicationStore.modeFrom(engine.readMode()), installedWidgets()))
                    // Also rechecked after acceptance: rows committed since the load began may await it.
                    "awaitingDelivery" -> reply(result,
                        store.awaitingDelivery(PhoneWidgetPublicationStore.modeFrom(engine.readMode()), installedWidgets()))
                    "beginSettingsWrite" -> {
                        // Begun first: a publication of the old settings cannot commit after this.
                        // A watch item built from changed watch settings is retired durably too,
                        // for a new process; a launcher-only save leaves it answerable, and its
                        // in-process send authority standing.
                        val watchSettings = arguments?.get("watch") != false
                        val token = engine.beginSurfaceSettingsWrite(owner, watchSettings)
                        val retired = try {
                            retireSurfaceSettings(store::retireSettings, WatchPublicationStore(context), watchSettings)
                        } catch (_: RuntimeException) {
                            false
                        }
                        if (retired) {
                            reply(result, token)
                        } else {
                            // The save never starts, but it advanced the revision: the error
                            // carries the one it settles, or null while another save is in flight.
                            val settled = engine.finishSurfaceSettingsWrite(owner, token)
                            main.post {
                                if (attached) result.error("widget_storage_unavailable", "Widget storage unavailable.", settled)
                            }
                        }
                    }
                    "finishSettingsWrite" -> reply(result, engine.finishSurfaceSettingsWrite(owner,
                        arguments?.get("token") as? String ?: throw IllegalArgumentException()))
                    "accept" -> {
                        val selection = selection(arguments)
                        reply(result, engine.acceptSnapshotLoad(required(arguments, "load"),
                            long(arguments, "generation"), selection?.versions,
                            selection?.attemptClockEras.orEmpty(), selection?.payloadOrders.orEmpty(),
                            selection?.emptyCacheOrders.orEmpty()) { store.retireRenewal() })
                    }
                    "issue" -> {
                        val selection = selection(arguments)
                        reply(result, engine.issueWidgetPublication(owner, required(arguments, "load"),
                            long(arguments, "generation"), required(arguments, "settingsRevision"),
                            store.sequence() ?: 0L, selection?.versions, selection?.attemptClockEras.orEmpty(),
                            selection?.payloadOrders.orEmpty(), selection?.emptyCacheOrders.orEmpty(),
                        ))
                    }
                    else -> scoped(call.method, arguments ?: throw IllegalArgumentException(), result)
                }
            } catch (_: IllegalArgumentException) {
                main.post { if (attached) result.error("invalid_widget_publication", "Invalid widget publication.", null) }
            } catch (_: Exception) {
                main.post { if (attached) result.error("widget_storage_unavailable", "Widget storage unavailable.", null) }
            }
        }
    }

    /** Publication and STALE writes hold a mode effect, so a switch waits for their commit. */
    private fun scoped(method: String, arguments: Map<*, *>, result: MethodChannel.Result) {
        val generation = long(arguments, "generation")
        val effect = UUID.randomUUID().toString()
        var ticket = if (method == "publish") long(arguments, "ticket") else null
        try {
            val lease = generation?.let { engine.enterEffect(effect, it) }
            if (generation != null && lease == null) {
                main.post { if (attached) result.error("widget_publication_retired", "Data mode changed.", null) }
                return
            }
            val saved = try {
                val mode = lease?.let { PhoneWidgetPublicationStore.modeFrom(engine.readMode()) }
                if (method == "publish") {
                    // Fixture writes carry no ticket; they still supersede every older one.
                    val proven = ticket != null
                    val issued = ticket ?: engine.reserveWidgetPublication(owner, store.sequence() ?: 0L)
                    ticket = issued
                    store.publish(arguments, mode, issued, engine, proven)
                } else store.markStale(mode, required(arguments, "observed"), engine)
            } finally {
                if (lease != null) engine.exitEffect(effect, lease, false)
            }
            reply(result, saved)
        } finally {
            // A publication that exits before its commit attempt must not block STALE.
            ticket?.let { engine.retireWidgetPublication(owner, it) }
        }
    }

    /** This app's installed home-screen widget ids. */
    private fun installedWidgets(): Set<String> {
        val manager = AppWidgetManager.getInstance(context)
        return manager.installedProviders.filter { it.provider.packageName == context.packageName }
            .flatMap { manager.getAppWidgetIds(it.provider).asList() }.mapTo(HashSet()) { it.toString() }
    }

    private fun long(arguments: Map<*, *>?, key: String) = (arguments?.get(key) as? Number)?.toLong()

    private fun required(arguments: Map<*, *>?, key: String) = long(arguments, key) ?: throw IllegalArgumentException()

    private fun selection(arguments: Map<*, *>?) = (arguments?.get("selection") as? Map<*, *>)?.let(::SelectionProof)

    private fun reply(result: MethodChannel.Result, value: Any?) {
        main.post { if (attached) result.success(value) }
    }

    fun detach() {
        attached = false
        channel.setMethodCallHandler(null)
        executor.execute { engine.detach(owner) }
    }

    private companion object {
        val executor = Executors.newSingleThreadExecutor()
        val METHODS = setOf("beginLoad", "established", "awaitingDelivery", "beginSettingsWrite", "finishSettingsWrite",
            "accept", "issue", "publish", "markStale")
    }
}
