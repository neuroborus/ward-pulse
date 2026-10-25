# Physical watch UI while charging

Use the verified identity, private profile and unlock rules from [Wear OS](wear.md) and
[command templates](commands.md). Charging is a state to verify, not an automatic UI blocker.

## What was actually proved

A previous physical run confirmed `AC powered: true`, battery `status: 2`, secure lock
enabled, keyguard `showing=false` and actual WardPulse Glance visible at the same time.
The route was charging-screen dismissal, a confirmed unfilled unlock screen, authorized
unlock and app entry. The exact successful charging-dismissal key was not preserved;
do not invent one or call a new key sequence previously verified.

In the later obstructed case, wake (224), Back (4) and app start left the charging overlay
visible. Primary stem (264) changed the foreground system package, but an unlock grid was
not confirmed. That transition proves neither dismissal nor unlock nor app visibility.

## Follow the currently visible state

1. Reconfirm physical identity and current transport. Inspect actual battery, keyguard,
   foreground and rendered UI. Keep only sanitized state observations.
2. If charging UI covers the app, use the current watch's normal dismissal action, then
   inspect the resulting UI immediately. Wake, Back or primary stem are distinct actions,
   not an unconditional sequence or retry loop. Use an appropriate observed action once;
   do not repeat the already-failed route without a changed state or diagnosed cause.
3. If the result is a face, launcher or another system screen, it still is not unlock proof.
   Expose the ordinary unlock UI through an actually available normal control. Confirm the
   current unfilled grid/PIN geometry privately before any authorized credential input.
4. Prepare unlock, keyguard verification, normal app entry and scenario observation as one
   bounded batch under the existing command reference. Keep the secure lock enabled.
   Proceed only when keyguard is not showing AND the intended app UI is actually visible.
5. Recheck that charging is still true during the observed scenario. Accept charging UI
   access only when actual charging, unlocked state and the intended visible page coexist.
   A resumed Activity, package transition or successful input command alone is insufficient.

If the overlay returns, classify the new visible state before another scenario. If no
normal route exposes unlock/app UI, record the exact blocker and leave that check Pending;
only then request necessary owner help. Preserve earlier successful charging evidence
without borrowing it as acceptance of the current build or scenario.

## Relevant existing command templates

Use only the action justified by the current UI; variables must already be privately
resolved as in [commands.md](commands.md). The key values below are Android constants,
not a guaranteed unlock/dismissal recipe.

```sh
adb -s "$DEVICE_SERIAL" shell dumpsys battery
adb -s "$DEVICE_SERIAL" shell input keyevent 224
adb -s "$DEVICE_SERIAL" shell input keyevent 4
adb -s "$DEVICE_SERIAL" shell input keyevent 264
adb -s "$DEVICE_SERIAL" shell am start -n "$APP_COMPONENT"
```

Never toggle simulated AC/battery state, force-stop physical SystemUI/offload services,
disable security, erase data or use emulator reset helpers to manufacture access.
Retain no authentication frames, unlock sequences or derived coordinates in proof/notes.
