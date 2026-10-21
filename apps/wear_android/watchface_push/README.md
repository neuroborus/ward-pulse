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

From `apps/wear_android/`, after private development signing setup, these debug commands
illustrate N/N+1 upgrade acceptance:

```sh
./gradlew :app:assembleDebug -PwardpulsePushVersionCode=1
./gradlew :app:assembleDebug -PwardpulsePushVersionCode=2
```

`wardpulsePushVersionCode` defaults to 1 and accepts a positive Kotlin/Android integer.
It controls the Push package's independent version history, not the Wear host version.
Increase it when distributing a newer face and keep the package/certificate stable. These
development examples do not require Push code 2 for the RC: the central
[0.1.0 version table](../../../docs/product/RELEASE_CHECKLIST.md#release-versions) retains
Push code 1 while the Wear host uses code 2; every versionName remains 0.1.0.
For a release artifact, Root uses the existing guarded recipe from the repository root:

```sh
just bundle-wear
```

Provide both host release signing and separate Push release signing before that build.
The ordinary variant dependency graph packages and signs the face, validates it, generates
the variant bundle, and packages the Wear app. No recursive Gradle, manual APK copy, token
substitution, or source edit is needed. `clean` removes the generated bundle, not keys.

Stage A also builds the ordinary guarded Wear release installer, verifies the fixed public
signer pins and compares the producer Push bytes with the generated asset, embedded Wear
AAB, embedded installer and staged Push APK. Its single Actions artifact contains seven
signed binaries plus checksums and sanitized provenance, as listed in the release checklist.
Direct host installers use the upload key, which does not promise debug/Play install update
compatibility. Received-artifact verification and GitHub draft publication remain unfinished
Stage B work; neither a successful upload nor historical debug acceptance closes those gates.

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
