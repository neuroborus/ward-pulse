package app.wardpulse.wear

import android.app.Activity
import android.app.Application
import android.content.Context
import android.content.SharedPreferences
import android.os.Bundle
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.lifecycleScope
import androidx.lifecycle.viewModelScope
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.runner.AndroidJUnitRunner
import app.wardpulse.wear.data.WatchSummaryStore
import app.wardpulse.wear.model.WatchDashboardSummary
import app.wardpulse.wear.watchface.WatchFaceConsentStore
import java.util.UUID
import java.util.concurrent.ExecutorService
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Job
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotSame
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.rules.TestRule
import org.junit.runner.Description
import org.junit.runners.model.MultipleFailureException
import org.junit.runners.model.Statement

/** Only this runner selects the application; services keep their ordinary storage context. */
class IsolatedWearRunner : AndroidJUnitRunner() {
    private lateinit var isolatedApplication: IsolatedWearApplication

    override fun newApplication(cl: ClassLoader, className: String, context: Context): Application =
        super.newApplication(cl, IsolatedWearApplication::class.java.name, context).also {
            isolatedApplication = it as IsolatedWearApplication
        }

    override fun callActivityOnCreate(activity: Activity, icicle: Bundle?) {
        if (activity is MainActivity) {
            check(activity.application === isolatedApplication)
            isolatedApplication.scope.register(activity)
        }
        super.callActivityOnCreate(activity, icicle)
        if (activity is MainActivity) {
            // Retain the real owner's job while its ViewModelStore is live. Lifecycle's
            // pre-destroy dispatch can clear that store before callActivityOnDestroy.
            isolatedApplication.scope.track(checkNotNull(
                ViewModelProvider(activity)[WatchFaceViewModel::class.java].viewModelScope.coroutineContext[Job],
            ))
            isolatedApplication.scope.track(checkNotNull(activity.lifecycleScope.coroutineContext[Job]))
            if (isolatedApplication.scope.closing) activity.finish()
        }
    }

    override fun callActivityOnStart(activity: Activity) {
        val scope = if (activity is MainActivity) isolatedApplication.scope else null
        val previous = scope?.refreshCount(activity) ?: 0
        super.callActivityOnStart(activity)
        if (scope != null) {
            check(scope.refreshCount(activity) == previous + 1) {
                "MainActivity.onStart must dispatch exactly one isolated refresh"
            }
        }
    }

    override fun callActivityOnDestroy(activity: Activity) {
        val scope = if (activity is MainActivity) isolatedApplication.scope else null
        super.callActivityOnDestroy(activity)
        scope?.destroyed(activity)
    }
}

internal class IsolatedWearApplication : Application(), MainActivityDependencies {
    @Volatile
    private var currentScope: IsolatedActivityScope? = null
    internal val scope: IsolatedActivityScope
        get() = checkNotNull(currentScope) { "Default MainActivity launch requires an isolated test scope" }

    internal fun openScope(): IsolatedActivityScope {
        check(currentScope == null) { "Previous isolated owners or operations have not retired" }
        return IsolatedActivityScope(this).also { currentScope = it }
    }

    internal fun release(scope: IsolatedActivityScope) {
        check(currentScope === scope)
        currentScope = null
    }

    override fun summaryStore(context: Context) = WatchSummaryStore(scope.summaryPreferences)
    override fun consentStore(context: Context) = WatchFaceConsentStore(scope.consentPreferences)
    override fun requestComplicationRefresh(context: Context) = scope.recordRefresh(context as MainActivity)
}

/** Wraps @After too, so failure cleanup cannot withdraw isolation from a surviving owner. */
internal class IsolatedActivityRule : TestRule {
    private lateinit var application: IsolatedWearApplication
    val scope: IsolatedActivityScope get() = application.scope

    override fun apply(base: Statement, description: Description) = object : Statement() {
        override fun evaluate() {
            application = InstrumentationRegistry.getInstrumentation().targetContext.applicationContext
                as? IsolatedWearApplication ?: error("Default suite requires IsolatedWearRunner and rebuilt target")
            val opened = application.openScope()
            val failures = mutableListOf<Throwable>()
            try {
                base.evaluate()
            } catch (failure: Throwable) {
                failures += failure
            } finally {
                try {
                    opened.close()
                } catch (failure: Throwable) {
                    failures += failure
                }
            }
            MultipleFailureException.assertEmpty(failures)
        }
    }
}

internal class IsolatedActivityScope(private val application: IsolatedWearApplication) : AutoCloseable {
    private val instrumentation = InstrumentationRegistry.getInstrumentation()
    private val prefix = "isolated_activity_${UUID.randomUUID()}"
    private val summaryName = "${prefix}_summary"
    val consentName = "${prefix}_consent"
    val summaryPreferences: SharedPreferences = application.getSharedPreferences(summaryName, Context.MODE_PRIVATE)
    val consentPreferences: SharedPreferences = application.getSharedPreferences(consentName, Context.MODE_PRIVATE)
    private val owners = linkedMapOf<Activity, CompletableDeferred<Unit>>()
    private val refreshes = mutableMapOf<Activity, Int>()
    private val jobs = mutableSetOf<Job>()
    private val executors = mutableSetOf<ExecutorService>()
    var closing = false
        private set

    fun register(activity: MainActivity) {
        check(owners.put(activity, CompletableDeferred()) == null)
    }

    fun recordRefresh(activity: MainActivity) {
        check(activity in owners)
        refreshes[activity] = refreshCount(activity) + 1
    }

    fun refreshCount(activity: Activity) = refreshes[activity] ?: 0

    fun assertRefreshDispatched(activity: MainActivity) {
        assertTrue("Real onStart must reach the recording refresh sink", refreshCount(activity) > 0)
        val storeField = MainActivity::class.java.getDeclaredField("store").apply { isAccessible = true }
        val preferencesField = WatchSummaryStore::class.java.getDeclaredField("preferences").apply {
            isAccessible = true
        }
        assertSame(summaryPreferences, preferencesField.get(storeField.get(activity)))
    }

    fun track(job: Job) {
        jobs += job
    }

    fun track(executor: ExecutorService) {
        executors += executor
    }

    fun destroyed(activity: Activity) {
        checkNotNull(owners[activity]).complete(Unit)
    }

    fun saveSummary(summary: WatchDashboardSummary?) {
        if (summary == null) {
            assertTrue(summaryPreferences.edit().remove("latest").commit())
        } else {
            WatchSummaryStore(summaryPreferences).save(summary)
            val fixture = checkNotNull(summaryPreferences.getString("latest", null))
            // Compare only this fixture's provenance; a newer phone publication is legitimate.
            assertFalse(
                "Test fixture reached normal datasource storage",
                fixture == application.getSharedPreferences("watch_summary", Context.MODE_PRIVATE)
                    .getString("latest", null),
            )
        }
        assertStorageIsPrivate()
    }

    fun assertStorageIsPrivate() {
        // Inspect the actual backing stores, without freezing live values or restoring over a producer.
        val normalSummary = application.getSharedPreferences("watch_summary", Context.MODE_PRIVATE)
        val normalConsent = application.getSharedPreferences("watch_face_consent", Context.MODE_PRIVATE)
        assertNotSame(normalSummary, summaryPreferences)
        assertNotSame(normalConsent, consentPreferences)
        val summaryField = WatchSummaryStore::class.java.getDeclaredField("preferences").apply { isAccessible = true }
        val consentField = WatchFaceConsentStore::class.java.getDeclaredField("preferences").apply { isAccessible = true }
        // This is the Context constructor used by production datasource services, even in this application.
        assertSame(normalSummary, summaryField.get(WatchSummaryStore(application)))
        assertSame(normalConsent, consentField.get(WatchFaceConsentStore(application)))
        assertSame(summaryPreferences, summaryField.get(application.summaryStore(application)))
        assertSame(consentPreferences, consentField.get(application.consentStore(application)))
    }

    override fun close() {
        lateinit var retirement: List<CompletableDeferred<Unit>>
        instrumentation.runOnMainSync {
            closing = true
            retirement = owners.values.toList()
            owners.keys.filterNot { it.isDestroyed }.forEach { it.finish() }
        }
        try {
            runBlocking { withTimeout(5_000) { retirement.forEach { it.await() } } }
        } finally {
            lateinit var operations: List<Job>
            instrumentation.runOnMainSync { operations = jobs.toList() }
            operations.forEach { it.cancel() }
            executors.forEach { it.shutdownNow() }
            try {
                runBlocking { withTimeout(5_000) { operations.forEach { it.join() } } }
            } finally {
                executors.forEach {
                    assertTrue("Owned consent workers must retire", it.awaitTermination(5, TimeUnit.SECONDS))
                }
            }
        }
        instrumentation.waitForIdleSync()
        instrumentation.runOnMainSync {
            check(owners.values.all { it.isCompleted } && jobs.all { it.isCompleted } &&
                executors.all { it.isTerminated }
            ) {
                "Isolation retained: an owned Activity or operation has not retired"
            }
            assertStorageIsPrivate()
            // No live preference is ever cleared or restored by this scope.
            for (name in listOf(summaryName, consentName)) {
                assertTrue(application.getSharedPreferences(name, Context.MODE_PRIVATE).edit().clear().commit())
                assertTrue(application.deleteSharedPreferences(name))
            }
            application.release(this)
        }
    }
}
