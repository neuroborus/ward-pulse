package app.wardpulse

import android.content.Context
import android.content.SharedPreferences
import android.test.InstrumentationTestCase
import app.wardpulse.watchsync.WatchPublication
import app.wardpulse.watchsync.WatchPublicationStore
import junit.framework.Assert.assertEquals
import junit.framework.Assert.assertFalse
import junit.framework.Assert.assertNull
import junit.framework.Assert.assertTrue

/**
 * The desired watch publication over real isolated preferences: a failed commit feeds neither a
 * put, an owner reply nor the order floor, in this process or a store opened after it, and a
 * settings save's retirement is durable once confirmed.
 */
@Suppress("DEPRECATION")
class WatchPublicationStoreTest : InstrumentationTestCase() {
    private lateinit var preferences: SharedPreferences
    private var failing = false

    override fun setUp() {
        super.setUp()
        preferences = instrumentation.targetContext.applicationContext
            .getSharedPreferences(NAME, Context.MODE_PRIVATE)
        assertTrue(preferences.edit().clear().commit())
    }

    override fun tearDown() {
        try {
            if (::preferences.isInitialized) assertTrue(preferences.edit().clear().commit())
        } finally {
            super.tearDown()
        }
    }

    fun testFailedWriteKeepsTheConfirmedPublication() {
        val store = WatchPublicationStore(failingPreferences())
        val confirmed = publication(7L, "confirmed")
        assertTrue(store.write(confirmed))
        failing = true
        assertFalse(store.write(publication(8L, "unconfirmed").copy(selection = "{}")))
        failing = false
        // What resume or an owner reply reads next, then a store opened as a new process would.
        assertEquals(confirmed, store.read())
        assertEquals(7L, store.lastSequence())
        val restarted = WatchPublicationStore(preferences)
        assertEquals(confirmed, restarted.read())
        assertEquals(7L, restarted.lastSequence())
        assertFalse(preferences.contains("selection"))
    }

    fun testFailedFirstWriteLeavesNoPublication() {
        val store = WatchPublicationStore(failingPreferences())
        failing = true
        assertFalse(store.write(publication(1L, "unconfirmed")))
        failing = false
        assertNull(store.read())
        assertEquals(0L, store.lastSequence())
        assertNull(WatchPublicationStore(preferences).read())
    }

    fun testSettingsRetirementIsDurableAndAFailedOneIsNotKept() {
        val store = WatchPublicationStore(failingPreferences())
        assertTrue(store.write(publication(3L, "built")))
        failing = true
        assertFalse(store.retireSettings())
        failing = false
        assertFalse(store.read()!!.retired)

        assertTrue(store.retireSettings())
        assertTrue(WatchPublicationStore(preferences).read()!!.retired)
        // A replacement built from the saved settings is sendable again.
        assertTrue(store.write(publication(4L, "rebuilt")))
        assertFalse(WatchPublicationStore(preferences).read()!!.retired)

        // An empty placeholder carries no settings.
        assertTrue(store.write(publication(5L, "empty").copy(placeholder = true)))
        assertTrue(store.retireSettings())
        assertFalse(store.read()!!.retired)
    }

    private fun publication(sequence: Long, label: String) = WatchPublication(
        sequence = sequence,
        installId = INSTALL_ID,
        generation = 2L,
        payload = """{"label":"$label"}""",
        summary = """{"label":"$label","sequence":$sequence}""",
    )

    /**
     * Injects a failed result after a real commit while [failing]; do not claim a reproduced
     * disk fault. Android keeps a failed commit in memory, which the real commit stands in for.
     */
    private fun failingPreferences(): SharedPreferences =
        object : SharedPreferences by preferences {
            override fun edit(): SharedPreferences.Editor {
                val editor = preferences.edit()
                return object : SharedPreferences.Editor by editor {
                    override fun putString(key: String?, value: String?): SharedPreferences.Editor =
                        also { editor.putString(key, value) }
                    override fun putLong(key: String?, value: Long): SharedPreferences.Editor =
                        also { editor.putLong(key, value) }
                    override fun putBoolean(key: String?, value: Boolean): SharedPreferences.Editor =
                        also { editor.putBoolean(key, value) }
                    override fun remove(key: String?): SharedPreferences.Editor = also { editor.remove(key) }
                    override fun clear(): SharedPreferences.Editor = also { editor.clear() }
                    override fun commit(): Boolean {
                        assertTrue(editor.commit())
                        return !failing
                    }
                }
            }
        }

    private companion object {
        const val NAME = "wardpulse.watch-publication.test"
        const val INSTALL_ID = "00000000-0000-4000-8000-000000000001"
    }
}
