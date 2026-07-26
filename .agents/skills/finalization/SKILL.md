---
name: finalization
description: Post-change finalization checklist for WardPulse (Rust core, Flutter phone shell, Kotlin Wear OS shell, WFF watch face, shared schemas, fixtures, Vocs documentation, and tooling). Use after completing feature, fix, refactor, documentation, or structure work before handoff or commit drafting.
---

# Finalization — WardPulse

> **Post-change checklist for `ward-pulse`**
>
> Run this after implementation or documentation work to keep the monorepo coherent.
>
> Last Updated: 2026-07-24

## 1. Scope Review

- [ ] Changes match the current product phase in `docs/DEVELOPMENT_PLAN.md`.
- [ ] Root files stay short and operational; durable requirements stay under `docs/`.
- [ ] No generated platform project noise was added unless the user asked for it.
- [ ] No unrelated local or user changes were reverted.
- [ ] Changed OpenPencil sources and their generated runtime exports are staged together.
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

- [ ] No provider credentials, authorization headers, raw prompts, or sensitive raw provider payloads entered the change set.
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
- [ ] If durable docs, Vocs pages, component READMEs, or site navigation changed, run:

```bash
just check-docs
```

## 5. Documentation Review

- [ ] `docs/README.md` links any new durable document.
- [ ] The Vocs page and `docs/site/vocs.config.ts` navigation are updated for documentation exposed on the site.
- [ ] Vocs pages import authoritative Markdown instead of duplicating it.
- [ ] `README.md` still describes the current repository shape and commands.
- [ ] Product, provider, release, or security docs are updated when behavior or boundaries changed.
- [ ] Placeholder TODOs are acceptable only for intentionally deferred platform generation work.

## 6. Staging And Commit Boundary

**Finalization never creates a git commit.**

When the user asks to finalize, finish checks, then stage only the files that belong to
this change set (`git add` the relevant paths). Stop there.

- Do **not** run `git commit`, `git commit --amend`, or any equivalent.
- Do **not** treat "finalize", "finalization", "handoff", or "stage" as permission to commit.
- Create a commit only when the user explicitly asks to commit (for example "commit",
  "create a commit", "закоммить").
- Draft the commit message for the staged set; leave the actual commit to the user or to a
  later explicit request.

## 7. Commit Message Draft

Draft commit messages in Conventional Commits form:

```text
type(scope): imperative summary
```

Rules:

- Prefer a small single-line message with no body. A subject line alone is the default and the preferred form; do not append details, rationale, or file lists just because they exist.
- Use `type(scope):` with a lowercase type and a short scope. Do not draft bare subjects such as `docs: …` when a scope applies.
- Keep the subject imperative, about 72 characters or fewer, and focused on why the change lands.
- Add a body only when the change is genuinely unclear without it. Treat a body as the exception, not the habit.
- Do not insert line breaks without a reason. Write each body paragraph as one single line and let the git client wrap it; never hard-wrap a sentence across several lines.
- Use a line break only to separate the subject from the body, to separate paragraphs, or to list items.
- Match recent `git log` style. Prefer existing scopes over inventing new ones.

Common types:

| Type | Use for |
| --- | --- |
| `feat` | user-visible capability or contract addition |
| `fix` | bug or incorrect behavior correction |
| `chore` | planning, maintenance, tooling, or non-user-facing docs/process updates |
| `docs` | documentation-only product/site prose when `chore(docs)` is too weak a fit |
| `test` | tests only |
| `ci` | GitHub Actions or check wiring |
| `refactor` | internal restructuring without behavior change |

Common scopes:

| Scope | Owns |
| --- | --- |
| `docs` | `docs/`, Vocs site, planning, provider/security/release notes |
| `core` | Rust domain crates |
| `providers` | provider adapters and contracts spanning providers |
| `openai` / `codex` / `claude` / `cursor` | one provider family |
| `phone` | Flutter phone shell |
| `wear` | Wear OS shell |
| `watchface` | WFF package |
| `sync` | phone-to-watch transport |
| `design` | OpenPencil sources and brand exports |
| `agents` | `.agents/skills/` and agent workflow |
| `android` | shared Android harness or toolchain notes |

Preferred examples, single line and no body:

```text
chore(docs): plan adaptive provider UI, polling, and watch rings
feat(providers): add on-device Codex usage reporting
fix(wear): sync live provider data to watch surfaces
chore(agents): document conventional commit drafting
```

When a body is genuinely required, keep it on one line:

```text
chore(docs): plan adaptive provider UI, polling, and watch rings

Record the dual plan/platform model and phases 9–13, set the global refresh floor to 5–60 minutes, and make finalization stage-only with an explicit no-commit rule.
```

## 8. Handoff Summary

When finalization completes, report:

1. Relevant checklist sections completed or skipped with reason.
2. Commands run and pass/fail status.
3. Important files changed.
4. Remaining risks or intentionally deferred work.
5. Git staging status after staging: what is staged, what remains unstaged or untracked.
6. Idiomatic draft commit message for the staged set, using section 7.

Remind the user that the changes are staged only and that no commit was created.
