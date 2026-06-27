---
name: rust-core
description: WardPulse Rust core implementation guidance. Use when editing core models, dashboard snapshots, budgets, alerts, projections, provider normalization, FFI boundaries, fixtures consumed by Rust, or the Rust CLI under core/.
---

# Rust Core — WardPulse

Use this skill for work under `core/` and Rust-owned contracts.

## Architecture

- Keep `ward-pulse-core` independent from provider transport and platform APIs.
- Keep `ward-pulse-providers` focused on parsing, validation, normalization, and provider-specific capability mapping.
- Keep `ward-pulse-ffi` as the source-of-truth platform boundary, not a dumping ground for app behavior.
- Keep `ward-pulse-cli` useful for local snapshots, fixture inspection, and developer diagnostics.

## Domain Rules

- Provider-specific raw data enters the core; normalized dashboard snapshots leave the core.
- Rust owns budgets, credits, projections, alerts, model breakdowns, status mapping, and watch summary derivation.
- Platform code owns HTTP clients, TLS, retries, background execution, secure credential retrieval, encrypted storage, and UI state.
- Prefer deterministic functions that are easy to fixture-test.
- Preserve previous successful snapshot semantics when modeling sync failure states.
- Avoid adding new crates unless they are conventional, lightweight, and justified by the use case.

## Data Modeling

- Model missing provider capabilities explicitly with `Option` values or capability descriptors.
- Keep status states shared and stable: OK, warning, error, rate limited, auth required, stale, unknown.
- Represent money as integer minor units plus an explicit currency code; do not use floating point for stored money.
- Keep core money constructors currency-neutral; provider fixtures and tests may define local USD helpers.
- Avoid assuming every provider has cost, tokens, credits, hourly buckets, or model breakdowns.
- Keep money currency explicit.
- Keep time values UTC at boundaries.

## Validation

After Rust changes, run:

```bash
cd core && cargo fmt --all -- --check
cd core && cargo clippy --workspace --all-targets -- -D warnings
cd core && cargo test --workspace
```

Add or update tests when changing budget math, projection logic, alert rules, status aggregation, provider normalization, or public FFI shape.
