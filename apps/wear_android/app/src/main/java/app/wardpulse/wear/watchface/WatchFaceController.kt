package app.wardpulse.wear.watchface

import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.withContext

enum class WatchFaceStatus {
    Checking,
    CheckFailed,
    FaceUnsupported,
    SeparateInstall,
    Missing,
    NoCapacity,
    Installed,
    InUse,
    InstallFailed,
    UpdateFailed,
}

enum class WatchFaceManualSelection { PermissionDeclined, ActivationUnavailable }

data class WatchFaceState(
    val status: WatchFaceStatus = WatchFaceStatus.Checking,
    val busy: Boolean = false,
    val updateAvailable: Boolean = false,
    val useAvailable: Boolean = false,
    val manualSelection: WatchFaceManualSelection? = null,
    val awaitingPermission: Boolean = false,
)

class WatchFaceController(
    private val client: WatchFacePushClient,
    private val consent: WatchFaceConsentHistory,
    private val ioDispatcher: CoroutineDispatcher = Dispatchers.IO,
) {
    private val mutex = Mutex()
    private val mutableState = MutableStateFlow(WatchFaceState())
    val state: StateFlow<WatchFaceState> = mutableState.asStateFlow()

    suspend fun check() = operation(WatchFaceStatus.CheckFailed) {
        mutableState.value = WatchFaceState(WatchFaceStatus.Checking, busy = true)
        withFace(observeActive = true) { _, _, _ -> }
    }

    suspend fun install() = operation(WatchFaceStatus.InstallFailed) {
        withFace { bundle, inventory, installed ->
            if (installed == null && inventory.remainingSlots > 0) {
                verifyResult(client.install(bundle), bundle)
                showInstalled()
            }
        }
    }

    suspend fun update() = operation(WatchFaceStatus.UpdateFailed) {
        withFace { bundle, _, installed ->
            if (installed != null && installed.versionCode < bundle.versionCode) {
                val result = client.update(installed.slotId, bundle)
                verifyResult(result, bundle)
                check(result.slotId == installed.slotId)
                // An update result is not a reliable current-active-face observation.
                showInstalled()
            }
        }
    }

    /** Call only for the user's explicit Use action, from the permission launcher's context. */
    suspend fun useWatchFace(launchPermission: () -> Unit) = operation(
        WatchFaceStatus.CheckFailed,
        preserveActivationOnCancellation = true,
    ) {
        var requestPermission = false
        withFace(observeActive = true) { _, _, installed ->
            if (installed == null || !state.value.useAvailable) return@withFace
            if (client.hasActivationPermission()) {
                if (consent.compareAndSet(WatchFaceConsent.Eligible, WatchFaceConsent.ActivationAttempted)) {
                    activate(installed)
                } else {
                    manualSelection()
                }
            } else {
                // The pending marker carries only the explicit action, never a slot ID.
                if (consent.compareAndSet(WatchFaceConsent.Eligible, WatchFaceConsent.PermissionPending)) {
                    requestPermission = true
                    mutableState.value = state.value.copy(useAvailable = false, awaitingPermission = true)
                } else {
                    manualSelection()
                }
            }
        }
        if (requestPermission) {
            try {
                launchPermission()
            } catch (failure: Exception) {
                abandonPermission()
                if (failure is CancellationException) throw failure
            }
        }
    }

    /** A recreated controller may resolve the persisted original action, but never relaunch it. */
    suspend fun onPermissionResult(granted: Boolean) = operation(
        WatchFaceStatus.CheckFailed,
        permissionResult = true,
        preserveActivationOnCancellation = true,
    ) {
        mutableState.value = state.value.copy(awaitingPermission = false)
        withContext(ioDispatcher) {
            if (consent.read() != WatchFaceConsent.PermissionPending) return@withContext
            // Consume the result first: interruption during the fresh read cannot replay consent.
            val history = if (granted) WatchFaceConsent.ActivationAttempted else WatchFaceConsent.PermissionDeclined
            val saved = consent.compareAndSet(WatchFaceConsent.PermissionPending, history)
            manualSelection(requireNotNull(history.manualSelection()))
            if (!saved) {
                mutableState.value = state.value.copy(status = WatchFaceStatus.CheckFailed)
                return@withContext
            }
            withFace { _, _, installed ->
                manualSelection(requireNotNull(history.manualSelection()))
                if (granted && installed != null && client.hasActivationPermission()) activate(installed)
            }
        }
    }

    private suspend fun activate(installed: InstalledWatchFace) {
        manualSelection()
        try {
            client.activate(installed.slotId)
            // Success is historical; only a separate status check can observe In use.
        } catch (failure: Exception) {
            if (failure is CancellationException) throw failure
        } catch (_: LinkageError) {
            // An unavailable platform implementation consumes this attempt as well.
        }
    }

    private suspend fun abandonPermission() = withContext(ioDispatcher) {
        manualSelection(WatchFaceManualSelection.PermissionDeclined)
        consent.compareAndSet(WatchFaceConsent.PermissionPending, WatchFaceConsent.PermissionDeclined)
    }

    private suspend fun withFace(
        observeActive: Boolean = false,
        action: suspend (WatchFaceBundle, WatchFaceInventory, InstalledWatchFace?) -> Unit,
    ) = withContext(ioDispatcher) {
        if (client.sdkInt < 34) {
            mutableState.value = WatchFaceState(WatchFaceStatus.FaceUnsupported, busy = true)
            return@withContext
        }
        if (!reading { client.isSupported() }) {
            mutableState.value = WatchFaceState(WatchFaceStatus.SeparateInstall, busy = true)
            return@withContext
        }
        reading { client.openBundle() }.use { bundle ->
            val inventory = reading {
                require(bundle.packageName == PUSH_FACE_PACKAGE && bundle.versionCode > 0)
                client.list().also { result ->
                    require(result.remainingSlots >= 0)
                    require(result.faces.count { it.packageName == bundle.packageName } <= 1)
                }
            }
            val installed = inventory.faces.singleOrNull { it.packageName == bundle.packageName }
            val active = installed != null && observeActive && reading { client.isActive(bundle.packageName) }
            val history = reading { consent.read() }
            mutableState.value = WatchFaceState(
                status = when {
                    active -> WatchFaceStatus.InUse
                    installed != null -> WatchFaceStatus.Installed
                    inventory.remainingSlots > 0 -> WatchFaceStatus.Missing
                    else -> WatchFaceStatus.NoCapacity
                },
                busy = true,
                updateAvailable = installed != null && installed.versionCode < bundle.versionCode,
                useAvailable = installed != null && !active && history == WatchFaceConsent.Eligible,
                manualSelection = history.manualSelection(),
            )
            action(bundle, inventory, installed)
        }
    }

    private fun verifyResult(result: InstalledWatchFace, bundle: WatchFaceBundle) {
        check(result.packageName == bundle.packageName && result.versionCode == bundle.versionCode)
    }

    private fun showInstalled() {
        mutableState.value = state.value.copy(
            status = WatchFaceStatus.Installed,
            updateAvailable = false,
            useAvailable = state.value.manualSelection == null,
        )
    }

    private fun manualSelection(
        reason: WatchFaceManualSelection = WatchFaceManualSelection.ActivationUnavailable,
    ) {
        mutableState.value = state.value.copy(
            useAvailable = false,
            manualSelection = reason,
            awaitingPermission = false,
        )
    }

    private suspend fun operation(
        failureStatus: WatchFaceStatus,
        permissionResult: Boolean = false,
        preserveActivationOnCancellation: Boolean = false,
        action: suspend () -> Unit,
    ) {
        // A permission result is completion of an existing action, not a duplicate tap.
        if (permissionResult) mutex.lock() else if (!mutex.tryLock()) return
        try {
            if (state.value.busy && !(permissionResult && state.value.awaitingPermission)) return
            mutableState.value = state.value.copy(busy = true)
            try {
                action()
            } catch (failure: Exception) {
                val interruptedActivation = failure is CancellationException && preserveActivationOnCancellation &&
                    state.value.status == WatchFaceStatus.Installed && state.value.manualSelection != null
                if (!interruptedActivation) {
                    mutableState.value = WatchFaceState(
                        if (failure is ReadFailure) WatchFaceStatus.CheckFailed else failureStatus,
                        manualSelection = WatchFaceManualSelection.ActivationUnavailable,
                    )
                }
                if (failure is CancellationException) throw failure
            } catch (_: LinkageError) {
                mutableState.value = WatchFaceState(WatchFaceStatus.CheckFailed)
            } finally {
                mutableState.value = state.value.copy(busy = state.value.awaitingPermission)
            }
        } finally {
            mutex.unlock()
        }
    }

    private suspend fun <T> reading(action: suspend () -> T): T = try {
        action()
    } catch (failure: Exception) {
        if (failure is CancellationException) throw failure
        throw ReadFailure(failure)
    }

    private class ReadFailure(cause: Exception) : Exception(cause)
}

private fun WatchFaceConsent.manualSelection(): WatchFaceManualSelection? = when (this) {
    WatchFaceConsent.Eligible -> null
    WatchFaceConsent.PermissionDeclined -> WatchFaceManualSelection.PermissionDeclined
    WatchFaceConsent.PermissionPending, WatchFaceConsent.ActivationAttempted ->
        WatchFaceManualSelection.ActivationUnavailable
}
