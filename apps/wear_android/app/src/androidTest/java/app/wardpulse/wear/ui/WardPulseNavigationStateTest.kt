package app.wardpulse.wear.ui

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.os.SystemClock
import android.view.Choreographer
import android.view.KeyEvent
import android.view.accessibility.AccessibilityNodeInfo
import androidx.activity.compose.setContent
import androidx.compose.runtime.Recomposer
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.MotionDurationScale
import androidx.compose.ui.platform.AndroidUiDispatcher
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import app.wardpulse.wear.MainActivity
import app.wardpulse.wear.model.AlertSummary
import app.wardpulse.wear.model.AllowanceSummary
import app.wardpulse.wear.model.PeriodSummary
import app.wardpulse.wear.model.PulseStatus
import app.wardpulse.wear.model.RingSummary
import app.wardpulse.wear.model.WatchDashboardSummary
import app.wardpulse.wear.model.WatchDataMode
import app.wardpulse.wear.ui.theme.WardPulseTheme
import app.wardpulse.wear.watchface.WatchFaceState
import app.wardpulse.wear.watchface.WatchFaceStatus
import java.io.File
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class WardPulseNavigationStateTest {
    private val instrumentation = InstrumentationRegistry.getInstrumentation()
    private val automation = instrumentation.uiAutomation
    private lateinit var scenario: ActivityScenario<MainActivity>
    private lateinit var recomposer: Recomposer
    private lateinit var compositionScope: CoroutineScope
    private lateinit var recomposition: Job
    private var summary by mutableStateOf<WatchDashboardSummary?>(null)
    private var watchFaceState by mutableStateOf(WatchFaceState(busy = true))
    private val calls = mutableListOf<String>()
    private var callbacks by mutableStateOf(callbacksFor("initial"))
    private val alpha = summary("Alpha", usedPercent = 25.0)
    private val beta = summary("Beta", usedPercent = 96.0)

    @After
    fun tearDown() {
        try {
            if (::scenario.isInitialized) scenario.close()
        } finally {
            if (::recomposer.isInitialized) recomposer.cancel()
            if (::compositionScope.isInitialized) compositionScope.cancel()
            runBlocking {
                withTimeout(5_000) {
                    if (::recomposition.isInitialized) recomposition.join()
                    if (::recomposer.isInitialized) recomposer.join()
                }
            }
        }
    }

    @Test
    fun utilityRepaintsOnTheSameVisitAndKeepsPendingPermissionAcrossSummaryChanges() {
        launchApp()
        assertVisible("Sync from phone")
        click("Watch face")
        assertVisible("Checking watch face…")
        assertAction("Check again", enabled = false)
        assertCalls("initial.check")

        scrollToStart()
        change { summary = alpha }
        assertVisible("Checking watch face…")
        assertCalls("initial.check")

        change {
            watchFaceState = WatchFaceState(WatchFaceStatus.Installed, useAvailable = true)
        }
        assertVisible("Installed")
        assertAbsent("Checking watch face…", anchor = "Installed")
        reveal("Make WardPulse your watch face.")
        assertAction("Use watch face", enabled = true)

        // Replace callbacks alone, without a status/summary change to hide a stale capture.
        change { callbacks = callbacksFor("latest") }
        click("Use watch face")
        assertAction("Use watch face", enabled = false)
        assertCalls("initial.check", "latest.use")

        // Arrival, replacement and loss must not pop the utility or replay its effects.
        for (next in listOf(null, alpha, beta, null, beta)) {
            change { summary = next }
            assertAction("Use watch face", enabled = false)
            assertAbsent("Sync from phone", anchor = "Use watch face", anchorIsAction = true)
            assertCalls("initial.check", "latest.use")
        }

        scrollToStart()
        change { watchFaceState = WatchFaceState(WatchFaceStatus.InUse) }
        assertVisible("In use")
        assertAbsent("Installed", anchor = "In use")
        assertAbsent("Use watch face", anchor = "In use")
        assertCalls("initial.check", "latest.use")

        // Other retained actions must also use the replacement callbacks.
        change { watchFaceState = WatchFaceState(WatchFaceStatus.CheckFailed) }
        assertVisible("Could not check the watch face.")
        assertAction("Check again", enabled = true)
        click("Check again")
        assertCalls("initial.check", "latest.use", "latest.check")

        scrollToStart()
        change { watchFaceState = WatchFaceState(WatchFaceStatus.Missing) }
        assertVisible("Install the WardPulse watch face.")
        assertAction("Install watch face", enabled = true)
        click("Install watch face")
        assertCalls("initial.check", "latest.use", "latest.check", "latest.install")

        scrollToStart()
        change {
            watchFaceState = WatchFaceState(WatchFaceStatus.Installed, updateAvailable = true)
        }
        assertVisible("Installed")
        assertAction("Update watch face", enabled = true)
        change { watchFaceState = watchFaceState.copy(busy = true) }
        assertAction("Update watch face", enabled = false)
        change { watchFaceState = watchFaceState.copy(busy = false) }
        click("Update watch face")
        assertCalls("initial.check", "latest.use", "latest.check", "latest.install", "latest.update")

        scrollToStart()
        change { watchFaceState = WatchFaceState(WatchFaceStatus.InUse) }
        assertVisible("In use")
        back()
        assertVisible("Codex Beta")
        assertVisible("4% left")
        assertTrue(scroll(AccessibilityNodeInfo.ACTION_SCROLL_FORWARD))
        assertVisible("Plan windows")
        reveal("Codex Beta")
        click("Watch face")
        assertVisible("In use")
        assertCalls(
            "initial.check", "latest.use", "latest.check", "latest.install", "latest.update", "latest.check",
        )
        back()
        assertVisible("Watch face")
        assertAbsent("In use", anchor = "Watch face", anchorIsAction = true)
        assertAbsent("Alerts: 1", anchor = "Watch face", anchorIsAction = true)
    }

    @Test
    fun retainedHomeAndAlertsRepaintReplacementLossAndRestorationWithoutResettingThePager() {
        launchApp(alpha)
        assertVisible("Codex Alpha")
        assertVisible("75% left")
        change { summary = beta }
        assertVisible("Codex Beta")
        assertVisible("4% left")
        assertAbsent("Codex Alpha", anchor = "Codex Beta")

        // Controlled in-memory Beta evidence: overwrite one native-size PNG in the target cache.
        val screenshot = checkNotNull(automation.takeScreenshot()) { "Beta screenshot failed" }
        try {
            val width = screenshot.width
            val height = screenshot.height
            assertTrue("Beta screenshot dimensions exceed bounds", width in 1..1024 && height in 1..1024)
            val evidence = File(instrumentation.targetContext.cacheDir, "wear-beta-four-percent.png")
            evidence.outputStream().use { output ->
                assertTrue("Beta PNG compression failed", screenshot.compress(Bitmap.CompressFormat.PNG, 100, output))
            }
            assertTrue("Beta PNG size exceeds bounds", evidence.isFile && evidence.length() in 1L..(4L * 1024 * 1024))
            val options = BitmapFactory.Options().apply { inScaled = false }
            val decoded = checkNotNull(BitmapFactory.decodeFile(evidence.absolutePath, options)) {
                "Beta PNG could not be decoded"
            }
            try {
                assertEquals("Beta artifact is not PNG", "image/png", options.outMimeType)
                assertEquals("Beta PNG width changed", width, decoded.width)
                assertEquals("Beta PNG height changed", height, decoded.height)
            } finally {
                decoded.recycle()
            }
        } finally {
            screenshot.recycle()
        }

        change { summary = null }
        assertVisible("Sync from phone")
        assertAbsent("Codex Beta", anchor = "Sync from phone")
        change { summary = alpha }
        assertVisible("Codex Alpha")
        assertVisible("75% left")

        click("Alerts: 1")
        assertVisible("Alerts")
        assertVisible("Alpha alert")
        change { summary = beta }
        assertVisible("Beta alert")
        assertAbsent("Alpha alert", anchor = "Beta alert")
        change { summary = null }
        assertVisible("Sync from phone")
        assertAbsent("Beta alert", anchor = "Sync from phone")
        change { summary = beta }
        assertVisible("Alerts")
        assertVisible("Beta alert")
        assertAbsent("Sync from phone", anchor = "Beta alert")

        back()
        assertVisible("Codex Beta")
        assertTrue(scroll(AccessibilityNodeInfo.ACTION_SCROLL_FORWARD))
        assertVisible("Plan windows")
        reveal("Codex Beta")
        change { summary = alpha }
        assertVisible("Plan windows")
        assertVisible("Codex Alpha")
        assertVisible("75% left")
        assertAbsent("Alerts: 1", anchor = "Codex Alpha")
        change { summary = null }
        assertVisible("Sync from phone")
        change { summary = beta }
        assertVisible("Plan windows")
        reveal("Codex Beta")
        assertVisible("4% left")

        change { watchFaceState = WatchFaceState(WatchFaceStatus.InUse) }
        click("Watch face")
        assertVisible("In use")
        assertCalls("initial.check")
        back()
        assertVisible("Watch face")
        assertAbsent("In use", anchor = "Watch face", anchorIsAction = true)
        assertAbsent("Alerts: 1", anchor = "Watch face", anchorIsAction = true)
        assertTrue(scroll(AccessibilityNodeInfo.ACTION_SCROLL_BACKWARD))
        assertVisible("Alerts: 1")
        assertVisible("Codex Beta")
        assertCalls("initial.check")
    }

    private fun launchApp(initialSummary: WatchDashboardSummary? = null) {
        instrumentation.runOnMainSync { summary = initialSummary }
        scenario = ActivityScenario.launch(MainActivity::class.java)
        scenario.onActivity { activity ->
            // Public Compose runtime APIs give this content a deterministic, animation-free
            // recomposer without changing device settings or adding a production test hook.
            val context = AndroidUiDispatcher.Main + object : MotionDurationScale {
                override val scaleFactor = 0f
            }
            compositionScope = CoroutineScope(context)
            recomposer = Recomposer(context)
            recomposition = compositionScope.launch { recomposer.runRecomposeAndApplyChanges() }
            activity.setContent(parent = recomposer) {
                WardPulseTheme {
                    WardPulseApp(
                        summary = summary,
                        watchFaceState = watchFaceState,
                        onCheckWatchFace = callbacks.onCheck,
                        onInstallWatchFace = callbacks.onInstall,
                        onUpdateWatchFace = callbacks.onUpdate,
                        onUseWatchFace = callbacks.onUse,
                    )
                }
            }
        }
        awaitUi()
    }

    private fun change(action: () -> Unit) {
        scenario.onActivity { action() }
        awaitUi()
    }

    private fun awaitUi() {
        instrumentation.waitForIdleSync()
        repeat(2) { awaitFrame() }
        runBlocking { withTimeout(5_000) { recomposer.awaitIdle() } }
        instrumentation.waitForIdleSync()
        // Callback-only changes need not emit accessibility events. Assertions below wait
        // for their own observable state instead of treating event quiet as publication.
    }

    private fun awaitFrame(timeoutMillis: Long = 5_000) {
        val frame = CountDownLatch(1)
        instrumentation.runOnMainSync {
            Choreographer.getInstance().postFrameCallback { frame.countDown() }
        }
        assertTrue("UI frame did not complete", frame.await(timeoutMillis, TimeUnit.MILLISECONDS))
    }

    private fun awaitAccessibility(message: String, condition: (AccessibilityNodeInfo) -> Boolean) {
        val deadline = SystemClock.uptimeMillis() + 5_000
        while (SystemClock.uptimeMillis() < deadline) {
            val root = appRoot()
            if (root != null && condition(root)) return
            val remaining = deadline - SystemClock.uptimeMillis()
            if (remaining <= 0) break
            awaitFrame(remaining)
        }
        throw AssertionError(message)
    }

    private fun back() {
        instrumentation.sendKeyDownUpSync(KeyEvent.KEYCODE_BACK)
        awaitUi()
    }

    private fun assertCalls(vararg expected: String) {
        scenario.onActivity { assertEquals(expected.toList(), calls) }
    }

    private fun callbacksFor(owner: String) = Callbacks(
        onCheck = { calls += "$owner.check" },
        onInstall = { calls += "$owner.install" },
        onUpdate = { calls += "$owner.update" },
        onUse = {
            calls += "$owner.use"
            watchFaceState = WatchFaceState(
                WatchFaceStatus.Installed,
                busy = true,
                awaitingPermission = true,
            )
        },
    )

    private data class Callbacks(
        val onCheck: () -> Unit,
        val onInstall: () -> Unit,
        val onUpdate: () -> Unit,
        val onUse: () -> Unit,
    )

    private fun assertVisible(text: String) {
        awaitAccessibility("Expected visible text: $text") { findText(it, text) != null }
    }

    private fun assertAbsent(text: String, anchor: String, anchorIsAction: Boolean = false) {
        awaitAccessibility("Expected $anchor without visible text: $text") { root ->
            val anchored = if (anchorIsAction) {
                findButton(root, anchor) != null
            } else {
                findText(root, anchor) != null
            }
            anchored && findText(root, text) == null
        }
    }

    private fun hasText(text: String): Boolean {
        return findText(text) != null
    }

    private fun findText(text: String): AccessibilityNodeInfo? = appRoot()?.let { findText(it, text) }

    private fun findText(root: AccessibilityNodeInfo, text: String): AccessibilityNodeInfo? = findNode(root) {
        it.isVisibleToUser && it.text?.toString()?.lineSequence()?.any { line -> line == text } == true
    }

    private fun findButton(root: AccessibilityNodeInfo, text: String): AccessibilityNodeInfo? {
        var node = findText(root, text) ?: return null
        while (!node.isClickable && node.className != "android.widget.Button") {
            node = node.parent?.takeIf { it.refresh() } ?: return null
        }
        return node
    }

    private fun assertAction(text: String, enabled: Boolean) {
        reveal(text)
        awaitAccessibility("Expected enabled=$enabled for $text") { root ->
            findButton(root, text)?.isEnabled == enabled
        }
    }

    private fun click(text: String) {
        reveal(text)
        var node = checkNotNull(findText(text)) { "Missing action: $text" }
        while (!node.actionList.contains(AccessibilityNodeInfo.AccessibilityAction.ACTION_CLICK)) {
            node = checkNotNull(node.parent?.takeIf { it.refresh() }) { "No click action for: $text" }
        }
        assertTrue("Disabled action: $text", node.isEnabled)
        assertTrue("Click failed: $text", node.performAction(AccessibilityNodeInfo.ACTION_CLICK))
        awaitUi()
    }

    private fun reveal(text: String) {
        // Bounded user scrolling through a lazy list, never navigation or state retries.
        repeat(8) {
            if (hasText(text)) return
            check(scroll(AccessibilityNodeInfo.ACTION_SCROLL_FORWARD)) { "Cannot reveal: $text" }
        }
        assertVisible(text)
    }

    private fun scrollToStart() {
        repeat(8) {
            if (!scroll(AccessibilityNodeInfo.ACTION_SCROLL_BACKWARD)) return
        }
        error("Utility did not reach the start")
    }

    private fun scroll(action: Int): Boolean {
        val node = findNode { candidate ->
            candidate.isVisibleToUser && candidate.actionList.any { it.id == action }
        } ?: return false
        val performed = node.performAction(action)
        if (performed) awaitUi()
        return performed
    }

    private fun appRoot(): AccessibilityNodeInfo? {
        val root = automation.rootInActiveWindow ?: return null
        return root.takeIf {
            it.refresh() && it.isVisibleToUser && it.packageName?.toString() == instrumentation.targetContext.packageName
        }
    }

    private fun findNode(predicate: (AccessibilityNodeInfo) -> Boolean): AccessibilityNodeInfo? {
        val root = appRoot() ?: return null
        return findNode(root, predicate)
    }

    private fun findNode(
        node: AccessibilityNodeInfo,
        predicate: (AccessibilityNodeInfo) -> Boolean,
    ): AccessibilityNodeInfo? {
        // Refresh every node, including descendants/parents, rather than trusting cached
        // results while Compose's accessibility publication may still be pending.
        if (!node.refresh()) return null
        if (predicate(node)) return node
        for (index in 0 until node.childCount) {
            val child = node.getChild(index) ?: continue
            val found = findNode(child, predicate)
            if (found != null) return found
        }
        return null
    }

    private fun summary(label: String, usedPercent: Double): WatchDashboardSummary {
        val period = PeriodSummary("today", null, null, null, null, null, PulseStatus.OK)
        return WatchDashboardSummary(
            schemaVersion = 9,
            dataMode = WatchDataMode.LIVE,
            generatedAt = "2026-10-16T12:00:00Z",
            overallStatus = PulseStatus.OK,
            rings = listOf(RingSummary("allowance.codex.plan", "Codex $label", usedPercent, PulseStatus.OK)),
            creditsGlance = null,
            today = period,
            week = period.copy(period = "week"),
            allowances = listOf(
                AllowanceSummary("plan", "Codex $label", usedPercent, null, resetsAt = null, status = PulseStatus.OK),
            ),
            providers = emptyList(),
            alerts = listOf(AlertSummary("warning", "$label alert")),
            isStale = false,
            manualRefreshAllowed = false,
            manualRefreshAvailableAt = null,
        )
    }
}
