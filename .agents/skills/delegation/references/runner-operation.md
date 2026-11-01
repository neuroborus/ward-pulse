# Runner operation contract

Read completely before choosing or operating a Runner route from [delegation](../SKILL.md).
Use [planning research](planning-research.md) to supply primary evidence and require a concrete repair choice during authoring.

## Actual execution and checks

Use `plan-authoring` followed by `plan-execution` by default. Code must be authored by an actual
Agent Runner code-producing execution step and pass the [owner-selected mode's](owner-selected-mode.md) required verification;
an approved plan or self-review is not code-producing execution or independent review. Outside
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

Until the owner changes the [2026-10-31 direction](owner-selected-mode.md), explicitly select `lazy` for every fresh `plan-authoring`, `plan-execution` and `polishing` run.
Verify the resolved mode; defaults are insufficient. Lazy self-review/Worker confirmation is not independent Reviewer evidence.
Use a supported stop on mismatch; preserve required checks and the coordinator's full independent ZERO.

Before a fresh start, reconcile one self-contained role-facing task/context against the current scoped Native
catalogue and changed guarantees. Identify its complete Runner Native `requiredChecks` inventory separately
from mandatory post-DONE HOST obligations; historical inventories are provenance, not competing catalogues.
The discovery catalogue is the union of Native commands applicable somewhere in the complete canonical plan, not all repository recipes; per-step assignment follows separately. Every selected command enters discovery and needs that global relevance; remove unrelated selections only before the fresh run. Unused definitions are not selections.
Inspect the FIRST role's published discovery `requiredChecks` immediately (`plan-execution`: `bootstrapProgress.worker.work.discovery.requiredChecks`, before `workerValidation`). Use a supported stop/reconciliation for an admitted-check/global-relevance mismatch; never treat extra HOST checks as informational or wait for merge/writable work.
For `plan-execution`, independently verify merged `validationSchedule.commands` against the admitted complete-plan Native union and resolve every step's command-index mapping against that step's admitted commands before accepting the schedule. Compare `pipelineState.requiredChecks` with the current step's resolved subset before accepting it, not with the complete-plan union. Compare exact command identities, not local C-IDs, which may be renumbered between discovery and steps. Preserve every admitted check: missing/extra commands or incorrect step mappings require supported stop/reconciliation. Apply this domain distinction to other routes only when they expose those domains; do not assume these `plan-execution` fields exist in authoring or another route.
Put read-only discovery versus workspace-write FINALIZE and real extra-authority needs in that task/context;
local operator guidance is not injected. Report genuine Native needs truthfully, never force empty reports.
A check assigned solely to HOST stays mandatory outside Native inventory/capability/environment-blocker
reports; an unselected HOST command does not acquire Native applicability merely because it is mandatory.
Keep mandatory HOST acceptance after whole DONE, run-owned process retirement and fresh separate
quiescent ownership; if the route used a foreground owning CLI, also require its actual exit.
HOST is not a Native check or Native-commit prerequisite. Preserve every scope-appropriate gate.

Bind managed controllers by `/proc` executable identity, the pinned Runner entry and exact
project/run arguments appropriate to their supported route; Node can expose `comm=MainThread`.
Revalidate PID + startTicks before comparisons; name/CWD alone or an empty `node`/`nodejs`
comm-filter result proves neither ownership nor retirement. Keep the census scoped,
including separately tracked owned descendants. An unreadable known or evidenced in-scope
identity leaves retirement unresolved; unrelated unreadable processes do not create a global
blocker. Public DONE or CPU/I/O activity alone proves neither owned-process exit nor semantic
progress/command success. Record match results/hashes instead of raw argv, environment,
prompts or authentication.

## Observed environment limits

- A historical `spawnSync python3` denial (`EPERM`) blocked `assertLabelsFit` in
  `tools/render-watch-ring-designs.mjs` inside that Runner executor; a separate trusted
  `just check-designs` environment ran Python/Pillow successfully. Current `assertLabelsFit`
  uses asynchronous `runFile` (`execFile`), not `spawnSync`: evaluate it in the actual executor.
  Neither fact proves current Native generation availability/PASS; preserve the task's Native/HOST division and authorship.
- **Sockets are denied**, so Gradle never starts: `just check-wear`, `just check-watchface`.
- **No network**, so a recipe that fetches needs a pinned artifact or it is the owner's.

A gate that cannot start is reported through the environment-blocker path. Necessary host
checks and captures may run outside Runner; that permission does not transfer code authorship.
