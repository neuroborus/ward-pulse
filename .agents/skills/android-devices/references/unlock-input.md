# Authorized unlock input

Read [command templates](commands.md) for the verified target and literal profile handling.
Use only the owner's explicitly authorized method/material. Capture/privacy rules stay in
[App capture and transient unlock-grid inspection](commands.md#app-capture-and-transient-unlock-grid-inspection).

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
