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

Complete the applicable sections below; read their linked checklists before deciding what
applies. Runner steps also follow [agent-runner.md](agent-runner.md) for the task-authoritative
Native/HOST division. These routes do not waive checks or change authorship/commit authority.

## 1. Scope Review

Complete [Scope Review](references/review.md#1-scope-review).

## 2. Boundary Review

Complete [Boundary Review](references/review.md#2-boundary-review).

## 3. Security Review

Complete [Security Review](references/review.md#3-security-review).

## 4. Tests And Checks

Read the complete [Tests And Checks](references/checks.md#4-tests-and-checks) matrix, including
test-authoring, conditional empty-cache/reuse verification and exact-commit CI repair acceptance.
Every applicable gate remains mandatory. Name unrun checks and their operator; never report
an unexecuted command as passing.

## 5. Emulator Check

Apply [Emulator Check](references/checks.md#5-emulator-check), including its device-triggering
changes and explicit skip reasons. Tests alone do not establish that the app runs.

## 6. Documentation Review

Complete [Documentation Review](references/review.md#6-documentation-review).

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

Before drafting a message, apply [Commit Message Draft](references/commit-message.md):
Conventional Commits, existing short scopes, imperative subject and a single-line subject
without a body by default. The reference owns the detailed rules, type/scope mapping and examples.

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
