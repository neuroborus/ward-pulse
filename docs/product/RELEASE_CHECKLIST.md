# Release Checklist

This checklist is a gate, not a schedule.

## Core

- Rust workspace builds.
- Core tests pass.
- Mock fixture generates a stable dashboard snapshot.
- Snapshot includes today, week, month, alerts, and watch summary state.

## Phone

- Flutter app starts on an Android emulator.
- Release builds never select mock data.
- Debug mock data requires explicit opt-in in Settings.
- Provider detail pages are reachable.
- Credentials are masked after save.
- Sync logs are redacted.

## Wear OS

- Wear app runs on emulator.
- The Glance, the plan windows page, and the active alert list are readable.
- Exhausted plan windows lead the second page.
- Stale data state is visible.
- Latest successful summary survives sync failure.
- Missing phone data does not create an implicit mock summary.

## Watch Face

- WFF package builds.
- Face installs on emulator or physical watch.
- Ambient mode remains readable.
- Tap target opens the Wear OS app where supported.
- Today, week, and provider status come from WardPulse complication data sources.

### Watch Face Push acceptance

**Local development acceptance recorded 2026-10-16** for runtime Source `abebbbc5`, on
actual emulators API 33, 34 and 36. Runner implementation and independent reviews completed;
Root's full Source and scoped artifact/device/visual review reached ZERO. The results below
are the recorded Owner evidence, not fresh checks of this documentation change. Production
signing, Play delivery and physical-watch acceptance remain separate.

Reviewed final N1 debug artifact identities are host `b9db16ab`, Push `7541bc20` and legacy
`e7e77b47`; detailed hashes and observations remain in the accepted Root/peer receipts.
Task runtimes were `wardpulse_push_wear_api36_1` / `emulator-5584`,
`wardpulse_push_wear_api34` / `emulator-5582` and
`wardpulse_push_wear_api33` / `emulator-5580`; the canonical runtime is identified below.

- [x] Final Owner `just check-wear` passed in 35 s, including lint and debug/instrumentation
  APK builds. Its `testDebugUnitTest` task was **UP-TO-DATE**; the actual **96/0** JVM execution
  belongs to UI08 and unchanged relevant production/core/JVM owners, not a fresh final run.
- [x] Final independent legacy `just check-watchface` passed in 15 s: official XML
  validator 1.7.0 accepted WFF 2, generator drift passed, and lint/debug APK/AAB builds passed.
- [x] The corrected test APK reproduced RED for the specific utility method against the
  preserved `1570106` host: expected visible **Installed**, one failure. The same test APK
  against the hash-verified final host passed both new methods **2/2**. This was not a full
  16-test baseline RED run. Final `just test-wear-device` then passed in 24 s, with the actual
  connected report **16 tests / 0 failures / 0 errors** (11.01 s).
- [x] Recorded negative signing checks rejected missing host release signing, missing Push
  release signing, a release configuration reusing the Push development identity, and an
  actual host/Push certificate collision. The producer removed the stale APK/token outputs
  on failure. These refusal checks do not prove positive production signing.
- [x] A new empty task-owned cache resolved/downloaded the official Push validator, verified
  its pinned checksum and completed actual APK validation through the ordinary producer
  graph. The warm repeat passed with that producer UP-TO-DATE. Final artifact review also
  freshly ran the official APK validator 1.1.0-alpha01 successfully against final Push bytes.
- [x] Final signed debug Push APK inspection established `app.wardpulse.watchfacepush.main`,
  versionCode 1, minimum API 34 / target 36, WFF 2, `hasCode=false`, no dex/native code, and
  the official APK/manifest allowlists. Its development certificate differs from the host's
  debug certificate and remained stable through the actual N1-to-N2 upgrade.
- [x] Both face packages' complication/launch targets resolve to `app.wardpulse`.
  Compiled and merged host `SAFE_WATCH_FACES` lists name only `app.wardpulse.watchface` and
  `app.wardpulse.watchfacepush.main`, without privileged access. Both scenes/resources match
  the canonical generated owner; compiled Push/activation permissions were inspected.
- [x] Final embedded `assets/default_watchface.apk` equals the signed producer and generated
  APK byte-for-byte. Fresh official validation, generated `@string/default_wf_token`, compiled
  string and `com.google.android.wearable.marketplace.DEFAULT_WATCHFACE_VALIDATION_TOKEN`
  agree with those exact bytes. Never publish raw validation tokens or signing secrets.
- [x] Ordinary `:app:assembleDebug` builds with `-PwardpulsePushVersionCode=1`, then `=2`,
  produced actual face versions N1/N2 with the same development signer. Installing host N2
  alone retained face N1; one explicit **Update watch face** installed N2, retained
  `ActivationAttempted`, Battery customization and selected WardPulse, and requested neither
  permission nor activation. The system briefly displayed Simple fallback before restoring
  that selection. Preserved state does not mean there was no transient system fallback.
  See [ordinary commands](../ANDROID_TOOLCHAIN.md#watch-face-push-builds).
- [x] On final task API36, installing only the N1 host automatically installed bundled Push
  N1 without activation; the first utility visit showed **Installed**. Earlier actual UI08
  **Install watch face** installed a missing own face with free capacity and no activation.
  This establishes free-capacity installation, not unknown occupied-slot recovery.
- [x] Final task API36 explicit **Use watch face** opened the real Allow dialog, consumed
  `ActivationAttempted` and selected WardPulse. Actual phone data rendered; ordinary editor
  customization from Day to Battery returned to live without a fresh fatal. Earlier UI08
  denial, Back dismissal and true process-death/relaunch preserved manual guidance without
  repeated permission. After N2, a later user-selected Perfunctory remained selected through
  a fresh check, actual app-process death and relaunch.
- [x] Injected-controller tests cover read failures/read-only **Check again**, duplicate
  suppression, operation-specific retries, newer-only updates/no legacy replacement or
  downgrade, **In use** alongside an update and **Installed** after update without an
  immediate active-state query. They also cover interrupted/failed activation and persisted
  history that cannot itself prove **In use**. These are fake/instrumented boundaries,
  distinct from actual SDK operations and observed system dialogs above.
- [x] Actual task UI08 no-summary entry and real Data Layer arrival/replacement retained the
  utility route. Final device UI tests exercised synthetic availability/loss and permission
  return. Canonical scrolling retained all five Plan windows rows before one utility entry,
  with both home pages and Alerts unchanged. Synthetic loss is not actual Data Layer loss.
- [x] Final API33 host-only startup, real summary and route passed with the dashboard usable
  and the Wear OS 5 requirement message; there was no face/permission/activation flow.
  Final API34 host/legacy upgrades, real Data Layer arrival, separate-install utility and
  legacy live/editor-return-live passed without reboot or force-stop. No Push package or
  activation history/permission flow was introduced there.
- [x] Final canonical `wardpulse_wear_round_api36_1` / `emulator-5554`, actual SDK36,
  **384×384 round / 320 dpi**, retained selected legacy `wfId15`, empty user style and upper
  Day/NoData providers. Auto-installed Push N1 stayed inactive; no canonical consent was
  consumed or data cleared. Natural Refresh/real WardPulseSync delivered fresh data to
  Glance and the live face; ordinary editor returned to live with empty crash buffers.
  Host minimum/target were 33/36; both faces 34/36. Canonical phone minimum 24 and package
  timestamp **2026-10-15 23:52:25** remained unchanged.
- [ ] Complete positive production-key builds and inspect the release Push certificate,
  including separation from host and configured Push development signing. Existing release
  AABs were not reviewed as fresh final outputs.
- [ ] Verify actual Play app-signing identity and delivery. Local distinct signers and
  bundle/token binding do not close this publication gate.
- [ ] Execute API35 separate-install/manual-selection acceptance; other API results do not
  certify that runtime.
- [ ] Perform physical-watch acceptance; emulator results do not certify hardware.
- [ ] Exercise real-platform unknown occupied-slot/capacity recovery without mutating the
  foreign face, SDK read/mutation faults, interrupted/failed activation and remaining
  summary-loss/permission-return permutations. Different-client faces and injected errors
  do not establish these unavailable scenarios.

**API34 transition qualification:** during replacement, an already-running headless
renderer logged a nonfatal `StringIndexOutOfBoundsException`. Attribution to an old/cached
document is an inference. The fresh final document rendered and returned from the ordinary
editor without restart or new exceptions; the crash buffer gained no fatal. This is not a
warning-free or seamless-replacement claim.

The integrated
[Revision 2026-10-16 — watch-face utility entry](WEAR_GLANCE_DESIGN.md#revision-2026-10-16--watch-face-utility-entry)
records canonical measurements and their scroll positions. At the extreme utility end,
the departing Make heading intersects the fixed clock near `y24`; it is fully readable in
the middle position. All instructions/actions are reachable across scrolling, not
simultaneously visible at every offset. The approved 500×500 fixed-dark
[manual-selection PNG and provenance](../assets/README.md#watch-face-utility-provenance-and-wear-freshness-2026-10-16)
are integrated with the [Watch guide](user-guide/WATCH.md#select-and-customize-the-face).
The PNG retains its original UI08/explicit-decline identity, bound to the unchanged final
UI owner; existing screenshot bytes and Glance geometry are preserved.

**Mandatory post-DONE documentation procedure:** after independent candidate review,
Native gates, distinct terminal approval, quiescent DONE and explicit Source/output
ownership release, Root stops only its existing `share9090.DubOhm` share and runs full
`just check-docs`. Preserve the original docs output/share during Native ownership: no
docs build, preview or publication runs there. Root reviews Source, all 12 existing user
pages and plain Markdown exports, old anchors, internal/original links, both themes,
unchanged galleries and keyboard Skip to content. Verify the new image's original regular
PNG output bytes (not a served filesystem symlink), deployment prefix, round 288px frame,
size, alt, caption and original link. Restore the agreed original-directory/path-mode
share. Record actual results in a separate Owner receipt and final handoff; whole-task
closure requires Owner ZERO. This procedure does not predict Docs GREEN or require a
second status-only Source commit. Concrete findings return through supported Runner repair.

## Signing

Local release builds for the phone, Wear app and legacy face read the root `key.properties`.
With Play App Signing, this configures the **upload key**: it signs the AAB submitted to Play,
while Google signs the APKs delivered to devices with the **app signing key**.
The phone and Wear app share `app.wardpulse` and must keep
one app signing identity. The watch face is a separate listing under `app.wardpulse.watchface`;
reusing its upload key does not establish which app signing key Play uses for that listing.
Verify the Play app signing certificates when checking the distribution identity. See
[Play App Signing: key types and ownership](https://support.google.com/googleplay/android-developer/answer/9842756?hl=en).

The additional `app.wardpulse.watchfacepush.main` is a directly signed APK embedded in the
Wear artifact, not another Play listing. Its certificate must differ from the phone/Wear
host certificate, including debug, and remain stable for face updates. Owner provisions
persistent development signing and a separate release identity through ignored root
`watchface-push-debug.properties` / `watchface-push-release.properties`; each names
`storeFile`, `storePassword`, `keyAlias` and `keyPassword` without tracked example values.
Keep keys outside the repository and build outputs, and keep credential values out of logs
and notes. CI provisions only its own development identity. The build provisions no Owner
Push identity. See [Push signing inputs](../../apps/wear_android/watchface_push/README.md#signing-inputs).

- `key.properties` exists at the repository root and names a keystore stored **outside** the
  repository.
- No keystore and no `key.properties` is tracked by git. Both are ignored; `git status` is the
  check.
- `just bundle-phone`, `just bundle-wear` and `just bundle-watchface` complete. Each one fails
  rather than fall back to the host/legacy debug key. Wear also requires valid separate Push
  release signing; verify actual certificates before declaring the artifacts publishable.
- The phone/legacy plain `assembleRelease` fallback remains debug-signed and nonpublishable.
  The Wear host retains that warning/fallback, but its bundled Push APK still needs separate
  valid release signing. Missing Push release configuration fails instead of reusing a key.

Creating the shared local upload key is a one-time setup, not a gate. It belongs to whoever
publishes the app:

```sh
keytool -genkeypair -v \
  -keystore ~/wardpulse-release.jks \
  -alias wardpulse \
  -keyalg RSA -keysize 2048 \
  -validity 10000
```

- `-keystore` — where the key file lands. Anywhere **outside** this repository; the path above
  is a suggestion, not a requirement.
- `-alias` — names the key inside the keystore, and must match `keyAlias` below.
- `-keyalg RSA -keysize 2048` — what Play accepts for upload keys.
- `-validity` — certificate validity in days. 10000 is about 27 years, giving the upload
  certificate a long lifetime.

`keytool` then asks for a keystore password, a key password, and the identity fields it writes
into the certificate.

Then write `key.properties` at the repository root with four entries — `storeFile` as an
absolute path, plus `storePassword`, `keyAlias` and `keyPassword` holding what `keytool` just
asked for. Nothing in this repository carries example values, and none should be added: a
plausible-looking password in a tracked file is the mistake this arrangement exists to prevent.

Back the local keystore up somewhere separate from the machine that builds, and keep the
passwords with it. **Losing an upload key does not end a Play App Signing listing:** the owner
can create a replacement and request an upload-key reset in Play Console, preserving the app
signing identity and existing installs. See
[Request an upload key reset](https://support.google.com/googleplay/android-developer/answer/9842756?hl=en).

For distribution outside Play with a self-managed app signing key, losing that key can prevent
future updates to existing installations. Keep that distribution key distinct from the upload
key in the release records; the reset process above applies to Play uploads, not to a lost
self-managed signing identity.

## Artefacts

- `just bundle-phone` produces the phone bundle; `app.wardpulse` carries the Wear app alongside
  it, from `just bundle-wear`.
- `just bundle-watchface` produces the watch face bundle, its own listing.
- The Wear artifact embeds the separately signed Push APK and matching validation token.
  Set `wardpulsePushVersionCode` to a positive integer for the intended face release; its
  default is 1. Preserve the package/certificate and increase the face version for an update.
- Each bundle's `versionCode` is higher than the one already on the track.

## Privacy And Legal

- App includes the independent-product disclaimer.
- [Privacy policy](PRIVACY_POLICY.md) is current.
- Provider credentials can be removed per connection.
- Local settings can be cleared through Android system settings.
- WardPulse stores no user data on developer-operated infrastructure.
- Apache-2.0 license scope and Rust package metadata are still accurate.
- WardPulse trademark and brand asset boundaries are documented.
- Third-party notices are current for bundled dependencies and assets.
- No credentials or sensitive provider payloads appear in logs.
