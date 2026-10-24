package app.wardpulse.wear.ui

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.focusable
import androidx.compose.foundation.gestures.scrollBy
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicText
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.input.nestedscroll.NestedScrollConnection
import androidx.compose.ui.input.nestedscroll.NestedScrollSource
import androidx.compose.ui.input.nestedscroll.nestedScroll
import androidx.compose.ui.input.rotary.onRotaryScrollEvent
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.text
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.PlatformTextStyle
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.TextLayoutResult
import androidx.compose.ui.text.TextMeasurer
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.text.style.LineHeightStyle
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Constraints
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.TextUnit
import androidx.compose.ui.unit.Velocity
import androidx.compose.ui.unit.sp
import androidx.wear.compose.material3.Text
import app.wardpulse.wear.model.WatchDashboardSummary
import app.wardpulse.wear.sync.PhoneRefreshRequester
import java.time.Duration
import java.time.Instant
import kotlin.math.ceil
import kotlin.math.cos
import kotlin.math.floor
import kotlin.math.sin
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

private val GlanceTextStyle =
    TextStyle(
        fontWeight = FontWeight.Bold,
        platformStyle = PlatformTextStyle(includeFontPadding = false),
        lineHeightStyle = LineHeightStyle(
            alignment = LineHeightStyle.Alignment.Center,
            trim = LineHeightStyle.Trim.Both,
        ),
    )

private fun glanceTextStyle(size: TextUnit, color: Color): TextStyle =
    GlanceTextStyle.copy(fontSize = size, color = color)

/** Locked Glance legend tokens (`WEAR_GLANCE_DESIGN.md` / review art). */
private val OkGreen = Color(0xFF65D78A)
private val WarnAmber = Color(0xFFE6C349)
private val DisabledGray = Color(0xFF5A635C)
private val DetailMuted = Color(0xFF5C655E)
private val LabelBright = Color(0xFFF4FBF8)
private val LabelMuted = Color(0xFF8A968F)
private val TrackGray = Color(0xFF2E3632)
private val PlateFill = Color(0xFF141916)
private val PlateFillDisabled = Color(0xFF121512)
private val PlateStroke = Color(0xFF2E3632)
private val AlertsActiveFill = Color(0xFF2A322C)
private val AlertsIdleFill = Color(0xFF171B18)
private val AlertsIdleStroke = Color(0xFF2A302C)
private val SurfaceMid = Color(0xFF101412)
private val SurfaceLift = Color(0xFF18201C)
private val SurfaceEdge = Color(0xFF0A0D0B)

/** Canvas size in `tools/render-wear-glance-designs.mjs`. */
private const val GlanceArtSizePx = 450f

/** Refresh plate radius / stroke / inset from the same review generator. */
private const val RefreshPlateRArt = 34f
private const val RefreshStrokeArt = 2.2f
private const val RefreshPadArt = 9f

private data class GlanceMetrics(
    val title: TextStyle,
    val subtitle: TextStyle,
    val refreshLabel: TextStyle,
    val detail: TextStyle,
    val alerts: TextStyle,
    val refreshSize: Dp,
    val miniArcSize: Dp,
    val miniStroke: Dp,
    val textGap: Dp,
    val rowHeight: Dp,
    val alertsGap: Dp,
    val timeClearance: Dp,
    val bottomClearance: Dp,
    val contentPadH: Dp,
    val alertsHeight: Dp,
    val alertsMinWidth: Dp,
    val alertsMaxWidth: Dp,
    val alertsPadH: Dp,
    val alertsRadius: Dp,
    val alertsStroke: Dp,
    val detailGap: Dp,
)

/** Scale review-art pixels onto the round shell diameter (not raw dp ≈ art px). */
private fun glanceMetricsFor(diameter: Dp): GlanceMetrics {
    fun art(px: Float): Dp = diameter * (px / GlanceArtSizePx)
    fun artSp(px: Float) = (diameter.value * (px / GlanceArtSizePx)).sp
    // refreshCy=96, r=34 → plate top at 62; clears AppScaffold StraightAppTimeText.
    return GlanceMetrics(
        title = glanceTextStyle(artSp(20f), LabelBright),
        subtitle = glanceTextStyle(artSp(18f), LabelMuted),
        refreshLabel = glanceTextStyle(artSp(13f), LabelBright),
        detail = glanceTextStyle(artSp(11f), DetailMuted),
        alerts = glanceTextStyle(artSp(16f), LabelBright),
        refreshSize = art(RefreshPlateRArt * 2f),
        // miniR=17, miniT=5 → outer box 2*(r + t/2).
        miniArcSize = art(39f),
        miniStroke = art(5f),
        textGap = art(12f),
        rowHeight = art(62f),
        // The art keeps the block clear of the pill by 12 (`alertsBtnY - 12`).
        alertsGap = art(12f),
        timeClearance = art(62f),
        // alertsBtnY = SIZE-78, h=36 → 42px below pill to rim.
        bottomClearance = art(42f),
        contentPadH = art(28f),
        alertsHeight = art(36f),
        alertsMinWidth = art(128f),
        alertsMaxWidth = art(200f),
        alertsPadH = art(18f),
        alertsRadius = art(18f),
        alertsStroke = art(1f),
        detailGap = art(8f),
    )
}

/**
 * Wear app home Glance — text legend for face ring colors
 * (`docs/product/WEAR_GLANCE_DESIGN.md`, baseline 2026-07-26).
 */
@Composable
internal fun GlanceLegendPage(
    summary: WatchDashboardSummary,
    onOpenAlerts: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val context = LocalContext.current
    val requester = remember { PhoneRefreshRequester(context) }
    var refreshAllowed by remember { mutableStateOf(summary.isManualRefreshAllowed()) }
    LaunchedEffect(
        summary.generatedAt,
        summary.manualRefreshAllowed,
        summary.manualRefreshAvailableAt,
    ) {
        refreshAllowed = summary.isManualRefreshAllowed()
        if (refreshAllowed) {
            return@LaunchedEffect
        }
        val availableAt =
            summary.manualRefreshAvailableAt
                ?.let { runCatching { Instant.parse(it) }.getOrNull() }
                ?: return@LaunchedEffect
        val delayMs =
            Duration.between(Instant.now(), availableAt).toMillis().coerceAtLeast(0L)
        if (delayMs > 0L) {
            delay(delayMs)
        }
        refreshAllowed = summary.isManualRefreshAllowed()
    }

    val chrome = glanceRefreshChrome(summary, refreshAllowed = refreshAllowed)
    val rows = glanceLegendRows(summary)
    val alertCount = summary.alerts.size

    BoxWithConstraints(modifier = modifier.fillMaxSize()) {
        val density = LocalDensity.current
        val diameter = minOf(maxWidth, maxHeight)
        val metrics = glanceMetricsFor(diameter)
        val gradient = Brush.radialGradient(
            colorStops = arrayOf(
                0.0f to SurfaceLift,
                0.55f to SurfaceMid,
                1.0f to SurfaceEdge,
            ),
            center = Offset(
                with(density) { maxWidth.toPx() / 2f },
                with(density) { maxHeight.toPx() * 0.48f },
            ),
            radius = with(density) { diameter.toPx() * 0.62f },
        )
        Column(
            modifier = Modifier
                .fillMaxSize()
                .background(gradient)
                .padding(horizontal = metrics.contentPadH)
                .padding(top = metrics.timeClearance, bottom = metrics.bottomClearance),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            GlanceRefreshControl(
                chrome = chrome,
                controlSize = metrics.refreshSize,
                labelStyle = metrics.refreshLabel,
                onRefresh = { requester.requestRefresh() },
            )
            if (chrome.detail != null) {
                Text(
                    chrome.detail,
                    modifier = Modifier.padding(top = metrics.detailGap),
                    style = metrics.detail,
                    color = DetailMuted,
                    textAlign = TextAlign.Center,
                )
            }

            Box(
                modifier = Modifier
                    .weight(1f)
                    .fillMaxWidth(),
                contentAlignment = Alignment.Center,
            ) {
                if (rows.isEmpty()) {
                    GlanceEmptyCopy(
                        summary = summary,
                        titleStyle = metrics.title.copy(
                            fontSize = (diameter.value * (16f / GlanceArtSizePx)).sp,
                        ),
                    )
                } else {
                    GlanceLegend(rows = rows, metrics = metrics, diameter = diameter)
                }
            }

            Spacer(modifier = Modifier.height(metrics.alertsGap))
            GlanceAlertsPill(
                count = alertCount,
                metrics = metrics,
                onOpen = onOpenAlerts,
            )
        }
    }
}

@Composable
private fun GlanceEmptyCopy(
    summary: WatchDashboardSummary,
    titleStyle: TextStyle,
) {
    val lines = glanceEmptyLines(summary)
    Column(horizontalAlignment = Alignment.CenterHorizontally) {
        lines.forEach { line ->
            Text(
                line,
                style = titleStyle,
                color = LabelMuted,
                textAlign = TextAlign.Center,
            )
        }
    }
}

internal fun glanceEmptyLines(summary: WatchDashboardSummary): List<String> =
    when {
        summary.providers.isEmpty() && summary.rings.isEmpty() ->
            listOf("Connect a provider", "on your phone")
        summary.rings.isEmpty() ->
            listOf("Choose percent rings", "in the phone app")
        else -> listOf("Ring data unavailable")
    }

internal data class GlanceMeasuredText(
    val text: AnnotatedString,
    val style: TextStyle,
    val layout: TextLayoutResult,
    val height: Int,
)

internal data class GlanceMeasuredRow(
    val model: GlanceLegendRowModel,
    val title: GlanceMeasuredText,
    val subtitle: GlanceMeasuredText,
    val height: Int,
)

internal data class GlanceLegendLayout(
    val rows: List<GlanceMeasuredRow>,
    val width: Int,
    val viewportHeight: Int,
    val scrolling: Boolean,
)

/** Replace only separator ranges, appending annotated slices to retain numeric colours. */
private fun glanceSubtitleSegments(text: AnnotatedString, splitPools: Boolean): AnnotatedString {
    val separators = Regex(" · ").findAll(text.text).toList()
    return buildAnnotatedString {
        var start = 0
        separators.forEach { separator ->
            val suffix = text.text.substring(separator.range.last + 1)
            val isCredits = suffix.endsWith(" credits") && " · " !in suffix
            if (splitPools || isCredits) {
                append(text.subSequence(start, separator.range.first))
                append("\n")
                start = separator.range.last + 1
            }
        }
        append(text.subSequence(start, text.length))
    }
}

private fun measureGlanceText(
    text: AnnotatedString,
    preferred: Int,
    floorSize: Int,
    lineHeight: Float,
    baseStyle: TextStyle,
    width: Int,
    diameter: Dp,
    density: Density,
    measurer: TextMeasurer,
    subtitle: Boolean = false,
): GlanceMeasuredText {
    fun style(size: Int) = baseStyle.copy(
        fontSize = (diameter.value * size / GlanceArtSizePx).sp,
        lineHeight = (diameter.value * lineHeight / GlanceArtSizePx).sp,
    )

    fun measure(value: AnnotatedString, size: Int, wrap: Boolean) = measurer.measure(
        text = value,
        style = style(size),
        softWrap = wrap,
        constraints = if (wrap) Constraints(maxWidth = width) else Constraints(),
    )

    fun result(value: AnnotatedString, size: Int, layout: TextLayoutResult): GlanceMeasuredText {
        val reservedLineHeight = with(density) { style(size).lineHeight.toPx() }
        return GlanceMeasuredText(
            value,
            style(size),
            layout,
            ceil(maxOf(layout.size.height.toFloat(), reservedLineHeight * layout.lineCount)).toInt(),
        )
    }

    for (size in preferred downTo floorSize) {
        val layout = measure(text, size, wrap = false)
        if (layout.size.width <= width) return result(text, size, layout)
    }

    // Try a percentage pair together, then separate pools if even the floor cannot fit it.
    // Titles use ordinary word boundaries; a remaining oversized token wraps by grapheme.
    val candidates = if (subtitle) {
        listOf(glanceSubtitleSegments(text, false), glanceSubtitleSegments(text, true))
    } else {
        listOf(text)
    }
    for (candidate in candidates) {
        for (size in preferred downTo floorSize) {
            val segments = if (subtitle) candidate.text.split('\n') else candidate.text.split(' ')
            if (segments.all { measure(AnnotatedString(it), size, false).size.width <= width }) {
                return result(candidate, size, measure(candidate, size, wrap = true))
            }
        }
    }
    val candidate = candidates.last()
    return result(candidate, floorSize, measure(candidate, floorSize, wrap = true))
}

/** Native text measurement is independent of overflow: short scaled rows also gain height. */
internal fun measureGlanceLegend(
    rows: List<GlanceLegendRowModel>,
    diameter: Dp,
    availableWidth: Int,
    availableHeight: Int,
    density: Density,
    measurer: TextMeasurer,
): GlanceLegendLayout {
    fun art(value: Float) = with(density) { (diameter * (value / GlanceArtSizePx)).toPx() }
    val metrics = glanceMetricsFor(diameter)
    val blockWidth = minOf(floor(art(370f)).toInt(), availableWidth).coerceAtLeast(1)
    val gap = art(2f) * density.fontScale
    fun arcColumns(row: GlanceLegendRowModel): Int = with(density) {
        val columns = if (row.secondaryArc == null) 1 else 2
        columns * ((diameter * (39f / GlanceArtSizePx)).roundToPx() +
            (diameter * (12f / GlanceArtSizePx)).roundToPx())
    }
    fun measuredRows(indicator: Int) = rows.map { row ->
        val textWidth = (blockWidth - indicator - arcColumns(row)).coerceAtLeast(1)
        val title = measureGlanceText(
            AnnotatedString(row.title), 20, 18, 28f, metrics.title,
            textWidth, diameter, density, measurer,
        )
        val subtitle = measureGlanceText(
            glanceSubtitleText(row), 18, 16, 26f, metrics.subtitle,
            textWidth, diameter, density, measurer, subtitle = true,
        )
        GlanceMeasuredRow(
            row, title, subtitle,
            ceil(maxOf(
                art(39f),
                with(density) { metrics.rowHeight.toPx() } * density.fontScale,
                title.height + subtitle.height + gap + art(6f) * density.fontScale,
            )).toInt(),
        )
    }
    val initial = measuredRows(0)
    val scrolling = initial.sumOf { it.height } > availableHeight
    val indicator = if (scrolling) ceil(art(6f)).toInt() else 0
    val measured = if (scrolling) measuredRows(indicator) else initial
    val contentWidth = measured.maxOfOrNull { row ->
        arcColumns(row.model) +
            maxOf(row.title.layout.size.width, row.subtitle.layout.size.width)
    } ?: 0
    return GlanceLegendLayout(
        measured,
        if (scrolling) blockWidth else minOf(blockWidth, contentWidth),
        if (scrolling) (availableHeight - ceil(art(14f)).toInt()).coerceAtLeast(1) else availableHeight,
        scrolling,
    )
}

@Composable
private fun GlanceLegend(rows: List<GlanceLegendRowModel>, metrics: GlanceMetrics, diameter: Dp) {
    val density = LocalDensity.current
    val measurer = rememberTextMeasurer()
    val scroll = rememberScrollState()
    val scope = rememberCoroutineScope()
    // Consume only the unused vertical motion/velocity, including at both limits. The
    // parent Home Pager keeps gestures outside this viewport and horizontal back swipes.
    val boundary = remember {
        object : NestedScrollConnection {
            override fun onPostScroll(
                consumed: Offset,
                available: Offset,
                source: NestedScrollSource,
            ) = Offset(0f, available.y)

            override suspend fun onPostFling(consumed: Velocity, available: Velocity) =
                Velocity(0f, available.y)
        }
    }
    BoxWithConstraints(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
        val layout = remember(rows, diameter, constraints, density, measurer) {
            measureGlanceLegend(
                rows, diameter, constraints.maxWidth, constraints.maxHeight, density, measurer,
            )
        }
        LaunchedEffect(layout.scrolling) {
            if (!layout.scrolling) scroll.scrollTo(0)
        }
        val blockWidth = with(density) { layout.width.toDp() }
        val gap = diameter * (2f / GlanceArtSizePx) * density.fontScale
        val indicatorWidth = diameter * (6f / GlanceArtSizePx)
        Box(
            modifier = Modifier
                .align(if (layout.scrolling) Alignment.TopCenter else Alignment.Center)
                .width(blockWidth)
                .then(if (layout.scrolling) {
                    Modifier.height(with(density) { layout.viewportHeight.toDp() }).clipToBounds()
                } else Modifier),
        ) {
            val scrolling = if (layout.scrolling) {
                Modifier
                    .nestedScroll(boundary)
                    .onRotaryScrollEvent {
                        scope.launch { scroll.scrollBy(it.verticalScrollPixels) }
                        true
                    }
                    .verticalScroll(scroll)
                    .focusable()
                    .padding(end = indicatorWidth)
            } else Modifier
            Column(modifier = Modifier.fillMaxWidth().then(scrolling)) {
                layout.rows.forEach { row -> GlanceLegendRow(row, metrics, gap) }
            }
            if (layout.scrolling) {
                Canvas(Modifier.align(Alignment.CenterEnd).width(indicatorWidth).height(
                    with(density) { layout.viewportHeight.toDp() },
                )) {
                    val contentHeight = size.height + scroll.maxValue
                    val thumb = (size.height * size.height / contentHeight).coerceAtMost(size.height)
                    val top = if (scroll.maxValue == 0) 0f else {
                        (size.height - thumb) * scroll.value / scroll.maxValue
                    }
                    drawLine(
                        LabelMuted, Offset(size.width / 2f, top),
                        Offset(size.width / 2f, top + thumb),
                        strokeWidth = size.width / 3f,
                    )
                }
            }
        }
    }
}

@Composable
private fun GlanceLegendRow(row: GlanceMeasuredRow, metrics: GlanceMetrics, gap: Dp) {
    val density = LocalDensity.current
    val model = row.model
    Row(
        verticalAlignment = Alignment.CenterVertically,
        modifier = Modifier.fillMaxWidth().height(with(density) { row.height.toDp() }),
    ) {
        MiniRemainingArc(
            remainingFraction = model.remainingFraction,
            color = Color(model.colorArgb),
            stroke = metrics.miniStroke,
            modifier = Modifier.size(metrics.miniArcSize),
        )
        model.secondaryArc?.let { arc ->
            Spacer(modifier = Modifier.width(metrics.textGap))
            MiniRemainingArc(
                remainingFraction = arc.remainingFraction,
                color = Color(arc.colorArgb),
                stroke = metrics.miniStroke,
                modifier = Modifier.size(metrics.miniArcSize),
            )
        }
        Spacer(modifier = Modifier.width(metrics.textGap))
        Column(modifier = Modifier.weight(1f)) {
            GlanceLegendText(row.title)
            Spacer(Modifier.height(gap))
            GlanceLegendText(
                row.subtitle,
                Modifier.clearAndSetSemantics { text = glanceSubtitleText(model) },
            )
        }
    }
}

@Composable
private fun GlanceLegendText(text: GlanceMeasuredText, modifier: Modifier = Modifier) {
    val density = LocalDensity.current
    Box(
        modifier = Modifier.fillMaxWidth().height(with(density) { text.height.toDp() }),
        contentAlignment = Alignment.CenterStart,
    ) {
        BasicText(text.text, style = text.style, modifier = modifier)
    }
}

/** Only genuinely exhausted percent tokens take the existing phone error color. */
internal fun glanceSubtitleText(row: GlanceLegendRowModel): AnnotatedString =
    buildAnnotatedString {
        append(row.subtitle)
        row.exhaustedPercentRanges.forEach { range ->
            addStyle(SpanStyle(color = Color(0xFFFFB4AB)), range.first, range.last + 1)
        }
    }

@Composable
private fun MiniRemainingArc(
    remainingFraction: Float,
    color: Color,
    stroke: Dp,
    modifier: Modifier = Modifier,
) {
    val strokeWidth = with(LocalDensity.current) { stroke.toPx() }
    Canvas(modifier = modifier) {
        drawMiniRemainingArc(remainingFraction, color, strokeWidth)
    }
}

/** Shared by the legend Canvas and the native pixel regression. */
internal fun DrawScope.drawMiniRemainingArc(
    remainingFraction: Float,
    color: Color,
    strokeWidth: Float,
) {
    val inset = strokeWidth / 2f
    val arcSize = Size(size.width - inset * 2f, size.height - inset * 2f)
    val topLeft = Offset(inset, inset)
    drawArc(
        color = TrackGray,
        startAngle = -90f,
        sweepAngle = 360f,
        useCenter = false,
        topLeft = topLeft,
        size = arcSize,
        style = Stroke(width = strokeWidth, cap = StrokeCap.Round),
    )
    val remaining = remainingFraction.coerceIn(0f, 1f)
    if (remaining > 0f) {
        val span = remaining * 360f
        val capDegrees =
            Math.toDegrees((strokeWidth / 2f / (arcSize.width / 2f)).toDouble()).toFloat()
        // Compensate round ends only when they fit. Short spans keep their actual
        // angular extent with flat ends instead of disappearing or becoming a dot.
        val roundEnds = span > 2f * capDegrees
        val capInset = if (roundEnds) capDegrees else 0f
        drawArc(
            color = color,
            startAngle = -90f + (1f - remaining) * 360f + capInset,
            sweepAngle = span - 2f * capInset,
            useCenter = false,
            topLeft = topLeft,
            size = arcSize,
            style = Stroke(
                width = strokeWidth,
                cap = if (roundEnds) StrokeCap.Round else StrokeCap.Butt,
            ),
        )
    }
}

@Composable
private fun GlanceRefreshControl(
    chrome: GlanceRefreshChrome,
    controlSize: Dp,
    labelStyle: TextStyle,
    onRefresh: () -> Unit,
) {
    val accent = when {
        !chrome.enabled -> DisabledGray
        chrome.ok -> OkGreen
        else -> WarnAmber
    }
    val plate = if (chrome.enabled) PlateFill else PlateFillDisabled
    val label = if (chrome.ok) "OK" else "!OK"
    val plateBorder = controlSize * (1f / (RefreshPlateRArt * 2f))

    Box(
        contentAlignment = Alignment.Center,
        modifier = Modifier
            .size(controlSize)
            .clip(CircleShape)
            .background(plate)
            .border(BorderStroke(plateBorder, PlateStroke), CircleShape)
            .clickable(enabled = chrome.enabled, onClick = onRefresh),
    ) {
        Canvas(modifier = Modifier.fillMaxSize()) {
            val plateR = size.minDimension / 2f
            val sw = plateR * (RefreshStrokeArt / RefreshPlateRArt)
            val pad = plateR * (RefreshPadArt / RefreshPlateRArt)
            val arcR = plateR - pad - sw * 1.75f
            val center = Offset(size.width / 2f, size.height / 2f)
            drawRefreshArrow(center, arcR, 310f, 76f, sw, accent)
            drawRefreshArrow(center, arcR, 130f, 256f, sw, accent)
        }
        Text(
            label,
            style = labelStyle,
            color = accent,
        )
    }
}

private fun DrawScope.drawRefreshArrow(
    center: Offset,
    radius: Float,
    startDeg: Float,
    tipDeg: Float,
    strokeWidth: Float,
    color: Color,
) {
    // Match tools/render-wear-glance-designs.mjs: fixed head length in px-space.
    val headLen = strokeWidth * 3.6f
    val headHalf = strokeWidth * 1.75f
    val gapDeg = 0.9f
    val insetDeg = Math.toDegrees((headLen / radius).toDouble()).toFloat()
    val baseDeg = tipDeg - insetDeg
    val arcEndDeg = baseDeg - gapDeg
    val sweep = (arcEndDeg - startDeg + 360f) % 360f

    drawArc(
        color = color,
        startAngle = startDeg - 90f,
        sweepAngle = sweep,
        useCenter = false,
        topLeft = Offset(center.x - radius, center.y - radius),
        size = Size(radius * 2f, radius * 2f),
        style = Stroke(width = strokeWidth, cap = StrokeCap.Butt),
    )

    val tip = polar(center, tipDeg, radius)
    val base = polar(center, baseDeg, radius)
    val tangent = clockwiseTangent(baseDeg)
    val normal = Offset(-tangent.y, tangent.x)
    val path = Path().apply {
        moveTo(tip.x, tip.y)
        lineTo(base.x + normal.x * headHalf, base.y + normal.y * headHalf)
        lineTo(base.x - normal.x * headHalf, base.y - normal.y * headHalf)
        close()
    }
    drawPath(path, color = color)
}

private fun polar(center: Offset, deg: Float, radius: Float): Offset {
    val rad = Math.toRadians(deg - 90.0)
    return Offset(
        center.x + (radius * cos(rad)).toFloat(),
        center.y + (radius * sin(rad)).toFloat(),
    )
}

private fun clockwiseTangent(deg: Float): Offset {
    val rad = Math.toRadians(deg - 90.0) + Math.PI / 2.0
    return Offset(cos(rad).toFloat(), sin(rad).toFloat())
}

@Composable
private fun GlanceAlertsPill(
    count: Int,
    metrics: GlanceMetrics,
    onOpen: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val active = count > 0
    val shape = RoundedCornerShape(metrics.alertsRadius)
    val stroke = if (active) metrics.alertsStroke * 1.5f else metrics.alertsStroke
    val labelColor = if (active) LabelBright else DisabledGray
    Box(
        contentAlignment = Alignment.Center,
        modifier = modifier
            .height(metrics.alertsHeight)
            .widthIn(min = metrics.alertsMinWidth, max = metrics.alertsMaxWidth)
            .clip(shape)
            .background(if (active) AlertsActiveFill else AlertsIdleFill.copy(alpha = 0.85f))
            .border(
                BorderStroke(
                    width = stroke,
                    color = if (active) WarnAmber else AlertsIdleStroke,
                ),
                shape,
            )
            .clickable(enabled = active, onClick = onOpen)
            .padding(horizontal = metrics.alertsPadH),
    ) {
        Text(
            "Alerts: $count",
            style = metrics.alerts,
            color = labelColor,
            textAlign = TextAlign.Center,
            maxLines = 1,
        )
    }
}
