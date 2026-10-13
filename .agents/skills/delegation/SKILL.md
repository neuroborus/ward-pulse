---
name: delegation
description: WardPulse delegation contract — who does the work and who checks it. Use before writing any production code, editing a generator, changing a locked design baseline, or building a mock. Covers subagent design loops, Agent Runner pipelines, the zero-findings bar, and what the coordinating session may and may not touch itself.
---

# Delegation — WardPulse

Neither the coordinating session nor a standalone subagent implements code outside Agent
Runner. Design is delegated to a subagent; the coordinator verifies the result independently.
This is the owner's standing instruction, clarified 2026-10-13.

## Who does what

| Work | Owner | Coordinator's job |
| --- | --- | --- |
| Design: locked baselines, visual language, mocks, review art | A subagent | Verify to zero findings |
| Code: source, tests, schemas, build/tool scripts, generator source | Agent Runner execution and independent review steps | Verify to zero findings |
| Documentation and workflow prose | A delegated subagent | Review the scoped prose change |
| Measurement, device capture, reading sources, running checks | Coordinator | — |
| Deciding what to build | Owner | Put the choice in front of them |

A mock, visual asset or locked design baseline is design. Any code needed to realize it,
including a generator change, goes through Agent Runner. An implementation patch or runnable
helper remains code even when placed in Markdown or `LOCAL_ARTIFACTS/`.

## Code goes through the runner

Use `plan-authoring` followed by `plan-execution` by default. Code must be authored by an actual
Agent Runner code-producing execution step and pass the pipeline's independent review steps;
an approved plan or an author's self-review is not execution or independent review. Outside
Runner, supply requirements, measurements, findings and acceptance criteria, not a prewritten
implementation patch for Runner merely to apply. Subagents may coordinate, operate, read and
review Runner work, but may not implement it independently.

Choose supported pipelines and worker steps by their current capabilities, not just their
names. `polishing` finalizes and stages an existing change set without committing; do not
assume it replaces implementation from scratch. Standing owner authorization dated 2026-10-13
permits Runner execution to commit within the approved task scope after its required reviews
and checks, unless a task-specific instruction forbids it. Verify the execution route's commit
behaviour before starting; do not invent a no-commit mode. If the task forbids commits and no
supported noncommitting route fits, report that conflict and continue independent authorized
work rather than implement by hand.

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

## When a delegate cannot run the step

Blocked code stays with Agent Runner. Sandbox, network or tool denial, a small change, speed,
or an automatic-commit conflict never permits implementation by the coordinator or a standalone
subagent. Recover through a supported Runner route, including the documented CLI when
appropriate, without changing frozen run configuration. Report any remaining incompatibility
and continue independent authorized work.

Walls this repository has hit:

- **`spawnSync python3` is denied (`EPERM`)**, so `just render-designs` can never finish inside
  a runner step — `tools/render-watch-ring-designs.mjs` shells out to python3 and Pillow in
  `assertLabelsFit`. Trusted checks execute in a different environment where python3 works,
  which is why `just check-designs` passes as a gate while the generator behind it cannot be
  run as work.
- **Sockets are denied**, so Gradle never starts: `just check-wear`, `just check-watchface`.
- **No network**, so a recipe that fetches needs a pinned artifact or it is the owner's.

A gate that cannot start is reported through the environment-blocker path. Necessary host
checks and captures may run outside Runner; that permission does not transfer code authorship.

## Design goes through a subagent

Spawn with `fork_turns: "all"` so the agent inherits this session's context instead of
re-exploring the repository. Hand it the measurements; do not make it re-derive them.

## The zero-findings bar

A task is done only when a **full independent pass by the coordinator turns up not a single
finding**. Return code findings to Runner for fixes through its execution/review workflow;
return design findings to the same design subagent so it keeps its context. After the last
fix, repeat the whole final pass, not only the previously failing part. Verify independently:
recompute the arithmetic, re-measure on the device, check every cross-reference and every claim
against the actual source. An author's own report is not independent evidence.

Report to the owner what checked out as well as what did not. A finding list with no account
of what was verified tells them nothing about how hard anyone looked.

## Do not stop

The owner hands over a **region of work**, not one task, and expects to come back after a day
or two to finished work. Standing instruction, 2026-10-11. So:

- Finishing one stream is not the end of the turn. Pick up the next open item and keep going.
- A delegate running in the background is not a reason to idle — scope the next stream, take
  the measurements the next delegate will need, run the owner's host checks.
- Do not stop to ask what to do next while anything surfaced is still open. Decide, act, and
  report the decision. Stop only when the region is actually finished, when a choice is
  genuinely the owner's to make and nothing else can proceed without it, or when continuing
  would need a credential or a device the session does not have.
- Keep a list of what is open — in `LOCAL_ARTIFACTS/` — so a long session always has a next
  move. The list is working state, never a technical-debt register in the repository.

## What the coordinator may touch

Measurements, captures, scans, reading files, running existing operational commands and checks,
and writing local notes under `LOCAL_ARTIFACTS/`. Creating or changing an implementation,
helper or test script is code, not an operational command. Staging reviewed, scoped changes is
permitted under finalization; manual coordinator commits require the owner's explicit request.

Not: production code, generated output, locked design documents, or review art.

Read-only generator drift checks are permitted. Verification may run unchanged generators in a
throwaway clone without rewriting canonical tracked files. Runtime exports in the canonical
worktree belong to the owning Runner execution; a design subagent may regenerate design
review/mock art with unchanged tools. Generator source edits remain Runner-only. The coordinator
never authors a committed code or design byte.
