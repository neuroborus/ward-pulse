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

**Pending Owner acceptance.** The four-commit implementation execution finishes without
waiting for these checks. They are Owner work after Runner reaches DONE, terminal
APPROVED/ACCEPTED and settled idle state without a lease/process, followed by Root's full
independent zero-findings review. They are outside the Native check inventory and are never
preconditions for any of the four implementation commits. Record unavailable keys, runtimes
or devices as pending, never as passes. Fake-manager tests do not replace platform proof.

- [ ] Run full `just check-wear` and independent legacy `just check-watchface`, plus affected
  debug, instrumentation and release builds. Run the durable-consent instrumentation through
  `just test-wear-device`. Historical legacy acceptance does not verify the new Push package.
- [ ] In an Owner-controlled setup with signing configuration deliberately absent, prove
  release refusal: the host publishability guard still rejects missing host release signing,
  and Push release signing has no debug/host fallback. Reject a reused certificate too.
- [ ] Using a new task-owned cache, prove cold resolution of the official validator,
  checksum verification and actual APK validation/tool completion, followed by warm reuse.
  A previously downloaded JAR or a successful `--help` invocation is not this evidence.
- [ ] Inspect the actual signed Push APK: designated package, requested versionCode,
  minimum API 34, WFF 2, `hasCode=false`, no dex, and official APK/manifest allowlists.
  Verify the certificate is stable across upgrades and differs from the host, including
  debug; release also differs from configured Push development signing. Inspect actual
  Play-delivered host identity when accepting Play distribution.
- [ ] Inspect both face packages' complication/launch targets: they resolve to the existing
  `app.wardpulse` host. Affected host providers' `SAFE_WATCH_FACES` metadata names only
  `app.wardpulse.watchface` and `app.wardpulse.watchfacepush.main`, without privileged access.
- [ ] Verify official validation and the exact APK/token binding inside the built Wear
  artifact: embedded `assets/default_watchface.apk`, generated `@string/default_wf_token`
  and `com.google.android.wearable.marketplace.DEFAULT_WATCHFACE_VALIDATION_TOKEN` agree
  with the validated signed bytes. A failed validation must leave no usable previous pair.
- [ ] Build `:app:assembleDebug` normally with `-PwardpulsePushVersionCode=N`, then N+1,
  keeping the same Push package/certificate. Install the newer host and explicitly use
  **Update watch face**; show an actual face upgrade preserving complications, settings
  and face selection. Host app updates alone must not be reported as face updates.
  See [ordinary commands](../ANDROID_TOOLCHAIN.md#watch-face-push-builds).
- [ ] Exercise default installation with the Wear app and explicit missing-face installation.
  Neither may activate the face or request activation permission. Exercise an unknown
  occupied slot and recovery after capacity becomes available, without mutating that face.
- [ ] Exercise explicit **Use watch face**, consent grant, denial and dismissal; interrupted
  or failed activation and recreation must not replay it. After refusal or a consumed
  opportunity, verify manual-picker guidance and no repeated prompt. A later user-selected
  face must remain selected. A prior activation record must not establish **In use**.
- [ ] Exercise read failure / read-only **Check again**, duplicate-action suppression and
  operation-specific retries. Verify newer-only updates, no legacy replacement/downgrade,
  **In use** alongside an available update, and **Installed** after install/update without
  an immediate active-state query following update.
- [ ] Change summary availability during permission return: arrival, replacement and loss
  must preserve the utility route and original explicit action. Reach the entry both after
  the complete Plan windows list and before any summary. Preserve both home pages and Alerts.
- [ ] Verify API 33 startup with the dashboard usable and the Wear OS 5 requirement message;
  API 34/35 without Push must offer separate installation/manual selection. Verify supported
  Wear OS 6+ Push behavior and complications/data propagation through both installation paths,
  including preserved legacy settings. Name the actual runtimes/devices used.
- [ ] After DONE and explicit documentation-output ownership handoff, Root stops only
  `share9090.DubOhm` for Owner `just check-docs`, then restores the same original directory
  and path-mode share. Preserve that share and original docs output throughout planning
  and Native execution; no documentation build runs in either phase.

Required follow-up remains outside the four-commit execution. After actual Owner device
acceptance, Root performs the separately reviewed canonical round-watch captures and
measurements: full Plan windows entry reachability, no-summary entry, full-list scrolling,
utility clipping and permission-return behavior. Capture the real utility as
`docs/assets/wear-watch-face-utility.png` under the existing 500×500 fixed-dark contract.

A distinct, subsequently reviewed Runner execution must add
**Revision 2026-10-16 — watch-face utility entry** and actual measurements to
[the Glance baseline](WEAR_GLANCE_DESIGN.md), reconciling the
[screenshot index](../assets/README.md), [watch guide](user-guide/WATCH.md),
[Wear README](../../apps/wear_android/README.md) and relevant
[development status](../DEVELOPMENT_PLAN.md#watch-face-push-status-2026-10-16).
Use that run's fresh Native gates and independent reviews, Owner documentation acceptance
with the agreed output handoff, and Root's full zero-findings review. Preserve Glance
geometry and unaffected screenshots. No measurement or screenshot is fabricated; leave
unperformed acceptance visible. The initial four commits are not final task handoff.

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
