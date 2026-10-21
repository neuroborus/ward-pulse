---
name: finalization
description: Post-change finalization checklist for WardPulse (Rust core, Flutter phone shell, Kotlin Wear OS shell, WFF watch face, shared schemas, fixtures, Vocs documentation, and tooling). Use after completing feature, fix, refactor, documentation, or structure work before handoff or commit drafting.
---

# Finalization — WardPulse

> **Post-change checklist for `ward-pulse`**
>
> Run this after implementation or documentation work to keep the monorepo coherent.
>
> Last Updated: 2026-10-17

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

Apply [test-authoring](../test-authoring/SKILL.md) when authoring or changing tests and during
finalization review: verify necessity, determinism and measured cost. Every required gate
below remains mandatory.

Most of this section reaches for the network or a device, so an isolated agent cannot finish it
alone. That does not excuse a box: name every check you could not run and hand it to the
operator, never tick one you did not execute. `AGENTS.md`, *When a check cannot run where you
are*, lists which is which.

- [ ] If Rust code changed, run:

```bash
cd core && cargo fmt --all -- --check
cd core && cargo clippy --workspace --all-targets -- -D warnings
cd core && RUSTDOCFLAGS="-D warnings" cargo doc --workspace --no-deps --document-private-items
cd core && cargo test --workspace
```

- [ ] If Flutter code changed and the project is generated, run:

```bash
just check-phone
```

  This runs `dart format --set-exit-if-changed` over `apps/phone_flutter` and `bindings/dart`,
  then `flutter analyze` and `flutter test`. Use `just fmt-phone` to apply formatting.

- [ ] If Android/Wear/WFF Gradle projects are generated, run the relevant Gradle test/build task.
- [ ] If schemas or fixtures changed, run `just validate-fixtures`: it parses every file and checks each golden fixture against its schema.
- [ ] If GitHub Actions workflows changed, run `actionlint .github/workflows/*.yml`.
- [ ] If a local skill changed, run the `quick_validate.py` command from `AGENTS.md` for each affected skill directory.
- [ ] If build or validation artifact downloads, pins or caches changed, or a CI failure suggests a warm cache is hiding a download failure, run the affected existing check on a network-capable host with a new, empty, task-owned cache. Verify the actual download, checksum and tool completion, then repeat once with that cache to prove reuse. Do not delete or seed shared caches, copy the repository, or add a test framework for this check. Record the command, cache location and outcomes; a warm-cache pass alone does not prove the download works.
- [ ] If durable docs, Vocs pages, component READMEs, or site navigation changed, run:

```bash
just check-docs
```

- [ ] For a CI repair, after an already-authorized push, verify that the workflows expected for that event and the affected paths all completed successfully on the exact pushed commit. Pending, failed or canceled runs, and successful runs on an older commit, do not establish success. This is post-push acceptance, not a local precommit gate or permission to push.

## 5. Emulator Check

Automated gates do not exercise the app. Unit tests use fakes, so they never load
`libward_pulse_ffi.so`, never resolve an exported symbol, and never render a screen.

Run the app on an emulator when the change could only fail there:

- [ ] FFI surface changed — exported symbol names, argument or return shapes, or the
      Dart binding. Symbols resolve at **run time**, so a mismatch survives every build.
- [ ] The serialized snapshot contract changed — a new or renamed field, or a different
      value shape. Host-side round trips do not prove the Android build agrees.
- [ ] UI, widget, watch face, or phone-to-watch payload behaviour changed.
- [ ] Background scheduling, secure storage, or WebView sign-in changed.

Skip it, and say so, for changes that cannot reach a device: pure refactors behind an
unchanged contract, comments and docs, tests, CI wiring, lockfiles.

```bash
adb devices -l                     # phone and Wear AVDs are usually already running
tools/build-android-rust/build.sh  # Rust .so for Android ABIs — slow
cd apps/phone_flutter && flutter build apk --debug
adb -s <serial> install -r build/app/outputs/flutter-apk/app-debug.apk
adb -s <serial> shell am start -n app.wardpulse/.MainActivity
adb -s <serial> logcat -d | grep -i wardpulse
```

Report what was exercised on device and what was not. "Tests pass" is not evidence that
the app runs; only the device is.

## 6. Documentation Review

- [ ] `docs/README.md` links any new durable document.
- [ ] The Vocs page and `docs/site/vocs.config.ts` navigation are updated for documentation exposed on the site.
- [ ] Vocs pages import authoritative Markdown instead of duplicating it.
- [ ] Root README begins with current product guidance, the approved PNG gallery and a user-guide entry.
- [ ] Apply [user-docs](../user-docs/SKILL.md) to public pages, routes and screenshots; refresh
      affected UI PNGs and their index, and keep developer/internal documentation out of the public site.
- [ ] Apply [docs-gate](../docs-gate/SKILL.md#keep-documentation-current) to reconcile affected
      documentation in this change set, or justify no documentation impact in the handoff.
- [ ] Placeholder TODOs are acceptable only for intentionally deferred platform generation work.

## 7. Staging And Commit Boundary

Follow the standing commit authorization in [AGENTS.md](../../../AGENTS.md#working-agreements).
For a coordinator commit, finish all applicable checks and the full independent zero-findings
pass after the last correction, then stage only the files belonging to this change set.
No new owner permission request is needed for work covered by that authorization.

The `polishing` pipeline stages an existing change set and stops without committing. A
coordinator commit is a separate action; it does not turn a canceled or failed Runner run
into a completed run. See [agent-runner.md](agent-runner.md#6-commit) for the Runner boundary.
If the task forbids commits, leave the reviewed change set staged and draft its message.

## 8. Commit Message Draft

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

Record the dual plan/platform model and phases 9–13, and set the global refresh floor to 5–60 minutes.
```

## 9. Handoff Summary

When finalization completes, report:

1. Relevant checklist sections completed or skipped with reason, including whether the
   change was exercised on an emulator.
2. Commands run and pass/fail status.
3. Important files changed.
4. Remaining risks or intentionally deferred work.
5. Actual staging and commit state: what is staged, what remains unstaged or untracked, and
   whether an authorized scoped commit exists.
6. Idiomatic draft message for a staged set, or the actual subject and hash for an authorized
   commit, using section 8.

If only staged, state that no commit was created. Otherwise identify the scoped commit and
whether Runner or the coordinator created it. Report the Runner run's actual status separately.
