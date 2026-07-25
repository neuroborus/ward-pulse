package app.wardpulse.wear.ui

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.size
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.wear.compose.material3.MaterialTheme
import androidx.wear.compose.material3.Text
import app.wardpulse.wear.model.PulseStatus
import app.wardpulse.wear.model.RingSummary
import app.wardpulse.wear.ui.theme.WardPulseSuccess
import java.util.Locale
import kotlin.math.min

/**
 * Concentric percent rings matching `apps/wear_android/design/rings.fig`.
 * Outer ring is selection slot 0; unavailable metrics are omitted by the payload.
 */
@Composable
internal fun UsageRings(
    rings: List<RingSummary>,
    modifier: Modifier = Modifier,
    diameter: Dp = 152.dp,
) {
    if (rings.isEmpty()) {
        return
    }

    val trackColor = MaterialTheme.colorScheme.outlineVariant
    val colors = rings.map { ringStatusColor(it.status) }
    val density = LocalDensity.current
    val strokeWidth = with(density) { 8.dp.toPx() }
    val gap = with(density) { 6.dp.toPx() }

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
                val sweep = (ring.usedPercent.coerceIn(0.0, 100.0) / 100.0 * 360.0).toFloat()
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
        Column(horizontalAlignment = Alignment.CenterHorizontally) {
            if (rings.size == 1) {
                Text(
                    rings.single().usedPercent.compactPercentLabel(),
                    style = MaterialTheme.typography.titleLarge,
                    color = colors.single(),
                )
                Text(
                    rings.single().label,
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            } else {
                Text(
                    "${rings.size}",
                    style = MaterialTheme.typography.titleLarge,
                    color = MaterialTheme.colorScheme.onBackground,
                )
                Text(
                    "rings",
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
    }
}

@Composable
private fun ringStatusColor(status: PulseStatus): Color = when (status) {
    PulseStatus.OK -> WardPulseSuccess
    PulseStatus.WARNING,
    PulseStatus.RATE_LIMITED,
    PulseStatus.STALE,
    -> MaterialTheme.colorScheme.tertiary
    PulseStatus.ERROR,
    PulseStatus.AUTH_REQUIRED,
    -> MaterialTheme.colorScheme.error
    PulseStatus.UNKNOWN -> MaterialTheme.colorScheme.onSurfaceVariant
}

private fun Double.compactPercentLabel(): String {
    val formatted = if (this % 1.0 == 0.0) {
        toLong().toString()
    } else {
        String.format(Locale.US, "%.0f", this)
    }
    return "$formatted%"
}
