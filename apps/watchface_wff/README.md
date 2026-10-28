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

The corrected adaptive face uses legacy code 2 and Push default code 3 with Wear 4
and phone 0.1.0+3; every versionName stays 0.1.0. Package/signing identities are preserved.
This is packaging for in-place updates, not a product release cut. Actual retained-binding,
legacy/Push update, true-ambient and transition acceptance remains **Pending** under the
[adaptive revision](../../docs/product/WATCH_RING_DESIGN.md#revision-2026-10-28--adaptive-bands-from-resolved-count).
The new face admits only its own response's exact 0/100, 0/200, 0/400, 0/800 envelopes;
MAX100 always means fixed legacy geometry, and malformed contracts draw no lower component.
`ringSlot` in `tools/render-watchface.mjs` keeps each main selector and strip beneath one
named full-canvas Group. Before emission in normal and `--check` modes,
`tools/check-watchface-structure.py` parses the actual XML to enforce one direct element
tree per Compare/Default and preserve main selector/strip containment. The baseline's three
main branches failed this check; corrected generation passes. Native causal effect remains
unproved; see the [adaptive incident and update qualification](../../docs/product/RELEASE_CHECKLIST.md#adaptive-integration-qualification-2026-10-28).

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
./gradlew :app:assembleDebug
```

The positive `wardpulsePushVersionCode` input defaults to 3. Keep the same Push certificate
across versions and outside build outputs so `clean` cannot replace it. Debug and release
Push signing use separate ignored configuration and must differ from the host certificate.
See [signing inputs](../wear_android/watchface_push/README.md#signing-inputs) and
[Push validation ownership](../../docs/ANDROID_TOOLCHAIN.md#watch-face-push-builds).
Never substitute an APK or token manually. The utility's explicit **Update watch face**
action updates without activation. Require an observed manager update from installed Push 2
to candidate 3; a bundled installation cannot prove that operation. The earlier unexpected
Push advance has an unknown trigger and leaves the original compatibility gaps open in the
qualification above. See [watch setup](../../docs/product/user-guide/WATCH.md).

Local development acceptance recorded **2026-10-16** includes final legacy WFF2/XML
validation, generator drift, lint/debug APK/AAB builds, and actual API34/canonical API36
legacy live/editor-return-live. Separate Push APK validation/token binding and API36
N1-to-N2 customization/selection retention also passed; XML validity alone does not prove
those results. The [acceptance record](../../docs/product/RELEASE_CHECKLIST.md#watch-face-push-acceptance)
retains the API34 replacement-time headless-renderer exception and N2 transient fallback,
and keeps production signing, Play delivery, API35 and hardware acceptance separate.
The dated utility baseline and approved manual-selection capture are integrated; existing
face geometry and screenshot bytes were unchanged by that setup-route work. Adaptive
geometry and its native acceptance are tracked separately above.

## Ownership

- WFF XML resources.
- Watch face manifest and packaging.
- Ambient-friendly visual states.
- Tap-to-open behavior where supported.

Detailed dashboard interaction belongs in the Wear OS app, not in the watch face.
