package app.wardpulse.wear.data

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import androidx.wear.watchface.complications.data.NoDataComplicationData
import androidx.wear.watchface.complications.data.RangedValueComplicationData
import app.wardpulse.wear.complication.CREDITS_RING_INDEX
import app.wardpulse.wear.complication.WatchComplicationText
import app.wardpulse.wear.complication.creditsOnlyComplicationData
import app.wardpulse.wear.complication.outerHalfComplicationData
import app.wardpulse.wear.complication.rangedComplicationBuilder
import app.wardpulse.wear.complication.ringComplicationData
import app.wardpulse.wear.model.AllowanceSummary
import app.wardpulse.wear.model.CreditsGlance
import app.wardpulse.wear.model.Money
import app.wardpulse.wear.model.PeriodSummary
import app.wardpulse.wear.model.PreviewWatchDashboardSummary
import app.wardpulse.wear.model.ProviderSummary
import app.wardpulse.wear.model.PulseStatus
import app.wardpulse.wear.model.Quantity
import app.wardpulse.wear.model.RingHalf
import app.wardpulse.wear.model.RingSummary
import app.wardpulse.wear.model.WatchDataMode
import app.wardpulse.wear.ui.RingFamily
import java.time.Instant
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.json.JSONObject

@RunWith(AndroidJUnit4::class)
class WatchSummaryStoreTest {
    private val context = ApplicationProvider.getApplicationContext<Context>()
    private val testContext = InstrumentationRegistry.getInstrumentation().context
    private val preferencesName = "watch_summary_test_${System.nanoTime()}"
    private val preferences = context.getSharedPreferences(preferencesName, Context.MODE_PRIVATE)
    private val store = WatchSummaryStore(preferences)

    @After
    fun cleanUp() {
        assertTrue(preferences.edit().clear().commit())
        assertTrue(context.deleteSharedPreferences(preferencesName))
    }

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

    /**
     * The paired fixture is the phone's own output, asserted byte for byte by
     * `watch_sync_service_test.dart` — so this parses what the phone writes,
     * not a literal written here to match it.
     */
    @Test
    fun keepsBothPoolsOfASplitBand() {
        val encoded = testContext.assets.open("watch_dashboard_summary_paired.json")
            .bufferedReader()
            .use { it.readText() }

        assertTrue(store.saveEncoded(encoded))
        // One entry is one band, and its second pool rides inside it.
        val rings = store.load()?.rings.orEmpty()
        assertEquals(1, rings.size)
        assertEquals("allowance.cursor.cursor-plan-other", rings.first().split?.id)
        assertEquals(62.0, rings.first().split?.usedPercent)
    }

    /** Canonical decoding and construction only; no service delivery or WFF paint evidence. */
    @Test
    fun creditsAndBudgetFixturesBuildExactComplicationEnvelopes() {
        val expectedRings = linkedMapOf(
            "credits_only" to emptyList(),
            "plan_credits" to listOf(
                RingSummary("allowance.codex.plan", "Codex plan", 63.0, PulseStatus.OK),
            ),
            "n1_full_below" to listOf(
                RingSummary("allowance.codex.plan", "Codex plan", 96.11003088951111, PulseStatus.OK),
            ),
            "n1_full_above" to listOf(
                RingSummary("allowance.codex.plan", "Codex plan", 96.11003041267395, PulseStatus.OK),
            ),
            "n1_week_near_full" to listOf(
                RingSummary(
                    "budget.anthropic.platform.week", "Anthropic week", 0.1, PulseStatus.OK,
                    spent = Money(10, "USD"), limit = Money(10_000, "USD"),
                ),
            ),
            "n2_week_day" to listOf(
                RingSummary(
                    "budget.anthropic.platform.week", "Anthropic week", 75.0, PulseStatus.OK,
                    spent = Money(7_500, "USD"), limit = Money(10_000, "USD"),
                ),
                RingSummary(
                    "budget.openai.platform.today", "OpenAI today", 40.0, PulseStatus.OK,
                    spent = Money(4_000, "USD"), limit = Money(10_000, "USD"),
                ),
            ),
            "n2_month_month" to listOf(
                RingSummary(
                    "budget.anthropic.platform.month", "Anthropic month", 0.1, PulseStatus.OK,
                    spent = Money(10, "USD"), limit = Money(10_000, "USD"),
                ),
                RingSummary(
                    "budget.openai.platform.month", "OpenAI month", 0.0, PulseStatus.OK,
                    spent = Money(0, "USD"), limit = Money(20_000, "USD"),
                ),
            ),
        )
        // Literal VALUE/TITLE/TEXT in outside-slot order, independent of production routing.
        val expectedRows = mapOf(
            "credits_only" to listOf(Triple(100f, "credits", "500")),
            "plan_credits" to listOf(Triple(74f, "", "37% · 320")),
            "n1_full_below" to listOf(Triple(7.779938220977783f, "", "4%")),
            "n1_full_above" to listOf(Triple(7.7799391746521f, "", "4%")),
            "n1_week_near_full" to listOf(Triple(199.8000030517578f, "7D", "\$0.10/100")),
            "n2_week_day" to listOf(
                Triple(240f, "D", "\$40.00/100"),
                Triple(100f, "7D", "\$75.00/100"),
            ),
            "n2_month_month" to listOf(
                Triple(400f, "M", "\$0.00/200"),
                Triple(399.6000061035156f, "M", "\$0.10/100"),
            ),
        )
        val expectedDescriptions = mapOf(
            "credits_only" to listOf("500 100%"),
            "plan_credits" to listOf("Codex plan 37%"),
            "n1_full_below" to listOf("Codex plan 4%"),
            "n1_full_above" to listOf("Codex plan 4%"),
            "n1_week_near_full" to listOf("Anthropic week 100%"),
            "n2_week_day" to listOf("OpenAI today 60%", "Anthropic week 25%"),
            "n2_month_month" to listOf("OpenAI month 100%", "Anthropic month 100%"),
        )
        val expectedColors = mapOf(
            "credits_only" to listOf(RingFamily.CODEX),
            "plan_credits" to listOf(RingFamily.CODEX),
            "n1_full_below" to listOf(RingFamily.CODEX),
            "n1_full_above" to listOf(RingFamily.CODEX),
            "n1_week_near_full" to listOf(RingFamily.CLAUDE),
            "n2_week_day" to listOf(RingFamily.CODEX, RingFamily.CLAUDE),
            "n2_month_month" to listOf(RingFamily.CODEX, RingFamily.CLAUDE),
        )
        val resources = context.resources
        val now = Instant.EPOCH
        for ((suffix, rings) in expectedRings) {
            val encoded = testContext.assets.open("watch_dashboard_summary_$suffix.json")
                .bufferedReader()
                .use { it.readText() }
            assertTrue(suffix, store.saveEncoded(encoded))
            val summary = requireNotNull(store.load())
            assertEquals(9, summary.schemaVersion)
            assertEquals(WatchDataMode.MOCK, summary.dataMode)
            assertEquals("2026-06-27T18:42:00.000Z", summary.generatedAt)
            assertEquals(PulseStatus.OK, summary.overallStatus)
            assertTrue(summary.manualRefreshAllowed)
            assertNull(summary.manualRefreshAvailableAt)
            assertFalse(summary.isStale)
            assertTrue(summary.alerts.isEmpty())
            assertEquals(suffix, rings, summary.rings)
            assertEquals(
                PeriodSummary("today", null, null, null, null, null, PulseStatus.UNKNOWN),
                summary.today,
            )
            assertEquals(
                PeriodSummary("week", null, null, null, null, null, PulseStatus.UNKNOWN),
                summary.week,
            )
            val providers = when (suffix) {
                "credits_only", "n1_full_below", "n1_full_above" -> listOf("codex")
                "plan_credits" -> listOf("codex", "claude")
                "n1_week_near_full" -> listOf("claude")
                else -> listOf("claude", "openai")
            }
            assertEquals(providers.map { ProviderSummary(it, PulseStatus.OK, null) }, summary.providers)
            val allowances = when (suffix) {
                "credits_only" -> listOf(
                    AllowanceSummary(
                        "purchased", "Codex · Credits", null, Quantity("500", "credits"),
                        unlimited = false, resetsAt = null, status = PulseStatus.OK,
                    ),
                )
                "plan_credits" -> listOf(
                    AllowanceSummary(
                        "purchased", "Codex · Credits", null, Quantity("320", "credits"),
                        unlimited = false, resetsAt = null, status = PulseStatus.OK,
                    ),
                    AllowanceSummary(
                        "purchased", "Claude · Extra usage", null, Quantity("80", "credits"),
                        unlimited = false, resetsAt = null, status = PulseStatus.OK,
                    ),
                )
                else -> emptyList()
            }
            assertEquals(allowances, summary.allowances)
            assertEquals(
                when (suffix) {
                    "credits_only" -> CreditsGlance("500", "Credits left", "codex")
                    "plan_credits" -> CreditsGlance("400", "Credits left", null)
                    else -> null
                },
                summary.creditsGlance,
            )
            val payloadIndices = when (suffix) {
                "credits_only" -> emptyList()
                "n2_week_day", "n2_month_month" -> listOf(1, 0)
                else -> listOf(0)
            }
            val maximum = when (suffix) {
                "credits_only" -> 100f
                "n2_week_day", "n2_month_month" -> 400f
                else -> 200f
            }
            for (outside in 0..2) {
                val expected = expectedRows.getValue(suffix).getOrNull(outside)
                if (expected == null) {
                    assertTrue(ringComplicationData(summary.rings, outside) { _, _, _, _ ->
                        error("$suffix: obsolete main $outside must clear")
                    } is NoDataComplicationData)
                    assertNull(WatchComplicationText.stripLabel(summary, outside))
                    continue
                }
                val data = (if (suffix == "credits_only") {
                    assertEquals(0, CREDITS_RING_INDEX)
                    assertTrue(ringComplicationData(summary.rings, outside) { _, _, _, _ ->
                        error("Credits do not supply a ring")
                    } is NoDataComplicationData)
                    creditsOnlyComplicationData(summary) { label, color ->
                        assertEquals("500", label)
                        assertEquals(RingFamily.CODEX, color)
                        rangedComplicationBuilder(
                            100f, "credits", color, contentDescription = label, text = label,
                        ).build()
                    }
                } else {
                    val payloadIndex = payloadIndices[outside]
                    ringComplicationData(summary.rings, outside) { ring, remaining, title, count ->
                        assertEquals(rings[payloadIndex], ring)
                        assertEquals(rings.size, count)
                        assertEquals(expected.first / (maximum / 100f), remaining)
                        assertEquals(expected.second, title)
                        rangedComplicationBuilder(
                            remaining, title, RingFamily.colorArgb(ring.id),
                            contentDescription = ring.label,
                            text = WatchComplicationText.stripLabel(summary, payloadIndex),
                            ringCount = count,
                        ).build()
                    }
                }) as RangedValueComplicationData
                assertEquals(RangedValueComplicationData.TYPE_UNDEFINED, data.valueType)
                assertEquals(0f, data.min)
                assertEquals(maximum, data.max)
                assertEquals(expected.first, data.value)
                assertEquals(expected.second, data.title!!.getTextAt(resources, now).toString())
                assertEquals(expected.third, data.text!!.getTextAt(resources, now).toString())
                assertEquals(
                    expectedDescriptions.getValue(suffix)[outside],
                    data.contentDescription!!.getTextAt(resources, now).toString(),
                )
                assertEquals(expectedColors.getValue(suffix)[outside], data.colorRamp!!.colors.single())
                when (suffix) {
                    // The current 360/44 cutoff; these bracket Float(100c), not decimal approximations.
                    "n1_full_below" -> assertTrue(data.value / data.max <= 0.03889969435954432)
                    "n1_full_above" -> assertTrue(data.value / data.max > 0.03889969435954432)
                    "n1_week_near_full" -> assertTrue(data.value < data.max)
                    "n2_month_month" -> if (outside == 1) assertTrue(data.value < data.max)
                }
            }
            for (ordinal in 0..1) {
                assertTrue(outerHalfComplicationData(summary.rings, ordinal) { _, _, _ ->
                    error("$suffix: obsolete extra $ordinal must clear")
                } is NoDataComplicationData)
            }
        }
    }

    /** N1 paired decoder/construction witnesses, independent of delivery and native paint. */
    @Test
    fun n1PairedFixturesKeepIndependentEndpointsAndCutoffs() {
        val expectedUsage = linkedMapOf(
            "n1_pair_zero_full" to (100.0 to 0.0),
            "n1_pair_tiny_near_full" to (99.96875 to 0.1),
            "n1_pair_below_above" to (97.92720222473145 to 98.1661571264267),
            "n1_pair_above_below" to (97.92720174789429 to 98.16615736484528),
            "n1_pair_near_full_tiny" to (0.1 to 99.96875),
            "n1_pair_full_zero" to (0.0 to 100.0),
            "n1_pair_both_zero" to (100.0 to 100.0),
        )
        // Literal wire values in main/extra order, not computed by the production decoder.
        val expectedValues = mapOf(
            "n1_pair_zero_full" to listOf(0f, 200f),
            "n1_pair_tiny_near_full" to listOf(0.0625f, 199.8000030517578f),
            "n1_pair_below_above" to listOf(4.145595550537109f, 3.6676857471466064f),
            "n1_pair_above_below" to listOf(4.145596504211426f, 3.6676852703094482f),
            "n1_pair_near_full_tiny" to listOf(199.8000030517578f, 0.0625f),
            "n1_pair_full_zero" to listOf(200f, 0f),
            "n1_pair_both_zero" to listOf(0f, 0f),
        )
        val expectedTitles = mapOf(
            "n1_pair_zero_full" to "split:spark:zero-inner",
            "n1_pair_tiny_near_full" to "split:spark",
            "n1_pair_below_above" to "split:spark",
            "n1_pair_above_below" to "split:spark",
            "n1_pair_near_full_tiny" to "split:spark",
            "n1_pair_full_zero" to "split:spark:zero-outer",
            "n1_pair_both_zero" to "split:spark:zero-both",
        )
        val expectedAmounts = mapOf(
            "n1_pair_zero_full" to listOf("0", "100"),
            "n1_pair_tiny_near_full" to listOf("0", "100"),
            "n1_pair_below_above" to listOf("2", "2"),
            "n1_pair_above_below" to listOf("2", "2"),
            "n1_pair_near_full_tiny" to listOf("100", "0"),
            "n1_pair_full_zero" to listOf("100", "0"),
            "n1_pair_both_zero" to listOf("0", "0"),
        )
        val resources = context.resources
        val now = Instant.EPOCH
        for ((suffix, usage) in expectedUsage) {
            val encoded = testContext.assets.open("watch_dashboard_summary_$suffix.json")
                .bufferedReader()
                .use { it.readText() }
            assertTrue(suffix, store.saveEncoded(encoded))
            val summary = requireNotNull(store.load())
            val expectedHalf = RingHalf("allowance.codex.spark", "Spark", usage.second, PulseStatus.OK)
            val expectedRing = RingSummary(
                "allowance.codex.plan", "Codex plan", usage.first, PulseStatus.OK,
                split = expectedHalf,
            )
            assertEquals(suffix, listOf(expectedRing), summary.rings)
            assertEquals(9, summary.schemaVersion)
            assertEquals(WatchDataMode.MOCK, summary.dataMode)
            assertEquals("2026-06-27T18:42:00.000Z", summary.generatedAt)
            assertEquals(PulseStatus.OK, summary.overallStatus)
            assertTrue(summary.manualRefreshAllowed)
            assertNull(summary.manualRefreshAvailableAt)
            assertFalse(summary.isStale)
            assertEquals(
                PeriodSummary("today", null, null, null, null, null, PulseStatus.UNKNOWN),
                summary.today,
            )
            assertEquals(
                PeriodSummary("week", null, null, null, null, null, PulseStatus.UNKNOWN),
                summary.week,
            )
            assertEquals(listOf(ProviderSummary("codex", PulseStatus.OK, null)), summary.providers)
            assertNull(summary.creditsGlance)
            assertTrue(summary.allowances.isEmpty())
            assertTrue(summary.alerts.isEmpty())

            val values = expectedValues.getValue(suffix)
            val amounts = expectedAmounts.getValue(suffix)
            val mainTitle = expectedTitles.getValue(suffix)
            val main = ringComplicationData(summary.rings, 0) { ring, remaining, title, count ->
                assertEquals(expectedRing, ring)
                assertEquals(values[0] / 2f, remaining)
                assertEquals(mainTitle, title)
                assertEquals(1, count)
                rangedComplicationBuilder(
                    remaining, title, RingFamily.colorArgb(ring.id),
                    contentDescription = ring.label,
                    text = WatchComplicationText.stripLabel(summary, 0),
                    ringCount = count,
                ).build()
            } as RangedValueComplicationData
            val extra = outerHalfComplicationData(summary.rings, 0) { half, outside, count ->
                assertEquals(expectedHalf, half)
                assertEquals(0, outside)
                assertEquals(1, count)
                val remaining = WatchComplicationText.remainingPercent(half.usedPercent)
                assertEquals(values[1] / 2f, remaining)
                rangedComplicationBuilder(
                    remaining, outside.toString(), RingFamily.colorArgb(half.id),
                    contentDescription = half.label, ringCount = count,
                ).build()
            } as RangedValueComplicationData
            for ((pool, data) in listOf(main, extra).withIndex()) {
                assertEquals(suffix, RangedValueComplicationData.TYPE_UNDEFINED, data.valueType)
                assertEquals(0f, data.min)
                assertEquals(200f, data.max)
                assertEquals(values[pool], data.value)
                assertEquals(
                    if (pool == 0) mainTitle else "0",
                    data.title!!.getTextAt(resources, now).toString(),
                )
                assertEquals(
                    if (pool == 0) "${amounts[0]}% · ${amounts[1]}%" else amounts[1],
                    data.text!!.getTextAt(resources, now).toString(),
                )
                assertEquals(
                    if (pool == 0) "Codex plan ${amounts[0]}%" else "Spark ${amounts[1]}%",
                    data.contentDescription!!.getTextAt(resources, now).toString(),
                )
                assertEquals(
                    if (pool == 0) RingFamily.CODEX else RingFamily.CODEX_SPARK,
                    data.colorRamp!!.colors.single(),
                )
            }
            when (suffix) {
                "n1_pair_tiny_near_full" -> {
                    assertTrue(main.value > 0f)
                    assertTrue(extra.value < extra.max)
                }
                "n1_pair_near_full_tiny" -> {
                    assertTrue(main.value < main.max)
                    assertTrue(extra.value > 0f)
                }
                // Inner 338/22 and extra 382/22 have different two-cap cutoffs.
                "n1_pair_below_above" -> {
                    assertTrue(main.value.toDouble() / main.max <= 0.020727979994442904)
                    assertTrue(extra.value.toDouble() / extra.max > 0.018338427340928037)
                }
                "n1_pair_above_below" -> {
                    assertTrue(main.value.toDouble() / main.max > 0.020727979994442904)
                    assertTrue(extra.value.toDouble() / extra.max <= 0.018338427340928037)
                }
            }
            for (outside in 1..2) {
                assertTrue(ringComplicationData(summary.rings, outside) { _, _, _, _ ->
                    error("$suffix: obsolete main $outside must clear")
                } is NoDataComplicationData)
                assertNull(WatchComplicationText.stripLabel(summary, outside))
            }
            assertTrue(outerHalfComplicationData(summary.rings, 1) { _, _, _ ->
                error("$suffix: obsolete extra 1 must clear")
            } is NoDataComplicationData)
        }
    }

    @Test
    fun rejectsNonfiniteCoercedRingValuesWhileKeepingKnownExhaustion() {
        val encoded = testContext.assets.open("watch_dashboard_summary_paired.json")
            .bufferedReader()
            .use { it.readText() }
        val exhausted = JSONObject(encoded).apply {
            getJSONArray("rings").getJSONObject(0).apply {
                put("usedPercent", 100.0)
                getJSONObject("split").put("usedPercent", 100.0)
            }
        }.toString()
        assertTrue(store.saveEncoded(exhausted))

        for (outer in listOf(false, true)) {
            for (invalid in listOf("Infinity", "NaN", "1e400")) {
                val malformed = JSONObject(exhausted).apply {
                    val ring = getJSONArray("rings").getJSONObject(0)
                    val target = if (outer) ring.getJSONObject("split") else ring
                    target.put("usedPercent", invalid)
                }.toString()
                assertFalse(store.saveEncoded(malformed))
                assertEquals(100.0, store.load()?.rings?.single()?.usedPercent)
                assertEquals(100.0, store.load()?.rings?.single()?.split?.usedPercent)
            }
        }
    }

    @Test
    fun rejectsLegacyPayloadWithoutAnExplicitDataMode() {
        val encoded = testContext.assets.open("watch_dashboard_summary.json")
            .bufferedReader()
            .use { it.readText() }
            .replace("\"schemaVersion\": 9,", "\"schemaVersion\": 2,")
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
            .replace("\"schemaVersion\": 9,", "\"schemaVersion\": 7,")
        preferences.edit().putString("latest", encoded).commit()

        assertNull(store.load())
    }

    @Test
    fun ignoresCorruptedSummary() {
        preferences.edit().putString("latest", "not-json").commit()

        assertNull(store.load())
    }
}
