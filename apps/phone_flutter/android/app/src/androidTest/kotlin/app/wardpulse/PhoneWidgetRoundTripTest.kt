package app.wardpulse

import android.app.Activity
import android.app.ActivityManager
import android.app.Application
import android.content.ComponentName
import android.content.Intent
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.Process
import android.os.SystemClock
import android.test.InstrumentationTestCase
import android.view.View
import es.antonborri.home_widget.HomeWidgetPlugin
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.android.FlutterView
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor.DartEntrypoint
import io.flutter.plugin.common.BasicMessageChannel
import io.flutter.plugin.common.StandardMessageCodec
import java.io.File
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicReference

/** Two actual Dart→auto-registered-plugin roundtrips, independent of the overlap falsifier. */
@Suppress("DEPRECATION")
class PhoneWidgetRoundTripTest : InstrumentationTestCase() {
    private val main = Handler(Looper.getMainLooper())
    private var deadline = 0L

    fun testForegroundAndActivityFreeDartPublication() {
        deadline = SystemClock.elapsedRealtime() + 60_000
        val context = instrumentation.targetContext
        val application = context.applicationContext as Application
        assertSame(application, application.applicationContext)
        assertEquals(WidgetPublicationFixture.PACKAGE, context.packageName)
        assertEquals(context.packageName, application.packageName)
        assertEquals(context.applicationInfo.uid, Process.myUid())
        assertEquals(File(context.applicationInfo.dataDir).canonicalFile, application.dataDir.canonicalFile)
        val process = application.getSystemService(ActivityManager::class.java).runningAppProcesses
            .single { it.pid == Process.myPid() }
        assertEquals(WidgetPublicationFixture.PACKAGE, process.processName)
        val preferences = HomeWidgetPlugin.getData(application)
        assertTrue("Fresh fixture must have no publication", preferences.all.isEmpty())

        val ownedActivity = AtomicReference<Activity?>()
        val resumed = CountDownLatch(1)
        val isResumed = AtomicBoolean(false)
        val destroyed = CountDownLatch(1)
        val callbacks = object : Application.ActivityLifecycleCallbacks {
            override fun onActivityCreated(activity: Activity, state: Bundle?) {
                if (activity is MainActivity) ownedActivity.set(activity)
            }
            override fun onActivityResumed(activity: Activity) {
                if (activity === ownedActivity.get()) { isResumed.set(true); resumed.countDown() }
            }
            override fun onActivityDestroyed(activity: Activity) {
                if (activity === ownedActivity.get()) destroyed.countDown()
            }
            override fun onActivityStarted(activity: Activity) {}
            override fun onActivityPaused(activity: Activity) {
                if (activity === ownedActivity.get()) isResumed.set(false)
            }
            override fun onActivityStopped(activity: Activity) {}
            override fun onActivitySaveInstanceState(activity: Activity, state: Bundle) {}
        }
        var monitor: android.app.Instrumentation.ActivityMonitor? = null
        var foreground: FlutterEngine? = null
        var headless: FlutterEngine? = null
        var view: FlutterView? = null
        var attachment: View.OnAttachStateChangeListener? = null
        val channels = mutableListOf<BasicMessageChannel<Any?>>()
        try {
            onMain {
                application.registerActivityLifecycleCallbacks(callbacks)
                monitor = instrumentation.addMonitor(MainActivity::class.java.name, null, false)
                application.startActivity(Intent().setComponent(ComponentName(
                    WidgetPublicationFixture.PACKAGE, MainActivity::class.java.name))
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
            }
            val activity = requireNotNull(monitor!!.waitForActivityWithTimeout(remaining(deadline))) {
                "Fixture Activity did not start"
            }
            await(resumed)
            assertSame(ownedActivity.get(), activity)
            val attached = CountDownLatch(1)
            onMain {
                assertSame(application, activity.applicationContext)
                view = activity.findViewById(FlutterActivity.FLUTTER_VIEW_ID)
                val actual = requireNotNull(view) { "Missing Activity FlutterView" }
                attachment = object : View.OnAttachStateChangeListener {
                    override fun onViewAttachedToWindow(view: View) { attached.countDown() }
                    override fun onViewDetachedFromWindow(view: View) {}
                }
                actual.addOnAttachStateChangeListener(attachment!!)
                if (actual.isAttachedToWindow) attached.countDown()
            }
            await(attached)
            onMain {
                assertTrue(view!!.isAttachedToWindow)
                assertTrue(isResumed.get())
                assertFalse(activity.isFinishing)
                foreground = requireNotNull(view!!.attachedFlutterEngine) { "No attached foreground engine" }
            }
            fun channel(engine: FlutterEngine): BasicMessageChannel<Any?> {
                var result: BasicMessageChannel<Any?>? = null
                onMain {
                    result = BasicMessageChannel(engine.dartExecutor.binaryMessenger,
                        "app.wardpulse/widget_publication_fixture", StandardMessageCodec.INSTANCE)
                    channels.add(result!!)
                }
                return result!!
            }
            fun roundTrip(engine: FlutterEngine, id: String, count: Int, value: Int) {
                val publication = WidgetPublicationFixture.payload(id, count, value, stale = id == "headless")
                assertEquals(mapOf("id" to id, "saved" to true), exchange(channel(engine),
                    mapOf("id" to id, "publication" to publication)))
                WidgetPublicationFixture.assertStored(application, preferences, publication, "$id Dart reply/consumer")
            }
            roundTrip(foreground!!, "foreground", 2, 20)
            onMain {
                headless = FlutterEngine(application)
                assertNotSame(foreground, headless)
                headless!!.dartExecutor.executeDartEntrypoint(DartEntrypoint.createDefault(), listOf("headless"))
            }
            roundTrip(headless!!, "headless", 6, 50)
        } finally {
            // Framework calls themselves may block: HOST also owns the outer timeout
            // and package retirement. Forced cleanup never makes this test pass.
            val cleanupDeadline = SystemClock.elapsedRealtime() + 10_000
            try {
                onMain(cleanupDeadline) {
                    try {
                        channels.forEach { it.setMessageHandler(null) }
                        attachment?.let { view?.removeOnAttachStateChangeListener(it) }
                    } finally {
                        try { headless?.destroy() } finally {
                            try { ownedActivity.get()?.finish() }
                            finally { monitor?.let { instrumentation.removeMonitor(it) } }
                        }
                    }
                }
                if (ownedActivity.get() != null) await(destroyed, cleanupDeadline)
            } finally {
                onMain(cleanupDeadline) { application.unregisterActivityLifecycleCallbacks(callbacks) }
            }
            assertTrue(preferences.edit().clear().commit())
        }
    }

    private fun exchange(channel: BasicMessageChannel<Any?>, message: Any): Any? {
        val replied = CountDownLatch(1)
        val reply = AtomicReference<Any?>()
        onMain { channel.send(message) { value -> reply.set(value); replied.countDown() } }
        await(replied)
        return reply.get()
    }

    private fun remaining(limit: Long): Long {
        val millis = limit - SystemClock.elapsedRealtime()
        assertTrue("Fixture deadline exceeded", millis > 0)
        return millis
    }

    private fun await(latch: CountDownLatch, limit: Long = deadline) {
        assertTrue("Fixture event/reply timed out", latch.await(remaining(limit), TimeUnit.MILLISECONDS))
    }

    private fun onMain(limit: Long = deadline, action: () -> Unit) {
        val completed = CountDownLatch(1)
        val failure = AtomicReference<Throwable?>()
        assertTrue(main.post {
            try { action() } catch (error: Throwable) { failure.set(error) }
            finally { completed.countDown() }
        })
        await(completed, limit)
        failure.get()?.let { throw AssertionError("Fixture main-thread operation failed", it) }
    }
}
