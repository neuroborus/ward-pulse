package app.wardpulse.wear.watchface

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.wear.compose.foundation.lazy.TransformingLazyColumn
import androidx.wear.compose.foundation.lazy.rememberTransformingLazyColumnState
import androidx.wear.compose.material3.Button
import androidx.wear.compose.material3.Card
import androidx.wear.compose.material3.ListHeader
import androidx.wear.compose.material3.MaterialTheme
import androidx.wear.compose.material3.ScreenScaffold
import androidx.wear.compose.material3.SurfaceTransformation
import androidx.wear.compose.material3.Text
import androidx.wear.compose.material3.lazy.rememberTransformationSpec
import androidx.wear.compose.material3.lazy.transformedHeight

@Composable
internal fun WatchFaceScreen(
    state: WatchFaceState,
    onCheck: () -> Unit,
    onInstall: () -> Unit,
    onUpdate: () -> Unit,
    onUse: () -> Unit,
) {
    // Observe once per navigation entry, including a fresh controller after process death.
    // Activity recreation alone must not check activity immediately after an update.
    var checkedOnVisit by rememberSaveable { mutableStateOf(false) }
    LaunchedEffect(Unit) {
        if (!checkedOnVisit || (state.status == WatchFaceStatus.Checking && !state.busy)) {
            checkedOnVisit = true
            onCheck()
        }
    }
    val scrollState = rememberTransformingLazyColumnState()
    val transformationSpec = rememberTransformationSpec()
    val canUse = state.status == WatchFaceStatus.Installed && !state.updateAvailable &&
        (state.useAvailable || state.awaitingPermission)
    val manualSelection = state.manualSelection.takeIf { state.status == WatchFaceStatus.Installed }

    ScreenScaffold(scrollState = scrollState) { contentPadding ->
        TransformingLazyColumn(
            state = scrollState,
            contentPadding = contentPadding,
            verticalArrangement = Arrangement.spacedBy(4.dp),
        ) {
            item { ListHeader { Text("Watch face") } }
            item {
                Card(
                    modifier = Modifier
                        .fillMaxWidth()
                        .transformedHeight(this, transformationSpec),
                    transformation = SurfaceTransformation(transformationSpec),
                ) {
                    Text(
                        when (state.status) {
                            WatchFaceStatus.Checking -> "Checking watch face…"
                            WatchFaceStatus.CheckFailed -> "Could not check the watch face."
                            WatchFaceStatus.FaceUnsupported -> "WardPulse Watch Face requires Wear OS 5 or later."
                            WatchFaceStatus.SeparateInstall ->
                                "Install WardPulse Watch Face separately, then select it from your watch-face list."
                            WatchFaceStatus.Missing -> "Install the WardPulse watch face."
                            WatchFaceStatus.NoCapacity -> "Watch-face installation is unavailable."
                            WatchFaceStatus.Installed -> "Installed"
                            WatchFaceStatus.InUse -> "In use"
                            WatchFaceStatus.InstallFailed -> "Could not install the watch face."
                            WatchFaceStatus.UpdateFailed -> "Could not update the watch face."
                        },
                    )
                    if (state.updateAvailable) {
                        Text("Watch face update available", color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                }
            }
            if (state.status == WatchFaceStatus.NoCapacity) {
                item {
                    Card(
                        modifier = Modifier
                            .fillMaxWidth()
                            .transformedHeight(this, transformationSpec),
                        transformation = SurfaceTransformation(transformationSpec),
                    ) {
                        Text("Another watch face is using the available slot. Check again after that slot is free.")
                    }
                }
            }
            if (state.updateAvailable) {
                item {
                    Button(
                        onClick = onUpdate,
                        enabled = !state.busy,
                        modifier = Modifier
                            .fillMaxWidth()
                            .transformedHeight(this, transformationSpec),
                        transformation = SurfaceTransformation(transformationSpec),
                    ) {
                        Text("Update watch face")
                    }
                }
            }
            if (canUse || manualSelection != null) {
                item {
                    Card(
                        modifier = Modifier
                            .fillMaxWidth()
                            .transformedHeight(this, transformationSpec),
                        transformation = SurfaceTransformation(transformationSpec),
                    ) {
                        if (canUse) {
                            Text("Make WardPulse your watch face.")
                            Text(
                                "This will replace your current watch face.",
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        } else {
                            Text(
                                when (manualSelection) {
                                    WatchFaceManualSelection.PermissionDeclined ->
                                        "You can select WardPulse manually from your watch-face list."
                                    else -> "To use WardPulse, choose it from your watch-face list."
                                },
                            )
                        }
                    }
                }
            }
            if (manualSelection != null) {
                item {
                    Card(
                        modifier = Modifier
                            .fillMaxWidth()
                            .transformedHeight(this, transformationSpec),
                        transformation = SurfaceTransformation(transformationSpec),
                    ) {
                        Text("Touch and hold your current watch face, then find WardPulse in the watch-face list.")
                    }
                }
            }
            val action = when (state.status) {
                WatchFaceStatus.Installed -> if (canUse) "Use watch face" to onUse else null
                WatchFaceStatus.Missing -> "Install watch face" to onInstall
                WatchFaceStatus.InstallFailed -> "Try again" to onInstall
                WatchFaceStatus.UpdateFailed -> "Try again" to onUpdate
                WatchFaceStatus.Checking,
                WatchFaceStatus.CheckFailed,
                WatchFaceStatus.NoCapacity,
                -> "Check again" to onCheck
                else -> null
            }
            if (action != null) {
                item {
                    Button(
                        onClick = action.second,
                        enabled = !state.busy && state.status != WatchFaceStatus.Checking,
                        modifier = Modifier
                            .fillMaxWidth()
                            .transformedHeight(this, transformationSpec),
                        transformation = SurfaceTransformation(transformationSpec),
                    ) {
                        Text(action.first)
                    }
                }
            }
        }
    }
}
