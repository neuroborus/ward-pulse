package app.wardpulse.wear.ui

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
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
import androidx.compose.foundation.layout.wrapContentWidth
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.PlatformTextStyle
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.LineHeightStyle
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.TextUnit
import androidx.compose.ui.unit.sp
import androidx.wear.compose.material3.Text
import app.wardpulse.wear.model.WatchDashboardSummary
import app.wardpulse.wear.sync.PhoneRefreshRequester
import java.time.Duration
import java.time.Instant
import kotlin.math.cos
import kotlin.math.sin
import kotlinx.coroutines.delay

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
    val rowGap: Dp,
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
        title = glanceTextStyle(artSp(16f), LabelBright),
        subtitle = glanceTextStyle(artSp(14f), LabelMuted),
        refreshLabel = glanceTextStyle(artSp(13f), LabelBright),
        detail = glanceTextStyle(artSp(11f), DetailMuted),
        alerts = glanceTextStyle(artSp(16f), LabelBright),
        refreshSize = art(RefreshPlateRArt * 2f),
        // miniR=17, miniT=5 → outer box 2*(r + t/2).
        miniArcSize = art(39f),
        miniStroke = art(5f),
        textGap = art(12f),
        rowHeight = art(54f),
        rowGap = art(6f),
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
                    GlanceEmptyCopy(summary = summary, titleStyle = metrics.title)
                } else {
                    // Wrap-content block (review art blockLeft), not full-bleed rows.
                    Column(
                        verticalArrangement = Arrangement.spacedBy(metrics.rowGap),
                        modifier = Modifier.wrapContentWidth(),
                    ) {
                        rows.forEach { row ->
                            key(row.title, row.subtitle) {
                                GlanceLegendRow(row = row, metrics = metrics)
                            }
                        }
                    }
                }
            }

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
    val lines = when {
        summary.providers.isEmpty() && summary.rings.isEmpty() ->
            listOf("Connect a provider", "on your phone")
        summary.rings.isEmpty() ->
            listOf("Choose percent rings", "in the phone app")
        else -> listOf("No remaining capacity")
    }
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

@Composable
private fun GlanceLegendRow(
    row: GlanceLegendRowModel,
    metrics: GlanceMetrics,
) {
    Row(
        verticalAlignment = Alignment.CenterVertically,
        modifier = Modifier.height(metrics.rowHeight),
    ) {
        MiniRemainingArc(
            remainingFraction = row.remainingFraction,
            color = Color(row.colorArgb),
            stroke = metrics.miniStroke,
            modifier = Modifier.size(metrics.miniArcSize),
        )
        Spacer(modifier = Modifier.width(metrics.textGap))
        Column {
            Text(
                row.title,
                style = metrics.title,
                color = LabelBright,
                maxLines = 1,
                softWrap = false,
                overflow = TextOverflow.Clip,
            )
            Text(
                row.subtitle,
                style = metrics.subtitle,
                color = LabelMuted,
                maxLines = 1,
                softWrap = false,
                overflow = TextOverflow.Clip,
            )
        }
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
        val strokeStyle = Stroke(width = strokeWidth, cap = StrokeCap.Round)
        val inset = strokeStyle.width / 2f
        val arcSize = Size(size.width - inset * 2f, size.height - inset * 2f)
        val topLeft = Offset(inset, inset)
        drawArc(
            color = TrackGray,
            startAngle = -90f,
            sweepAngle = 360f,
            useCenter = false,
            topLeft = topLeft,
            size = arcSize,
            style = strokeStyle,
        )
        val sweep = remainingFraction.coerceIn(0f, 1f) * 360f
        if (sweep > 0f) {
            drawArc(
                color = color,
                startAngle = -90f,
                sweepAngle = sweep,
                useCenter = false,
                topLeft = topLeft,
                size = arcSize,
                style = strokeStyle,
            )
        }
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
