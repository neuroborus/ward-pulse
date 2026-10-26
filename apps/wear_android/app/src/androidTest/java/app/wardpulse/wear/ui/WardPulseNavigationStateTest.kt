package app.wardpulse.wear.ui

import android.app.PendingIntent
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Rect
import android.graphics.RectF
import android.os.Build
import android.os.SystemClock
import android.util.Log
import android.view.Choreographer
import android.view.InputDevice
import android.view.KeyEvent
import android.view.MotionEvent
import android.view.View
import android.view.ViewGroup
import android.view.accessibility.AccessibilityNodeInfo
import androidx.activity.BackEventCompat
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.onFocusedBoundsChanged
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.Recomposer
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.LocalSaveableStateRegistry
import androidx.compose.runtime.saveable.SaveableStateRegistry
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.MotionDurationScale
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.input.pointer.util.VelocityTracker
import androidx.compose.ui.layout.LayoutCoordinates
import androidx.compose.ui.layout.positionOnScreen
import androidx.compose.ui.platform.AndroidUiDispatcher
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.ViewRootForTest
import androidx.compose.ui.semantics.SemanticsNode
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.semantics.getOrNull
import androidx.compose.ui.unit.Density
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.ViewModelProvider
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.runner.lifecycle.ActivityLifecycleCallback
import androidx.test.runner.lifecycle.ActivityLifecycleMonitorRegistry
import androidx.test.runner.lifecycle.Stage
import androidx.wear.compose.material3.AppScaffold
import app.wardpulse.wear.MainActivity
import app.wardpulse.wear.WatchFaceViewModel
import app.wardpulse.wear.data.WatchSummaryStore
import app.wardpulse.wear.model.AlertSummary
import app.wardpulse.wear.model.AllowanceSummary
import app.wardpulse.wear.model.PeriodSummary
import app.wardpulse.wear.model.ProviderSummary
import app.wardpulse.wear.model.PulseStatus
import app.wardpulse.wear.model.RingSummary
import app.wardpulse.wear.model.WatchDashboardSummary
import app.wardpulse.wear.model.WatchDataMode
import app.wardpulse.wear.ui.theme.WardPulseTheme
import app.wardpulse.wear.watchface.InstalledWatchFace
import app.wardpulse.wear.watchface.WatchFaceBundle
import app.wardpulse.wear.watchface.WatchFaceConsent
import app.wardpulse.wear.watchface.WatchFaceConsentHistory
import app.wardpulse.wear.watchface.WatchFaceController
import app.wardpulse.wear.watchface.WatchFaceInventory
import app.wardpulse.wear.watchface.WatchFacePushClient
import app.wardpulse.wear.watchface.WatchFaceScreen
import app.wardpulse.wear.watchface.WatchFaceState
import app.wardpulse.wear.watchface.WatchFaceStatus
import java.io.File
import java.util.Collections
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.Job
import kotlinx.coroutines.cancel
import kotlinx.coroutines.cancelAndJoin
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertSame
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
    private val scrollTrace = mutableListOf<String>()
    private var focusedCoordinates: LayoutCoordinates? = null
    private var callbacks by mutableStateOf(callbacksFor("initial"))
    private val alpha = summary("Alpha", usedPercent = 25.0)
    private val beta = summary("Beta", usedPercent = 96.0)
    private val productionOwners = mutableListOf<MainActivity>()
    private var productionTaskId: Int? = null
    private var savedSummaryPreferences: SharedPreferences? = null
    private var originalSavedSummary: String? = null
    private var oldTapToken: PendingIntent? = null
    private var entrySequence = 0L
    private val ownerLifecycle = ActivityLifecycleCallback { activity, stage ->
        if (activity is MainActivity && stage == Stage.CREATED) {
            if (productionTaskId == null) productionTaskId = activity.taskId
            productionOwners += activity
        }
    }

    @After
    fun tearDown() {
        try {
            if (::scenario.isInitialized) scenario.close()
        } finally {
            try {
                oldTapToken?.cancel()
                instrumentation.runOnMainSync {
                    // Only Activities created during this isolated test, including duplicates on failure.
                    productionOwners.filterNot { it.isDestroyed }.forEach { it.finish() }
                }
                if (productionTaskId != null) {
                    awaitOwnerState("Production test owners must be destroyed") {
                        var destroyed = false
                        instrumentation.runOnMainSync { destroyed = productionOwners.all { it.isDestroyed } }
                        destroyed
                    }
                }
            } finally {
                try {
                    instrumentation.runOnMainSync {
                        ActivityLifecycleMonitorRegistry.getInstance().removeLifecycleCallback(ownerLifecycle)
                    }
                    savedSummaryPreferences?.let { preferences ->
                        assertTrue(preferences.edit().putString("latest", originalSavedSummary).commit())
                    }
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
        }
    }

    @Test
    fun productionRedeliveryKeepsOwnersAndLauncherNavigationWithoutReplayingConsumedFaceEntry() {
        launchProduction(alpha)
        val owner = productionOwner()
        val model = productionModel(owner)
        awaitHomePage(0)
        click("Alerts: 1")
        assertVisible("Alpha alert")

        deliverEntry(launcherIntent())
        assertVisible("Alpha alert")
        assertClock(visible = true, anchor = "Alerts")
        assertProductionOwner(owner)
        onActivity { assertEquals(Intent.ACTION_MAIN, it.intent.action) }

        // Old actionless delivery has no Activity flags. Manifest singleTop must suffice.
        deliverEntry(Intent(instrumentation.targetContext, MainActivity::class.java))
        awaitHomePage(0)
        assertVisible("Codex Alpha")
        assertClock(visible = false, anchor = "Codex Alpha")
        assertProductionOwner(owner)
        onActivity { assertEquals(null, it.intent.action) }

        page(AccessibilityNodeInfo.AccessibilityAction.ACTION_PAGE_DOWN.id)
        reveal("Watch face")
        click("Watch face")
        assertProductionUtility()
        deliverEntry(launcherIntent())
        assertProductionUtility()
        assertSame(model, productionModel(owner))

        // Measured wordmark flags: explicit component, NEW_TASK, no action/category.
        deliverEntry(faceIntent())
        awaitHomePage(0)
        assertClock(visible = false, anchor = "Codex Alpha")
        assertProductionOwner(owner)
        assertSame(model, productionModel(owner))
        onActivity {
            assertTrue(it.intent.flags and Intent.FLAG_ACTIVITY_NEW_TASK != 0)
            assertEquals(null, it.intent.categories)
        }

        // A consumed face Intent must not reset restored nested navigation on recreation.
        click("Alerts: 1")
        recreateProductionOwner()
        val recreated = productionOwner()
        assertTrue(owner !== recreated)
        assertSame(model, productionModel(recreated))
        assertProductionOwner(recreated, creations = 2)
        assertVisible("Alpha alert")
        assertClock(visible = true, anchor = "Alerts")

        WatchSummaryStore(instrumentation.targetContext).save(beta)
        assertVisible("Beta alert")
        back(toHomePage = 0)
        assertVisible("Codex Beta")
        click("Alerts: 1")
        deliverEntry(faceIntent().addFlags(Intent.FLAG_ACTIVITY_REORDER_TO_FRONT or Intent.FLAG_ACTIVITY_SINGLE_TOP))
        awaitHomePage(0)
        assertVisible("Codex Beta")
        assertProductionOwner(recreated, creations = 2)
        // Home/reopen cycles retain the same Activity and continue observing fresh data.
        repeat(3) {
            instrumentation.sendKeyDownUpSync(KeyEvent.KEYCODE_HOME)
            awaitBackground(recreated)
            deliverEntry(faceIntent())
            awaitHomePage(0)
            assertVisible("Codex Beta")
            assertProductionOwner(recreated, creations = 2)
        }
        back()
        awaitBackground(recreated)
        deliverEntry(launcherIntent())
        awaitHomePage(0)
        assertProductionOwner(recreated, creations = 2)
        assertSame(model, productionModel(recreated))
    }

    @Test
    fun productionOldTapReturnsToNoSummaryPromptAndRootSwipeRetainsTheOwner() {
        launchProduction(null, entry = faceIntent())
        val owner = productionOwner()
        val model = productionModel(owner)
        assertVisible("Sync from phone")
        click("Watch face")
        assertProductionUtility()
        // A separate request code avoids changing or cancelling the installed face's token.
        oldTapToken = PendingIntent.getActivity(
            instrumentation.targetContext, 17361,
            Intent(instrumentation.targetContext, MainActivity::class.java),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        checkNotNull(oldTapToken).send()
        assertVisible("Sync from phone")
        assertClock(visible = true, anchor = "Sync from phone")
        assertProductionOwner(owner)
        assertSame(model, productionModel(owner))

        WatchSummaryStore(instrumentation.targetContext).save(alpha)
        awaitHomePage(0)
        assertVisible("Codex Alpha")
        val viewport = checkNotNull(nativeSurface("home-pager")).viewport
        backPreview(cancelled = true, touchOnly = true) { assertProductionOwner(owner) }
        awaitHomePage(0)
        awaitHomeViewport(viewport)
        assertProductionOwner(owner)
        backPreview(cancelled = false, touchOnly = true) { assertProductionOwner(owner) }
        awaitBackground(owner)
        deliverEntry(launcherIntent())
        awaitHomePage(0)
        assertVisible("Codex Alpha")
        assertProductionOwner(owner)
        assertSame(model, productionModel(owner))
    }

    @Test
    fun homeDismissalCallsOnceAfterCommittedSwipeOrBackAndNeverAfterCancellation() {
        var dismissals = 0
        launchApp(alpha, onDismissHome = { dismissals++ })
        awaitHomePage(0)
        val viewport = checkNotNull(nativeSurface("home-pager")).viewport
        for (cancelled in listOf(true, false)) {
            backPreview(cancelled, touchOnly = true) {
                scenario.onActivity { assertEquals(0, dismissals) }
            }
            scenario.onActivity { assertEquals(if (cancelled) 0 else 1, dismissals) }
            awaitHomePage(0)
            awaitHomeViewport(viewport)
        }
        back()
        scenario.onActivity { assertEquals(2, dismissals) }
        if (Build.VERSION.SDK_INT > 35) {
            backPreview(cancelled = true) { scenario.onActivity { assertEquals(2, dismissals) } }
            scenario.onActivity { assertEquals(2, dismissals) }
            backPreview(cancelled = false) { scenario.onActivity { assertEquals(2, dismissals) } }
            scenario.onActivity { assertEquals(3, dismissals) }
        }
        assertClock(visible = false, anchor = "Codex Alpha")
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
        // Preserve restored Alerts focus; otherwise establish the focused-control fixture
        // with the same public input-focus action used by the rotary ownership cases.
        recordHomePager("before utility Back to Home page=0")
        back(toHomePage = 0)
        assertVisible("Codex Beta")
        assertVisible("4% left")
        assertClock(visible = false, anchor = "Alerts: 1")
        val alerts = checkNotNull(appRoot()?.let { findButton(it, "Alerts: 1") })
        if (!alerts.isFocused) {
            assertTrue("Alerts input focus failed", alerts.performAction(AccessibilityNodeInfo.ACTION_FOCUS))
        }
        assertTrue(scroll(AccessibilityNodeInfo.ACTION_SCROLL_FORWARD, focusedGlanceControl = "Alerts: 1"))
        assertVisible("Plan windows")
        assertClock(visible = true, anchor = "Plan windows")
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
    fun separateFaceGuidanceRefreshesOnRecheckExternalReturnAndRevisit() {
        var nextStatus = WatchFaceStatus.SeparateMissing
        instrumentation.runOnMainSync {
            callbacks = callbacksFor("manual").copy(onCheck = {
                calls += "manual.check"
                watchFaceState = WatchFaceState(nextStatus)
            })
        }
        launchApp()
        click("Watch face")
        val missing = "Install WardPulse Watch Face separately, then select it from your watch-face list."
        val unknown = "Could not check whether the separate watch face is installed."
        val installed = "Installed. Select WardPulse from your watch-face list."
        assertVisible(missing)
        assertAction("Check again", enabled = true)
        assertCalls("manual.check")

        change {
            nextStatus = WatchFaceStatus.SeparateCheckFailed
            callbacks = callbacks.copy(onCheck = {
                calls += "latest.check"
                watchFaceState = WatchFaceState(nextStatus)
            })
        }
        click("Check again")
        scrollToStart()
        assertVisible(unknown)
        assertAbsent(missing, anchor = unknown)
        assertCalls("manual.check", "latest.check")

        // Model leaving for an external installation without modifying any package/data.
        scenario.moveToState(Lifecycle.State.CREATED)
        instrumentation.runOnMainSync { nextStatus = WatchFaceStatus.SeparateInstalled }
        scenario.moveToState(Lifecycle.State.RESUMED)
        awaitUi()
        assertVisible(installed)
        assertAbsent(unknown, anchor = installed)
        assertAbsent("In use", anchor = installed)
        assertAbsent("Use watch face", anchor = installed)
        assertAction("Check again", enabled = true)
        assertCalls("manual.check", "latest.check", "latest.check")

        back()
        assertVisible("Sync from phone")
        change { nextStatus = WatchFaceStatus.SeparateMissing }
        click("Watch face")
        assertVisible(missing)
        assertAbsent(installed, anchor = missing)
        assertCalls("manual.check", "latest.check", "latest.check", "latest.check")
    }

    @Test
    fun supportedFaceResumeKeepsPostUpdateActivityUnobserved() {
        launchApp()
        click("Watch face")
        assertCalls("initial.check")
        change { watchFaceState = WatchFaceState(WatchFaceStatus.Installed, updateAvailable = true) }
        click("Update watch face")
        change { watchFaceState = WatchFaceState(WatchFaceStatus.Installed, useAvailable = true) }
        scenario.moveToState(Lifecycle.State.CREATED)
        scenario.moveToState(Lifecycle.State.RESUMED)
        awaitUi()
        scrollToStart()
        assertVisible("Installed")
        assertAbsent("In use", anchor = "Installed")
        assertCalls("initial.check", "initial.update")
    }

    @Test
    fun separateFaceReturnDuringOldObservationRefreshesAfterItSettles() {
        assertFreshSeparateFaceAfterOldObservation { install ->
            scenario.moveToState(Lifecycle.State.CREATED)
            install()
            scenario.moveToState(Lifecycle.State.RESUMED)
            awaitUi()
        }
    }

    @Test
    fun separateFaceRevisitDuringOldObservationRefreshesAfterItSettles() {
        assertFreshSeparateFaceAfterOldObservation { install ->
            back()
            assertVisible("Sync from phone")
            install()
            click("Watch face")
        }
    }

    @Test
    fun separateFaceRestoredCompositionDuringOldObservationRefreshesAfterItSettles() {
        var visible by mutableStateOf(false)
        var registry by mutableStateOf(SaveableStateRegistry(null) { true })
        assertFreshSeparateFaceAfterOldObservation(
            launchContent = {
                launchApp(content = {
                    AppScaffold {
                        if (visible) {
                            CompositionLocalProvider(LocalSaveableStateRegistry provides registry) {
                                WatchFaceScreen(
                                    state = watchFaceState,
                                    onCheck = callbacks.onCheck,
                                    onInstall = callbacks.onInstall,
                                    onUpdate = callbacks.onUpdate,
                                    onUse = callbacks.onUse,
                                )
                            }
                        }
                    }
                })
            },
            openUtility = { change { visible = true } },
        ) { install ->
            var saved = emptyMap<String, List<Any?>>()
            // Rebuild the screen from its actual saved values, retaining the controller
            // as the ViewModel does. The new observer receives only its initial resume.
            change {
                saved = registry.performSave()
                visible = false
            }
            install()
            change {
                registry = SaveableStateRegistry(saved) { true }
                visible = true
            }
        }
    }

    private fun assertFreshSeparateFaceAfterOldObservation(
        launchContent: () -> Unit = { launchApp() },
        openUtility: () -> Unit = { click("Watch face") },
        leaveAndReturn: (() -> Unit) -> Unit,
    ) {
        val oldObservationEntered = CompletableDeferred<Unit>()
        val releaseOldObservation = CompletableDeferred<Unit>()
        val installed = AtomicBoolean(false)
        val effects = Collections.synchronizedList(mutableListOf<String>())
        fun unexpected(effect: String): Nothing {
            effects += effect
            error("Unexpected separate-face effect: $effect")
        }
        val client = object : WatchFacePushClient {
            override val sdkInt = 34
            override fun isSupported(): Boolean {
                effects += "support"
                return false
            }
            override fun isSeparateFaceInstalled(): Boolean {
                effects += "separate"
                val observed = installed.get()
                if (oldObservationEntered.complete(Unit)) {
                    runBlocking { releaseOldObservation.await() }
                }
                return observed
            }
            override fun openBundle(): WatchFaceBundle = unexpected("bundle")
            override suspend fun list(): WatchFaceInventory = unexpected("inventory")
            override suspend fun isActive(packageName: String): Boolean = unexpected("active")
            override suspend fun install(bundle: WatchFaceBundle): InstalledWatchFace = unexpected("install")
            override suspend fun update(slotId: String, bundle: WatchFaceBundle): InstalledWatchFace =
                unexpected("update")
            override fun hasActivationPermission(): Boolean = unexpected("permission")
            override suspend fun activate(slotId: String): Unit = unexpected("activate")
        }
        val consent = object : WatchFaceConsentHistory {
            override fun read(): WatchFaceConsent = unexpected("consent.read")
            override fun compareAndSet(expected: WatchFaceConsent, consent: WatchFaceConsent): Boolean =
                unexpected("consent.write")
        }
        val controller = WatchFaceController(client, consent)
        launchContent()
        val observation = Job(compositionScope.coroutineContext[Job])
        val scope = CoroutineScope(compositionScope.coroutineContext + observation)
        val checks = mutableListOf<Job>()
        scenario.onActivity {
            callbacks = callbacksFor("separate").copy(onCheck = {
                calls += "separate.check"
                checks += scope.launch(start = CoroutineStart.UNDISPATCHED) { controller.check() }
            })
            scope.launch {
                controller.state.collect { watchFaceState = it }
            }
        }
        try {
            openUtility()
            runBlocking { withTimeout(5_000) { oldObservationEntered.await() } }
            assertVisible("Checking watch face…")
            // Model an external installation after the old query captured absence.
            leaveAndReturn { installed.set(true) }
            assertCalls("separate.check", "separate.check")
            scenario.onActivity {
                assertEquals(2, checks.size)
                checks.forEach { assertFalse(it.isCompleted) }
            }
            assertEquals(WatchFaceState(WatchFaceStatus.Checking, busy = true), controller.state.value)
            assertEquals(listOf("support", "separate"), effects.toList())

            releaseOldObservation.complete(Unit)
            val guidance = "Installed. Select WardPulse from your watch-face list."
            assertVisible(guidance)
            assertAction("Check again", enabled = true)
            assertAbsent("In use", anchor = guidance)
            assertAbsent("Use watch face", anchor = guidance)
            assertCalls("separate.check", "separate.check")
            assertEquals(WatchFaceState(WatchFaceStatus.SeparateInstalled), controller.state.value)
            assertEquals(listOf("support", "separate", "support", "separate"), effects.toList())
        } finally {
            releaseOldObservation.complete(Unit)
            runBlocking {
                withTimeout(5_000) { observation.cancelAndJoin() }
            }
        }
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

    @Test
    fun localLegendAndPagerAccessibilityActionsStaySeparateAndClocksFollowVisibleContent() {
        // Three short rows overflow by height at the supported 2x text scale. Only
        // this in-memory composition is scaled; no provider or device setting changes.
        val overflowing = alpha.copy(
            rings = listOf(
                RingSummary("allowance.codex.plan", "Codex Alpha", 25.0, PulseStatus.OK),
                RingSummary("allowance.cursor.plan", "Cursor Beta", 20.0, PulseStatus.OK),
                RingSummary("allowance.claude.plan", "Claude Gamma", 0.0, PulseStatus.OK),
            ),
        )
        launchApp(fontScale = 2f)
        assertClock(visible = true, anchor = "Sync from phone")
        change { summary = overflowing }
        assertClock(visible = false, anchor = "Codex Alpha")
        assertAbsent("Claude Gamma", anchor = "Codex Alpha")

        val local = taggedNode("glance-legend", AccessibilityNodeInfo.ACTION_SCROLL_FORWARD)
        val pager = taggedNode("home-pager", AccessibilityNodeInfo.AccessibilityAction.ACTION_PAGE_DOWN.id)
        assertTrue("Legend must be a separate node from the Home Pager", local != pager)
        assertTrue("Local forward action failed", local.performAction(AccessibilityNodeInfo.ACTION_SCROLL_FORWARD))
        awaitUi()
        // New content becomes visible, rather than merely exposing an XML action.
        assertVisible("Claude Gamma")
        assertAbsent("Codex Alpha", anchor = "Claude Gamma")
        assertAbsent("Plan windows", anchor = "Alerts: 1")
        assertClock(visible = false, anchor = "Claude Gamma")
        val localBack = taggedNode("glance-legend", AccessibilityNodeInfo.ACTION_SCROLL_BACKWARD)
        assertTrue("Local backward action failed", localBack.performAction(AccessibilityNodeInfo.ACTION_SCROLL_BACKWARD))
        awaitUi()
        assertVisible("Codex Alpha")
        assertAbsent("Claude Gamma", anchor = "Codex Alpha")
        assertAbsent("Plan windows", anchor = "Alerts: 1")

        // Recomposition alone and a measured refresh-detail change must not restore time.
        change { callbacks = callbacksFor("recomposed") }
        assertClock(visible = false, anchor = "Codex Alpha")
        change { summary = overflowing.copy(isStale = true) }
        assertClock(visible = false, anchor = "Stale")

        page(AccessibilityNodeInfo.AccessibilityAction.ACTION_PAGE_DOWN.id)
        assertClock(visible = true, anchor = "Plan windows")
        change { summary = null }
        assertClock(visible = true, anchor = "Sync from phone")
        change { summary = overflowing }
        assertClock(visible = true, anchor = "Plan windows")
        val planList = taggedNode("plan-windows-list")
        val planHeaderAtStart = bounds(checkNotNull(findText(planList, "Plan windows")))
        val planClockAtStart = bounds(taggedNode("app-clock"))
        assertTrue(
            "Expected the header, plan row and utility entry in the local collection",
            findNode(planList) { it.collectionInfo?.rowCount == 3 } != null,
        )
        assertTrue(
            "Plan windows must initially be at its local start",
            findNode(planList) { node ->
                node.actionList.any { it.id == AccessibilityNodeInfo.ACTION_SCROLL_BACKWARD }
            } == null && findNode(planList) { node ->
                node.actionList.any { it.id == AccessibilityNodeInfo.ACTION_SCROLL_FORWARD }
            } != null,
        )
        change { watchFaceState = WatchFaceState(WatchFaceStatus.InUse) }
        assertTrue(
            "Plan windows local forward action failed",
            scroll(AccessibilityNodeInfo.ACTION_SCROLL_FORWARD, within = "plan-windows-list"),
        )
        reveal("Watch face", within = "plan-windows-list")
        scrollToEnd(within = "plan-windows-list")
        val planEnd = taggedNode("plan-windows-list")
        val nativePlanEnd = checkNotNull(nativeSurface("plan-windows-list"))
        assertTrue(
            "Plan windows must reach its owned end with backward scrolling available",
            nativePlanEnd.maxScrollOffset != null && nativePlanEnd.maxScrollOffset > 0f &&
                nativePlanEnd.scrollOffset == nativePlanEnd.maxScrollOffset &&
                findNode(planEnd) { node ->
                    node.actionList.any { it.id == AccessibilityNodeInfo.ACTION_SCROLL_FORWARD }
                } == null && findNode(planEnd) { node ->
                    node.actionList.any { it.id == AccessibilityNodeInfo.ACTION_SCROLL_BACKWARD }
                } != null,
        )
        assertAbsent("Plan windows", anchor = "Watch face")
        click("Watch face", within = "plan-windows-list")
        assertClock(visible = true, anchor = "In use")
        change { summary = null }
        assertClock(visible = true, anchor = "In use")
        change { summary = overflowing }
        assertClock(visible = true, anchor = "In use")
        back()
        assertClock(visible = true, anchor = "Watch face")
        assertAbsent("In use", anchor = "Watch face", anchorIsAction = true)
        assertAbsent("Plan windows", anchor = "Watch face")
        scrollToStart(within = "plan-windows-list")
        assertPlanWindowsStart(planHeaderAtStart, planClockAtStart)
        assertClock(visible = true, anchor = "Plan windows")
        page(AccessibilityNodeInfo.AccessibilityAction.ACTION_PAGE_UP.id)
        assertClock(visible = false, anchor = "Alerts: 1")

        click("Alerts: 1")
        assertClock(visible = true, anchor = "Alerts")
        change { summary = null }
        assertClock(visible = true, anchor = "Sync from phone")
        change { summary = overflowing }
        assertClock(visible = true, anchor = "Alerts")
        back()
        assertClock(visible = false, anchor = "Alerts: 1")
        change {
            summary = overflowing.copy(
                rings = emptyList(),
                providers = listOf(ProviderSummary("codex", PulseStatus.OK, null)),
            )
        }
        assertClock(visible = false, anchor = "Choose percent rings")
        change { summary = null }
        assertClock(visible = true, anchor = "Sync from phone")
        click("Watch face")
        assertClock(visible = true, anchor = "In use")
        change { summary = overflowing }
        assertClock(visible = true, anchor = "In use")
        back()
        assertClock(visible = false, anchor = "Codex Alpha")
        change { summary = null }
        // The restored no-summary destination can retain its list near Watch face.
        // There is no Home Pager here: reach the original anchor by local scrolling.
        scrollToStart()
        assertClock(visible = true, anchor = "Sync from phone")
        change { summary = overflowing }
        assertClock(visible = false, anchor = "Codex Alpha")
    }

    @Test
    fun overflowingGlanceAcquiresRotaryFocusAndKeepsBothLimitsLocal() {
        val overflowing = overflowingSummary()
        launchApp(overflowing, fontScale = 2f)
        assertLegendOffset("Visible overflowing Glance must acquire input focus without Tab") { value, max ->
            value == 0f && max > 0f
        }
        change { callbacks = callbacksFor("startup-recomposed") }
        assertLegendOffset("Recomposition before input must preserve Glance and its local start") { value, _ ->
            value == 0f
        }
        val initialContent = checkNotNull(nativeSurface("glance-legend")).content

        rotaryScroll(-1f)
        assertLegendOffset("Native forward rotary must move the focused legend") { value, _ -> value > 0f }
        assertTrue(initialContent != checkNotNull(nativeSurface("glance-legend")).content)
        rotaryScroll(1f)
        assertLegendOffset("Native backward rotary must return the legend to its start") { value, _ -> value == 0f }
        rotaryScroll(1f)
        assertLegendOffset("Unused backward rotary must stay on Glance at its start") { value, _ -> value == 0f }

        rotaryScroll(-1_000f)
        assertLegendOffset("Native rotary must reach the legend end") { value, max -> value == max }
        assertVisible("Claude Gamma")
        rotaryScroll(-1f)
        assertLegendOffset("Unused forward rotary must stay on Glance at its end") { value, max -> value == max }
        change { callbacks = callbacksFor("recomposed") }
        assertLegendOffset("Recomposition must retain the focused legend position") { value, max -> value == max }

        // Explicit input focus on an action is distinct from accessibility focus and
        // must survive a stable-page update rather than being reclaimed by the legend.
        val alerts = checkNotNull(appRoot()?.let { findButton(it, "Alerts: 1") })
        assertTrue("Alerts input focus failed", alerts.performAction(AccessibilityNodeInfo.ACTION_FOCUS))
        awaitAccessibility("Alerts must own input focus") { root ->
            findButton(root, "Alerts: 1")?.isFocused == true
        }
        change { summary = overflowing.copy(isStale = true) }
        awaitAccessibility("A header update must preserve action input focus") { root ->
            findButton(root, "Alerts: 1")?.isFocused == true &&
                nativeSurface("glance-legend")?.focused != true
        }
        val retainedOffset = checkNotNull(nativeSurface("glance-legend")?.scrollOffset)
        click("Alerts: 1")
        assertOtherRouteFocus("Alpha alert")
        back()
        assertLegendOffset("Returning from Alerts must retain the local position and focus") { value, _ ->
            value == retainedOffset
        }
        rotaryScroll(1f)
        assertLegendOffset("Returned Glance must receive backward rotary") { value, _ -> value < retainedOffset }
        click("Alerts: 1")
        assertOtherRouteFocus("Alpha alert")
        // Retained Home content must not reclaim focus when overflow leaves or returns.
        change { summary = alpha }
        assertOtherRouteFocus("Alpha alert")
        change { summary = overflowing }
        assertOtherRouteFocus("Alpha alert")
        back()
        assertLegendOffset("Returning after retained content updates must restore local ownership") { value, max ->
            value in 0f..max
        }
    }

    @Test
    fun rotaryOwnershipFollowsTheVisibleHomePageRouteAndOverflow() {
        val overflowing = overflowingSummary()
        launchApp(alpha, fontScale = 2f)
        awaitAccessibility("Fitting Glance must not install a rotary focus target") {
            nativeSurface("home-pager")?.atPage(0) == true &&
                nativeSurface("glance-legend")?.let { it.focused != true && it.maxScrollOffset == null } == true
        }
        change { summary = overflowing }
        assertLegendOffset("Entering overflow must acquire local rotary focus") { value, max -> value == 0f && max > 0f }
        change { summary = alpha }
        awaitAccessibility("Leaving overflow must release local rotary focus") {
            nativeSurface("glance-legend")?.let { it.focused != true && it.maxScrollOffset == null } == true
        }
        change { summary = overflowing }
        assertLegendOffset("Restored overflow must start with local rotary focus") { value, _ -> value == 0f }

        page(AccessibilityNodeInfo.AccessibilityAction.ACTION_PAGE_DOWN.id)
        assertPlanRotaryFocus()
        change { summary = alpha }
        assertPlanRotaryFocus()
        change { summary = overflowing }
        assertPlanRotaryFocus()
        val planStart = checkNotNull(nativeSurface("plan-windows-list")).content
        rotaryScroll(-1f)
        awaitAccessibility("Plan windows must receive rotary after the Glance handoff") {
            nativeSurface("home-pager")?.atPage(1) == true &&
                nativeSurface("plan-windows-list")?.let {
                    it.focused == true && it.scrollOffset != null && it.scrollOffset > 0f && it.content != planStart
                } == true && nativeSurface("glance-legend")?.focused != true
        }
        scrollToStart(within = "plan-windows-list")
        page(AccessibilityNodeInfo.AccessibilityAction.ACTION_PAGE_UP.id)
        assertLegendOffset("Paging back must reactivate the legend") { value, _ -> value == 0f }

        change { summary = null }
        assertOtherRouteFocus("Sync from phone")
        change { watchFaceState = WatchFaceState(WatchFaceStatus.InUse) }
        click("Watch face")
        assertOtherRouteFocus("In use")
        change { summary = overflowing }
        assertOtherRouteFocus("In use")
        back()
        assertLegendOffset("Returning from the utility must focus the newly restored legend") { value, _ -> value == 0f }
        assertCalls("initial.check")

        val alerts = checkNotNull(appRoot()?.let { findButton(it, "Alerts: 1") })
        assertTrue("Alerts input focus failed", alerts.performAction(AccessibilityNodeInfo.ACTION_FOCUS))
        awaitAccessibility("Alerts must own input focus before overflow changes") { root ->
            findButton(root, "Alerts: 1")?.isFocused == true
        }
        for (next in listOf(alpha, overflowing)) {
            change { summary = next }
            awaitAccessibility("Changing overflow must preserve explicit action input focus") { root ->
                findButton(root, "Alerts: 1")?.isFocused == true &&
                    nativeSurface("glance-legend")?.focused != true
            }
        }
    }

    @Test
    fun planWindowsTouchScrollAndBoundaryPagingRemainAvailable() {
        launchApp(alpha, fontScale = 2f)
        taggedNode("glance-legend")
        page(AccessibilityNodeInfo.AccessibilityAction.ACTION_PAGE_DOWN.id)
        assertClock(visible = true, anchor = "Plan windows")
        val list = taggedNode("plan-windows-list")
        val headerAtStart = bounds(checkNotNull(findText(list, "Plan windows")))
        val clockAtStart = bounds(taggedNode("app-clock"))
        val localContentAtStart = checkNotNull(nativeSurface("plan-windows-list")).content

        verticalDrag(forward = true)
        awaitAccessibility("Touch must move local content while Plan windows stays settled") { root ->
            val currentList = findNode(root) {
                it.isVisibleToUser && it.viewIdResourceName == "plan-windows-list"
            }
            val header = currentList?.let { findText(it, "Plan windows") }
            val clock = findNode(root) { it.isVisibleToUser && it.viewIdResourceName == "app-clock" }
            val localContent = nativeSurface("plan-windows-list")?.content
            nativeSurface("home-pager")?.atPage(1) == true && currentList != null &&
                !localContent.isNullOrEmpty() && localContent != localContentAtStart &&
                findNode(currentList) { it.collectionInfo?.rowCount == 3 } != null &&
                (header == null || bounds(header) != headerAtStart) &&
                clock != null && !clock.text.isNullOrBlank() && !bounds(clock).isEmpty &&
                findNode(root) { it.isVisibleToUser && it.viewIdResourceName == "glance-legend" } == null &&
                findText(root, "Alerts: 1") == null
        }
        scrollToStart(within = "plan-windows-list")
        assertPlanWindowsStart(headerAtStart, clockAtStart)
        assertClock(visible = true, anchor = "Plan windows")
        val localStart = taggedNode("plan-windows-list")
        assertTrue(
            "The touch paging gesture must start at the local backward boundary",
            findNode(localStart) { node ->
                node.actionList.any { it.id == AccessibilityNodeInfo.ACTION_SCROLL_BACKWARD }
            } == null && findNode(localStart) { node ->
                node.actionList.any { it.id == AccessibilityNodeInfo.ACTION_SCROLL_FORWARD }
            } != null,
        )
        verticalDrag(forward = false)
        assertClock(visible = false, anchor = "Codex Alpha")
        assertAbsent("Plan windows", anchor = "Codex Alpha")
        awaitAccessibility("Touch boundary paging must settle fully on Glance") { root ->
            val glance = findNode(root) { it.isVisibleToUser && it.viewIdResourceName == "glance-legend" }
            nativeSurface("home-pager")?.atPage(0) == true && glance != null &&
                findText(glance, "Codex Alpha") != null &&
                findButton(root, "Alerts: 1") != null &&
                findNode(root) { it.isVisibleToUser && it.viewIdResourceName == "app-clock" } == null &&
                findNode(root) { it.isVisibleToUser && it.viewIdResourceName == "plan-windows-list" } == null
        }
        val arrival = "Touch reached the tagged Glance at the native Pager start:${surfaceDiagnostics()}"
        scrollTrace += arrival
        arrival.lineSequence().forEach { Log.i("WardPulseNavigation", it) }
        // Explicit page navigation still works after an ordinary boundary drag.
        page(AccessibilityNodeInfo.AccessibilityAction.ACTION_PAGE_DOWN.id)
        assertClock(visible = true, anchor = "Plan windows")
    }

    @Test
    fun destinationClockMovesWithCancelledAndCompletedBackPreviewsOverGlance() {
        launchApp(alpha)
        assertClock(visible = false, anchor = "Codex Alpha")
        click("Alerts: 1")
        assertClock(visible = true, anchor = "Alerts")
        val root = checkNotNull(appRoot())
        val clockAtRest = bounds(checkNotNull(findNode(root) { it.viewIdResourceName == "app-clock" }))
        val titleAtRest = bounds(checkNotNull(findText(root, "Alerts")))

        for (cancelled in listOf(true, false)) {
            backPreview(cancelled) {
                awaitAccessibility("Clock must move or clip with the dismissing Alerts page") { preview ->
                    val title = findText(preview, "Alerts")
                    val clock = findNode(preview) {
                        it.isVisibleToUser && it.viewIdResourceName == "app-clock"
                    }
                    (title == null || bounds(title) != titleAtRest) &&
                        (clock == null || bounds(clock) != clockAtRest)
                }
            }
            if (cancelled) {
                assertClock(visible = true, anchor = "Alerts")
                awaitAccessibility("Cancelled dismissal must restore the Alerts clock") { restored ->
                    val clock = findNode(restored) { it.viewIdResourceName == "app-clock" && it.isVisibleToUser }
                    clock != null && bounds(clock) == clockAtRest && findText(restored, "Alerts") != null
                }
            } else {
                assertClock(visible = false, anchor = "Codex Alpha")
                assertAbsent("Alerts", anchor = "Codex Alpha")
            }
        }
    }

    private fun bounds(node: AccessibilityNodeInfo) = Rect().also { node.getBoundsInScreen(it) }

    private data class NativeSurface(
        val viewport: RectF,
        val scrollOffset: Float?,
        val maxScrollOffset: Float?,
        val rows: Int?,
        val pendingLayout: Boolean,
        val touchSlop: Float,
        val minimumFlingVelocity: Float,
        val content: List<Pair<String, Offset>>,
        val focused: Boolean?,
        val retainedFocusedBounds: RectF?,
        val inputFocus: List<String>,
        val homePagerState: HomePagerState?,
    ) {
        // Foundation's Pager semantic range is its absolute pixel scroll offset. For
        // these two fill-size pages, only the two endpoints represent page alignment.
        fun atPage(page: Int): Boolean = !pendingLayout && rows == 2 &&
            maxScrollOffset != null && maxScrollOffset > 0f &&
            scrollOffset == (if (page == 0) 0f else maxScrollOffset)
    }

    private fun nativeSurface(tag: String): NativeSurface? {
        var result: NativeSurface? = null
        onActivity { activity ->
            fun find(node: SemanticsNode): SemanticsNode? {
                if (!node.layoutInfo.isAttached || !node.layoutInfo.isPlaced) return null
                if (node.config.getOrNull(SemanticsProperties.TestTag) == tag) return node
                return node.children.firstNotNullOfOrNull { find(it) }
            }
            fun content(node: SemanticsNode): List<Pair<String, Offset>> = buildList {
                if (!node.layoutInfo.isAttached || !node.layoutInfo.isPlaced) return@buildList
                node.config.getOrNull(SemanticsProperties.Text)?.forEach {
                    add(it.text to node.positionOnScreen)
                }
                node.children.forEach { addAll(content(it)) }
            }
            fun inputFocus(node: SemanticsNode): List<String> = buildList {
                if (!node.layoutInfo.isAttached || !node.layoutInfo.isPlaced) return@buildList
                if (node.config.getOrNull(SemanticsProperties.Focused) == true) {
                    add(
                        "tag=${node.config.getOrNull(SemanticsProperties.TestTag)}, " +
                            "text=${content(node).map { it.first }}, " +
                            "position=${node.positionOnScreen}, size=${node.size}",
                    )
                }
                node.children.forEach { addAll(inputFocus(it)) }
            }
            fun visit(view: View) {
                if (view is ViewRootForTest) {
                    val node = find(view.semanticsOwner.unmergedRootSemanticsNode)
                    if (node != null) {
                        // Read actual measured size and placement, before accessibility
                        // clipping. AppScaffold overlays the clock on the fill-size Pager.
                        val origin = node.positionOnScreen
                        val range = node.config.getOrNull(SemanticsProperties.VerticalScrollAxisRange)
                        val config = node.layoutInfo.viewConfiguration
                        // This callback can retain live coordinates after focus is lost.
                        // Only Focused semantics above identify current input ownership.
                        val retainedFocusedBounds = focusedCoordinates?.takeIf { it.isAttached }?.let {
                            val position = it.positionOnScreen()
                            RectF(position.x, position.y, position.x + it.size.width, position.y + it.size.height)
                        }
                        result = NativeSurface(
                            RectF(origin.x, origin.y, origin.x + node.size.width, origin.y + node.size.height),
                            range?.value?.invoke(), range?.maxValue?.invoke(),
                            node.config.getOrNull(SemanticsProperties.CollectionInfo)?.rowCount,
                            view.hasPendingMeasureOrLayout, config.touchSlop, config.minimumFlingVelocity,
                            content(node),
                            node.config.getOrNull(SemanticsProperties.Focused),
                            retainedFocusedBounds,
                            inputFocus(view.semanticsOwner.unmergedRootSemanticsNode),
                            node.config.getOrNull(HomePagerStateKey),
                        )
                    }
                }
                if (result == null && view is ViewGroup) {
                    for (index in 0 until view.childCount) {
                        visit(view.getChildAt(index))
                        if (result != null) break
                    }
                }
            }
            visit(activity.window.decorView)
        }
        return result
    }

    private fun assertPlanWindowsStart(headerAtStart: Rect, clockAtStart: Rect) {
        awaitAccessibility("Plan windows must return to its owned local start with the complete header and clock") { root ->
            val pager = nativeSurface("home-pager")
            val local = nativeSurface("plan-windows-list")
            val list = findNode(root) { it.isVisibleToUser && it.viewIdResourceName == "plan-windows-list" }
            val header = list?.let { findText(it, "Plan windows") }
            val clock = findNode(root) { it.isVisibleToUser && it.viewIdResourceName == "app-clock" }
            val headerBounds = header?.let { bounds(it) }
            val clockBounds = clock?.let { bounds(it) }
            // Keep the complete original text dimensions, not its transformed y or
            // the dynamically clipped accessibility viewport, as the return contract.
            pager?.atPage(1) == true && list != null && headerBounds != null && clock != null && clockBounds != null &&
                local?.scrollOffset == 0f && local.maxScrollOffset != null && local.maxScrollOffset > 0f &&
                findNode(list) { it.collectionInfo?.rowCount == 3 } != null &&
                headerBounds.width() == headerAtStart.width() && headerBounds.height() == headerAtStart.height() &&
                pager.viewport.contains(
                    headerBounds.left.toFloat(), headerBounds.top.toFloat(),
                    headerBounds.right.toFloat(), headerBounds.bottom.toFloat(),
                ) &&
                !clock.text.isNullOrBlank() && !clockBounds.isEmpty &&
                clockBounds.width() == clockAtStart.width() && clockBounds.height() == clockAtStart.height() &&
                bounds(root).contains(clockBounds) && clockBounds.bottom <= headerBounds.top &&
                findNode(root) { it.isVisibleToUser && it.viewIdResourceName == "glance-legend" } == null &&
                findText(root, "Alerts: 1") == null && findNode(list) { node ->
                    node.actionList.any { it.id == AccessibilityNodeInfo.ACTION_SCROLL_BACKWARD }
                } == null && findNode(list) { node ->
                    node.actionList.any { it.id == AccessibilityNodeInfo.ACTION_SCROLL_FORWARD }
                } != null
        }
    }

    private fun surfaceDiagnostics(): String = buildString {
        appendLine("\nNative Pager=${nativeSurface("home-pager")}")
        appendLine("Native Glance=${nativeSurface("glance-legend")}")
        appendLine("Native Plan windows=${nativeSurface("plan-windows-list")}")
        val root = appRoot()
        if (root == null) {
            appendLine("No application accessibility root")
        } else {
            findNode(root) { node ->
                if (node.viewIdResourceName != null || !node.text.isNullOrBlank() || node.isScrollable) {
                    appendLine(
                        "id=${node.viewIdResourceName}, text=${node.text}, visible=${node.isVisibleToUser}, " +
                            "focused=${node.isFocused}, accessibilityFocused=${node.isAccessibilityFocused}, " +
                            "bounds=${bounds(node)}, scrollable=${node.isScrollable}, " +
                            "actions=${node.actionList.map { it.id }}, rows=${node.collectionInfo?.rowCount}, " +
                            "row=${node.collectionItemInfo?.rowIndex}",
                    )
                }
                false
            }
        }
    }

    private fun assertLegendOffset(message: String, condition: (Float, Float) -> Boolean) {
        awaitAccessibility(message) { root ->
            val legend = nativeSurface("glance-legend")
            // Observe the actual focus target, before clipping. Its rectangle must
            // stay at the viewport while content moves beneath it, even at either end.
            nativeSurface("home-pager")?.atPage(0) == true && legend?.focused == true &&
                legend.retainedFocusedBounds == legend.viewport &&
                legend.scrollOffset != null && legend.maxScrollOffset != null &&
                condition(legend.scrollOffset, legend.maxScrollOffset) &&
                findNode(root) { it.isVisibleToUser && it.viewIdResourceName == "glance-legend" } != null &&
                findNode(root) { it.isVisibleToUser && it.viewIdResourceName == "app-clock" } == null &&
                findNode(root) { it.isVisibleToUser && it.viewIdResourceName == "plan-windows-list" } == null
        }
    }

    private fun assertPlanRotaryFocus() {
        awaitAccessibility("Settled Plan windows must own rotary focus") { root ->
            nativeSurface("home-pager")?.atPage(1) == true &&
                nativeSurface("plan-windows-list")?.focused == true &&
                nativeSurface("glance-legend")?.focused != true &&
                findNode(root) { it.isVisibleToUser && it.viewIdResourceName == "plan-windows-list" } != null
        }
    }

    private fun assertOtherRouteFocus(anchor: String) {
        awaitAccessibility("$anchor must keep input focus outside the legend") { root ->
            findText(root, anchor) != null && nativeSurface("glance-legend")?.focused != true &&
                findNode(root) { it.isVisibleToUser && it.isFocused } != null
        }
    }

    private fun rotaryScroll(axisScroll: Float) {
        val now = SystemClock.uptimeMillis()
        val event = MotionEvent.obtain(
            now, now, MotionEvent.ACTION_SCROLL, 1,
            arrayOf(MotionEvent.PointerProperties().apply { id = 0 }),
            arrayOf(MotionEvent.PointerCoords().apply { setAxisValue(MotionEvent.AXIS_SCROLL, axisScroll) }),
            0, 0, 1f, 1f, 0, 0, InputDevice.SOURCE_ROTARY_ENCODER, 0,
        )
        try {
            // Native AXIS_SCROLL is negative forward; Compose converts it to pixels.
            scrollTrace += "native rotary axisScroll=$axisScroll"
            assertTrue("Native rotary input failed", automation.injectInputEvent(event, true))
        } finally {
            event.recycle()
        }
        awaitUi()
    }

    private fun verticalDrag(forward: Boolean) {
        taggedNode("home-pager")
        var alignedPager: NativeSurface? = null
        awaitAccessibility("Touch must begin on aligned Plan windows") {
            alignedPager = nativeSurface("home-pager")
            alignedPager?.atPage(1) == true
        }
        val pager = checkNotNull(alignedPager)
        val viewport = pager.viewport
        val x = viewport.centerX()
        // The intended 20%–80% stroke is 60% of the native page, not of its
        // accessibility rectangle. Keep ordinary frame-paced touch input and release.
        val startY = viewport.top + viewport.height() * (if (forward) 0.8f else 0.2f)
        val endY = viewport.top + viewport.height() * (if (forward) 0.2f else 0.8f)
        val before = surfaceDiagnostics()
        val traceStart = scrollTrace.size
        val velocity = VelocityTracker()
        val downTime = SystemClock.uptimeMillis()
        fun pointer(action: Int, y: Float) {
            val event = MotionEvent.obtain(downTime, SystemClock.uptimeMillis(), action, x, y, 0)
            try {
                event.source = InputDevice.SOURCE_TOUCHSCREEN
                assertTrue("Vertical touch input failed", automation.injectInputEvent(event, true))
                velocity.addPosition(event.eventTime, Offset(x, y))
                scrollTrace += "touch action=$action, elapsed=${event.eventTime - downTime}ms, x=$x, y=$y"
            } finally {
                event.recycle()
            }
        }
        pointer(MotionEvent.ACTION_DOWN, startY)
        var beforeRelease: NativeSurface? = null
        try {
            for (step in 1..12) {
                pointer(MotionEvent.ACTION_MOVE, startY + (endY - startY) * step / 12)
                awaitFrame()
                if (step == 6 || step == 12) {
                    scrollTrace += "touch step=$step, native Pager=${nativeSurface("home-pager")}, " +
                        "native local=${nativeSurface("plan-windows-list")}"
                }
            }
            beforeRelease = nativeSurface("home-pager")
        } finally {
            pointer(MotionEvent.ACTION_UP, endY)
            // This estimates the injected pointer velocity, not the velocity delivered
            // through the child's nested fling. Arrival is asserted separately below.
            val injectedVelocity = velocity.calculateVelocity().y
            awaitUi()
            val pagerTravelFraction = beforeRelease?.scrollOffset?.let { end ->
                pager.scrollOffset?.let { start -> (end - start) / viewport.height() }
            }
            val diagnostic = "touch forward=$forward, viewport=$viewport, startY=$startY, endY=$endY, " +
                "strokeFraction=${kotlin.math.abs(endY - startY) / viewport.height()}, " +
                "touchSlop=${pager.touchSlop}, minimumFlingVelocity=${pager.minimumFlingVelocity}, " +
                "injectedVelocityY=$injectedVelocity, pagerTravelFraction=$pagerTravelFraction, " +
                "defaultSnapPositionalThreshold=0.5, beforeRelease=$beforeRelease\n" +
                scrollTrace.drop(traceStart).joinToString("\n", postfix = "\n") +
                "Before touch:$before\nAfter UP and UI synchronization:${surfaceDiagnostics()}"
            scrollTrace += diagnostic
            diagnostic.lineSequence().forEach { Log.i("WardPulseNavigation", it) }
        }
    }

    private fun backPreview(cancelled: Boolean, touchOnly: Boolean = false, duringPreview: () -> Unit) {
        var inspected = false
        if (Build.VERSION.SDK_INT > 35 && !touchOnly) {
            // Wear's API 36+ host uses the Activity's predictive-back callback.
            onActivity { activity ->
                activity.onBackPressedDispatcher.dispatchOnBackStarted(
                    BackEventCompat(0f, 0f, 0f, BackEventCompat.EDGE_LEFT),
                )
            }
            try {
                onActivity { activity ->
                    activity.onBackPressedDispatcher.dispatchOnBackProgressed(
                        BackEventCompat(0f, 0f, 0.75f, BackEventCompat.EDGE_LEFT),
                    )
                }
                awaitUi()
                duringPreview()
                inspected = true
            } finally {
                onActivity { activity ->
                    if (cancelled || !inspected) {
                        activity.onBackPressedDispatcher.dispatchOnBackCancelled()
                    } else {
                        activity.onBackPressedDispatcher.onBackPressed()
                    }
                }
                awaitUi()
            }
        } else {
            // Earlier Wear hosts consume horizontal touch dragging, rather than
            // predictive-back progress. Hold the pointer while inspecting the preview.
            val window = if (touchOnly) {
                checkNotNull(nativeSurface("home-pager")).viewport
            } else {
                RectF(bounds(checkNotNull(appRoot())))
            }
            val startX = window.left + window.width() * 0.05f
            val endX = window.left + window.width() * 0.8f
            val y = window.centerY()
            val downTime = SystemClock.uptimeMillis()
            fun pointer(action: Int, x: Float) {
                val event = MotionEvent.obtain(downTime, SystemClock.uptimeMillis(), action, x, y, 0)
                try {
                    event.source = InputDevice.SOURCE_TOUCHSCREEN
                    assertTrue("Back gesture input failed", automation.injectInputEvent(event, true))
                } finally {
                    event.recycle()
                }
            }
            pointer(MotionEvent.ACTION_DOWN, startX)
            try {
                for (step in 1..12) {
                    pointer(MotionEvent.ACTION_MOVE, startX + (endX - startX) * step / 12)
                    awaitFrame()
                }
                awaitUi()
                duringPreview()
                inspected = true
            } finally {
                if (cancelled || !inspected) {
                    for (step in 1..12) {
                        pointer(MotionEvent.ACTION_MOVE, endX + (startX - endX) * step / 12)
                        awaitFrame()
                    }
                    pointer(MotionEvent.ACTION_CANCEL, startX)
                } else {
                    pointer(MotionEvent.ACTION_UP, endX)
                }
                awaitUi()
            }
        }
    }

    private fun launchProduction(initialSummary: WatchDashboardSummary?, entry: Intent = launcherIntent()) {
        val context = instrumentation.targetContext
        val preferences = context.getSharedPreferences("watch_summary", Context.MODE_PRIVATE)
        originalSavedSummary = preferences.getString("latest", null)
        savedSummaryPreferences = preferences
        if (initialSummary == null) {
            assertTrue(preferences.edit().remove("latest").commit())
        } else {
            WatchSummaryStore(context).save(initialSummary)
        }
        // Isolate only this test's task; do not clear or adopt historical retained owners.
        // ActivityScenario filters lifecycle events by the original intent action/categories.
        // Production setIntent() changes those, so track these owners by identity and task instead.
        instrumentation.runOnMainSync {
            ActivityLifecycleMonitorRegistry.getInstance().addLifecycleCallback(ownerLifecycle)
            context.startActivity(
                entry.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_MULTIPLE_TASK),
            )
        }
        awaitOwnerState("Initial production owner must be resumed") {
            var resumed = false
            instrumentation.runOnMainSync {
                resumed = productionOwners.singleOrNull()?.lifecycle?.currentState == Lifecycle.State.RESUMED
            }
            resumed
        }
        awaitUi()
    }

    private fun onActivity(action: (MainActivity) -> Unit) {
        if (productionTaskId == null) {
            scenario.onActivity { action(it) }
        } else {
            instrumentation.runOnMainSync {
                val owner = checkNotNull(productionOwners.lastOrNull {
                    it.taskId == productionTaskId && !it.isDestroyed
                }) { "No live production owner in task $productionTaskId" }
                action(owner)
            }
        }
    }

    private fun recreateProductionOwner() {
        val previous = productionOwner()
        onActivity { it.recreate() }
        awaitOwnerState("Production recreation must destroy the old owner and resume its replacement") {
            var recreated = false
            instrumentation.runOnMainSync {
                val current = productionOwners.lastOrNull { it.taskId == productionTaskId && !it.isDestroyed }
                recreated = previous.isDestroyed && current != null && current !== previous &&
                    current.lifecycle.currentState == Lifecycle.State.RESUMED
            }
            recreated
        }
        awaitUi()
    }

    private fun launcherIntent() = Intent.makeMainActivity(
        ComponentName(instrumentation.targetContext, MainActivity::class.java),
    )

    private fun faceIntent() = Intent(instrumentation.targetContext, MainActivity::class.java)
        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)

    private fun deliverEntry(intent: Intent) {
        // These are production-owner regression inputs, not proof of actual WFF/launcher taps.
        val receipt = ++entrySequence
        val receiptKey = "wardpulse.navigation.test.entry"
        onActivity { it.startActivity(intent.putExtra(receiptKey, receipt)) }
        awaitOwnerState("Entry $receipt must reach a resumed owner: $intent") {
            var delivered = false
            instrumentation.runOnMainSync {
                delivered = ActivityLifecycleMonitorRegistry.getInstance().getActivitiesInStage(Stage.RESUMED)
                    .filterIsInstance<MainActivity>()
                    .any { it.intent.getLongExtra(receiptKey, -1L) == receipt }
            }
            delivered
        }
        awaitUi()
    }

    private fun productionOwner(): MainActivity {
        lateinit var owner: MainActivity
        onActivity { owner = it }
        return owner
    }

    private fun productionModel(owner: MainActivity): WatchFaceViewModel {
        lateinit var model: WatchFaceViewModel
        instrumentation.runOnMainSync { model = ViewModelProvider(owner)[WatchFaceViewModel::class.java] }
        return model
    }

    private fun assertProductionUtility() {
        assertClock(visible = true, anchor = "Watch face")
        awaitAccessibility("Watch face must be the utility header, not the Home entry button") { root ->
            findText(root, "Watch face") != null && findButton(root, "Watch face") == null &&
                nativeSurface("home-pager")?.homePagerState?.lifecycle != Lifecycle.State.RESUMED
        }
    }

    private fun awaitHomeViewport(viewport: RectF) {
        awaitAccessibility("Home must restore its native viewport after the root gesture") {
            nativeSurface("home-pager")?.let { home ->
                !home.pendingLayout && home.viewport == viewport
            } == true
        }
    }

    private fun assertProductionOwner(owner: MainActivity, creations: Int = 1) {
        onActivity { current ->
            assertSame(owner, current)
            assertEquals(productionTaskId, current.taskId)
            assertFalse(current.isFinishing)
            assertFalse(current.isDestroyed)
            val resumed = ActivityLifecycleMonitorRegistry.getInstance().getActivitiesInStage(Stage.RESUMED)
                .filterIsInstance<MainActivity>()
            assertEquals(listOf(owner), resumed)
            assertEquals(creations, productionOwners.size)
            assertEquals(setOf(productionTaskId), productionOwners.map { it.taskId }.toSet())
            Log.i(
                "WardPulseNavigation",
                "owner=${System.identityHashCode(current)}, task=${current.taskId}, " +
                    "creations=$creations, delivered=${current.intent}",
            )
        }
    }

    private fun awaitBackground(owner: MainActivity) {
        awaitOwnerState("One dismissal must background the retained owner/task") {
            var stopped = false
            instrumentation.runOnMainSync {
                stopped = !owner.lifecycle.currentState.isAtLeast(Lifecycle.State.STARTED) && !owner.hasWindowFocus()
            }
            stopped && appRoot() == null
        }
        instrumentation.runOnMainSync {
            assertFalse(owner.isFinishing)
            assertFalse(owner.isDestroyed)
        }
    }

    private fun awaitOwnerState(message: String, condition: () -> Boolean) {
        val deadline = SystemClock.uptimeMillis() + 5_000
        fun failure(): Nothing {
            var owners = ""
            instrumentation.runOnMainSync {
                owners = productionOwners.joinToString { owner ->
                    "${System.identityHashCode(owner)}/task=${owner.taskId}/state=${owner.lifecycle.currentState}/" +
                        "finishing=${owner.isFinishing}/destroyed=${owner.isDestroyed}"
                }
            }
            throw AssertionError("$message; ownedTask=$productionTaskId, owners=[$owners]")
        }
        while (SystemClock.uptimeMillis() < deadline) {
            if (condition()) return
            val remaining = deadline - SystemClock.uptimeMillis()
            if (remaining <= 0) break
            awaitFrame(remaining, onTimeout = ::failure)
        }
        failure()
    }

    private fun launchApp(
        initialSummary: WatchDashboardSummary? = null,
        fontScale: Float? = null,
        content: (@Composable () -> Unit)? = null,
        onDismissHome: () -> Unit = {},
    ) {
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
                val density = LocalDensity.current
                CompositionLocalProvider(
                    LocalDensity provides Density(density.density, fontScale ?: density.fontScale),
                ) {
                    WardPulseTheme {
                        Box(Modifier.fillMaxSize().onFocusedBoundsChanged { focusedCoordinates = it }) {
                            if (content != null) {
                                content()
                            } else {
                                WardPulseApp(
                                    summary = summary,
                                    watchFaceState = watchFaceState,
                                    onCheckWatchFace = callbacks.onCheck,
                                    onInstallWatchFace = callbacks.onInstall,
                                    onUpdateWatchFace = callbacks.onUpdate,
                                    onUseWatchFace = callbacks.onUse,
                                    onDismissHome = onDismissHome,
                                )
                            }
                        }
                    }
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
        // Production-owner cases keep MainActivity's own window Recomposer/composition.
        if (::recomposer.isInitialized) runBlocking { withTimeout(5_000) { recomposer.awaitIdle() } }
        instrumentation.waitForIdleSync()
        // Callback-only changes need not emit accessibility events. Assertions below wait
        // for their own observable state instead of treating event quiet as publication.
    }

    private fun awaitFrame(
        timeoutMillis: Long = 5_000,
        onTimeout: () -> Nothing = { throw AssertionError("UI frame did not complete") },
    ) {
        val frame = CountDownLatch(1)
        instrumentation.runOnMainSync {
            Choreographer.getInstance().postFrameCallback { frame.countDown() }
        }
        if (!frame.await(timeoutMillis, TimeUnit.MILLISECONDS)) onTimeout()
    }

    private fun awaitAccessibility(
        message: String,
        diagnostics: () -> String = { "" },
        condition: (AccessibilityNodeInfo) -> Boolean,
    ) {
        val deadline = SystemClock.uptimeMillis() + 5_000
        fun failure(): Nothing {
            val state = runCatching { surfaceDiagnostics() }.getOrElse { "\nSurface diagnostics failed: $it" }
            throw AssertionError(message + diagnostics() + "\n${scrollTrace.joinToString("\n")}" + state)
        }
        while (SystemClock.uptimeMillis() < deadline) {
            val root = appRoot()
            if (root != null && condition(root)) return
            val remaining = deadline - SystemClock.uptimeMillis()
            if (remaining <= 0) break
            // A final partial vsync belongs to this predicate's deadline. It must
            // not replace the useful assertion and state with a frame-latch failure.
            awaitFrame(remaining, onTimeout = ::failure)
        }
        failure()
    }

    private fun back(toHomePage: Int? = null) {
        instrumentation.sendKeyDownUpSync(KeyEvent.KEYCODE_BACK)
        if (toHomePage == null) awaitUi() else awaitHomePage(toHomePage)
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

    private fun taggedNode(tag: String, action: Int? = null): AccessibilityNodeInfo {
        var result: AccessibilityNodeInfo? = null
        awaitAccessibility("Expected $tag with accessibility action $action") { root ->
            val owner = findNode(root) { it.isVisibleToUser && it.viewIdResourceName == tag }
            // Scroll semantics can be published on an untagged descendant of their owner.
            result = owner?.let {
                if (action == null) it else findNode(it) { node ->
                    node.isVisibleToUser && node.actionList.any { it.id == action }
                }
            }
            result != null
        }
        return checkNotNull(result)
    }

    private fun page(action: Int) {
        val node = taggedNode("home-pager", action)
        assertTrue("Home Pager action failed: $action", performHomePagerAction(node, action))
    }

    private fun homePagerObservation(pager: NativeSurface?): String =
        "state=${pager?.homePagerState}, offset=${pager?.scrollOffset}/${pager?.maxScrollOffset}, " +
            "pendingLayout=${pager?.pendingLayout}, inputFocus=${pager?.inputFocus}, " +
            "retainedFocusedBounds=${pager?.retainedFocusedBounds}"

    private fun recordHomePager(message: String) {
        val observation = "$message: ${homePagerObservation(nativeSurface("home-pager"))}"
        scrollTrace += observation
        Log.i("WardPulseNavigation", observation)
    }

    private fun awaitHomePage(page: Int, focusedGlanceControl: String? = null) {
        val started = SystemClock.uptimeMillis()
        val trace = ArrayDeque<String>()
        var previous: String? = null
        awaitAccessibility(
            "Expected resumed Home at settled page $page, focusedGlanceControl=$focusedGlanceControl",
            diagnostics = { "\nHome settlement observations:\n${trace.joinToString("\n")}" },
        ) { root ->
            val pager = nativeSurface("home-pager")
            val state = pager?.homePagerState
            val local = nativeSurface(if (page == 0) "glance-legend" else "plan-windows-list")
            val controlFocused = focusedGlanceControl?.let { findButton(root, it)?.isFocused }
            val observation = "${homePagerObservation(pager)}, localFocused=${local?.focused}, " +
                "localMax=${local?.maxScrollOffset}, controlFocused=$controlFocused"
            if (observation != previous) {
                // Retain bounded state changes, including transient focus and page targets.
                if (trace.size == 32) trace.removeFirst()
                trace.addLast("page=$page +${SystemClock.uptimeMillis() - started}ms: $observation")
                previous = observation
            }
            pager?.atPage(page) == true && state != null && state.lifecycle == Lifecycle.State.RESUMED &&
                !state.scrolling && state.currentPage == page && state.settledPage == page &&
                state.targetPage == page && state.offsetFraction == 0f &&
                (page != 1 || local?.focused == true) &&
                (focusedGlanceControl == null || (page == 0 && local != null && local.maxScrollOffset == null &&
                    local.focused != true && controlFocused == true))
        }
        trace.forEach {
            scrollTrace += it
            Log.i("WardPulseNavigation", it)
        }
    }

    private fun performHomePagerAction(
        node: AccessibilityNodeInfo,
        action: Int,
        focusedGlanceControl: String? = null,
    ): Boolean {
        val destination = when (action) {
            AccessibilityNodeInfo.ACTION_SCROLL_FORWARD,
            AccessibilityNodeInfo.AccessibilityAction.ACTION_PAGE_DOWN.id -> 1
            AccessibilityNodeInfo.ACTION_SCROLL_BACKWARD,
            AccessibilityNodeInfo.AccessibilityAction.ACTION_PAGE_UP.id -> 0
            else -> error("Unexpected Home Pager action: $action")
        }
        awaitHomePage(1 - destination, focusedGlanceControl)
        recordHomePager("before action=$action owner=${node.viewIdResourceName} to page=$destination")
        assertTrue("Home Pager action owner disappeared: $action", node.refresh())
        if (focusedGlanceControl != null) {
            assertTrue(
                "Focused-control forward paging must expose the native PageDown dispatch",
                node.actionList.any { it.id == AccessibilityNodeInfo.AccessibilityAction.ACTION_PAGE_DOWN.id },
            )
        }
        val performed = node.performAction(action)
        recordHomePager("after action=$action to page=$destination, performed=$performed")
        if (performed) awaitHomePage(destination)
        return performed
    }

    private fun assertClock(visible: Boolean, anchor: String) {
        var observation = "No application accessibility root observed"
        awaitAccessibility(
            "Expected clock visible=$visible on $anchor",
            diagnostics = { "\nLast evaluated clock/anchor state: $observation" },
        ) { root ->
            val clock = findNode(root) { it.viewIdResourceName == "app-clock" && it.isVisibleToUser }
            val bounds = Rect()
            clock?.getBoundsInScreen(bounds)
            val showingTime = clock != null && !clock.text.isNullOrBlank() && !bounds.isEmpty
            val anchored = findText(root, anchor) != null
            observation = "anchorVisible=$anchored, clockVisible=${clock != null}, " +
                "showingTime=$showingTime, clockText=${clock?.text}, clockBounds=$bounds"
            anchored && (if (visible) showingTime else clock == null)
        }
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

    private fun click(text: String, within: String? = null) {
        reveal(text, within)
        var node = checkNotNull(findText(text)) { "Missing action: $text" }
        while (!node.actionList.contains(AccessibilityNodeInfo.AccessibilityAction.ACTION_CLICK)) {
            node = checkNotNull(node.parent?.takeIf { it.refresh() }) { "No click action for: $text" }
        }
        assertTrue("Disabled action: $text", node.isEnabled)
        assertTrue("Click failed: $text", node.performAction(AccessibilityNodeInfo.ACTION_CLICK))
        awaitUi()
    }

    private fun reveal(text: String, within: String? = null) {
        // Bounded user scrolling through a lazy list, never navigation or state retries.
        repeat(8) {
            if (hasText(text)) return
            check(scroll(AccessibilityNodeInfo.ACTION_SCROLL_FORWARD, within)) { "Cannot reveal: $text" }
        }
        assertVisible(text)
    }

    private fun scrollToStart(within: String? = null) {
        scrollTrace += "scrollToStart within=$within"
        repeat(8) {
            if (!scroll(AccessibilityNodeInfo.ACTION_SCROLL_BACKWARD, within)) return
        }
        error("Scrollable content did not reach the start\n${scrollTrace.joinToString("\n")}")
    }

    private fun scrollToEnd(within: String) {
        scrollTrace += "scrollToEnd within=$within"
        repeat(8) {
            if (!scroll(AccessibilityNodeInfo.ACTION_SCROLL_FORWARD, within)) return
        }
        error("Scrollable content did not reach the end\n${scrollTrace.joinToString("\n")}")
    }

    private fun scroll(action: Int, within: String? = null, focusedGlanceControl: String? = null): Boolean {
        val verifyPlanWindows = within == "plan-windows-list"
        var content = emptyList<Pair<String, Rect>>()
        var nativeContent = emptyList<Pair<String, Offset>>()
        var observation = "No Plan windows state observed"
        val observePlanWindows: (AccessibilityNodeInfo) -> Boolean = { root ->
            val list = findNode(root) { it.isVisibleToUser && it.viewIdResourceName == within }
            val pager = findNode(root) { it.isVisibleToUser && it.viewIdResourceName == "home-pager" }
            val glance = findNode(root) { it.isVisibleToUser && it.viewIdResourceName == "glance-legend" }
            val clock = findNode(root) { it.isVisibleToUser && it.viewIdResourceName == "app-clock" }
            val collection = list?.let { findNode(it) { node -> node.collectionInfo?.rowCount == 3 } }
            content = buildList {
                if (list != null) findNode(list) { node ->
                    if (node.isVisibleToUser && !node.text.isNullOrBlank()) {
                        add(node.text.toString() to bounds(node))
                    }
                    false
                }
            }
            val listBounds = list?.let { bounds(it) }
            val nativePager = nativeSurface("home-pager")
            val nativeLocal = nativeSurface("plan-windows-list")
            nativeContent = nativeLocal?.content.orEmpty()
            val showingTime = clock != null && !clock.text.isNullOrBlank() && !bounds(clock).isEmpty
            observation = "pagerBounds=${pager?.let { bounds(it) }}, listBounds=$listBounds, " +
                "rows=${collection?.collectionInfo?.rowCount}, showingTime=$showingTime, " +
                "glanceVisible=${glance != null}, nativePager=$nativePager, nativeLocal=$nativeLocal, content=$content"
            pager != null && nativePager?.atPage(1) == true && list != null &&
                collection != null && showingTime && glance == null &&
                findText(root, "Alerts: 1") == null && content.isNotEmpty()
        }
        if (verifyPlanWindows) {
            awaitAccessibility(
                "Expected settled Plan windows before local action $action",
                diagnostics = { "\n$observation\n${scrollTrace.joinToString("\n")}" },
                condition = observePlanWindows,
            )
            scrollTrace += "before action=$action, $observation"
        }
        val before = content
        val nativeBefore = nativeContent
        val root = appRoot()
        val owner = if (within == null) root else root?.let {
            findNode(it) { candidate -> candidate.isVisibleToUser && candidate.viewIdResourceName == within }
        }
        if (within != null) checkNotNull(owner) { "Missing local list owner: $within" }
        // Scoped local actions include untagged aliases inside the list owner only.
        val node = owner?.let {
            findNode(it) { candidate ->
                candidate.isVisibleToUser && candidate.actionList.any { it.id == action }
            }
        }
        val target = node?.toString()
        val homePagerAction = node?.viewIdResourceName == "home-pager"
        if (focusedGlanceControl != null) {
            assertTrue("Focused-control paging must target Home Pager", homePagerAction)
        }
        val performed = if (homePagerAction) {
            performHomePagerAction(checkNotNull(node), action, focusedGlanceControl)
        } else node?.performAction(action) ?: false
        scrollTrace += "action=$action, within=$within, owner=${owner?.viewIdResourceName}, rootPresent=${root != null}, " +
            "target=$target, performed=$performed"
        if (performed) {
            if (!homePagerAction) awaitUi()
            if (verifyPlanWindows) {
                awaitAccessibility(
                    "Expected local content movement on settled Plan windows after action $action",
                    diagnostics = { "\n$observation\n${scrollTrace.joinToString("\n")}" },
                ) { updated ->
                    observePlanWindows(updated) && content.toSet() != before.toSet() &&
                        nativeBefore.isNotEmpty() && nativeContent.isNotEmpty() && nativeContent != nativeBefore
                }
                scrollTrace += "after action=$action, $observation"
            }
        } else if (root != null) {
            if (verifyPlanWindows) {
                awaitAccessibility(
                    "Expected settled Plan windows at the local boundary after action $action",
                    diagnostics = { "\n$observation\n${scrollTrace.joinToString("\n")}" },
                    condition = observePlanWindows,
                )
                scrollTrace += "boundary action=$action, $observation"
            }
            // Record published content at the stop without issuing another action or waiting
            // for a missing action to appear. Its absence is not proof of list position.
            findNode(root) { candidate ->
                if (candidate.isVisibleToUser && !candidate.text.isNullOrBlank()) {
                    scrollTrace += "text=${candidate.text}, bounds=${bounds(candidate)}"
                }
                false
            }
        }
        return performed
    }

    private fun appRoot(): AccessibilityNodeInfo? {
        val root = automation.rootInActiveWindow ?: return null
        return root.takeIf {
            it.refresh() && it.isVisibleToUser && it.packageName?.toString() == instrumentation.targetContext.packageName
        }
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

    private fun overflowingSummary() = alpha.copy(
        rings = listOf(
            RingSummary("allowance.codex.plan", "Codex Alpha", 25.0, PulseStatus.OK),
            RingSummary("allowance.cursor.plan", "Cursor Beta", 20.0, PulseStatus.OK),
            RingSummary("allowance.claude.plan", "Claude Gamma", 0.0, PulseStatus.OK),
        ),
    )

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
