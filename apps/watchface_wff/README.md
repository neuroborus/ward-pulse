# WardPulse Watch Face

Declarative Watch Face Format v2 package for a glanceable WardPulse summary.

The face follows the locked concentric baseline in `docs/product/WATCH_RING_DESIGN.md`:
remaining arcs (up to three ring slots; melt clockwise from 12), large time hero, quiet
watermark, and sunk family strips (`%` / `% · credits` on the matching provider). Ring and
strip data come from Wear OS `RANGED_VALUE` complication providers. Missing rings stay empty
instead of inventing filler. Tapping the face or a WardPulse complication opens the Wear OS
app; ambient keeps muted arcs, large time, a quieter mark, and the strips dimmed rather than
switched off, so the credits and budget money they alone carry survive it.

## Packaging paths

This directory owns the canonical WFF 2 resources in `src/main/res/` and the independent
legacy package `app.wardpulse.watchface` (minimum API 34 / Wear OS 5). Its identity, settings
and separate installation path remain intact.

The [bundled Push module](../wear_android/watchface_push/README.md#resource-ownership) consumes
these same resources directly to build `app.wardpulse.watchfacepush.main`. It is a separate,
resource-only, signed APK dependency of the Wear app, with `hasCode=false` and minimum API 34.
There is one scene and one generator; do not copy or hand-edit generated XML or drawables.
Both packages retain complication and launch targets in the host `app.wardpulse`.

The Wear app minimum is API 33; the phone minimum is unchanged. The Wear app checks Push
support before using its manager. Supported Wear OS 6+ devices can install the bundled
face; WFF 2 devices without Push use separate installation and manual selection. API 33
can run the dashboard, but this face requires Wear OS 5 or later. No public listing URL
or release availability is established here.

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
XML validator; it does not validate a Push APK or generate a Push token. `build-watchface`
produces debug APK and AAB artifacts under
`apps/watchface_wff/build/outputs/`. The run command installs the APK and selects
`app.wardpulse.watchface` on the target Wear device.

Ordinary Wear builds also build, separately sign and validate the bundled face, then embed
its matching APK/token through Gradle's variant graph. From `apps/wear_android/`, after
Owner signing setup:

```sh
./gradlew :app:assembleDebug -PwardpulsePushVersionCode=1
./gradlew :app:assembleDebug -PwardpulsePushVersionCode=2
```

The positive `wardpulsePushVersionCode` input defaults to 1. Keep the same Push certificate
across versions and outside build outputs so `clean` cannot replace it. Debug and release
Push signing use separate ignored configuration and must differ from the host certificate.
See [signing inputs](../wear_android/watchface_push/README.md#signing-inputs) and
[Push validation ownership](../../docs/ANDROID_TOOLCHAIN.md#watch-face-push-builds).
Never substitute an APK or token manually. Updating the Wear app does not itself update
the installed face; the utility's explicit **Update watch face** action does that without
activation. See [watch setup](../../docs/product/user-guide/WATCH.md).

Owner builds, signing readiness, APK/token inspection, compatibility and device acceptance
remain [pending](../../docs/product/RELEASE_CHECKLIST.md#watch-face-push-acceptance).
Real utility screenshots, round-watch measurements and the dated baseline reconciliation
require the separate follow-up execution after device acceptance. Existing face geometry
and screenshots are unchanged.

## Ownership

- WFF XML resources.
- Watch face manifest and packaging.
- Ambient-friendly visual states.
- Tap-to-open behavior where supported.

Detailed dashboard interaction belongs in the Wear OS app, not in the watch face.
