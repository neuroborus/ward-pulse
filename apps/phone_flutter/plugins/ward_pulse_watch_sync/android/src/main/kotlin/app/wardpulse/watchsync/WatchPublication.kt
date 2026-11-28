package app.wardpulse.watchsync

import android.content.Context
import android.content.SharedPreferences
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.util.JsonReader
import android.util.JsonToken
import android.util.Log
import com.google.android.gms.wearable.DataItem
import com.google.android.gms.wearable.DataMapItem
import com.google.android.gms.wearable.PutDataMapRequest
import com.google.android.gms.wearable.Wearable
import java.io.StringReader
import java.nio.ByteBuffer
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone
import java.util.UUID
import org.json.JSONArray
import org.json.JSONObject

/**
 * The watch Data Item this install wants Wear to hold: the v9 [payload] projection and the v10
 * [summary]. [installId] and [generation] are null for a v9-only publication made before the
 * data-mode record existed. [placeholder] marks the empty summary a transition left until real
 * input replaces it. [selection] is the report or failure selection proof, as JSON, that every
 * actual put proves again. [retired] records durably that a settings save began after it was
 * built, so a new process neither puts it nor treats it as established; real input rebuilds it.
 */
data class WatchPublication(
    val sequence: Long,
    val installId: String?,
    val generation: Long?,
    val payload: String,
    val summary: String?,
    val placeholder: Boolean = false,
    val selection: String? = null,
    val retired: Boolean = false,
) {
    internal fun proof(): SelectionProof? = selection?.let { SelectionProof(JSONObject(it).toMap()) }
}

/**
 * The desired publication, which survives process death. Its acknowledgement does not: a new
 * process reasserts the desired item, since an orphaned put may have overwritten it.
 *
 * Only a confirmed write is desired. SharedPreferences keeps a failed commit in memory, so
 * [write] restores the previous item; neither a put, an owner reply nor the order floor reads
 * the unconfirmed candidate, in this process or after it dies.
 */
class WatchPublicationStore(private val preferences: SharedPreferences) {
    constructor(context: Context) :
        this(context.applicationContext.getSharedPreferences(NAME, Context.MODE_PRIVATE))

    fun read(): WatchPublication? = synchronized(monitor) {
        val sequence = preferences.getLong(SEQUENCE, 0L)
        val payload = preferences.getString(PAYLOAD, null)
        if (sequence <= 0L || payload == null) return null
        val installId = preferences.getString(INSTALL_ID, null)
        WatchPublication(
            sequence = sequence,
            installId = installId,
            generation = installId?.let { preferences.getLong(GENERATION, -1L) },
            payload = payload,
            summary = preferences.getString(SUMMARY, null),
            placeholder = preferences.getBoolean(PLACEHOLDER, false),
            selection = preferences.getString(SELECTION, null),
            retired = preferences.getBoolean(RETIRED, false),
        )
    }

    /** The newest order this install published; a new process allocates above it. */
    fun lastSequence(): Long = synchronized(monitor) { preferences.getLong(SEQUENCE, 0L) }

    fun write(publication: WatchPublication): Boolean = synchronized(monitor) {
        val previous = read()
        if (commit(publication)) return true
        // Best effort on disk; memory takes the previous item even when this commit fails too.
        if (previous == null) preferences.edit().clear().commit() else commit(previous)
        false
    }

    /**
     * Durably retires the desired item's settings as a settings save begins, before it writes;
     * false when that cannot be confirmed, and the save must not start. An empty placeholder
     * carries no settings and stays sendable.
     */
    fun retireSettings(): Boolean = synchronized(monitor) {
        val desired = read()
        if (desired == null || desired.placeholder || desired.retired) return true
        if (preferences.edit().putBoolean(RETIRED, true).commit()) return true
        preferences.edit().putBoolean(RETIRED, false).commit()
        false
    }

    /**
     * Records that Wear stores an item of [installId]'s [generation], so it has left the previous
     * mode: its owner request named that order as the one it stores, whatever the desired item's
     * order and whether a settings save retired it. It survives process death, and a late proof
     * of an older generation never replaces a newer one. Neither a completed put, this node's own
     * copy nor an order Wear read but did not store records anything, since a disconnected watch
     * receives only the latest item, which a settings save may retire before Wear stores it.
     * The record is per phone install, not per watch: with two paired watches, one watch's proof
     * also ends the fallback another, still showing the previous mode, is owed. Only a single
     * paired watch is supported here.
     *
     * A watch that speaks only v9 sends no owner request, so it never records one: after a
     * transition, a retired item with no replacement is then replaced by the empty summary,
     * whose v9 projection is an empty Live summary, until real input arrives. Generation 0 never
     * owes it, so a v9 watch keeps ordinary capacity handling until a mode transition.
     */
    fun markDelivered(installId: String, generation: Long) {
        synchronized(monitor) {
            if (preferences.getString(DELIVERED_INSTALL_ID, null) == installId &&
                preferences.getLong(DELIVERED_GENERATION, -1L) >= generation
            ) {
                return
            }
            preferences.edit()
                .putString(DELIVERED_INSTALL_ID, installId)
                .putLong(DELIVERED_GENERATION, generation)
                .commit()
        }
    }

    /** Whether Wear proved it stores an item of [installId]'s [generation], in any process. */
    fun delivered(installId: String, generation: Long): Boolean = synchronized(monitor) {
        preferences.getString(DELIVERED_INSTALL_ID, null) == installId &&
            preferences.getLong(DELIVERED_GENERATION, -1L) == generation
    }

    private fun commit(publication: WatchPublication): Boolean =
        preferences.edit().run {
            putLong(SEQUENCE, publication.sequence)
            putString(PAYLOAD, publication.payload)
            if (publication.summary == null) remove(SUMMARY) else putString(SUMMARY, publication.summary)
            if (publication.installId == null) {
                remove(INSTALL_ID)
                remove(GENERATION)
            } else {
                putString(INSTALL_ID, publication.installId)
                putLong(GENERATION, publication.generation ?: -1L)
            }
            putBoolean(PLACEHOLDER, publication.placeholder)
            if (publication.selection == null) remove(SELECTION) else putString(SELECTION, publication.selection)
            putBoolean(RETIRED, publication.retired)
            // An acknowledgement persisted by an earlier build would skip a reassertion.
            remove(LEGACY_ACKNOWLEDGED)
            commit()
        }

    private companion object {
        // Every store instance shares the file, read from binder threads too.
        val monitor = Any()
        const val NAME = "wardpulse.watch-publication.v1"
        const val SEQUENCE = "sequence"
        const val PAYLOAD = "payload"
        const val SUMMARY = "summary"
        const val INSTALL_ID = "installId"
        const val GENERATION = "generation"
        const val PLACEHOLDER = "placeholder"
        const val SELECTION = "selection"
        const val RETIRED = "settingsRetired"
        const val DELIVERED_INSTALL_ID = "deliveredInstallId"
        const val DELIVERED_GENERATION = "deliveredGeneration"
        const val LEGACY_ACKNOWLEDGED = "acknowledged"
    }
}

/**
 * Durably retires, as a settings save begins, what the saved settings feed: launcher rows through
 * [retireLauncher] always, and [watch]'s desired item only when [watchSettings] change. A
 * launcher-only save leaves the watch item answerable to owner proofs, since its content stands;
 * false when a retirement cannot be confirmed, and the save must not start.
 */
fun retireSurfaceSettings(
    retireLauncher: () -> Boolean,
    watch: WatchPublicationStore,
    watchSettings: Boolean,
): Boolean = retireLauncher() && (!watchSettings || watch.retireSettings())

/** The v9 payload and v10 summary of the watch Data Item this node holds. */
data class WatchHeldItem(val payload: String?, val summary: String?)

/** The watch Data Item on the Data Layer. */
interface WatchTransport {
    /** Puts the item; [done] runs on the main thread once the put settles. */
    fun put(context: Context, publication: WatchPublication, done: (Exception?) -> Unit)

    /**
     * Reads this node's own item; [done] runs on the main thread with it, or null without one,
     * and never runs when the lookup fails.
     */
    fun readHeld(context: Context, done: (WatchHeldItem?) -> Unit)
}

/** A load or settings change retired the summary before its durable write. */
class WatchSummarySupersededException : IllegalStateException("Watch summary input changed.")

/** How [admitWatchSend] answered a send. */
enum class WatchAdmission { ADMITTED, SUPERSEDED, RETIRED }

/**
 * Admits the send of [ticket] with its selection proof ([ConnectionCacheEngine.admitWatchSummary]).
 * It is superseded when a newer arrival was already admitted, which readiness completing out of
 * order allows, or its accepted load or settings revision was replaced; a fresh read answers
 * either, since this summary never reaches the transport. A stale selection retires it.
 */
fun admitWatchSend(
    engine: ConnectionCacheEngine,
    ticket: Long,
    versions: Map<String, Map<String, String>>?,
    attemptClockEras: Map<String, Long>,
    payloadOrders: Map<String, Map<String, *>>,
    emptyCacheOrders: Map<String, String>,
): WatchAdmission =
    when (engine.admitWatchSummary(ticket, versions, attemptClockEras, payloadOrders, emptyCacheOrders)) {
        true -> WatchAdmission.ADMITTED
        false -> WatchAdmission.SUPERSEDED
        null -> if (engine.watchSummaryCurrent(ticket)) WatchAdmission.RETIRED else WatchAdmission.SUPERSEDED
    }

/**
 * A put queue for the watch Data Item; [process] is the process-wide one. Main thread only.
 *
 * One put is in flight at a time. A submission is admitted and persisted as the desired
 * publication at once, even while an earlier put settles; the newest desired item is put once
 * it does, so a late completion can never overwrite it and process death keeps the replacement.
 * The write itself is refused once a settings save or newer load retired its input
 * ([ConnectionCacheEngine.commitWatchSummary]), and a settings save durably retires the written
 * item, so a new process neither reasserts nor counts it as established.
 * Every actual put is leased against mode commits and proves its install, generation,
 * selection, accepted load and settings revision again ([ConnectionCacheEngine.enterWatchSend]);
 * a retired or expired one is not sent. Only the matching sequence is acknowledged, in memory.
 * A transient failure retries with bounded backoff; after that the publication stays pending
 * until startup, resume, an explicit sync, a Wear route proof or a worker engine resumes it.
 *
 * A submission settles with its own put's result only once that put started. One replaced
 * before then, or whose input a settings save or newer load retired, settles with
 * [WatchSummarySupersededException]; one whose lease is refused otherwise settles as unavailable.
 *
 * `WardPulseSync` reports only a submitted order's first successful put, which the paired gate
 * reads as a fresh publication. Reassertions of an item Wear may already hold, and other
 * diagnostics, use [DIAGNOSTIC_TAG].
 *
 * [storeFor], [engineFor] and [transport] are the durable desired record, the process engine and
 * the Wearable Data Layer, for puts and the local-item lookup alike. Device tests construct a
 * queue over their own; a new queue holds none of an earlier one's put state, as after process
 * death.
 */
class WatchPublisher(
    private val storeFor: (Context) -> WatchPublicationStore,
    private val engineFor: (Context) -> ConnectionCacheEngine,
    private val transport: WatchTransport,
) {
    private var inFlight = false
    // The submission whose put has not started, and the one whose put is in flight.
    private var waiting: Pending? = null
    private var sending: Pending? = null
    // Orders submitted to this queue that no put has delivered yet.
    private val fresh = mutableSetOf<Long>()
    private var retries = 0
    private var retry: Runnable? = null

    private class Pending(val sequence: Long, val settled: (Exception?) -> Unit)

    /**
     * Makes [publication] desired once its write is confirmed; [settled] runs once its put settles,
     * or with [WatchSummarySupersededException] when its input was retired before the write or a
     * newer submission replaced it before its put started. A put in flight settles first.
     */
    fun submit(context: Context, publication: WatchPublication, settled: (Exception?) -> Unit) {
        val appContext = context.applicationContext
        val store = storeFor(appContext)
        val written = try {
            engineFor(appContext).commitWatchSummary(publication.sequence) { store.write(publication) }
        } catch (error: RuntimeException) {
            settled(error)
            return
        }
        if (written != true) {
            settled(if (written == null) WatchSummarySupersededException() else
                IllegalStateException("Watch publication storage failed."))
            return
        }
        // A submission replaced before its put never reaches the transport.
        waiting?.settled?.invoke(WatchSummarySupersededException())
        waiting = Pending(publication.sequence, settled)
        fresh.add(publication.sequence)
        restartRetries()
        pump(appContext)
    }

    /** Resumes a pending or retrying put; callable from any thread. */
    fun resume(context: Context) {
        val appContext = context.applicationContext
        main.post {
            restartRetries()
            pump(appContext)
        }
    }

    /**
     * Replaces a desired publication the durable mode record says is owed, missing after a
     * transition or retired by one, with an empty summary of the current generation, so a failed
     * Live load or invalid ring choices cannot leave Demo on the watch. A settings save that
     * retires a transition's item before Wear proved it stores one of its generation owes it again.
     * Otherwise resumes a pending put, which a new process reasserts. Main thread.
     */
    fun reconcile(context: Context) {
        val appContext = context.applicationContext
        try {
            val engine = engineFor(appContext)
            val store = storeFor(appContext)
            val desired = store.read()
            if (!engine.watchPublicationOwed(desired?.installId, desired?.generation) &&
                !retiredBeforeDelivery(store, desired)
            ) {
                resume(appContext)
                return
            }
            val mode = engine.readMode()
            val installId = mode["installId"] as String
            val generation = (mode["generation"] as Number).toLong()
            val owner = UUID.randomUUID().toString()
            val lease = engine.enterEffect(owner, generation) ?: return
            // The lease orders the write against mode commits; the put takes its own.
            try {
                val ticket = engine.reserveWatchSummary(store.lastSequence())
                if (!engine.claimWatchSummary(ticket)) return
                submit(appContext, emptyPublication(installId, generation, mode["mode"] as String, ticket)) {}
            } finally {
                ConnectionCacheChannel.finishPublication(engine, owner, lease)
            }
        } catch (error: RuntimeException) {
            Log.w(DIAGNOSTIC_TAG, "Watch summary reconciliation unavailable (${error.javaClass.simpleName}).")
        }
    }

    /**
     * Whether a settings save retired [desired], of a transition's generation, before Wear proved
     * it stores an item of that generation ([WatchPublicationStore.markDelivered]), so the watch
     * may still hold the previous mode; a watch that never proves an order, as a v9-only one,
     * always may. Once it did, a retired item keeps the last valid summary on the watch until
     * real input replaces it, as in the same mode.
     */
    private fun retiredBeforeDelivery(store: WatchPublicationStore, desired: WatchPublication?): Boolean {
        val installId = desired?.installId ?: return false
        val generation = desired.generation ?: return false
        return desired.retired && generation > 0L && !store.delivered(installId, generation)
    }

    /**
     * Whether the desired publication is a real, sendable v10 summary of the current generation
     * whose settings no save retired, in this process or durably before it, and whose selection
     * still holds. A newer accepted load that does not publish keeps, and adopts, a summary
     * built from an older one ([ConnectionCacheEngine.watchSummaryEstablished]).
     */
    fun established(context: Context): Boolean {
        val appContext = context.applicationContext
        resume(appContext)
        val engine = engineFor(appContext)
        val mode = engine.readMode()
        if (mode["initialized"] != true || mode["switching"] == true) return true
        val desired = storeFor(appContext).read() ?: return false
        val proof = desired.proof()
        return !desired.placeholder && !desired.retired && desired.installId == mode["installId"] &&
            desired.generation == (mode["generation"] as Number).toLong() &&
            (proof == null || engine.validAll(proof.versions, proof.attemptClockEras, proof.payloadOrders,
                proof.emptyCacheOrders)) &&
            engine.watchSummaryEstablished(desired.sequence)
    }

    /**
     * Answers a Wear route proof ([ownerRequest]) with the current install and generation and the
     * desired order; null when malformed, without a v10 publication, or while a settings save has
     * retired the desired item and no replacement exists, so Wear verifies neither it nor the Data
     * Item still holding it. An item of an older generation is answered with the current one, so
     * Wear refuses it. A proof naming a stored item of the current install and generation records
     * that Wear left the previous mode ([WatchPublicationStore.markDelivered]), before the
     * reconciliation it requests runs and even without a reply; a bare nonce names none. The proof
     * also checks this node's item ([checkHeld]).
     */
    fun ownerReply(context: Context, request: ByteArray?): ByteArray? {
        val proof = request?.let(::ownerRequest) ?: return null
        val appContext = context.applicationContext
        try {
            val mode = engineFor(appContext).readMode()
            val installId = mode["installId"] as? String ?: return null
            val generation = (mode["generation"] as Number).toLong()
            val store = storeFor(appContext)
            proof.held?.takeIf { it.installId == installId && it.generation == generation }?.let {
                runCatching { store.markDelivered(it.installId, it.generation) }
            }
            val desired = store.read()?.takeIf { it.installId != null && !it.retired } ?: return null
            return JSONObject()
                .put("nonce", proof.nonce)
                .put("installId", installId)
                .put("generation", generation)
                .put("sequence", desired.sequence)
                .toString()
                .toByteArray(Charsets.UTF_8)
        } finally {
            main.post {
                checkHeld(appContext)
                reconcile(appContext)
            }
        }
    }

    /** Reads this node's own item: an acknowledged desired item it no longer holds is put again. */
    private fun checkHeld(context: Context) {
        try {
            val desired = storeFor(context).read() ?: return
            val engine = engineFor(context)
            if (!engine.watchSummaryAcknowledged(desired.sequence)) return
            transport.readHeld(context) { held ->
                if (held == WatchHeldItem(desired.payload, desired.summary)) return@readHeld
                engine.reassertWatchSummary(desired.sequence)
                restartRetries()
                pump(context)
            }
        } catch (error: RuntimeException) {
            Log.w(DIAGNOSTIC_TAG, "Watch summary check unavailable (${error.javaClass.simpleName}).")
        }
    }

    private fun restartRetries() {
        retry?.let { main.removeCallbacks(it) }
        retry = null
        retries = 0
    }

    private fun pump(context: Context) {
        if (inFlight || retry != null) return
        val desired = storeFor(context).read() ?: return
        val owner = UUID.randomUUID().toString()
        val (engine, lease) = try {
            val engine = engineFor(context)
            if (engine.watchSummaryAcknowledged(desired.sequence)) return
            val proof = desired.proof()
            engine to desired.takeUnless { it.retired }?.let {
                engine.enterWatchSend(owner, it.sequence, it.installId, it.generation, proof?.versions,
                    proof?.attemptClockEras.orEmpty(), proof?.payloadOrders.orEmpty(), proof?.emptyCacheOrders.orEmpty())
            }
        } catch (error: RuntimeException) {
            settle(context, desired.sequence, error)
            return
        }
        val pending = waiting?.takeIf { it.sequence == desired.sequence }
        if (lease == null) {
            // Retired by a commit, a newer accepted load, a settings save (durably too, before
            // process death) or its expired selection: never sent; reconciliation, a load or a
            // newer submission replaces it. A draining switch reconciles once it settles.
            if (pending != null) {
                waiting = null
                pending.settled(
                    if (desired.retired || !engine.watchSummaryCurrent(desired.sequence)) {
                        WatchSummarySupersededException()
                    } else {
                        IllegalStateException("Watch summary send unavailable.")
                    },
                )
            }
            return
        }
        inFlight = true
        // Its put starts; a newer submission no longer replaces it before the transport.
        if (pending != null) {
            waiting = null
            sending = pending
        }
        val sent = { error: Exception? ->
            ConnectionCacheChannel.finishPublication(engine, owner, lease)
            settle(context, desired.sequence, error)
        }
        try {
            transport.put(context, desired, sent)
        } catch (error: RuntimeException) {
            sent(error)
        }
    }

    private fun settle(context: Context, sequence: Long, error: Exception?) {
        inFlight = false
        val store = storeFor(context)
        // The started put's submission, or a waiting one whose send failed before its put.
        val pending = sending?.takeIf { it.sequence == sequence }?.also { sending = null }
            ?: waiting?.takeIf { it.sequence == sequence }?.also { waiting = null }
        if (error == null) {
            // Only the matching desired sequence is acknowledged.
            if (store.read()?.sequence == sequence) {
                runCatching { engineFor(context).acknowledgeWatchSummary(sequence) }
            }
            retries = 0
            if (fresh.remove(sequence)) {
                Log.i(TAG, "Watch summary queued.")
            } else {
                Log.i(DIAGNOSTIC_TAG, "Watch summary reasserted.")
            }
            // An older order is never put after this one.
            fresh.removeAll { it < sequence }
        } else if (store.read()?.sequence == sequence && retries < BACKOFF_MS.size) {
            val next = Runnable {
                retry = null
                pump(context)
            }
            retry = next
            main.postDelayed(next, BACKOFF_MS[retries++])
        }
        pending?.settled?.invoke(error)
        // A failed put waits for its retry or a resume; a newer desired item is sent now.
        if (error == null || store.read()?.sequence != sequence) pump(context)
    }

    companion object {
        const val DIAGNOSTIC_TAG = "WardPulseWatch"
        private const val TAG = "WardPulseSync"
        private const val DATA_PATH = "/wardpulse/watch-summary"
        private const val PAYLOAD_KEY = "payload"
        private const val SUMMARY_KEY = "summary"
        private const val REVISION_KEY = "revision"
        private val BACKOFF_MS = longArrayOf(1_000L, 5_000L, 30_000L)
        private val main = Handler(Looper.getMainLooper())

        /** The app's queue: its durable desired record, the process engine and the Data Layer. */
        val process = WatchPublisher(
            storeFor = { WatchPublicationStore(it) },
            engineFor = { ConnectionCacheChannel.engine(it) },
            transport = DataLayerTransport,
        )
    }

    private object DataLayerTransport : WatchTransport {
        override fun put(context: Context, publication: WatchPublication, done: (Exception?) -> Unit) {
            val request = PutDataMapRequest.create(DATA_PATH).apply {
                dataMap.putString(PAYLOAD_KEY, publication.payload)
                publication.summary?.let { dataMap.putString(SUMMARY_KEY, it) }
                dataMap.putLong(REVISION_KEY, System.currentTimeMillis())
            }.asPutDataRequest().setUrgent()
            Wearable.getDataClient(context).putDataItem(request).addOnCompleteListener { task ->
                done(if (task.isSuccessful) null else task.exception ?: IllegalStateException())
            }
        }

        override fun readHeld(context: Context, done: (WatchHeldItem?) -> Unit) {
            Wearable.getNodeClient(context).localNode
                .onSuccessTask { node ->
                    val uri = Uri.Builder().scheme("wear").authority(node.id).path(DATA_PATH).build()
                    Wearable.getDataClient(context).getDataItem(uri)
                }
                .addOnSuccessListener { item: DataItem? ->
                    done(item?.let { DataMapItem.fromDataItem(it).dataMap }
                        ?.let { WatchHeldItem(it.getString(PAYLOAD_KEY), it.getString(SUMMARY_KEY)) })
                }
        }
    }
}

private fun JSONObject.toMap(): Map<String, Any?> =
    keys().asSequence().associateWith { key -> get(key).fromJson() }

private fun Any?.fromJson(): Any? = when (this) {
    is JSONObject -> toMap()
    is JSONArray -> List(length()) { get(it).fromJson() }
    JSONObject.NULL -> null
    else -> this
}

/** Adds the owner and order to a v10 body. */
internal fun orderedSummary(body: JSONObject, installId: String, generation: Long, sequence: Long): String =
    body.put("installId", installId).put("generation", generation).put("sequence", sequence).toString()

/** An empty summary of [mode]; its v9 projection never carries Demo and disables Demo refresh. */
internal fun emptyPublication(installId: String, generation: Long, mode: String, sequence: Long): WatchPublication {
    val generatedAt = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", Locale.US)
        .apply { timeZone = TimeZone.getTimeZone("UTC") }
        .format(Date())
    fun body(schemaVersion: Int, dataMode: String, refresh: Boolean) = JSONObject()
        .put("schemaVersion", schemaVersion)
        .put("dataMode", dataMode)
        .put("generatedAt", generatedAt)
        .put("overallStatus", "unknown")
        .put("manualRefreshAllowed", refresh)
        .put("manualRefreshAvailableAt", JSONObject.NULL)
        .put("rings", JSONArray())
        .put("creditsGlance", JSONObject.NULL)
        .put("today", unknownPeriod("today"))
        .put("week", unknownPeriod("week"))
        .put("allowances", JSONArray())
        .put("providers", JSONArray())
        .put("alerts", JSONArray())
        .put("isStale", false)
    val demo = mode == "demo"
    return WatchPublication(
        sequence = sequence,
        installId = installId,
        generation = generation,
        payload = body(LEGACY_SCHEMA_VERSION, if (demo) "live" else mode, refresh = !demo).toString(),
        summary = orderedSummary(body(SCHEMA_VERSION, mode, refresh = true), installId, generation, sequence),
        placeholder = true,
    )
}

private fun unknownPeriod(period: String) = JSONObject()
    .put("period", period)
    .put("spent", JSONObject.NULL)
    .put("limit", JSONObject.NULL)
    .put("remaining", JSONObject.NULL)
    .put("usedPercent", JSONObject.NULL)
    .put("projectedTotal", JSONObject.NULL)
    .put("status", "unknown")

/**
 * A v10 refresh body, validated at native receipt: one complete strict JSON object with exactly
 * one `installId` string and one non-negative integer `generation`; null when malformed.
 */
fun orderedRefresh(payload: ByteArray): Pair<String, Long>? {
    val body = strictObject(payload, REFRESH_MEMBERS) ?: return null
    val installId = body.getValue("installId").takeIf(INSTALL_ID::matches) ?: return null
    val generation = body.getValue("generation").takeIf(GENERATION::matches)?.toLongOrNull() ?: return null
    return Pair(installId, generation)
}

/** The install, generation and order of the v10 item a watch stores. */
data class WatchHeldOrder(val installId: String, val generation: Long, val sequence: Long)

/** A Wear route proof: its [nonce] and the order of the item Wear stores, if it named one. */
data class WatchOwnerRequest(val nonce: String, val held: WatchHeldOrder?)

/**
 * A Wear route proof on `/wardpulse/summary-owner`, validated at native receipt: one complete
 * strict JSON object with exactly a `nonce` and the `installId`, `generation` and `sequence` of
 * the v10 item the watch has stored, which it sends before a commit and again after one. A bare
 * nonce, as Wear sends before it stores a v10 item and an earlier Wear build always sends, is
 * still answered but names no held item. Null when malformed.
 */
fun ownerRequest(payload: ByteArray): WatchOwnerRequest? {
    if (payload.firstOrNull() != '{'.code.toByte()) {
        val nonce = payload.toString(Charsets.UTF_8)
        return if (nonce.isEmpty() || nonce.length > MAX_NONCE_LENGTH) null else WatchOwnerRequest(nonce, null)
    }
    val body = strictObject(payload, OWNER_REQUEST_MEMBERS) ?: return null
    val nonce = body.getValue("nonce").takeIf { it.isNotEmpty() && it.length <= MAX_NONCE_LENGTH } ?: return null
    val installId = body.getValue("installId").takeIf(INSTALL_ID::matches) ?: return null
    val generation = body.getValue("generation").takeIf(GENERATION::matches)?.toLongOrNull() ?: return null
    val sequence = body.getValue("sequence").takeIf(SEQUENCE::matches)?.toLongOrNull() ?: return null
    return WatchOwnerRequest(nonce, WatchHeldOrder(installId, generation, sequence))
}

/**
 * The members of one complete strict JSON object, in valid UTF-8: exactly [members], each once
 * with its token type, as their string or number text; null when malformed. Android's
 * `JSONObject(String)` is lenient: it stops after the first value and keeps the last of
 * duplicate members, so it cannot tell a valid body from one with trailing content.
 * `JsonReader` checks the structure but decodes unsupported escapes, so string syntax is
 * checked first.
 */
private fun strictObject(payload: ByteArray, members: Map<String, JsonToken>): Map<String, String>? = try {
    // Malformed UTF-8 throws rather than decoding to replacement characters.
    val body = Charsets.UTF_8.newDecoder().decode(ByteBuffer.wrap(payload)).toString()
    if (!jsonStringsWellFormed(body)) null else JsonReader(StringReader(body)).use { reader ->
        val values = mutableMapOf<String, String>()
        reader.beginObject()
        while (reader.hasNext()) {
            val name = reader.nextName()
            if (name in values || members[name] != reader.peek()) return@use null
            values[name] = reader.nextString()
        }
        reader.endObject()
        if (reader.peek() != JsonToken.END_DOCUMENT || values.keys != members.keys) null else values
    }
} catch (_: Exception) {
    null
}

/**
 * Whether every string in [json] keeps JSON string syntax: no raw control character, and only
 * the escapes JSON defines. Text outside strings is left to the strict reader.
 */
private fun jsonStringsWellFormed(json: String): Boolean {
    var inString = false
    var index = 0
    while (index < json.length) {
        val char = json[index++]
        when {
            !inString -> inString = char == '"'
            char == '"' -> inString = false
            char < ' ' -> return false
            char == '\\' -> when (json.getOrNull(index++)) {
                '"', '\\', '/', 'b', 'f', 'n', 'r', 't' -> Unit
                'u' -> {
                    if (index + 4 > json.length || !json.substring(index, index + 4).all(::isHexDigit)) return false
                    index += 4
                }
                else -> return false
            }
        }
    }
    return true
}

private fun isHexDigit(char: Char) = char in '0'..'9' || char in 'a'..'f' || char in 'A'..'F'

internal const val LEGACY_SCHEMA_VERSION = 9
internal const val SCHEMA_VERSION = 10
private const val MAX_NONCE_LENGTH = 64
private val INSTALL_ID = Regex("^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$")
private val GENERATION = Regex("^(0|[1-9][0-9]*)$")
private val SEQUENCE = Regex("^[1-9][0-9]*$")
private val REFRESH_MEMBERS = mapOf("installId" to JsonToken.STRING, "generation" to JsonToken.NUMBER)
private val OWNER_REQUEST_MEMBERS = mapOf(
    "nonce" to JsonToken.STRING,
    "installId" to JsonToken.STRING,
    "generation" to JsonToken.NUMBER,
    "sequence" to JsonToken.NUMBER,
)
