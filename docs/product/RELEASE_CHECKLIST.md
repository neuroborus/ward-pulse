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

One key signs all three packages. The phone and the Wear app share `app.wardpulse`, so Play
refuses to install one over the other unless their signatures match, and the watch face ships
beside them under `app.wardpulse.watchface`.

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
- `-validity` — days. 10000 is about 27 years: a key has to outlive the listing it signs.

`keytool` then asks for a keystore password, a key password, and the identity fields it writes
into the certificate.

Then write `key.properties` at the repository root with four entries — `storeFile` as an
absolute path, plus `storePassword`, `keyAlias` and `keyPassword` holding what `keytool` just
asked for. Nothing in this repository carries example values, and none should be added: a
plausible-looking password in a tracked file is the mistake this arrangement exists to prevent.

**Losing this key ends the listing.** Google Play identifies an app by its signature, so a lost
or rotated key means the existing listing can never be updated again — only republished under a
new identity, losing its installs and reviews. Back the keystore up somewhere separate from the
machine that builds, and keep the passwords with it.

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
