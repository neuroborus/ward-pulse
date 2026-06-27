# WardPulse

WardPulse watches the pulse of your AI tools.

WardPulse is a local-first usage dashboard for AI tool spend, limits, credits, and activity across providers. The initial product track targets Android phones, Wear OS, and a lightweight Watch Face Format surface.

## Repository Shape

This repository is intentionally organized as one product monorepo with separate runtime surfaces:

- `core/` contains the Rust domain model, provider normalization, FFI boundary, and CLI.
- `apps/phone_flutter/` contains the Flutter phone app shell.
- `apps/wear_android/` contains the native Kotlin/Compose for Wear OS shell.
- `apps/watchface_wff/` contains the Watch Face Format package shell.
- `schemas/` contains shared JSON schemas for snapshots, accounts, usage buckets, and budgets.
- `fixtures/` contains sanitized provider fixtures and stable dashboard snapshots.
- `bindings/` contains generated and hand-written platform binding wrappers.
- `docs/` contains product, architecture, security, and release documentation.
- `tools/` contains local automation for code generation, fixture validation, and Android Rust builds.

## Current Phase

The repository is at Phase 0: foundation and structure. Platform projects are represented as idiomatic shells, not generated app projects yet. That keeps the first commit focused on ownership boundaries and avoids generated Flutter or Gradle noise before the core model stabilizes.

## Useful Commands

Install `just` if you want the command shortcuts.

```sh
just test-core
just lint-core
just check-core
just gen-bindings
just run-phone
just run-wear
just build-watchface
```

Direct Rust commands work from `core/`:

```sh
cargo fmt --all -- --check
cargo clippy --workspace --all-targets -- -D warnings
cargo test --workspace
```

## Documentation

Start with [docs/README.md](docs/README.md). It is the documentation index and project gate. The original development plan lives at [docs/DEVELOPMENT_PLAN.md](docs/DEVELOPMENT_PLAN.md).

Repository-wide working agreements for agents and humans live in [AGENTS.md](AGENTS.md).
