package app.wardpulse.wear.ui

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.gestures.animateScrollBy
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.calculateEndPadding
import androidx.compose.foundation.layout.calculateStartPadding
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.pager.PagerState
import androidx.compose.foundation.pager.VerticalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.ExperimentalComposeUiApi
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.SemanticsPropertyKey
import androidx.compose.ui.semantics.scrollBy
import androidx.compose.ui.semantics.scrollByOffset
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.testTagsAsResourceId
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.compose.currentStateAsState
import androidx.wear.compose.foundation.BasicSwipeToDismissBox
import androidx.wear.compose.foundation.ScrollInfoProvider
import androidx.wear.compose.foundation.hierarchicalFocusGroup
import androidx.wear.compose.foundation.lazy.TransformingLazyColumn
import androidx.wear.compose.foundation.lazy.rememberTransformingLazyColumnState
import androidx.wear.compose.material3.AppScaffold
import androidx.wear.compose.material3.Button
import androidx.wear.compose.material3.ButtonDefaults
import androidx.wear.compose.material3.Card
import androidx.wear.compose.material3.CompactButton
import androidx.wear.compose.material3.CompactButtonDefaults
import androidx.wear.compose.material3.ListHeader
import androidx.wear.compose.material3.MaterialTheme
import androidx.wear.compose.material3.ScreenScaffold
import androidx.wear.compose.material3.ScrollIndicator
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
import kotlin.math.ceil
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch

private const val HOME_ROUTE = "home"
private const val ALERTS_ROUTE = "alerts"
private const val WATCH_FACE_ROUTE = "watch-face"

private enum class HomePage {
    Glance,
    PlanWindows,
}

// Native observers need destination completion as well as visible Pager content.
internal val HomePagerStateKey = SemanticsPropertyKey<HomePagerState>("HomePagerState")

internal data class HomePagerState(
    val lifecycle: Lifecycle.State,
    val currentPage: Int,
    val settledPage: Int,
    val targetPage: Int,
    val offsetFraction: Float,
    val scrolling: Boolean,
)

// NoSummary observers read native layout and the existing asynchronous request;
// observation never initiates or cancels scrolling.
internal val SummaryScrollStateKey = SemanticsPropertyKey<() -> SummaryScrollState>("SummaryScrollState")

internal data class SummaryScrollState(
    val scrolling: Boolean,
    val canScrollForward: Boolean,
    val canScrollBackward: Boolean,
    val items: List<SummaryScrollItem>,
    val totalItems: Int,
    val viewportHeight: Int,
    val beforePadding: Int,
    val afterPadding: Int,
    val request: SummaryScrollRequest?,
)

internal data class SummaryScrollItem(val index: Int, val offset: Int, val transformedHeight: Int)

internal data class SummaryScrollRequest(
    val invocation: Any,
    val amount: Float,
    val consumed: Float?,
    val completed: Boolean,
    val cancelled: Boolean,
)

private class SummaryScrollRequestState(val amount: Float) {
    var job: Job? = null
    var consumed: Float? = null
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
    faceEntryRequest: Long? = null,
    onFaceEntryConsumed: (Long) -> Unit = {},
    onDismissHome: () -> Unit = {},
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
    LaunchedEffect(faceEntryRequest) {
        faceEntryRequest?.let { request ->
            navController.popBackStack(HOME_ROUTE, inclusive = false)
            // Also works before a summary (and therefore a Pager layout) exists.
            pagerState.requestScrollToPage(HomePage.Glance.ordinal)
            onFaceEntryConsumed(request)
        }
    }
    // Each clock belongs to its destination so dismissal transforms and clips it
    // with that page, including a cancelled swipe or a predictive-back preview.
    SwipeDismissableNavHost(
        navController = navController,
        startDestination = HOME_ROUTE,
        modifier = Modifier.fillMaxSize(),
    ) {
        composable(HOME_ROUTE) {
            val latestSummary = currentSummary
            var clockHeight by remember { mutableIntStateOf(0) }
            val showClock = latestSummary == null ||
                (!pagerState.isScrollInProgress && pagerState.settledPage == HomePage.PlanWindows.ordinal)
            HomeDismissal(pagerState, onDismissHome) {
                AppScaffold(timeText = {
                    if (showClock) StraightAppTimeText(Modifier.onSizeChanged { clockHeight = it.height })
                }) {
                    if (latestSummary == null) {
                        EmptyDashboardScreen(clockHeight, onOpenWatchFace = { navController.navigate(WATCH_FACE_ROUTE) })
                    } else {
                        HomeScreen(
                            summary = latestSummary,
                            pagerState = pagerState,
                            onOpenAlerts = { navController.navigate(ALERTS_ROUTE) },
                            onOpenWatchFace = { navController.navigate(WATCH_FACE_ROUTE) },
                        )
                    }
                }
            }
        }
        composable(ALERTS_ROUTE) {
            val latestSummary = currentSummary
            var clockHeight by remember { mutableIntStateOf(0) }
            AppScaffold(timeText = { StraightAppTimeText(Modifier.onSizeChanged { clockHeight = it.height }) }) {
                if (latestSummary == null) {
                    EmptyDashboardScreen(clockHeight, onOpenWatchFace = { navController.navigate(WATCH_FACE_ROUTE) })
                } else {
                    SummaryScreen(title = "Alerts", rows = latestSummary.alertRows())
                }
            }
        }
        composable(WATCH_FACE_ROUTE) {
            AppScaffold(timeText = { StraightAppTimeText() }) {
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
private fun HomeDismissal(pagerState: PagerState, onDismiss: () -> Unit, content: @Composable () -> Unit) {
    // Home can remain composed behind a nested destination or its back preview.
    val lifecycle by LocalLifecycleOwner.current.lifecycle.currentStateAsState()
    val resumed = lifecycle == Lifecycle.State.RESUMED
    BackHandler(enabled = resumed, onBack = onDismiss)
    BasicSwipeToDismissBox(
        onDismissed = onDismiss,
        modifier = Modifier.fillMaxSize(),
        userSwipeEnabled = resumed && !pagerState.isScrollInProgress,
    ) { isBackground ->
        if (!isBackground) content()
    }
}

@OptIn(ExperimentalComposeUiApi::class)
@Composable
private fun EmptyDashboardScreen(clockHeight: Int, onOpenWatchFace: () -> Unit) {
    SummaryScreen(
        title = "WardPulse",
        rows = listOf(SummaryRow("Sync from phone", "No dashboard data yet")),
        modifier = Modifier
            .semantics { testTagsAsResourceId = true }
            .testTag("empty-dashboard-list"),
        onOpenWatchFace = onOpenWatchFace,
        compactWatchFaceAction = true,
        clockInset = with(LocalDensity.current) { clockHeight.toDp() } + 4.dp,
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

@OptIn(ExperimentalComposeUiApi::class)
@Composable
private fun HomeScreen(
    summary: WatchDashboardSummary,
    pagerState: PagerState,
    onOpenAlerts: () -> Unit,
    onOpenWatchFace: () -> Unit,
) {
    val pages = HomePage.entries
    val lifecycle by LocalLifecycleOwner.current.lifecycle.currentStateAsState()

    VerticalPager(
        state = pagerState,
        modifier = Modifier
            .fillMaxSize()
            .semantics {
                testTagsAsResourceId = true
                this[HomePagerStateKey] = HomePagerState(
                    lifecycle, pagerState.currentPage, pagerState.settledPage,
                    pagerState.targetPage, pagerState.currentPageOffsetFraction, pagerState.isScrollInProgress,
                )
            }
            .testTag("home-pager"),
        beyondViewportPageCount = 0,
    ) { page ->
        // Keep source focus through the animation: changing the active hierarchy can
        // trigger focus/bring-into-view scrolling that cancels the Pager mutation.
        // Navigation owns route focus; transfer page ownership only on settlement.
        val pageModifier = Modifier.hierarchicalFocusGroup(
            active = pagerState.settledPage == page,
        )
        when (pages[page]) {
            HomePage.Glance -> GlanceLegendPage(
                summary = summary,
                onOpenAlerts = onOpenAlerts,
                modifier = pageModifier,
            )
            HomePage.PlanWindows -> SummaryScreen(
                title = "Plan windows",
                rows = summary.planRows(),
                modifier = pageModifier.testTag("plan-windows-list"),
                onOpenWatchFace = onOpenWatchFace,
            )
        }
    }
}

@OptIn(ExperimentalComposeUiApi::class)
@Composable
private fun StraightAppTimeText(modifier: Modifier = Modifier) {
    val timeSource = TimeTextDefaults.rememberTimeSource(TimeTextDefaults.timeFormat())
    Text(
        text = timeSource.currentTime(),
        modifier = modifier
            .fillMaxWidth()
            .semantics { testTagsAsResourceId = true }
            .testTag("app-clock")
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
    modifier: Modifier = Modifier,
    onOpenWatchFace: (() -> Unit)? = null,
    compactWatchFaceAction: Boolean = false,
    clockInset: Dp = 0.dp,
) {
    val state = rememberTransformingLazyColumnState()
    val scope = rememberCoroutineScope()
    val transformationSpec = rememberTransformationSpec()
    var lastRequest by remember { mutableStateOf<SummaryScrollRequestState?>(null) }
    val scrollInfo = remember(state, compactWatchFaceAction) {
        val native = ScrollInfoProvider(state)
        if (compactWatchFaceAction) {
            // NoSummary reserves separate clock space. Keep native indicator/stage
            // information, but never scroll that persistent clock away.
            object : ScrollInfoProvider by native {
                override val isScrollAwayValid = false
            }
        } else {
            native
        }
    }

    ScreenScaffold(
        scrollInfoProvider = scrollInfo,
        scrollIndicator = { ScrollIndicator(state) },
    ) { contentPadding ->
        // Reserve only the measured clock and the list's ordinary 4dp spacing.
        // Clip outside all item transformations, including departing text/surface paint.
        val listModifier = if (compactWatchFaceAction) {
            Modifier.padding(top = clockInset).clipToBounds().then(modifier)
        } else {
            modifier
        }
        val listPadding = if (compactWatchFaceAction) {
            val direction = LocalLayoutDirection.current
            PaddingValues(
                start = contentPadding.calculateStartPadding(direction),
                top = (contentPadding.calculateTopPadding() - clockInset).coerceAtLeast(0.dp),
                end = contentPadding.calculateEndPadding(direction),
                bottom = contentPadding.calculateBottomPadding(),
            )
        } else {
            contentPadding
        }
        TransformingLazyColumn(
            modifier = listModifier.semantics {
                if (compactWatchFaceAction) {
                    this[SummaryScrollStateKey] = {
                        val layout = state.layoutInfo
                        SummaryScrollState(
                            state.isScrollInProgress, state.canScrollForward, state.canScrollBackward,
                            layout.visibleItems.map { SummaryScrollItem(it.index, it.offset, it.transformedHeight) },
                            layout.totalItemsCount, layout.viewportSize.height,
                            layout.beforeContentPadding, layout.afterContentPadding,
                            lastRequest?.let {
                                SummaryScrollRequest(
                                    it, it.amount, it.consumed,
                                    it.job?.isCompleted == true, it.job?.isCancelled == true,
                                )
                            },
                        )
                    }
                }
                // Accessibility scrolls belong to this list, including their unconsumed
                // distance at a boundary. Touch and rotary keep the normal scrollable path.
                scrollBy { _, y ->
                    if (compactWatchFaceAction) {
                        val request = SummaryScrollRequestState(y)
                        lastRequest = request
                        request.job = scope.launch { request.consumed = state.animateScrollBy(y) }
                    } else {
                        scope.launch { state.animateScrollBy(y) }
                    }
                    true
                }
                scrollByOffset { Offset(0f, state.animateScrollBy(it.y)) }
            },
            state = state,
            contentPadding = listPadding,
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
                    val actionModifier = Modifier
                        .fillMaxWidth()
                        .transformedHeight(this, transformationSpec)
                    val transformation = SurfaceTransformation(transformationSpec)
                    if (compactWatchFaceAction) {
                        CompactWatchFaceAction(
                            onClick = onOpenWatchFace,
                            modifier = actionModifier.testTag("empty-watch-face-action"),
                            transformation = transformation,
                        )
                    } else {
                        Card(
                            onClick = onOpenWatchFace,
                            modifier = actionModifier,
                            transformation = transformation,
                        ) {
                            Text("Watch face")
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun CompactWatchFaceAction(
    onClick: () -> Unit,
    modifier: Modifier,
    transformation: SurfaceTransformation,
) {
    val label = "Watch face"
    val density = LocalDensity.current
    val direction = LocalLayoutDirection.current
    val style = MaterialTheme.typography.labelSmall
    val labelLayout = rememberTextMeasurer().measure(label, style = style, softWrap = false)
    BoxWithConstraints(modifier) {
        val padding = CompactButtonDefaults.ContentPadding
        val tapPadding = CompactButtonDefaults.TapTargetPadding
        val contentWidth = with(density) {
            constraints.maxWidth - padding.calculateLeftPadding(direction).roundToPx() -
                padding.calculateRightPadding(direction).roundToPx() -
                tapPadding.calculateLeftPadding(direction).roundToPx() -
                tapPadding.calculateRightPadding(direction).roundToPx()
        }
        val contentHeight = with(density) {
            CompactButtonDefaults.Height.roundToPx() - tapPadding.calculateTopPadding().roundToPx() -
                tapPadding.calculateBottomPadding().roundToPx() - padding.calculateTopPadding().roundToPx() -
                padding.calculateBottomPadding().roundToPx()
        }
        // Include the full scaled line reservation even when native font metrics trim it.
        val lineHeight = maxOf(
            labelLayout.size.height,
            ceil(with(density) { style.lineHeight.toPx() }).toInt(),
        )
        if (labelLayout.size.width <= contentWidth && lineHeight <= contentHeight) {
            CompactButton(
                onClick = onClick,
                modifier = Modifier.fillMaxWidth(),
                colors = ButtonDefaults.filledTonalButtonColors(),
                transformation = transformation,
                label = { Text(label, maxLines = Int.MAX_VALUE, overflow = TextOverflow.Clip) },
            )
        } else {
            Button(
                onClick = onClick,
                modifier = Modifier.fillMaxWidth(),
                colors = ButtonDefaults.filledTonalButtonColors(),
                transformation = transformation,
            ) {
                Text(label, maxLines = Int.MAX_VALUE, overflow = TextOverflow.Clip)
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
