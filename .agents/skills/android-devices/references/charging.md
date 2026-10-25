# Physical watch UI while charging

Use verified physical identity and the private profile/unlock rules from [Wear OS](wear.md)
and [command templates](commands.md). This is a stateful route, not a blind key sequence.

## Verified route, 2026-10-25

On the owner's OnePlus Watch 2, SDK 34, 466×466, Root observed release-app Glance while AC was
true, battery status was **5 (FULL)** at 100%, keyguard was not showing and security stayed
enabled. Full `dumpsys window` identified WardPulse MainActivity as the focused window/app.
AC true with FULL is valid powered-state evidence; status **2 (CHARGING)** is not required.
This proves access while on the charger, not fresh provider data or face/AOD acceptance.
The exact dismissal route was observed on this watch; other brands' normal controls may vary.

1. Reconfirm identity, wake with key 224, then inspect actual wakefulness, focus and UI.
   Key 224 can leave `mWakefulness=Asleep` with the charging/offload UI visible. In that
   observed state, ONE normal primary-stem key 264 woke it to Awake/keyguard. Observe the
   actual focus/UI transition before a lock tap; this is not an unconditional key chain.
   If charging UI still covers the app while Awake, use a normal horizontal Back swipe
   **from the left edge**, sized from the CURRENT viewport. Wait for observable UI idle
   and inspect the result; the verified route exposed the locked WardPulse face.
2. Tap its currently visible lock control at verified current bounds. Wait for the settled
   UNENTERED unlock grid and inspect its geometry privately. A visible face is not unlock
   proof. Do not reuse remembered coordinates or capture an entered authentication path.
3. Prepare the owner's authorized continuous pattern from the private profile, with DOWN
   at its first resolved node, MOVE through every remaining node and an explicit last MOVE
   before UP at the last node. Keep secrets and derived coordinates private and ephemeral.
   Feed credential-input commands through **`adb shell -T` stdin**, not literal tool text,
   echo, shell trace, command arguments, logs or delegated context.
4. After ONE gesture, use a bounded observation of keyguard `showing=false` for **up to five
   seconds**. An immediate unchanged flag is not rejection proof. Inspect an explicit
   rejection if present; otherwise wait for the observable result before classifying it.
   On timeout or rejection, stop automated credential input and inspect state/cause;
   existing authorization persists, without guessing or input retry loops.
5. Immediately enter the app with `am start -W` only if the actual launcher/face entry path
   is not itself under test. Observe the intended native page, keyguard, external power and
   full-window focus in the SAME bounded batch. Model/tool round trips can outlast unlock.
   Wait for observed UI idle before input/capture; fixed 0.3/0.6-second assumptions proved
   inadequate. Save an app frame only after keyguard is not showing AND the page is settled;
   elapsed sleep time alone is not a PASS. Never save an authentication frame.
6. Accept this scenario only when the intended visible page, unlocked state, correct focus
   and actual external power coexist. If the screen relocks or the overlay returns, classify
   the new state instead of treating a resumed Activity or successful command as a PASS.

Prepare the entire unlock, bounded observation, app entry and proof collection before
credential input. Do not pause for a model round trip between those operations. Use existing
operator capabilities; this reference does not provide a new parser, helper or retry script.

## Relevant existing command templates

Resolve every variable privately as in commands.md. The swipe coordinates describe a normal
Back gesture, not an unlock secret. The `shell -T` invocation receives privately prepared
in-memory credential commands on stdin; do not persist or print that input.

```sh
adb -s "$DEVICE_SERIAL" shell input keyevent 224
adb -s "$DEVICE_SERIAL" shell input keyevent 264
adb -s "$DEVICE_SERIAL" shell input touchscreen swipe "$LEFT_EDGE_X" "$BACK_Y" "$INNER_X" "$BACK_Y" "$SWIPE_MS"
adb -s "$DEVICE_SERIAL" shell -T
adb -s "$DEVICE_SERIAL" shell am start -W -n "$APP_COMPONENT"
adb -s "$DEVICE_SERIAL" shell dumpsys window policy
adb -s "$DEVICE_SERIAL" shell dumpsys window
adb -s "$DEVICE_SERIAL" shell dumpsys power
adb -s "$DEVICE_SERIAL" shell dumpsys battery
```

Use full `dumpsys window` for actual focus; the `windows` subcommand alone did not supply
the needed focus evidence. Inspect the current rendered page too. Diagnostic app starts
are inappropriate substitutes when the entry/navigation route itself is under test.

## Evidence and boundaries

The older successful charging record had AC true, status 2 and unlocked Glance, but its
exact dismissal key was not preserved. Keep that historical distinction; the route above
was separately observed on October 25. Wake/Back-key/app-start alone had left the overlay
visible; a primary-stem package transition alone had not confirmed an unlock grid.
A later complete observation confirmed the asleep-charging primary-stem recovery, current
grid, authorized unlock, bounded keyguard wait and settled face/Glance access with AC true,
FULL at 100% and security enabled. It does not retroactively validate the earlier transition.

An early immediate keyguard check misclassified a successful gesture as unconfirmed:
later state recorded unlock, then automatic relock about a minute later. Another successful
unlock relocked during a model round trip before capture. These observations require the
bounded wait and single prepared observation batch. Do not replay input while its outcome
is unconfirmed or after an explicit rejection. A later CONFIRMED automatic relock is a new
stateful scenario under the existing authorization: reconfirm current UI/grid before unlock.

Keep actual provider Stale/error diagnostic frames private unless documenting that exact
state. Never toggle AC/battery state, force-stop physical SystemUI/offload, disable security,
erase data or substitute emulator reset helpers. Try the verified state-dependent route
before asking the owner to remove the charger; report any remaining concrete blocker.
