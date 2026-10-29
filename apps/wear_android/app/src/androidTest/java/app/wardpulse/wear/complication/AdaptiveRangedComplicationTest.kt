package app.wardpulse.wear.complication

import android.annotation.SuppressLint
import android.content.Context
import android.os.Parcel
import android.support.wearable.complications.ComplicationData as WireComplicationData
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.wear.watchface.complications.data.NoDataComplicationData
import androidx.wear.watchface.complications.data.RangedValueComplicationData
import androidx.wear.watchface.complications.data.toApiComplicationData
import app.wardpulse.wear.model.PulseStatus
import app.wardpulse.wear.model.RingHalf
import app.wardpulse.wear.model.RingSummary
import app.wardpulse.wear.ui.RingFamily
import java.time.Instant
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

/** Real Android API validation and wire Bundle/Parcel transport, not a mocked serializer. */
@SuppressLint("RestrictedApi")
@RunWith(AndroidJUnit4::class)
class AdaptiveRangedComplicationTest {
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
}
