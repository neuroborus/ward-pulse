# Runner operation contract

Read completely before choosing or operating a Runner route from [delegation](../SKILL.md).

## Actual execution and checks

Use `plan-authoring` followed by `plan-execution` by default. Code must be authored by an actual
Agent Runner code-producing execution step and pass the pipeline's independent review steps;
an approved plan or an author's self-review is not execution or independent review. Outside
Runner, supply requirements, measurements, findings and acceptance criteria, not a prewritten
implementation patch for Runner merely to apply. Subagents may coordinate, operate, read and
review Runner work, but may not implement it independently.

Choose supported pipelines and worker steps by their current capabilities, not just their
names. `polishing` finalizes and stages an existing change set without committing; do not
assume it replaces implementation from scratch. Commit authorization is defined in
[AGENTS.md](../../../../AGENTS.md#working-agreements). A stage-only result can be followed by a
separate authorized coordinator commit. Verify the execution route's commit behaviour before
starting; do not invent a no-commit mode. If the task forbids commits and no supported
noncommitting route fits, report that conflict and continue independent authorized work
rather than implement by hand.

**Who runs which check is settled in
[agent-runner.md](../../finalization/agent-runner.md).** It carries the division between what
a step proves inside its sandbox and what the owner runs on the host, with reasons and dates.
Read it before scoping gates; do not duplicate or re-derive that division per task.

That file is reached by reference, not by configuration. The runner's `finalization` setting
accepts only `auto`, `none`, or a path ending in `/SKILL.md`, so it stays at `auto` and the step
loads `.agents/skills/finalization/SKILL.md`. **A task's gates section is what carries the
division to the step**, and it is authoritative for that step — so every runner task names the
required checks explicitly, says which ones the owner runs afterwards, and points at
`agent-runner.md` for the reasoning.

## Frozen configuration and backend recovery

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

## Observed environment limits

- **`spawnSync python3` is denied (`EPERM`)**, so `just render-designs` can never finish inside
  a runner step — `tools/render-watch-ring-designs.mjs` shells out to python3 and Pillow in
  `assertLabelsFit`. Trusted checks execute in a different environment where python3 works,
  which is why `just check-designs` passes as a gate while the generator behind it cannot be
  run as work.
- **Sockets are denied**, so Gradle never starts: `just check-wear`, `just check-watchface`.
- **No network**, so a recipe that fetches needs a pinned artifact or it is the owner's.

A gate that cannot start is reported through the environment-blocker path. Necessary host
checks and captures may run outside Runner; that permission does not transfer code authorship.
