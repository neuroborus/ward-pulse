# Release Checklist

This checklist is a gate, not a schedule.

## Core

- Rust workspace builds.
- Core tests pass.
- Mock fixture generates a stable dashboard snapshot.
- Snapshot includes today, week, month, alerts, and watch summary state.

## Phone

- Flutter app starts on an Android emulator.
- Home dashboard renders mock data.
- Provider detail pages are reachable.
- Credentials are masked after save.
- Sync logs are redacted.

## Wear OS

- Wear app runs on emulator.
- Today, week, providers, alerts, and last sync screens are readable.
- Stale data state is visible.
- Latest successful summary survives sync failure.

## Watch Face

- WFF package builds.
- Face installs on emulator or physical watch.
- Ambient mode remains readable.
- Tap target opens the Wear OS app where supported.

## Privacy And Legal

- App includes the independent-product disclaimer.
- Privacy policy draft exists.
- Data deletion flow exists.
- No credentials or sensitive provider payloads appear in logs.
