# Release Checklist

This checklist is a gate, not a schedule.

## Release versions

The [product release ledger](../../tools/release/README.md#product-ledger) is the private
`@wardpulse/app` workspace. Stock Changesets owns its version, generated changelog and
consumed fragments. [Pending fragments](../../.changeset/README.md) must target only that
product; root tooling and docs remain `0.0.0`, while Cargo and Dart metadata are independent.
The initial stock-generated `0.1.0` entry records the existing candidate. It does not mean
the existing GitHub draft is publicly published or authorize a new release operation.

Use the [prepare-release skill](../../.agents/skills/prepare-release/SKILL.md) to audit the
actual repository-wide release range against pending fragments and generated notes. Inspect
`just release-status`; for an explicitly requested cut, use `just prepare-release VERSION`.
The [local bridge](../../tools/release/README.md#local-version-preparation) preflights the
official plan and all native declarations before stock generation or native writes, then
mirrors a genuine transition with phone +2, next even Wear and independent legacy/Push +1.
A fully matching target changes nothing and preserves pending fragments. Partial generation
or I/O requires reconciliation, not an automatic retry. This setup retains 0.1.0 and 1/2/1/1.

The 0.1.0 RC source versions are:

| Artifact | Package | versionName | versionCode | Source |
| --- | --- | --- | --- | --- |
| Phone AAB | `app.wardpulse` | `0.1.0` | `1` | `version` in [pubspec.yaml](../../apps/phone_flutter/pubspec.yaml) (`0.1.0+1`) |
| Wear host AAB | `app.wardpulse` | `0.1.0` | `2` | `defaultConfig` in [Wear build.gradle.kts](../../apps/wear_android/app/build.gradle.kts) |
| Legacy WFF AAB | `app.wardpulse.watchface` | `0.1.0` | `1` | `defaultConfig` in [WFF build.gradle.kts](../../apps/watchface_wff/build.gradle.kts) |
| Bundled Push APK | `app.wardpulse.watchfacepush.main` | `0.1.0` | `1` | `pushVersionCode` / `defaultConfig` in [Push build.gradle.kts](../../apps/wear_android/watchface_push/build.gradle.kts) |

Phone and Wear share a package and delivered app-signing identity, but need distinct
versionCodes. WardPulse allocates coordinated pairs as **odd phone / next even Wear**:
1/2, then 3/4, 5/6. The paired Wear code is higher by this project convention; Google
requires [unique Wear/form-factor codes](https://developer.android.com/training/wearables/packaging#unique_version_code),
not this odd/even scheme or a universal ordering across independently managed dedicated
tracks. A build for only one form factor may leave the other reserved code unused.

Before a later publication, consult the actual app's uploaded version history, including
testing tracks. Allocate a fresh unused pair above previously used codes and preserve
monotonic updates for each form factor. Never reuse an uploaded code, including for a
rebuild after a consumed upload. The user-facing `versionName` does not determine the
internal positive `versionCode`; see Android's
[version settings](https://developer.android.com/studio/publish/versioning#version-settings).

Both face packages have independent version histories. Push's positive
`wardpulsePushVersionCode` input currently defaults to 1; its N/N+1 development upgrade examples do
not set the Wear host code or require Push code 2 for this RC. Root must resolve first
publication versus existing signing and uploaded-version history before provisioning
credentials or treating these versions as publishable. If actual history conflicts with
this RC, return the material decision to Root before release execution; do not silently
reallocate versions or invent a Play state.

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

**Historical post-DONE documentation procedure (2026-10-16 Push task):** the following
requirements belong to that task's Source/output handoff. After independent candidate review,
Native gates, distinct terminal approval, quiescent DONE and explicit Source/output
ownership release, Root was required to stop only its existing `share9090.DubOhm` share
and run full `just check-docs`. Preserve the original docs output/share during Native ownership: no
docs build, preview or publication runs there. Root reviews Source, all 12 existing user
pages and plain Markdown exports, old anchors, internal/original links, both themes,
unchanged galleries and keyboard Skip to content. Verify the new image's original regular
PNG output bytes (not a served filesystem symlink), deployment prefix, round 288px frame,
size, alt, caption and original link. Restore the agreed original-directory/path-mode
share. Record actual results in a separate Owner receipt and final handoff; whole-task
closure requires Owner ZERO. This procedure does not predict Docs GREEN or require a
second status-only Source commit. Concrete findings return through supported Runner repair.

## Signing

Root owns private signing setup after the Owner answers whether existing keys must be
reused or first-publication credentials may be created, Runner reaches DONE, its owned
processes retire and Source/output ownership is released. Resolve the
[actual signing/version history](#release-versions) first. Runner and its operator must
not inspect private `.env`, `key.properties`, `watchface-push-*.properties`, keystores,
alias/password values or provider stores. No key creation, import or rotation belongs to
source preparation.

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
and notes. Pull-request Wear CI generates a temporary development identity for debug
builds. The manual [Android release build](#manual-android-release-build-stage-a) imports
the existing persistent upload and Push release identities; it generates no keys. The
Gradle producers provision no Owner Push identity. See
[Push signing inputs](../../apps/wear_android/watchface_push/README.md#signing-inputs).

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

Only when the Owner authorizes new credentials after resolving existing history may Root
create the shared local upload key. This private setup is separate from Runner's source
checks; reuse the authorized existing identity for an established release history.
For an authorized new key, the existing setup command is:

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

- `just bundle-phone` and `just bundle-wear` produce separate phone and Wear AABs for
  `app.wardpulse`. Wear distribution uses its
  [dedicated form-factor track](https://support.google.com/googleplay/android-developer/answer/13295490?hl=en).
- `just bundle-watchface` produces the legacy face AAB for its separate listing.
- These unchanged recipes require root `key.properties` through the existing
  `wardpulseRequireReleaseKey` guard. Phone also builds the Android Rust library; Wear
  additionally requires separate Push release signing.
- The Wear artifact embeds the separately signed Push APK and matching validation token.
  Use the independent [release versions](#release-versions); preserve the Push package and
  certificate and increase its code for a face update.

## Manual Android release build (Stage A)

[release-github.yml](../../.github/workflows/release-github.yml) implements Stage A in job
`build` and Stage B in dependent job `publish`: independent transfer verification followed
by draft staging and the selected GitHub release state. Hosted acceptance of the new notes
and state options remains pending, alongside permissions, secrets, failure/cancellation
cleanup, transfer and rerun/partial-state behavior.
Local source checks do not establish hosted behavior, Play delivery or runtime acceptance.
Normal PR test CI stays separate.

Before a future dispatch, the Owner configures an `android-release` GitHub Environment
restricted to the `main` branch and supplies the eight Environment secrets below. Required
reviewers are an optional Owner policy, not a workflow prerequisite. Reuse the existing
authorized identities after resolving [signing/version history](#release-versions); do not
generate, rotate or upload new credentials as part of source preparation.

| Environment secret | Private input |
| --- | --- |
| `ANDROID_UPLOAD_KEYSTORE_BASE64` | Single-line base64 of the persistent shared upload keystore |
| `ANDROID_UPLOAD_STORE_PASSWORD` | Upload keystore password |
| `ANDROID_UPLOAD_KEY_ALIAS` | Upload private-key alias |
| `ANDROID_UPLOAD_KEY_PASSWORD` | Upload private-key password |
| `ANDROID_PUSH_RELEASE_KEYSTORE_BASE64` | Single-line base64 of the separate persistent Push release keystore |
| `ANDROID_PUSH_RELEASE_STORE_PASSWORD` | Push release keystore password |
| `ANDROID_PUSH_RELEASE_KEY_ALIAS` | Push release private-key alias |
| `ANDROID_PUSH_RELEASE_KEY_PASSWORD` | Push release private-key password |

The workflow pins SHA-256 certificates to upload
`d02f85820e60d6cf49e939a1af72a84c17d3ce107c840b4e9d3ac0f3946f078e`
and Push `04fa77a4feabb08e8c71fb1ddc32000c63f18e6ff5967e3b5b8acbd5b36d4950`.
Both imported private keys, both passwords per identity and these public pins are checked
before Gradle. Public tooling is installed before secrets are exposed. Keystores and private
diagnostics live in restricted `RUNNER_TEMP` outside checkout; only the existing ignored root
`key.properties` and `watchface-push-release.properties` hold escaped signing configuration.
Import, guarded builds and verification/staging run in separate bounded steps. All eight
secret inputs are scoped to import; only the upload store password is also supplied to AAB
verification. Successful import retains signing files for the builds, which remove signing
properties and the Push keystore on success. The upload keystore remains for AAB trust checks
until verification exits. Failure/signal traps clean immediately; an unconditional cleanup
step also removes workflow-created signing files and private temporary state on success,
failure or cancellation before upload. No release configuration is cached or uploaded.
Hosted behavior still needs the acceptance above; private signing material must never enter
logs or receipts.

For a future authorized invocation, open **Actions → GitHub Release → Run
workflow**, select branch `main`, and enter an already prepared stable tag (default `v0.1.0`).
Inputs default to `draft=true`, `prerelease=false`, `latest=false`. Latest offers `true`,
`false` and `automatic`: `true` with draft or prerelease is rejected before setup. Automatic
requests GitHub's legacy latest policy only for a published normal release; drafts and
prereleases stay nonlatest. Draft/prerelease are independent markers and still use stable tags.
The [release owner](../../tools/release/README.md#publication-boundary) describes readiness:
the ledger/tag/native versions must agree, the exact generated notes must be nonempty and
pending Changesets input must be consumed by an explicitly prepared cut before dispatch.
The current pending tooling patch therefore requires a future version cut. Notes are literal
Markdown from the original immutable checkout; no npm setup or PR-list fallback is used.
The workflow rejects other refs and checks out the original full dispatch SHA without persisted Git
credentials. Before setup it checks all four source versionNames against the tag and enforces
positive odd phone / next-even Wear codes and independent positive face codes. It never
overrides versions or resolves a moving source ref. Build permission is only `contents: read`;
runs are serialized with cancellation disabled. The dependent publication job has only
`contents: write`, receives no signing secrets and uses the current repository's workflow
token, without a PAT, broader-token fallback or alternate repository. Repository policy must
permit that token to create drafts and upload release assets; refusal fails the job.

The unchanged guarded `just bundle-phone`, `just bundle-wear`, `just bundle-watchface`
and guarded ordinary release APK builds produce these seven files for the current sources:

| File in the Actions artifact | Purpose |
| --- | --- |
| `wardpulse-phone-0.1.0-code1.aab` | Phone Play upload bundle |
| `wardpulse-phone-0.1.0-code1.apk` | Direct phone installer |
| `wardpulse-wear-0.1.0-code2.aab` | Wear Play upload bundle |
| `wardpulse-wear-0.1.0-code2.apk` | Direct Wear installer |
| `wardpulse-legacy-0.1.0-code1.aab` | Legacy WFF Play upload bundle |
| `wardpulse-legacy-0.1.0-code1.apk` | Direct legacy WFF installer |
| `wardpulse-push-0.1.0-code1.apk` | Separate Push identity, embedded by the Wear producer |

The three direct installers are signed with the **upload key**. This does not promise update
compatibility with debug installs or Play-delivered installs, whose app-signing certificates
may differ. Push retains its separate persistent signer. These are direct release producer
APKs; no debug or bundletool universal substitute is used. Installer basenames are discovered
from the actual producer output directories, including legacy filename casing.

Standard `jarsigner`/`keytool` verify the three AABs; `apksigner` verifies all four APKs.
Positive verification evidence and fixed signer pins are required. The pinned imported
keystore supplies AAB trust for the self-signed upload certificate; missing timestamps are
accepted, while strict signer failures and unsigned entries fail. Exact Push bytes must match
the generated asset, Wear AAB, Wear installer and staged Push APK. `PrepareDefaultWatchFace`,
the official validator and AGP retain token/package/version ownership; raw tokens and resources
are never exported as diagnostics.

The explicit upload allowlist adds only `SHA256SUMS` and `provenance.json` to those seven
binaries. Provenance records the exact source SHA, tag/version, run ID, originating build
attempt, binary hashes, public signer fingerprints and completed producer checks. Download
the artifact from the successful run's summary within its 14-day retention period; its name
is `wardpulse-android-<tag>-<run-id>-attempt-<build-attempt>`. Keep that originating attempt
with the bytes when retrying later work. Job outputs expose the exact upload `artifact_id`,
`artifact_name`, `source_sha`, `tag`, `version`, `build_run_id` and `build_run_attempt` for
Stage B. No build tree, logs, signing configuration or raw tokens are uploaded.

### Verified transfer and draft publication (Stage B)

Job `publish` runs only after successful `build`. It binds all seven outputs to the original
`main` workflow dispatch, full source SHA, tag/version, run ID and expected artifact name.
A publication-only rerun retains `build_run_attempt` from the successful build rather than
substituting the newer workflow attempt. The pinned current-run download action receives
only the exact artifact ID; it does not select a name or a latest artifact. No separate
Actions run/job/artifact metadata API or whole-workflow success is required.

The receiver re-reads version/code declarations at the exact source commit, derives the
seven binary names and requires exactly those files plus `SHA256SUMS` and `provenance.json`
as regular root files. Unsafe, nested, unexpected or missing files, duplicate receipt keys
or records, conflicting identities, incomplete/extra hashes and hash mismatches fail closed.
It recomputes every binary hash and checks provenance source/tag/version/run/origin-attempt,
signer pins and completed producer checks. A download digest warning is not verification.
The receiver does not duplicate the producer's APK/token parsing or signature tooling.

Before any release mutation, authenticated paginated List releases includes drafts and rejects
every existing release for the exact tag. GET-by-tag absence is not used. An existing tag is
independently resolved, peeling annotated tags to the exact source commit; conflicting or
unresolvable refs fail. Both conflict checks repeat immediately before creation. This precheck
is not atomic and cannot prevent arbitrary future external mutation.

The single [publisher](../../tools/release/release_github.py), `Publisher.publish`, always
creates a draft targeting the full immutable source SHA, requesting `make_latest: "false"`
with the exact Changesets body and selected prerelease marker. It re-observes ID, body,
markers, source/tag and conflicts after creation and upload. All nine names, IDs, sizes and
supplied digests must match before any requested transition to public state; only this
invocation's newly created bound ID can be transitioned. Final observations require the exact
body, prerelease marker, requested draft state and assets. Optional digests are not required.
A draft may lack a tag ref; a public release requires a real ref peeled to the source.
The workflow never separately creates, moves or deletes tags and cannot override an existing
tag via `target_commitish`. Latest policy is requested without claiming a response echo field.

Observed races, mutation, network/auth/API ambiguity or permission refusal fail the job.
Failures preserve all existing, partial and newly public releases and assets: the workflow
never resumes or edits a preexisting release, deletes state, overwrites assets, blindly retries
uncertain effects or broadens credentials. A rerun
may proceed only if creation has not occurred and no release exists for the tag. Any partial
draft, complete draft or public release causes the next attempt to refuse publication; the
Owner must inspect the retained state and deliberately resolve it before retrying. A failed
create or publication request may already have taken effect, so inspect actual state even
when no response was received.
These instructions authorize no remote operation during local source preparation.

## Manual Google Play release

There are two independent manual Actions: **GitHub Release** builds and creates the
verified release in the selected state described above; **Google Play Release**, in
[release-google-play.yml](../../.github/workflows/release-google-play.yml), consumes a
stable published non-prerelease release. Both use only their own `workflow_dispatch`; no push,
tag, release event or completion chains them. If draft was selected, a human must inspect and
explicitly publish it before selecting its tag for Play. There is no latest/tag fallback.
The [tool README](../../tools/release-google-play/README.md#preparation-interface) owns
the exact preparation and apply commands and their proof limits.

### Play prerequisites and credentials

Before an authorized dispatch, the Owner must complete setup outside this source task:

- Resolve actual app/version/signing history. `app.wardpulse` must already exist in Play
  Console, have its first bundle uploaded manually and have Play App Signing configured.
  Configure the Wear OS form factor and its dedicated tracks; confirm the shared
  phone/Wear delivered app-signing identity. Source defaults do not establish Console state.
- Enable the IAM, Service Account Credentials and Google Play Android Developer APIs in
  the service account's Cloud project. Grant the service account
  `roles/iam.serviceAccountTokenCreator` on **itself**, as required by the pinned auth
  action to mint an access token from service-account JSON. Invite its `client_email`
  to Play Console with app-scoped access to `app.wardpulse`: view app information and
  release apps to the intended testing tracks. Production release permission is a
  separate requirement for an explicitly selected production track. Routine testing
  releases need no finance/orders/account Admin access. See
  [API setup](https://developers.google.com/android-publisher/getting_started) and the
  [pinned auth action](https://github.com/google-github-actions/auth/blob/7c6bc770dae815cd3e89ee6cdf493a5fab2cc093/README.md).
- Configure a separate GitHub Environment named `google-play`, restricted to `main`,
  with only `GOOGLE_PLAY_SERVICE_ACCOUNT_JSON`. Keep the eight signing secrets in
  `android-release`; the Play job has none of them. No PAT, `id-token` permission,
  additional identity secret/variable or custom OAuth setup is used. The action infers
  the service account from JSON `client_email`, disables credential-file creation and
  ambient credential export, and requests only the
  `https://www.googleapis.com/auth/androidpublisher` scope.
- Discover actual mobile/Wear IDs using
  [edits.tracks.list](https://developers.google.com/android-publisher/api-ref/rest/v3/edits.tracks/list)
  and Console. Existing tracks are required. `qa` and `wear:qa` are workflow defaults,
  not a promise that those tracks exist; use discovered IDs for other closed tracks.
  No track is created and production is never selected automatically.

For a future authorized invocation, open **Actions → Google Play Release → Run workflow**,
select `main` and enter the explicit stable published tag. Phone/Wear tracks default to
`qa`/`wear:qa`; status offers `draft` (default) or `completed`. Check the actual selected
track before choosing completed: completed internal testing is still internal testing,
not production. Review, processing and tester availability remain separate Play gates.

### Dispatch binding and application

The Play job grants only `contents: read`, serializes dispatches without cancellation
and bounds job/step execution. It checks out the original immutable main dispatch SHA
with full history and no persisted Git credentials. Only that checkout's final helper
runs from its clean root; selected releases supply data, never executable tooling.
Trusted repository/SHA/event/ref context remains unchanged. Inputs pass through quoted
environment variables, not interpolation into shell source.

Public GitHub preparation completes before Google authentication. It requires a stable,
published, non-prerelease tag in original-main ancestry, the seven-record receipt and
all nine asset identities, fixed signer pins and exact downloaded hashes. Historical
producer run/attempt IDs remain receipt identities, not current Play dispatch IDs.
Preparation retains two AABs, two receipts and dispatch-bound schema-1 metadata in a
fresh absolute directory outside checkout. Apply uses the same directory and checkout,
re-observing current GitHub identities and retained bytes before any Play mutation.
Saved metadata is not reusable across unrelated runs; consistency checks are not fresh
cryptographic attestation. `GH_TOKEN` is environment-only in both phases. Only apply
receives the auth action's masked access-token step output as `PLAY_ACCESS_TOKEN`.
No credentials enter argv, job outputs, artifacts, receipts or logs.

The helper applies only the exact phone and Wear AABs to `app.wardpulse` on the selected
separate form-factor tracks in one edit. It never rebuilds or re-signs. Existing bundles
are reused only for the same code and SHA-256; matching drafts can be promoted. Conflicting
or consumed-but-unlisted codes, newer versions, conflicting drafts and active/halted
rollouts require Console resolution. Drafts preserve completed serving releases and
retained codes; replacing multiple retained completed codes requires an explicit Console
retention decision. A completed bundle cannot be downgraded to draft. Track responses
must preserve requested/retained state, allowing only documented generated names and
an omitted priority returned as exact integer zero. Explicit priorities remain unchanged.
Validation precedes commit with `ERROR_IF_IN_REVIEW`, without review cancellation,
blind retry, alternate authentication or automatic rollback. Commit success does not
prove review completion or delivery. See [Play edits](https://developers.google.com/android-publisher/edits)
and [commit behavior](https://developers.google.com/android-publisher/api-ref/rest/v3/edits/commit).

Legacy `app.wardpulse.watchface` distribution remains optional and separate; this workflow
does not upload it. Push is already embedded in the Wear AAB and is never uploaded
separately. The GitHub workflow still supplies all seven signed binaries and two receipts.
Direct upload-signed installers do not promise updates over debug or Play app-signing
identities.

### Uncertain outcomes and pending acceptance

On a failed/uncertain mutation or mismatched response, stop. The helper's `.play-operation`
marker protects only its retained directory and prevents further automatic mutation there.
A fresh hosted dispatch or job rerun gets another directory; ephemeral hosted runners do
not preserve the marker across runs. Inspect and reconcile actual Play server/Console
bundle hashes/codes and both track states, including whether commit took effect, **before
any fresh dispatch or job rerun**. A new edit and read-only queries may be necessary;
reconciliation must precede further upload, track update or commit. Preserve any available
retained directory while investigating. Do not automatically remove markers or replay
an unresolved operation. Follow the tool's
[recovery guidance](../../tools/release-google-play/README.md#interrupted-or-uncertain-apply).

Hosted credential/authentication, exact upload/reuse, validation/commit, review and delivery
remain unexecuted acceptance gates. Offline checks and source review do not close them,
the local signed-RC gate or the device/runtime gates below. No credential provisioning,
dispatch or remote release operation is authorized by source preparation alone.

## Acceptance gates

### Reviewed source

- Review the version metadata, exact change scope and preserved signing/Push guards, and
  complete independent semantic review and applicable source checks.
- Record only executed checks as passed. Reviewed source and green CI establish source
  readiness; they do not prove a signed RC exists or establish Play acceptance.

### Local signed RC

Root performs this acceptance after Runner DONE and retired ownership. Keep every item
pending until actually executed against the exact candidate source commit.

- Record that commit and fresh results from the complete unchanged `just check-phone`,
  `just check-wear`, `just check-watchface`, `just validate-fixtures`, `just check-designs`
  and host `just check-docs`. `check-watchface` already includes canonical WFF drift.
- Produce fresh signed phone, Wear and legacy WFF AABs through `just bundle-phone`,
  `just bundle-wear` and `just bundle-watchface`, including the separately signed,
  officially validated release Push APK. Preserve the signing guards and ordinary producer
  graph; never seed/substitute an APK or token, or use build-name/build-number overrides
  to conceal incorrect source metadata.
- Inspect actual signed artifacts with installed standard tooling: manifest package,
  versionName/code, SDK and ABI targets, signing validity and certificates. Phone/Wear
  upload signers must agree. The release Push signer must differ from the host and
  configured Push development signers; local upload certificates do not establish the
  APK signer selected by Play.
- Confirm the Wear AAB embeds exactly the validated release Push APK bytes. Confirm the
  generated token, compiled resource and manifest token binding match that exact APK,
  without exposing raw tokens or validator output.
- Inspect the packaged phone native libraries' ELF load and RELRO segment alignment,
  bundle packaging settings and resulting APK ZIP alignment as applicable against the
  official [16 KB page-size guidance](https://developer.android.com/guide/practices/page-sizes).
  Record native-library applicability for the other artifacts, including resource-only
  faces. A source declaration or successful compilation is not packaged-library or runtime
  evidence; runtime 16 KB acceptance remains a separate gate.
- Preserve original artifact bytes. In a private ignored local receipt, record source
  commit, artifact paths and hashes, inspection/check commands and actual results,
  including certificate comparisons and APK/token binding. Keep credentials, key material,
  alias/password values and raw validation tokens out of receipts, docs and logs. Complete
  Root and peer full final review; concrete code or packaging defects return through
  reviewed Runner repair.

### Play distribution

- Resolve actual app history and verify the delivered phone/Wear app-signing identity in
  Play. Confirm the embedded Push signer's separation from that delivered host certificate.
  Equality of upload keys does not prove the signer of Google-delivered APKs. The legacy
  face listing has its own app-signing identity and version history.
- Verify form-factor tracks, store/policy requirements and internal-testing installation
  and delivery. Local signed artifacts and green CI do not imply publication or authorize
  an upload, merge or release.
- Record physical-device and remaining runtime acceptance separately. The dated
  [Push evidence and open limitations](#watch-face-push-acceptance) preserve the API35,
  hardware and unobserved recovery gates; other emulator results do not close them or
  runtime 16 KB acceptance. Preserve existing devices and signing identities during host
  acceptance; do not reset them or reinstall canonical apps under a different certificate.

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
