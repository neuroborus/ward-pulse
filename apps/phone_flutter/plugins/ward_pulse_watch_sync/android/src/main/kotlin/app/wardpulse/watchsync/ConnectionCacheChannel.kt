package app.wardpulse.watchsync

import android.content.Context
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.UUID
import java.util.concurrent.Executors

/** Registered for every engine, including a fresh WorkManager engine. */
internal class ConnectionCacheChannel(context: Context, messenger: BinaryMessenger) : MethodChannel.MethodCallHandler {
    private val owner = UUID.randomUUID().toString()
    private val main = Handler(Looper.getMainLooper())
    private val channel = MethodChannel(messenger, "app.wardpulse/connection_cache")
    private val appContext = context.applicationContext
    private val engine = engine(appContext)
    private var attached = true
    init { channel.setMethodCallHandler(this) }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        executor.execute {
            try {
                if (call.method == "validAll") {
                    val versions = call.argument<Map<String, Map<String, String>>>("versions")
                        ?: error("Versions required.")
                    val attemptEras = call.argument<Map<String, Number>>("attemptClockEras")
                        ?.mapValues { it.value.toLong() }.orEmpty()
                    val payloadOrders = call.argument<Map<String, Map<String, Any>>>("payloadOrders").orEmpty()
                    val emptyOrders = call.argument<Map<String, String>>("emptyCacheOrders").orEmpty()
                    val recoveryRevision = call.argument<Number>("recoveryPreferenceRevision")?.toLong()
                    val recoveryGeneration = call.argument<Number>("recoveryModeGeneration")?.toLong()
                    deliver(result, engine.validAll(versions, attemptEras, payloadOrders, emptyOrders,
                        recoveryRevision, recoveryGeneration))
                    return@execute
                }
                if (dataMode(call, result) || recoveryDelivery(call, result)) return@execute
                val connection = call.argument<String>("connection") ?: error("Connection required.")
                val expected = call.argument<Map<String, String>>("expected")
                val generation = call.argument<Number>("generation")?.toLong()
                when (call.method) {
                    "acquire" -> engine.acquire(owner, connection, call.argument<String>("action") ?: error("Action required."),
                        expected, call.argument<String>("fetchTicket"), generation, call.argument<String>("settlementLease"),
                        { value -> deliver(result, value) }, { fail(result) })
                    "acquireFetch" -> engine.acquireFetch(owner, connection, generation,
                        { value -> deliver(result, value) }, { fail(result) })
                    "validFetch" -> deliver(result, engine.validFetch(owner, connection,
                        call.argument<String>("fetchTicket") ?: error("Fetch ticket required."),
                        call.argument<Boolean>("forAdmission") == true))
                    "claimAutomatic" -> deliver(result, engine.claimAutomatic(owner, connection,
                        call.argument<String>("fetchTicket") ?: error("Fetch ticket required."), expected ?: error("Version required."),
                        call.argument<Number>("intervalMillis")?.toLong() ?: error("Interval required."),
                        call.argument<Boolean>("cacheOnly") == true))
                    "stampFetch" -> deliver(result, engine.stampFetch(owner, connection,
                        call.argument<String>("fetchTicket") ?: error("Fetch ticket required."), expected ?: error("Version required.")))
                    "releaseFetch" -> deliver(result, engine.releaseFetch(owner, connection,
                        call.argument<String>("fetchTicket") ?: error("Fetch ticket required."),
                        call.argument<Number>("reportAtMillis")?.toLong()))
                    "prepareMigration" -> deliver(result, engine.prepareMigration(owner, connection, call.argument<String>("lease") ?: error("Lease required.")))
                    "finish" -> deliver(result, engine.finish(owner, connection, call.argument<String>("lease") ?: error("Lease required."),
                        call.argument<String>("operation") ?: error("Operation required."), call.argument<String>("identity")))
                    "queueLegacyCleanup" -> { engine.queueLegacyCleanup(owner, connection, call.argument<String>("lease") ?: error("Lease required.")); deliver(result, null) }
                    "acknowledgeCleanup" -> deliver(result, engine.acknowledgeCleanup(owner, connection, call.argument<String>("lease") ?: error("Lease required."), call.argument<List<String>>("cleaned") ?: emptyList()))
                    "readNotice" -> deliver(result, engine.readNotice(connection))
                    "dismissNotice" -> deliver(result, engine.dismissNotice(connection, call.argument<String>("eventId") ?: error("Event required.")))
                    "valid" -> deliver(result, engine.valid(connection, expected ?: error("Version required.")))
                    "ownsAutomatic" -> deliver(result, engine.ownsAutomatic(connection, expected ?: error("Version required.")))
                    "readSnapshot" -> {
                        val version = expected ?: error("Version required.")
                        val ordered = call.argument<Boolean>("ordered") == true
                        val row = engine.readSnapshotPair(connection, version,
                            ordered && call.argument<Boolean>("forSelection") == true, generation)
                        deliver(result, if (ordered) row else row["snapshot"])
                    }
                    "writeSnapshot" -> {
                        val version = expected ?: error("Version required.")
                        val snapshot = call.argument<String>("snapshot") ?: error("Snapshot required.")
                        val generatedAt = call.argument<Number>("generatedAt")?.toLong() ?: error("Timestamp required.")
                        val ordered = call.argument<Boolean>("ordered") == true
                        val stamp = if (ordered) call.argument<String>("stamp") else null
                        val write = engine.writeSnapshotOrdered(owner, connection, version, snapshot, generatedAt, stamp, generation)
                        deliver(result, if (ordered) write else write["status"] == "stored")
                    }
                    "upgradeSnapshotTimestamp" -> deliver(result, engine.upgradeSnapshotTimestamp(connection, expected ?: error("Version required."),
                        call.argument<String>("snapshot") ?: error("Snapshot required."),
                        call.argument<Number>("generatedAt")?.toLong() ?: error("Timestamp required."), generation))
                    "clearSnapshot" -> { engine.clearSnapshot(connection, expected, generation); deliver(result, null) }
                    else -> main.post { if (attached) result.notImplemented() }
                }
            } catch (_: Exception) { fail(result) }
        }
    }
    /** Data-mode calls are process-wide and carry no connection. */
    private fun dataMode(call: MethodCall, result: MethodChannel.Result): Boolean {
        fun generation() = call.argument<Number>("generation")?.toLong() ?: error("Generation required.")
        when (call.method) {
            "readMode" -> deliver(result, engine.readMode())
            "beginModeImport" -> engine.beginModeImport(owner, { token -> deliver(result, token) }, { fail(result) })
            "finishModeImport" -> {
                engine.finishModeImport(owner, call.argument<String>("token") ?: error("Import token required."),
                    call.argument<Boolean>("legacyMock"))
                deliver(result, null)
            }
            "beginOperation" -> if (call.argument<Boolean>("waitForSwitch") == true) {
                engine.beginAfterSwitch(owner, { value -> deliver(result, value) }, { fail(result) })
            } else {
                deliver(result, engine.beginOperation())
            }
            "operationCurrent" -> deliver(result, engine.operationCurrent(generation()))
            "enterEffect" -> deliver(result, engine.enterEffect(owner, generation(), call.argument<Boolean>("settlement") == true))
            "exitEffect" -> {
                engine.exitEffect(owner, call.argument<String>("lease") ?: error("Lease required."),
                    call.argument<Boolean>("unresolved") == true)
                deliver(result, null)
            }
            "switchMode" -> engine.switchMode(owner, call.argument<String>("mode") ?: error("Mode required."),
                { value ->
                    deliver(result, value)
                    // The committed mode replaces the outgoing summary before any new publication.
                    main.post { WatchPublisher.process.reconcile(appContext) }
                }, { error ->
                    // A put held while the switch drained resumes under the unchanged record.
                    main.post { WatchPublisher.process.reconcile(appContext) }
                    if (error is ConnectionCacheEngine.ModeWriteFailure) {
                        main.post {
                            if (attached) result.error("data_mode_write_failed", "Could not save data mode.",
                                error.unresolvedStorageFailure)
                        }
                    } else fail(result)
                })
            else -> return false
        }
        return true
    }
    /** Recovery delivery state is process-wide and carries no connection. */
    private fun recoveryDelivery(call: MethodCall, result: MethodChannel.Result): Boolean {
        fun occurrences() = call.argument<List<String>>("occurrences") ?: error("Occurrences required.")
        when (call.method) {
            "beginRecoveryPreferenceWrite" -> deliver(result, engine.beginRecoveryPreferenceWrite(owner))
            "finishRecoveryPreferenceWrite" -> {
                engine.finishRecoveryPreferenceWrite(owner, call.argument<String>("token") ?: error("Token required."))
                deliver(result, null)
            }
            "readRecoveryPreferenceRevision" -> deliver(result, engine.readRecoveryPreferenceRevision())
            "recoveryDeliveryCurrent" -> deliver(result, engine.recoveryDeliveryCurrent(
                call.argument<Number>("revision")?.toLong() ?: error("Revision required."),
                call.argument<Number>("generation")?.toLong()))
            "readUnrecordedRecoveries" -> deliver(result, engine.readUnrecordedRecoveries())
            "recordUnrecordedRecoveries" -> { engine.recordUnrecordedRecoveries(occurrences()); deliver(result, null) }
            "forgetUnrecordedRecoveries" -> { engine.forgetUnrecordedRecoveries(occurrences()); deliver(result, null) }
            else -> return false
        }
        return true
    }
    private fun deliver(result: MethodChannel.Result, value: Any?) {
        main.post { if (attached) result.success(value) }
    }
    private fun fail(result: MethodChannel.Result) {
        main.post { if (attached) result.error("connection_storage_unavailable", "Connection storage unavailable.", null) }
    }
    fun detach() {
        attached = false
        channel.setMethodCallHandler(null)
        executor.execute { engine.detach(owner) }
    }
    companion object {
        private val executor = Executors.newSingleThreadExecutor()
        private var shared: ConnectionCacheEngine? = null
        @Synchronized internal fun engine(context: Context): ConnectionCacheEngine {
            shared?.let { return it }
            // Only Flutter Debug may honor Debug Mock data. Profile is debuggable
            // too, so the embedding's per-mode build constant decides.
            val mockAllowed = io.flutter.BuildConfig.DEBUG
            return ConnectionCacheEngine(backend(context, "wardpulse.connection-cache.v1"),
                backend(context, "wardpulse.data-mode.v1"), { System.currentTimeMillis() }, mockAllowed).also { shared = it }
        }
        /** An empty tap follows the legacy rule; a v10 body must name the current owner. */
        fun captureWatchRefresh(context: Context, payload: ByteArray?, captured: (Map<String, Any>?) -> Unit) {
            executor.execute {
                val operation = runCatching {
                    val engine = engine(context.applicationContext)
                    if (payload == null || payload.isEmpty()) {
                        engine.captureLegacyWatchRefresh(payload)
                    } else {
                        orderedRefresh(payload)?.let { (installId, generation) ->
                            engine.captureWatchRefresh(installId, generation)
                        }
                    }
                }.getOrNull()
                Handler(Looper.getMainLooper()).post { captured(operation) }
            }
        }
        fun finishPublication(engine: ConnectionCacheEngine, owner: String, lease: String) {
            executor.execute { engine.exitEffect(owner, lease, false) }
        }
        private fun backend(context: Context, name: String): ConnectionCacheEngine.Backend {
            // Opened on first use: unscoped work never loads the mode file.
            val preferences by lazy { context.getSharedPreferences(name, Context.MODE_PRIVATE) }
            return object : ConnectionCacheEngine.Backend {
                override fun read(): Map<String, String> = preferences.all.mapValues { (_, value) ->
                    value as? String ?: error("Invalid connection storage.")
                }
                override fun commit(values: Map<String, String>): Boolean {
                    val editor = preferences.edit().clear()
                    values.forEach { (key, value) -> editor.putString(key, value) }
                    return editor.commit()
                }
            }
        }
    }
}
