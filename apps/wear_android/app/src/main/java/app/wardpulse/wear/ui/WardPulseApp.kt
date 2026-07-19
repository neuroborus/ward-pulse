package app.wardpulse.wear.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import androidx.wear.compose.foundation.lazy.TransformingLazyColumn
import androidx.wear.compose.foundation.lazy.rememberTransformingLazyColumnState
import androidx.wear.compose.material3.AppScaffold
import androidx.wear.compose.material3.Button
import androidx.wear.compose.material3.Card
import androidx.wear.compose.material3.ListHeader
import androidx.wear.compose.material3.MaterialTheme
import androidx.wear.compose.material3.ScreenScaffold
import androidx.wear.compose.material3.SurfaceTransformation
import androidx.wear.compose.material3.Text
import androidx.wear.compose.material3.lazy.rememberTransformationSpec
import androidx.wear.compose.material3.lazy.transformedHeight
import androidx.wear.compose.navigation.SwipeDismissableNavHost
import androidx.wear.compose.navigation.composable
import androidx.wear.compose.navigation.rememberSwipeDismissableNavController
import androidx.wear.compose.ui.tooling.preview.WearPreviewDevices
import androidx.wear.compose.ui.tooling.preview.WearPreviewSquare
import app.wardpulse.wear.model.MockWatchDashboardSummary
import app.wardpulse.wear.model.Money
import app.wardpulse.wear.model.PulseStatus
import app.wardpulse.wear.model.WatchDashboardSummary
import app.wardpulse.wear.ui.theme.WardPulseSuccess
import app.wardpulse.wear.ui.theme.WardPulseTheme
import java.util.Locale

private const val HOME_ROUTE = "home"

private enum class Screen(val route: String, val label: String) {
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
fun WardPulseApp(summary: WatchDashboardSummary) {
    AppScaffold {
        val navController = rememberSwipeDismissableNavController()
        SwipeDismissableNavHost(
            navController = navController,
            startDestination = HOME_ROUTE,
        ) {
            composable(HOME_ROUTE) {
                HomeScreen(summary) { navController.navigate(it.route) }
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

private fun WatchDashboardSummary.rowsFor(screen: Screen): List<SummaryRow> = when (screen) {
    Screen.TODAY -> listOf(
        SummaryRow("${today.spent.labelOrUnknown()} / ${today.limit.labelOrUnknown()}", "Budget"),
        SummaryRow(today.usedPercent.usedLabel(), "${today.remaining.labelOrUnknown()} left"),
        SummaryRow(overallStatus.label, "Overall status", overallStatus),
    )
    Screen.WEEK -> listOf(
        SummaryRow("${week.spent.labelOrUnknown()} / ${week.limit.labelOrUnknown()}", "Budget"),
        SummaryRow(week.usedPercent.usedLabel(), "${week.remaining.labelOrUnknown()} left"),
        SummaryRow(
            week.projectedTotal?.label ?: "Unavailable",
            "Projected total",
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
        SummaryRow(lastSyncLabel, "Saved locally"),
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

@Composable
private fun HomeScreen(summary: WatchDashboardSummary, onOpen: (Screen) -> Unit) {
    val state = rememberTransformingLazyColumnState()
    val transformationSpec = rememberTransformationSpec()

    ScreenScaffold(scrollState = state) { contentPadding ->
        TransformingLazyColumn(
            state = state,
            contentPadding = contentPadding,
            verticalArrangement = Arrangement.spacedBy(4.dp),
        ) {
            item {
                ListHeader { Text("WardPulse") }
            }
            item {
                val status = if (summary.isStale) PulseStatus.WARNING else summary.overallStatus
                Card(
                    modifier = Modifier
                        .fillMaxWidth()
                        .transformedHeight(this, transformationSpec),
                    transformation = SurfaceTransformation(transformationSpec),
                ) {
                    Text(
                        if (summary.isStale) "Stale data" else summary.overallStatus.label,
                        color = statusColor(status),
                    )
                    Text(
                        "Today ${summary.today.usedPercent.percentLabel()} · " +
                            "Week ${summary.week.usedPercent.percentLabel()}",
                    )
                }
            }
            items(Screen.entries.size) { index ->
                val destination = Screen.entries[index]
                Button(
                    onClick = { onOpen(destination) },
                    modifier = Modifier
                        .fillMaxWidth()
                        .transformedHeight(this, transformationSpec),
                    transformation = SurfaceTransformation(transformationSpec),
                ) {
                    Text(destination.label)
                }
            }
        }
    }
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
                    Text(row.detail)
                }
            }
        }
    }
}

@Composable
private fun statusColor(status: PulseStatus): Color = when (status) {
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

private fun Money?.labelOrUnknown(): String = this?.label ?: "Unknown"

private fun Double?.percentLabel(): String = this?.let { value ->
    val formatted = if (value % 1.0 == 0.0) {
        value.toLong().toString()
    } else {
        String.format(Locale.US, "%.1f", value)
    }
    "$formatted%"
} ?: "Unknown"

private fun Double?.usedLabel(): String = "${percentLabel()} used"

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
        WardPulseApp(MockWatchDashboardSummary.value)
    }
}
