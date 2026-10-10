---
name: delegation
description: WardPulse delegation contract — who does the work and who checks it. Use before writing any production code, editing a generator, changing a locked design baseline, or building a mock. Covers subagent design loops, Agent Runner pipelines, the zero-findings bar, and what the coordinating session may and may not touch itself.
---

# Delegation — WardPulse

The coordinating session does not write production code and does not author design. It
delegates, then verifies. This is the owner's standing instruction, restated 2026-10-10.

## Who does what

| Work | Owner | Coordinator's job |
| --- | --- | --- |
| Design: locked baselines, visual language, mocks, review art | A subagent | Verify to zero findings |
| Code: generators, Kotlin, Dart, Rust, schemas, tests | Agent Runner | Verify to zero findings |
| Measurement, device capture, reading sources, running checks | Coordinator | — |
| Deciding what to build | Owner | Put the choice in front of them |

A mock is design. Patching a generator to produce a picture is still patching a generator —
it goes to a subagent, not to the coordinator's own hands.

## Code goes through the runner

Plan with `plan-authoring`, execute with `plan-execution`. `polishing` finalizes and stages an
existing change set **without committing**, which is what AGENTS.md wants when the owner has
not asked for a commit.

**Who runs which check is settled in `.agents/skills/finalization/agent-runner.md`.** It
carries the division between what a step proves inside its sandbox and what the owner runs on
the host, with the reasons and the dates. Read it before scoping a task's gates; do not restate
it here and do not re-derive it per task.

That file is reached by reference, not by configuration. The runner's `finalization` setting
accepts only `auto`, `none`, or a path ending in `/SKILL.md`, so it stays at `auto` and the step
loads `.agents/skills/finalization/SKILL.md`. **A task's gates section is what carries the
division to the step**, and it is authoritative for that step — so every runner task names the
required checks explicitly, says which ones the owner runs afterwards, and points at
`agent-runner.md` for the reasoning.

Two things this repository has learned the hard way, and they belong here rather than there:

- **Trusted-check configuration is frozen at run start.** Editing
  `LOCAL_ARTIFACTS/agent-runner.json` while a run exists leaves that run unable to resume *and*
  unable to cancel — the protected-input guard refuses both. Prepare the selection before
  starting, never during.
- **A backend upgrade mid-run strands the run, and every run started after it from the same
  MCP session.** The runner records an immutable provider-policy receipt per role at the first
  probe and refuses a later probe that disagrees (`ERR_PROVIDER_POLICY_CHANGED`). Codex
  auto-updates on an hourly schedule; on 2026-10-10 it swapped 0.162.0 for 0.162.1 in the
  second the run was created, which killed the reviewer at launch and then failed every
  dispatch, because the long-lived MCP server kept resolving the old binary while the shell
  resolved the new one. The symptom is a detached continuation that exits before durable
  acknowledgement, with no rollout session written. Neither run could be recovered; both were
  cancelled. The way through is to drive the pipeline from the CLI — `agent-run run <pipeline>
  --project … --task …` — where both probes see one binary, which also puts the real error on
  stderr instead of leaving it to be dug out of `state.json`.

Aliases live in the runner-root catalog or in the project's own
`LOCAL_ARTIFACTS/agent-runner.json`; a project selection replaces the root selection, so list
every alias the pipeline needs. Trusted commands execute in the project directory and inherit
the runner's environment. `local.properties` in each Android module removes the `ANDROID_HOME`
dependency for Gradle.

## Design goes through a subagent

Spawn with `subagent_type: "fork"` so the agent inherits this session's context instead of
re-exploring the repository. Hand it the measurements; do not make it re-derive them.

## The zero-findings bar

A task is done only when a **full pass by the coordinator turns up not a single finding**. Any
finding goes back to the same agent — `SendMessage`, so it keeps its context — and the loop
repeats. Verify independently: recompute the arithmetic, re-measure on the device, check every
cross-reference and every claim against the actual source. An agent's own report is not
evidence.

Report to the owner what checked out as well as what did not. A finding list with no account
of what was verified tells them nothing about how hard anyone looked.

## What the coordinator may touch

Measurements, captures, scans, reading files, running `just` checks, and writing local notes
under `LOCAL_ARTIFACTS/`. Restoring a tree a delegate left dirty. Staging and committing once
the owner has asked for a commit.

Not: production code, generated output, locked design documents, or review art.
