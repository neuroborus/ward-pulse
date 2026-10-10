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

Two things this repository has already learned the hard way:

- **Trusted-check configuration is frozen at run start.** Editing
  `LOCAL_ARTIFACTS/agent-runner.json` while a run exists leaves that run unable to resume *and*
  unable to cancel — the protected-input guard refuses both. Prepare the selection before
  starting, never during.
- **The runner cannot grant network or a device.** Gradle, npm and the WFF validator all need
  the network; `adb` needs the emulator. A worker that declares them reports `unsupported`, and
  no configuration fixes that. Scope the runner's required checks to what runs inside its
  sandbox, and state plainly in `task.md` that the host checks and any device acceptance belong
  to the operator, performed after the run. That is correct scoping, not a weakened gate.

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
