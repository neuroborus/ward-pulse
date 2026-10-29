# Bundled Push watch face

This resource-only Android application produces `app.wardpulse.watchfacepush.main` for
[Watch Face Push](https://developer.android.com/training/wearables/watch-face-push).
It is a signed APK dependency of the Wear app, not a runtime Android library. Its minimum
is API 34 with WFF 2; the Wear app minimum is independently API 33. Push availability still
requires a runtime capability check. The Wear app's `WatchFaceController` handles installation
recovery, one-time activation and explicit updates; `WatchFaceScreen` presents the utility
route. See [watch face setup](../README.md#watch-face-setup).

## Resource ownership

The `main` resource source set in [build.gradle.kts](build.gradle.kts) consumes
`apps/watchface_wff/src/main/res/` directly. The legacy `app.wardpulse.watchface` package,
its signing/settings, and its independent build remain intact. The canonical resource owner
is [the WFF module](../../watchface_wff/README.md); change its generator, never generated XML
or PNGs. Both packages retain the explicit `app.wardpulse` complication and launch targets.
The host's affected complication services trust only these two own face packages through
`android.support.wearable.complications.SAFE_WATCH_FACES`.

## Signing inputs

Root provisions/reuses authorized local identities after the Owner resolves existing keys
and release history, Runner reaches DONE and ownership retires; see
[Signing](../../../docs/product/RELEASE_CHECKLIST.md#signing). Runner and its operator must
not inspect private signing inputs. At the repository root, Root supplies ignored
`watchface-push-debug.properties` for development and `watchface-push-release.properties`
for release. Each contains the property names `storeFile`, `storePassword`, `keyAlias`, and
`keyPassword`, with real values supplied privately. `storeFile` must be an absolute path
outside this repository. Java properties escaping applies to paths and values. Do not put
credentials in examples, logs, notes, Source, or command-line Gradle properties.

Keep the development keystore in a persistent private location outside all build outputs:
`clean` must not delete it. Reuse that same certificate for version N and N+1. A different
development key on each local build prevents a normal face upgrade. Pull-request Wear CI
generates its own temporary development identity for debug builds. The manual
[Stage A release workflow](../../../docs/product/RELEASE_CHECKLIST.md#manual-android-release-build-stage-a)
imports the existing persistent shared upload and separate Push release identities from
eight Environment secrets; it generates no keys. Public tooling setup precedes secret
exposure. Separate import, build and verification steps retain imported keys in restricted
temporary storage outside checkout only while needed. Successful builds remove escaped
ignored signing properties and the Push keystore; AAB verification retains upload-keystore
trust until it exits. Failure/signal traps and unconditional pre-upload cleanup remove
workflow-created signing state and private diagnostics. Hosted cleanup/transfer acceptance
remains pending.

`RequirePushSigning` rejects absent/incomplete configuration and unusable private keys.
Neither Push build type falls back to the host signing configuration or the conventional
Android debug key. A configured release certificate must also differ from the configured
Push development certificate. `PrepareDefaultWatchFace` in
[the host build script](../app/build.gradle.kts) verifies the actual signed APK and rejects
a certificate matching the selected host certificate, including debug. AGP's host signing
validation runs first so a fresh host debug keystore is available for this comparison.

The existing host `key.properties` and `wardpulseRequireReleaseKey` publishability guard
remain unchanged. Phone and Wear share `app.wardpulse` and their delivered app-signing
identity. The independently signed `app.wardpulse.watchfacepush.main` APK is embedded in
the Wear host, not a separate Play listing. Local upload-key equality does not establish
Play's delivered APK signer. Push release signing is an additional required identity,
never permission to publish a debug-signed host. See the central
[acceptance gates](../../../docs/product/RELEASE_CHECKLIST.md#acceptance-gates).

## Ordinary builds and versions

From `apps/wear_android/`, after private development signing setup, this debug command
builds the current bundled face:

```sh
./gradlew :app:assembleDebug
```

`wardpulsePushVersionCode` currently defaults to 3 and accepts a positive Kotlin/Android integer.
It controls the Push package's independent version history, not the Wear host version.
The [local product bridge](../../../tools/release/README.md#local-version-preparation) advances
its default by 1 for a genuine product transition, independently of legacy face codes, and
mirrors the stable product versionName. An unchanged target does not increment it. Keep the
package/certificate stable and check actual uploaded history before distribution.
The [current source versions](../../../docs/product/RELEASE_CHECKLIST.md#release-versions)
are phone 3/Wear 4/legacy 2/Push 3, all versionName 0.1.0. The main-comparison correction
advances only Push's guarded default from 2 to 3, without a release cut. In the adaptive
HOST attempt, installing Wear 4 was followed by Push 2 before any explicit update; the
trigger is unknown. New-Wear4/old-Push1 and explicit 1→2 were not observed. Preserve those
receipts and gaps; require a genuine explicit **Update watch face** from installed Push 2
to candidate 3, or reviewed strictly newer input if delivery advances unexpectedly. Bundled
installation is not explicit-update evidence. Follow the
[forward-only acceptance record](../../../docs/product/RELEASE_CHECKLIST.md#adaptive-integration-qualification-2026-10-28);
do not synthesize an old baseline, downgrade, reinstall or reset retained state.
For a release artifact, Root uses the existing guarded recipe from the repository root:

```sh
just bundle-wear
```

Provide both host release signing and separate Push release signing before that build.
The ordinary variant dependency graph packages and signs the face, validates it, generates
the variant bundle, and packages the Wear app. No recursive Gradle, manual APK copy, token
substitution, or source edit is needed. `clean` removes the generated bundle, not keys.

The manual release workflow's Stage A builds the ordinary guarded Wear release installer,
verifies the fixed public signer pins and compares the producer Push bytes with the generated
asset, embedded Wear AAB, embedded installer and staged Push APK. Its single Actions artifact contains seven
signed binaries: phone/Wear/legacy each supply an AAB and direct APK, and Push supplies its
separately signed APK, plus `SHA256SUMS` and sanitized `provenance.json`. The
[manual release instructions](../../../docs/product/RELEASE_CHECKLIST.md#manual-android-release-build-stage-a)
own the exact filenames, main-restricted Environment/eight signing secrets and manual dispatch.
Signing state is removed before artifact upload; publication receives no signing secrets.
Direct host installers use the upload key, which does not promise debug/Play install update
compatibility.

Stage B's dependent `publish` job downloads only the successful build's exact artifact ID,
binding its name/source/tag/version/run and originating build attempt to the original main
dispatch. A publication-only rerun retains that build attempt. It derives expected filenames
from immutable source metadata, verifies the exact nine regular root files, receipt identities,
signer pins and every binary SHA-256, then uses only `contents: write` to stage a full-SHA
nonlatest GitHub draft with exact generated notes and the selected prerelease marker.
The [release owner](../../../tools/release/README.md#publication-boundary) defines typed
draft/prerelease/latest options, early prepared-version readiness and the single publisher.
Authenticated paginated release discovery
refuses any existing release for the tag, including drafts; existing tags must independently
peel to the source. Conflict checks repeat before creation, without claiming atomic exclusion.
Release ID/body/markers/target/tag are re-observed after creation and upload; all nine asset
names/IDs/sizes and supplied digests must match before this invocation's new draft can become
public. Final state is re-observed; public releases require a tag ref peeled to source.
Failures preserve partial/public state without overwrite, resume, deletion or blind retry.
Uncertain effects require Owner reconciliation. Hosted transfer, new publication modes,
permissions, cleanup, rerun/cancellation and partial-state acceptance remain pending,
as do separate Play/runtime gates; local checks and historical debug acceptance do not close them.

The separate **Google Play Release** Action in
[release-google-play.yml](../../../.github/workflows/release-google-play.yml) is independently
manual: if draft was selected, a human must publish it before selecting its explicit stable
non-prerelease tag.
From the original main dispatch checkout, it prepares and re-observes the exact released
phone/Wear AABs, then applies them to existing tracks (defaults `qa`/`wear:qa`, status
`draft`) in one edit. It neither rebuilds nor re-signs. Only the isolated `google-play`
Environment's service-account JSON is used; the Play job receives no Android signing secrets.
Legacy WFF remains an optional separate listing. Push is already embedded in Wear and is
never uploaded separately. Completed internal testing does not imply production or delivery.
An uncertain apply requires actual Play server/Console reconciliation before any further
mutation, including a fresh dispatch or job rerun: `.play-operation` protects only its
retained directory, which ephemeral hosted runners do not preserve across runs. See
[Play setup and recovery](../../../docs/product/RELEASE_CHECKLIST.md#manual-google-play-release)
and the [helper interfaces](../../../tools/release-google-play/README.md#apply-interface).
Hosted auth/upload/commit/review/delivery acceptance remains pending.

## Official validation and generated outputs

The host build owns the nontransitive build-time dependency
`com.google.android.wearable.watchface.validator:validator-push-cli:1.1.0-alpha01@jar`,
resolved by Gradle through existing Google Maven. The official artifact is
<https://dl.google.com/dl/android/maven2/com/google/android/wearable/watchface/validator/validator-push-cli/1.1.0-alpha01/validator-push-cli-1.1.0-alpha01.jar>.
`validatorSha256` pins its SHA-256 to
`04dc20a0994df3eaebf025e107f7589c147b2ce8a2c628745e01a5c0a63fe4dd`.
Keep the dependency version, this checksum, and the CLI output contract together when
reviewing an update. The existing XML validator serves a separate purpose.

`PrepareDefaultWatchFace` verifies the tool checksum before execution, passes the absolute
signed APK to `--apk_path` and the host `app.wardpulse` to `--package_name`, and requires
the official success record plus exactly one token. The CLI's exit code alone is
insufficient. Raw output and tokens are captured privately, never logged. The official
validator enforces the APK/manifest allowlists; the face has no application code or
runtime dependencies and disables dependency metadata in the APK.

The task clears previous outputs before validation and stages the exact signed bytes.
Only a successful validation publishes the APK/token pair under ignored
`app/build/generated/defaultWatchFace/<variant>/`: `assets/default_watchface.apk` and
`res/values/default_watchface.xml` containing `@string/default_wf_token`. The host manifest
references it with `com.google.android.wearable.marketplace.DEFAULT_WATCHFACE_VALIDATION_TOKEN`,
as required by the [Wear app integration](https://developer.android.com/training/wearables/watch-face-push/wear-os-app).
The generated assets and resources participate in AGP's variant source graph. Resource,
version, signing, APK byte, validator, client-package, or Java-runtime changes invalidate
the relevant inputs; a failed validation publishes no bundle. No APK or token is checked in,
and no runtime validator or separate download helper is used.

## Native integration candidate

`PrepareNativePushCandidate` in the [host build script](../app/build.gradle.kts) is attached
only to debug AndroidTest assets when **both** `-PwardpulseNativeCandidate=true` and
`-PwardpulsePushVersionCode=4` are supplied. A different/missing version with opt-in is
rejected. It consumes `PrepareDefaultWatchFace.outputDirectory` through the existing signed
APK/official-validation dependency graph, without an APK/token input property or alternate
validator. Ordinary builds have no candidate asset source. Returning to ordinary flags removes
that source from the variant graph; do not install a host built with candidate flags.

`PrepareDefaultWatchFace` also emits `identity.properties` outside the host's assets/resources.
This minimal producer receipt binds package/code, APK and resource-table SHA-256, separate face
and host signer hashes, pinned validator hash and token hash. A successful opt-in consumer
copies the exact APK/token and receipt into generated test assets `native_push_candidate/`.
Failed producer validation invalidates its whole output; failed consumer packaging removes
its assets. The AGP source graph tracks these outputs and their producer inputs. No generated
APK, receipt or token is checked in or printed. Resource equality plus complete installed APK
byte equality binds the actual candidate; it is not a renderer observation.

The test-local `NativePackage.read` in
[NativePushState.kt](../app/src/androidTest/java/app/wardpulse/wear/nativeintegration/NativePushState.kt)
uses a bounded, complete installed-path enumeration only to locate the installed Push APK
and reject splits. Normal target-UID file/archive access supplies its actual full hash,
package/code/single signer and resource table; candidate/asset receipts never replace that
evidence. The later resource check uses the same verified installed-file result, without a
visibility-sensitive application-info lookup. Unavailable archive/signing capability remains
Pending, independently of candidate validation and file readability.

Candidate 4 is strictly an integration input. Push's default stays 3, Wear 4, phone 3,
legacy 2 and common versionName 0.1.0; no product release is prepared. A non-installing
`:app:assembleDebugAndroidTest` may build local dependencies but never authorizes target
installation. Follow the [stock-runner provisioning order](../../../docs/ANDROID_TOOLCHAIN.md#guarded-push-witness):
only the test APK is installed before the actual baseline-host SDK witness. Keep the original
installed host and asset 3 intact through the result and separate settled native evidence.
Afterward retain intended Push 4, reconcile uncertain results without retry or downgrade,
restore/verify normal data and retire the instrumentation owner before ordinary rebuilding
and target provisioning. Test APK provisioning, SDK mutation and later target installation
are distinct effects and evidence. Actual graph execution and native acceptance remain Pending.
The SDK result or a retained legacy renderer does not prove retained Push selections. The
updated Push face's own existing instance and independent actual provider-selection records
are required; cached delivered-data sources and defaults are not selection records. The baseline
reader queries the existing complications selection service and requires a sole stable active
runtime instance before and after that component-scoped query. Unavailable, partial, denied or
unmapped responses keep dispatch/retention Pending; actual service applicability requires HOST proof.
Legacy-only evidence cannot complete the pre-replacement witness or admit target installation.
The harness never creates, activates or reselects a face; the completed run's frozen ban is
unchanged. The adopted **2026-10-29 post-DONE HOST scope** permits **one** ordinary system-picker
selection of a pre-existing, configured, owned Push 3 instance on the canonical **Round AVD**
under the [limited procedure](../../../docs/ANDROID_TOOLCHAIN.md#guarded-push-witness).
Preserve original host 4/asset 3 through the stock witness; discover authoritative configuration
after test-only provisioning and before dispatch, then restore the exact original configured
Legacy selection, settings and normal data after the witness/whole original/owner retirement
while retaining Push 4. No instance creation, SDK/app activation, new permission or binding/style change is
included; missing configuration or witness evidence remains Pending.

The later [client probe](../README.md#guarded-complication-client-probe) is test-only and
requires that completed pre-replacement witness and subsequent ordinary target provisioning.
It cannot create/activate an instance, bypass permissions or replace SDK-update/ordinary
datasource evidence with a supplied bitmap. Its access, effective restoration and the full
item12 matrix remain Pending. Neither that probe nor candidate 4 closes UNKNOWN causality,
old-Push1 matrix gaps, missing 1→2/2→3 manager evidence or the utility-button gap.

## Local development acceptance

Recorded **2026-10-16** for runtime Source `abebbbc5`: debug builds, negative signing
guards, cold validator download/checksum/tool completion and warm reuse, plus final signed
APK/allowlist/provider-target inspection and exact validation-token binding passed. Actual
API36 N1-to-N2 update retained customization and selection with the same development face
signer; host update alone left face N1 installed. The system briefly used Simple fallback
before restoring WardPulse. API33/API34 compatibility and both-path live/editor observations
have their own recorded scope.

See the central [acceptance record](../../../docs/product/RELEASE_CHECKLIST.md#watch-face-push-acceptance)
for final artifact/device evidence and limitations. Production signing, actual Play
app-signing/delivery, API35, physical hardware and unobserved platform-failure/capacity
scenarios remain open. Development signer/token proof does not close them. The dated
baseline and approved manual-selection PNG are integrated; post-DONE Owner documentation
build/browser verification in that record belongs to the dated 2026-10-16 Push task.
Current release work follows the separate
[source, local signed-RC and Play gates](../../../docs/product/RELEASE_CHECKLIST.md#acceptance-gates):
fresh release artifact/certificate and exact embedded APK/token inspection must be recorded
privately before local RC acceptance. Historical debug proof establishes neither those
release results nor Play delivery or the remaining runtime gates.
