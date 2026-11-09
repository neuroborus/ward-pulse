package app.wardpulse

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.os.Bundle
import android.test.InstrumentationTestCase
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
        } finally { super.tearDown() }
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

    private fun editing(wrap: (SharedPreferences.Editor) -> SharedPreferences.Editor) =
        object : SharedPreferences by preferences {
            override fun edit() = wrap(preferences.edit())
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
