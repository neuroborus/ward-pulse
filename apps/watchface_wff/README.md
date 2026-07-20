# WardPulse Watch Face

Declarative Watch Face Format v1 package for a glanceable WardPulse summary.

The face renders today, week, and provider-status complications supplied by the Wear OS app.
Missing values remain neutral instead of falling back to sample data. Tapping the face or a
WardPulse complication opens the Wear OS app; ambient mode keeps only the time and product label.

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
