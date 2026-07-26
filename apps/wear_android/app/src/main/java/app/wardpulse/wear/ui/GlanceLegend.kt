package app.wardpulse.wear.ui

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.wear.compose.material3.MaterialTheme
import androidx.wear.compose.material3.Text
import app.wardpulse.wear.model.WatchDashboardSummary
import app.wardpulse.wear.sync.PhoneRefreshRequester
import java.time.Duration
import java.time.Instant
import kotlin.math.cos
import kotlin.math.sin
import kotlinx.coroutines.delay

private val OkGreen = Color(0xFF65D78A)
private val WarnAmber = Color(0xFFE6C349)
private val DisabledGray = Color(0xFF5A635C)
private val DetailMuted = Color(0xFF5C655E)
private val TrackGray = Color(0xFF2E3632)
private val PlateFill = Color(0xFF141916)
private val PlateFillDisabled = Color(0xFF121512)
private val AlertsActiveFill = Color(0xFF2A322C)
private val AlertsIdleFill = Color(0xFF171B18)
private val AlertsIdleStroke = Color(0xFF2A302C)

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
    var refreshAllowed by remember(
        summary.manualRefreshAllowed,
        summary.manualRefreshAvailableAt,
    ) {
        mutableStateOf(summary.isManualRefreshAllowed())
    }
    LaunchedEffect(summary.manualRefreshAllowed, summary.manualRefreshAvailableAt) {
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

    Column(
        modifier = modifier
            .fillMaxSize()
            .padding(horizontal = 14.dp, vertical = 4.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Spacer(modifier = Modifier.height(18.dp))
        GlanceRefreshControl(
            chrome = chrome,
            onRefresh = { requester.requestRefresh() },
        )
        if (chrome.detail != null) {
            Text(
                chrome.detail,
                modifier = Modifier.padding(top = 6.dp),
                style = MaterialTheme.typography.labelSmall.copy(
                    fontSize = 11.sp,
                    fontWeight = FontWeight.Bold,
                ),
                color = DetailMuted,
                textAlign = TextAlign.Center,
            )
        }

        Box(
            modifier = Modifier
                .weight(1f)
                .fillMaxWidth()
                .padding(top = 8.dp, bottom = 4.dp),
            contentAlignment = Alignment.Center,
        ) {
            if (rows.isEmpty()) {
                GlanceEmptyCopy(summary = summary)
            } else {
                Column(
                    verticalArrangement = Arrangement.spacedBy(6.dp),
                    modifier = Modifier.fillMaxWidth(),
                ) {
                    rows.forEach { row ->
                        GlanceLegendRow(row = row)
                    }
                }
            }
        }

        GlanceAlertsPill(
            count = alertCount,
            onOpen = onOpenAlerts,
            modifier = Modifier.padding(bottom = 10.dp),
        )
    }
}

@Composable
private fun GlanceEmptyCopy(summary: WatchDashboardSummary) {
    val lines =
        if (summary.rings.isEmpty()) {
            listOf("Choose percent rings", "in the phone app")
        } else {
            listOf("No remaining capacity")
        }
    Column(horizontalAlignment = Alignment.CenterHorizontally) {
        lines.forEach { line ->
            Text(
                line,
                style = MaterialTheme.typography.bodySmall.copy(fontWeight = FontWeight.Bold),
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                textAlign = TextAlign.Center,
            )
        }
    }
}

@Composable
private fun GlanceLegendRow(row: GlanceLegendRowModel) {
    Row(
        verticalAlignment = Alignment.CenterVertically,
        modifier = Modifier.fillMaxWidth(),
    ) {
        MiniRemainingArc(
            remainingFraction = row.remainingFraction,
            color = Color(row.colorArgb),
            modifier = Modifier.size(34.dp),
        )
        Spacer(modifier = Modifier.width(10.dp))
        Column(modifier = Modifier.weight(1f)) {
            Text(
                row.title,
                style = MaterialTheme.typography.labelLarge.copy(fontWeight = FontWeight.Bold),
                color = MaterialTheme.colorScheme.onBackground,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
            Text(
                row.subtitle,
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
        }
    }
}

@Composable
private fun MiniRemainingArc(
    remainingFraction: Float,
    color: Color,
    modifier: Modifier = Modifier,
) {
    Canvas(modifier = modifier) {
        val stroke = Stroke(width = size.minDimension * 0.18f, cap = StrokeCap.Round)
        val inset = stroke.width / 2f
        val arcSize = Size(size.width - inset * 2f, size.height - inset * 2f)
        val topLeft = Offset(inset, inset)
        drawArc(
            color = TrackGray,
            startAngle = -90f,
            sweepAngle = 360f,
            useCenter = false,
            topLeft = topLeft,
            size = arcSize,
            style = stroke,
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
                style = stroke,
            )
        }
    }
}

@Composable
private fun GlanceRefreshControl(
    chrome: GlanceRefreshChrome,
    onRefresh: () -> Unit,
) {
    val accent = when {
        !chrome.enabled -> DisabledGray
        chrome.ok -> OkGreen
        else -> WarnAmber
    }
    val plate = if (chrome.enabled) PlateFill else PlateFillDisabled
    val label = if (chrome.ok) "OK" else "!OK"

    Box(
        contentAlignment = Alignment.Center,
        modifier = Modifier
            .size(68.dp)
            .clip(CircleShape)
            .background(plate)
            .then(
                if (chrome.enabled) {
                    Modifier.clickable(onClick = onRefresh)
                } else {
                    Modifier
                },
            ),
    ) {
        Canvas(modifier = Modifier.fillMaxSize().padding(9.dp)) {
            val strokeWidth = size.minDimension * 0.085f
            val radius = size.minDimension / 2f - strokeWidth * 1.75f
            val center = Offset(size.width / 2f, size.height / 2f)
            drawRefreshArrow(center, radius, 310f, 76f, strokeWidth, accent)
            drawRefreshArrow(center, radius, 130f, 256f, strokeWidth, accent)
        }
        Text(
            label,
            style = MaterialTheme.typography.labelLarge.copy(
                fontSize = 13.sp,
                fontWeight = FontWeight.Bold,
            ),
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
    val headLen = strokeWidth * 3.4f
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
    onOpen: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val active = count > 0
    val shape = RoundedCornerShape(18.dp)
    Box(
        contentAlignment = Alignment.Center,
        modifier = modifier
            .clip(shape)
            .background(if (active) AlertsActiveFill else AlertsIdleFill)
            .border(
                BorderStroke(
                    width = if (active) 1.5.dp else 1.dp,
                    color = if (active) WarnAmber else AlertsIdleStroke,
                ),
                shape,
            )
            .clickable(enabled = active, onClick = onOpen)
            .padding(horizontal = 18.dp, vertical = 8.dp),
    ) {
        Text(
            "Alerts: $count",
            style = MaterialTheme.typography.labelLarge.copy(fontWeight = FontWeight.Bold),
            color = if (active) {
                MaterialTheme.colorScheme.onBackground
            } else {
                DisabledGray
            },
            textAlign = TextAlign.Center,
        )
    }
}
