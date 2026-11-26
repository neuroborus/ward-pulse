package app.wardpulse

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.os.Bundle
import android.test.InstrumentationTestCase
import app.wardpulse.watchsync.ConnectionCacheEngine
import app.wardpulse.watchsync.PhoneWidgetPublicationStore
import es.antonborri.home_widget.HomeWidgetPlugin
import junit.framework.Assert.assertEquals
import junit.framework.Assert.assertTrue
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicReference

/** Real isolated preferences and the unchanged widget consumer, without launcher registration. */
@Suppress("DEPRECATION")
class PhoneWidgetPublicationTest : InstrumentationTestCase() {
    private lateinit var preferences: SharedPreferences
    private val context get() = instrumentation.targetContext.applicationContext

    override fun setUp() {
        super.setUp()
        assertEquals(WidgetPublicationFixture.PACKAGE, context.packageName)
        preferences = HomeWidgetPlugin.getData(context)
        assertTrue(preferences.edit().clear().commit())
    }

    override fun tearDown() {
        try {
            if (::preferences.isInitialized) assertTrue(preferences.edit().clear().commit())
        } finally {
            try {
                // Releases a settings save or ticket this test left on the process-wide authority.
                PhoneWidgetPublicationStore.engine(context).detach(OWNER)
            } finally { super.tearDown() }
        }
    }

    fun testOverlappingPublicationsRemainComplete() {
        val old = WidgetPublicationFixture.payload("old", 2, 10)
        val a = WidgetPublicationFixture.payload("A", 6, 0, stale = true)
        val b = WidgetPublicationFixture.payload("B", 3, 70)
        val ordinary = PhoneWidgetPublicationStore(preferences)
        assertTrue(preferences.edit().putString("unrelated", "retained").commit())
        assertTrue(ordinary.publish(old))
        val staged = CountDownLatch(1)
        val release = CountDownLatch(1)
        val paused = PhoneWidgetPublicationStore(afterStaging("row_0_percent") {
            staged.countDown()
            await(release)
        })
        val failure = AtomicReference<Throwable?>()
        val worker = worker(failure) { assertTrue(paused.publish(a)) }
        try {
            await(staged)
            WidgetPublicationFixture.assertStored(context, preferences, old, "coherence: old while A staged")
            assertTrue(ordinary.publish(b))
            WidgetPublicationFixture.assertStored(context, preferences, b, "coherence: B while A staged")
        } finally {
            release.countDown()
            join(worker)
            failure.get()?.let { throw AssertionError("Publication worker failed", it) }
        }
        WidgetPublicationFixture.assertStored(context, preferences, a, "coherence: A after release")
        assertEquals("retained", preferences.getString("unrelated", null))
        val empty = WidgetPublicationFixture.payload("empty", 0, 0)
        assertTrue(ordinary.publish(empty))
        WidgetPublicationFixture.assertStored(context, preferences, empty, "empty publication")
    }

    fun testAbandonedAndInvalidStagingLeaveOldPublication() {
        val old = WidgetPublicationFixture.payload("old", 2, 10)
        val next = WidgetPublicationFixture.payload("next", 6, 40)
        assertTrue(PhoneWidgetPublicationStore(preferences).publish(old))
        val abandoned = PhoneWidgetPublicationStore(afterStaging("row_0_percent") {
            throw IllegalStateException("Abandon staging")
        })
        try { abandoned.publish(next); fail("Staging should be abandoned") }
        catch (_: IllegalStateException) { /* Expected before commit. */ }
        val invalid = PhoneWidgetPublicationStore(object : SharedPreferences by preferences {
            override fun edit(): SharedPreferences.Editor = error("Invalid input reached persistence")
        })
        for ((key, value) in listOf("row_count" to 7, "empty" to "1", "stale" to "bad",
            "row_5_color" to 42, "row_5_pool" to null)) {
            try { invalid.publish(next + (key to value)); fail("Invalid $key accepted") }
            catch (_: IllegalArgumentException) { /* Entire map is validated first. */ }
        }
        WidgetPublicationFixture.assertStored(context, preferences, old, "abandoned/invalid staging")
    }

    fun testRetainedStaleSerializesSnapshotAndFlagCommit() {
        val old = WidgetPublicationFixture.payload("old", 2, 10)
        val next = WidgetPublicationFixture.payload("next", 6, 40)
        val ordinary = PhoneWidgetPublicationStore(preferences)
        assertNull(ordinary.markStale())
        assertTrue(ordinary.publish(old))
        val read = CountDownLatch(1)
        val fullStaged = CountDownLatch(1)
        val release = CountDownLatch(1)
        val stale = PhoneWidgetPublicationStore(object : SharedPreferences by preferences {
            override fun getAll(): MutableMap<String, *> {
                val snapshot = preferences.all
                read.countDown()
                await(release)
                return snapshot
            }
        })
        val full = PhoneWidgetPublicationStore(afterStaging("row_5_color") {
            fullStaged.countDown()
        })
        val failure = AtomicReference<Throwable?>()
        val staleWorker = worker(failure) { assertEquals(true, stale.markStale()) }
        var fullWorker: Thread? = null
        try {
            await(read)
            fullWorker = worker(failure) { assertTrue(full.publish(next)) }
            await(fullStaged)
            WidgetPublicationFixture.assertStored(context, preferences, old, "STALE snapshot retained")
        } finally {
            release.countDown()
            try { join(staleWorker) } finally { fullWorker?.let(::join) }
            failure.get()?.let { throw AssertionError("STALE/full worker failed", it) }
        }
        WidgetPublicationFixture.assertStored(context, preferences, next, "full commit follows STALE")
        assertEquals(true, ordinary.markStale())
        WidgetPublicationFixture.assertStored(context, preferences, next + ("stale" to "1"), "flag only")
        assertTrue(ordinary.publish(WidgetPublicationFixture.payload("empty", 0, 0)))
        val empty = preferences.all
        assertNull(ordinary.markStale())
        assertEquals(empty, preferences.all)
    }

    fun testFailedDiskCommitReportsFailureWithoutMemoryRollback() {
        val next = WidgetPublicationFixture.payload("failure", 3, 60)
        val store = PhoneWidgetPublicationStore(editing { editor ->
            object : SharedPreferences.Editor by editor {
                // Inject the failure result after a real commit; do not claim a reproduced disk fault.
                override fun commit(): Boolean { assertTrue(editor.commit()); return false }
            }
        })
        assertFalse(store.publish(next))
        WidgetPublicationFixture.assertStored(context, preferences, next, "complete memory after failure")
        assertEquals(false, store.markStale())
        WidgetPublicationFixture.assertStored(context, preferences, next + ("stale" to "1"), "failed STALE commit")
    }

    fun testUnconfirmedRenewalRetirementRetries() {
        assertTrue(preferences.edit().putBoolean("publication_renewable", true)
            .putBoolean("publication_complete", true).commit())
        var commits = 0
        var failing = true
        // Memory loses the flag either way.
        val store = PhoneWidgetPublicationStore(editing { editor -> committing(editor) { commits++; !failing } })
        assertFalse(store.retireRenewal())
        assertEquals("the injected failure", 1, commits)
        assertFalse(preferences.contains("publication_renewable"))
        assertTrue("only the renewal flag retires", preferences.getBoolean("publication_complete", false))
        assertFalse("a retry cannot infer the removal from memory", store.retireRenewal())
        assertEquals(2, commits)
        failing = false
        assertTrue(store.retireRenewal())
        assertEquals(3, commits)
        assertTrue(store.retireRenewal())
        assertEquals(3, commits)

        // A fixture write's failed commit also removes the flag from memory only.
        assertTrue(preferences.edit().putBoolean("publication_renewable", true).commit())
        val engine = PhoneWidgetPublicationStore.engine(context)
        val fixture = engine.reserveWidgetPublication(OWNER, store.sequence() ?: 0L)
        failing = true
        val attempted = commits
        assertEquals(false, store.publish(WidgetPublicationFixture.payload("fixture", 1, 20), null, fixture, engine,
            proven = false))
        val published = commits
        assertTrue("the injected publication failure", published > attempted)
        assertFalse(preferences.contains("publication_renewable"))
        failing = false
        assertTrue(store.retireRenewal())
        assertEquals(published + 1, commits)
        assertTrue(store.retireRenewal())
        assertEquals(published + 1, commits)
    }

    fun testRetiredRowsAndStaleFlagAreIneligibleForRedraw() {
        val initial = PhoneWidgetPublicationStore.Mode("install", 0L, "live")
        val mock = PhoneWidgetPublicationStore.Mode("install", 1L, "mock")
        val returned = PhoneWidgetPublicationStore.Mode("install", 2L, "live")
        val store = PhoneWidgetPublicationStore(preferences)
        val rows = WidgetPublicationFixture.payload("old", 2, 10)

        assertTrue(store.publish(rows))
        assertEquals(2, initial.eligibleRows(preferences.all)["row_count"])
        assertTrue(mock.eligibleRows(preferences.all).isEmpty())
        assertTrue(store.publish(rows, mock))
        assertEquals(true, store.markStale(mock))
        val retired = preferences.all
        assertEquals("1", mock.eligibleRows(retired)["stale"])
        assertTrue(returned.eligibleRows(retired).isEmpty())
        assertTrue(mock.copy(installId = "other-install").eligibleRows(retired).isEmpty())
        assertNull(store.markStale(returned))
        assertEquals(retired, preferences.all)

        assertTrue(store.publish(rows, returned))
        assertEquals("0", returned.eligibleRows(preferences.all)["stale"])
        assertEquals(2, returned.eligibleRows(preferences.all)["row_count"])
    }

    fun testTicketsOrderPublicationsAndDelayedRedraws() {
        // Issue, commit and launcher delivery share the process-wide authority.
        val engine = PhoneWidgetPublicationStore.engine(context)
        val store = PhoneWidgetPublicationStore(preferences)
        fun begin() = engine.beginWidgetLoad { store.sequence() ?: 0L }
        fun accept(load: Long) = engine.acceptSnapshotLoad(load, null,
            null, emptyMap<String, Long>(), emptyMap<String, Map<String, Any>>(), emptyMap<String, String>())
        val headless = begin()
        val foreground = begin()
        val revision = foreground["settingsRevision"] as Long
        fun issue(load: Map<String, Any>) = engine.issueWidgetPublication(OWNER, load["load"] as Long, null,
            revision, store.sequence() ?: 0L,
            null, emptyMap<String, Long>(), emptyMap<String, Map<String, Any>>(), emptyMap<String, String>())
        assertTrue(accept(foreground["load"] as Long))
        assertFalse("late headless acceptance", accept(headless["load"] as Long))
        val a = WidgetPublicationFixture.payload("A", 2, 10)
        val first = issue(foreground)!!
        assertEquals(true, store.publish(a, null, first, engine))
        val rendered = PhoneWidgetPublicationStore.sequenceOf(preferences.all)
        assertNull("late headless result", issue(headless))

        val b = WidgetPublicationFixture.payload("B", 3, 70)
        val edit = issue(foreground)!!
        assertNull("superseded ticket", store.publish(a, null, first, engine))
        assertEquals(true, store.publish(b, null, edit, engine))
        WidgetPublicationFixture.assertStored(context, preferences, b, "slot edit re-ticket")
        val mode = PhoneWidgetPublicationStore.currentMode(context)
        var delivered = "none"
        mode.deliverIfCurrent(context, preferences, 1, rendered, true) { delivered = "A" }
        assertEquals("delayed redraw of a replaced publication", "none", delivered)
        mode.deliverIfCurrent(context, preferences, 1, store.sequence(), true) { delivered = "B" }
        assertEquals("B", delivered)
        // Another widget's frame of B is rendered; a slot save settles before its dispatch.
        val held = store.sequence()
        engine.finishSurfaceSettingsWrite(OWNER, engine.beginSurfaceSettingsWrite(OWNER))
        mode.deliverIfCurrent(context, preferences, 2, held, true) { delivered = "retired B" }
        assertEquals("first frame of rows a save retired", "B", delivered)
        mode.deliverIfCurrent(context, preferences, 1, held, true) { delivered = "retained B" }
        assertEquals("retained B", delivered)
        // A frame that shows none of B's rows, such as a no-fit frame, needs only the stored-sequence fence.
        mode.deliverIfCurrent(context, preferences, 2, held, false) { delivered = "no-fit" }
        assertEquals("no-fit", delivered)
        fun recorded(key: String) = preferences.getStringSet(key, null)
        assertEquals("widgets holding a frame of B", setOf("1", "2"), recorded("publication_framed"))
        assertEquals("widgets showing B's rows", setOf("1"), recorded("publication_delivered"))
        // Its frame granted no retained redraw: enlarging it cannot reveal the retired rows.
        mode.deliverIfCurrent(context, preferences, 2, held, true) { delivered = "resized B" }
        assertEquals("no-fit", delivered)
        assertEquals("the refused widget is owed a frame", setOf("1"), recorded("publication_framed"))

        assertNull("late failure", store.markStale(null, headless["observed"] as Long, engine))
        val failed = begin()
        assertEquals(edit, failed["observed"])
        assertEquals(true, store.markStale(null, failed["observed"] as Long, engine))
        WidgetPublicationFixture.assertStored(context, preferences, b + ("stale" to "1"), "observed STALE")
        assertEquals(edit + 1, store.sequence())
        assertTrue(store.publish(a))
        assertNull("unordered fixture write", store.sequence())
    }

    fun testExplicitEmptyResultNeedsPublicationAuthority() {
        val engine = PhoneWidgetPublicationStore.engine(context)
        val store = PhoneWidgetPublicationStore(preferences)
        val provider = WardPulseAppWidget()
        val options = Bundle().apply {
            putInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH, 360)
            putInt(AppWidgetManager.OPTION_APPWIDGET_MAX_WIDTH, 360)
            putInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT, 600)
            putInt(AppWidgetManager.OPTION_APPWIDGET_MAX_HEIGHT, 600)
        }
        // Whether the frame refresh renders from the stored rows needs their authority.
        fun frame(rows: Map<String, *>) = provider.publication(context, 0, rows, options, PhoneWidgetLayout.MAX_BITMAP_BYTES)
        fun content(eligible: Boolean) = (if (eligible) preferences.all else emptyMap<String, Any>()).let {
            provider.ownContent(it, frame(it))
        }
        val load = engine.beginWidgetLoad { store.sequence() ?: 0L }
        val ordinal = load["load"] as Long
        assertTrue(engine.acceptSnapshotLoad(ordinal, null,
            null, emptyMap<String, Long>(), emptyMap<String, Map<String, Any>>(), emptyMap<String, String>()))
        val ticket = engine.issueWidgetPublication(OWNER, ordinal, null, load["settingsRevision"] as Long,
            store.sequence() ?: 0L,
            null, emptyMap<String, Long>(), emptyMap<String, Map<String, Any>>(), emptyMap<String, String>())!!
        // The user cleared every slot; that explicit empty result commits.
        assertEquals(true, store.publish(WidgetPublicationFixture.payload("empty", 0, 0), null, ticket, engine))
        assertTrue("explicit empty result", content(true))
        assertFalse("neutral outgoing-mode clear", content(false))
        val mode = PhoneWidgetPublicationStore.currentMode(context)
        val held = store.sequence()
        var delivered = "none"
        mode.deliverIfCurrent(context, preferences, 1, held, content(true)) { delivered = "current empty" }
        assertEquals("current empty", delivered)
        // Widget 2's empty frame is held while the user saves a nonempty selection.
        engine.finishSurfaceSettingsWrite(OWNER, engine.beginSurfaceSettingsWrite(OWNER))
        mode.deliverIfCurrent(context, preferences, 2, held, content(true)) { delivered = "retired empty" }
        assertEquals("a retired empty result keeps the retained frame", "current empty", delivered)
        mode.deliverIfCurrent(context, preferences, 2, held, content(false)) { delivered = "clear" }
        assertEquals("the neutral clear needs no authority", "clear", delivered)
        // A Claude Plan pause can filter every stored row out of a nonempty publication; that
        // frame shows none of its content, so it clears the launcher without first-delivery authority.
        val paused = WidgetPublicationFixture.payload("paused", 2, 10)
        assertFalse("a frame the pause emptied", provider.ownContent(paused, frame(preferences.all)))
        assertTrue("its unfiltered rows", provider.ownContent(paused, frame(paused)))
    }

    fun testEstablishedRequiresCompletePublicationOfSavedSettings() {
        val engine = ConnectionCacheEngine(object : ConnectionCacheEngine.Backend {
            override fun read(): Map<String, String> = emptyMap()
            override fun commit(values: Map<String, String>) = true
        })
        val record = engine.initializeMode(false)
        val mode = PhoneWidgetPublicationStore.Mode(record["installId"] as String, record["generation"] as Long,
            record["mode"] as String)
        val store = PhoneWidgetPublicationStore(preferences)
        fun begin() = engine.beginWidgetLoad { store.sequence() ?: 0L }
        // Cutover-era rows carry the mode tags but no full ticketed publication.
        assertTrue(store.publish(WidgetPublicationFixture.payload("A", 2, 10), mode))
        assertFalse("cutover rows", store.established(mode))
        assertEquals(true, store.markStale(mode, begin()["observed"] as Long, engine))
        assertFalse("STALE-only write", store.established(mode))

        val load = begin()
        val ordinal = load["load"] as Long
        assertTrue(engine.acceptSnapshotLoad(ordinal, mode.generation,
            null, emptyMap<String, Long>(), emptyMap<String, Map<String, Any>>(), emptyMap<String, String>()))
        val ticket = engine.issueWidgetPublication("test", ordinal, mode.generation,
            load["settingsRevision"] as Long, store.sequence() ?: 0L,
            null, emptyMap<String, Long>(), emptyMap<String, Map<String, Any>>(), emptyMap<String, String>())!!
        assertEquals(true, store.publish(WidgetPublicationFixture.payload("B", 3, 70), mode, ticket, engine))
        assertTrue(store.established(mode))
        assertTrue("restart", PhoneWidgetPublicationStore(preferences).established(mode))
        // An installed widget without a frame of B, even after a restart, needs a fresh publication.
        assertFalse("undelivered widget", store.established(mode, listOf("7")))
        assertFalse("undelivered widget after restart",
            PhoneWidgetPublicationStore(preferences).established(mode, listOf("7")))

        // A slot save began; the process may die before its publication.
        val save = engine.beginSurfaceSettingsWrite("test")
        assertTrue(store.retireSettings())
        assertFalse("unpublished save after restart", PhoneWidgetPublicationStore(preferences).established(mode))
        assertEquals(true, store.markStale(mode, begin()["observed"] as Long, engine))
        assertFalse("STALE keeps the save unpublished", store.established(mode))

        // The rebuild's disk commit fails after updating memory; the next cadence-denied load rebuilds again.
        engine.finishSurfaceSettingsWrite("test", save)
        val failing = PhoneWidgetPublicationStore(editing { editor ->
            object : SharedPreferences.Editor by editor {
                // Inject the failure result after a real commit; do not claim a reproduced disk fault.
                override fun commit(): Boolean { assertTrue(editor.commit()); return false }
            }
        })
        val rebuild = begin()
        val rebuildLoad = rebuild["load"] as Long
        assertTrue(engine.acceptSnapshotLoad(rebuildLoad, mode.generation,
            null, emptyMap<String, Long>(), emptyMap<String, Map<String, Any>>(), emptyMap<String, String>()))
        val unconfirmed = engine.issueWidgetPublication("test", rebuildLoad, mode.generation,
            rebuild["settingsRevision"] as Long, store.sequence() ?: 0L,
            null, emptyMap<String, Long>(), emptyMap<String, Map<String, Any>>(), emptyMap<String, String>())!!
        val rows = WidgetPublicationFixture.payload("C", 1, 40)
        assertEquals(false, failing.publish(rows, mode, unconfirmed, engine))
        WidgetPublicationFixture.assertStored(context, preferences, rows, "memory after failed rebuild")
        assertFalse("unconfirmed full commit", store.established(mode))
    }

    private fun editing(wrap: (SharedPreferences.Editor) -> SharedPreferences.Editor) =
        object : SharedPreferences by preferences {
            override fun edit() = wrap(preferences.edit())
        }

    /**
     * Injects [result] after a real commit of [editor]; do not claim a reproduced disk fault. Each
     * mutator returns this proxy, so a chained `remove(...).commit()` reaches the injection too.
     */
    private fun committing(editor: SharedPreferences.Editor, result: () -> Boolean): SharedPreferences.Editor =
        object : SharedPreferences.Editor by editor {
            override fun putString(key: String?, value: String?): SharedPreferences.Editor =
                also { editor.putString(key, value) }
            override fun putStringSet(key: String?, values: MutableSet<String>?): SharedPreferences.Editor =
                also { editor.putStringSet(key, values) }
            override fun putInt(key: String?, value: Int): SharedPreferences.Editor =
                also { editor.putInt(key, value) }
            override fun putLong(key: String?, value: Long): SharedPreferences.Editor =
                also { editor.putLong(key, value) }
            override fun putFloat(key: String?, value: Float): SharedPreferences.Editor =
                also { editor.putFloat(key, value) }
            override fun putBoolean(key: String?, value: Boolean): SharedPreferences.Editor =
                also { editor.putBoolean(key, value) }
            override fun remove(key: String?): SharedPreferences.Editor = also { editor.remove(key) }
            override fun clear(): SharedPreferences.Editor = also { editor.clear() }
            override fun commit(): Boolean { assertTrue(editor.commit()); return result() }
        }

    private fun afterStaging(field: String, action: () -> Unit) = editing { editor ->
        object : SharedPreferences.Editor by editor {
            override fun putString(key: String?, value: String?): SharedPreferences.Editor {
                editor.putString(key, value)
                if (key == field) action()
                return this
            }
        }
    }

    private fun worker(failure: AtomicReference<Throwable?>, action: () -> Unit) = Thread {
        try { action() } catch (error: Throwable) { failure.compareAndSet(null, error) }
    }.apply { start() }

    private fun await(latch: CountDownLatch) {
        assertTrue("Publication barrier timed out", latch.await(10, TimeUnit.SECONDS))
    }

    private fun join(worker: Thread) {
        worker.join(10_000)
        assertFalse("Publication worker did not retire", worker.isAlive)
    }
}

private const val OWNER = "publication-test"

/** Shared, fixed inputs and consumer assertions for native and Dart-origin publications. */
internal object WidgetPublicationFixture {
    const val PACKAGE = "app.wardpulse.widgetpublicationtest"
    private val fields = listOf("kind", "spent_minor", "spent_currency", "cap_minor", "cap_currency",
        "extra_used_value", "extra_used_unit", "extra_cap_value", "extra_cap_unit",
        "percent", "credits", "label", "family", "pool", "resets_at", "color")

    fun payload(tag: String, count: Int, value: Int, stale: Boolean = false): Map<String, Any> =
        linkedMapOf<String, Any>("row_count" to count, "empty" to if (count == 0) "1" else "0",
            "stale" to if (stale) "1" else "0").apply {
            for (slot in 0 until 6) for (field in fields) put("row_${slot}_$field", "")
            for (slot in 0 until count) {
                put("row_${slot}_kind", "allowance")
                put("row_${slot}_label", "$tag $slot")
                put("row_${slot}_family", tag)
                put("row_${slot}_pool", "Pool $slot")
                put("row_${slot}_percent", "${value + slot}% left")
                put("row_${slot}_credits", "${value + slot} credits")
                put("row_${slot}_resets_at", "2028-02-10T09:15:00.000Z")
                put("row_${slot}_color", "ff91c4b1")
            }
        }

    fun assertStored(context: Context, preferences: SharedPreferences, expected: Map<String, Any>, phase: String) {
        val snapshot = preferences.all
        val options = Bundle().apply {
            putInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH, 360)
            putInt(AppWidgetManager.OPTION_APPWIDGET_MAX_WIDTH, 360)
            putInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT, 600)
            putInt(AppWidgetManager.OPTION_APPWIDGET_MAX_HEIGHT, 600)
        }
        val publication = WardPulseAppWidget().publication(context, 0, snapshot, options,
            PhoneWidgetLayout.MAX_BITMAP_BYTES)
        for (plan in publication.plans) {
            val count = expected["row_count"] as Int
            assertEquals(phase, count, plan.rows.size)
            assertEquals(phase, if (count == 0) PhoneWidgetLayout.EmptyState.NO_METRICS
                else PhoneWidgetLayout.EmptyState.NONE, plan.state)
            assertEquals(phase, expected["stale"] == "1", plan.text.any { it.text == "STALE" })
            for ((slot, visible) in plan.rows.withIndex()) {
                assertEquals(phase, expected["row_${slot}_label"], visible.row.identity)
                assertEquals(phase, expected["row_${slot}_family"], visible.row.family)
                assertEquals(phase, expected["row_${slot}_pool"], visible.row.pool)
                assertEquals(phase, (expected["row_${slot}_percent"] as String).removeSuffix(" left"), visible.row.percent)
                assertEquals(phase, (expected["row_${slot}_credits"] as String).removeSuffix(" credits"), visible.row.credits)
                assertEquals(phase, 0xff91c4b1.toInt(), visible.row.color)
                assertTrue(phase, visible.row.reset.startsWith("Reset "))
            }
        }
        assertEquals(phase, expected, snapshot.filterKeys { it in expected })
    }
}
