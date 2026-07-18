package app.wardpulse.wear.data

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import app.wardpulse.wear.model.MockWatchSummary
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class WatchSummaryStoreTest {
    private val context = ApplicationProvider.getApplicationContext<Context>()
    private val preferences = context.getSharedPreferences(
        "watch_summary_test_${System.nanoTime()}",
        Context.MODE_PRIVATE,
    )
    private val store = WatchSummaryStore(preferences)

    @Test
    fun persistsLatestSummary() {
        store.save(MockWatchSummary.value)

        assertEquals(MockWatchSummary.value, store.load())
    }

    @Test
    fun ignoresCorruptedSummary() {
        preferences.edit().putString("latest", "not-json").commit()

        assertNull(store.load())
    }
}
