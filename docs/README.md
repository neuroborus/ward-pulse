# WardPulse Docs

This directory is the documentation gate for the project. Root files should stay operational and short; durable product and architecture decisions live here.

## Start Here

- [DEVELOPMENT_PLAN.md](DEVELOPMENT_PLAN.md) is the full product and implementation plan.
- [ANDROID_TOOLCHAIN.md](ANDROID_TOOLCHAIN.md) records the verified Android/Flutter development baseline, SDK package names, AVDs, and setup commands.
- [product/ANDROID_GOALS.md](product/ANDROID_GOALS.md) defines the MVP goal, surfaces, and non-goals.
- [product/PROVIDER_NOTES.md](product/PROVIDER_NOTES.md) tracks provider integration assumptions and open questions.
- [product/SECURITY_MODEL.md](product/SECURITY_MODEL.md) defines local-first credential and diagnostics rules.
- [product/RELEASE_CHECKLIST.md](product/RELEASE_CHECKLIST.md) is the release readiness gate for phone, Wear OS, and watch face builds.
- [../LICENSE](../LICENSE), [../TRADEMARKS.md](../TRADEMARKS.md), [../THIRD_PARTY_NOTICES.md](../THIRD_PARTY_NOTICES.md), and [../brand/README.md](../brand/README.md) define the source license, attribution gate, and brand boundaries.

## Project Gates

Use this index before adding new work:

1. Product scope belongs in `docs/product/`.
2. Stable cross-platform data contracts belong in `schemas/`.
3. Portable business logic belongs in `core/`.
4. Platform-specific UI, transport, storage, and background execution belong in `apps/`.
5. Generated bindings belong in `bindings/*/generated/`; source interfaces belong in `core/ward-pulse-ffi/`.
6. Sanitized examples belong in `fixtures/`; secrets, raw prompts, auth headers, and sensitive provider payloads must not be committed.
7. Product identity assets belong in `brand/`; Apache-2.0 source rights and brand rights stay separate.

## Documentation Rules

- Keep root `README.md` as a short orientation and command entry point.
- Keep long requirements and decisions in this folder.
- Update `DEVELOPMENT_PLAN.md` only when the product direction changes.
- Add focused documents instead of growing one catch-all file.
- Link new documents from this index before relying on them in implementation.
