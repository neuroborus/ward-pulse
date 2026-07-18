package app.wardpulse.wear.data

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import app.wardpulse.wear.model.MockWatchDashboardSummary
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class WatchSummaryStoreTest {
    private val context = ApplicationProvider.getApplicationContext<Context>()
    private val testContext = InstrumentationRegistry.getInstrumentation().context
    private val preferences = context.getSharedPreferences(
        "watch_summary_test_${System.nanoTime()}",
        Context.MODE_PRIVATE,
    )
    private val store = WatchSummaryStore(preferences)

    @Test
    fun persistsLatestSummary() {
        store.save(MockWatchDashboardSummary.value)

        assertEquals(MockWatchDashboardSummary.value, store.load())
    }

    @Test
    fun acceptsCanonicalTransportFixture() {
        val encoded = testContext.assets.open("watch_dashboard_summary.json")
            .bufferedReader()
            .use { it.readText() }

        assertTrue(store.saveEncoded(encoded))
        assertEquals("2026-06-27T18:42:00.000Z", store.load()?.generatedAt)
    }

    @Test
    fun invalidSummaryKeepsPreviousState() {
        store.save(MockWatchDashboardSummary.value)

        assertFalse(store.saveEncoded("{\"schemaVersion\":2}"))
        assertEquals(MockWatchDashboardSummary.value, store.load())
    }

    @Test
    fun ignoresCorruptedSummary() {
        preferences.edit().putString("latest", "not-json").commit()

        assertNull(store.load())
    }
}
