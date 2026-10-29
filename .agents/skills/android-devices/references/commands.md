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

## Guard launches and navigation

After an app or Settings launch and after every navigation transition, join fresh window
focus/foreground state with the settled hierarchy or original frame that identifies the
expected visible page. Verify this before the next input or page capture. An unlocked
device, resumed Activity or successful `am start -W` result alone does not prove that page.

For menu/page catalogs, stop the navigation batch on an empty hierarchy or unexpected page.
Retain sanitized actual foreground/page evidence; do not label captures from the intended
route or continue the planned scroll/tap sequence on another UI. Reobserve through the
existing supported route and resume only after the expected page is established. Fixed
delay or command completion alone does not prove settlement.

## Wake, Home and authorized in-place update

```sh
adb -s "$DEVICE_SERIAL" shell input keyevent 224
adb -s "$DEVICE_SERIAL" shell input keyevent 3
adb -s "$DEVICE_SERIAL" install -r "$APK_PATH"
```

Use only the needed action. Before installation, establish the package and matching signing
certificate as required by the phone/watch reference; a mismatch does not permit uninstall.

## Authorized pattern

Read [authorized pattern input](unlock-input.md#authorized-pattern) before using its
existing templates to prepare the bounded unlock/scenario batch.

## Authorized PIN

Read [authorized PIN input](unlock-input.md#authorized-pin) before using its existing
templates; preserve the current method's authorization and observed UI preconditions.

## App capture and transient unlock-grid inspection

For saved app captures, verify unlocked, non-authentication UI in the same bounded batch:
```sh
adb -s "$DEVICE_SERIAL" exec-out screencap -p > "$PRIVATE_CAPTURE_PATH"
```

Only unfilled/unentered unlock UI may be inspected privately and transiently for geometry.
Never capture entered pattern/PIN, retain an authentication frame as proof or publish it.
Keep identifying content out of saved app frames. Apply user-docs before public use;
a screenshot alone is not a PASS.
