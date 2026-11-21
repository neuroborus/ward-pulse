package app.wardpulse.wear.complication

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.drawable.Icon
import android.os.Parcel
import android.support.wearable.complications.ComplicationData as WireComplicationData
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.wear.watchface.complications.data.ComplicationType
import androidx.wear.watchface.complications.data.MonochromaticImageComplicationData
import androidx.wear.watchface.complications.data.NoDataComplicationData
import androidx.wear.watchface.complications.data.RangedValueComplicationData
import androidx.wear.watchface.complications.data.toApiComplicationData
import app.wardpulse.wear.R
import app.wardpulse.wear.model.AllowanceSummary
import app.wardpulse.wear.model.CreditsGlance
import app.wardpulse.wear.model.PreviewWatchDashboardSummary
import app.wardpulse.wear.model.PulseStatus
import app.wardpulse.wear.model.Quantity
import app.wardpulse.wear.model.RingHalf
import app.wardpulse.wear.model.RingSummary
import app.wardpulse.wear.ui.RingFamily
import java.time.Instant
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

/** Real Android API validation and wire Bundle/Parcel transport, not a mocked serializer. */
@SuppressLint("RestrictedApi")
@RunWith(AndroidJUnit4::class)
class AdaptiveRangedComplicationTest {
    @Test
    fun debugRangedWithoutTextSurvivesWireParcel() {
        val resources = ApplicationProvider.getApplicationContext<Context>().resources
        val original = debugRangedComplicationData()
        original.validate()
        val wire = original.asWireComplicationData()
        val parcel = Parcel.obtain()
        val restoredWire = try {
            wire.writeToParcel(parcel, 0)
            parcel.setDataPosition(0)
            WireComplicationData.CREATOR.createFromParcel(parcel)
        } finally {
            parcel.recycle()
        }
        val restored = restoredWire.toApiComplicationData() as RangedValueComplicationData
        restored.validate()
        for (data in listOf(original, restored)) {
            assertEquals(ComplicationType.RANGED_VALUE, data.type)
            assertTrue(data.value.isFinite() && data.min.isFinite() && data.max.isFinite())
            assertEquals(4f, data.value, 0f)
            assertEquals(0f, data.min, 0f)
            assertEquals(10f, data.max, 0f)
            assertTrue(data.value > data.min && data.value < data.max)
            assertEquals(RangedValueComplicationData.TYPE_UNDEFINED, data.valueType)
            assertEquals("Probe", data.title!!.getTextAt(resources, Instant.EPOCH).toString())
            assertEquals("QA ranged fixture", data.contentDescription!!.getTextAt(resources, Instant.EPOCH).toString())
            assertNull(data.text)
        }
        for (data in listOf(wire, restoredWire)) {
            assertEquals(WireComplicationData.TYPE_RANGED_VALUE, data.type)
            assertFalse(data.hasShortText())
            assertNull(data.shortText)
        }
    }

    /** Constructed image transport only; installed dispatch and WFF paint need separate evidence. */
    @Test
    fun debugMonoImageAndTintSurviveWireParcel() {
        val context = ApplicationProvider.getApplicationContext<Context>()
        val original = debugMonoComplicationData(context)
        original.validate()
        val wire = original.asWireComplicationData()
        val parcel = Parcel.obtain()
        val restoredWire = try {
            wire.writeToParcel(parcel, 0)
            parcel.setDataPosition(0)
            WireComplicationData.CREATOR.createFromParcel(parcel)
        } finally {
            parcel.recycle()
        }
        val restored = restoredWire.toApiComplicationData() as MonochromaticImageComplicationData
        restored.validate()
        for (data in listOf(wire, restoredWire)) {
            assertEquals(WireComplicationData.TYPE_ICON, data.type)
            assertNotNull(data.icon)
            assertFalse(data.hasShortText())
            assertFalse(data.hasShortTitle())
            assertFalse(data.hasLongText())
            assertFalse(data.hasLongTitle())
            assertFalse(data.hasRangedValue())
        }
        fun pixels(icon: Icon): IntArray {
            val bitmap = Bitmap.createBitmap(24, 24, Bitmap.Config.ARGB_8888)
            return try {
                val drawable = checkNotNull(icon.loadDrawable(context))
                drawable.setBounds(0, 0, 24, 24)
                drawable.draw(Canvas(bitmap))
                IntArray(24 * 24).also { bitmap.getPixels(it, 0, 24, 0, 0, 24, 24) }
            } finally {
                bitmap.recycle()
            }
        }
        val silhouette = pixels(Icon.createWithResource(context, R.drawable.ic_complication))
            .map { Color.alpha(it) }.toIntArray()
        assertTrue(silhouette.any { it == 0 })
        assertTrue(silhouette.any { it == 255 })
        val rendered = listOf(original, restored).map { data ->
            assertEquals(ComplicationType.MONOCHROMATIC_IMAGE, data.type)
            assertEquals("QA monochromatic fixture", data.contentDescription!!.getTextAt(context.resources, Instant.EPOCH).toString())
            val icon = data.monochromaticImage.image
            assertEquals(Icon.TYPE_RESOURCE, icon.type)
            assertEquals("app.wardpulse", icon.resPackage)
            assertEquals(R.drawable.ic_complication, icon.resId)
            pixels(icon).also { image ->
                assertArrayEquals(silhouette, image.map { Color.alpha(it) }.toIntArray())
                assertTrue(image.any { it == 0xFFFF00FF.toInt() })
                for (pixel in image.filter { Color.alpha(it) > 0 }) {
                    assertEquals(0x00FF00FF, pixel and 0x00FFFFFF)
                }
            }
        }
        assertArrayEquals(rendered[0], rendered[1])
    }

    @Test
    fun genericEnvelopesRoundTripWithUnscaledHumanSemantics() {
        val resources = ApplicationProvider.getApplicationContext<Context>().resources
        val now = Instant.EPOCH
        // Both endpoints of each new envelope, fractional ratios, rounded zero,
        // near-full and the smallest Float protect distinct encoding boundaries.
        val samples = listOf(
            null to 0f, null to 100f, null to 37.125f,
            1 to 0f, 1 to 100f,
            2 to 0f, 2 to 100f,
            3 to 0f, 3 to 100f,
            2 to 37.125f, 3 to 0.04f, 1 to 99.96f, 3 to Float.MIN_VALUE,
        )
        for ((count, percent) in samples) {
            val title = when {
                count == 3 && percent == 0f -> "split:spark:zero-both"
                percent == 0f -> "zero"
                else -> ""
            }
            val amount = WatchComplicationText.percentAmount(percent)
            val label = if (title == "split:spark:zero-both") "0% · 0%" else "$amount% · 500"
            val color = if (title == "split:spark:zero-both") RingFamily.CODEX else RingFamily.CLAUDE
            val original = rangedComplicationBuilder(
                percent, title, color, contentDescription = "Plan",
                text = label, ringCount = count,
            ).build()
            original.validate()
            val wire = original.asWireComplicationData()
            val parcel = Parcel.obtain()
            val restored = try {
                wire.writeToParcel(parcel, 0)
                parcel.setDataPosition(0)
                WireComplicationData.CREATOR.createFromParcel(parcel)
                    .toApiComplicationData() as RangedValueComplicationData
            } finally {
                parcel.recycle()
            }
            restored.validate()
            val factor = count?.let { (1 shl it).toFloat() } ?: 1f
            assertEquals(percent * factor, restored.value)
            assertEquals(0f, restored.min)
            assertEquals(100f * factor, restored.max)
            assertEquals(percent / 100f, restored.value / restored.max)
            assertEquals(RangedValueComplicationData.TYPE_UNDEFINED, restored.valueType)
            assertEquals(title, restored.title!!.getTextAt(resources, now).toString())
            assertEquals(label, restored.text!!.getTextAt(resources, now).toString())
            assertEquals("Plan $amount%", restored.contentDescription!!.getTextAt(resources, now).toString())
            assertEquals(color, restored.colorRamp!!.colors.single())
        }

        // Constructed/serialized N1 selection evidence only: no service-return or delivery claim.
        val rings = listOf(RingSummary(
            "allowance.codex.plan", "Codex plan", 63.0, PulseStatus.OK,
            split = RingHalf("allowance.codex.spark", "Spark Weekly", 63.0, PulseStatus.OK),
        ))
        val selected = outerHalfComplicationData(rings, 0) { half, outside, count ->
            assertEquals(rings.single().split, half)
            assertEquals(0, outside)
            assertEquals(1, count)
            rangedComplicationBuilder(
                WatchComplicationText.remainingPercent(half.usedPercent), outside.toString(),
                RingFamily.colorArgb(half.id), ringCount = count,
            ).build()
        } as RangedValueComplicationData
        assertTrue(outerHalfComplicationData(rings, 1) { _, _, _ ->
            error("Singleton pair has no second extra")
        } is NoDataComplicationData)
        selected.validate()
        val parcel = Parcel.obtain()
        val serialized = try {
            selected.asWireComplicationData().writeToParcel(parcel, 0)
            parcel.setDataPosition(0)
            WireComplicationData.CREATOR.createFromParcel(parcel)
                .toApiComplicationData() as RangedValueComplicationData
        } finally {
            parcel.recycle()
        }
        serialized.validate()
        for (data in listOf(selected, serialized)) {
            assertEquals(74f, data.value)
            assertEquals(0f, data.min)
            assertEquals(200f, data.max)
            assertEquals(RangedValueComplicationData.TYPE_UNDEFINED, data.valueType)
            assertEquals("0", data.title!!.getTextAt(resources, now).toString())
            assertEquals(RingFamily.CODEX_SPARK, data.colorRamp!!.colors.single())
        }
    }

    /** Distinct constructed wire contracts only; no service delivery or WFF paint evidence. */
    @Test
    fun creditsAndReorderedExtrasRoundTripWithExactWireContracts() {
        val resources = ApplicationProvider.getApplicationContext<Context>().resources
        val now = Instant.EPOCH
        val creditsSummary = PreviewWatchDashboardSummary.value.copy(
            rings = emptyList(),
            creditsGlance = CreditsGlance("500", "Credits left", "codex"),
            allowances = listOf(
                AllowanceSummary(
                    "purchased", "Codex · Credits", null, Quantity("500", "credits"),
                    unlimited = false, resetsAt = null, status = PulseStatus.OK,
                ),
            ),
        )
        val credits = creditsOnlyComplicationData(creditsSummary) { label, color ->
            assertEquals("500", label)
            assertEquals(RingFamily.CODEX, color)
            rangedComplicationBuilder(
                100f, WatchComplicationText.CREDITS_TOKEN, color, contentDescription = label, text = label,
            ).build()
        } as RangedValueComplicationData
        val before = listOf(
            RingSummary(
                "allowance.codex.plan", "Codex plan", 90.0, PulseStatus.OK,
                split = RingHalf("allowance.codex.spark", "Spark", 30.0, PulseStatus.OK),
            ),
            RingSummary(
                "allowance.cursor.cursor-plan-models", "Cursor Models", 70.0, PulseStatus.OK,
                split = RingHalf("allowance.cursor.cursor-plan-other", "Other Models", 20.0, PulseStatus.OK),
            ),
            RingSummary("allowance.claude.plan", "Claude plan", 10.0, PulseStatus.OK),
        )
        val after = listOf(
            RingSummary("allowance.claude.plan", "Claude plan", 95.0, PulseStatus.OK),
            RingSummary("allowance.codex.plan", "Codex plan", 55.0, PulseStatus.OK),
            RingSummary(
                "allowance.cursor.cursor-plan-models", "Cursor Models", 25.0, PulseStatus.OK,
                split = RingHalf("allowance.cursor.cursor-plan-other", "Other Models", 5.0, PulseStatus.OK),
            ),
        )
        // Literal payload/outside positions for the Spark, Other, then replacement Other extras.
        val envelopes = mutableListOf(credits)
        for ((rings, positions) in listOf(
            before to listOf(0 to 2, 1 to 1),
            after to listOf(2 to 0),
        )) {
            for ((ordinal, position) in positions.withIndex()) {
                val selected = outerHalfComplicationData(rings, ordinal) { half, outside, count ->
                    assertEquals(rings[position.first].split, half)
                    assertEquals(position.second, outside)
                    assertEquals(3, count)
                    rangedComplicationBuilder(
                        WatchComplicationText.remainingPercent(half.usedPercent), outside.toString(),
                        RingFamily.colorArgb(half.id), contentDescription = half.label, ringCount = count,
                    ).build()
                } as RangedValueComplicationData
                envelopes += selected
            }
            assertTrue(outerHalfComplicationData(rings, positions.size) { _, _, _ ->
                error("Obsolete extra must clear")
            } is NoDataComplicationData)
        }
        val expectedRows = listOf(
            Triple(100f, "credits", "500"),
            Triple(560f, "2", "70"),
            Triple(640f, "1", "80"),
            Triple(760f, "0", "95"),
        )
        val expectedMaxima = listOf(100f, 800f, 800f, 800f)
        val expectedColors = listOf(RingFamily.CODEX, RingFamily.CODEX_SPARK, RingFamily.CURSOR, RingFamily.CURSOR)
        val expectedDescriptions = listOf("500 100%", "Spark 70%", "Other Models 80%", "Other Models 95%")
        for ((index, original) in envelopes.withIndex()) {
            original.validate()
            val parcel = Parcel.obtain()
            val restored = try {
                original.asWireComplicationData().writeToParcel(parcel, 0)
                parcel.setDataPosition(0)
                WireComplicationData.CREATOR.createFromParcel(parcel)
                    .toApiComplicationData() as RangedValueComplicationData
            } finally {
                parcel.recycle()
            }
            restored.validate()
            for (data in listOf(original, restored)) {
                val expected = expectedRows[index]
                assertEquals(RangedValueComplicationData.TYPE_UNDEFINED, data.valueType)
                assertEquals(0f, data.min)
                assertEquals(expectedMaxima[index], data.max)
                assertEquals(expected.first, data.value)
                assertEquals(expected.second, data.title!!.getTextAt(resources, now).toString())
                assertEquals(expected.third, data.text!!.getTextAt(resources, now).toString())
                assertEquals(expectedDescriptions[index], data.contentDescription!!.getTextAt(resources, now).toString())
                assertEquals(expectedColors[index], data.colorRamp!!.colors.single())
            }
        }
    }
}
