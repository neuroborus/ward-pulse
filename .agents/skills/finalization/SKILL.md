---
name: finalization
description: Post-change finalization checklist for WardPulse (Rust core, Flutter phone shell, Kotlin Wear OS shell, WFF watch face, shared schemas, fixtures, docs, and tooling). Use after completing feature, fix, refactor, documentation, or structure work before handoff or commit drafting.
---

# Finalization — WardPulse

> **Post-change checklist for `ward-pulse`**
>
> Run this after implementation or documentation work to keep the monorepo coherent.
>
> Last Updated: 2026-06-28

## 1. Scope Review

- [ ] Changes match the current product phase in `docs/DEVELOPMENT_PLAN.md`.
- [ ] Root files stay short and operational; durable requirements stay under `docs/`.
- [ ] No generated platform project noise was added unless the user asked for it.
- [ ] No unrelated local or user changes were reverted.
- [ ] Changes follow root `AGENTS.md` working agreements.

## 2. Boundary Review

- [ ] Rust domain logic stays under `core/`.
- [ ] Provider normalization stays in Rust; platform transport and credential storage stay in app shells.
- [ ] Flutter phone work stays in `apps/phone_flutter/`.
- [ ] Wear OS Kotlin/Compose work stays in `apps/wear_android/`.
- [ ] Watch Face Format resources stay in `apps/watchface_wff/`.
- [ ] Generated bindings stay in `bindings/*/generated/`; source interface design stays in `core/ward-pulse-ffi/`.
- [ ] Shared contracts stay in `schemas/`; sanitized examples stay in `fixtures/`.

## 3. Security Review

- [ ] No provider credentials, authorization headers, raw prompts, or sensitive raw provider payloads were committed.
- [ ] Logs, fixtures, examples, and docs use redacted or mock data.
- [ ] Credential rules in `docs/product/SECURITY_MODEL.md` still match implementation assumptions.
- [ ] Wear OS and watch face surfaces do not gain credential entry or credential storage responsibilities.

## 4. Tests And Checks

- [ ] If Rust code changed, run:

```bash
cd core && cargo fmt --all -- --check
cd core && cargo clippy --workspace --all-targets -- -D warnings
cd core && cargo test --workspace
```

- [ ] If Flutter code changed and the project is generated, run:

```bash
cd apps/phone_flutter && flutter analyze && flutter test
```

- [ ] If Android/Wear/WFF Gradle projects are generated, run the relevant Gradle test/build task.
- [ ] If schemas or fixtures changed, validate fixture shape manually or with `tools/validate-fixtures/` when available.
- [ ] If GitHub Actions workflows changed, run `actionlint .github/workflows/*.yml`.

## 5. Documentation Review

- [ ] `docs/README.md` links any new durable document.
- [ ] `README.md` still describes the current repository shape and commands.
- [ ] Product, provider, release, or security docs are updated when behavior or boundaries changed.
- [ ] Placeholder TODOs are acceptable only for intentionally deferred platform generation work.

## 6. Handoff Summary

When finalization completes, report:

1. Relevant checklist sections completed or skipped with reason.
2. Commands run and pass/fail status.
3. Important files changed.
4. Remaining risks or intentionally deferred work.
5. Git staging status: staged, unstaged, and untracked state.
6. Idiomatic draft commit message for the staged set.

Do not create a commit unless the user explicitly asks for one.
