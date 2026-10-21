package app.wardpulse.wear.watchface

import java.util.Collections
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.cancelAndJoin
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class WatchFaceControllerTest {
    @Test
    fun unsupportedDevicesDoNotCreateOrUseTheManager() = runBlocking {
        val client = FakeClient()
        val controller = controller(client)
        client.sdkInt = 33
        controller.check()
        controller.install()
        controller.useWatchFace { client.events += "permission" }
        assertEquals(WatchFaceStatus.FaceUnsupported, controller.state.value.status)
        assertTrue(client.events.isEmpty())

        client.sdkInt = 34
        client.supported = false
        controller.check()
        controller.useWatchFace { client.events += "permission" }
        assertEquals(WatchFaceStatus.SeparateInstall, controller.state.value.status)
        assertEquals(listOf("support", "support"), client.events)
        assertEquals(0, client.events.count { it == "permission" })
    }

    @Test
    fun capabilityManagerAndListFailuresAreRecoverableReadOnlyChecks() = runBlocking {
        val client = FakeClient()
        val controller = controller(client)
        client.supportFailure = IllegalStateException()
        controller.check()
        assertEquals(WatchFaceStatus.CheckFailed, controller.state.value.status)
        client.supportFailure = NoClassDefFoundError()
        controller.check()
        assertEquals(WatchFaceStatus.CheckFailed, controller.state.value.status)
        client.supportFailure = null
        client.listFailure = IllegalStateException()
        controller.check()
        assertEquals(WatchFaceStatus.CheckFailed, controller.state.value.status)
        assertEquals(client.opened, client.closed)

        client.listFailure = null
        controller.check()
        assertEquals(WatchFaceStatus.Installed, controller.state.value.status)
        assertTrue(controller.state.value.updateAvailable)
        assertNoMutations(client)
    }

    @Test
    fun foreignBundleAndAmbiguousInstalledIdentityFailClosed() = runBlocking {
        val client = FakeClient()
        val controller = controller(client)
        client.bundlePackage = "app.wardpulse.watchface"
        controller.install()
        assertEquals(WatchFaceStatus.CheckFailed, controller.state.value.status)
        client.bundlePackage = PUSH_FACE_PACKAGE
        client.inventory = WatchFaceInventory(listOf(own(), own(slot = "duplicate")), 0)
        controller.update()
        assertEquals(WatchFaceStatus.CheckFailed, controller.state.value.status)
        assertNoMutations(client)
        assertEquals(client.opened, client.closed)
    }

    @Test
    fun installationUsesFreshCapacityAndNeverReplacesUnknownOrLegacyFaces() = runBlocking {
        val client = FakeClient()
        val controller = controller(client)
        client.inventory = WatchFaceInventory(emptyList(), 1)
        controller.check()
        assertEquals(WatchFaceStatus.Missing, controller.state.value.status)
        client.inventory = WatchFaceInventory(
            listOf(InstalledWatchFace("occupied", "app.wardpulse.watchface", 1)),
            0,
        )
        controller.install()
        assertEquals(WatchFaceStatus.NoCapacity, controller.state.value.status)
        assertNoMutations(client)

        client.inventory = WatchFaceInventory(emptyList(), 1)
        controller.install()
        assertEquals(WatchFaceStatus.Installed, controller.state.value.status)
        assertTrue(controller.state.value.useAvailable)
        assertEquals(1, client.events.count { it == "install" })
        assertFalse(client.events.contains("active"))
        assertFalse(client.events.contains("activate"))
        assertEquals(client.opened, client.closed)
    }

    @Test
    fun installDoesNotTurnIntoUpdateAndUpdateDoesNotTurnIntoInstall() = runBlocking {
        val client = FakeClient()
        val controller = controller(client)
        controller.install()
        client.inventory = WatchFaceInventory(emptyList(), 1)
        controller.update()
        assertEquals(WatchFaceStatus.Missing, controller.state.value.status)
        assertNoMutations(client)
    }

    @Test
    fun updateUsesFreshExactPackageSlotAndActualNewerBundleVersion() = runBlocking {
        val client = FakeClient()
        val controller = controller(client)
        controller.check()
        client.events.clear()
        client.inventory = WatchFaceInventory(
            listOf(InstalledWatchFace("unknown", "app.wardpulse.watchfacepush.other", 1), own(slot = "fresh")),
            0,
        )
        controller.update()
        assertEquals("fresh", client.updatedSlot)
        assertEquals(WatchFaceStatus.Installed, controller.state.value.status)
        assertFalse(controller.state.value.updateAvailable)
        assertFalse(client.events.contains("active"))
        assertFalse(client.events.contains("activate"))

        client.events.clear()
        for (installedVersion in listOf(2L, 3L)) {
            client.inventory = WatchFaceInventory(listOf(own(version = installedVersion)), 0)
            controller.update()
        }
        assertNoMutations(client)
    }

    @Test
    fun observedInUseCoexistsWithAvailableUpdateButUpdateReportsOnlyInstalled() = runBlocking {
        val client = FakeClient().apply { active = true }
        val controller = controller(client)
        controller.check()
        assertEquals(WatchFaceStatus.InUse, controller.state.value.status)
        assertTrue(controller.state.value.updateAvailable)
        assertFalse(controller.state.value.useAvailable)
        client.events.clear()
        controller.update()
        assertEquals(WatchFaceStatus.Installed, controller.state.value.status)
        assertFalse(client.events.contains("active"))
    }

    @Test
    fun mutationFailureClosesBundleAndRetryRepeatsOnlyTheRequestedOperation() = runBlocking {
        val client = FakeClient()
        val controller = controller(client)
        client.inventory = WatchFaceInventory(emptyList(), 1)
        client.mutation = { error("Unavailable service") }
        controller.install()
        assertEquals(WatchFaceStatus.InstallFailed, controller.state.value.status)
        assertFalse(controller.state.value.busy)
        client.inventory = WatchFaceInventory(listOf(own()), 0)
        controller.update()
        assertEquals(WatchFaceStatus.UpdateFailed, controller.state.value.status)

        client.mutation = {}
        controller.update()
        assertEquals(WatchFaceStatus.Installed, controller.state.value.status)
        assertEquals(1, client.events.count { it == "install" })
        assertEquals(2, client.events.count { it == "update" })
        assertFalse(client.events.contains("activate"))
        assertEquals(client.opened, client.closed)
    }

    @Test
    fun busyOperationsSuppressDuplicatesAndCancellationClosesTheirDescriptor() = runBlocking {
        val client = FakeClient()
        val controller = controller(client)
        val completion = CompletableDeferred<Unit>()
        client.mutation = { completion.await() }
        val job = launch(start = CoroutineStart.UNDISPATCHED) { controller.update() }
        assertTrue(controller.state.value.busy)
        controller.update()
        controller.install()
        controller.check()
        controller.useWatchFace { client.events += "permission" }
        assertEquals(0, client.events.count { it == "permission" })
        assertEquals(1, client.events.count { it == "list" })
        assertEquals(1, client.events.count { it == "update" })
        job.cancelAndJoin()
        assertEquals(client.opened, client.closed)
        assertFalse(controller.state.value.busy)

        client.mutation = {}
        controller.check()
        assertEquals(WatchFaceStatus.Installed, controller.state.value.status)
    }

    @Test
    fun explicitUsePersistsBeforePermissionAndResolvesFreshSlotAfterRecreation() = runBlocking {
        val client = FakeClient()
        val consent = FakeConsent(client.events)
        val first = controller(client, consent)
        first.useWatchFace {
            assertEquals(client.opened, client.closed)
            client.events += "permission"
        }
        assertEquals(WatchFaceConsent.PermissionPending, consent.saved)
        assertTrue(first.state.value.busy)
        assertTrue(client.events.indexOf("save:PermissionPending") < client.events.indexOf("permission"))
        first.useWatchFace { client.events += "permission" }
        first.update()
        assertEquals(1, client.events.count { it == "permission" })

        val recreated = controller(client, consent)
        recreated.check()
        assertFalse(recreated.state.value.useAvailable)
        assertFalse(recreated.state.value.busy)
        client.inventory = WatchFaceInventory(listOf(own(slot = "returned")), 0)
        client.permission = true
        recreated.onPermissionResult(true)
        assertEquals("returned", client.activatedSlot)
        assertTrue(client.events.indexOf("save:ActivationAttempted") < client.events.indexOf("activate"))
        recreated.onPermissionResult(true)
        recreated.useWatchFace { client.events += "permission" }
        assertEquals(1, client.events.count { it == "permission" })
        assertEquals(1, client.events.count { it == "activate" })
        assertEquals(WatchFaceStatus.Installed, recreated.state.value.status)
    }

    @Test
    fun permissionReturnWaitsForAnOverlappingReadAfterRecreation() = runBlocking {
        val client = FakeClient()
        val consent = FakeConsent(client.events)
        controller(client, consent).useWatchFace { client.events += "permission" }
        val recreated = controller(client, consent)
        client.permission = true
        val completion = CompletableDeferred<Unit>()
        client.listing = { completion.await() }
        val checking = launch(start = CoroutineStart.UNDISPATCHED) { recreated.check() }
        val returning = launch(start = CoroutineStart.UNDISPATCHED) { recreated.onPermissionResult(true) }
        assertTrue(returning.isActive)
        client.inventory = WatchFaceInventory(listOf(own(slot = "returned")), 0)
        completion.complete(Unit)
        checking.join()
        returning.join()
        assertEquals("returned", client.activatedSlot)
        assertEquals(1, client.events.count { it == "activate" })
        assertEquals(1, client.events.count { it == "permission" })
        assertFalse(recreated.state.value.busy)
    }

    @Test
    fun denialOrDismissalPersistsAndNeverReplaysEvenIfPermissionIsLaterGranted() = runBlocking {
        val client = FakeClient()
        val consent = FakeConsent(client.events)
        controller(client, consent).useWatchFace { client.events += "permission" }
        val recreated = controller(client, consent)
        recreated.onPermissionResult(false)
        assertEquals(WatchFaceConsent.PermissionDeclined, consent.saved)
        assertEquals(WatchFaceStatus.Installed, recreated.state.value.status)
        assertEquals(WatchFaceManualSelection.PermissionDeclined, recreated.state.value.manualSelection)
        client.permission = true
        controller(client, consent).useWatchFace { client.events += "permission" }
        recreated.onPermissionResult(true)
        assertEquals(1, client.events.count { it == "permission" })
        assertNoMutations(client)
    }

    @Test
    fun failureDuringPermissionReturnConsumesTheActionWithoutReplayingIt() = runBlocking {
        val client = FakeClient()
        val consent = FakeConsent(client.events)
        controller(client, consent).useWatchFace { client.events += "permission" }
        client.permission = true
        client.listFailure = IllegalStateException()
        val recreated = controller(client, consent)
        recreated.onPermissionResult(true)
        assertEquals(WatchFaceStatus.CheckFailed, recreated.state.value.status)
        assertEquals(WatchFaceConsent.ActivationAttempted, consent.saved)
        client.listFailure = null
        recreated.check()
        recreated.onPermissionResult(true)
        recreated.useWatchFace { client.events += "permission" }
        assertEquals(1, client.events.count { it == "permission" })
        assertFalse(recreated.state.value.useAvailable)
        assertNoMutations(client)
        assertEquals(client.opened, client.closed)
    }

    @Test
    fun existingGrantStillRequiresExplicitUseAndSuccessNeverProvesCurrentActivity() = runBlocking {
        val client = FakeClient().apply { permission = true }
        val consent = FakeConsent(client.events)
        val controller = controller(client, consent)
        controller.check()
        assertNoMutations(client)
        controller.useWatchFace { client.events += "permission" }
        assertEquals(WatchFaceConsent.ActivationAttempted, consent.saved)
        assertEquals(WatchFaceStatus.Installed, controller.state.value.status)
        controller.check()
        assertEquals(WatchFaceStatus.Installed, controller.state.value.status)
        controller.useWatchFace { client.events += "permission" }
        assertEquals(0, client.events.count { it == "permission" })
        assertEquals(1, client.events.count { it == "activate" })
    }

    @Test
    fun overlappingOwnersClaimPermissionOrExistingGrantActivationOnlyOnce() = runBlocking {
        for (granted in listOf(false, true)) {
            val clients = List(2) { FakeClient().apply { permission = granted } }
            val consent = FakeConsent(clients.first().events)
            val ready = CountDownLatch(2)
            val release = CountDownLatch(1)
            consent.beforeClaim = {
                // Both controllers have already read Eligible through their separate mutexes.
                ready.countDown()
                assertTrue(release.await(5, TimeUnit.SECONDS))
            }
            val owners = clients.map { controller(it, consent) }
            val attempts = owners.mapIndexed { index, owner ->
                async(Dispatchers.Default) {
                    owner.useWatchFace { clients[index].events += "permission" }
                }
            }
            try {
                assertTrue(ready.await(5, TimeUnit.SECONDS))
                release.countDown()
                attempts.awaitAll()
                consent.beforeClaim = {}

                val history = if (granted) WatchFaceConsent.ActivationAttempted else WatchFaceConsent.PermissionPending
                assertEquals(history, consent.saved)
                assertEquals(1, clients.first().events.count { it == "save:$history" })
                assertEquals(if (granted) 0 else 1, clients.sumOf { it.events.count { it == "permission" } })
                assertEquals(if (granted) 1 else 0, clients.sumOf { it.events.count { it == "activate" } })
                clients.forEach { assertEquals(it.opened, it.closed) }

                // A new owner cannot replay the winner, even after the user changes faces.
                clients.forEach { client ->
                    controller(client, consent).useWatchFace { client.events += "permission" }
                }
                assertEquals(if (granted) 0 else 1, clients.sumOf { it.events.count { it == "permission" } })
                assertEquals(if (granted) 1 else 0, clients.sumOf { it.events.count { it == "activate" } })
            } finally {
                release.countDown()
                attempts.forEach { it.cancelAndJoin() }
            }
        }
    }

    @Test
    fun overlappingPermissionResultsHaveOneConsumerBeforeFreshLookup() = runBlocking {
        for (granted in listOf(false, true)) {
            val clients = List(2) { index ->
                FakeClient().apply {
                    permission = true
                    inventory = WatchFaceInventory(listOf(own(slot = "returned-$index")), 0)
                }
            }
            val consent = FakeConsent(clients.first().events).apply { saved = WatchFaceConsent.PermissionPending }
            val ready = CountDownLatch(2)
            val release = CountDownLatch(1)
            consent.beforeClaim = {
                ready.countDown()
                assertTrue(release.await(5, TimeUnit.SECONDS))
            }
            val owners = clients.map { controller(it, consent) }
            val results = owners.map { owner -> async(Dispatchers.Default) { owner.onPermissionResult(granted) } }
            try {
                assertTrue(ready.await(5, TimeUnit.SECONDS))
                release.countDown()
                results.awaitAll()
                consent.beforeClaim = {}

                val history = if (granted) WatchFaceConsent.ActivationAttempted else WatchFaceConsent.PermissionDeclined
                assertEquals(history, consent.saved)
                assertEquals(1, clients.first().events.count { it == "save:$history" })
                assertEquals(1, clients.sumOf { it.events.count { it == "list" } })
                assertEquals(if (granted) 1 else 0, clients.sumOf { it.events.count { it == "activate" } })
                if (granted) {
                    clients.forEachIndexed { index, client ->
                        if (client.activatedSlot != null) assertEquals("returned-$index", client.activatedSlot)
                    }
                }
                clients.forEach { assertEquals(it.opened, it.closed) }

                owners.forEach { it.onPermissionResult(!granted) }
                clients.forEach { client ->
                    controller(client, consent).useWatchFace { client.events += "permission" }
                }
                assertEquals(history, consent.saved)
                assertEquals(0, clients.sumOf { it.events.count { it == "permission" } })
                assertEquals(if (granted) 1 else 0, clients.sumOf { it.events.count { it == "activate" } })
            } finally {
                release.countDown()
                results.forEach { it.cancelAndJoin() }
            }
        }
    }

    @Test
    fun permissionLaunchAbandonmentCannotOverwriteAnotherOwnersCompletedResult() = runBlocking {
        val client = FakeClient()
        val consent = FakeConsent(client.events)
        val first = controller(client, consent)
        val recreated = controller(client, consent)
        first.useWatchFace {
            client.events += "permission"
            client.permission = true
            launch(start = CoroutineStart.UNDISPATCHED) { recreated.onPermissionResult(true) }
            error("Activity lost after result delivery")
        }
        assertEquals(WatchFaceConsent.ActivationAttempted, consent.saved)
        recreated.onPermissionResult(true)
        recreated.useWatchFace { client.events += "permission" }
        assertEquals(1, client.events.count { it == "permission" })
        assertEquals(1, client.events.count { it == "activate" })
        assertEquals(client.opened, client.closed)
    }

    @Test
    fun persistenceFailurePreventsPermissionAndActivationEffects() = runBlocking {
        val client = FakeClient()
        val consent = FakeConsent(client.events).apply { writable = false }
        val controller = controller(client, consent)
        controller.useWatchFace { client.events += "permission" }
        assertEquals(0, client.events.count { it == "permission" })
        assertFalse(controller.state.value.useAvailable)
        client.permission = true
        controller.useWatchFace { client.events += "permission" }
        assertEquals(0, client.events.count { it == "permission" })
        consent.saved = WatchFaceConsent.PermissionPending
        val recreated = controller(client, consent)
        recreated.onPermissionResult(true)
        assertEquals(WatchFaceStatus.CheckFailed, recreated.state.value.status)
        assertFalse(recreated.state.value.busy)
        assertEquals(WatchFaceManualSelection.ActivationUnavailable, recreated.state.value.manualSelection)
        assertNoMutations(client)
    }

    @Test
    fun permissionLaunchFailureConsumesConsentAndLeavesManualGuidance() = runBlocking {
        val client = FakeClient()
        val consent = FakeConsent(client.events)
        val controller = controller(client, consent)
        controller.useWatchFace {
            client.events += "permission"
            error("Destroyed activity")
        }
        assertEquals(WatchFaceConsent.PermissionDeclined, consent.saved)
        assertEquals(WatchFaceManualSelection.PermissionDeclined, controller.state.value.manualSelection)
        assertFalse(controller.state.value.busy)
        controller.useWatchFace { client.events += "permission" }
        assertEquals(1, client.events.count { it == "permission" })
        assertNoMutations(client)
    }

    @Test
    fun interruptedOrFailedActivationCannotReplayAfterRecreation() = runBlocking {
        val client = FakeClient().apply { permission = true }
        val consent = FakeConsent(client.events)
        val completion = CompletableDeferred<Unit>()
        client.activation = { completion.await() }
        val first = controller(client, consent)
        val job = launch(start = CoroutineStart.UNDISPATCHED) {
            first.useWatchFace { client.events += "permission" }
        }
        assertEquals(WatchFaceConsent.ActivationAttempted, consent.saved)
        job.cancelAndJoin()
        assertEquals(client.opened, client.closed)
        assertFalse(first.state.value.busy)
        assertEquals(WatchFaceStatus.Installed, first.state.value.status)
        val recreated = controller(client, consent)
        recreated.check()
        recreated.useWatchFace { client.events += "permission" }
        assertEquals(0, client.events.count { it == "permission" })
        assertEquals(1, client.events.count { it == "activate" })
        assertEquals(WatchFaceManualSelection.ActivationUnavailable, recreated.state.value.manualSelection)

        val failedClient = FakeClient().apply {
            permission = true
            activation = { error("Platform activation opportunity exhausted") }
        }
        val failed = controller(failedClient)
        failed.useWatchFace { failedClient.events += "permission" }
        assertEquals(WatchFaceStatus.Installed, failed.state.value.status)
        assertFalse(failed.state.value.useAvailable)
        failed.useWatchFace { failedClient.events += "permission" }
        assertEquals(0, failedClient.events.count { it == "permission" })
        assertEquals(1, failedClient.events.count { it == "activate" })
    }

    private fun controller(client: FakeClient, consent: FakeConsent = FakeConsent(client.events)) =
        WatchFaceController(client, consent, Dispatchers.Unconfined)

    private fun assertNoMutations(client: FakeClient) {
        assertTrue(client.events.none { it in listOf("install", "update", "activate") })
    }

    private class FakeConsent(private val events: MutableList<String>) : WatchFaceConsentHistory {
        @Volatile
        var saved = WatchFaceConsent.Eligible
        var writable = true
        var beforeClaim: () -> Unit = {}
        override fun read() = saved
        override fun compareAndSet(expected: WatchFaceConsent, consent: WatchFaceConsent): Boolean {
            beforeClaim()
            return synchronized(this) {
                if (saved != expected) return@synchronized false
                events += "save:$consent"
                if (writable) saved = consent
                writable
            }
        }
    }

    private class FakeClient : WatchFacePushClient {
        override var sdkInt = 36
        var supported = true
        var supportFailure: Throwable? = null
        var listFailure: Exception? = null
        var bundlePackage = PUSH_FACE_PACKAGE
        var inventory = WatchFaceInventory(listOf(own()), 0)
        var active = false
        var permission = false
        var opened = 0
        var closed = 0
        var updatedSlot: String? = null
        var activatedSlot: String? = null
        var mutation: suspend () -> Unit = {}
        var listing: suspend () -> Unit = {}
        var activation: suspend () -> Unit = {}
        val events: MutableList<String> = Collections.synchronizedList(mutableListOf())

        override fun isSupported(): Boolean {
            events += "support"
            supportFailure?.let { throw it }
            return supported
        }

        override fun openBundle(): WatchFaceBundle {
            opened++
            return object : WatchFaceBundle {
                override val packageName = bundlePackage
                override val versionCode = 2L
                override fun close() { closed++ }
            }
        }

        override suspend fun list(): WatchFaceInventory {
            events += "list"
            listing()
            listFailure?.let { throw it }
            return inventory
        }

        override suspend fun isActive(packageName: String): Boolean {
            assertEquals(PUSH_FACE_PACKAGE, packageName)
            events += "active"
            return active
        }

        override suspend fun install(bundle: WatchFaceBundle): InstalledWatchFace {
            events += "install"
            mutation()
            return own(version = bundle.versionCode)
        }

        override suspend fun update(slotId: String, bundle: WatchFaceBundle): InstalledWatchFace {
            events += "update"
            updatedSlot = slotId
            mutation()
            return own(slot = slotId, version = bundle.versionCode)
        }

        override fun hasActivationPermission() = permission
        override suspend fun activate(slotId: String) {
            events += "activate"
            activatedSlot = slotId
            activation()
        }
    }

    companion object {
        private fun own(slot: String = "original", version: Long = 1) =
            InstalledWatchFace(slot, PUSH_FACE_PACKAGE, version)
    }
}
