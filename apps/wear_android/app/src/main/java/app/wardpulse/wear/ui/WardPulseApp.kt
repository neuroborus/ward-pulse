package app.wardpulse.wear.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.pager.VerticalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
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
import java.time.Instant

private const val HOME_ROUTE = "home"
private const val ALERTS_ROUTE = "alerts"

private enum class HomePage {
    Glance,
    PlanWindows,
}

private data class SummaryRow(
    val title: String,
    val detail: String,
    val status: PulseStatus? = null,
)

@Composable
fun WardPulseApp(summary: WatchDashboardSummary?) {
    // Straight clock: default curved TimeText warps on round API 34+ shells.
    // Sized to Glance review art (muted, not a face-style hero).
    AppScaffold(timeText = { StraightAppTimeText() }) {
        if (summary == null) {
            EmptyDashboardScreen()
            return@AppScaffold
        }
        val navController = rememberSwipeDismissableNavController()
        SwipeDismissableNavHost(
            navController = navController,
            startDestination = HOME_ROUTE,
        ) {
            composable(HOME_ROUTE) {
                HomeScreen(
                    summary = summary,
                    onOpenAlerts = { navController.navigate(ALERTS_ROUTE) },
                )
            }
            composable(ALERTS_ROUTE) {
                SummaryScreen(title = "Alerts", rows = summary.alertRows())
            }
        }
    }
}

@Composable
private fun EmptyDashboardScreen() {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(horizontal = 18.dp, vertical = 28.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center,
    ) {
        Text("WardPulse", style = MaterialTheme.typography.titleMedium)
        Text(
            "Sync from phone",
            modifier = Modifier.padding(top = 8.dp),
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            textAlign = TextAlign.Center,
        )
        Text(
            "No dashboard data yet",
            style = MaterialTheme.typography.labelSmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            textAlign = TextAlign.Center,
        )
    }
}

/**
 * When each window comes back, exhausted ones first
 * (`apps/wear_android/README.md`, Plan windows).
 */
private fun WatchDashboardSummary.planRows(): List<SummaryRow> =
    planWindowRows(this, Instant.now())
        .map { SummaryRow(it.title, it.detail, it.status) }
        .ifEmpty { listOf(SummaryRow("No plan windows", "Sync from the phone")) }

private fun WatchDashboardSummary.alertRows(): List<SummaryRow> =
    alerts.map {
        SummaryRow(
            it.severity.replaceFirstChar(Char::uppercase),
            it.message,
            it.severity.toStatus(),
        )
    }.ifEmpty { listOf(SummaryRow("No active alerts", "All providers look normal")) }

@Composable
private fun HomeScreen(
    summary: WatchDashboardSummary,
    onOpenAlerts: () -> Unit,
) {
    val pages = HomePage.entries
    val pagerState = rememberPagerState(pageCount = { pages.size })

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
private fun SummaryScreen(title: String, rows: List<SummaryRow>) {
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
        WardPulseApp(PreviewWatchDashboardSummary.glanceLegend)
    }
}
