# Parameterized operator commands

These are existing ADB command templates, not a bundled script or parser. Read
[connection.md](connection.md) first. Privately load only allowlisted profile fields as
literal data; never source/eval/print `.env`, enable xtrace or export the whole profile.
Resolve every variable before use. Do not execute unresolved placeholders.

Choose PHONE or WEAR consistently: `DEVICE_SERIAL`, expected model/SDK/hardware ID and
`HARDWARE_ID_PROPERTY` come from that device's profile fields. `CONNECT_ENDPOINT` is its
currently confirmed wireless host:connection-port, never the pairing port. Discovery may
resolve a changed port; it does not establish identity or authorize new pairing.
Allow only the two documented hardware-ID property names, not arbitrary profile text.

## Discover, connect and identify

```sh
adb devices -l
adb mdns services
adb connect "$CONNECT_ENDPOINT"
adb -s "$DEVICE_SERIAL" shell getprop ro.product.model
adb -s "$DEVICE_SERIAL" shell getprop "$HARDWARE_ID_PROPERTY"
adb -s "$DEVICE_SERIAL" shell getprop ro.build.version.sdk
adb -s "$DEVICE_SERIAL" shell wm size
```

Compare identity outputs privately against expected fields before mutations. Keep raw
hardware identifiers out of published proof. Use the newly verified serial throughout;
do not substitute an emulator or another transport after a failed operation.

## Read actual lock, window and task state

```sh
adb -s "$DEVICE_SERIAL" shell dumpsys window policy
adb -s "$DEVICE_SERIAL" shell dumpsys window windows
adb -s "$DEVICE_SERIAL" shell dumpsys activity activities
```

Inspect results privately; retain only relevant lock state, target foreground component
and task/Activity measurements. A resumed record or visible face is not unlock proof.
Check the current rendered UI too; charging SystemUI may cover the app.

## Wake, Home and authorized in-place update

```sh
adb -s "$DEVICE_SERIAL" shell input keyevent 224
adb -s "$DEVICE_SERIAL" shell input keyevent 3
adb -s "$DEVICE_SERIAL" install -r "$APK_PATH"
```

Use only the needed action. Before installation, establish the package and matching signing
certificate as required by the phone/watch reference; a mismatch does not permit uninstall.

## Authorized pattern

Derive the ordered nodes privately from that device's `*_UNLOCK_SECRET`, then resolve
ephemeral numeric coordinates inside the CURRENT visually verified unlock grid. No stored pixel
coordinates, secret sequence or secret length is specified here. Fully prepare the batch:
DOWN is at FIRST; instantiate the NODE MOVE template for each following non-final node,
in order; the explicit LAST MOVE handles the final node, immediately before UP at LAST.

```sh
adb -s "$DEVICE_SERIAL" shell input touchscreen motionevent DOWN "$FIRST_X" "$FIRST_Y"
adb -s "$DEVICE_SERIAL" shell input touchscreen motionevent MOVE "$NODE_X" "$NODE_Y"
adb -s "$DEVICE_SERIAL" shell input touchscreen motionevent MOVE "$LAST_X" "$LAST_Y"
adb -s "$DEVICE_SERIAL" shell input touchscreen motionevent UP "$LAST_X" "$LAST_Y"
```

The NODE line is a template to instantiate as needed, not an extra literal gesture node.
Never omit the final MOVE. Execute all gesture events, unlock verification and the guarded
scenario in one bounded operational batch; no model round trip between events. Stop if
identity, lock-screen geometry or unlocked/foreground state cannot be confirmed.

## Authorized PIN

Use only when the current verified PIN UI accepts digit text and Enter. Privately validate
`UNLOCK_SECRET` from the selected device's `*_UNLOCK_SECRET` as digits only; preserve leading
zeroes as text. Do not print it or put its literal value in tool command text.

```sh
adb -s "$DEVICE_SERIAL" shell input text "$UNLOCK_SECRET"
adb -s "$DEVICE_SERIAL" shell input keyevent 66
```

Keep PIN input, verification and the guarded scenario in one bounded batch too. After any
rejection, stop automated input and inspect the cause; authorization persists, not guessing.

## App capture and transient unlock-grid inspection

For saved app captures, verify unlocked, non-authentication UI in the same bounded batch:
```sh
adb -s "$DEVICE_SERIAL" exec-out screencap -p > "$PRIVATE_CAPTURE_PATH"
```

Only unfilled/unentered unlock UI may be inspected privately and transiently for geometry.
Never capture entered pattern/PIN, retain an authentication frame as proof or publish it.
Keep identifying content out of saved app frames. Apply user-docs before public use;
a screenshot alone is not a PASS.
