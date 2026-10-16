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
    private val engine = engine(context.applicationContext)
    private var attached = true
    init { channel.setMethodCallHandler(this) }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        executor.execute {
            try {
                if (call.method == "validAll") {
                    deliver(result, engine.validAll(call.argument<Map<String, Map<String, String>>>("versions") ?: error("Versions required.")))
                    return@execute
                }
                val connection = call.argument<String>("connection") ?: error("Connection required.")
                val expected = call.argument<Map<String, String>>("expected")
                when (call.method) {
                    "acquire" -> engine.acquire(owner, connection, call.argument<String>("action") ?: error("Action required."), expected, call.argument<String>("fetchTicket"),
                        { value -> deliver(result, value) }, { failure -> fail(result) })
                    "acquireFetch" -> engine.acquireFetch(owner, connection) { value -> deliver(result, value) }
                    "validFetch" -> deliver(result, engine.validFetch(owner, connection, call.argument<String>("fetchTicket") ?: error("Fetch ticket required.")))
                    "releaseFetch" -> { engine.releaseFetch(owner, connection, call.argument<String>("fetchTicket") ?: error("Fetch ticket required.")); deliver(result, null) }
                    "prepareMigration" -> deliver(result, engine.prepareMigration(owner, connection, call.argument<String>("lease") ?: error("Lease required.")))
                    "finish" -> deliver(result, engine.finish(owner, connection, call.argument<String>("lease") ?: error("Lease required."),
                        call.argument<String>("operation") ?: error("Operation required."), call.argument<String>("identity")))
                    "queueLegacyCleanup" -> { engine.queueLegacyCleanup(owner, connection, call.argument<String>("lease") ?: error("Lease required.")); deliver(result, null) }
                    "acknowledgeCleanup" -> deliver(result, engine.acknowledgeCleanup(owner, connection, call.argument<String>("lease") ?: error("Lease required."), call.argument<List<String>>("cleaned") ?: emptyList()))
                    "valid" -> deliver(result, engine.valid(connection, expected ?: error("Version required.")))
                    "readSnapshot" -> deliver(result, engine.readSnapshot(connection, expected ?: error("Version required.")))
                    "writeSnapshot" -> deliver(result, engine.writeSnapshot(connection, expected ?: error("Version required."),
                        call.argument<String>("snapshot") ?: error("Snapshot required."), call.argument<Number>("generatedAt")?.toLong() ?: error("Timestamp required.")))
                    "upgradeSnapshotTimestamp" -> deliver(result, engine.upgradeSnapshotTimestamp(connection, expected ?: error("Version required."),
                        call.argument<String>("snapshot") ?: error("Snapshot required."), call.argument<Number>("generatedAt")?.toLong() ?: error("Timestamp required.")))
                    "clearSnapshot" -> { engine.clearSnapshot(connection, expected); deliver(result, null) }
                    else -> main.post { if (attached) result.notImplemented() }
                }
            } catch (_: Exception) { fail(result) }
        }
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
        @Synchronized private fun engine(context: Context): ConnectionCacheEngine {
            shared?.let { return it }
            val preferences = context.getSharedPreferences("wardpulse.connection-cache.v1", Context.MODE_PRIVATE)
            return ConnectionCacheEngine(object : ConnectionCacheEngine.Backend {
                override fun read(): Map<String, String> = preferences.all.mapValues { (_, value) ->
                    value as? String ?: error("Invalid connection storage.")
                }
                override fun commit(values: Map<String, String>): Boolean {
                    val editor = preferences.edit().clear()
                    values.forEach { (key, value) -> editor.putString(key, value) }
                    return editor.commit()
                }
            }).also { shared = it }
        }
    }
}
