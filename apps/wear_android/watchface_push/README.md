# Bundled Push watch face

This resource-only Android application produces `app.wardpulse.watchfacepush.main` for
[Watch Face Push](https://developer.android.com/training/wearables/watch-face-push).
It is a signed APK dependency of the Wear app, not a runtime Android library. Its minimum
is API 34 with WFF 2; the Wear app minimum is independently API 33. Push availability still
requires a runtime capability check. Packaging alone does not implement installation
recovery, activation, or updates; those belong to the subsequent controller and UI steps.

## Resource ownership

The `main` resource source set in [build.gradle.kts](build.gradle.kts) consumes
`apps/watchface_wff/src/main/res/` directly. The legacy `app.wardpulse.watchface` package,
its signing/settings, and its independent build remain intact. The canonical resource owner
is [the WFF module](../../watchface_wff/README.md); change its generator, never generated XML
or PNGs. Both packages retain the explicit `app.wardpulse` complication and launch targets.
The host's affected complication services trust only these two own face packages through
`android.support.wearable.complications.SAFE_WATCH_FACES`.

## Signing inputs

The Owner provisions local identities. At the repository root, supply ignored
`watchface-push-debug.properties` for development and `watchface-push-release.properties`
for release. Each contains the property names `storeFile`, `storePassword`, `keyAlias`, and
`keyPassword`, with real values supplied privately. `storeFile` must be an absolute path
outside this repository. Java properties escaping applies to paths and values. Do not put
credentials in examples, logs, notes, Source, or command-line Gradle properties.

Keep the development keystore in a persistent private location outside all build outputs:
`clean` must not delete it. Reuse that same certificate for version N and N+1. A different
development key on each local build prevents a normal face upgrade. CI creates its own
temporary development identity for its debug build; it never provisions a release key.

`RequirePushSigning` rejects absent/incomplete configuration and unusable private keys.
Neither Push build type falls back to the host signing configuration or the conventional
Android debug key. A configured release certificate must also differ from the configured
Push development certificate. `PrepareDefaultWatchFace` in
[the host build script](../app/build.gradle.kts) verifies the actual signed APK and rejects
a certificate matching the selected host certificate, including debug. AGP's host signing
validation runs first so a fresh host debug keystore is available for this comparison.

The existing host `key.properties` and `wardpulseRequireReleaseKey` publishability guard
remain unchanged. Phone and Wear still share their host signing identity. Push release
signing is an additional independently required identity, never permission to publish a
debug-signed host. See [Signing](../../../docs/product/RELEASE_CHECKLIST.md#signing) for
the existing phone/Wear release requirements.

## Ordinary builds and versions

From `apps/wear_android/`, after private signing setup:

```sh
./gradlew :app:assembleDebug -PwardpulsePushVersionCode=1
./gradlew :app:assembleDebug -PwardpulsePushVersionCode=2
```

`wardpulsePushVersionCode` defaults to 1 and accepts a positive Kotlin/Android integer.
Increase it when distributing a newer face. Both commands build the same Push package;
keep its certificate stable. For a publishable host release, use the existing release guard:

```sh
./gradlew :app:bundleRelease -PwardpulseRequireReleaseKey=true -PwardpulsePushVersionCode=2
```

Provide both host release signing and separate Push release signing before that build.
The ordinary variant dependency graph packages and signs the face, validates it, generates
the variant bundle, and packages the Wear app. No recursive Gradle, manual APK copy, token
substitution, or source edit is needed. `clean` removes the generated bundle, not keys.

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

## Pending acceptance

No Owner build, signing readiness, APK allowlist/provider-target inspection, official
validation/token binding, cold-cache completion, warm reuse, or actual N-to-N+1 upgrade is
claimed by this implementation step. These remain Owner acceptance after the four-commit
Runner execution finishes and Root reviews it. API 33 startup, supported Push installation,
API 34/35 separate-install fallback, preserved configuration/selection, and complication
propagation through both packages also remain pending. Controller/utility implementation
and their documentation retain their subsequent planned positions. Device captures and
measured baseline reconciliation belong to the required separate follow-up execution.
