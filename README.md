# WardPulse

WardPulse watches the pulse of your AI tools.

WardPulse is a local-first usage dashboard for AI tool spend, limits, credits, and activity across providers. The initial product track targets Android phones, Wear OS, and a lightweight Watch Face Format surface.

## Repository Shape

This repository is intentionally organized as one product monorepo with separate runtime surfaces:

- `core/` contains the Rust domain model, provider normalization, FFI boundary, and CLI.
- `apps/phone_flutter/` contains the Flutter phone app shell.
- `apps/wear_android/` contains the native Kotlin/Compose for Wear OS shell.
- `apps/watchface_wff/` contains the declarative Watch Face Format package.
- `schemas/` contains shared JSON schemas for snapshots, accounts, usage buckets, and budgets.
- `fixtures/` contains sanitized provider fixtures and stable dashboard snapshots.
- `bindings/` contains platform binding wrappers.
- `brand/` contains protected product identity, shared OpenPencil sources, and store artwork.
- `docs/` contains product documentation and the Vocs site workspace.
- `tools/` contains repeatable local development and validation automation.

## Current Phase

Phase 7 implementation is complete. Live acceptance remains: save an OpenAI Admin API key on
the phone and confirm that the dashboard shows organization usage and cost reporting.

## Useful Commands

Install `just` if you want the command shortcuts.

```sh
just test-core
just lint-core
just check-core
just check-phone
just snapshot-core
just validate-fixtures
just build-android-rust
just run-phone
just check-wear
just validate-watchface
just check-watchface
just docs-dev
just check-docs
just export-icons
just build-wear
just test-wear-device
just test-phone-watch-sync
just run-wear
just build-watchface
ANDROID_SERIAL="$WEAR_SERIAL" just run-watchface
```

Direct Rust commands work from `core/`:

```sh
cargo fmt --all -- --check
cargo clippy --workspace --all-targets -- -D warnings
cargo test --workspace
cargo run --quiet -p ward-pulse-cli
```

Fixture validation runs from the repository root:

```sh
python3 tools/validate-fixtures/validate_json.py
```

## Documentation

Start with [docs/README.md](docs/README.md). It is the documentation index and project gate. The
Vocs workflow lives in [docs/DOCUMENTATION.md](docs/DOCUMENTATION.md), the development plan in
[docs/DEVELOPMENT_PLAN.md](docs/DEVELOPMENT_PLAN.md), and the verified Android/Flutter environment
in [docs/ANDROID_TOOLCHAIN.md](docs/ANDROID_TOOLCHAIN.md).
Design asset ownership and OpenPencil exports are documented in
[docs/DESIGN_ASSETS.md](docs/DESIGN_ASSETS.md).

Repository-wide working agreements for agents and humans live in [AGENTS.md](AGENTS.md).

## License

WardPulse source code, docs, schemas, fixtures, and tooling are licensed under the [Apache License 2.0](LICENSE) unless a file explicitly says otherwise.

The Apache-2.0 license does not grant rights to the WardPulse name, logo, app icon, watch face identity, store listings, or other product branding. Brand and product identity rules live in [TRADEMARKS.md](TRADEMARKS.md) and [brand/README.md](brand/README.md).
