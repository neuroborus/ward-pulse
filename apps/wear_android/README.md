# WardPulse Wear OS App

Native Wear OS shell for compact WardPulse dashboard screens.

The app uses Kotlin, Compose for Wear OS Material 3, and a locally persisted sanitized mock
summary. Phone-to-watch transport starts in Phase 5.

## Ownership

- Today, week, providers, alerts, and last sync screens.
- Local storage of the latest watch summary.
- Wear-specific navigation, rotary input, shape-aware layouts, and stale data states.
- Wear Data Layer receiver from Phase 5 onward.

Provider credentials are never entered or stored on the watch.

## Commands

From the repository root:

```sh
just check-wear
just build-wear
just test-wear-device
just run-wear
```

`test-wear-device` and `run-wear` require one active Wear AVD. Canonical AVD names and setup
commands live in [`docs/ANDROID_TOOLCHAIN.md`](../../docs/ANDROID_TOOLCHAIN.md).
