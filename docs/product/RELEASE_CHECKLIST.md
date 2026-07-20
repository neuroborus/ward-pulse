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
- Today, week, providers, alerts, and last sync screens are readable.
- Stale data state is visible.
- Latest successful summary survives sync failure.
- Missing phone data does not create an implicit mock summary.

## Watch Face

- WFF package builds.
- Face installs on emulator or physical watch.
- Ambient mode remains readable.
- Tap target opens the Wear OS app where supported.
- Today, week, and provider status come from WardPulse complication data sources.

## Privacy And Legal

- App includes the independent-product disclaimer.
- Privacy policy draft exists.
- Data deletion flow exists.
- Apache-2.0 license scope and Rust package metadata are still accurate.
- WardPulse trademark and brand asset boundaries are documented.
- Third-party notices are current for bundled dependencies and assets.
- No credentials or sensitive provider payloads appear in logs.
