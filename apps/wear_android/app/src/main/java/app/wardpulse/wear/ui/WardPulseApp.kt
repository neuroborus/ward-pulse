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
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.wear.compose.foundation.lazy.TransformingLazyColumn
import androidx.wear.compose.foundation.lazy.rememberTransformingLazyColumnState
import androidx.wear.compose.material3.AppScaffold
import androidx.wear.compose.material3.Button
import androidx.wear.compose.material3.ButtonDefaults
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
import app.wardpulse.wear.model.AllowanceSummary
import app.wardpulse.wear.model.Money
import app.wardpulse.wear.model.PreviewWatchDashboardSummary
import app.wardpulse.wear.model.PulseStatus
import app.wardpulse.wear.model.RingSummary
import app.wardpulse.wear.model.WatchDashboardSummary
import app.wardpulse.wear.ui.theme.WardPulseTheme

private const val HOME_ROUTE = "home"

private enum class HomePage {
    Glance,
    Menu,
}

private enum class Screen(val route: String, val label: String) {
    USAGE("usage", "Usage"),
    TODAY("today", "Today"),
    WEEK("week", "Week"),
    PROVIDERS("providers", "Providers"),
    ALERTS("alerts", "Alerts"),
    LAST_SYNC("last-sync", "Last sync"),
}

private data class SummaryRow(
    val title: String,
    val detail: String,
    val status: PulseStatus? = null,
)

@Composable
fun WardPulseApp(summary: WatchDashboardSummary?) {
    // Straight clock chrome: default curved TimeText + glyph warping looks mangled
    // on round API 34+ emulators/devices with the Material3 arc renderer.
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
                    onOpen = { navController.navigate(it.route) },
                    onOpenRing = { index -> navController.navigate("ring/$index") },
                )
            }
            composable("ring/{index}") { entry ->
                val index = entry.arguments?.getString("index")?.toIntOrNull()
                val ring = index?.let { summary.activeRings.getOrNull(it) }
                if (ring == null) {
                    SummaryScreen(
                        title = "Ring",
                        rows = listOf(SummaryRow("Unavailable", "Choose rings on the phone")),
                    )
                } else {
                    SummaryScreen(
                        title = ring.label,
                        rows = listOf(
                            SummaryRow(formatPercentUsedLabel(ring.usedPercent), "Used", ring.status),
                            SummaryRow(ring.status.label, "Status", ring.status),
                        ),
                    )
                }
            }
            Screen.entries.forEach { screen ->
                composable(screen.route) {
                    SummaryScreen(
                        title = screen.label,
                        rows = summary.rowsFor(screen),
                    )
                }
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

private fun WatchDashboardSummary.rowsFor(screen: Screen): List<SummaryRow> = when (screen) {
    Screen.USAGE -> allowances.map { allowance ->
        SummaryRow(
            allowance.label,
            allowance.valueLabel,
            allowance.status,
        )
    }.ifEmpty { listOf(SummaryRow("No usage data", "Sync from the phone")) }
    Screen.TODAY -> listOf(
        SummaryRow("${today.spent.labelOrUnknown()} / ${today.limit.labelOrUnknown()}", "Budget"),
        SummaryRow(formatPercentUsedLabel(today.usedPercent), "${today.remaining.labelOrUnknown()} left"),
        SummaryRow(overallStatus.label, "Overall status", overallStatus),
    )
    Screen.WEEK -> listOf(
        SummaryRow("${week.spent.labelOrUnknown()} / ${week.limit.labelOrUnknown()}", "Budget"),
        SummaryRow(formatPercentUsedLabel(week.usedPercent), "${week.remaining.labelOrUnknown()} left"),
        SummaryRow(
            title = week.projectedTotal?.label ?: "Unavailable",
            detail = "Projected total",
        ),
    )
    Screen.PROVIDERS -> providers.map {
        SummaryRow(it.providerLabel, it.todaySpent?.label ?: "Unavailable", it.status)
    }
    Screen.ALERTS -> alerts.map {
        SummaryRow(
            it.severity.replaceFirstChar(Char::uppercase),
            it.message,
            it.severity.toStatus(),
        )
    }
        .ifEmpty { listOf(SummaryRow("No active alerts", "All providers look normal")) }
    Screen.LAST_SYNC -> listOf(
        SummaryRow(lastSyncLabel, "Local time"),
        SummaryRow(lastSyncUtcLabel, "UTC"),
        SummaryRow(
            title = if (isStale) "Stale data" else "Up to date",
            detail = if (isStale) {
                "Showing the last saved summary"
            } else {
                "Latest summary is available"
            },
            status = if (isStale) PulseStatus.WARNING else PulseStatus.OK,
        ),
    )
}

/** Exhausted layers are omitted on the surface (design: omit usedPercent >= 100). */
private val WatchDashboardSummary.activeRings: List<RingSummary>
    get() = rings.filter { it.usedPercent < 100.0 }

@Composable
private fun HomeScreen(
    summary: WatchDashboardSummary,
    onOpen: (Screen) -> Unit,
    onOpenRing: (Int) -> Unit,
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
                onOpenAlerts = { onOpen(Screen.ALERTS) },
            )
            HomePage.Menu -> MenuPage(
                summary = summary,
                onOpen = onOpen,
                onOpenRing = onOpenRing,
            )
        }
    }
}

@Composable
private fun MenuPage(
    summary: WatchDashboardSummary,
    onOpen: (Screen) -> Unit,
    onOpenRing: (Int) -> Unit,
) {
    val state = rememberTransformingLazyColumnState()
    val transformationSpec = rememberTransformationSpec()
    val rings = summary.activeRings
    val menuColors = ButtonDefaults.buttonColors(
        containerColor = MaterialTheme.colorScheme.surfaceContainerHigh,
        contentColor = MaterialTheme.colorScheme.onSurface,
    )

    ScreenScaffold(scrollState = state) { contentPadding ->
        TransformingLazyColumn(
            state = state,
            contentPadding = contentPadding,
            verticalArrangement = Arrangement.spacedBy(6.dp),
            modifier = Modifier.padding(horizontal = 18.dp),
        ) {
            item {
                ListHeader {
                    Text("Menu", style = MaterialTheme.typography.titleSmall)
                }
            }
            items(rings.size) { index ->
                val ring = rings[index]
                Button(
                    onClick = { onOpenRing(index) },
                    modifier = Modifier
                        .fillMaxWidth()
                        .transformedHeight(this, transformationSpec),
                    colors = menuColors,
                    transformation = SurfaceTransformation(transformationSpec),
                ) {
                    Column(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalAlignment = Alignment.CenterHorizontally,
                    ) {
                        Text(
                            ring.label,
                            style = MaterialTheme.typography.labelLarge,
                            textAlign = TextAlign.Center,
                        )
                        Text(
                            formatPercentRemainingLabel(ring.usedPercent),
                            style = MaterialTheme.typography.labelMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                            textAlign = TextAlign.Center,
                        )
                    }
                }
            }
            items(Screen.entries.size) { index ->
                val destination = Screen.entries[index]
                Button(
                    onClick = { onOpen(destination) },
                    modifier = Modifier
                        .fillMaxWidth()
                        .transformedHeight(this, transformationSpec),
                    colors = menuColors,
                    transformation = SurfaceTransformation(transformationSpec),
                ) {
                    Text(
                        destination.label,
                        modifier = Modifier.fillMaxWidth(),
                        style = MaterialTheme.typography.labelLarge,
                        textAlign = TextAlign.Center,
                    )
                }
            }
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
            .padding(top = 6.dp),
        style = MaterialTheme.typography.labelMedium,
        color = MaterialTheme.colorScheme.onBackground,
        textAlign = TextAlign.Center,
    )
}

private val AllowanceSummary.valueLabel: String
    get() = when {
        unlimited -> "Unlimited"
        usedPercent != null -> formatPercentUsedLabel(usedPercent)
        remaining != null -> remaining.label
        else -> "Unavailable"
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

private fun Money?.labelOrUnknown(): String = this?.label ?: "Unknown"

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
