package app.wardpulse.wear.sync

import android.content.Context
import android.net.Uri
import android.util.Log
import app.wardpulse.wear.complication.WatchComplicationUpdater
import app.wardpulse.wear.data.SummaryOwner
import app.wardpulse.wear.data.WatchSummaryStore
import app.wardpulse.wear.data.strictJsonObject
import com.google.android.gms.tasks.Tasks
import com.google.android.gms.wearable.DataItem
import com.google.android.gms.wearable.DataMapItem
import com.google.android.gms.wearable.Wearable
import java.util.UUID
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import org.json.JSONObject

/**
 * The summary Data Item one phone node wrote: its v10 value and its v9 projection.
 * [orderedPresent] is whether the v10 key exists at all; present with a null [ordered] means a
 * malformed value, which is refused without reading the v9 projection.
 */
internal data class SummaryItem(
    val host: String,
    val ordered: String?,
    val legacy: String?,
    val orderedPresent: Boolean = ordered != null,
) {
    val eligible: Boolean get() = orderedPresent || legacy != null
}

/** The Data Layer as route resolution reads it. Calls block; never use it on the main thread. */
internal interface SummaryRoute {
    fun connectedHosts(): Set<String>

    /** Every summary item the Data Layer holds, from any host. */
    fun items(): List<SummaryItem>

    /** Rereads the exact item at `wear://[host]/wardpulse/watch-summary`. */
    fun item(host: String): SummaryItem?

    /**
     * Sends [nonce] and the [held] order this watch stores from [host], if any, to it on
     * [WatchDataContract.OWNER_PATH] ([WatchSummaryReconciler.ownerRequest]); null when no reply
     * arrives.
     */
    fun requestOwner(host: String, nonce: String, held: SummaryOwner?): ByteArray?

    /**
     * Names the [held] order this watch has just stored from [host] in a route proof on the same
     * path, best effort; its reply is not read.
     */
    fun reportHeld(host: String, nonce: String, held: SummaryOwner)
}

internal enum class ReconcileOutcome { ACCEPTED, UNCHANGED, REJECTED, UNRESOLVED, SUPERSEDED }

/**
 * Accepts a phone summary only for a resolved route.
 *
 * Data events and reconnects are only signals: every call resolves the route afresh and rereads
 * its item. A v10 item needs a fresh nonce reply from its own host naming the same install and
 * generation at or below the item's order. The request names only the order this watch already
 * stores from that host, and an accepted v10 commit names its new order in a further proof, so
 * the phone never counts an item Wear read but did not store. A v9 item is read only
 * while v10 is absent and the route never established v10 ownership. The exact item is reread
 * and the route resolved again, in that order, before the commit; a replacement the final
 * resolution's item inventory already holds answers in its own attempt.
 *
 * Resolutions are ordered by when they start, before any read: the newest one to need a proof,
 * or to find its route invalid, retires older proofs at the commit itself, while an older read
 * returning late cannot retire a newer proof. Each accepted write is reported once, whichever
 * entry point made it ([report]).
 */
internal class WatchSummaryReconciler(
    private val store: WatchSummaryStore,
    private val route: SummaryRoute,
    private val newNonce: () -> String = { UUID.randomUUID().toString() },
) {
    /**
     * Resolves the reachable bound host, otherwise a unique connected candidate, and rereads its
     * item. An unchanged item for the accepted binding is neither requested nor written, unless
     * [revalidate] (an observed reconnect) asks its owner again: a match stays UNCHANGED, a
     * mismatch is REJECTED, and the stored summary is kept either way.
     */
    fun reconcile(revalidate: Boolean = false): ReconcileOutcome {
        val attempt = store.beginAttempt()
        return try {
            val host = resolveHost() ?: return retire(attempt)
            val item = route.item(host)?.takeIf { it.eligible } ?: return retire(attempt)
            val unchanged = unchanged(item)
            if (unchanged && !revalidate) return ReconcileOutcome.UNCHANGED
            if (item.orderedPresent) {
                // Malformed v10 is refused outright: its v9 projection is not a fallback.
                val ordered = item.ordered ?: return ReconcileOutcome.REJECTED
                return acceptOrdered(host, ordered, unchanged, attempt)
            }
            // v9 carries no owner to ask, so a reconnect has nothing to revalidate.
            if (unchanged) return ReconcileOutcome.UNCHANGED
            val legacy = item.legacy ?: return ReconcileOutcome.REJECTED
            if (store.orderedRoute(host) || store.decodeLegacy(legacy) == null) {
                return ReconcileOutcome.REJECTED
            }
            if (!store.claimAttempt(attempt)) return ReconcileOutcome.SUPERSEDED
            // As for v10, the exact item must still be this v9 value with no v10 field, and a
            // replacement answers in its own attempt; the host must still own the route after that
            // read, since a disconnect during it leaves the item readable from the cache.
            val current = route.item(host)
            recheckRoute(host, current)?.let { return it }
            if (current == null || current.orderedPresent || current.legacy != legacy) {
                return ReconcileOutcome.SUPERSEDED
            }
            settle(store.accept(host, legacy, null, attempt), host, legacy, attempt)
        } catch (_: Exception) {
            ReconcileOutcome.UNRESOLVED
        }
    }

    /**
     * A route found invalid retires any older proof still pending for it; nothing is written.
     * A newer resolution already deciding keeps its proof.
     */
    private fun retire(attempt: Long): ReconcileOutcome {
        store.claimAttempt(attempt)
        return ReconcileOutcome.UNRESOLVED
    }

    private fun unchanged(item: SummaryItem): Boolean {
        val encoded = (if (item.orderedPresent) item.ordered else item.legacy) ?: return false
        return store.unchanged(item.host, encoded)
    }

    /** A resolved route: its host and, unless bound, the inventory items it was resolved from. */
    private class Route(val host: String, val observed: List<SummaryItem>)

    /** A reachable binding is never replaced by another phone's item. */
    private fun resolveRoute(): Route? {
        val connected = route.connectedHosts()
        val bound = store.binding()?.host
        if (bound != null && bound in connected) return Route(bound, emptyList())
        val candidates = route.items().filter { it.host in connected && it.eligible }
        val host = candidates.map { it.host }.distinct().singleOrNull() ?: return null
        return Route(host, candidates)
    }

    private fun resolveHost(): String? = resolveRoute()?.host

    /**
     * Resolves the route again after the commit's exact [current] read: UNRESOLVED unless [host]
     * still owns it, since a disconnect during that read leaves its item readable from the cache,
     * and SUPERSEDED when the inventory an unbound resolution read already holds a replacement,
     * which answers in its own attempt. Null when the commit may proceed.
     */
    private fun recheckRoute(host: String, current: SummaryItem?): ReconcileOutcome? {
        val resolved = resolveRoute()
        if (resolved == null || resolved.host != host) return ReconcileOutcome.UNRESOLVED
        if (resolved.observed.any { it != current }) return ReconcileOutcome.SUPERSEDED
        return null
    }

    private fun acceptOrdered(host: String, ordered: String, unchanged: Boolean, attempt: Long): ReconcileOutcome {
        val decoded = store.decodeOrdered(ordered) ?: return ReconcileOutcome.REJECTED
        // A newer resolution that already decided owns the route; this older read is stale.
        if (!store.claimAttempt(attempt)) return ReconcileOutcome.SUPERSEDED
        val nonce = newNonce()
        val stored = store.binding()?.takeIf { it.host == host }?.owner
        val reply = route.requestOwner(host, nonce, stored)?.let(::ownerReply)
            ?: return ReconcileOutcome.UNRESOLVED
        if (!store.attemptCurrent(attempt)) return ReconcileOutcome.SUPERSEDED
        val (replyNonce, owner) = reply
        if (replyNonce != nonce || owner.installId != decoded.owner.installId ||
            owner.generation != decoded.owner.generation || decoded.owner.sequence < owner.sequence
        ) {
            return ReconcileOutcome.REJECTED
        }
        if (unchanged) return ReconcileOutcome.UNCHANGED
        // A replacement written while the proof was pending answers in its own attempt.
        val current = route.item(host)
        // The proven host must still own the route at the commit, after that read: a disconnect
        // during the proof or the read leaves its item readable from the cache.
        recheckRoute(host, current)?.let { return it }
        if (current?.ordered != ordered) return ReconcileOutcome.SUPERSEDED
        val outcome = settle(store.accept(host, ordered, decoded.owner, attempt), host, ordered, attempt)
        // Only a stored item shows the phone that Wear holds its order.
        if (outcome == ReconcileOutcome.ACCEPTED) {
            runCatching { route.reportHeld(host, newNonce(), decoded.owner) }
        }
        return outcome
    }

    /** Another entry point that already stored this delivery leaves it UNCHANGED here. */
    private fun settle(accepted: Boolean, host: String, encoded: String, attempt: Long) = when {
        accepted -> ReconcileOutcome.ACCEPTED
        store.unchanged(host, encoded) -> ReconcileOutcome.UNCHANGED
        store.attemptCurrent(attempt) -> ReconcileOutcome.REJECTED
        else -> ReconcileOutcome.SUPERSEDED
    }

    companion object {
        private val executor = Executors.newSingleThreadExecutor()

        /** Its only message is the receipt marker the paired gate reads. */
        private const val RECEIPT_TAG = "WardPulseSync"

        /**
         * Reports one stock receipt for an accepted write, whether the listener or the activity
         * made it; the store accepts each delivery once. Unchanged items emit nothing, and other
         * route outcomes stay outside the receipt marker stream.
         */
        internal fun report(context: Context, outcome: ReconcileOutcome) {
            when (outcome) {
                ReconcileOutcome.ACCEPTED -> {
                    WatchComplicationUpdater.requestUpdate(context)
                    Log.i(RECEIPT_TAG, "Watch summary received.")
                }
                ReconcileOutcome.UNCHANGED -> Unit
                else -> Log.i(WatchDataContract.DIAGNOSTIC_TAG, "Watch summary not accepted.")
            }
        }

        /**
         * Exactly `{nonce, installId, generation, sequence}`, with a generation at or above 0 and
         * a sequence at or above 1, as the v10 owner fields; null when malformed.
         */
        internal fun ownerReply(bytes: ByteArray): Pair<String, SummaryOwner>? = try {
            val json = strictJsonObject(String(bytes, Charsets.UTF_8))
            require(json.keys().asSequence().toSet() == OWNER_REPLY_MEMBERS)
            val nonce = json.get("nonce")
            val installId = json.get("installId")
            val generation = json.get("generation")
            val sequence = json.get("sequence")
            require(nonce is String && nonce.isNotEmpty() && installId is String && installId.isNotEmpty())
            require((generation is Int || generation is Long) && (sequence is Int || sequence is Long))
            val owner = SummaryOwner(installId, (generation as Number).toLong(), (sequence as Number).toLong())
            require(owner.generation >= 0L && owner.sequence >= 1L)
            Pair(nonce, owner)
        } catch (_: Exception) {
            null
        }

        private val OWNER_REPLY_MEMBERS = setOf("nonce", "installId", "generation", "sequence")

        /**
         * Exactly `{nonce, installId, generation, sequence}`: the [nonce] and the order of the v10
         * item this watch stores from the phone, so the phone records that Wear has left the
         * previous mode once it stores any item of the current install and generation, whatever
         * its order. Without a stored v10 order it is the bare nonce, which the phone answers but
         * never counts.
         */
        internal fun ownerRequest(nonce: String, held: SummaryOwner?): ByteArray =
            if (held == null) {
                nonce.toByteArray(Charsets.UTF_8)
            } else {
                JSONObject()
                    .put("nonce", nonce)
                    .put("installId", held.installId)
                    .put("generation", held.generation)
                    .put("sequence", held.sequence)
                    .toString()
                    .toByteArray(Charsets.UTF_8)
            }

        /** Reconciles off the main thread, for example when the Wear app starts. */
        fun reconcileAsync(context: Context, store: WatchSummaryStore) {
            val appContext = context.applicationContext
            executor.execute {
                report(appContext, WatchSummaryReconciler(store, WearableSummaryRoute(appContext)).reconcile())
            }
        }
    }
}

/** Production [SummaryRoute] over the Wearable Data Layer. */
internal class WearableSummaryRoute(context: Context) : SummaryRoute {
    private val appContext = context.applicationContext

    override fun connectedHosts(): Set<String> =
        await(Wearable.getNodeClient(appContext).connectedNodes).mapTo(HashSet()) { it.id }

    override fun items(): List<SummaryItem> {
        val uri = Uri.Builder().scheme(SCHEME).path(WatchDataContract.PATH).build()
        val buffer = await(Wearable.getDataClient(appContext).getDataItems(uri))
        return try {
            buffer.map { it.toSummaryItem() }
        } finally {
            buffer.release()
        }
    }

    override fun item(host: String): SummaryItem? {
        val uri = Uri.Builder().scheme(SCHEME).authority(host).path(WatchDataContract.PATH).build()
        return await(Wearable.getDataClient(appContext).getDataItem(uri))?.toSummaryItem()
    }

    override fun requestOwner(host: String, nonce: String, held: SummaryOwner?): ByteArray? = try {
        await(send(host, nonce, held))
    } catch (_: Exception) {
        null
    }

    // The commit already happened, so the reply is not awaited.
    override fun reportHeld(host: String, nonce: String, held: SummaryOwner) {
        send(host, nonce, held)
    }

    private fun send(host: String, nonce: String, held: SummaryOwner?) =
        Wearable.getMessageClient(appContext).sendRequest(
            host,
            WatchDataContract.OWNER_PATH,
            WatchSummaryReconciler.ownerRequest(nonce, held),
        )

    private fun <T> await(task: com.google.android.gms.tasks.Task<T>): T =
        Tasks.await(task, TIMEOUT_SECONDS, TimeUnit.SECONDS)

    private companion object {
        const val SCHEME = "wear"
        const val TIMEOUT_SECONDS = 10L
    }
}

/**
 * Freezes the item's values; Data Layer buffers are released after the callback. A key holding
 * anything but a string reads as present with a null value, never as absent.
 */
internal fun DataItem.toSummaryItem(): SummaryItem {
    val map = DataMapItem.fromDataItem(this).dataMap
    return SummaryItem(
        host = uri.host.orEmpty(),
        ordered = map.get<Any?>(WatchDataContract.SUMMARY_KEY) as? String,
        legacy = map.get<Any?>(WatchDataContract.PAYLOAD_KEY) as? String,
        orderedPresent = map.containsKey(WatchDataContract.SUMMARY_KEY),
    )
}
