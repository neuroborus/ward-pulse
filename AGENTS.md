# AGENTS.md

## Project Goals

- Build WardPulse as a local-first AI tool usage dashboard for Android phone, Wear OS, and Watch Face Format surfaces.
- Keep one product repository with one Rust domain core, separate platform-native UI shells, shared schemas, fixtures, tests, and release process.
- Keep provider credentials local to user devices and keep fixtures/logs sanitized.
- Keep Apache-2.0 source licensing and WardPulse brand rights separate.
- Keep the code clean, conventional, and easy to extend.

## Working Agreements

- All code comments and logs must be in English.
- Follow the current monorepo layout before creating new directories.
- Avoid introducing new dependencies. Add a crate/package only when it is conventional for the ecosystem and clearly justified.
- Keep Rust domain logic deterministic and independent from Flutter, Android, Google Play APIs, secure storage, and platform transport.
- Keep platform shells responsible for UI, transport, storage, background scheduling, and phone-to-watch propagation.
- Prefer small, focused changes.
- Do not generate full Flutter or Gradle projects unless the current task explicitly requires it.
- Do not create a git commit unless the user explicitly asks to commit. Finalization stages relevant files and drafts a message; it does not commit.
- Do not commit secrets, provider credentials, authorization headers, raw prompts, or sensitive raw provider payloads.
- Do not treat WardPulse brand assets as covered by Apache-2.0 unless a file explicitly says so.
- Keep OpenPencil `.fig` sources with their owner and regenerate runtime exports instead of editing them by hand.

## Repository Map

Use this map before exploring. It is the navigation source of truth; update it when
ownership or layout changes. `justfile` at the root is the command index (`just --list`).

| Subsystem | Path | Purpose |
| --- | --- | --- |
| Rust domain core | `core/ward-pulse-core/` | Deterministic domain logic: snapshot building, alerts, budgets, projections |
| Provider adapters | `core/ward-pulse-providers/` | Parse per-provider usage reports into provider snapshots |
| FFI crate | `core/ward-pulse-ffi/` | C-ABI JSON-string exports of core + providers for the phone |
| CLI | `core/ward-pulse-cli/` | Prints the mock dashboard snapshot (`just snapshot-core`, stdout only) |
| Bindings | `bindings/dart/` | `ward_pulse_bindings` package; loads `libward_pulse_ffi.so` via `dart:ffi` (`kotlin`/`swift` siblings are `.gitkeep` placeholders) |
| Phone shell | `apps/phone_flutter/` | Flutter dashboard, provider connections, settings, watch/widget sync |
| Wear OS app | `apps/wear_android/` | Compose Glance legend, summary store, complications |
| Watch face | `apps/watchface_wff/` | Declarative Watch Face Format package |
| Schemas | `schemas/` | JSON Schemas for snapshots, accounts, usage buckets, budgets, watch summary |
| Fixtures | `fixtures/` | Sanitized provider payloads + cross-language golden snapshots |
| Tools | `tools/` | Review-art generators, icon export, Rust-for-Android build, validators |
| Brand assets | `brand/` | WardPulse identity sources and locked previews (ownership: `docs/DESIGN_ASSETS.md`) |
| Docs | `docs/` | Durable documentation; `docs/product/` holds locked design baselines |
| Skills | `.agents/skills/` | Repo workflow skills (`.claude/skills` is a symlink to it) |
| Local scratch | `LOCAL_ARTIFACTS/` | Gitignored working notes and plans; never committed |

### Rust workspace (`core/`)

Run all cargo commands from `core/` — there is no root `Cargo.toml`. Tests are in-module
(`#[cfg(test)] mod tests` at the bottom of each `mod.rs`); there are no `tests/` directories.

- Types live in `ward-pulse-core/src/model/mod.rs` (`DashboardSnapshot`, `ProviderSnapshot`,
  `Money`). Time handling: `time.rs`.
- `dashboard/mod.rs` builds snapshots and aggregate totals; `alerts/mod.rs` applies alert
  settings and local budget limits; `budget/` evaluates spend against a limit; `projection/`
  projects spend linearly over a period.
- One adapter module per family: `openai/`, `codex/`, `claude/`, `cursor/`, `mock/`.
  `claude/platform.rs` and `cursor/platform.rs` normalize the Anthropic organization and
  Cursor team Admin APIs; `mock/demo.rs` invents demo data. Shared: `allowance.rs`, `poll.rs`.
- FFI surface: `ward-pulse-ffi/src/lib.rs` (single file). Adding a core capability the phone
  needs means touching ffi + `bindings/dart/lib/src/ward_pulse_bindings.dart` +
  `apps/phone_flutter/lib/dashboard/phone_live_bindings.dart`.

### Phone (`apps/phone_flutter/`)

Entry: `lib/main.dart` → `lib/app/ward_pulse_app.dart`. Tests: flat `test/`
(`<name>_test.dart`, usually matching a lib file). Config: `pubspec.yaml` (path dependency on
`bindings/dart`).

- `lib/dashboard/` — screen, per-provider repositories, `phone_live_bindings.dart` (FFI wiring).
- `lib/providers/` — Providers tab: connection rows, credential stores/dialogs,
  `alert_threshold_dialogs.dart`.
- `lib/settings/` — preference stores; `watch_ring_preferences.dart` owns the ring catalog,
  selection, and ring-id migrations.
- `lib/sync/` — headless provider polling and phone→watch transport
  (`watch_sync_service.dart`, scheduler, reporting clients).
- `lib/watchface/` — Watchface tab; `lib/widget/` — home-widget payload and preferences;
  `lib/charts/` — history chart and budget bar.
- Android host code: `android/app/src/main/kotlin/app/wardpulse/` (`MainActivity`,
  `WardPulseAppWidget`, `WatchRefreshListenerService`).

### Wear (`apps/wear_android/`)

Kotlin lives under `app/src/main/java/app/wardpulse/wear/` (ignore the empty top-level
`data/`, `ui/`, `test/` directories). Unit tests: `app/src/test/`; device tests:
`app/src/androidTest/`. Review art: `design/`.

- `ui/` — `WardPulseApp.kt` (screens), `GlanceModels.kt`/`GlanceLegend.kt`, `UsageRings.kt`,
  `RingFamily.kt` (ring-id → family color).
- `data/WatchSummaryStore.kt` — persisted summary; owns `SCHEMA_VERSION` (must match the
  `schemaVersion` written by phone `watch_sync_service.dart`; a mismatch discards the payload).
- `sync/` — `WatchSummaryListenerService.kt`, `WatchDataContract.kt` (paths/keys),
  `PhoneRefreshRequester.kt`. `complication/` — watch complications.

### Watch face (`apps/watchface_wff/`)

Single declarative file: `src/main/res/raw/watchface.xml`, **generated** by
`tools/render-watchface.mjs` (`just render-watchface`) — edit the generator, never the XML;
`just check-watchface` fails on drift. Metadata in `res/xml/watch_face_info.xml`. Validate with
`just validate-watchface`. Geometry and language rules are locked in
`docs/product/WATCH_RING_DESIGN.md` — read it before changing the face.

### Shared contracts and goldens

- `schemas/*.schema.json` — JSON Schemas; validate with `just validate-fixtures`.
- `fixtures/providers/<family>/` — sanitized provider payloads used by Rust and phone tests.
- `fixtures/snapshots/` — cross-language goldens; `dashboard_today.json` is compared in
  FFI/CLI tests and loaded by 12+ phone tests. Regenerate via `just snapshot-core > fixtures/snapshots/dashboard_today.json`;
  the other snapshot fixtures have no generator and are edited by hand.

### Design and docs

- Locked baselines in `docs/product/`: `WATCH_RING_DESIGN.md` (face), `WEAR_GLANCE_DESIGN.md`
  (Glance), `PHONE_WIDGET_DESIGN.md` (widget); asset ownership in `docs/DESIGN_ASSETS.md`;
  phases in `docs/DEVELOPMENT_PLAN.md`; provider API notes in `docs/product/PROVIDER_NOTES.md`.
- Review art is generated, never hand-edited: `tools/render-watch-ring-designs.mjs` (face),
  `tools/render-wear-glance-designs.mjs` (Glance), `tools/render-phone-widget-designs.mjs`
  (widget), `tools/render-brand-icons.mjs` + `just export-icons` (brand marks).
- Android toolchain and device workflow: `docs/ANDROID_TOOLCHAIN.md`.

## Task → first files

### Provider parsing or a new provider capability
Start with:
- `core/ward-pulse-providers/src/<family>/mod.rs`
- `fixtures/providers/<family>/`
- `docs/product/PROVIDER_NOTES.md`

### Dashboard aggregation, alerts, budgets
Start with:
- `core/ward-pulse-core/src/dashboard/mod.rs`
- `core/ward-pulse-core/src/alerts/mod.rs`
- `core/ward-pulse-core/src/model/mod.rs`

### Exposing core data to the phone (FFI)
Start with:
- `core/ward-pulse-ffi/src/lib.rs`
- `bindings/dart/lib/src/ward_pulse_bindings.dart`
- `apps/phone_flutter/lib/dashboard/phone_live_bindings.dart`

### Phone UI (dashboard, providers, settings)
Start with:
- `apps/phone_flutter/lib/dashboard/dashboard_screen.dart`
- `apps/phone_flutter/lib/providers/providers_screen.dart`
- `apps/phone_flutter/lib/settings/settings_screen.dart`

### Watch ring catalog, selection, payload
Start with:
- `apps/phone_flutter/lib/settings/watch_ring_preferences.dart`
- `apps/phone_flutter/lib/sync/watch_sync_service.dart`
- `apps/phone_flutter/lib/watchface/watchface_screen.dart`

### Phone→watch transport or summary schema
Start with:
- `apps/phone_flutter/lib/sync/watch_sync_service.dart`
- `apps/wear_android/app/src/main/java/app/wardpulse/wear/data/WatchSummaryStore.kt`
- `apps/wear_android/app/src/main/java/app/wardpulse/wear/sync/WatchDataContract.kt`

### Wear UI (Glance, rings, complications)
Start with:
- `apps/wear_android/app/src/main/java/app/wardpulse/wear/ui/WardPulseApp.kt`
- `apps/wear_android/app/src/main/java/app/wardpulse/wear/ui/GlanceModels.kt`
- `apps/wear_android/app/src/main/java/app/wardpulse/wear/ui/RingFamily.kt`

### Watch face rendering
Start with:
- `docs/product/WATCH_RING_DESIGN.md`
- `tools/render-watchface.mjs` (writes `apps/watchface_wff/src/main/res/raw/watchface.xml`)

### Phone home widget
Start with:
- `apps/phone_flutter/lib/widget/phone_widget_payload.dart`
- `apps/phone_flutter/android/app/src/main/kotlin/app/wardpulse/WardPulseAppWidget.kt`
- `docs/product/PHONE_WIDGET_DESIGN.md`

### Review art or design changes
Start with:
- the owning design doc in `docs/product/`
- the matching `tools/render-*-designs.mjs` generator

### Tests
Start with:
- Rust: `mod tests` at the bottom of the module you changed (run from `core/`)
- Phone: `apps/phone_flutter/test/<file>_test.dart` (usually mirrors the lib file name)
- Wear: `apps/wear_android/app/src/test/` (unit) or `app/src/androidTest/` (device)

## Context and File Reading Policy

- Use the Repository Map and Task → first files before exploring the tree.
- Search for symbols (grep) before opening files; open a file only when the search confirms it
  is relevant.
- Prefer targeted reads (line ranges around the match) over full-file reads; most files here
  are read for one function or one table.
- Do not reread files that have not changed since the last read.
- Do not read generated, build, lock, or vendor content (`core/target/`, `*/build/`,
  `node_modules/`, `Cargo.lock`, `package-lock.json`, `pubspec.lock`, `bindings/*/generated/`)
  unless the task is specifically about it.
- Use subagents for broad repository exploration; keep the main session's context on files
  relevant to the current change.
- Never sacrifice correctness to save context: verify claims in the actual code before acting
  on them, and prefer one extra targeted read over a guess.

## Required Checks

After Rust changes, run:

```bash
cd core && cargo fmt --all -- --check
cd core && cargo clippy --workspace --all-targets -- -D warnings
cd core && RUSTDOCFLAGS="-D warnings" cargo doc --workspace --no-deps --document-private-items
cd core && cargo test --workspace
```

After schema or fixture changes, validate JSON syntax and keep examples sanitized:

```bash
just validate-fixtures
```

After local skill changes, run:

```bash
python3 /home/neuroborus/.codex/skills/.system/skill-creator/scripts/quick_validate.py .agents/skills/<skill-name>
```

After durable documentation, Vocs page, or navigation changes, run:

```bash
just check-docs
```

## Documentation

- Start from `docs/README.md` for durable project documentation.
- Keep root `README.md` short and operational.
- Keep product, provider, security, and release guidance in `docs/product/`.
- Keep component-specific guidance beside its owner and expose it through thin pages in `docs/site/`.
- Update `docs/site/vocs.config.ts` when site navigation changes.
- Update local skills in `.agents/skills/` when repository workflow or ownership boundaries change.
- `.claude/skills` is a symlink to `.agents/skills/` so Claude Code discovers the same set. Edit
  the skills through `.agents/skills/`; never add a second copy under `.claude/`.
