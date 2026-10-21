package app.wardpulse.wear.ui

import android.graphics.Bitmap
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Canvas
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.drawscope.CanvasDrawScope
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.LayoutDirection
import androidx.test.ext.junit.runners.AndroidJUnit4
import kotlin.math.abs
import kotlin.math.atan2
import kotlin.math.cos
import kotlin.math.roundToInt
import kotlin.math.sin
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class MiniRemainingArcPaintTest {
    private val scales = listOf(384f / 450f, 360f / 450f)
    private val pairedColors = listOf(
        RingFamily.CODEX,
        RingFamily.CODEX_SPARK,
        RingFamily.CURSOR_OWN,
        RingFamily.CURSOR,
    )
    private val background = 0xFF0A0D0B.toInt()
    private val track = 0xFF2E3632.toInt()

    @Test
    fun lowPositiveSpansRemainVisibleAndProportionalAcrossTheCapTransition() {
        scales.forEach { scale ->
            val side = (39f * scale).roundToInt()
            val stroke = 5f * scale
            // One centreline pixel of angular uncertainty covers raster ties and AA.
            val tolerance = Math.toDegrees(1.0 / ((side - stroke) / 2.0))
            pairedColors.forEach { color ->
                val zero = paint(0f, color, side, stroke)
                assertTrackOnly(zero, side, scale, color, stroke)
                var previousExtent = 0.0
                listOf(0.02f, 0.04f, 0.046f, 0.048f, 0.06f, 0.08f, 0.1f).forEach { remaining ->
                    val pixels = paint(remaining, color, side, stroke)
                    val label = "scale=$scale color=$color remaining=$remaining"
                    val angles = coloredAngles(pixels, zero, color, side)
                    assertTrue("No visible family paint: $label", angles.isNotEmpty())
                    assertTrue("No solid family paint: $label", pixels.any { it == color })
                    val extent = angles.max()
                    assertTrue(
                        "Span is not proportional: $label extent=$extent",
                        abs(extent - remaining * 360f) <= tolerance,
                    )
                    assertTrue("Span moved away from 12: $label", abs(angles.min()) <= tolerance)
                    assertTrue("Span grew backwards: $label", extent + tolerance >= previousExtent)
                    previousExtent = extent
                }
            }
        }
    }

    @Test
    fun ordinarySpansKeepRoundEndsAndNearFullSpansKeepTheUsageGap() {
        scales.forEach { scale ->
            val side = (39f * scale).roundToInt()
            val stroke = 5f * scale
            val tolerance = Math.toDegrees(1.0 / ((side - stroke) / 2.0))
            pairedColors.forEach { color ->
                val zero = paint(0f, color, side, stroke)
                val quarter = paint(0.25f, color, side, stroke)
                assertEquals(color, quarter[pointAt(315.0, side, stroke)])
                val angles = coloredAngles(quarter, zero, color, side)
                assertTrue("Quarter span lost its start", abs(angles.max() - 90.0) <= tolerance)
                assertTrue("Quarter span lost its end at 12", abs(angles.min()) <= tolerance)
                // The outer shoulder at the nine-o'clock tip is track with a round
                // end; a flat-ended quarter arc paints half this pixel instead.
                val shoulder = (side / 2) * side
                assertNearTrack(quarter[shoulder], zero[shoulder], color)

                val nearFull = paint(0.96f, color, side, stroke)
                val gap = pointAt(7.2, side, stroke)
                assertNearTrack(nearFull[gap], zero[gap], color)
                listOf(90.0, 180.0, 270.0).forEach { angle ->
                    assertEquals(
                        "Missing near-full paint at $angle",
                        color,
                        nearFull[pointAt(angle, side, stroke)],
                    )
                }
            }
        }
    }

    private fun paint(remaining: Float, color: Int, side: Int, stroke: Float): IntArray {
        val bitmap = Bitmap.createBitmap(side, side, Bitmap.Config.ARGB_8888)
        try {
            CanvasDrawScope().draw(
                density = Density(1f),
                layoutDirection = LayoutDirection.Ltr,
                canvas = Canvas(bitmap.asImageBitmap()),
                size = Size(side.toFloat(), side.toFloat()),
            ) {
                drawRect(Color(background))
                drawMiniRemainingArc(remaining, Color(color), stroke)
            }
            return IntArray(side * side).also {
                bitmap.getPixels(it, 0, side, 0, 0, side, side)
            }
        } finally {
            bitmap.recycle()
        }
    }

    private fun assertTrackOnly(pixels: IntArray, side: Int, scale: Float, color: Int, stroke: Float) {
        val family = when (color) {
            RingFamily.CODEX -> "Codex main"
            RingFamily.CODEX_SPARK -> "Codex Spark"
            RingFamily.CURSOR_OWN -> "Cursor own models"
            RingFamily.CURSOR -> "Cursor other models"
            else -> "Unknown"
        }
        val context = "scale=$scale family=$family color=0x${"%08X".format(color)} side=$side stroke=$stroke"
        assertEquals(
            "Zero centre is not background: $context pixel=(${side / 2},${side / 2}) " +
                "argb=0x${"%08X".format(pixels[(side / 2) * side + side / 2])} " +
                "expectedArgb=0x${"%08X".format(background)}",
            background,
            pixels[(side / 2) * side + side / 2],
        )
        assertTrue(
            "Zero has no solid track: $context expectedArgb=0x${"%08X".format(track)}",
            pixels.any { it == track },
        )
        pixels.forEachIndexed { index, pixel ->
            val pixelContext = "$context pixel=(${index % side},${index / side}) argb=0x${"%08X".format(pixel)}"
            assertEquals(
                "Zero pixel is not opaque: $pixelContext channel=A value=${pixel ushr 24} " +
                    "allowed=255..255 deviation=${255 - (pixel ushr 24)}",
                255,
                pixel ushr 24,
            )
            // Allow one lower quantization unit for retained native pixel 0xFF090D0A.
            listOf(0, 8, 16).forEach { shift ->
                val channel = (pixel ushr shift) and 255
                val lower = ((background ushr shift) and 255) - 1
                val upper = (track ushr shift) and 255
                val channelName = when (shift) {
                    0 -> "B"
                    8 -> "G"
                    else -> "R"
                }
                assertTrue(
                    "Zero contains paint outside the track palette: $pixelContext " +
                        "channel=$channelName value=$channel allowed=$lower..$upper " +
                        "deviation=${maxOf(lower - channel, channel - upper, 0)}",
                    channel in lower..upper,
                )
            }
        }
    }

    private fun coloredAngles(pixels: IntArray, zero: IntArray, color: Int, side: Int): List<Double> =
        pixels.indices.filter { index ->
            // Count pixels closer to the actual family colour than to the zero
            // image. This works for dark Spark as well as the brighter pools.
            colorDistance(pixels[index], color) < colorDistance(pixels[index], zero[index])
        }.map { index ->
            val dx = index % side + 0.5 - side / 2.0
            val dy = index / side + 0.5 - side / 2.0
            // Short remaining spans end at 12 and grow back towards nine o'clock.
            Math.toDegrees(atan2(-dx, -dy))
        }

    private fun pointAt(clockwiseDegrees: Double, side: Int, stroke: Float): Int {
        val angle = Math.toRadians(clockwiseDegrees)
        val radius = (side - stroke) / 2.0
        val x = (side / 2.0 + radius * sin(angle)).toInt()
        val y = (side / 2.0 - radius * cos(angle)).toInt()
        return y * side + x
    }

    private fun assertNearTrack(pixel: Int, zero: Int, color: Int) {
        // At most one quarter of the family/track contrast from edge AA. A flat
        // shoulder or a cap that closes the usage gap exceeds this allowance.
        assertTrue("Expected exposed track", colorDistance(pixel, zero) < colorDistance(color, zero) / 16.0)
    }

    private fun colorDistance(first: Int, second: Int): Int =
        listOf(0, 8, 16).sumOf { shift ->
            val difference = ((first ushr shift) and 255) - ((second ushr shift) and 255)
            difference * difference
        }
}
