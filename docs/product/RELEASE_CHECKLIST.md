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

## Signing

Local release builds read one keystore for all three packages. With Play App Signing, this is
the **upload key**: it signs the AAB submitted to Play, while Google signs the APKs delivered to
devices with the **app signing key**. The phone and Wear app share `app.wardpulse` and must keep
one app signing identity. The watch face is a separate listing under `app.wardpulse.watchface`;
reusing its upload key does not establish which app signing key Play uses for that listing.
Verify the Play app signing certificates when checking the distribution identity. See
[Play App Signing: key types and ownership](https://support.google.com/googleplay/android-developer/answer/9842756?hl=en).

- `key.properties` exists at the repository root and names a keystore stored **outside** the
  repository.
- No keystore and no `key.properties` is tracked by git. Both are ignored; `git status` is the
  check.
- `just bundle-phone`, `just bundle-wear` and `just bundle-watchface` complete. Each one fails
  rather than fall back to the debug key, so a build that succeeds is a build that is signed.
- A plain `assembleRelease` without the key still builds, warns that it is debug-signed, and is
  never what gets uploaded.

Creating the key is a one-time setup, not a gate. It belongs to whoever publishes the app:

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
