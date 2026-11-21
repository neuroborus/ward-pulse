package app.wardpulse.wear.watchface

import android.content.Context
import android.content.Intent
import android.os.SystemClock
import android.util.Xml
import android.view.Choreographer
import androidx.lifecycle.Lifecycle
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.runner.lifecycle.ActivityLifecycleCallback
import androidx.test.runner.lifecycle.ActivityLifecycleMonitorRegistry
import androidx.test.runner.lifecycle.Stage
import app.wardpulse.wear.IsolatedActivityRule
import app.wardpulse.wear.MainActivity
import app.wardpulse.wear.WatchFaceViewModel
import java.io.File
import java.util.concurrent.Callable
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotSame
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.xmlpull.v1.XmlPullParser

@RunWith(AndroidJUnit4::class)
class WatchFaceConsentStoreTest {
    @get:Rule
    internal val isolation = IsolatedActivityRule()

    private val instrumentation = InstrumentationRegistry.getInstrumentation()
    private val context = ApplicationProvider.getApplicationContext<Context>()
    private val preferencesName = "watch_face_consent_test_${System.nanoTime()}"
    private val preferences = context.getSharedPreferences(preferencesName, Context.MODE_PRIVATE)
    private val owners = mutableListOf<MainActivity>()
    private val ownerLifecycle = ActivityLifecycleCallback { activity, stage ->
        if (activity is MainActivity && stage == Stage.CREATED) owners += activity
    }

    @After
    fun cleanUp() {
        context.deleteSharedPreferences(preferencesName)
    }

    @Test
    fun freshStoreAllowsAnExplicitUseAction() {
        assertEquals(WatchFaceConsent.Eligible, WatchFaceConsentStore(preferences).read())
    }

    @Test
    fun permissionAndActivationHistoryIsDurableBeforeClaimReturns() {
        val store = WatchFaceConsentStore(preferences)
        for ((expected, history) in listOf(
            WatchFaceConsent.Eligible to WatchFaceConsent.PermissionPending,
            WatchFaceConsent.PermissionPending to WatchFaceConsent.PermissionDeclined,
            WatchFaceConsent.Eligible to WatchFaceConsent.ActivationAttempted,
            WatchFaceConsent.PermissionPending to WatchFaceConsent.ActivationAttempted,
        )) {
            assertTrue(preferences.edit().putString("history", expected.name).commit())
            assertTrue(store.compareAndSet(expected, history))
            assertEquals(history, WatchFaceConsentStore(preferences).read())
            // Reopening preferences alone reads Android's memory cache. Inspect disk as well:
            // the marker must survive process death before permission/activation can proceed.
            assertEquals(history.name, persistedHistory())
            assertFalse(WatchFaceConsentStore(preferences).compareAndSet(expected, history))
            assertEquals(history.name, persistedHistory())
        }
    }

    @Test
    fun separateStoppedAndResumedActivityOwnersShareExclusiveDurableClaims() {
        val productionPreferences = isolation.scope.consentPreferences
        val originalHistory = productionPreferences.getString("history", null)
        val executor = Executors.newFixedThreadPool(2).also { isolation.scope.track(it) }
        try {
            instrumentation.runOnMainSync {
                ActivityLifecycleMonitorRegistry.getInstance().addLifecycleCallback(ownerLifecycle)
            }
            val first = launchOwner()
            instrumentation.runOnMainSync { assertTrue(first.moveTaskToBack(true)) }
            awaitOwnerState("First production owner must be stopped before the second launch") { isStopped(first) }
            val second = launchOwner()
            awaitOwnerState("First owner must stay stopped while the second resumes") {
                isStopped(first) && second.lifecycle.currentState == Lifecycle.State.RESUMED
            }

            val models = mutableListOf<WatchFaceViewModel>()
            val controllers = mutableListOf<WatchFaceController>()
            val stores = mutableListOf<WatchFaceConsentStore>()
            val taskIds = mutableListOf<Int>()
            instrumentation.runOnMainSync {
                for (activity in listOf(first, second)) {
                    // Follow the actual private construction path; do not substitute test owners/stores.
                    val model = MainActivity::class.java.getDeclaredMethod("getWatchFace").apply {
                        isAccessible = true
                    }.invoke(activity) as WatchFaceViewModel
                    val controller = WatchFaceViewModel::class.java.getDeclaredField("controller").apply {
                        isAccessible = true
                    }.get(model) as WatchFaceController
                    val store = WatchFaceController::class.java.getDeclaredField("consent").apply {
                        isAccessible = true
                    }.get(controller) as WatchFaceConsentStore
                    models += model
                    controllers += controller
                    stores += store
                    taskIds += activity.taskId
                }
                assertNotSame(first, second)
                assertEquals(Lifecycle.State.CREATED, first.lifecycle.currentState)
                assertEquals(Lifecycle.State.RESUMED, second.lifecycle.currentState)
                assertEquals(2, taskIds.toSet().size)
                assertNotSame(models[0], models[1])
                assertNotSame(controllers[0], controllers[1])
                assertNotSame(stores[0], stores[1])
                isolation.scope.assertStorageIsPrivate()
                val backing = WatchFaceConsentStore::class.java.getDeclaredField("preferences").apply {
                    isAccessible = true
                }
                stores.forEach { assertSame(productionPreferences, backing.get(it)) }
            }

            instrumentation.runOnMainSync { second.recreate() }
            var recreated: MainActivity? = null
            awaitOwnerState("Second owner must be destroyed and its replacement resumed in the same task") {
                recreated = owners.singleOrNull { it.taskId == taskIds[1] && !it.isDestroyed }
                second.isDestroyed && recreated != null && recreated !== second &&
                    recreated?.lifecycle?.currentState == Lifecycle.State.RESUMED && isStopped(first)
            }
            instrumentation.runOnMainSync {
                val retained = MainActivity::class.java.getDeclaredMethod("getWatchFace").apply {
                    isAccessible = true
                }.invoke(checkNotNull(recreated))
                assertSame(models[1], retained)
            }

            for ((expected, history) in listOf(
                WatchFaceConsent.Eligible to WatchFaceConsent.PermissionPending,
                WatchFaceConsent.Eligible to WatchFaceConsent.ActivationAttempted,
                WatchFaceConsent.PermissionPending to WatchFaceConsent.ActivationAttempted,
                WatchFaceConsent.PermissionPending to WatchFaceConsent.PermissionDeclined,
            )) {
                assertTrue(productionPreferences.edit().putString("history", expected.name).commit())
                stores.forEach { assertEquals(expected, it.read()) }
                val ready = CountDownLatch(2)
                val release = CountDownLatch(1)
                val effects = AtomicInteger()
                val claims = stores.map { store ->
                    executor.submit(Callable {
                        ready.countDown()
                        assertTrue(release.await(5, TimeUnit.SECONDS))
                        val claimed = store.compareAndSet(expected, history)
                        if (claimed) {
                            // Prove durability before allowing the winning owner's effect.
                            assertEquals(history.name, persistedHistory(isolation.scope.consentName))
                            effects.incrementAndGet()
                        }
                        claimed
                    })
                }
                try {
                    assertTrue(ready.await(5, TimeUnit.SECONDS))
                    release.countDown()
                    assertEquals(1, claims.count { it.get(5, TimeUnit.SECONDS) })
                    assertEquals(1, effects.get())
                    stores.forEach { assertEquals(history, it.read()) }
                    assertFalse(stores[0].compareAndSet(expected, history))
                    assertEquals(history.name, persistedHistory(isolation.scope.consentName))
                    isolation.scope.assertStorageIsPrivate()
                } finally {
                    release.countDown()
                    claims.forEach { it.cancel(true) }
                }
            }
        } finally {
            try {
                finishOwners()
            } finally {
                executor.shutdownNow()
                try {
                    assertTrue(executor.awaitTermination(5, TimeUnit.SECONDS))
                } finally {
                    val editor = productionPreferences.edit()
                    if (originalHistory == null) editor.remove("history") else editor.putString("history", originalHistory)
                    assertTrue(editor.commit())
                }
            }
        }
    }

    @Test
    fun unrecognizedHistoryCannotRestoreConsentEligibility() {
        assertTrue(preferences.edit().putString("history", "unrecognized").commit())

        assertEquals(WatchFaceConsent.ActivationAttempted, WatchFaceConsentStore(preferences).read())
        assertFalse(WatchFaceConsentStore(preferences).compareAndSet(
            WatchFaceConsent.Eligible,
            WatchFaceConsent.PermissionPending,
        ))
        assertEquals("unrecognized", persistedHistory())
    }

    private fun launchOwner(): MainActivity {
        var creations = 0
        instrumentation.runOnMainSync {
            creations = owners.size
            // Ordinary launch keeps lifecycle waits bounded even if singleTop redelivers the Intent.
            context.startActivity(Intent(context, MainActivity::class.java).addFlags(
                Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_MULTIPLE_TASK,
            ))
        }
        var launched: MainActivity? = null
        awaitOwnerState("Launch must create and resume one new production owner (previous creations=$creations)") {
            launched = owners.drop(creations).singleOrNull()
            launched?.lifecycle?.currentState == Lifecycle.State.RESUMED
        }
        instrumentation.runOnMainSync { isolation.scope.assertRefreshDispatched(checkNotNull(launched)) }
        return checkNotNull(launched)
    }

    private fun isStopped(owner: MainActivity): Boolean =
        owner.lifecycle.currentState == Lifecycle.State.CREATED && !owner.isFinishing && !owner.isDestroyed &&
            !owner.hasWindowFocus() &&
            ActivityLifecycleMonitorRegistry.getInstance().getActivitiesInStage(Stage.STOPPED).any { it === owner }

    private fun finishOwners() {
        try {
            instrumentation.runOnMainSync {
                owners.filterNot { it.isDestroyed }.forEach { it.finish() }
            }
            awaitOwnerState("All production test owners must be destroyed") { owners.all { it.isDestroyed } }
        } finally {
            instrumentation.runOnMainSync {
                ActivityLifecycleMonitorRegistry.getInstance().removeLifecycleCallback(ownerLifecycle)
            }
        }
    }

    private fun awaitOwnerState(message: String, condition: () -> Boolean) {
        val deadline = SystemClock.uptimeMillis() + 5_000
        fun failure(): Nothing {
            var observations = ""
            instrumentation.runOnMainSync {
                observations = owners.joinToString { owner ->
                    "${System.identityHashCode(owner)}/task=${owner.taskId}/state=${owner.lifecycle.currentState}/" +
                        "finishing=${owner.isFinishing}/destroyed=${owner.isDestroyed}"
                }
            }
            throw AssertionError("$message; owners=[$observations]")
        }
        while (SystemClock.uptimeMillis() < deadline) {
            var satisfied = false
            instrumentation.runOnMainSync { satisfied = condition() }
            if (satisfied) return
            val remaining = deadline - SystemClock.uptimeMillis()
            if (remaining <= 0) break
            val frame = CountDownLatch(1)
            instrumentation.runOnMainSync {
                Choreographer.getInstance().postFrameCallback { frame.countDown() }
            }
            if (!frame.await(remaining, TimeUnit.MILLISECONDS)) failure()
        }
        failure()
    }

    private fun persistedHistory(name: String = preferencesName): String? {
        val file = File(context.applicationInfo.dataDir, "shared_prefs/$name.xml")
        return file.inputStream().use { input ->
            val parser = Xml.newPullParser()
            parser.setInput(input, "UTF-8")
            while (parser.next() != XmlPullParser.END_DOCUMENT) {
                if (parser.eventType == XmlPullParser.START_TAG && parser.name == "string" &&
                    parser.getAttributeValue(null, "name") == "history"
                ) {
                    return@use parser.nextText()
                }
            }
            null
        }
    }
}
