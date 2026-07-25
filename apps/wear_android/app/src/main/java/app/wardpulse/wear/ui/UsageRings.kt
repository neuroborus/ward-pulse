package app.wardpulse.wear.ui

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.wear.compose.material3.MaterialTheme
import androidx.wear.compose.material3.Text
import app.wardpulse.wear.model.PulseStatus
import app.wardpulse.wear.model.RingSummary
import kotlin.math.min
import kotlin.math.roundToInt

/**
 * Concentric remaining arcs + sunk family strips
 * (`docs/product/WATCH_RING_DESIGN.md`, baseline 2026-07-25).
 *
 * Outer ring is the tightest remaining selected metric. Exhausted layers are omitted upstream.
 * Watch-face time lives on the system / WFF surface; the Wear app module keeps the aperture for strips.
 */
@Composable
internal fun UsageRings(
    rings: List<RingSummary>,
    modifier: Modifier = Modifier,
    diameter: Dp = 152.dp,
    tokenGlance: String? = null,
) {
    if (rings.isEmpty()) {
        return
    }

    val trackColor = MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.55f)
    val colors = rings.map { ringFamilyColor(it.id, it.status) }
    val density = LocalDensity.current
    val strokeWidth = with(density) { 8.dp.toPx() }
    val gap = with(density) { 3.dp.toPx() }
    val wellColor = Color(0xE60B0E0C)

    Box(modifier = modifier, contentAlignment = Alignment.Center) {
        Canvas(modifier = Modifier.size(diameter)) {
            val outer = min(size.width, size.height)
            val center = Offset(size.width / 2f, size.height / 2f)
            rings.forEachIndexed { index, ring ->
                val inset = index * (strokeWidth + gap)
                val diameterPx = (outer - inset * 2f).coerceAtLeast(strokeWidth * 2f)
                val topLeft = Offset(center.x - diameterPx / 2f, center.y - diameterPx / 2f)
                val arcSize = Size(diameterPx, diameterPx)
                drawArc(
                    color = trackColor,
                    startAngle = -90f,
                    sweepAngle = 360f,
                    useCenter = false,
                    topLeft = topLeft,
                    size = arcSize,
                    style = Stroke(width = strokeWidth, cap = StrokeCap.Round),
                )
                val remaining =
                    (100.0 - ring.usedPercent.coerceIn(0.0, 100.0)).coerceAtLeast(0.0)
                val sweep = (remaining / 100.0 * 360.0).toFloat()
                if (sweep > 0f) {
                    drawArc(
                        color = colors[index],
                        startAngle = -90f,
                        sweepAngle = sweep,
                        useCenter = false,
                        topLeft = topLeft,
                        size = arcSize,
                        style = Stroke(width = strokeWidth, cap = StrokeCap.Round),
                    )
                }
            }
        }
        Column(
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(3.dp),
            modifier = Modifier.padding(top = diameter * 0.22f),
        ) {
            rings.forEachIndexed { index, ring ->
                val remaining =
                    (100.0 - ring.usedPercent.coerceIn(0.0, 100.0))
                        .coerceAtLeast(0.0)
                        .roundToInt()
                val label =
                    if (index == 0 && !tokenGlance.isNullOrBlank()) {
                        "$remaining% · $tokenGlance"
                    } else {
                        "$remaining%"
                    }
                SunkStrip(
                    text = label,
                    accent = colors[index],
                    wellColor = wellColor,
                )
            }
        }
    }
}

@Composable
private fun SunkStrip(
    text: String,
    accent: Color,
    wellColor: Color,
) {
    Row(
        verticalAlignment = Alignment.CenterVertically,
        modifier = Modifier
            .widthIn(min = 56.dp, max = 108.dp)
            .background(wellColor, RoundedCornerShape(5.dp))
            .padding(horizontal = 5.dp, vertical = 3.dp),
    ) {
        Box(
            modifier = Modifier
                .padding(end = 5.dp)
                .width(2.5.dp)
                .height(12.dp)
                .background(accent, RoundedCornerShape(1.dp)),
        )
        Text(
            text,
            style = MaterialTheme.typography.labelMedium,
            color = MaterialTheme.colorScheme.onBackground,
            textAlign = TextAlign.Center,
            modifier = Modifier.weight(1f, fill = false),
        )
    }
}

@Composable
private fun ringFamilyColor(ringId: String, status: PulseStatus): Color {
    val family = Color(RingFamily.colorArgb(ringId))
    // Keep family stroke on warn/stale; only hard failures leave the family palette.
    return when (status) {
        PulseStatus.ERROR,
        PulseStatus.AUTH_REQUIRED,
        -> MaterialTheme.colorScheme.error
        PulseStatus.UNKNOWN -> MaterialTheme.colorScheme.onSurfaceVariant
        else -> family
    }
}
