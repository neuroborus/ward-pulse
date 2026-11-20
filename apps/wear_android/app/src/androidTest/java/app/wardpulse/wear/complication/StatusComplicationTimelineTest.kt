package app.wardpulse.wear.complication

import android.annotation.SuppressLint
import android.app.PendingIntent
import android.content.Context
import android.content.ContextWrapper
import android.content.Intent
import android.content.SharedPreferences
import android.os.Parcel
import android.support.wearable.complications.ComplicationData as WireComplicationData
import android.support.wearable.complications.IComplicationManager
import android.support.wearable.complications.IComplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import androidx.wear.watchface.complications.data.ComplicationData
import androidx.wear.watchface.complications.data.ComplicationType
import androidx.wear.watchface.complications.data.ShortTextComplicationData
import androidx.wear.watchface.complications.data.toApiComplicationData
import androidx.wear.watchface.complications.datasource.ComplicationDataSourceService
import app.wardpulse.wear.IsolatedActivityRule
import app.wardpulse.wear.MainActivity
import java.lang.reflect.Field
import java.time.Clock
import java.time.Instant
import java.time.ZoneOffset
import java.time.temporal.ChronoUnit
import java.util.concurrent.LinkedBlockingQueue
import java.util.concurrent.TimeUnit
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * The installed Status service's Binder reply, Parcel-transported as a watch face receives it.
 * Proves the emitted timeline and wire validity only, not renderer playback or redraw.
 */
@SuppressLint("RestrictedApi")
@RunWith(AndroidJUnit4::class)
class StatusComplicationTimelineTest {
    @get:Rule
    internal val isolation = IsolatedActivityRule()

    private val instrumentation = InstrumentationRegistry.getInstrumentation()
    private val context = instrumentation.targetContext
    private val replies = LinkedBlockingQueue<Reply>()
    private val manager = object : IComplicationManager.Stub() {
        override fun updateComplicationData(complicationInstanceId: Int, data: WireComplicationData?) {
            replies.put(Reply(complicationInstanceId, data?.let(::parcelled)))
        }
    }

    private data class Reply(val id: Int, val data: WireComplicationData?)

    /**
     * The service's Clock seam, found reflectively so these same test bytes also run against a
     * baseline Status service, which has no seam and keeps its ordinary clock.
     */
    private val clockSeam: Field? = StatusComplicationDataSourceService::class.java.declaredFields
        .singleOrNull { it.name == "clock" && it.type == Clock::class.java }
        ?.apply { isAccessible = true }

    @Test
    fun statusAgesAtTheStaleCutoffAndKeepsRequestTimeFreshness() {
        // The first cutoffs sit an hour past the fixed clock, so a service reading the
        // real clock classifies the first request identically.
        val base = Instant.now().truncatedTo(ChronoUnit.SECONDS)
        val live = fixture("watch_dashboard_summary_selected_ring_unavailable.json")
        val mock = fixture("watch_dashboard_summary_plan_credits.json")
        withService { _, request ->
            for ((offsetMillis, cutoffSeconds) in listOf(0L to 3600L, 250L to 3601L)) {
                val generated = base.minusSeconds(3600).plusMillis(offsetMillis)
                val cutoff = base.plusSeconds(cutoffSeconds)
                store(live.copyWith(generatedAt = generated))
                assertTimeline(request(base), cutoff, "OK" to "CLAUDE · OK", "STALE" to "CLAUDE · STALE")
                store(mock.copyWith(generatedAt = generated))
                assertTimeline(request(base), cutoff, "tst ok" to "MOCK · OK", "tst old" to "MOCK · STALE")

                // Request time decides freshness exactly; only playback rounds up to the second.
                val deadline = generated.plus(2, ChronoUnit.HOURS)
                store(live.copyWith(generatedAt = generated))
                assertTimeline(
                    request(deadline.minusNanos(1)), cutoff,
                    "OK" to "CLAUDE · OK", "STALE" to "CLAUDE · STALE",
                )
                assertStatic(request(deadline), "STALE", "CLAUDE · STALE")
            }

            // Other fresh statuses keep their full reading until the cutoff.
            store(live.copyWith(generatedAt = base.minusSeconds(3600), providerStatus = "warning"))
            assertTimeline(
                request(base), base.plusSeconds(3600),
                "CLAUDE · WARN" to "CLAUDE · WARN", "STALE" to "CLAUDE · STALE",
            )

            store(live.copyWith(generatedAt = base, isStale = true))
            assertStatic(request(base), "STALE", "CLAUDE · STALE")
            store(mock.copyWith(generatedAt = base, isStale = true))
            assertStatic(request(base), "tst old", "MOCK · STALE")

            // A recent summary whose reported status is already stale stays static.
            store(live.copyWith(generatedAt = base, providerStatus = "stale"))
            assertStatic(request(base), "STALE", "CLAUDE · STALE")
            store(mock.copyWith(generatedAt = base, overallStatus = "stale"))
            assertStatic(request(base), "tst old", "MOCK · STALE")

            // A cutoff no wire endpoint can carry keeps the exact request-time reading.
            val lastWireSecond = Instant.ofEpochSecond(Long.MAX_VALUE / 1000)
            store(live.copyWith(generatedAt = lastWireSecond.minusMillis(500).minus(2, ChronoUnit.HOURS)))
            assertStatic(request(base), "OK", "CLAUDE · OK")

            assertTrue(isolation.scope.summaryPreferences.edit().remove("latest").commit())
            assertStatic(request(base), "—", "—")
            assertTrue(isolation.scope.summaryPreferences.edit().putString("latest", "{").commit())
            assertStatic(request(base), "—", "—")
        }
    }

    @Test
    fun previewAndTapActionAreUnchanged() {
        withService { service, _ ->
            assertText(checkNotNull(service.getPreviewData(ComplicationType.SHORT_TEXT)), "SYNC", "SYNC")
            assertNull(service.getPreviewData(ComplicationType.RANGED_VALUE))
        }
    }

    /** One bound service; each request fixes only its clock, where the service has the seam. */
    private fun withService(
        block: (service: StatusComplicationDataSourceService, request: (Instant) -> WireComplicationData) -> Unit,
    ) {
        val storage = isolation.scope.summaryPreferences
        val attached = object : ContextWrapper(context) {
            override fun getApplicationContext(): Context = this
            override fun getSharedPreferences(name: String, mode: Int): SharedPreferences =
                if (name == "watch_summary") storage else error("Unexpected preference name")
        }
        val service = StatusComplicationDataSourceService()
        lateinit var provider: IComplicationProvider
        instrumentation.runOnMainSync {
            ContextWrapper::class.java.getDeclaredMethod("attachBaseContext", Context::class.java)
                .apply { isAccessible = true }
                .invoke(service, attached)
            service.onCreate()
            provider = IComplicationProvider.Stub.asInterface(
                service.onBind(Intent(ComplicationDataSourceService.ACTION_COMPLICATION_UPDATE_REQUEST)),
            )
        }
        try {
            var id = 0
            block(service) { now ->
                clockSeam?.let { seam ->
                    instrumentation.runOnMainSync { seam.set(service, Clock.fixed(now, ZoneOffset.UTC)) }
                }
                provider.onUpdate(++id, WireComplicationData.TYPE_SHORT_TEXT, manager.asBinder())
                val reply = checkNotNull(replies.poll(5, TimeUnit.SECONDS)) { "No Status reply" }
                assertEquals(id, reply.id)
                checkNotNull(reply.data).also { data ->
                    check(clockSeam != null || data.timelineEntries.isNullOrEmpty()) {
                        "A timeline Status service has no Clock seam"
                    }
                }
            }
        } finally {
            instrumentation.runOnMainSync { service.onDestroy() }
        }
    }

    private fun assertTimeline(
        wire: WireComplicationData,
        cutoff: Instant,
        fresh: Pair<String, String>,
        stale: Pair<String, String>,
    ) {
        // Schedule before text: a static baseline reply fails here first.
        val entries = wire.timelineEntries.orEmpty()
        assertEquals("Scheduled stale entries", 1, entries.size)
        val entry = entries.single()
        assertEquals(cutoff.epochSecond, entry.timelineStartEpochSecond)
        assertEquals(Long.MAX_VALUE / 1000, entry.timelineEndEpochSecond)
        assertTrue(entry.isActiveAt(cutoff.toEpochMilli()))
        assertTrue(entry.isActiveAt(Long.MAX_VALUE))
        assertEquals(cutoff.toEpochMilli() - 1, wire.endDateTimeMillis)
        assertTrue(wire.isActiveAt(cutoff.toEpochMilli() - 1))
        assertFalse(wire.isActiveAt(cutoff.toEpochMilli()))
        assertText(wire.toApiComplicationData(), fresh.first, fresh.second)
        assertText(entry.toApiComplicationData(), stale.first, stale.second)
    }

    private fun assertStatic(wire: WireComplicationData, text: String, description: String) {
        assertText(wire.toApiComplicationData(), text, description)
        assertTrue(wire.isActiveAt(Long.MAX_VALUE))
        assertTrue(wire.timelineEntries.isNullOrEmpty())
    }

    private fun assertText(data: ComplicationData, text: String, description: String) {
        data.validate()
        val shortText = data as ShortTextComplicationData
        assertEquals(text, shortText.text.getTextAt(context.resources, Instant.EPOCH).toString())
        assertEquals(description, shortText.contentDescription!!.getTextAt(context.resources, Instant.EPOCH).toString())
        assertTapOpensMainActivity(shortText)
    }

    private fun assertTapOpensMainActivity(data: ComplicationData) {
        val existing = PendingIntent.getActivity(
            context, 0, Intent(context, MainActivity::class.java),
            PendingIntent.FLAG_NO_CREATE or PendingIntent.FLAG_IMMUTABLE,
        )
        assertNotNull(existing)
        assertEquals(existing, data.tapAction)
    }

    private fun parcelled(wire: WireComplicationData): WireComplicationData {
        val parcel = Parcel.obtain()
        return try {
            wire.writeToParcel(parcel, 0)
            parcel.setDataPosition(0)
            WireComplicationData.CREATOR.createFromParcel(parcel)
        } finally {
            parcel.recycle()
        }
    }

    private fun fixture(asset: String) = JSONObject(
        instrumentation.context.assets.open(asset).use { it.readBytes() }.toString(Charsets.UTF_8),
    )

    private fun JSONObject.copyWith(
        generatedAt: Instant,
        isStale: Boolean = false,
        providerStatus: String? = null,
        overallStatus: String? = null,
    ) = JSONObject(toString()).apply {
        put("generatedAt", generatedAt.toString())
        put("isStale", isStale)
        providerStatus?.let { getJSONArray("providers").getJSONObject(0).put("status", it) }
        overallStatus?.let { put("overallStatus", it) }
    }

    private fun store(summary: JSONObject) {
        assertTrue(isolation.scope.summaryPreferences.edit().putString("latest", summary.toString()).commit())
    }
}
