package app.wardpulse.wear.ui

import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.PlatformTextStyle
import androidx.compose.ui.text.TextMeasurer
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.font.createFontFamilyResolver
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import kotlin.math.ceil
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

/** Native font/layout regressions; device gestures and actual circular ink remain acceptance. */
@RunWith(AndroidJUnit4::class)
class GlanceLegendLayoutTest {
    private val context = InstrumentationRegistry.getInstrumentation().targetContext
    private val pair = GlanceLegendRowModel(
        title = "Cursor plan",
        subtitle = "100% · 100% left · 999.9T credits",
        remainingFraction = 1f,
        colorArgb = RingFamily.CURSOR_OWN,
        secondaryArc = GlanceLegendArcModel(1f, RingFamily.CURSOR),
    )
    private val ordinary = GlanceLegendRowModel(
        title = "Claude plan · Sonnet weekly",
        subtitle = "100% left · 999.9T credits",
        remainingFraction = 1f,
        colorArgb = RingFamily.CLAUDE,
    )

    @Test
    fun denseDefaultScenesKeepBothLinesAndClearEveryRefreshDetail() {
        listOf(360, 384, 466).forEach { pixels ->
            val density = Density(2f, fontScale = 1f)
            val measurer = measurer(density)
            val art = pixels / 450f
            // Measure the actual detail type rather than assume its glyph height is 16.
            listOf(null, "Mock data", "Stale", "Rate limited", "Auth required", "Warning", "Error", "Unknown")
                .forEach { detail ->
                    val detailHeight = detail?.let {
                        measurer.measure(
                            AnnotatedString(it),
                            TextStyle(
                                fontSize = (11f * art / density.density).sp,
                                fontWeight = FontWeight.Bold,
                                platformStyle = PlatformTextStyle(includeFontPadding = false),
                            ),
                        ).size.height + ceil(8f * art).toInt()
                    } ?: 0
                    val height = (230f * art).toInt() - detailHeight
                    val layout = layout(listOf(ordinary, pair, pair.copy(title = "Codex plan")), pixels, 1f, height)
                    assertFalse("$pixels / $detail unexpectedly scrolls", layout.scrolling)
                    assertTrue(layout.rows.sumOf { it.height } <= height)
                    layout.rows.forEach { row ->
                        assertEquals(1, row.title.layout.lineCount)
                        assertEquals(1, row.subtitle.layout.lineCount)
                        assertComplete(row)
                    }
                }
        }
    }

    @Test
    fun heightAloneActivatesScrollingForShortWidthFittingRows() {
        val short = ordinary.copy(title = "Claude plan · 5h", subtitle = "0% left")
        listOf(1.5f, 2f).forEach { scale ->
            val layout = layout(List(3) { short }, 384, scale)
            assertTrue("Short rows must scroll at $scale", layout.scrolling)
            assertEquals(3, layout.rows.size)
            assertEquals((230f * 384 / 450).toInt() - ceil(14f * 384 / 450).toInt(), layout.viewportHeight)
            layout.rows.forEach { row ->
                assertEquals(1, row.title.layout.lineCount)
                assertEquals(1, row.subtitle.layout.lineCount)
                assertTrue(row.height >= 62f * 384 / 450 * scale)
                assertComplete(row)
            }
        }
    }

    @Test
    fun scaledPairsAndLongTitlesWrapWithoutLosingTokensOrExhaustionSpans() {
        val zeroPair = pair.copy(
            subtitle = "0% · 0% left · 999.9T credits",
            exhaustedPercentRanges = listOf(0..1, 5..6),
        )
        listOf(360, 384, 466).forEach { pixels ->
            listOf(1.5f, 2f).forEach { scale ->
                val models = listOf(ordinary, pair, zeroPair)
                val layout = layout(models, pixels, scale)
                assertTrue(layout.scrolling)
                assertEquals(models, layout.rows.map { it.model })
                assertTrue(layout.rows[0].title.layout.lineCount > 1)
                assertTrue(layout.rows[1].subtitle.layout.lineCount > 1)
                layout.rows.forEach { row ->
                    assertComplete(row)
                    assertEquals(
                        row.model.subtitle.replace(" · ", " "),
                        row.subtitle.text.text.replace(" · ", " ").replace('\n', ' '),
                    )
                    val designScale = pixels / 450f / 2f
                    assertTrue(row.title.style.fontSize.value / designScale in 17.9999f..20.0001f)
                    assertTrue(row.subtitle.style.fontSize.value / designScale in 15.9999f..18.0001f)
                }
                val styled = layout.rows.last().subtitle.text
                assertEquals(listOf("0%", "0%"), styled.spanStyles.map {
                    assertEquals(Color(0xFFFFB4AB), it.item.color)
                    styled.text.substring(it.start, it.end)
                })
            }
        }
    }

    @Test
    fun smallFontScaleKeepsTheArcFloorAndUnusualTokensRemainComplete() {
        val small = layout(List(3) { ordinary }, 384, 0.5f)
        assertFalse(small.scrolling)
        small.rows.forEach { assertTrue(it.height >= 39f * 384 / 450) }

        val external = ordinary.copy(title = "External " + "W".repeat(80))
        val wrapped = layout(listOf(external, pair.copy(subtitle = "0% · 41% left")), 360, 2f)
        assertEquals(external.title, wrapped.rows.first().title.text.text)
        wrapped.rows.forEach(::assertComplete)
    }

    private fun measurer(density: Density) = TextMeasurer(
        defaultFontFamilyResolver = createFontFamilyResolver(context),
        defaultDensity = density,
        defaultLayoutDirection = LayoutDirection.Ltr,
    )

    private fun layout(
        rows: List<GlanceLegendRowModel>,
        pixels: Int,
        scale: Float,
        height: Int = (230f * pixels / 450).toInt(),
    ): GlanceLegendLayout {
        val density = Density(2f, fontScale = scale)
        return measureGlanceLegend(
            rows, (pixels / density.density).dp, (394f * pixels / 450).toInt(),
            height, density, measurer(density),
        )
    }

    private fun assertComplete(row: GlanceMeasuredRow) {
        listOf(row.title, row.subtitle).forEach { text ->
            assertFalse(text.text.text, text.layout.hasVisualOverflow)
            assertEquals(text.text.length, text.layout.getLineEnd(text.layout.lineCount - 1))
            assertTrue(text.height >= text.layout.size.height)
        }
    }
}
