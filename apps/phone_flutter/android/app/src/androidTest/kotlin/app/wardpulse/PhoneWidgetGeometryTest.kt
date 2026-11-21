package app.wardpulse

import android.appwidget.AppWidgetHostView
import android.appwidget.AppWidgetManager
import android.content.ComponentName
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
            val component = ComponentName(context, WardPulseAppWidget::class.java)
            val info = requireNotNull(AppWidgetManager.getInstance(context).installedProviders
                .singleOrNull { it.provider == component }) {
                "Expected exactly one installed widget provider for $component"
            }
            setAppWidget(AppWidgetManager.INVALID_APPWIDGET_ID, info)
            // Initialization adds default padding; this unattached host uses the full allocation.
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
        for ((allocation, dimensions) in allocations.withIndex()) {
            val (width, height) = dimensions
            measure(host, width, height)
            assertNative(host, plan, "unchanged/$size/allocation=$allocation")
        }
        val root = host.findViewById<View>(R.id.widget_root)
        assertTrue("Money keeps its exact accessible currency/amount",
            root.contentDescription.toString().contains("USD 12.34"))
        root.setPadding(9, 11, 13, 15)
        root.findViewById<View>(R.id.widget_card).setPadding(7, 7, 7, 7)
        val expectedImages = layers.map { (layer, id) -> id to (plan.bounds(layer) != null) } +
            (R.id.widget_watermark to plan.mark)
        val oldBitmap = Bitmap.createBitmap(1, 1, Bitmap.Config.ARGB_8888).apply {
            this.density = Bitmap.DENSITY_NONE
            eraseColor(Color.MAGENTA)
        }
        try {
            for ((id, present) in expectedImages) {
                root.findViewById<ImageView>(id).apply {
                    // Exercise restoration of present images and clearing of absent images.
                    setImageBitmap(if (present) null else oldBitmap)
                    setPadding(5, 5, 5, 5)
                    visibility = if (present) View.GONE else View.VISIBLE
                }
            }
            val before = nativeDiagnostic(host, plan, "unchanged/$size/before-reapply")
            for ((id, present) in expectedImages) if (!present) {
                assertSame("Seeded content in view=$id: $before", oldBitmap,
                    (root.findViewById<ImageView>(id).drawable as? BitmapDrawable)?.bitmap)
            }
            host.updateAppWidget(publication.views)
            measure(host, plan.width, plan.height)
            val diagnostic = nativeDiagnostic(host, plan, "unchanged/$size/reapply")
            assertSame("Update exercises retained application: $diagnostic", root,
                host.findViewById<View>(R.id.widget_root))
            assertNative(host, plan, "unchanged/$size/reapply")
        } finally {
            oldBitmap.recycle()
        }
    }

    private fun states(context: Context) {
        val widgetOptions = options(listOf(wide))
        val initial = publish(context, widgetOptions)
        val host = host(context, initial)
        measure(host, wide)
        assertNative(host, initial.plans.single(), "states/initial")
        val retained = (listOf(R.id.widget_root, R.id.widget_card) +
            layers.values + R.id.widget_watermark).associateWith { host.findViewById<View>(it) }
        val cases = listOf(
            "empty" to publish(context, widgetOptions, mapOf("row_count" to 0, "empty" to "1")),
            "no-fit" to publish(context, options(listOf(SizeF(20f, 3f)))),
            "stale" to publish(context, widgetOptions, cache(stale = true)),
            "fresh" to initial,
        )
        for ((name, publication) in cases) {
            host.updateAppWidget(publication.views)
            measure(host, wide)
            val plan = publication.plans.single()
            val diagnostic = nativeDiagnostic(host, plan, "states/$name")
            for ((id, view) in retained) assertSame("Retained view=$id: $diagnostic", view,
                host.findViewById<View>(id))
            assertNative(host, plan, "states/$name")
        }
        assertEquals("Stale header preserves six rows", 6, cases[2].second.plans.single().rows.size)
        assertEquals(PhoneWidgetLayout.EmptyState.NO_METRICS, cases[0].second.plans.single().state)
        assertNull("Tiny no-fit publishes no misleading card", cases[1].second.plans.single().card)
    }

    private fun responsive(context: Context) {
        for (count in listOf(3, 4)) {
            val publication = publish(context, options(foldSizes.take(count)))
            assertTrue(publication.sizes.responsive)
            assertEquals(count, publication.plans.size)
            val host = host(context, publication)
            for ((step, index) in ((0 until count).toList() +
                (count - 1 downTo 0).toList()).withIndex()) {
                val case = "responsive/count=$count/step=$step/variant=$index"
                // AppWidgetHostView selects the responsive variant during native layout.
                measure(host, foldSizes[index])
                assertNative(host, publication.plans[index], "$case/layout")
                host.updateAppWidget(publication.views)
                measure(host, foldSizes[index])
                assertNative(host, publication.plans[index], "$case/reapply")
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
            putParcelableArrayList(AppWidgetManager.OPTION_APPWIDGET_SIZES, null)
        }
        val emptyList = Bundle(missing).apply {
            putParcelableArrayList(AppWidgetManager.OPTION_APPWIDGET_SIZES, arrayListOf<SizeF>())
        }
        for (orientation in listOf(Configuration.ORIENTATION_PORTRAIT,
            Configuration.ORIENTATION_LANDSCAPE)) {
            val context = configured(night, orientation)
            for ((name, widgetOptions) in listOf("missing" to missing, "null" to nullList,
                "empty" to emptyList, "default" to Bundle())) {
                val publication = publish(context, widgetOptions)
                assertFalse(publication.sizes.responsive)
                val index = if (orientation == Configuration.ORIENTATION_LANDSCAPE
                    && publication.plans.size == 2) 1 else 0
                val host = host(context, publication)
                measure(host, publication.sizes.values[index])
                assertNative(host, publication.plans[index], "fallback/$name/variant=$index/layout")
                host.updateAppWidget(publication.views)
                measure(host, host.width + 30, host.height + 30)
                assertNative(host, publication.plans[index], "fallback/$name/variant=$index/reapply")
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
        assertNative(defaultHost, defaultPublication.plans.single(), "fallback/invalid")
        val retainedContext = OrientationContext(configured(night, Configuration.ORIENTATION_PORTRAIT))
        val retained = publish(retainedContext, missing)
        val retainedHost = host(retainedContext, retained)
        measure(retainedHost, retained.sizes.values[0])
        val retainedRoot = retainedHost.findViewById<View>(R.id.widget_root)
        for ((step, index) in listOf(0, 1, 0).withIndex()) {
            retainedContext.current = configured(night, if (index == 0)
                Configuration.ORIENTATION_PORTRAIT else Configuration.ORIENTATION_LANDSCAPE)
            retainedHost.updateAppWidget(retained.views)
            measure(retainedHost, retained.sizes.values[index])
            val case = "fallback/retained/step=$step/variant=$index"
            val diagnostic = nativeDiagnostic(retainedHost, retained.plans[index], case)
            assertSame("Legacy orientation reuses the host/root: $diagnostic", retainedRoot,
                retainedHost.findViewById<View>(R.id.widget_root))
            assertNative(retainedHost, retained.plans[index], case)
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
            assertNative(host, publication.plans.first(), "budget/bytes=$budget")
            for (plan in publication.plans) for (layer in layers.keys) {
                val bounds = plan.bounds(layer) ?: continue
                assertTrue(bounds.width() <= PhoneWidgetLayout.MAX_BITMAP_SIDE
                    && bounds.height() <= PhoneWidgetLayout.MAX_BITMAP_SIDE)
            }
            if (budget == 0L) assertTrue(publication.plans.all { it.card == null && it.rows.isEmpty() })
        }
    }

    private fun padding(view: View) =
        listOf(view.paddingLeft, view.paddingTop, view.paddingRight, view.paddingBottom)

    private fun bounds(bounds: PhoneWidgetLayout.Bounds?) =
        bounds?.let { "[${it.left},${it.top},${it.right},${it.bottom}]" } ?: "null"

    private fun viewState(view: View?): String {
        if (view == null) return "missing"
        val geometry = "type=${view.javaClass.simpleName} size=${view.width}x${view.height} " +
            "bounds=[${view.left},${view.top},${view.right},${view.bottom}] " +
            "visibility=${view.visibility} padding=${padding(view)}"
        if (view !is ImageView) return geometry
        val drawable = view.drawable
        val bitmap = (drawable as? BitmapDrawable)?.bitmap
        val content = when {
            bitmap == null -> "null"
            bitmap.isRecycled -> "recycled"
            else -> "${bitmap.width}x${bitmap.height} density=${bitmap.density} " +
                "config=${bitmap.config} bytes=${bitmap.allocationByteCount}"
        }
        return "$geometry drawable=${drawable?.javaClass?.simpleName ?: "null"} bitmap=$content"
    }

    private fun nativeDiagnostic(
        host: AppWidgetHostView, plan: PhoneWidgetLayout.Plan, case: String,
    ): String {
        val configuration = host.resources.configuration
        val root = host.findViewById<View>(R.id.widget_root)
        val card = root?.findViewById<View>(R.id.widget_card)
        val images = layers.entries.joinToString("; ") { (layer, id) ->
            val ink = plan.bounds(layer)
            val expectedBitmap = ink?.let {
                "${it.width()}x${it.height()} density=${Bitmap.DENSITY_NONE}"
            } ?: "null"
            val expectedDrawable = if (ink == null) "null|BitmapDrawable" else "BitmapDrawable"
            val expectedPadding = if (ink == null || plan.card == null) listOf(0, 0, 0, 0)
                else listOf(ink.left - plan.card.left, ink.top - plan.card.top,
                    plan.card.right - ink.right, plan.card.bottom - ink.bottom)
            "layer=$layer expected={drawable=$expectedDrawable bitmap=$expectedBitmap " +
                "ink=${bounds(ink)} visibility=${if (ink == null) View.GONE else View.VISIBLE} " +
                "padding=$expectedPadding} actual={${viewState(root?.findViewById<View>(id))}}"
        }
        return "case=$case API=${Build.VERSION.SDK_INT} density=${host.resources.displayMetrics.density} " +
            "host=${host.width}x${host.height} hostPadding=${padding(host)} " +
            "fontScale=${configuration.fontScale} orientation=${configuration.orientation} " +
            "uiMode=${configuration.uiMode} plan=${plan.width}x${plan.height} rows=${plan.rows.size} " +
            "state=${plan.state} expectedCard=${bounds(plan.card)} expectedRootCardPadding=[0,0,0,0] " +
            "root={${viewState(root)}} card={${viewState(card)}}; $images; " +
            "layer=WATERMARK expected={drawable=${if (plan.mark) "BitmapDrawable" else "null|BitmapDrawable"} " +
            "bitmap=${if (plan.mark) "present density=${Bitmap.DENSITY_NONE}" else "null"} " +
            "visibility=${if (plan.mark) View.VISIBLE else View.GONE} padding=[0,0,0,0]} " +
            "actual={${viewState(root?.findViewById<View>(R.id.widget_watermark))}}"
    }

    private fun assertBitmap(image: ImageView, present: Boolean, diagnostic: String): Bitmap? {
        val drawable = image.drawable
        assertTrue("Expected a bitmap drawable or cleared wrapper: $diagnostic",
            drawable == null || drawable is BitmapDrawable)
        val bitmap = (drawable as? BitmapDrawable)?.bitmap
        // ImageView.setImageBitmap(null) may keep its BitmapDrawable with a null bitmap.
        assertEquals("Bitmap content must be ${if (present) "present" else "cleared"}: $diagnostic",
            present, bitmap != null)
        if (bitmap != null) assertFalse("Bitmap must be usable: $diagnostic", bitmap.isRecycled)
        return bitmap
    }

    private fun assertNative(host: AppWidgetHostView, plan: PhoneWidgetLayout.Plan, case: String) {
        // Capture every layer before any predicate can abort this observation.
        val diagnostic = nativeDiagnostic(host, plan, case)
        val root = requireNotNull(host.findViewById<View>(R.id.widget_root)) { diagnostic }
        val card = requireNotNull(root.findViewById<View>(R.id.widget_card)) { diagnostic }
        assertEquals(diagnostic, host.width, root.width)
        assertEquals(diagnostic, host.height, root.height)
        assertEquals(diagnostic, listOf(0, 0, 0, 0), padding(root))
        assertEquals(diagnostic, listOf(0, 0, 0, 0), padding(card))
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
            val image = requireNotNull(root.findViewById<View>(id) as? ImageView) { diagnostic }
            val ink = plan.bounds(layer)
            assertEquals(diagnostic, if (ink == null) View.GONE else View.VISIBLE, image.visibility)
            val content = assertBitmap(image, ink != null, "layer=$layer: $diagnostic")
            if (ink == null) {
                assertEquals(diagnostic, listOf(0, 0, 0, 0), padding(image))
            } else {
                val bitmap = requireNotNull(content) { diagnostic }
                assertEquals(diagnostic, Bitmap.DENSITY_NONE, bitmap.density)
                assertEquals(diagnostic, ink.width(), bitmap.width)
                assertEquals(diagnostic, ink.height(), bitmap.height)
                assertEquals(diagnostic, card.width, image.width)
                assertEquals(diagnostic, card.height, image.height)
                assertEquals(diagnostic, card.width, bitmap.width + image.paddingLeft + image.paddingRight)
                assertEquals(diagnostic, card.height, bitmap.height + image.paddingTop + image.paddingBottom)
                val plannedCard = requireNotNull(bounds) { diagnostic }
                assertEquals(diagnostic, ink.left - plannedCard.left, image.paddingLeft)
                assertEquals(diagnostic, ink.top - plannedCard.top, image.paddingTop)
            }
        }
        val mark = requireNotNull(root.findViewById<View>(R.id.widget_watermark) as? ImageView) { diagnostic }
        assertEquals(diagnostic, if (plan.mark) View.VISIBLE else View.GONE, mark.visibility)
        assertEquals(diagnostic, listOf(0, 0, 0, 0), padding(mark))
        val markBitmap = assertBitmap(mark, plan.mark, "layer=WATERMARK: $diagnostic")
        if (markBitmap != null) assertEquals(diagnostic, Bitmap.DENSITY_NONE, markBitmap.density)
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
