package app.wardpulse

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Rect
import android.graphics.Typeface
import java.util.EnumMap
import kotlin.math.ceil

/** One bounded set of masks: native resource tints retain the host's day/night palette. */
internal class PhoneWidgetRenderer(context: Context, private val density: Float) :
    PhoneWidgetLayout.Measurer {
    private val paints = EnumMap<PhoneWidgetLayout.Style, Paint>(PhoneWidgetLayout.Style::class.java)

    init {
        for (style in PhoneWidgetLayout.Style.values()) {
            paints[style] = Paint(Paint.ANTI_ALIAS_FLAG or Paint.SUBPIXEL_TEXT_FLAG).apply {
                typeface = if (style.bold) fonts(context).bold else fonts(context).regular
                textSize = style.sizeDp * density
                color = Color.WHITE
                isFakeBoldText = false
            }
        }
    }

    override fun measure(text: String, style: PhoneWidgetLayout.Style): PhoneWidgetLayout.Glyphs {
        val paint = paints.getValue(style)
        val line = paint.fontMetricsInt
        val supported = PhoneWidgetLayout.supportedText(text)
        if (text.isEmpty() || !supported) {
            return PhoneWidgetLayout.Glyphs(0, 0, 0, 0, line.top, line.bottom, supported)
        }
        val ink = Rect()
        paint.getTextBounds(text, 0, text.length, ink)
        return PhoneWidgetLayout.Glyphs(
            minOf(0, ink.left) - 1, ink.top - 1,
            maxOf(ink.right, ceil(paint.measureText(text)).toInt()) + 1, ink.bottom + 1,
            line.top, line.bottom, true,
        )
    }

    data class Image(val bitmap: Bitmap, val bounds: PhoneWidgetLayout.Bounds)

    /** Plans bind every glyph and layer extent before creating any content bitmap. */
    fun render(plan: PhoneWidgetLayout.Plan): Map<PhoneWidgetLayout.Layer, Image>? {
        val images = EnumMap<PhoneWidgetLayout.Layer, Image>(PhoneWidgetLayout.Layer::class.java)
        try {
            for (layer in PhoneWidgetLayout.Layer.values()) {
                val bounds = plan.bounds(layer) ?: continue
                val alpha = layer != PhoneWidgetLayout.Layer.ACCENT
                val expected = PhoneWidgetLayout.bitmapBytes(bounds.width(), bounds.height(), alpha)
                if (expected == Long.MAX_VALUE) return discard(images)
                val bitmap = Bitmap.createBitmap(
                    bounds.width(), bounds.height(),
                    if (alpha) Bitmap.Config.ALPHA_8 else Bitmap.Config.ARGB_8888,
                )
                // RemoteViews must display these already-measured pixels without density scaling.
                bitmap.density = Bitmap.DENSITY_NONE
                if (bitmap.allocationByteCount.toLong() > expected) {
                    bitmap.recycle()
                    return discard(images)
                }
                images[layer] = Image(bitmap, bounds)
                val canvas = Canvas(bitmap)
                for (run in plan.text) {
                    if (run.style.layer != layer) continue
                    canvas.drawText(
                        run.text,
                        (run.x - run.glyphs.left - bounds.left).toFloat(),
                        (run.y - run.glyphs.top - bounds.top).toFloat(),
                        paints.getValue(run.style),
                    )
                }
                if (layer == PhoneWidgetLayout.Layer.ACCENT) {
                    val paint = Paint(Paint.ANTI_ALIAS_FLAG)
                    for (bar in plan.bars) {
                        paint.color = bar.color
                        val left = (bar.x - bounds.left).toFloat()
                        val top = (bar.y - bounds.top).toFloat()
                        canvas.drawRoundRect(
                            left, top, left + bar.width, top + bar.height,
                            density * 1.5f, density * 1.5f, paint,
                        )
                    }
                }
            }
        } catch (_: OutOfMemoryError) {
            return discard(images)
        }
        return images
    }

    private fun discard(images: Map<PhoneWidgetLayout.Layer, Image>): Nothing? {
        for (image in images.values) image.bitmap.recycle()
        return null
    }

    private data class Fonts(val regular: Typeface, val bold: Typeface)

    companion object {
        @Volatile private var loadedFonts: Fonts? = null
        @Volatile private var loadedMark: Bitmap? = null

        private fun fonts(context: Context): Fonts = loadedFonts ?: synchronized(this) {
            loadedFonts ?: Fonts(
                Typeface.createFromAsset(context.assets, "fonts/NotoSans-Regular.ttf"),
                Typeface.createFromAsset(context.assets, "fonts/NotoSans-Bold.ttf"),
            ).also { loadedFonts = it }
        }

        /** Crop only transparent logo margins; the owned brand export itself stays unchanged. */
        fun mark(context: Context): Bitmap = loadedMark ?: synchronized(this) {
            loadedMark ?: run {
                val options = BitmapFactory.Options().apply {
                    inScaled = false
                    inJustDecodeBounds = true
                }
                BitmapFactory.decodeResource(context.resources, R.drawable.wardpulse_mono, options)
                require(options.outWidth in 1..512 && options.outHeight in 1..512)
                options.inJustDecodeBounds = false
                val source = requireNotNull(BitmapFactory.decodeResource(
                    context.resources, R.drawable.wardpulse_mono, options,
                ))
                val pixels = IntArray(source.width * source.height)
                source.getPixels(pixels, 0, source.width, 0, 0, source.width, source.height)
                var left = source.width
                var top = source.height
                var right = 0
                var bottom = 0
                for (y in 0 until source.height) for (x in 0 until source.width) {
                    if (pixels[y * source.width + x] ushr 24 == 0) continue
                    left = minOf(left, x)
                    top = minOf(top, y)
                    right = maxOf(right, x + 1)
                    bottom = maxOf(bottom, y + 1)
                }
                require(right > left && bottom > top)
                Bitmap.createBitmap(source, left, top, right - left, bottom - top).also {
                    it.density = Bitmap.DENSITY_NONE
                    if (it !== source) source.recycle()
                    loadedMark = it
                }
            }
        }
    }
}
