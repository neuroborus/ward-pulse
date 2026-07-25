# WardPulse Watch Face

Declarative Watch Face Format v2 package for a glanceable WardPulse summary.

The face follows the locked concentric baseline in `docs/product/WATCH_RING_DESIGN.md`:
remaining arcs (up to four ring slots), large time hero, quiet watermark, and a sunk token
strip. Ring / token data comes from Wear OS complication providers. Missing rings stay empty
instead of inventing filler. Tapping the face or a WardPulse complication opens the Wear OS
app; ambient keeps muted arcs, large time, and a quieter mark (strips off).

## Commands

From the repository root:

```sh
just validate-watchface
just check-watchface
just build-watchface
ANDROID_SERIAL="$WEAR_SERIAL" just run-watchface
```

`validate-watchface` uses the checksum-pinned official WFF validator. `build-watchface`
produces debug APK and AAB artifacts under
`apps/watchface_wff/build/outputs/`. The run command installs the APK and selects
`app.wardpulse.watchface` on the target Wear device.

## Ownership

- WFF XML resources.
- Watch face manifest and packaging.
- Ambient-friendly visual states.
- Tap-to-open behavior where supported.

Detailed dashboard interaction belongs in the Wear OS app, not in the watch face.
