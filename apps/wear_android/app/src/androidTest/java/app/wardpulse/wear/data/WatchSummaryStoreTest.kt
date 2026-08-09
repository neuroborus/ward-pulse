package app.wardpulse.wear.data

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import app.wardpulse.wear.model.Money
import app.wardpulse.wear.model.PreviewWatchDashboardSummary
import app.wardpulse.wear.model.WatchDataMode
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
        store.save(PreviewWatchDashboardSummary.value)

        assertEquals(PreviewWatchDashboardSummary.value, store.load())
    }

    @Test
    fun acceptsCanonicalTransportFixture() {
        val encoded = testContext.assets.open("watch_dashboard_summary.json")
            .bufferedReader()
            .use { it.readText() }

        assertTrue(store.saveEncoded(encoded))
        assertEquals("2026-06-27T18:42:00.000Z", store.load()?.generatedAt)
        assertEquals(WatchDataMode.MOCK, store.load()?.dataMode)
    }

    @Test
    fun rejectsLegacyPayloadWithoutAnExplicitDataMode() {
        val encoded = testContext.assets.open("watch_dashboard_summary.json")
            .bufferedReader()
            .use { it.readText() }
            .replace("\"schemaVersion\": 8,", "\"schemaVersion\": 2,")
            .replace("  \"dataMode\": \"mock\",\n", "")

        assertFalse(store.saveEncoded(encoded))
        assertNull(store.load())
    }

    @Test
    fun preservesUnlimitedPurchasedUsage() {
        val encoded = testContext.assets.open("watch_dashboard_summary.json")
            .bufferedReader()
            .use { it.readText() }
            .replace(
                "\"allowances\": []",
                """"allowances": [{"source":"purchased","label":"Purchased credits","usedPercent":null,"remaining":null,"unlimited":true,"resetsAt":null,"status":"ok"}]""",
            )

        assertTrue(store.saveEncoded(encoded))
        assertTrue(store.load()?.allowances?.single()?.unlimited == true)
    }

    /**
     * The fixture carries no ring — mock accounts hold no budget — so this is the only place
     * the phone's literal ring shape meets the parser. Wear's own round-trip cannot prove it:
     * it writes and reads the same keys, and would drift from the phone in step.
     */
    @Test
    fun readsBudgetMoneyInThePhoneWireShape() {
        val encoded = testContext.assets.open("watch_dashboard_summary.json")
            .bufferedReader()
            .use { it.readText() }
            .replace(
                "\"rings\": []",
                """"rings": [{"id":"budget.anthropic.platform.week","label":"Week","usedPercent":28.5,"status":"ok","spent":{"minorUnits":7130,"currency":"USD"},"limit":{"minorUnits":25000,"currency":"USD"}}]""",
            )

        assertTrue(store.saveEncoded(encoded))
        val ring = store.load()?.rings?.single()
        assertEquals(Money(7_130, "USD"), ring?.spent)
        assertEquals(Money(25_000, "USD"), ring?.limit)
    }

    @Test
    fun invalidSummaryKeepsPreviousState() {
        store.save(PreviewWatchDashboardSummary.value)

        assertFalse(store.saveEncoded("{\"schemaVersion\":3,\"rings\":[]}"))
        assertEquals(PreviewWatchDashboardSummary.value, store.load())
    }

    /** A schema bump throws away what the previous build stored — quietly, not by crashing. */
    @Test
    fun discardsASummaryStoredByAnOlderSchema() {
        val encoded = testContext.assets.open("watch_dashboard_summary.json")
            .bufferedReader()
            .use { it.readText() }
            .replace("\"schemaVersion\": 8,", "\"schemaVersion\": 7,")
        preferences.edit().putString("latest", encoded).commit()

        assertNull(store.load())
    }

    @Test
    fun ignoresCorruptedSummary() {
        preferences.edit().putString("latest", "not-json").commit()

        assertNull(store.load())
    }
}
