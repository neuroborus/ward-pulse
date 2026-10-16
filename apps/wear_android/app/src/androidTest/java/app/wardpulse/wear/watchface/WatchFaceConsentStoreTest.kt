package app.wardpulse.wear.watchface

import android.content.Context
import android.content.Intent
import android.util.Xml
import androidx.lifecycle.Lifecycle
import androidx.test.core.app.ActivityScenario
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
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
import org.junit.Test
import org.junit.runner.RunWith
import org.xmlpull.v1.XmlPullParser

@RunWith(AndroidJUnit4::class)
class WatchFaceConsentStoreTest {
    private val context = ApplicationProvider.getApplicationContext<Context>()
    private val preferencesName = "watch_face_consent_test_${System.nanoTime()}"
    private val preferences = context.getSharedPreferences(preferencesName, Context.MODE_PRIVATE)

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
        val productionPreferences = context.getSharedPreferences("watch_face_consent", Context.MODE_PRIVATE)
        val originalHistory = productionPreferences.getString("history", null)
        val executor = Executors.newFixedThreadPool(2)
        try {
            val intent = Intent(context, MainActivity::class.java).addFlags(
                Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_MULTIPLE_TASK,
            )
            ActivityScenario.launch<MainActivity>(intent).use { first ->
                first.moveToState(Lifecycle.State.CREATED)
                ActivityScenario.launch<MainActivity>(intent).use { second ->
                    val models = mutableListOf<WatchFaceViewModel>()
                    val controllers = mutableListOf<WatchFaceController>()
                    val stores = mutableListOf<WatchFaceConsentStore>()
                    val taskIds = mutableListOf<Int>()
                    for (scenario in listOf(first, second)) {
                        scenario.onActivity { activity ->
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
                    }
                    assertEquals(Lifecycle.State.CREATED, first.state)
                    assertEquals(Lifecycle.State.RESUMED, second.state)
                    assertEquals(2, taskIds.toSet().size)
                    assertNotSame(models[0], models[1])
                    assertNotSame(controllers[0], controllers[1])
                    assertNotSame(stores[0], stores[1])

                    second.recreate()
                    second.onActivity { activity ->
                        val retained = MainActivity::class.java.getDeclaredMethod("getWatchFace").apply {
                            isAccessible = true
                        }.invoke(activity)
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
                                    assertEquals(history.name, persistedHistory("watch_face_consent"))
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
                            assertEquals(history.name, persistedHistory("watch_face_consent"))
                        } finally {
                            release.countDown()
                            claims.forEach { it.cancel(true) }
                        }
                    }
                }
            }
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
