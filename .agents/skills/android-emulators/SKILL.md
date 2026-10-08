---
name: android-emulators
description: Operate WardPulse Android phone and Wear OS emulators safely. Use for isolated Android Studio work, AVD input or screenshots, phone-watch pairing or bridge recovery, snapshots, restarts, and actions that could risk emulator state; not for ordinary app implementation or build configuration.
---

# Android Emulators — WardPulse

Use this skill for operational work on the project's configured phone and Wear OS AVDs.

## Source Of Truth

- Read the relevant section of `docs/ANDROID_TOOLCHAIN.md` before acting.
- Start with **Wear emulator navigation**, **Isolated Android Studio display**, **Pairing the
  canonical phone and Wear AVDs**, **Restarting a paired emulator set**, or **Preserving
  emulator state**, according to the task.
- Keep commands, measured coordinates, node IDs, and dated host observations in that document.
  Do not duplicate or reconstruct its procedure from memory in this skill.
- Treat live state as authoritative. If ADB or the display stack is unavailable, do not claim
  device, pairing, screenshot, or UI verification.

## Operating Boundaries

- Use the isolated Xwayland/KWin display only for desktop UI that exists in Android Studio.
- Control and inspect emulators through ADB; they do not need the Studio display.
- Address every ADB command with an explicit, currently discovered device serial.
- Do not substitute Wear network node IDs for ADB serials.
- Prefer deterministic ADB navigation and UI bounds over guessed screen coordinates.

## Isolated Studio Display

- Preserve the owner's desktop session by using the documented nested display stack.
- Keep the verified 1280×800 startup geometry and disable KWin composition. Changing geometry
  with `xrandr` makes root captures unusable; restart the stack when geometry must change.
- Treat keyboard XTEST as the only supported Studio input channel. Pointer XTEST does not reach
  clients in this rootful Xwayland setup.
- Capture the nested root window when visual confirmation is needed.
- Stop Studio, KWin, and Xwayland in the documented reverse order.

## Pairing And Reconnection

- Pair the canonical phone and watch once through Android Studio's **Pair Wearable** flow, using
  keyboard navigation for Studio and ADB for consent on the phone.
- Treat **Failed to enable emulator pairing** as a non-fatal consent timeout only in the
  documented verified flow, when the companion activity is already open at `CONSENT`. Do not
  generalize that conclusion to other pairing failures.
- Verify both `WearableService` views, save both paired states, and confirm the WardPulse receipt
  log plus refreshed complication values as described in the toolchain guide.
- Pairing data lives on `/data`, but the transient transport bridge does not survive emulator
  process restarts. For a known pair reporting `IsConnected=false`, restore the bridge before
  considering another pairing attempt.
- Do not rely on restoring the canonical phone's `paired` snapshot. Use the documented cold-boot
  path; it preserves the pair on `/data`. The Wear snapshot may still be restored normally.

## Preserve Emulator State

- Save a snapshot before any risky action. Snapshot saving requires Vulkan to be disabled in the
  documented Android advanced-features configuration.
- Never delete or recreate an AVD as a troubleshooting step. That loses sign-in, browser
  sessions, system settings, keyboard layout, and pairing state.
- Never clear `com.google.android.gms` data on the watch; doing so destroys the pairing.
- Restart the WardPulse app process with `am kill`, not `am force-stop`, so scheduled
  WorkManager jobs survive. This restriction does not prohibit the documented targeted system-UI
  recovery command.
- Set `/data` capacity before first boot. Do not expect `qemu-img resize` to change a materialized
  image that already has snapshots.

## Before Acting

1. Identify the exact AVDs and discover their current ADB serials.
2. Inspect connection, process, and snapshot state without mutating it.
3. Read the matching toolchain procedure and choose the least state-changing operation.
4. Save recoverable state before any operation that could affect pairing or device data.
5. Verify the requested outcome through ADB or the documented Studio screenshot workflow.

If a proposed recovery conflicts with these preservation rules, stop before changing state and
explain which persisted state it would destroy.
