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
| Documentation and workflow prose | A delegated subagent | Verify to zero findings |
| Measurement, device capture, reading sources, running checks | Coordinator | — |
| Deciding what to build | Owner | Put the choice in front of them |

A mock, visual asset or locked design baseline is design. Any code needed to realize it,
including a generator change, goes through Agent Runner. An implementation patch or runnable
helper remains code even when placed in Markdown or `LOCAL_ARTIFACTS/`.

## Code goes through the runner

Before choosing or operating a Runner route, read the complete
[Runner operation contract](references/runner-operation.md). It preserves actual execution
and independent review, default pipelines, commit boundaries, explicit Native/HOST gates,
frozen configuration, backend-upgrade recovery and command-alias ownership.
Outside Runner supply requirements, measurements, findings and acceptance criteria, never
a prewritten implementation patch or a standalone code fallback.

## When a delegate cannot run the step

Blocked code stays with Agent Runner. Sandbox, network or tool denial, a small change, speed,
or an automatic-commit conflict never permits implementation by the coordinator or a standalone
subagent. Recover through a supported Runner route, including the documented CLI when
appropriate, without changing frozen run configuration. Report any remaining incompatibility
and continue independent authorized work.

Read the [observed environment limits](references/runner-operation.md#observed-environment-limits)
before classifying a blocker. Report gates that cannot start through the environment-blocker
path. Necessary host checks and captures do not transfer code authorship.

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
permitted under finalization; coordinator commits follow the standing authorization in
[AGENTS.md](../../../AGENTS.md#working-agreements) and [finalization](../finalization/SKILL.md#7-staging-and-commit-boundary).

Not: production code, generated output, locked design documents, or review art.

Read-only generator drift checks are permitted. Verification may run unchanged generators in a
throwaway clone without rewriting canonical tracked files. Runtime exports in the canonical
worktree belong to the owning Runner execution; a design subagent may regenerate design
review/mock art with unchanged tools. Generator source edits remain Runner-only. The coordinator
never authors a committed code or design byte.
