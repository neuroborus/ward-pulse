package app.wardpulse

import android.appwidget.AppWidgetHostView
import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.ContextWrapper
import android.content.res.Configuration
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.drawable.BitmapDrawable
import android.os.Build
import android.os.Bundle
import android.test.InstrumentationTestCase
import android.util.SizeF
import android.view.View
import android.widget.ImageView
import kotlin.math.abs
import kotlin.math.ceil
import kotlin.math.max

/** Real RemoteViews/XML application without registering a widget or writing user preferences. */
@Suppress("DEPRECATION")
class PhoneWidgetGeometryTest : InstrumentationTestCase() {
    private class OrientationContext(base: Context) : ContextWrapper(base) {
        var current = base
        override fun getResources() = current.resources
        override fun getAssets() = current.assets
        override fun getTheme() = current.theme
    }

    private val provider = WardPulseAppWidget()
    private val wide = SizeF(640f, 600f)
    private val narrow = SizeF(155f, 600f)
    private val foldSizes = listOf(wide, narrow, SizeF(300f, 280f), SizeF(640f, 110f))
    private val layers = mapOf(
        PhoneWidgetLayout.Layer.PRIMARY to R.id.widget_primary,
        PhoneWidgetLayout.Layer.MUTED to R.id.widget_muted,
        PhoneWidgetLayout.Layer.STALE to R.id.widget_stale,
        PhoneWidgetLayout.Layer.ACCENT to R.id.widget_accents,
    )

    fun testRemoteViewsGeometry() {
        runTestOnUiThread {
            for (night in listOf(Configuration.UI_MODE_NIGHT_NO, Configuration.UI_MODE_NIGHT_YES)) {
                val context = configured(night, Configuration.ORIENTATION_PORTRAIT)
                for (size in listOf(wide, narrow)) unchangedPlan(context, size)
                states(context)
                if (Build.VERSION.SDK_INT >= 31) {
                    responsive(context)
                }
                aggregateBudget(context)
                fallbacks(night)
            }
        }
    }

    private fun configured(night: Int, orientation: Int): Context {
        val target = instrumentation.targetContext
        val configuration = Configuration(target.resources.configuration).apply {
            uiMode = (uiMode and Configuration.UI_MODE_NIGHT_MASK.inv()) or night
            this.orientation = orientation
        }
        return target.createConfigurationContext(configuration)
    }

    private fun cache(stale: Boolean = false): Map<String, Any> = buildMap {
        put("row_count", 6)
        put("stale", if (stale) "1" else "0")
        for (index in 0..5) {
            put("row_${index}_label", "Codex · Window ${index + 1}")
            put("row_${index}_family", "Codex")
            put("row_${index}_pool", "Window ${index + 1}")
            put("row_${index}_percent", "50%")
            put("row_${index}_credits", "42K credits")
            put("row_${index}_resets_at", "2026-02-10T09:15:00Z")
            put("row_${index}_color", "ff91c4b1")
        }
        put("row_4_label", "Claude · Extra Credits")
        put("row_4_family", "Claude")
        put("row_4_pool", "Extra Credits")
        put("row_4_kind", "allowance")
        put("row_4_extra_used_value", "2.5")
        put("row_4_extra_used_unit", "USD")
        put("row_4_extra_cap_value", "10")
        put("row_4_extra_cap_unit", "USD")
        put("row_5_label", "OpenAI · Today")
        put("row_5_family", "OpenAI")
        put("row_5_pool", "Today")
        put("row_5_kind", "budget")
        put("row_5_spent_minor", "1234")
        put("row_5_spent_currency", "USD")
        put("row_5_percent", "")
        put("row_5_credits", "")
        put("row_5_resets_at", "")
    }

    private fun options(sizes: List<SizeF>): Bundle = Bundle().apply {
        putInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH, sizes.minOf { it.width }.toInt())
        putInt(AppWidgetManager.OPTION_APPWIDGET_MAX_WIDTH, sizes.maxOf { it.width }.toInt())
        putInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT, sizes.minOf { it.height }.toInt())
        putInt(AppWidgetManager.OPTION_APPWIDGET_MAX_HEIGHT, sizes.maxOf { it.height }.toInt())
        if (Build.VERSION.SDK_INT >= 31) {
            putParcelableArrayList(AppWidgetManager.OPTION_APPWIDGET_SIZES, ArrayList(sizes))
        }
    }

    private fun publish(
        context: Context, options: Bundle, data: Map<String, *> = cache(),
        budget: Long = PhoneWidgetLayout.MAX_BITMAP_BYTES,
    ) = provider.publication(context, 0, data, options, budget)

    private fun host(context: Context, publication: WardPulseAppWidget.Publication) =
        AppWidgetHostView(context).apply {
            // This unattached test host has no launcher-owned padding, id or service registration.
            setPadding(0, 0, 0, 0)
            updateAppWidget(publication.views)
        }

    private fun measure(host: AppWidgetHostView, width: Int, height: Int) {
        host.requestLayout()
        host.measure(View.MeasureSpec.makeMeasureSpec(width, View.MeasureSpec.EXACTLY),
            View.MeasureSpec.makeMeasureSpec(height, View.MeasureSpec.EXACTLY))
        host.layout(0, 0, width, height)
    }

    private fun measure(host: AppWidgetHostView, size: SizeF) {
        val density = host.resources.displayMetrics.density
        measure(host, ceil(size.width * density).toInt(), ceil(size.height * density).toInt())
    }

    private fun unchangedPlan(context: Context, size: SizeF) {
        val publication = publish(context, options(listOf(size)))
        val plan = publication.plans.single()
        assertEquals("Six complete rows fit the reference geometry", 6, plan.rows.size)
        assertTrue("Width alone releases whole columns", plan.rows.all {
            when {
                size != wide -> !it.labels && !it.credits && !it.lower
                it.row.budget -> it.labels && it.lower && !it.credits && !it.reset
                else -> it.labels && it.credits && it.reset
            }
        })
        val card = requireNotNull(plan.card)
        val host = host(context, publication)
        val density = context.resources.displayMetrics.density
        // The selected plan is unchanged; only the actual host allocation varies.
        val allocations = listOf(
            plan.width to plan.height,
            plan.width + ceil(80 * density).toInt() to plan.height + ceil(120 * density).toInt(),
            max(card.width() + 2, plan.width - ceil(20 * density).toInt()) to
                max(card.height() + 2, plan.height - ceil(20 * density).toInt()),
        )
        for ((width, height) in allocations) {
            measure(host, width, height)
            assertNative(host, plan)
        }
        val root = host.findViewById<View>(R.id.widget_root)
        assertTrue("Money keeps its exact accessible currency/amount",
            root.contentDescription.toString().contains("USD 12.34"))
        root.setPadding(9, 11, 13, 15)
        root.findViewById<View>(R.id.widget_card).setPadding(7, 7, 7, 7)
        for (id in layers.values + R.id.widget_watermark) {
            root.findViewById<ImageView>(id).apply {
                setImageBitmap(null)
                setPadding(5, 5, 5, 5)
                visibility = View.GONE
            }
        }
        host.updateAppWidget(publication.views)
        measure(host, plan.width, plan.height)
        assertSame("Update exercises retained application", root, host.findViewById(R.id.widget_root))
        assertNative(host, plan)
    }

    private fun states(context: Context) {
        val widgetOptions = options(listOf(wide))
        val initial = publish(context, widgetOptions)
        val host = host(context, initial)
        val cases = listOf(
            publish(context, widgetOptions, mapOf("row_count" to 0, "empty" to "1")),
            publish(context, options(listOf(SizeF(20f, 3f)))),
            publish(context, widgetOptions, cache(stale = true)),
            initial,
        )
        for (publication in cases) {
            host.updateAppWidget(publication.views)
            measure(host, wide)
            assertNative(host, publication.plans.single())
        }
        assertEquals("Stale header preserves six rows", 6, cases[2].plans.single().rows.size)
        assertEquals(PhoneWidgetLayout.EmptyState.NO_METRICS, cases[0].plans.single().state)
        assertNull("Tiny no-fit publishes no misleading card", cases[1].plans.single().card)
    }

    private fun responsive(context: Context) {
        for (count in listOf(3, 4)) {
            val publication = publish(context, options(foldSizes.take(count)))
            assertTrue(publication.sizes.responsive)
            assertEquals(count, publication.plans.size)
            val host = host(context, publication)
            for (index in (0 until count).toList() + (count - 1 downTo 0).toList()) {
                // AppWidgetHostView selects the responsive variant during native layout.
                measure(host, foldSizes[index])
                assertNative(host, publication.plans[index])
                host.updateAppWidget(publication.views)
                measure(host, foldSizes[index])
                assertNative(host, publication.plans[index])
            }
            assertEquals("Four-size hosts keep the wide plan", 6, publication.plans[0].rows.size)
        }
        val sanitized = options(listOf(wide, narrow)).apply {
            putParcelableArrayList(AppWidgetManager.OPTION_APPWIDGET_SIZES,
                arrayListOf(null, wide, wide, SizeF(0f, 100f), SizeF(-1f, 100f), narrow))
        }
        assertEquals(listOf(wide, narrow), provider.hostSizes(sanitized).values)
        val guarded = options((0..16).map { SizeF(200f + it, 600f) })
        assertEquals("Input/map limit stays sixteen", 16, provider.hostSizes(guarded).values.size)
    }

    private fun fallbacks(night: Int) {
        val missing = options(listOf(narrow, SizeF(640f, 280f))).apply {
            remove(AppWidgetManager.OPTION_APPWIDGET_SIZES)
        }
        val nullList = Bundle(missing).apply {
            putParcelableArrayList<SizeF>(AppWidgetManager.OPTION_APPWIDGET_SIZES, null)
        }
        val emptyList = Bundle(missing).apply {
            putParcelableArrayList<SizeF>(AppWidgetManager.OPTION_APPWIDGET_SIZES, arrayListOf())
        }
        for (orientation in listOf(Configuration.ORIENTATION_PORTRAIT,
            Configuration.ORIENTATION_LANDSCAPE)) {
            val context = configured(night, orientation)
            for (options in listOf(missing, nullList, emptyList, Bundle())) {
                val publication = publish(context, options)
                assertFalse(publication.sizes.responsive)
                val index = if (orientation == Configuration.ORIENTATION_LANDSCAPE
                    && publication.plans.size == 2) 1 else 0
                val host = host(context, publication)
                measure(host, publication.sizes.values[index])
                assertNative(host, publication.plans[index])
                host.updateAppWidget(publication.views)
                measure(host, host.width + 30, host.height + 30)
                assertNative(host, publication.plans[index])
            }
        }
        val context = configured(night, Configuration.ORIENTATION_PORTRAIT)
        val reversed = Bundle(missing).apply {
            putInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH, 640)
            putInt(AppWidgetManager.OPTION_APPWIDGET_MAX_WIDTH, 155)
        }
        assertEquals(provider.hostSizes(missing), provider.hostSizes(reversed))
        val invalid = Bundle().apply {
            putInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH, -1)
            putInt(AppWidgetManager.OPTION_APPWIDGET_MAX_HEIGHT, -1)
        }
        assertEquals(listOf(SizeF(180f, 110f)), provider.hostSizes(invalid).values)
        val defaultPublication = publish(context, invalid)
        val defaultHost = host(context, defaultPublication)
        measure(defaultHost, SizeF(180f, 110f))
        assertNative(defaultHost, defaultPublication.plans.single())
        val retainedContext = OrientationContext(configured(night, Configuration.ORIENTATION_PORTRAIT))
        val retained = publish(retainedContext, missing)
        val retainedHost = host(retainedContext, retained)
        measure(retainedHost, retained.sizes.values[0])
        val retainedRoot = retainedHost.findViewById<View>(R.id.widget_root)
        for (index in listOf(0, 1, 0)) {
            retainedContext.current = configured(night, if (index == 0)
                Configuration.ORIENTATION_PORTRAIT else Configuration.ORIENTATION_LANDSCAPE)
            retainedHost.updateAppWidget(retained.views)
            measure(retainedHost, retained.sizes.values[index])
            assertSame("Legacy orientation reuses the host/root", retainedRoot,
                retainedHost.findViewById(R.id.widget_root))
            assertNative(retainedHost, retained.plans[index])
        }
    }

    private fun aggregateBudget(context: Context) {
        val sizes = if (Build.VERSION.SDK_INT >= 31) {
            listOf(wide, SizeF(100f, 80f), SizeF(110f, 90f), SizeF(120f, 100f))
        } else {
            // Six portrait rows and one short landscape row have deliberately unequal costs.
            listOf(SizeF(320f, 600f), SizeF(640f, 80f))
        }
        val options = options(sizes)
        val complete = publish(context, options)
        assertEquals(6, complete.plans.first().rows.size)
        val fullCost = complete.plans.first().bitmapBytes() +
            PhoneWidgetRenderer.mark(context).allocationByteCount
        assertTrue("The full plan exceeds an equal share",
            fullCost > complete.bitmapBytes / complete.plans.size)
        val exact = publish(context, options, budget = complete.bitmapBytes)
        assertEquals("A fitting aggregate loses no content", complete.bitmapBytes, exact.bitmapBytes)
        assertEquals(6, exact.plans.first().rows.size)
        for (budget in listOf(complete.bitmapBytes, complete.bitmapBytes / 2, 0L)) {
            val publication = publish(context, options, budget = budget)
            assertTrue("All masks and marks fit the publication allowance", publication.bitmapBytes <= budget)
            val host = host(context, publication)
            measure(host, wide)
            assertNative(host, publication.plans.first())
            for (plan in publication.plans) for (layer in layers.keys) {
                val bounds = plan.bounds(layer) ?: continue
                assertTrue(bounds.width() <= PhoneWidgetLayout.MAX_BITMAP_SIDE
                    && bounds.height() <= PhoneWidgetLayout.MAX_BITMAP_SIDE)
            }
            if (budget == 0L) assertTrue(publication.plans.all { it.card == null && it.rows.isEmpty() })
        }
    }

    private fun assertNative(host: AppWidgetHostView, plan: PhoneWidgetLayout.Plan) {
        val configuration = host.resources.configuration
        val root = requireNotNull(host.findViewById<View>(R.id.widget_root)) {
            "Widget root absent: API=${Build.VERSION.SDK_INT} host=${host.width}x${host.height} " +
                "plan=${plan.width}x${plan.height} rows=${plan.rows.size}"
        }
        val card = root.findViewById<View>(R.id.widget_card)
        val diagnostic = "API=${Build.VERSION.SDK_INT} density=${host.resources.displayMetrics.density} " +
            "host=${host.width}x${host.height} root=${root.width}x${root.height} " +
            "fontScale=${configuration.fontScale} orientation=${configuration.orientation} " +
            "uiMode=${configuration.uiMode} plan=${plan.width}x${plan.height} rows=${plan.rows.size} " +
            "card=[${card.left},${card.top},${card.right},${card.bottom}]"
        assertEquals(diagnostic, host.width, root.width)
        assertEquals(diagnostic, host.height, root.height)
        assertEquals(diagnostic, 0, root.paddingLeft + root.paddingTop + root.paddingRight + root.paddingBottom)
        assertTrue("Full root keeps its tap listener: $diagnostic", root.hasOnClickListeners())
        val bounds = plan.card
        assertEquals(diagnostic, if (bounds == null) View.GONE else View.VISIBLE, card.visibility)
        if (bounds != null) {
            assertEquals(diagnostic, bounds.width(), card.width)
            assertEquals(diagnostic, bounds.height(), card.height)
            assertTrue(diagnostic, abs(card.left - (root.width - card.width) / 2) <= 1)
            assertTrue(diagnostic, abs(card.top - (root.height - card.height) / 2) <= 1)
            for (row in plan.rows) assertTrue(diagnostic,
                root.contentDescription.toString().contains(PhoneWidgetLayout.rowDescription(row)))
        }
        for ((layer, id) in layers) {
            val image = root.findViewById<ImageView>(id)
            val ink = plan.bounds(layer)
            assertEquals(diagnostic, if (ink == null) View.GONE else View.VISIBLE, image.visibility)
            if (ink == null) {
                assertNull(image.drawable)
                assertEquals(0, image.paddingLeft + image.paddingTop + image.paddingRight + image.paddingBottom)
            } else {
                val bitmap = (image.drawable as BitmapDrawable).bitmap
                assertEquals(diagnostic, Bitmap.DENSITY_NONE, bitmap.density)
                assertEquals(diagnostic, ink.width(), bitmap.width)
                assertEquals(diagnostic, ink.height(), bitmap.height)
                assertEquals(diagnostic, card.width, image.width)
                assertEquals(diagnostic, card.height, image.height)
                assertEquals(diagnostic, card.width, bitmap.width + image.paddingLeft + image.paddingRight)
                assertEquals(diagnostic, card.height, bitmap.height + image.paddingTop + image.paddingBottom)
                val plannedCard = requireNotNull(bounds)
                assertEquals(diagnostic, ink.left - plannedCard.left, image.paddingLeft)
                assertEquals(diagnostic, ink.top - plannedCard.top, image.paddingTop)
            }
        }
        val mark = root.findViewById<ImageView>(R.id.widget_watermark)
        assertEquals(diagnostic, if (plan.mark) View.VISIBLE else View.GONE, mark.visibility)
        assertEquals(diagnostic, 0, mark.paddingLeft + mark.paddingTop + mark.paddingRight + mark.paddingBottom)
        val frame = Bitmap.createBitmap(root.width, root.height, Bitmap.Config.ARGB_8888)
        try {
            root.draw(Canvas(frame))
            if (plan.rows.isNotEmpty()) {
                val bottomInset = ceil(8 * host.resources.displayMetrics.density).toInt()
                assertEquals("Actual theme surface: $diagnostic",
                    host.context.getColor(R.color.ward_pulse_widget_surface),
                    frame.getPixel(card.left + card.width / 2, card.bottom - bottomInset))
            }
            val pixels = IntArray(frame.width)
            var painted = false
            for (y in 0 until frame.height) {
                frame.getPixels(pixels, 0, frame.width, 0, y, frame.width, 1)
                for (x in pixels.indices) {
                    val inside = bounds != null && x >= card.left && x < card.right
                        && y >= card.top && y < card.bottom
                    if (!inside && Color.alpha(pixels[x]) != 0) {
                        fail("Exterior paint at $x,$y: $diagnostic")
                    }
                    painted = painted || Color.alpha(pixels[x]) != 0
                }
            }
            assertEquals("Actual card paint: $diagnostic", bounds != null, painted)
        } finally {
            frame.recycle()
        }
    }
}
