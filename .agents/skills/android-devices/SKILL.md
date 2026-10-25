---
name: android-devices
description: Operate physical Android phones and Wear OS watches through authorized USB or wireless ADB for inspection, updates, navigation and captures. Use android-emulators for AVDs.
---

# Physical Android devices — WardPulse

Use this common entrypoint for real phones and watches connected through developer-mode
ADB. Keep existing owner authorization and device state intact. This skill does not grant
new access, authorize unrelated actions or transfer code authorship outside Runner.

## Read the relevant detail

| Need | Reference |
| --- | --- |
| Identify/reconnect a device or use its local profile | [Connection and local profile](references/connection.md) |
| Work with the owner's phone | [Phone](references/phone.md) |
| Work with a physical Wear OS watch | [Wear OS](references/wear.md) |
| Execute the relevant existing ADB operator commands | [Command templates](references/commands.md) |

For AVDs, snapshots, emulator pairing or Studio, use
[android-emulators](../android-emulators/SKILL.md). Do not apply its reset/recovery helpers
to physical devices. For app implementation, use
[android-surfaces](../android-surfaces/SKILL.md); for documentation images, also apply
[user-docs](../user-docs/SKILL.md).

## Establish the target

Discover current ADB transports and bind the intended physical device to the local
profile's expected model, hardware ID and SDK before mutating it. A remembered endpoint,
network node ID, matching model alone or visible watch face is insufficient identity.
Use an explicit, currently verified serial for every device-targeted ADB call; discovery
commands have no target. USB and wireless aliases can represent the same physical device.
On mismatch or unavailable identity, keep mutations pending until the target is resolved.

Read [connection.md](references/connection.md) before loading the skill-local `.env`.
The tracked `.env.example` contains empty documented fields only. Real values belong in
the ignored, mode-600 `.env`; never create or expose real values in a tracked file.
Parse only allowlisted fields as literal data, never execute/source/eval the file or print
its contents. Unlock material stays with the authorized operator, outside agent packets,
commands shown in logs, screenshots, proofs and durable notes.

## Continue within the authorized task

Carry forward the owner's existing permission for routine inspection and scoped updates;
do not ask again for every reconnection, screenshot or ordinary authorized action.
Respect a device the owner has taken away or is using. A working emulator does not prove
that the physical device is connected, unlocked or verified.

Choose the least state-changing operation. For an authorized update, check the target
package and signing certificate, then use an in-place install preserving app data.
Do not automatically uninstall, clear app/account data, reset pairing, reboot, disable
security, run adb root or change system-wide ADB state to recover a failed check.
If those actions are actually needed, explain the concrete state at risk and use the
owner's explicit task scope; hypothetical risk does not create a new approval flow.

## Verify the actual interaction

Check keyguard and the visible app immediately before each scenario. A face can be visible
while locked, and charging SystemUI can cover a resumed Activity. After an authorized
unlock, perform the scenario and its observations in one bounded sequence; model/tool
delays can let the watch relock. Do not mistake a lock-screen `--` for lost provider data.

Use only an explicitly owner-authorized unlock method/material. Confirm current UI
geometry before input. After rejection, stop automated input and inspect the cause;
existing owner authorization persists, without a mandatory new approval request.
Never guess, retry in a loop or disable the lock. The
[Wear reference](references/wear.md) owns pattern-input details.

Record sanitized measurements, actual visible outcomes and any nonsecret current endpoint
in ignored working notes. Exclude unlock/authentication frames from public captures and
proofs; never save a pattern while its path is visible. Report unavailable physical checks as
pending, with emulator results identified separately. Preserve accounts, pairing,
credentials, scheduled work and the owner's requested launcher arrangement.
