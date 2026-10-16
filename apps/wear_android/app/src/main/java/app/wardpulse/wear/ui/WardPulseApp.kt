package app.wardpulse.wear.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.pager.PagerState
import androidx.compose.foundation.pager.VerticalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.wear.compose.foundation.lazy.TransformingLazyColumn
import androidx.wear.compose.foundation.lazy.rememberTransformingLazyColumnState
import androidx.wear.compose.material3.AppScaffold
import androidx.wear.compose.material3.Card
import androidx.wear.compose.material3.ListHeader
import androidx.wear.compose.material3.MaterialTheme
import androidx.wear.compose.material3.ScreenScaffold
import androidx.wear.compose.material3.SurfaceTransformation
import androidx.wear.compose.material3.Text
import androidx.wear.compose.material3.TimeTextDefaults
import androidx.wear.compose.material3.lazy.rememberTransformationSpec
import androidx.wear.compose.material3.lazy.transformedHeight
import androidx.wear.compose.navigation.SwipeDismissableNavHost
import androidx.wear.compose.navigation.composable
import androidx.wear.compose.navigation.rememberSwipeDismissableNavController
import androidx.wear.compose.ui.tooling.preview.WearPreviewDevices
import androidx.wear.compose.ui.tooling.preview.WearPreviewSquare
import app.wardpulse.wear.model.PreviewWatchDashboardSummary
import app.wardpulse.wear.model.PulseStatus
import app.wardpulse.wear.model.WatchDashboardSummary
import app.wardpulse.wear.ui.theme.WardPulseTheme
import app.wardpulse.wear.watchface.WatchFaceScreen
import app.wardpulse.wear.watchface.WatchFaceState
import java.time.Instant

private const val HOME_ROUTE = "home"
private const val ALERTS_ROUTE = "alerts"
private const val WATCH_FACE_ROUTE = "watch-face"

private enum class HomePage {
    Glance,
    PlanWindows,
}

internal data class SummaryRow(
    val title: String,
    val detail: String,
    val status: PulseStatus? = null,
)

@Composable
fun WardPulseApp(
    summary: WatchDashboardSummary?,
    watchFaceState: WatchFaceState,
    onCheckWatchFace: () -> Unit,
    onInstallWatchFace: () -> Unit,
    onUpdateWatchFace: () -> Unit,
    onUseWatchFace: () -> Unit,
) {
    val navController = rememberSwipeDismissableNavController()
    val pagerState = rememberPagerState(pageCount = { HomePage.entries.size })
    // Navigation retains destination content, so read current inputs inside each composition.
    val currentSummary by rememberUpdatedState(summary)
    val currentWatchFaceState by rememberUpdatedState(watchFaceState)
    val currentOnCheck by rememberUpdatedState(onCheckWatchFace)
    val currentOnInstall by rememberUpdatedState(onInstallWatchFace)
    val currentOnUpdate by rememberUpdatedState(onUpdateWatchFace)
    val currentOnUse by rememberUpdatedState(onUseWatchFace)
    // Straight clock: default curved TimeText warps on round API 34+ shells.
    // Sized to Glance review art (muted, not a face-style hero).
    AppScaffold(timeText = { StraightAppTimeText() }) {
        SwipeDismissableNavHost(
            navController = navController,
            startDestination = HOME_ROUTE,
        ) {
            composable(HOME_ROUTE) {
                val latestSummary = currentSummary
                if (latestSummary == null) {
                    EmptyDashboardScreen(onOpenWatchFace = { navController.navigate(WATCH_FACE_ROUTE) })
                } else {
                    HomeScreen(
                        summary = latestSummary,
                        pagerState = pagerState,
                        onOpenAlerts = { navController.navigate(ALERTS_ROUTE) },
                        onOpenWatchFace = { navController.navigate(WATCH_FACE_ROUTE) },
                    )
                }
            }
            composable(ALERTS_ROUTE) {
                val latestSummary = currentSummary
                if (latestSummary == null) {
                    EmptyDashboardScreen(onOpenWatchFace = { navController.navigate(WATCH_FACE_ROUTE) })
                } else {
                    SummaryScreen(title = "Alerts", rows = latestSummary.alertRows())
                }
            }
            composable(WATCH_FACE_ROUTE) {
                WatchFaceScreen(
                    state = currentWatchFaceState,
                    onCheck = currentOnCheck,
                    onInstall = currentOnInstall,
                    onUpdate = currentOnUpdate,
                    onUse = currentOnUse,
                )
            }
        }
    }
}

@Composable
private fun EmptyDashboardScreen(onOpenWatchFace: () -> Unit) {
    SummaryScreen(
        title = "WardPulse",
        rows = listOf(SummaryRow("Sync from phone", "No dashboard data yet")),
        onOpenWatchFace = onOpenWatchFace,
    )
}

/**
 * When each window comes back, exhausted ones first
 * (`apps/wear_android/README.md`, Plan windows).
 */
private fun WatchDashboardSummary.planRows(): List<SummaryRow> =
    planWindowRows(this, Instant.now())
        .map { SummaryRow(it.title, it.detail, it.status) }
        .ifEmpty { listOf(SummaryRow("No plan windows", "Sync from the phone")) }

internal fun WatchDashboardSummary.alertRows(): List<SummaryRow> =
    alerts.map {
        SummaryRow(
            it.severity.replaceFirstChar(Char::uppercase),
            it.message,
            it.severity.toStatus(),
        )
    }.ifEmpty { listOf(SummaryRow("No active alerts", "No alerts in the latest summary")) }

@Composable
private fun HomeScreen(
    summary: WatchDashboardSummary,
    pagerState: PagerState,
    onOpenAlerts: () -> Unit,
    onOpenWatchFace: () -> Unit,
) {
    val pages = HomePage.entries

    VerticalPager(
        state = pagerState,
        modifier = Modifier.fillMaxSize(),
        beyondViewportPageCount = 0,
    ) { page ->
        when (pages[page]) {
            HomePage.Glance -> GlanceLegendPage(
                summary = summary,
                onOpenAlerts = onOpenAlerts,
            )
            HomePage.PlanWindows -> SummaryScreen(
                title = "Plan windows",
                rows = summary.planRows(),
                onOpenWatchFace = onOpenWatchFace,
            )
        }
    }
}

@Composable
private fun StraightAppTimeText() {
    val timeSource = TimeTextDefaults.rememberTimeSource(TimeTextDefaults.timeFormat())
    Text(
        text = timeSource.currentTime(),
        modifier = Modifier
            .fillMaxWidth()
            // Review art: ~y=32 top of glyphs on a 450px canvas → ~14dp on 192dp shells.
            .padding(top = 14.dp),
        style = MaterialTheme.typography.labelSmall.copy(
            fontWeight = FontWeight.Bold,
            fontSize = 7.sp,
            lineHeight = 9.sp,
        ),
        color = Color(0xFF8A968F),
        textAlign = TextAlign.Center,
        maxLines = 1,
    )
}

@Composable
private fun SummaryScreen(
    title: String,
    rows: List<SummaryRow>,
    onOpenWatchFace: (() -> Unit)? = null,
) {
    val state = rememberTransformingLazyColumnState()
    val transformationSpec = rememberTransformationSpec()

    ScreenScaffold(scrollState = state) { contentPadding ->
        TransformingLazyColumn(
            state = state,
            contentPadding = contentPadding,
            verticalArrangement = Arrangement.spacedBy(4.dp),
        ) {
            item {
                ListHeader { Text(title) }
            }
            items(rows.size) { index ->
                val row = rows[index]
                Card(
                    modifier = Modifier
                        .fillMaxWidth()
                        .transformedHeight(this, transformationSpec),
                    transformation = SurfaceTransformation(transformationSpec),
                ) {
                    Text(
                        row.title,
                        color = row.status?.let { statusColor(it) } ?: Color.Unspecified,
                    )
                    Text(
                        row.detail,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
            if (onOpenWatchFace != null) {
                item {
                    Card(
                        onClick = onOpenWatchFace,
                        modifier = Modifier
                            .fillMaxWidth()
                            .transformedHeight(this, transformationSpec),
                        transformation = SurfaceTransformation(transformationSpec),
                    ) {
                        Text("Watch face")
                    }
                }
            }
        }
    }
}

@Composable
private fun statusColor(status: PulseStatus): Color = when (status) {
    PulseStatus.OK -> MaterialTheme.colorScheme.primary
    PulseStatus.WARNING,
    PulseStatus.RATE_LIMITED,
    PulseStatus.STALE,
    -> MaterialTheme.colorScheme.tertiary
    PulseStatus.ERROR,
    PulseStatus.AUTH_REQUIRED,
    -> MaterialTheme.colorScheme.error
    PulseStatus.UNKNOWN -> MaterialTheme.colorScheme.onSurfaceVariant
}

private fun String.toStatus(): PulseStatus = when (this) {
    "error" -> PulseStatus.ERROR
    "warning" -> PulseStatus.WARNING
    else -> PulseStatus.UNKNOWN
}

@WearPreviewDevices
@WearPreviewSquare
@Composable
private fun WardPulsePreview() {
    WardPulseTheme {
        WardPulseApp(
            summary = PreviewWatchDashboardSummary.glanceLegend,
            watchFaceState = WatchFaceState(),
            onCheckWatchFace = {},
            onInstallWatchFace = {},
            onUpdateWatchFace = {},
            onUseWatchFace = {},
        )
    }
}
