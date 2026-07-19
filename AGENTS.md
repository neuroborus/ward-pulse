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
- Do not commit secrets, provider credentials, authorization headers, raw prompts, or sensitive raw provider payloads.
- Do not treat WardPulse brand assets as covered by Apache-2.0 unless a file explicitly says so.

## Required Checks

After Rust changes, run:

```bash
cd core && cargo fmt --all -- --check
cd core && cargo clippy --workspace --all-targets -- -D warnings
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

## Documentation

- Start from `docs/README.md` for durable project documentation.
- Keep root `README.md` short and operational.
- Keep product, provider, security, and release guidance in `docs/product/`.
- Update local skills in `.agents/skills/` when repository workflow or ownership boundaries change.
