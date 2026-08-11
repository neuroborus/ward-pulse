# WardPulse Watch Face

Declarative Watch Face Format v2 package for a glanceable WardPulse summary.

The face follows the locked concentric baseline in `docs/product/WATCH_RING_DESIGN.md`:
remaining arcs (up to three ring slots; melt clockwise from 12), large time hero, quiet
watermark, and sunk family strips (`%` / `% · credits` on the matching provider). Ring and
strip data come from Wear OS `RANGED_VALUE` complication providers. Missing rings stay empty
instead of inventing filler. Tapping the face or a WardPulse complication opens the Wear OS
app; ambient keeps muted arcs, large time, and a quieter mark (strips off).

## Commands

From the repository root:

```sh
just render-watchface
just validate-watchface
just check-watchface
just build-watchface
ANDROID_SERIAL="$WEAR_SERIAL" just run-watchface
```

`render-watchface` writes `res/raw/watchface.xml` and the ring-type drawables in
`res/drawable-nodpi/` from `tools/render-watchface.mjs` — edit the generator, never its output;
`check-watchface` fails on drift. `validate-watchface` uses the checksum-pinned official WFF
validator. `build-watchface`
produces debug APK and AAB artifacts under
`apps/watchface_wff/build/outputs/`. The run command installs the APK and selects
`app.wardpulse.watchface` on the target Wear device.

## Ownership

- WFF XML resources.
- Watch face manifest and packaging.
- Ambient-friendly visual states.
- Tap-to-open behavior where supported.

Detailed dashboard interaction belongs in the Wear OS app, not in the watch face.
