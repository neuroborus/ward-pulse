package app.wardpulse

import android.content.Context
import android.content.SharedPreferences
import android.test.InstrumentationTestCase
import app.wardpulse.watchsync.ConnectionCacheEngine
import app.wardpulse.watchsync.WatchAdmission
import app.wardpulse.watchsync.WatchHeldItem
import app.wardpulse.watchsync.WatchPublication
import app.wardpulse.watchsync.WatchPublicationStore
import app.wardpulse.watchsync.WatchPublisher
import app.wardpulse.watchsync.WatchSummarySupersededException
import app.wardpulse.watchsync.WatchTransport
import app.wardpulse.watchsync.admitWatchSend
import app.wardpulse.watchsync.retireSurfaceSettings
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicReference
import junit.framework.Assert.assertEquals
import junit.framework.Assert.assertFalse
import junit.framework.Assert.assertNotNull
import junit.framework.Assert.assertNull
import junit.framework.Assert.assertTrue
import org.json.JSONObject

/**
 * The actual watch publisher queue over test-owned durable preferences, engine and a held Data
 * Layer: puts wait for the test, and the local-item lookup answers from the puts it settled. The
 * installed app's publication record, its order floor and the process queue with its callbacks
 * stay outside the test. A process death is a fresh engine over the same mode record and a fresh
 * queue over the same preferences.
 */
@Suppress("DEPRECATION")
class WatchPublisherTest : InstrumentationTestCase() {
    private val context: Context get() = instrumentation.targetContext.applicationContext
    private val transport = HeldTransport()
    private lateinit var preferences: SharedPreferences
    private lateinit var publisher: WatchPublisher
    private val store: WatchPublicationStore get() = WatchPublicationStore(preferences)

    override fun setUp() {
        super.setUp()
        preferences = context.getSharedPreferences(STORE_NAME, Context.MODE_PRIVATE)
        assertTrue(preferences.edit().clear().commit())
    }

    override fun tearDown() {
        try {
            // Work an earlier queue posted settles before the test's preferences are cleared.
            instrumentation.waitForIdleSync()
            if (::preferences.isInitialized) assertTrue(preferences.edit().clear().commit())
        } finally {
            super.tearDown()
        }
    }

    fun testReplacementIsDesiredWhileTheEarlierPutIsHeldAndOnlyItsOwnPutAcknowledgesIt() {
        val engine = process(MapBackend())
        val install = engine.initializeMode(false)["installId"] as String
        val first = publication(claimed(engine), install, label = "first")
        onMain { publisher.submit(context, first) {} }
        assertEquals(listOf(first), transport.items())

        val second = publication(claimed(engine), install, label = "second")
        onMain { publisher.submit(context, second) {} }
        // Persisted at once while the earlier put is held; no second put starts yet.
        assertEquals(second, store.read())
        assertEquals(listOf(first), transport.items())

        onMain { transport.complete(0) }
        // The held put's settlement acknowledges neither order; the replacement is put next.
        assertFalse(engine.watchSummaryAcknowledged(first.sequence))
        assertFalse(engine.watchSummaryAcknowledged(second.sequence))
        assertEquals(listOf(first, second), transport.items())
        onMain { transport.complete(1) }
        assertTrue(engine.watchSummaryAcknowledged(second.sequence))
    }

    fun testProcessDeathWithAHeldPutReassertsThePendingReplacement() {
        val modes = MapBackend()
        val engine = process(modes)
        val install = engine.initializeMode(false)["installId"] as String
        val first = publication(claimed(engine), install, label = "first")
        val second = publication(claimed(engine), install, label = "second")
        onMain {
            publisher.submit(context, first) {}
            publisher.submit(context, second) {}
        }

        // The process dies before the held put settles; the new one reasserts the replacement.
        val restarted = restart(modes)
        onMain { publisher.reconcile(context) }
        instrumentation.waitForIdleSync()
        assertEquals(listOf(second), transport.items())
        onMain { transport.complete(0) }
        assertTrue(restarted.watchSummaryAcknowledged(second.sequence))
        assertEquals(second.sequence + 1, restarted.reserveWatchSummary(store.lastSequence()))
    }

    fun testStartupAfterAModeCommitReconstructsTheCurrentGenerationEmptyItem() {
        val modes = MapBackend()
        val engine = process(modes)
        val install = engine.initializeMode(false)["installId"] as String
        val live = publication(claimed(engine), install, label = "live")
        assertTrue(store.write(live))
        // Demo commits, and the process dies before replacing the generation 0 item.
        val switched = AtomicReference<Map<String, Any>>()
        engine.switchMode("test", "demo", { switched.set(it) }, { throw AssertionError(it) })
        assertEquals(1L, switched.get()["generation"])

        val restarted = restart(modes)
        onMain { publisher.reconcile(context) }
        val desired = store.read()
        assertNotNull(desired)
        assertEquals(live.sequence + 1, desired!!.sequence)
        assertEquals(install, desired.installId)
        assertEquals(1L, desired.generation)
        assertTrue(desired.placeholder)
        val summary = JSONObject(desired.summary!!)
        assertEquals("demo", summary.getString("dataMode"))
        assertEquals(1L, summary.getLong("generation"))
        assertEquals(desired.sequence, summary.getLong("sequence"))
        // Its v9 projection never carries Demo.
        assertEquals("live", JSONObject(desired.payload).getString("dataMode"))
        assertEquals(listOf(desired), transport.items())
        onMain { transport.complete(0) }
        assertTrue(restarted.watchSummaryAcknowledged(desired.sequence))
    }

    fun testEstablishedFollowsSettingsAcrossNewerLoadsAndProcessDeath() {
        val modes = MapBackend()
        val engine = process(modes)
        val install = engine.initializeMode(false)["installId"] as String
        assertFalse(onMain { publisher.established(context) })

        val (load, revision) = accept(engine)
        val ticket = engine.issueWatchSummary(0L, load, 0L, revision)!!
        assertEquals(true, engine.admitWatchSummary(ticket, null))
        val published = publication(ticket, install, label = "published")
        onMain { publisher.submit(context, published) {} }
        onMain { transport.complete(0) }

        // A later cadence-denied load is accepted without publishing; the summary stays
        // established, and the load adopts it, so its reassertion is still put.
        accept(engine)
        assertTrue(onMain { publisher.established(context) })
        assertTrue(onMain { publisher.established(context) })
        val lease = engine.enterWatchSend("test", ticket, install, 0L, null, emptyMap(), emptyMap(), emptyMap())
        assertNotNull(lease)
        engine.exitEffect("test", lease, false)

        // A ring save retires it, in this process and durably, as the settings channel does.
        saveSettings(engine)
        assertFalse(onMain { publisher.established(context) })

        // The process dies before the replacement: the new one neither counts nor reasserts it.
        val restarted = restart(modes)
        assertFalse(onMain { publisher.established(context) })
        onMain { publisher.reconcile(context) }
        instrumentation.waitForIdleSync()
        assertTrue(transport.items().isEmpty())

        // Real input rebuilds it: the fresh write is established again.
        val rebuilt = publication(claimed(restarted), install, label = "rebuilt")
        onMain { publisher.submit(context, rebuilt) {} }
        assertFalse(store.read()!!.retired)
        assertTrue(onMain { publisher.established(context) })
    }

    fun testASaveBeforeTheWriteRefusesItAsSuperseded() {
        val engine = process(MapBackend())
        val install = engine.initializeMode(false)["installId"] as String
        val (load, revision) = accept(engine)
        val ticket = engine.issueWatchSummary(0L, load, 0L, revision)!!
        assertEquals(true, engine.admitWatchSummary(ticket, null))
        engine.finishSurfaceSettingsWrite("test", engine.beginSurfaceSettingsWrite("test"))
        val outcome = AtomicReference<Exception?>()
        onMain { publisher.submit(context, publication(ticket, install, label = "stale")) { outcome.set(it) } }
        assertTrue(outcome.get() is WatchSummarySupersededException)
        assertEquals(null, store.read())
        assertTrue(transport.items().isEmpty())
    }

    fun testASubmissionReplacedBeforeItsPutStartsSettlesSuperseded() {
        val engine = process(MapBackend())
        val install = engine.initializeMode(false)["installId"] as String
        val held = publication(claimed(engine), install, label = "held")
        val replaced = publication(claimed(engine), install, label = "replaced")
        val outcome = AtomicReference<Exception?>()
        onMain {
            publisher.submit(context, held) {}
            publisher.submit(context, replaced) { outcome.set(it) }
        }
        assertNull(outcome.get())

        val latest = publication(claimed(engine), install, label = "latest")
        onMain { publisher.submit(context, latest) {} }
        // The replaced submission never reaches the transport, so it never reports a delivery.
        assertTrue(outcome.get() is WatchSummarySupersededException)
        assertEquals(listOf(held), transport.items())
        onMain { transport.complete(0) }
        assertEquals(listOf(held, latest), transport.items())
    }

    fun testASettingsSyncHeldBehindAPutAndRetiredBeforeItsSendSettlesSuperseded() {
        val engine = process(MapBackend())
        val install = engine.initializeMode(false)["installId"] as String
        val held = publication(claimed(engine), install, label = "held")
        onMain { publisher.submit(context, held) {} }

        // Settings Sync publishes the accepted load under the settled revision behind that put.
        val (load, revision) = accept(engine)
        val ticket = engine.issueWatchSummary(store.lastSequence(), load, 0L, revision)!!
        assertEquals(true, engine.admitWatchSummary(ticket, null))
        val outcome = AtomicReference<Exception?>()
        val synced = AtomicReference(false)
        onMain {
            publisher.submit(context, publication(ticket, install, label = "sync")) {
                outcome.set(it)
                synced.set(true)
            }
        }
        assertFalse(synced.get())

        // A save retires it before its own send starts; the held put settles and nothing follows.
        saveSettings(engine)
        onMain { transport.complete(0) }
        assertTrue(synced.get())
        assertTrue(outcome.get() is WatchSummarySupersededException)
        assertEquals(listOf(held), transport.items())
    }

    fun testReadinessSettlingOutOfOrderSupersedesTheOlderSend() {
        val engine = process(MapBackend())
        engine.initializeMode(false)
        val (load, revision) = accept(engine)
        val older = engine.issueWatchSummary(store.lastSequence(), load, 0L, revision)!!
        val newer = engine.issueWatchSummary(store.lastSequence(), load, 0L, revision)!!
        // The newer request's readiness settles first; the older one is never sent.
        assertEquals(WatchAdmission.ADMITTED, admit(engine, newer))
        assertEquals(WatchAdmission.SUPERSEDED, admit(engine, older))
        // A save after issue supersedes a ticket before its admission too.
        val saved = engine.issueWatchSummary(store.lastSequence(), load, 0L, revision)!!
        saveSettings(engine)
        assertEquals(WatchAdmission.SUPERSEDED, admit(engine, saved))
    }

    fun testOwnerRequestsAfterASettingsSaveAndProcessDeathGetNoReplyUntilAReplacement() {
        val modes = MapBackend()
        val engine = process(modes)
        val install = engine.initializeMode(false)["installId"] as String
        val published = publication(claimed(engine), install, label = "published")
        onMain { publisher.submit(context, published) {} }
        // Answered before its put settles, so the reassertion check finds no acknowledgement.
        assertEquals(published.sequence, ownerReply()!!.getLong("sequence"))
        onMain { transport.complete(0) }

        saveSettings(engine)

        // The process dies before a replacement: no reply, and the reconciliation the request
        // asks for still puts nothing. A new process holds no acknowledgement to check against
        // the Data Layer.
        val restarted = restart(modes)
        assertNull(ownerReply())
        instrumentation.waitForIdleSync()
        assertTrue(transport.items().isEmpty())
        assertTrue(store.read()!!.retired)

        val rebuilt = publication(claimed(restarted), install, label = "rebuilt")
        onMain { publisher.submit(context, rebuilt) {} }
        val reply = ownerReply()!!
        assertEquals(rebuilt.sequence, reply.getLong("sequence"))
        assertEquals(install, reply.getString("installId"))
        assertEquals(0L, reply.getLong("generation"))
    }

    fun testALauncherOnlySaveLeavesTheWatchItemAnswerable() {
        val modes = MapBackend()
        val engine = process(modes)
        val install = engine.initializeMode(false)["installId"] as String
        val published = publication(claimed(engine), install, label = "published")
        onMain { publisher.submit(context, published) {} }
        onMain { transport.complete(0) }

        // Launcher choices leave the watch content standing; no load or replacement follows.
        launcherSave(engine)
        assertFalse(store.read()!!.retired)
        assertEquals(published.sequence, ownerReply()!!.getLong("sequence"))
        instrumentation.waitForIdleSync()
        // The acknowledged item's check reads the held item, which it still is: nothing is put.
        assertEquals(1, transport.reads())
        assertEquals(listOf(published), transport.items())

        // Across a restart too, the owner proof still names the item the watch holds.
        val restarted = restart(modes)
        assertEquals(published.sequence, ownerReply()!!.getLong("sequence"))
        instrumentation.waitForIdleSync()

        // A ring or alert-rule save does retire it.
        saveSettings(restarted)
        assertNull(ownerReply())
    }

    fun testALauncherOnlySaveKeepsAWatchItemWaitingBehindAPutSendable() {
        val engine = process(MapBackend())
        val install = engine.initializeMode(false)["installId"] as String
        val held = publication(claimed(engine), install, label = "held")
        onMain { publisher.submit(context, held) {} }

        // Settings Sync publishes the accepted load under the settled revision behind that put.
        val (load, revision) = accept(engine)
        val ticket = engine.issueWatchSummary(store.lastSequence(), load, 0L, revision)!!
        assertEquals(true, engine.admitWatchSummary(ticket, null))
        val sync = publication(ticket, install, label = "sync")
        val outcome = AtomicReference<Exception?>()
        val settled = AtomicReference(false)
        onMain {
            publisher.submit(context, sync) {
                outcome.set(it)
                settled.set(true)
            }
        }

        // A launcher-only save, in flight and once it settles, leaves its send authority standing.
        val token = engine.beginSurfaceSettingsWrite("test", false)
        assertTrue(engine.watchSummaryCurrent(ticket))
        assertTrue(retireSurfaceSettings({ true }, store, watchSettings = false))
        assertNotNull(engine.finishSurfaceSettingsWrite("test", token))
        assertTrue(engine.watchSummaryCurrent(ticket))

        // The held put settles, and the waiting summary's own put starts and is acknowledged.
        onMain { transport.complete(0) }
        assertEquals(listOf(held, sync), transport.items())
        assertFalse(settled.get())
        onMain { transport.complete(1) }
        assertTrue(settled.get())
        assertNull(outcome.get())
        assertTrue(engine.watchSummaryAcknowledged(ticket))
        assertEquals(ticket, ownerReply()!!.getLong("sequence"))
        instrumentation.waitForIdleSync()
        assertEquals(listOf(held, sync), transport.items())

        // A save that may change the watch content, even overlapping a launcher-only one, and a
        // newer accepted load still retire such authority.
        val (next, nextRevision) = accept(engine)
        assertFalse(engine.watchSummaryCurrent(ticket))
        val rebuilt = engine.issueWatchSummary(store.lastSequence(), next, 0L, nextRevision)!!
        val launcher = engine.beginSurfaceSettingsWrite("test", false)
        val rings = engine.beginSurfaceSettingsWrite("test")
        engine.finishSurfaceSettingsWrite("test", launcher)
        engine.finishSurfaceSettingsWrite("test", rings)
        assertFalse(engine.watchSummaryCurrent(rebuilt))
    }

    fun testATransitionStaysOwedUntilWearCanVerifyAnItemOfItsGeneration() {
        val modes = MapBackend()
        val engine = process(modes)
        val install = engine.initializeMode(false)["installId"] as String
        // Demo, then Live again: the watch may hold Demo until it can verify a Live item.
        val switched = AtomicReference<Map<String, Any>>()
        engine.switchMode("test", "demo", { switched.set(it) }, { throw AssertionError(it) })
        engine.switchMode("test", "live", { switched.set(it) }, { throw AssertionError(it) })
        val generation = (switched.get()["generation"] as Number).toLong()
        assertEquals(2L, generation)
        onMain { publisher.reconcile(context) }
        val empty = store.read()!!
        assertTrue(empty.placeholder)
        assertEquals(listOf(empty), transport.items())

        // Real Live input waits behind the empty put, and a save retires it before its send.
        val (load, revision) = accept(engine, generation)
        val ticket = engine.issueWatchSummary(store.lastSequence(), load, generation, revision)!!
        assertEquals(true, engine.admitWatchSummary(ticket, null))
        onMain { publisher.submit(context, publication(ticket, install, "live", generation)) {} }
        saveSettings(engine)
        onMain { transport.complete(0, IllegalStateException("put failed")) }
        assertEquals(listOf(empty), transport.items())
        assertTrue(store.read()!!.retired)

        // After a restart with no real Live input, the empty item of the generation is owed again.
        val restarted = restart(modes)
        onMain { publisher.reconcile(context) }
        instrumentation.waitForIdleSync()
        val owed = store.read()!!
        assertTrue(owed.placeholder)
        assertEquals(generation, owed.generation)
        assertEquals(listOf(owed), transport.items())
        onMain { transport.complete(0) }

        // Once an owner proof named an item of the generation this node holds, Wear can verify
        // it, and a retired item keeps the last valid summary, as in the same mode.
        val rebuilt = publication(claimed(restarted), install, "rebuilt", generation)
        onMain { publisher.submit(context, rebuilt) {} }
        onMain { transport.complete(1) }
        assertFalse(store.delivered(install, generation))
        assertEquals(rebuilt.sequence, ownerReply(holding = rebuilt)!!.getLong("sequence"))
        instrumentation.waitForIdleSync()
        assertTrue(store.delivered(install, generation))
        saveSettings(restarted)
        restart(modes)
        onMain { publisher.reconcile(context) }
        instrumentation.waitForIdleSync()
        assertTrue(transport.items().isEmpty())
        assertEquals(rebuilt.sequence, store.read()!!.sequence)
    }

    fun testAPutWearCannotVerifyKeepsTheTransitionOwed() {
        val modes = MapBackend()
        val engine = process(modes)
        val install = engine.initializeMode(false)["installId"] as String
        val switched = AtomicReference<Map<String, Any>>()
        engine.switchMode("test", "demo", { switched.set(it) }, { throw AssertionError(it) })
        engine.switchMode("test", "live", { switched.set(it) }, { throw AssertionError(it) })
        val generation = (switched.get()["generation"] as Number).toLong()
        onMain { publisher.reconcile(context) }
        val empty = store.read()!!
        assertTrue(empty.placeholder)

        // Real Live input becomes desired behind the held empty put, so the owner reply names it,
        // not the empty item; a save retires it before its send, and then the empty put succeeds.
        val (load, revision) = accept(engine, generation)
        val ticket = engine.issueWatchSummary(store.lastSequence(), load, generation, revision)!!
        assertEquals(true, engine.admitWatchSummary(ticket, null))
        onMain { publisher.submit(context, publication(ticket, install, "live", generation)) {} }
        assertEquals(ticket, ownerReply()!!.getLong("sequence"))
        // The reconciliation the request asks for settles first.
        instrumentation.waitForIdleSync()
        saveSettings(engine)
        onMain { transport.complete(0) }
        instrumentation.waitForIdleSync()
        assertTrue(store.read()!!.retired)
        assertFalse(store.delivered(install, generation))

        // After a restart with no real Live input, an empty item Wear can verify is owed again.
        restart(modes)
        onMain { publisher.reconcile(context) }
        instrumentation.waitForIdleSync()
        val owed = store.read()!!
        assertTrue(owed.placeholder)
        assertEquals(generation, owed.generation)
        assertEquals(listOf(owed), transport.items())
        assertEquals(owed.sequence, ownerReply()!!.getLong("sequence"))
        onMain { transport.complete(0) }
        // Its completed put alone shows nothing; a proof naming the item Wear holds does.
        assertFalse(store.delivered(install, generation))
        assertEquals(owed.sequence, ownerReply(holding = owed)!!.getLong("sequence"))
        instrumentation.waitForIdleSync()
        assertTrue(store.delivered(install, generation))
    }

    fun testASaveAfterTheFirstLivePutCompletedKeepsTheTransitionOwed() {
        val modes = MapBackend()
        val engine = process(modes)
        val install = engine.initializeMode(false)["installId"] as String
        val switched = AtomicReference<Map<String, Any>>()
        engine.switchMode("test", "demo", { switched.set(it) }, { throw AssertionError(it) })
        engine.switchMode("test", "live", { switched.set(it) }, { throw AssertionError(it) })
        val generation = (switched.get()["generation"] as Number).toLong()
        onMain { publisher.reconcile(context) }

        // With the watch away, the empty put and then the first Live item's own put succeed.
        onMain { transport.complete(0) }
        val (load, revision) = accept(engine, generation)
        val ticket = engine.issueWatchSummary(store.lastSequence(), load, generation, revision)!!
        assertEquals(true, engine.admitWatchSummary(ticket, null))
        onMain { publisher.submit(context, publication(ticket, install, "live", generation)) {} }
        onMain { transport.complete(1) }
        assertTrue(engine.watchSummaryAcknowledged(ticket))
        assertFalse(store.delivered(install, generation))

        // A ring save retires it before the watch reconnects, and the process dies before a
        // replacement. The reconnecting watch's proof gets no reply and owes an empty Live item.
        saveSettings(engine)
        restart(modes)
        assertNull(ownerReply())
        instrumentation.waitForIdleSync()
        val owed = store.read()!!
        assertTrue(owed.placeholder)
        assertEquals(generation, owed.generation)
        assertEquals(listOf(owed), transport.items())
        assertEquals(owed.sequence, ownerReply()!!.getLong("sequence"))
        onMain { transport.complete(0) }
        assertEquals(owed.sequence, ownerReply(holding = owed)!!.getLong("sequence"))
        instrumentation.waitForIdleSync()
        assertTrue(store.delivered(install, generation))
    }

    fun testASaveRetiringTheFirstLiveItemInFlightKeepsTheTransitionOwed() {
        val modes = MapBackend()
        val engine = process(modes)
        val install = engine.initializeMode(false)["installId"] as String
        val switched = AtomicReference<Map<String, Any>>()
        engine.switchMode("test", "demo", { switched.set(it) }, { throw AssertionError(it) })
        engine.switchMode("test", "live", { switched.set(it) }, { throw AssertionError(it) })
        val generation = (switched.get()["generation"] as Number).toLong()
        onMain { publisher.reconcile(context) }
        val empty = store.read()!!

        // Real Live input becomes desired behind the empty put, which then fails, so no put of
        // the generation has succeeded yet; no retry is scheduled for an item no longer desired.
        val (load, revision) = accept(engine, generation)
        val ticket = engine.issueWatchSummary(store.lastSequence(), load, generation, revision)!!
        assertEquals(true, engine.admitWatchSummary(ticket, null))
        val live = publication(ticket, install, "live", generation)
        onMain { publisher.submit(context, live) {} }
        onMain { transport.complete(0, IllegalStateException("put failed")) }

        // The Live item's own put starts, and a save retires that same item while it is in
        // flight; the put then succeeds, but the owner reply refuses the item Wear now holds.
        assertEquals(listOf(empty, live), transport.items())
        saveSettings(engine)
        onMain { transport.complete(1) }
        instrumentation.waitForIdleSync()
        assertTrue(store.read()!!.retired)
        assertFalse(store.delivered(install, generation))
        assertNull(ownerReply())
        // The reconciliation the request asks for owes an empty Live item Wear can verify.
        instrumentation.waitForIdleSync()
        assertFalse(store.delivered(install, generation))
        val owed = store.read()!!
        assertTrue(owed.placeholder)
        assertEquals(generation, owed.generation)
        assertEquals(owed, transport.items().last())

        // The process dies before that put settles; the new one puts it again and names it.
        restart(modes)
        onMain { publisher.reconcile(context) }
        instrumentation.waitForIdleSync()
        assertEquals(listOf(owed), transport.items())
        onMain { transport.complete(0) }
        assertEquals(owed.sequence, ownerReply(holding = owed)!!.getLong("sequence"))
        instrumentation.waitForIdleSync()
        assertTrue(store.delivered(install, generation))
    }

    fun testAProofNamingAnOrderBelowTheDesiredOneShowsWearLeftThePreviousMode() {
        val modes = MapBackend()
        val engine = process(modes)
        val install = engine.initializeMode(false)["installId"] as String
        val switched = AtomicReference<Map<String, Any>>()
        engine.switchMode("test", "demo", { switched.set(it) }, { throw AssertionError(it) })
        engine.switchMode("test", "live", { switched.set(it) }, { throw AssertionError(it) })
        val generation = (switched.get()["generation"] as Number).toLong()
        onMain { publisher.reconcile(context) }
        val empty = store.read()!!

        // Wear stores the empty item and its report is lost; the first Live item then becomes
        // desired and its own put succeeds while the watch is away.
        onMain { transport.complete(0) }
        val (load, revision) = accept(engine, generation)
        val ticket = engine.issueWatchSummary(store.lastSequence(), load, generation, revision)!!
        assertEquals(true, engine.admitWatchSummary(ticket, null))
        onMain { publisher.submit(context, publication(ticket, install, "live", generation)) {} }
        onMain { transport.complete(1) }

        // A bare nonce, or a watch still storing the previous generation's item, shows nothing.
        for (holding in listOf(null, publication(empty.sequence, install, "demo", generation - 1))) {
            assertEquals(ticket, ownerReply(holding)!!.getLong("sequence"))
            instrumentation.waitForIdleSync()
            assertFalse(store.delivered(install, generation))
        }

        // The reconnecting watch names the empty item it stores, below the desired order: the
        // reply still names the Live order, and Wear has left Demo.
        assertEquals(ticket, ownerReply(holding = empty)!!.getLong("sequence"))
        assertTrue(store.delivered(install, generation))
        instrumentation.waitForIdleSync()

        // So a ring save retiring the Live item with no replacement keeps Wear's last valid
        // summary, in this process and after its death: no empty fallback is put.
        saveSettings(engine)
        onMain { publisher.reconcile(context) }
        instrumentation.waitForIdleSync()
        assertEquals(2, transport.items().size)
        restart(modes)
        onMain { publisher.reconcile(context) }
        instrumentation.waitForIdleSync()
        assertTrue(transport.items().isEmpty())
        assertEquals(ticket, store.read()!!.sequence)
    }

    fun testAProofNamingTheRetiredDesiredOrderShowsWearLeftThePreviousMode() {
        val modes = MapBackend()
        val engine = process(modes)
        val install = engine.initializeMode(false)["installId"] as String
        val switched = AtomicReference<Map<String, Any>>()
        engine.switchMode("test", "demo", { switched.set(it) }, { throw AssertionError(it) })
        engine.switchMode("test", "live", { switched.set(it) }, { throw AssertionError(it) })
        val generation = (switched.get()["generation"] as Number).toLong()
        onMain { publisher.reconcile(context) }
        onMain { transport.complete(0) }
        val (load, revision) = accept(engine, generation)
        val ticket = engine.issueWatchSummary(store.lastSequence(), load, generation, revision)!!
        assertEquals(true, engine.admitWatchSummary(ticket, null))
        val live = publication(ticket, install, "live", generation)
        onMain { publisher.submit(context, live) {} }
        onMain { transport.complete(1) }

        // Wear stores the Live item and its report is lost; with the watch away, a ring save
        // retires that item and nothing replaces it.
        saveSettings(engine)
        assertFalse(store.delivered(install, generation))

        // The reconnecting watch names the Live order it stores: the retired item gets no reply,
        // but Wear has left Demo.
        assertNull(ownerReply(holding = live))
        assertTrue(store.delivered(install, generation))

        // The reconciliation the proof requests, and one after process death, put no fallback.
        instrumentation.waitForIdleSync()
        assertEquals(2, transport.items().size)
        restart(modes)
        onMain { publisher.reconcile(context) }
        instrumentation.waitForIdleSync()
        assertTrue(transport.items().isEmpty())
        assertEquals(ticket, store.read()!!.sequence)
    }

    fun testAProofReachingANewProcessShowsWearCanVerifyTheTransition() {
        val modes = MapBackend()
        val engine = process(modes)
        val install = engine.initializeMode(false)["installId"] as String
        val switched = AtomicReference<Map<String, Any>>()
        engine.switchMode("test", "demo", { switched.set(it) }, { throw AssertionError(it) })
        engine.switchMode("test", "live", { switched.set(it) }, { throw AssertionError(it) })
        val generation = (switched.get()["generation"] as Number).toLong()
        onMain { publisher.reconcile(context) }
        onMain { transport.complete(0) }
        val (load, revision) = accept(engine, generation)
        val ticket = engine.issueWatchSummary(store.lastSequence(), load, generation, revision)!!
        assertEquals(true, engine.admitWatchSummary(ticket, null))
        val live = publication(ticket, install, "live", generation)
        onMain { publisher.submit(context, live) {} }
        onMain { transport.complete(1) }

        // The process dies; Wear's proof naming the Live order it stored starts a new one, which
        // acknowledged nothing, and is counted all the same.
        val restarted = restart(modes)
        assertFalse(restarted.watchSummaryAcknowledged(ticket))
        assertEquals(ticket, ownerReply(holding = live)!!.getLong("sequence"))
        instrumentation.waitForIdleSync()
        assertTrue(store.delivered(install, generation))

        // So a save with no replacement keeps Wear's last valid Live summary: nothing is put.
        saveSettings(restarted)
        restart(modes)
        onMain { publisher.reconcile(context) }
        instrumentation.waitForIdleSync()
        assertTrue(transport.items().isEmpty())
        assertEquals(ticket, store.read()!!.sequence)
    }

    fun testAWatchSpeakingOnlyV9KeepsCapacityHandlingUntilATransitionOwesTheEmptyItem() {
        val modes = MapBackend()
        val engine = process(modes)
        val install = engine.initializeMode(false)["installId"] as String
        // In generation 0 a retired item with no replacement stays the last valid summary.
        val (load, revision) = accept(engine)
        val ticket = engine.issueWatchSummary(0L, load, 0L, revision)!!
        assertEquals(true, engine.admitWatchSummary(ticket, null))
        onMain { publisher.submit(context, publication(ticket, install, label = "live")) {} }
        onMain { transport.complete(0) }
        saveSettings(engine)
        onMain { publisher.reconcile(context) }
        instrumentation.waitForIdleSync()
        assertEquals(1, transport.items().size)
        assertEquals(ticket, store.read()!!.sequence)

        // After Demo and back, a watch that sends no owner request records no delivery, so the
        // same save owes the empty item, whose v9 projection is an empty Live summary. The put's
        // mode lease is released on the plugin's executor, so the switches may complete there.
        val switched = AtomicReference<Map<String, Any>>()
        val returned = CountDownLatch(1)
        engine.switchMode("test", "demo", { switched.set(it) }, { throw AssertionError(it) })
        engine.switchMode("test", "live", {
            switched.set(it)
            returned.countDown()
        }, { throw AssertionError(it) })
        assertTrue(returned.await(10, TimeUnit.SECONDS))
        val generation = (switched.get()["generation"] as Number).toLong()
        onMain { publisher.reconcile(context) }
        onMain { transport.complete(1) }
        val (liveLoad, liveRevision) = accept(engine, generation)
        val liveTicket = engine.issueWatchSummary(store.lastSequence(), liveLoad, generation, liveRevision)!!
        assertEquals(true, engine.admitWatchSummary(liveTicket, null))
        onMain { publisher.submit(context, publication(liveTicket, install, "live", generation)) {} }
        onMain { transport.complete(2) }
        saveSettings(engine)
        onMain { publisher.reconcile(context) }
        instrumentation.waitForIdleSync()
        assertFalse(store.delivered(install, generation))
        val owed = store.read()!!
        assertTrue(owed.placeholder)
        assertEquals(generation, owed.generation)
        assertEquals(owed, transport.items().last())
        val projection = JSONObject(owed.payload)
        assertEquals("live", projection.getString("dataMode"))
        assertTrue(projection.getBoolean("manualRefreshAllowed"))
        assertEquals(0, projection.getJSONArray("rings").length())
    }

    /** A fresh engine over [modes] and a fresh queue over the test's preferences, as one process. */
    private fun process(modes: MapBackend): ConnectionCacheEngine {
        val engine = ConnectionCacheEngine(MapBackend(), modes, { System.currentTimeMillis() }, true)
        publisher = WatchPublisher(storeFor = { store }, engineFor = { engine }, transport = transport)
        return engine
    }

    /** Process death: no put state, no in-memory acknowledgement or authority, same durable records. */
    private fun restart(modes: MapBackend): ConnectionCacheEngine {
        transport.clear()
        return process(modes)
    }

    /** A settings save, as the settings channel makes one: in this process and durably. */
    private fun saveSettings(engine: ConnectionCacheEngine) {
        val token = engine.beginSurfaceSettingsWrite("test")
        assertTrue(retireSurfaceSettings({ true }, store, watchSettings = true))
        engine.finishSurfaceSettingsWrite("test", token)
    }

    /** A launcher-only save, as the settings channel makes one: the watch item stays answerable. */
    private fun launcherSave(engine: ConnectionCacheEngine) {
        val token = engine.beginSurfaceSettingsWrite("test", false)
        assertTrue(retireSurfaceSettings({ true }, store, watchSettings = false))
        engine.finishSurfaceSettingsWrite("test", token)
    }

    private fun admit(engine: ConnectionCacheEngine, ticket: Long) =
        admitWatchSend(engine, ticket, null, emptyMap(), emptyMap(), emptyMap())

    /** Wear's route proof naming the order of the item it stores, [holding], or a bare nonce. */
    private fun ownerReply(holding: WatchPublication? = null): JSONObject? {
        val request = holding?.let {
            JSONObject()
                .put("nonce", "nonce")
                .put("installId", it.installId)
                .put("generation", it.generation)
                .put("sequence", it.sequence)
                .toString()
        } ?: "nonce"
        return onMain { publisher.ownerReply(context, request.toByteArray(Charsets.UTF_8)) }
            ?.let { JSONObject(it.toString(Charsets.UTF_8)) }
    }

    private fun claimed(engine: ConnectionCacheEngine): Long =
        engine.reserveWatchSummary(store.lastSequence()).also {
            assertTrue(engine.claimWatchSummary(it))
        }

    /** Accepts a new load of the retained snapshot; its ordinal and settled settings revision. */
    private fun accept(engine: ConnectionCacheEngine, generation: Long = 0L): Pair<Long, Long> {
        val view = engine.beginWidgetLoad { 0L }
        val load = view["load"] as Long
        assertTrue(engine.acceptSnapshotLoad(load, generation, null, emptyMap(), emptyMap(), emptyMap()))
        return load to view["settingsRevision"] as Long
    }

    private fun publication(sequence: Long, installId: String, label: String, generation: Long = 0L) =
        WatchPublication(
            sequence = sequence,
            installId = installId,
            generation = generation,
            payload = """{"label":"$label"}""",
            summary = """{"label":"$label","sequence":$sequence}""",
        )

    private fun <T> onMain(action: () -> T): T {
        val value = AtomicReference<Any?>()
        val failure = AtomicReference<Throwable?>()
        instrumentation.runOnMainSync {
            try {
                value.set(action())
            } catch (error: Throwable) {
                failure.set(error)
            }
        }
        failure.get()?.let { throw it }
        @Suppress("UNCHECKED_CAST")
        return value.get() as T
    }

    /**
     * Holds every put until the test settles it on the main thread. The local-item lookup answers
     * at once, on the caller's main thread, with the last put that succeeded, which a process
     * death leaves on the Data Layer.
     */
    private class HeldTransport : WatchTransport {
        private val puts = mutableListOf<Pair<WatchPublication, (Exception?) -> Unit>>()
        private var held: WatchHeldItem? = null
        private var reads = 0

        override fun put(context: Context, publication: WatchPublication, done: (Exception?) -> Unit) {
            synchronized(puts) { puts += publication to done }
        }

        override fun readHeld(context: Context, done: (WatchHeldItem?) -> Unit) {
            done(synchronized(puts) { reads++; held })
        }

        fun items(): List<WatchPublication> = synchronized(puts) { puts.map { it.first } }
        fun reads(): Int = synchronized(puts) { reads }

        fun complete(index: Int, error: Exception? = null) {
            val done = synchronized(puts) {
                val (publication, done) = puts[index]
                if (error == null) held = WatchHeldItem(publication.payload, publication.summary)
                done
            }
            done(error)
        }

        fun clear() = synchronized(puts) { puts.clear() }
    }

    private class MapBackend : ConnectionCacheEngine.Backend {
        private var values: Map<String, String> = emptyMap()

        @Synchronized override fun read(): Map<String, String> = HashMap(values)

        @Synchronized override fun commit(values: Map<String, String>): Boolean {
            this.values = HashMap(values)
            return true
        }
    }

    private companion object {
        // Not the app's own record, so the installed publication and its order floor stay put.
        const val STORE_NAME = "wardpulse.watch-publication.publisher-test"
    }
}
