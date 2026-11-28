package app.wardpulse.wear.sync

import android.content.Context
import android.content.SharedPreferences
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import app.wardpulse.wear.BuildConfig
import app.wardpulse.wear.data.SummaryAttempts
import app.wardpulse.wear.data.SummaryBinding
import app.wardpulse.wear.data.SummaryOwner
import app.wardpulse.wear.data.WatchSummaryStore
import app.wardpulse.wear.model.WatchDataMode
import org.json.JSONObject
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

/**
 * Store policy and route proofs on the actual Wear store; the Data Layer is a stand-in. Each test
 * orders its own route resolutions, so the app's listener, which a paired device can signal
 * during the run, cannot advance them.
 */
@RunWith(AndroidJUnit4::class)
class WatchSummaryReconcilerTest {
    private val context = ApplicationProvider.getApplicationContext<Context>()
    private val testContext = InstrumentationRegistry.getInstrumentation().context
    private val preferencesName = "watch_summary_route_test_${System.nanoTime()}"
    private val preferences = context.getSharedPreferences(preferencesName, Context.MODE_PRIVATE)
    private val attempts = SummaryAttempts()
    private val production = WatchSummaryStore(preferences, debugBuild = false, attempts = attempts)
    private val route = FakeRoute()
    private var nonces = 0

    @After
    fun cleanUp() {
        assertTrue(preferences.edit().clear().commit())
        assertTrue(context.deleteSharedPreferences(preferencesName))
    }

    @Test
    fun runtimeDefaultFollowsTheBuild() {
        val store = WatchSummaryStore(preferences)
        assertEquals(BuildConfig.DEBUG, store.saveEncoded(legacy(mode = "mock")))
        assertEquals(BuildConfig.DEBUG, store.decodeOrdered(ordered(mode = "mock")) != null)
    }

    @Test
    fun productionAcceptsDemoAndRejectsMockOnWritesAndReads() {
        assertTrue(production.saveEncoded(ordered(mode = "demo")))
        assertEquals(WatchDataMode.DEMO, production.load()?.dataMode)
        assertTrue(production.decodeOrdered(ordered(mode = "demo")) != null)

        assertFalse(production.saveEncoded(ordered(mode = "mock")))
        assertFalse(production.saveEncoded(legacy(mode = "mock")))
        assertNull(production.decodeOrdered(ordered(mode = "mock")))
        assertNull(production.decodeLegacy(legacy(mode = "mock")))
        assertFalse(production.accept(PHONE, ordered(mode = "mock"), owner(), claimed()))

        // A Mock summary persisted by a Debug build is not rendered by a production read.
        assertTrue(WatchSummaryStore(preferences, debugBuild = true).saveEncoded(legacy(mode = "mock")))
        assertNull(production.load())
        assertEquals(WatchDataMode.MOCK, WatchSummaryStore(preferences, debugBuild = true).load()?.dataMode)
    }

    @Test
    fun legacyProjectionNeverCarriesDemo() {
        assertNull(production.decodeLegacy(legacy(mode = "demo")))
        assertFalse(production.saveEncoded(legacy(mode = "demo")))
        // A v10 value is not a v9 projection.
        assertNull(production.decodeLegacy(ordered()))
    }

    @Test
    fun canonicalOrderedExampleDecodesStrictly() {
        val example = asset("watch_dashboard_summary_v10_demo.json")
        val decoded = production.decodeOrdered(example)!!
        assertEquals(WatchDataMode.DEMO, decoded.summary.dataMode)
        assertEquals(10, decoded.summary.schemaVersion)
        assertEquals(SummaryOwner("00000000-0000-4000-8000-000000000000", 1L, 1L), decoded.owner)
        for (malformed in listOf(
            JSONObject(example).put("schemaVersion", "10"),
            JSONObject(example).put("generation", "1"),
            JSONObject(example).put("generation", -1),
            JSONObject(example).put("sequence", 0),
            JSONObject(example).put("sequence", 1.5),
            JSONObject(example).put("installId", "install-1"),
            JSONObject(example).apply { remove("installId") },
            JSONObject(example).put("dataMode", "unknown"),
        )) {
            assertNull(malformed.toString(), production.decodeOrdered(malformed.toString()))
        }
    }

    @Test
    fun verifiedOrderedSummaryBindsHostOwnerAndWatermark() {
        route.publish(PHONE, ordered(sequence = 3))
        route.answer(owner(sequence = 3))

        assertEquals(ReconcileOutcome.ACCEPTED, reconcile())
        assertEquals(SummaryBinding(PHONE, owner(sequence = 3)), production.binding())
        assertTrue(production.orderedRoute(PHONE))
        assertEquals(WatchDataMode.DEMO, production.load()?.dataMode)
        assertEquals(listOf(PHONE to "nonce-1"), route.requests)
        // Nothing was stored from the phone yet, so the request is the bare nonce; only the
        // commit names the order, which the phone needs before it records that Wear has left the
        // previous mode and stops owing the empty fallback.
        assertEquals(listOf<SummaryOwner?>(null), route.held)
        assertEquals(listOf(PHONE to owner(sequence = 3)), route.reported)
    }

    @Test
    fun aRequestNamesOnlyTheOrderWearStoresAndAFailedCommitReportsNone() {
        route.publish(PHONE, ordered(mode = "live", sequence = 3))
        route.answer(owner(sequence = 3))
        assertEquals(ReconcileOutcome.ACCEPTED, reconcile())

        // The proof for a newer item names the stored one, not the item it read.
        route.publish(PHONE, ordered(mode = "live", sequence = 4))
        route.answer(owner(sequence = 4))
        // The phone disconnects while the exact item is read again for the commit.
        route.onItem = { if (it == 2) route.connected -= PHONE }
        assertEquals(ReconcileOutcome.UNRESOLVED, reconcile())
        assertEquals(owner(sequence = 3), route.held.last())
        assertEquals(owner(sequence = 3), production.binding()?.owner)
        // Wear stores nothing, so it names no new order.
        assertEquals(listOf(PHONE to owner(sequence = 3)), route.reported)

        // A newer resolution deciding during that read supersedes the commit just as silently.
        route.connected += PHONE
        route.onItem = { if (it == 2) claimed() }
        assertEquals(ReconcileOutcome.SUPERSEDED, reconcile())
        assertEquals(owner(sequence = 3), route.held.last())
        assertEquals(listOf(PHONE to owner(sequence = 3)), route.reported)

        route.onItem = {}
        assertEquals(ReconcileOutcome.ACCEPTED, reconcile())
        assertEquals(owner(sequence = 3), route.held.last())
        assertEquals(PHONE to owner(sequence = 4), route.reported.last())
    }

    @Test
    fun ownerRequestIsExactlyTheNonceAndTheHeldOrder() {
        val request = JSONObject(
            String(WatchSummaryReconciler.ownerRequest("nonce-1", owner(generation = 2, sequence = 5))),
        )
        assertEquals(setOf("nonce", "installId", "generation", "sequence"), request.keys().asSequence().toSet())
        assertEquals("nonce-1", request.getString("nonce"))
        assertEquals(INSTALL, request.getString("installId"))
        assertEquals(2L, request.getLong("generation"))
        assertEquals(5L, request.getLong("sequence"))
        // Without a stored v10 order it is the bare nonce an earlier build sends.
        assertEquals("nonce-1", String(WatchSummaryReconciler.ownerRequest("nonce-1", null)))
    }

    @Test
    fun passiveRestartWithAnUnchangedItemNeitherRequestsNorWrites() {
        val counted = CountingPreferences(preferences)
        val store = WatchSummaryStore(counted, debugBuild = false, attempts = attempts)
        route.publish(PHONE, ordered(sequence = 3))
        route.answer(owner(sequence = 3))
        assertEquals(ReconcileOutcome.ACCEPTED, reconcile(store))
        val requests = route.requests.size
        val writes = counted.writes
        val record = preferences.all

        // A restarted listener or Activity, or a repeated data event, resolves the same item.
        assertEquals(ReconcileOutcome.UNCHANGED, reconcile(store))
        assertEquals(ReconcileOutcome.UNCHANGED, reconcile(store))
        assertEquals(requests, route.requests.size)
        assertEquals(writes, counted.writes)
        assertEquals(record, preferences.all)
        assertEquals(WatchDataMode.DEMO, WatchSummaryStore(preferences, debugBuild = false).load()?.dataMode)
    }

    @Test
    fun malformedOrderedValueNeverFallsBackToTheProjection() {
        route.publish(PHONE, ordered = "{\"schemaVersion\":10}", legacy = legacy())
        route.answer(owner())

        assertEquals(ReconcileOutcome.REJECTED, reconcile())
        assertNull(production.load())
        assertTrue(route.requests.isEmpty())
    }

    @Test
    fun presentButNonStringOrderedKeyNeverFallsBackToTheProjection() {
        // `toSummaryItem` reads a v10 key holding a non-string as present with a null value.
        route.items[PHONE] = SummaryItem(PHONE, ordered = null, legacy = legacy(), orderedPresent = true)
        route.connected += PHONE
        route.answer(owner())

        assertEquals(ReconcileOutcome.REJECTED, reconcile())
        assertNull(production.load())
        assertNull(production.binding())
        assertTrue(route.requests.isEmpty())
    }

    @Test
    fun orderedContractIsClosedOnIncomingAndPersistedReads() {
        val example = asset("watch_dashboard_summary_v10_demo.json")
        val malformed = listOf(
            JSONObject(example).put("unexpected", true),
            JSONObject(example).apply { getJSONArray("rings").getJSONObject(0).put("extra", 1) },
            JSONObject(example).apply { remove("manualRefreshAvailableAt") },
            JSONObject(example).apply { getJSONArray("rings").getJSONObject(0).remove("split") },
            JSONObject(example).apply { getJSONObject("today").remove("projectedTotal") },
            JSONObject(example).put("isStale", "false"),
            JSONObject(example).put("manualRefreshAllowed", 1),
            JSONObject(example).put(SELECTED_RING_DATA_UNAVAILABLE, "true"),
            JSONObject(example).apply { getJSONArray("rings").getJSONObject(0).put("usedPercent", "63") },
            JSONObject(example).apply { getJSONArray("allowances").getJSONObject(0).put("unlimited", "false") },
            JSONObject(example).apply {
                getJSONObject("week").put("spent", JSONObject().put("minorUnits", 1.5).put("currency", "USD"))
            },
            JSONObject(example).apply { getJSONObject("creditsGlance").put("text", 400) },
            // Value bounds of the shared contract, not only JSON types.
            JSONObject(example).put("manualRefreshAvailableAt", "soon"),
            JSONObject(example).apply { getJSONArray("allowances").getJSONObject(0).put("usedPercent", -1) },
            JSONObject(example).apply { getJSONArray("allowances").getJSONObject(0).put("resetsAt", "tomorrow") },
        ).map { it.toString() } + JSONObject(example).toString().let { canonical ->
            // One complete strict document: Android's lenient reader would take each of these.
            listOf(
                "$canonical trailing",
                "$canonical{}",
                canonical.replaceFirst("{", "{/* comment */"),
                canonical.replaceFirst("\"schemaVersion\"", "schemaVersion"),
                canonical.replaceFirst("{", "{\"isStale\":false,"),
            )
        }
        for (encoded in malformed) {
            assertNull(encoded, production.decodeOrdered(encoded))
            assertFalse(encoded, production.saveEncoded(encoded))
            assertFalse(encoded, production.accept(PHONE, encoded, owner(), claimed()))

            // A value persisted before this check is not rendered either.
            assertTrue(preferences.edit().putString("latest", encoded).commit())
            assertNull(encoded, production.load())
            assertTrue(preferences.edit().remove("latest").commit())
        }
        val optional = JSONObject(example).apply {
            put(SELECTED_RING_DATA_UNAVAILABLE, true)
            getJSONObject("creditsGlance").remove("provider")
            getJSONArray("allowances").getJSONObject(0).remove("unlimited")
        }.toString()
        assertTrue(production.saveEncoded(optional))
        assertTrue(production.load()!!.selectedRingDataUnavailable)
    }

    @Test
    fun orderedSummaryRequiresAMatchingFreshReply() {
        route.publish(PHONE, ordered(generation = 1, sequence = 4))
        for (reply in listOf(
            owner(installId = OTHER_INSTALL, generation = 1, sequence = 4),
            // The phone committed a newer mode generation before replacing the item.
            owner(generation = 2, sequence = 4),
            // A newer desired put is still settling; this item is older than it.
            owner(generation = 1, sequence = 5),
        )) {
            route.answer(reply)
            assertEquals(reply.toString(), ReconcileOutcome.REJECTED, reconcile())
        }
        route.reply = { _, _ -> null }
        assertEquals(ReconcileOutcome.UNRESOLVED, reconcile())
        route.reply = { _, nonce -> replyBytes("stale-$nonce", owner(generation = 1, sequence = 4)) }
        assertEquals(ReconcileOutcome.REJECTED, reconcile())
        assertNull(production.load())

        // The item is at or after the phone's desired order.
        route.answer(owner(generation = 1, sequence = 3))
        assertEquals(ReconcileOutcome.ACCEPTED, reconcile())
    }

    @Test
    fun watermarkRefusesOlderOrdersUntilAVerifiedNewInstall() {
        route.publish(PHONE, ordered(sequence = 7))
        route.answer(owner(sequence = 7))
        assertEquals(ReconcileOutcome.ACCEPTED, reconcile())

        // An orphaned put from before process death arrives late.
        route.publish(PHONE, ordered(mode = "live", sequence = 6))
        route.answer(owner(sequence = 6))
        assertEquals(ReconcileOutcome.REJECTED, reconcile())
        assertEquals(owner(sequence = 7), production.binding()?.owner)

        // A replacement phone install starts its own counter once verified.
        route.publish(PHONE, ordered(mode = "live", installId = OTHER_INSTALL, generation = 0, sequence = 1))
        route.answer(owner(installId = OTHER_INSTALL, generation = 0, sequence = 1))
        assertEquals(ReconcileOutcome.ACCEPTED, reconcile())
        assertEquals(owner(installId = OTHER_INSTALL, generation = 0, sequence = 1), production.binding()?.owner)
        assertEquals(WatchDataMode.LIVE, production.load()?.dataMode)
    }

    @Test
    fun deathBetweenModeCommitAndReplacementKeepsTheRetiredDemoOut() {
        route.publish(PHONE, ordered(mode = "live", generation = 0, sequence = 1))
        route.answer(owner(generation = 0, sequence = 1))
        assertEquals(ReconcileOutcome.ACCEPTED, reconcile())
        // The phone committed Demo (generation 1), then died before its put replaced the item;
        // a stale Demo put from an earlier Demo session surfaces now.
        route.publish(PHONE, ordered(mode = "demo", generation = 1, sequence = 2))
        route.answer(owner(generation = 2, sequence = 3))
        assertEquals(ReconcileOutcome.REJECTED, reconcile())
        assertEquals(WatchDataMode.LIVE, production.load()?.dataMode)

        // The restarted phone reasserts its current-generation empty summary.
        route.publish(PHONE, ordered(mode = "live", generation = 2, sequence = 3))
        assertEquals(ReconcileOutcome.ACCEPTED, reconcile())
        assertEquals(owner(generation = 2, sequence = 3), production.binding()?.owner)
    }

    @Test
    fun aNewerAttemptRetiresAnOverlappingProof() {
        route.publish(PHONE, ordered(sequence = 2))
        var overlapped: ReconcileOutcome? = null
        route.reply = { _, nonce ->
            if (overlapped == null) {
                route.reply = { _, inner -> replyBytes(inner, owner(sequence = 2)) }
                // A second resolution starts while the first nonce is outstanding.
                overlapped = reconcile()
            }
            replyBytes(nonce, owner(sequence = 2))
        }
        assertEquals(ReconcileOutcome.SUPERSEDED, reconcile())
        assertEquals(ReconcileOutcome.ACCEPTED, overlapped)
        assertEquals(owner(sequence = 2), production.binding()?.owner)
    }

    @Test
    fun replacementWrittenDuringTheProofAnswersInItsOwnAttempt() {
        route.publish(PHONE, ordered(sequence = 2))
        route.reply = { _, nonce ->
            route.publish(PHONE, ordered(sequence = 3))
            replyBytes(nonce, owner(sequence = 2))
        }
        assertEquals(ReconcileOutcome.SUPERSEDED, reconcile())
        assertNull(production.binding())
    }

    @Test
    fun routeResolutionPrefersTheBoundHostThenAUniqueCandidate() {
        route.publish(PHONE, ordered(sequence = 1))
        route.publish(OTHER_PHONE, ordered(installId = OTHER_INSTALL, sequence = 1))
        // Two connected candidates and no binding: nothing is guessed.
        assertEquals(ReconcileOutcome.UNRESOLVED, reconcile())
        assertTrue(route.requests.isEmpty())

        route.connected -= OTHER_PHONE
        route.answer(owner(sequence = 1))
        assertEquals(ReconcileOutcome.ACCEPTED, reconcile())
        route.connected += OTHER_PHONE
        route.publish(PHONE, ordered(mode = "live", sequence = 2))
        route.answer(owner(sequence = 2))
        assertEquals(ReconcileOutcome.ACCEPTED, reconcile())
        assertEquals(PHONE, route.requests.last().first)

        // The bound phone is unreachable; the remaining unique candidate is verified instead.
        route.connected -= PHONE
        route.answer(owner(installId = OTHER_INSTALL, sequence = 1))
        assertEquals(ReconcileOutcome.ACCEPTED, reconcile())
        assertEquals(OTHER_PHONE, production.binding()?.host)
    }

    @Test
    fun aReachableBindingIsNotReplacedByAnotherPhonesItem() {
        route.publish(PHONE, ordered(sequence = 1))
        route.answer(owner(sequence = 1))
        assertEquals(ReconcileOutcome.ACCEPTED, reconcile())
        val requests = route.requests.size

        // Another connected phone writes; its data event is only a signal for the bound route.
        route.publish(OTHER_PHONE, ordered(mode = "live", installId = OTHER_INSTALL, sequence = 5))
        route.answer(owner(installId = OTHER_INSTALL, sequence = 5))
        assertEquals(ReconcileOutcome.UNCHANGED, reconcile())
        assertEquals(requests, route.requests.size)
        assertEquals(SummaryBinding(PHONE, owner(sequence = 1)), production.binding())
        assertEquals(WatchDataMode.DEMO, production.load()?.dataMode)

        // The bound phone is reachable but its item is gone: still not replaced.
        route.items.remove(PHONE)
        assertEquals(ReconcileOutcome.UNRESOLVED, reconcile())
        assertEquals(PHONE, production.binding()?.host)
    }

    @Test
    fun anItemFromADisconnectedHostIsIgnored() {
        route.publish(OTHER_PHONE, ordered(installId = OTHER_INSTALL, sequence = 1), connect = false)
        route.answer(owner(installId = OTHER_INSTALL, sequence = 1))
        assertEquals(ReconcileOutcome.UNRESOLVED, reconcile())
        assertTrue(route.requests.isEmpty())
        assertNull(production.load())

        // With the bound phone unreachable too, a disconnected host still cannot take over.
        route.publish(PHONE, ordered(sequence = 1))
        route.answer(owner(sequence = 1))
        assertEquals(ReconcileOutcome.ACCEPTED, reconcile())
        route.connected -= PHONE
        route.publish(OTHER_PHONE, ordered(installId = OTHER_INSTALL, sequence = 2), connect = false)
        assertEquals(ReconcileOutcome.UNRESOLVED, reconcile())
        assertEquals(PHONE, production.binding()?.host)
    }

    @Test
    fun observedReconnectRevalidatesAnUnchangedItemWithoutWriting() {
        val counted = CountingPreferences(preferences)
        val store = WatchSummaryStore(counted, debugBuild = false, attempts = attempts)
        route.publish(PHONE, ordered(sequence = 3))
        route.answer(owner(sequence = 3))
        assertEquals(ReconcileOutcome.ACCEPTED, reconcile(store))
        val requests = route.requests.size
        val writes = counted.writes
        val record = preferences.all

        // While disconnected the phone committed a newer generation it has not yet put.
        route.answer(owner(generation = 2, sequence = 4))
        assertEquals(ReconcileOutcome.UNCHANGED, reconcile(store))
        assertEquals(requests, route.requests.size)

        // The reconnect asks again, naming the item it holds; the phone's owner request handler
        // then reasserts.
        val reported = route.reported.size
        assertEquals(ReconcileOutcome.REJECTED, reconcile(store, revalidate = true))
        assertEquals(requests + 1, route.requests.size)
        assertEquals(owner(sequence = 3), route.held.last())
        route.answer(owner(sequence = 3))
        assertEquals(ReconcileOutcome.UNCHANGED, reconcile(store, revalidate = true))
        assertEquals(requests + 2, route.requests.size)
        assertEquals(owner(sequence = 3), route.held.last())
        // Nothing new was stored, so no further order is named.
        assertEquals(reported, route.reported.size)
        assertEquals(writes, counted.writes)
        assertEquals(record, preferences.all)
        assertEquals(SummaryBinding(PHONE, owner(sequence = 3)), store.binding())
    }

    @Test
    fun anUnchangedSignalDoesNotRetireAnInFlightProof() {
        route.publish(PHONE, ordered(sequence = 1))
        route.answer(owner(sequence = 1))
        assertEquals(ReconcileOutcome.ACCEPTED, reconcile())

        val inFlight = claimed()
        assertEquals(ReconcileOutcome.UNCHANGED, reconcile())
        assertTrue(production.attemptCurrent(inFlight))
        assertTrue(production.accept(PHONE, ordered(sequence = 2), owner(sequence = 2), inFlight))
    }

    @Test
    fun aNewerAttemptAtTheCommitBoundaryRefusesTheOlderCommit() {
        val older = claimed()
        val newer = claimed()
        assertFalse(production.accept(PHONE, ordered(sequence = 1), owner(sequence = 1), older))
        assertNull(production.binding())
        assertTrue(production.accept(PHONE, ordered(sequence = 1), owner(sequence = 1), newer))

        // A newer resolution decides during the final reread, after the reply and route checks.
        route.publish(PHONE, ordered(sequence = 2))
        route.answer(owner(sequence = 2))
        route.onItem = { reads -> if (reads == 2) claimed() }
        assertEquals(ReconcileOutcome.SUPERSEDED, reconcile())
        assertEquals(owner(sequence = 1), production.binding()?.owner)
    }

    @Test
    fun ownerReplyIsExactlyTheOwnerFieldsWithinTheirBounds() {
        val valid = JSONObject(String(replyBytes("nonce-1", owner(generation = 0, sequence = 1))))
        assertEquals(
            Pair("nonce-1", owner(generation = 0, sequence = 1)),
            WatchSummaryReconciler.ownerReply(valid.toString().toByteArray()),
        )
        for (malformed in listOf(
            JSONObject(valid.toString()).put("extra", true),
            JSONObject(valid.toString()).apply { remove("sequence") },
            JSONObject(valid.toString()).put("sequence", 0),
            JSONObject(valid.toString()).put("sequence", -3),
            JSONObject(valid.toString()).put("generation", -1),
            JSONObject(valid.toString()).put("generation", "0"),
            JSONObject(valid.toString()).put("installId", ""),
        )) {
            assertNull(malformed.toString(), WatchSummaryReconciler.ownerReply(malformed.toString().toByteArray()))
        }
        for (notStrict in listOf("$valid junk", "$valid{}", valid.toString().replaceFirst("\"nonce\"", "nonce"))) {
            assertNull(notStrict, WatchSummaryReconciler.ownerReply(notStrict.toByteArray()))
        }
    }

    @Test
    fun anOlderReadReturningLateCannotRetireANewerProof() {
        route.publish(PHONE, ordered(sequence = 1))
        val olderRead = CountDownLatch(1)
        val resumeOlder = CountDownLatch(1)
        val olderDone = CountDownLatch(1)
        route.onItem = { reads ->
            // The older resolution has read sequence 1; it pauses before its nonce allocation.
            if (reads == 1) {
                olderRead.countDown()
                resumeOlder.await(TIMEOUT_SECONDS, TimeUnit.SECONDS)
            }
        }
        var older: ReconcileOutcome? = null
        val olderThread = Thread {
            older = reconcile()
            olderDone.countDown()
        }
        olderThread.start()
        assertTrue(olderRead.await(TIMEOUT_SECONDS, TimeUnit.SECONDS))

        // A newer resolution reads sequence 2 and the older one resumes while its nonce is out.
        route.publish(PHONE, ordered(sequence = 2))
        route.reply = { _, nonce ->
            resumeOlder.countDown()
            assertTrue(olderDone.await(TIMEOUT_SECONDS, TimeUnit.SECONDS))
            replyBytes(nonce, owner(sequence = 2))
        }
        assertEquals(ReconcileOutcome.ACCEPTED, reconcile())
        olderThread.join(TimeUnit.SECONDS.toMillis(TIMEOUT_SECONDS))
        assertEquals(ReconcileOutcome.SUPERSEDED, older)
        assertEquals(listOf(PHONE to "nonce-1"), route.requests)
        assertEquals(owner(sequence = 2), production.binding()?.owner)
    }

    @Test
    fun aDeliveryIsAcceptedOnceWhicheverEntryPointStoresIt() {
        route.publish(PHONE, ordered(sequence = 1))
        route.answer(owner(sequence = 1))
        // The activity's start-up resolution stores the fresh item before the listener's signal.
        assertEquals(ReconcileOutcome.ACCEPTED, reconcile())
        assertEquals(ReconcileOutcome.UNCHANGED, reconcile())
        // A proof reaching its commit after another entry point stored the same item writes nothing.
        assertFalse(production.accept(PHONE, ordered(sequence = 1), owner(sequence = 1), claimed()))
        assertEquals(SummaryBinding(PHONE, owner(sequence = 1)), production.binding())
    }

    @Test
    fun aFailedCommitKeepsTheConfirmedRecordAndTheSameItemRetries() {
        var failing = false
        val store = WatchSummaryStore(failingPreferences { failing }, debugBuild = false, attempts = attempts)
        route.publish(PHONE, ordered(mode = "demo", sequence = 1))
        route.answer(owner(sequence = 1))
        failing = true
        // A failed first write leaves nothing rendered or bound.
        assertEquals(ReconcileOutcome.REJECTED, reconcile(store))
        assertNull(store.load())
        assertNull(store.binding())
        failing = false
        assertEquals(ReconcileOutcome.ACCEPTED, reconcile(store))

        // The Demo to Live replacement fails to commit.
        route.publish(PHONE, ordered(mode = "live", generation = 2, sequence = 2))
        route.answer(owner(generation = 2, sequence = 2))
        failing = true
        assertEquals(ReconcileOutcome.REJECTED, reconcile(store))
        failing = false
        assertEquals(WatchDataMode.DEMO, store.load()?.dataMode)
        assertEquals(SummaryBinding(PHONE, owner(sequence = 1)), store.binding())
        assertEquals(WatchDataMode.DEMO, WatchSummaryStore(preferences, debugBuild = false).load()?.dataMode)

        // The same verified item arriving again is not unchanged, so it retries and is stored.
        assertEquals(ReconcileOutcome.ACCEPTED, reconcile(store))
        assertEquals(WatchDataMode.LIVE, store.load()?.dataMode)
        assertEquals(SummaryBinding(PHONE, owner(generation = 2, sequence = 2)), store.binding())
    }

    @Test
    fun aDisconnectDuringTheProofIsRefusedWhileItsItemStaysCached() {
        route.publish(PHONE, ordered(sequence = 1))
        // No signal arrives: the commit itself resolves the route again.
        route.reply = { _, nonce ->
            route.connected -= PHONE
            replyBytes(nonce, owner(sequence = 1))
        }
        assertEquals(ReconcileOutcome.UNRESOLVED, reconcile())
        assertNull(production.binding())
        assertNull(production.load())

        // The disconnect is signalled while the proof is pending; it retires the proof even if
        // the phone is back by the commit.
        route.connected += PHONE
        var signalled: ReconcileOutcome? = null
        route.reply = { _, nonce ->
            route.connected -= PHONE
            signalled = reconcile()
            route.connected += PHONE
            replyBytes(nonce, owner(sequence = 1))
        }
        assertEquals(ReconcileOutcome.SUPERSEDED, reconcile())
        assertEquals(ReconcileOutcome.UNRESOLVED, signalled)
        assertNull(production.binding())

        // Reconnected, the cached item is proved afresh.
        route.answer(owner(sequence = 1))
        assertEquals(ReconcileOutcome.ACCEPTED, reconcile())
        assertEquals(SummaryBinding(PHONE, owner(sequence = 1)), production.binding())
    }

    @Test
    fun legacyItemsAreReadOnlyOnRoutesWithoutOrderedOwnership() {
        route.publish(PHONE, ordered = null, legacy = legacy(mode = "live"))
        assertEquals(ReconcileOutcome.ACCEPTED, reconcile())
        assertEquals(SummaryBinding(PHONE, null), production.binding())
        assertTrue(route.requests.isEmpty())

        route.publish(PHONE, ordered(mode = "live", sequence = 1))
        route.answer(owner(sequence = 1))
        assertEquals(ReconcileOutcome.ACCEPTED, reconcile())

        // A downgraded phone app on the same route cannot replace v10 with v9.
        route.publish(PHONE, ordered = null, legacy = legacy(mode = "live", generatedAt = "2026-06-28T00:00:00Z"))
        assertEquals(ReconcileOutcome.REJECTED, reconcile())
        assertEquals(owner(sequence = 1), production.binding()?.owner)
    }

    @Test
    fun aDemoTapAfterLiveIsAcceptedStillNamesTheRenderedDemoOwner() {
        route.publish(PHONE, ordered(mode = "demo", generation = 1, sequence = 1))
        route.answer(owner(generation = 1, sequence = 1))
        assertEquals(ReconcileOutcome.ACCEPTED, reconcile())
        // What the Glance renders, read with its binding.
        val rendered = production.loadBound()!!
        assertEquals(WatchDataMode.DEMO, rendered.summary.dataMode)

        // The store accepts Live before the Glance redraws.
        route.publish(PHONE, ordered(mode = "live", generation = 2, sequence = 2))
        route.answer(owner(generation = 2, sequence = 2))
        assertEquals(ReconcileOutcome.ACCEPTED, reconcile())
        assertEquals(owner(generation = 2, sequence = 2), production.binding()?.owner)

        // A tap on the still-visible Demo names Demo's retired generation, so the phone only
        // resends; the next bound read pairs Live with its own owner.
        val tapped = JSONObject(String(PhoneRefreshRequester.refreshBody(rendered.binding!!.owner!!)))
        assertEquals(1L, tapped.getLong("generation"))
        val redrawn = production.loadBound()!!
        assertEquals(WatchDataMode.LIVE, redrawn.summary.dataMode)
        assertEquals(SummaryBinding(PHONE, owner(generation = 2, sequence = 2)), redrawn.binding)
    }

    @Test
    fun aLegacyCommitRechecksItsRouteAndExactItem() {
        // The phone disconnects while its v9 item is read.
        route.publish(PHONE, ordered = null, legacy = legacy(mode = "live"))
        route.onItem = { if (it == 1) route.connected -= PHONE }
        assertEquals(ReconcileOutcome.UNRESOLVED, reconcile())
        assertNull(production.binding())
        assertNull(production.load())

        // It disconnects while the exact item is read again for the commit; the cache still
        // returns it.
        route.publish(PHONE, ordered = null, legacy = legacy(mode = "live"))
        route.onItem = { if (it == 2) route.connected -= PHONE }
        assertEquals(ReconcileOutcome.UNRESOLVED, reconcile())
        assertNull(production.binding())
        assertNull(production.load())

        // It reconnects and replaces the item with a v10 value while the v9 one is read.
        route.publish(PHONE, ordered = null, legacy = legacy(mode = "live"))
        route.onItem = { if (it == 1) route.publish(PHONE, ordered(mode = "live", sequence = 1)) }
        assertEquals(ReconcileOutcome.SUPERSEDED, reconcile())
        assertNull(production.binding())
        assertFalse(production.orderedRoute(PHONE))

        // The replacement answers in its own attempt, with its proof.
        route.onItem = {}
        route.answer(owner(sequence = 1))
        assertEquals(ReconcileOutcome.ACCEPTED, reconcile())
        assertEquals(owner(sequence = 1), production.binding()?.owner)
    }

    @Test
    fun anOrderedCommitRechecksItsRouteAfterTheExactItemRead() {
        route.publish(PHONE, ordered(mode = "live", sequence = 1))
        route.answer(owner(sequence = 1))
        // The phone disconnects while the exact item is read again after its proof.
        route.onItem = { if (it == 2) route.connected -= PHONE }
        assertEquals(ReconcileOutcome.UNRESOLVED, reconcile())
        assertNull(production.binding())
        assertNull(production.load())

        route.onItem = {}
        route.connected += PHONE
        assertEquals(ReconcileOutcome.ACCEPTED, reconcile())
        assertEquals(owner(sequence = 1), production.binding()?.owner)
    }

    @Test
    fun aReplacementTheFinalRouteInventoryHoldsRefusesTheOlderCommit() {
        // An unbound v9 route: a v10 field appears after the final exact read returned the v9
        // item, before the route inventory is read.
        route.publish(PHONE, ordered = null, legacy = legacy(mode = "live"))
        route.onItem = { if (it == 2) route.publish(PHONE, ordered(mode = "live", sequence = 1)) }
        assertEquals(ReconcileOutcome.SUPERSEDED, reconcile())
        assertNull(production.binding())
        assertNull(production.load())
        assertFalse(production.orderedRoute(PHONE))

        // The replacement answers in its own attempt, with its proof.
        route.onItem = {}
        route.answer(owner(sequence = 1))
        assertEquals(ReconcileOutcome.ACCEPTED, reconcile())
        assertEquals(owner(sequence = 1), production.binding()?.owner)
    }

    @Test
    fun anOrderedReplacementTheFinalRouteInventoryHoldsRefusesTheOlderCommit() {
        // Unbound, a newer v10 item appears after the final exact read of the proven one.
        route.publish(PHONE, ordered(mode = "live", sequence = 1))
        route.answer(owner(sequence = 1))
        route.onItem = { if (it == 2) route.publish(PHONE, ordered(mode = "live", sequence = 2)) }
        assertEquals(ReconcileOutcome.SUPERSEDED, reconcile())
        assertNull(production.binding())
        assertNull(production.load())

        route.onItem = {}
        route.answer(owner(sequence = 2))
        assertEquals(ReconcileOutcome.ACCEPTED, reconcile())
        assertEquals(owner(sequence = 2), production.binding()?.owner)
    }

    @Test
    fun refreshBodyCarriesOnlyTheAcceptedOwner() {
        val body = JSONObject(String(PhoneRefreshRequester.refreshBody(owner(generation = 4, sequence = 9))))
        assertEquals(setOf("installId", "generation"), body.keys().asSequence().toSet())
        assertEquals(INSTALL, body.getString("installId"))
        assertEquals(4L, body.getLong("generation"))
    }

    private fun reconcile(store: WatchSummaryStore = production, revalidate: Boolean = false) =
        WatchSummaryReconciler(store, route) { "nonce-${++nonces}" }.reconcile(revalidate)

    /** A resolution that started and decided, as one needing a proof does. */
    private fun claimed(): Long = production.beginAttempt().also { assertTrue(production.claimAttempt(it)) }

    /**
     * Reports a failed result after a real commit while [failing]; do not claim a reproduced disk
     * fault. Android keeps a failed commit in memory, which the real commit stands in for.
     */
    private fun failingPreferences(failing: () -> Boolean): SharedPreferences =
        object : SharedPreferences by preferences {
            override fun edit(): SharedPreferences.Editor {
                val editor = preferences.edit()
                return object : SharedPreferences.Editor by editor {
                    override fun putString(key: String?, value: String?): SharedPreferences.Editor =
                        also { editor.putString(key, value) }
                    override fun putLong(key: String?, value: Long): SharedPreferences.Editor =
                        also { editor.putLong(key, value) }
                    override fun putStringSet(key: String?, values: MutableSet<String>?): SharedPreferences.Editor =
                        also { editor.putStringSet(key, values) }
                    override fun remove(key: String?): SharedPreferences.Editor = also { editor.remove(key) }
                    override fun commit(): Boolean {
                        assertTrue(editor.commit())
                        return !failing()
                    }
                }
            }
        }

    /**
     * [delegate], counting every write: no store write starts without an editor. The store's
     * change listener cannot show one, since it posts to the main thread and an identical value
     * notifies nothing.
     */
    private class CountingPreferences(private val delegate: SharedPreferences) : SharedPreferences by delegate {
        var writes = 0
            private set

        override fun edit(): SharedPreferences.Editor {
            writes++
            return delegate.edit()
        }
    }

    private fun asset(name: String) =
        testContext.assets.open(name).bufferedReader().use { it.readText() }

    private fun legacy(mode: String = "live", generatedAt: String? = null): String =
        JSONObject(asset("watch_dashboard_summary.json")).apply {
            put("dataMode", mode)
            if (generatedAt != null) put("generatedAt", generatedAt)
        }.toString()

    private fun ordered(
        mode: String = "demo",
        installId: String = INSTALL,
        generation: Long = 1,
        sequence: Long = 1,
    ): String = JSONObject(asset("watch_dashboard_summary_v10_demo.json")).apply {
        put("dataMode", mode)
        put("installId", installId)
        put("generation", generation)
        put("sequence", sequence)
    }.toString()

    private fun owner(installId: String = INSTALL, generation: Long = 1, sequence: Long = 1) =
        SummaryOwner(installId, generation, sequence)

    private fun replyBytes(nonce: String, owner: SummaryOwner) = JSONObject()
        .put("nonce", nonce)
        .put("installId", owner.installId)
        .put("generation", owner.generation)
        .put("sequence", owner.sequence)
        .toString()
        .toByteArray()

    private fun FakeRoute.answer(owner: SummaryOwner) {
        reply = { _, nonce -> replyBytes(nonce, owner) }
    }

    private class FakeRoute : SummaryRoute {
        val connected = mutableSetOf<String>()
        val items = mutableMapOf<String, SummaryItem>()
        val requests = mutableListOf<Pair<String, String>>()

        /** The stored order each request named; null for a bare nonce. */
        val held = mutableListOf<SummaryOwner?>()

        /** Each order an accepted commit named afterwards. */
        val reported = mutableListOf<Pair<String, SummaryOwner>>()
        var reply: (String, String) -> ByteArray? = { _, _ -> null }

        /** Runs as each exact-item read returns, with its count since the hook was set. */
        var onItem: (Int) -> Unit = {}
            set(value) {
                field = value
                reads = 0
            }
        private var reads = 0

        /** Publishes [host]'s item, by default from a connected phone. */
        fun publish(host: String, ordered: String?, legacy: String? = null, connect: Boolean = true) {
            items[host] = SummaryItem(host, ordered, legacy)
            if (connect) connected += host
        }

        override fun connectedHosts(): Set<String> = connected.toSet()
        override fun items(): List<SummaryItem> = items.values.toList()
        override fun item(host: String): SummaryItem? {
            val item = items[host]
            onItem(++reads)
            return item
        }
        override fun requestOwner(host: String, nonce: String, held: SummaryOwner?): ByteArray? {
            requests += host to nonce
            this.held += held
            return reply(host, nonce)
        }
        override fun reportHeld(host: String, nonce: String, held: SummaryOwner) {
            reported += host to held
        }
    }

    private companion object {
        const val PHONE = "phone-node"
        const val OTHER_PHONE = "other-phone-node"
        const val INSTALL = "11111111-1111-4111-8111-111111111111"
        const val OTHER_INSTALL = "22222222-2222-4222-8222-222222222222"
        const val SELECTED_RING_DATA_UNAVAILABLE = "selectedRingDataUnavailable"
        const val TIMEOUT_SECONDS = 10L
    }
}
